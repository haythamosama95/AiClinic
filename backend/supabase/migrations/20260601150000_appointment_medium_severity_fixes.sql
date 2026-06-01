-- Medium-severity appointment fixes:
-- #8  Permission check before transition validation in update_appointment_status
-- #11 appointments.read permission for read-only listing
-- #6  reschedule_appointment response includes status and type

-- -----------------------------------------------------------------------------
-- appointments.read permission seed
-- -----------------------------------------------------------------------------
INSERT INTO public.roles_permissions (role, permission_key, is_granted)
VALUES
  ('owner', 'appointments.read', true),
  ('administrator', 'appointments.read', true),
  ('doctor', 'appointments.read', true),
  ('receptionist', 'appointments.read', true),
  ('lab_staff', 'appointments.read', true)
ON CONFLICT (role, permission_key) DO UPDATE
SET is_granted = EXCLUDED.is_granted,
    is_deleted = false;

-- -----------------------------------------------------------------------------
-- assert_appointment_access: create OR cancel OR read
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.assert_appointment_access()
RETURNS public.staff_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = auth.uid()
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF v_staff.is_bootstrap_admin AND NOT auth_internal.organization_exists() THEN
    RETURN v_staff;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    WHERE rp.role = v_staff.role
      AND rp.permission_key IN ('appointments.create', 'appointments.cancel', 'appointments.read')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN v_staff;
END;
$$;

-- -----------------------------------------------------------------------------
-- update_appointment_status: permission before transition matrix
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

-- -----------------------------------------------------------------------------
-- reschedule_appointment: include status and type in response
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.reschedule_appointment(
  p_appointment_id uuid,
  p_start_time timestamptz,
  p_duration_minutes int DEFAULT NULL,
  p_end_time timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_appt public.appointments%ROWTYPE;
  v_duration int;
  v_start timestamptz;
  v_end timestamptz;
BEGIN
  PERFORM auth_internal.assert_permission('appointments.create');

  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  IF v_appt.status <> 'scheduled' OR v_appt.type <> 'planned' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only scheduled planned appointments can be rescheduled.');
  END IF;

  IF p_start_time IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Start time is required.');
  END IF;

  v_duration := COALESCE(p_duration_minutes, auth_internal.resolve_appointment_default_duration(v_appt.branch_id));

  BEGIN
    PERFORM auth_internal.assert_appointment_duration_bounds(v_duration);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Duration must be between 5 and 240 minutes.');
  END;

  SELECT rt.resolved_start, rt.resolved_end
  INTO v_start, v_end
  FROM auth_internal.resolve_appointment_times(p_start_time, v_duration, p_end_time) rt;

  IF NOT auth_internal.appointment_within_branch_working_hours(v_appt.branch_id, v_start, v_end) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Appointment must be within branch working hours.');
  END IF;

  IF auth_internal.appointment_has_overlap(v_appt.branch_id, v_appt.doctor_id, v_start, v_end, v_appt.id) THEN
    RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment.');
  END IF;

  IF auth_internal.patient_has_same_day_appointment(v_appt.branch_id, v_appt.patient_id, v_start, v_appt.id) THEN
    RETURN public.rpc_error(
      'PATIENT_ALREADY_BOOKED_SAME_DAY',
      'This patient already has an appointment on the same day.'
    );
  END IF;

  UPDATE public.appointments a
  SET
    start_time = v_start,
    end_time = v_end,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.reschedule',
    'appointments',
    v_appt.id,
    jsonb_build_object('start_time', v_start, 'end_time', v_end)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'appointment_id', v_appt.id,
      'start_time', v_start,
      'end_time', v_end,
      'status', v_appt.status::text,
      'type', v_appt.type::text
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to reschedule appointments.');
    END IF;
    RAISE;
END;
$$;
