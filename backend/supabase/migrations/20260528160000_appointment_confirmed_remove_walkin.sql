-- V1-4: add phone-confirmation status; remove walk-in booking path.

ALTER TYPE public.appointment_status ADD VALUE IF NOT EXISTS 'confirmed';

UPDATE public.appointments
SET type = 'planned'
WHERE type = 'walk_in';

CREATE OR REPLACE FUNCTION auth_internal.create_appointment(
  p_branch_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_type text,
  p_start_time timestamptz DEFAULT NULL,
  p_duration_minutes int DEFAULT NULL,
  p_end_time timestamptz DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_patient public.patients%ROWTYPE;
  v_type public.appointment_type;
  v_status public.appointment_status;
  v_duration int;
  v_start timestamptz;
  v_end timestamptz;
  v_appointment_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('appointments.create');
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);

  IF p_doctor_id IS NOT NULL THEN
    PERFORM auth_internal.assert_appointment_doctor(p_doctor_id, p_branch_id);
  END IF;

  BEGIN
    v_patient := auth_internal.assert_org_patient(p_patient_id, false);
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

  IF p_notes IS NOT NULL AND length(trim(p_notes)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Notes must be 2000 characters or fewer.');
  END IF;

  BEGIN
    v_type := lower(trim(p_type))::public.appointment_type;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Type must be planned.');
  END;

  IF v_type <> 'planned' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Walk-in appointments are no longer supported. Book a planned appointment.');
  END IF;

  v_duration := COALESCE(p_duration_minutes, auth_internal.resolve_appointment_default_duration(p_branch_id));

  BEGIN
    PERFORM auth_internal.assert_appointment_duration_bounds(v_duration);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Duration must be between 5 and 240 minutes.');
  END;

  IF p_start_time IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Start time is required for planned appointments.');
  END IF;

  SELECT rt.resolved_start, rt.resolved_end
  INTO v_start, v_end
  FROM auth_internal.resolve_appointment_times(p_start_time, v_duration, p_end_time) rt;

  IF NOT auth_internal.appointment_within_branch_working_hours(p_branch_id, v_start, v_end) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Appointment must be within branch working hours.');
  END IF;

  IF auth_internal.appointment_has_overlap(p_branch_id, p_doctor_id, v_start, v_end, NULL) THEN
    RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment.');
  END IF;

  v_status := 'scheduled';

  IF auth_internal.patient_has_same_day_appointment(p_branch_id, p_patient_id, v_start, NULL) THEN
    RETURN public.rpc_error(
      'PATIENT_ALREADY_BOOKED_SAME_DAY',
      'This patient already has an appointment on the same day.'
    );
  END IF;

  INSERT INTO public.appointments (
    branch_id,
    patient_id,
    doctor_id,
    start_time,
    end_time,
    type,
    status,
    queue_number,
    notes,
    created_by,
    updated_by
  )
  VALUES (
    p_branch_id,
    p_patient_id,
    p_doctor_id,
    v_start,
    v_end,
    v_type,
    v_status,
    NULL,
    NULLIF(trim(COALESCE(p_notes, '')), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_appointment_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.create',
    'appointments',
    v_appointment_id,
    jsonb_build_object(
      'branch_id', p_branch_id,
      'patient_id', p_patient_id,
      'doctor_id', p_doctor_id,
      'type', v_type::text,
      'status', v_status::text,
      'start_time', v_start,
      'end_time', v_end
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'appointment_id', v_appointment_id,
      'start_time', v_start,
      'end_time', v_end,
      'status', v_status::text,
      'type', v_type::text
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create appointments.');
    END IF;
    IF SQLERRM = 'INVALID_DOCTOR' THEN
      RETURN public.rpc_error('INVALID_DOCTOR', 'Doctor is not valid for this branch.');
    END IF;
    IF SQLERRM = 'INVALID_BRANCH' THEN
      RETURN public.rpc_error('INVALID_BRANCH', 'Branch is not valid for this appointment.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.cancel_appointment(
  p_appointment_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_appt public.appointments%ROWTYPE;
BEGIN
  PERFORM auth_internal.assert_permission('appointments.cancel');

  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  IF v_appt.status NOT IN ('scheduled', 'confirmed', 'checked_in') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only scheduled, confirmed, or checked-in appointments can be cancelled.');
  END IF;

  IF p_reason IS NOT NULL AND length(trim(p_reason)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Cancel reason must be 2000 characters or fewer.');
  END IF;

  UPDATE public.appointments a
  SET
    status = 'cancelled',
    cancel_reason = NULLIF(trim(COALESCE(p_reason, '')), ''),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.cancel',
    'appointments',
    v_appt.id,
    jsonb_build_object('status', 'cancelled', 'cancel_reason', NULLIF(trim(COALESCE(p_reason, '')), ''))
  );

  RETURN public.rpc_success(jsonb_build_object('appointment_id', v_appt.id, 'status', 'cancelled'));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to cancel appointments.');
    END IF;
    RAISE;
END;
$$;

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

  v_allowed := CASE v_appt.status
    WHEN 'scheduled' THEN v_new IN ('confirmed', 'cancelled', 'no_show')
    WHEN 'confirmed' THEN v_new IN ('checked_in', 'cancelled', 'no_show')
    WHEN 'checked_in' THEN v_new IN ('in_progress', 'cancelled', 'no_show')
    WHEN 'in_progress' THEN v_new = 'completed'
    ELSE false
  END;

  IF NOT v_allowed THEN
    RETURN public.rpc_error('INVALID_TRANSITION', 'This status change is not allowed.');
  END IF;

  IF v_new IN ('cancelled', 'no_show') THEN
    PERFORM auth_internal.assert_permission('appointments.cancel');
  ELSE
    PERFORM auth_internal.assert_permission('appointments.create');
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
    jsonb_build_object('old_status', v_appt.status::text, 'new_status', v_new::text)
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

DROP FUNCTION IF EXISTS auth_internal.find_walk_in_slot(uuid, uuid, int);
