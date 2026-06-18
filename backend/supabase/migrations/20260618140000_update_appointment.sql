-- Full appointment edit for non-terminal planned appointments (V1-4 detail edit flow).
-- Scheduled: patient, doctor, time, and notes may change.
-- Confirmed / checked_in / in_progress: only doctor and notes may change.

CREATE OR REPLACE FUNCTION auth_internal.update_appointment(
  p_appointment_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_start_time timestamptz,
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
  v_appt public.appointments%ROWTYPE;
  v_patient public.patients%ROWTYPE;
  v_duration int;
  v_start timestamptz;
  v_end timestamptz;
  v_effective_doctor_id uuid;
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

  IF v_appt.type <> 'planned' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only planned appointments can be edited.');
  END IF;

  IF v_appt.status IN ('completed', 'cancelled', 'no_show') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'This appointment cannot be edited.');
  END IF;

  IF p_patient_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Patient is required.');
  END IF;

  IF p_start_time IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Start time is required.');
  END IF;

  IF p_doctor_id IS NOT NULL THEN
    PERFORM auth_internal.assert_appointment_doctor(p_doctor_id, v_appt.branch_id);
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

  IF v_appt.status <> 'scheduled' THEN
    IF p_patient_id <> v_appt.patient_id THEN
      RETURN public.rpc_error(
        'INVALID_INPUT',
        'Patient cannot be changed after the appointment is confirmed.'
      );
    END IF;

    IF v_start <> v_appt.start_time OR v_end <> v_appt.end_time THEN
      RETURN public.rpc_error(
        'INVALID_INPUT',
        'Time cannot be changed after the appointment is confirmed. Cancel and re-book instead.'
      );
    END IF;
  ELSE
    IF NOT auth_internal.appointment_within_branch_working_hours(v_appt.branch_id, v_start, v_end) THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Appointment must be within branch working hours.');
    END IF;

    IF auth_internal.patient_has_same_day_appointment(v_appt.branch_id, p_patient_id, v_start, v_appt.id) THEN
      RETURN public.rpc_error(
        'PATIENT_ALREADY_BOOKED_SAME_DAY',
        'This patient already has an appointment on the same day.'
      );
    END IF;
  END IF;

  v_effective_doctor_id := p_doctor_id;

  IF auth_internal.appointment_has_overlap(v_appt.branch_id, v_effective_doctor_id, v_start, v_end, v_appt.id) THEN
    RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment.');
  END IF;

  UPDATE public.appointments a
  SET
    patient_id = p_patient_id,
    doctor_id = p_doctor_id,
    start_time = v_start,
    end_time = v_end,
    notes = NULLIF(trim(COALESCE(p_notes, '')), ''),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.update',
    'appointments',
    v_appt.id,
    jsonb_build_object(
      'patient_id', p_patient_id,
      'doctor_id', p_doctor_id,
      'start_time', v_start,
      'end_time', v_end
    )
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
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update appointments.');
    END IF;
    IF SQLERRM = 'INVALID_DOCTOR' THEN
      RETURN public.rpc_error('INVALID_DOCTOR', 'Doctor is not valid for this branch.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_appointment(
  p_appointment_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_start_time timestamptz,
  p_duration_minutes int DEFAULT NULL,
  p_end_time timestamptz DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_appointment(
    p_appointment_id,
    p_patient_id,
    p_doctor_id,
    p_start_time,
    p_duration_minutes,
    p_end_time,
    p_notes
  );
$$;

GRANT EXECUTE ON FUNCTION auth_internal.update_appointment(
  uuid, uuid, uuid, timestamptz, int, timestamptz, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.update_appointment(
  uuid, uuid, uuid, timestamptz, int, timestamptz, text
) TO authenticated;
