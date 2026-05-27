-- V1-4: Allow planned appointments without an assigned doctor (walk-in still requires a doctor).

ALTER TABLE public.appointments
  ALTER COLUMN doctor_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION auth_internal.appointment_has_overlap(
  p_branch_id uuid,
  p_doctor_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_exclude_appointment_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p_doctor_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.appointments a
      WHERE a.branch_id = p_branch_id
        AND a.doctor_id = p_doctor_id
        AND a.is_deleted = false
        AND a.status NOT IN ('cancelled', 'no_show')
        AND (p_exclude_appointment_id IS NULL OR a.id <> p_exclude_appointment_id)
        AND a.start_time < p_end_time
        AND a.end_time > p_start_time
    );
$$;

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
    IF p_doctor_id IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'A doctor is required for walk-in appointments.');
    END IF;

    SELECT s.slot_start, s.slot_end
    INTO v_start, v_end
    FROM auth_internal.find_walk_in_slot(p_branch_id, p_doctor_id, v_duration) s
    LIMIT 1;

    IF v_start IS NULL THEN
      RETURN public.rpc_error('NO_SLOT_AVAILABLE', 'No walk-in slot is available today for this doctor and duration.');
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

  IF v_appt.doctor_id IS NOT NULL
     AND auth_internal.appointment_has_overlap(v_appt.branch_id, v_appt.doctor_id, v_start, v_end, v_appt.id) THEN
    RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment for the doctor.');
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

CREATE OR REPLACE FUNCTION auth_internal.list_appointments(
  p_branch_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_doctor_id uuid DEFAULT NULL,
  p_statuses text[] DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items jsonb;
BEGIN
  PERFORM auth_internal.assert_appointment_access();
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);

  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from THEN
    RETURN public.rpc_error('INVALID_INPUT', 'A valid time range is required.');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sub.id,
        'patient_id', sub.patient_id,
        'patient_name', sub.patient_name,
        'doctor_id', sub.doctor_id,
        'doctor_name', sub.doctor_name,
        'start_time', sub.start_time,
        'end_time', sub.end_time,
        'type', sub.type,
        'status', sub.status
      )
      ORDER BY sub.start_time
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      a.id,
      a.patient_id,
      p.full_name AS patient_name,
      a.doctor_id,
      sm.full_name AS doctor_name,
      a.start_time,
      a.end_time,
      a.type::text AS type,
      a.status::text AS status
    FROM public.appointments a
    JOIN public.patients p ON p.id = a.patient_id
    LEFT JOIN public.staff_members sm ON sm.id = a.doctor_id
    WHERE a.branch_id = p_branch_id
      AND a.is_deleted = false
      AND a.start_time >= p_from
      AND a.start_time < p_to
      AND (p_doctor_id IS NULL OR a.doctor_id = p_doctor_id)
      AND (
        p_statuses IS NULL
        OR cardinality(p_statuses) = 0
        OR a.status::text = ANY (p_statuses)
      )
    ORDER BY a.start_time
  ) sub;

  RETURN public.rpc_success(jsonb_build_object('items', v_items));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('FORBIDDEN', 'INVALID_BRANCH') THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list appointments.');
      END IF;
      RETURN public.rpc_error('INVALID_INPUT', 'Branch is not valid for this session.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_appointment(
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
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_appointment(
    p_branch_id,
    p_patient_id,
    p_doctor_id,
    p_type,
    p_start_time,
    p_duration_minutes,
    p_end_time,
    p_notes
  );
$$;
