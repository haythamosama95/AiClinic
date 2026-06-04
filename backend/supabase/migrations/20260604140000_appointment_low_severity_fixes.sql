-- Low-severity appointment fixes:
-- #12 get_appointment_settings includes branch working_schedule
-- #15 Standardize cancel/status audit payloads

-- -----------------------------------------------------------------------------
-- get_appointment_settings: include working_schedule
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.get_appointment_settings(p_branch_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_default int;
  v_schedule jsonb;
BEGIN
  PERFORM auth_internal.assert_appointment_access();
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);

  SELECT b.working_schedule
  INTO v_schedule
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.is_deleted = false;

  v_default := auth_internal.resolve_appointment_default_duration(p_branch_id);

  RETURN public.rpc_success(
    jsonb_build_object(
      'default_duration_minutes', v_default,
      'min_duration_minutes', 5,
      'max_duration_minutes', 240,
      'working_schedule', v_schedule
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('FORBIDDEN', 'INVALID_BRANCH') THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view appointment settings.');
      END IF;
      RETURN public.rpc_error('INVALID_BRANCH', 'Branch is not valid for this session.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- cancel_appointment: standardized audit payload
-- -----------------------------------------------------------------------------
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
    jsonb_build_object(
      'appointment_id', v_appt.id,
      'branch_id', v_appt.branch_id,
      'patient_id', v_appt.patient_id,
      'doctor_id', v_appt.doctor_id,
      'old_status', v_appt.status::text,
      'new_status', 'cancelled',
      'cancel_reason', NULLIF(trim(COALESCE(p_reason, '')), '')
    )
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

-- -----------------------------------------------------------------------------
-- update_appointment_status: standardized audit payload (permission-first)
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
