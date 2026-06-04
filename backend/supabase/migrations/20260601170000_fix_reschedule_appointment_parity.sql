-- Align reschedule_appointment validation with create_appointment:
-- working hours, same-day patient limit, and branch-wide overlap (including doctor-less).

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
      'end_time', v_end
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
