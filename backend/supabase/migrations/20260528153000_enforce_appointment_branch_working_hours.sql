-- V1-4 hotfix: enforce branch working hours for planned and walk-in booking.

CREATE OR REPLACE FUNCTION auth_internal.appointment_within_branch_working_hours(
  p_branch_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_tz text;
  v_schedule jsonb;
  v_local_start timestamp;
  v_local_end timestamp;
  v_day_name text;
  v_day jsonb;
  v_is_working boolean;
  v_open time;
  v_close time;
BEGIN
  IF p_start_time IS NULL OR p_end_time IS NULL OR p_end_time <= p_start_time THEN
    RETURN false;
  END IF;

  SELECT
    COALESCE(NULLIF(trim(o.timezone), ''), 'UTC'),
    b.working_schedule
  INTO v_org_tz, v_schedule
  FROM public.branches b
  JOIN public.organizations o ON o.id = b.organization_id
  WHERE b.id = p_branch_id
    AND b.is_deleted = false
    AND b.is_active = true;

  IF v_schedule IS NULL THEN
    RETURN false;
  END IF;

  v_local_start := p_start_time AT TIME ZONE v_org_tz;
  v_local_end := p_end_time AT TIME ZONE v_org_tz;

  -- Appointment must stay inside one local day.
  IF v_local_start::date <> v_local_end::date THEN
    RETURN false;
  END IF;

  v_day_name := CASE extract(isodow FROM v_local_start)
    WHEN 1 THEN 'monday'
    WHEN 2 THEN 'tuesday'
    WHEN 3 THEN 'wednesday'
    WHEN 4 THEN 'thursday'
    WHEN 5 THEN 'friday'
    WHEN 6 THEN 'saturday'
    ELSE 'sunday'
  END;

  SELECT d.value
  INTO v_day
  FROM jsonb_array_elements(v_schedule -> 'days') AS d(value)
  WHERE lower(trim(COALESCE(d.value ->> 'day', ''))) = v_day_name
  LIMIT 1;

  IF v_day IS NULL THEN
    RETURN false;
  END IF;

  v_is_working := COALESCE((v_day ->> 'is_working_day')::boolean, false);
  IF NOT v_is_working THEN
    RETURN false;
  END IF;

  v_open := (v_day ->> 'open_time')::time;
  v_close := (v_day ->> 'close_time')::time;

  RETURN v_local_start::time >= v_open
    AND v_local_end::time <= v_close;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.find_walk_in_slot(
  p_branch_id uuid,
  p_doctor_id uuid,
  p_duration_minutes int
)
RETURNS TABLE (slot_start timestamptz, slot_end timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_tz text;
  v_schedule jsonb;
  v_local_now timestamp;
  v_local_day date;
  v_day_name text;
  v_day jsonb;
  v_open time;
  v_close time;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_cursor timestamptz;
  v_appt record;
BEGIN
  SELECT
    COALESCE(NULLIF(trim(o.timezone), ''), 'UTC'),
    b.working_schedule
  INTO v_org_tz, v_schedule
  FROM public.branches b
  JOIN public.organizations o ON o.id = b.organization_id
  WHERE b.id = p_branch_id;

  IF v_schedule IS NULL THEN
    RETURN;
  END IF;

  v_local_now := now() AT TIME ZONE v_org_tz;
  v_local_day := v_local_now::date;
  v_day_name := CASE extract(isodow FROM v_local_now)
    WHEN 1 THEN 'monday'
    WHEN 2 THEN 'tuesday'
    WHEN 3 THEN 'wednesday'
    WHEN 4 THEN 'thursday'
    WHEN 5 THEN 'friday'
    WHEN 6 THEN 'saturday'
    ELSE 'sunday'
  END;

  SELECT d.value
  INTO v_day
  FROM jsonb_array_elements(v_schedule -> 'days') AS d(value)
  WHERE lower(trim(COALESCE(d.value ->> 'day', ''))) = v_day_name
  LIMIT 1;

  IF v_day IS NULL OR NOT COALESCE((v_day ->> 'is_working_day')::boolean, false) THEN
    RETURN;
  END IF;

  v_open := (v_day ->> 'open_time')::time;
  v_close := (v_day ->> 'close_time')::time;
  v_day_start := ((v_local_day::timestamp + v_open) AT TIME ZONE v_org_tz);
  v_day_end := ((v_local_day::timestamp + v_close) AT TIME ZONE v_org_tz);
  v_cursor := greatest(now(), v_day_start);

  FOR v_appt IN
    SELECT a.start_time, a.end_time
    FROM public.appointments a
    WHERE a.branch_id = p_branch_id
      AND a.is_deleted = false
      AND a.status NOT IN ('cancelled', 'no_show')
      AND a.start_time >= v_day_start
      AND a.start_time < v_day_end
    ORDER BY a.start_time
  LOOP
    IF v_cursor + make_interval(mins => p_duration_minutes) <= v_appt.start_time
       AND auth_internal.appointment_within_branch_working_hours(
         p_branch_id,
         v_cursor,
         v_cursor + make_interval(mins => p_duration_minutes)
       )
       AND NOT auth_internal.appointment_has_overlap(
         p_branch_id, p_doctor_id, v_cursor, v_cursor + make_interval(mins => p_duration_minutes), NULL
       ) THEN
      slot_start := v_cursor;
      slot_end := v_cursor + make_interval(mins => p_duration_minutes);
      RETURN NEXT;
      RETURN;
    END IF;

    IF v_appt.end_time > v_cursor THEN
      v_cursor := v_appt.end_time;
    END IF;
  END LOOP;

  IF v_cursor + make_interval(mins => p_duration_minutes) <= v_day_end
     AND auth_internal.appointment_within_branch_working_hours(
       p_branch_id,
       v_cursor,
       v_cursor + make_interval(mins => p_duration_minutes)
     )
     AND NOT auth_internal.appointment_has_overlap(
       p_branch_id, p_doctor_id, v_cursor, v_cursor + make_interval(mins => p_duration_minutes), NULL
     ) THEN
    slot_start := v_cursor;
    slot_end := v_cursor + make_interval(mins => p_duration_minutes);
    RETURN NEXT;
  END IF;

  RETURN;
END;
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

    IF NOT auth_internal.appointment_within_branch_working_hours(p_branch_id, v_start, v_end) THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Appointment must be within branch working hours.');
    END IF;

    IF auth_internal.appointment_has_overlap(p_branch_id, p_doctor_id, v_start, v_end, NULL) THEN
      RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment.');
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
      RETURN public.rpc_error('NO_SLOT_AVAILABLE', 'No walk-in slot is available today for this duration.');
    END IF;

    v_status := 'checked_in';
  END IF;

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
