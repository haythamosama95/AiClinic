-- Enforce at most one in_progress appointment per doctor at a branch (unassigned
-- doctor_id shares a single slot). Applies to status RPC and visit create advance.

-- -----------------------------------------------------------------------------
-- auth_internal.doctor_has_in_progress_appointment
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.doctor_has_in_progress_appointment(
  p_branch_id uuid,
  p_doctor_id uuid,
  p_exclude_appointment_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.appointments a
    WHERE a.branch_id = p_branch_id
      AND a.status = 'in_progress'
      AND a.is_deleted = false
      AND a.id <> p_exclude_appointment_id
      AND (
        (p_doctor_id IS NULL AND a.doctor_id IS NULL)
        OR (p_doctor_id IS NOT NULL AND a.doctor_id = p_doctor_id)
      )
  );
$$;

-- -----------------------------------------------------------------------------
-- update_appointment_status: block second in_progress for same doctor
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_appointment_status(
  p_appointment_id uuid,
  p_new_status text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_appt public.appointments%ROWTYPE;
  v_new public.appointment_status;
  v_allowed boolean := false;
  v_org_tz text;
  v_appt_day date;
  v_today date;
BEGIN
  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  BEGIN
    v_new := lower(trim(p_new_status))::public.appointment_status;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Status is not valid.');
  END;

  IF v_new IN ('cancelled', 'no_show') THEN
    PERFORM auth_internal.assert_permission('appointments.cancel');
  ELSE
    PERFORM auth_internal.assert_permission('appointments.create');
  END IF;

  IF v_appt.status = 'in_progress' AND v_new = 'completed' THEN
    RETURN public.rpc_error(
      'VISIT_REQUIRED_FOR_COMPLETION',
      'Complete the visit documentation to finish this appointment.'
    );
  END IF;

  v_allowed := CASE v_appt.status
    WHEN 'scheduled' THEN v_new IN ('confirmed', 'cancelled', 'no_show')
    WHEN 'confirmed' THEN v_new IN ('checked_in', 'cancelled', 'no_show')
    WHEN 'checked_in' THEN v_new IN ('in_progress', 'cancelled', 'no_show')
    WHEN 'in_progress' THEN false
    ELSE false
  END;

  IF NOT v_allowed THEN
    RETURN public.rpc_error('INVALID_TRANSITION', 'This status change is not allowed.');
  END IF;

  IF v_new IN ('checked_in', 'in_progress', 'completed', 'no_show') THEN
    SELECT COALESCE(NULLIF(trim(o.timezone), ''), 'UTC')
    INTO v_org_tz
    FROM public.branches b
    JOIN public.organizations o ON o.id = b.organization_id
    WHERE b.id = v_appt.branch_id;

    v_appt_day := (v_appt.start_time AT TIME ZONE v_org_tz)::date;
    v_today := (now() AT TIME ZONE v_org_tz)::date;

    IF v_today < v_appt_day THEN
      RETURN public.rpc_error(
        'INVALID_TRANSITION',
        'This status change is only allowed on or after the appointment day.'
      );
    END IF;
  END IF;

  IF v_new = 'in_progress'
    AND auth_internal.doctor_has_in_progress_appointment(
      v_appt.branch_id,
      v_appt.doctor_id,
      v_appt.id
    ) THEN
    RETURN public.rpc_error(
      'DOCTOR_ALREADY_IN_PROGRESS',
      'This doctor already has a patient in progress. Complete that visit before starting another.'
    );
  END IF;

  UPDATE public.appointments a
  SET
    status = v_new,
    cancel_reason = a.cancel_reason,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.status',
    'appointments',
    v_appt.id,
    jsonb_build_object(
      'appointment_id', v_appt.id,
      'branch_id', v_appt.branch_id,
      'patient_id', v_appt.patient_id,
      'doctor_id', v_appt.doctor_id,
      'old_status', v_appt.status::text,
      'new_status', v_new::text
    )
  );

  RETURN public.rpc_success(jsonb_build_object('appointment_id', v_appt.id, 'status', v_new::text));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update appointment status.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- create_visit: block advance to in_progress when doctor already has one
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_visit(
  p_appointment_id uuid,
  p_doctor_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_appt public.appointments%ROWTYPE;
  v_patient public.patients%ROWTYPE;
  v_doctor_id uuid;
  v_visit_id uuid;
  v_visit_date date;
  v_advanced_appointment boolean := false;
BEGIN
  v_caller := auth_internal.assert_permission('visits.create');

  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  IF v_appt.status NOT IN ('checked_in', 'in_progress') THEN
    RETURN public.rpc_error(
      'APPOINTMENT_NOT_ELIGIBLE',
      'Visits can only be created from checked-in or in-progress appointments.'
    );
  END IF;

  BEGIN
    v_patient := auth_internal.assert_org_patient(v_appt.patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived.');
      END IF;
      RAISE;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.visits v
    WHERE v.appointment_id = p_appointment_id
      AND v.is_deleted = false
  ) THEN
    RETURN public.rpc_error('VISIT_ALREADY_EXISTS', 'A visit already exists for this appointment.');
  END IF;

  v_doctor_id := v_appt.doctor_id;
  IF v_doctor_id IS NULL THEN
    IF p_doctor_id IS NULL THEN
      RETURN public.rpc_error('DOCTOR_REQUIRED', 'A doctor must be selected for this appointment.');
    END IF;

    BEGIN
      PERFORM auth_internal.assert_appointment_doctor(p_doctor_id, v_appt.branch_id);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM = 'INVALID_DOCTOR' THEN
          RETURN public.rpc_error('INVALID_DOCTOR', 'Doctor is not valid for this branch.');
        END IF;
        RAISE;
    END;

    v_doctor_id := p_doctor_id;

    UPDATE public.appointments a
    SET
      doctor_id = v_doctor_id,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE a.id = v_appt.id;

    v_appt.doctor_id := v_doctor_id;
  END IF;

  v_visit_date := auth_internal.resolve_visit_date_from_appointment(v_appt.start_time, v_appt.branch_id);

  IF v_appt.status = 'checked_in' THEN
    IF auth_internal.doctor_has_in_progress_appointment(
      v_appt.branch_id,
      v_doctor_id,
      v_appt.id
    ) THEN
      RETURN public.rpc_error(
        'DOCTOR_ALREADY_IN_PROGRESS',
        'This doctor already has a patient in progress. Complete that visit before starting another.'
      );
    END IF;

    UPDATE public.appointments a
    SET
      status = 'in_progress',
      updated_at = now(),
      updated_by = auth.uid()
    WHERE a.id = v_appt.id;

    v_advanced_appointment := true;
  END IF;

  INSERT INTO public.visits (
    branch_id,
    appointment_id,
    patient_id,
    doctor_id,
    visit_date,
    status,
    created_by,
    updated_by
  )
  VALUES (
    v_appt.branch_id,
    v_appt.id,
    v_appt.patient_id,
    v_doctor_id,
    v_visit_date,
    'in_progress',
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_visit_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'visit.create',
    'visits',
    v_visit_id,
    jsonb_build_object(
      'visit_id', v_visit_id,
      'appointment_id', v_appt.id,
      'patient_id', v_appt.patient_id,
      'doctor_id', v_doctor_id,
      'visit_date', v_visit_date
    )
  );

  IF v_advanced_appointment THEN
    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
    VALUES (
      auth.uid(),
      public.jwt_organization_id(),
      'appointment.status_in_progress',
      'appointments',
      v_appt.id,
      jsonb_build_object('old_status', 'checked_in', 'new_status', 'in_progress')
    );
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'visit_id', v_visit_id,
      'appointment_id', v_appt.id,
      'status', 'in_progress',
      'visit_date', v_visit_date
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create visits.');
    END IF;
    RAISE;
END;
$$;
