-- V1-4: Make walk-in doctor assignment optional (same as planned).

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
  v_caller public.staff_members%ROWTYPE;
  v_patient public.patients%ROWTYPE;
  v_type public.appointment_type;
  v_status public.appointment_status;
  v_duration int;
  v_start timestamptz;
  v_end timestamptz;
  v_slot record;
  v_appointment_id uuid;
BEGIN
  v_caller := auth_internal.assert_permission('appointments.create');
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
      RETURN public.rpc_error('INVALID_INPUT', 'Type must be planned or walk_in.');
  END;

  v_duration := COALESCE(p_duration_minutes, auth_internal.resolve_appointment_default_duration(p_branch_id));

  BEGIN
    PERFORM auth_internal.assert_appointment_duration_bounds(v_duration);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Duration must be between 5 and 240 minutes.');
  END;

  IF v_type = 'planned' THEN
    IF p_start_time IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Start time is required for planned appointments.');
    END IF;

    SELECT rt.resolved_start, rt.resolved_end
    INTO v_start, v_end
    FROM auth_internal.resolve_appointment_times(p_start_time, v_duration, p_end_time) rt;

    IF p_doctor_id IS NOT NULL
       AND auth_internal.appointment_has_overlap(p_branch_id, p_doctor_id, v_start, v_end, NULL) THEN
      RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment for the doctor.');
    END IF;

    v_status := 'scheduled';
  ELSE
    IF p_doctor_id IS NOT NULL THEN
      SELECT s.slot_start, s.slot_end
      INTO v_start, v_end
      FROM auth_internal.find_walk_in_slot(p_branch_id, p_doctor_id, v_duration) s
      LIMIT 1;

      IF v_start IS NULL THEN
        RETURN public.rpc_error(
          'NO_SLOT_AVAILABLE',
          'No walk-in slot is available today for this branch, doctor, and duration.'
        );
      END IF;
    ELSE
      SELECT rt.resolved_start, rt.resolved_end
      INTO v_start, v_end
      FROM auth_internal.resolve_appointment_times(now(), v_duration, NULL) rt;
    END IF;

    v_status := 'checked_in';
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
