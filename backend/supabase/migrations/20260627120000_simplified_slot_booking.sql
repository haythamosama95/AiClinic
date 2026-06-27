-- 011 Simplified Slot Booking: restore per-doctor overlap and add slot query RPC.
--
-- Supersedes branch-wide slot uniqueness in 20260528150500_appointment_slot_and_patient_day_conflicts.sql.
-- Alternate-doctor booking requires per-doctor conflict detection so two doctors may share
-- the same branch clock time while the same doctor cannot double-book.

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

CREATE OR REPLACE FUNCTION auth_internal.get_simplified_booking_slots(
  p_branch_id uuid,
  p_local_date date,
  p_preferred_doctor_id uuid
)
RETURNS public.rpc_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_tz text;
  v_schedule jsonb;
  v_today_local date;
  v_max_local date;
  v_day_name text;
  v_day jsonb;
  v_open time;
  v_close time;
  v_duration int;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_cursor timestamptz;
  v_block_end timestamptz;
  v_doctor_id uuid;
  v_available_ids uuid[] := ARRAY[]::uuid[];
  v_state text;
  v_blocks jsonb := '[]'::jsonb;
BEGIN
  PERFORM auth_internal.assert_appointment_access();
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);
  PERFORM auth_internal.assert_appointment_doctor(p_preferred_doctor_id, p_branch_id);

  SELECT
    COALESCE(NULLIF(trim(o.timezone), ''), 'UTC'),
    b.working_schedule
  INTO v_org_tz, v_schedule
  FROM public.branches b
  JOIN public.organizations o ON o.id = b.organization_id
  WHERE b.id = p_branch_id
    AND b.is_deleted = false
    AND b.is_active = true;

  v_today_local := (now() AT TIME ZONE v_org_tz)::date;
  v_max_local := v_today_local + 90;

  IF p_local_date < v_today_local OR p_local_date > v_max_local THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Date must be between today and 90 days ahead.');
  END IF;

  v_duration := auth_internal.resolve_appointment_default_duration(p_branch_id);

  IF v_schedule IS NULL THEN
    RETURN public.rpc_success(
      jsonb_build_object(
        'default_duration_minutes', v_duration,
        'blocks', '[]'::jsonb
      )
    );
  END IF;

  v_day_name := CASE extract(isodow FROM p_local_date)
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
    RETURN public.rpc_success(
      jsonb_build_object(
        'default_duration_minutes', v_duration,
        'blocks', '[]'::jsonb
      )
    );
  END IF;

  v_open := (v_day ->> 'open_time')::time;
  v_close := (v_day ->> 'close_time')::time;
  v_day_start := ((p_local_date::timestamp + v_open) AT TIME ZONE v_org_tz);
  v_day_end := ((p_local_date::timestamp + v_close) AT TIME ZONE v_org_tz);
  v_cursor := v_day_start;

  WHILE v_cursor + make_interval(mins => v_duration) <= v_day_end LOOP
    v_block_end := v_cursor + make_interval(mins => v_duration);

    IF NOT auth_internal.appointment_within_branch_working_hours(p_branch_id, v_cursor, v_block_end) THEN
      v_cursor := v_cursor + make_interval(mins => v_duration);
      CONTINUE;
    END IF;

    v_available_ids := ARRAY[]::uuid[];

    FOR v_doctor_id IN
      SELECT sm.id
      FROM public.staff_members sm
      JOIN public.staff_branch_assignments sba
        ON sba.staff_member_id = sm.id
       AND sba.branch_id = p_branch_id
       AND sba.is_deleted = false
      WHERE sm.role = 'doctor'
        AND sm.is_deleted = false
        AND sm.is_active = true
      ORDER BY sm.full_name
    LOOP
      IF NOT auth_internal.appointment_has_overlap(p_branch_id, v_doctor_id, v_cursor, v_block_end, NULL) THEN
        v_available_ids := array_append(v_available_ids, v_doctor_id);
      END IF;
    END LOOP;

    IF p_local_date = v_today_local AND v_cursor < now() THEN
      v_state := 'past';
    ELSIF p_preferred_doctor_id = ANY (v_available_ids) THEN
      v_state := 'available';
    ELSIF cardinality(v_available_ids) > 0 THEN
      v_state := 'alternate_doctors_available';
    ELSE
      v_state := 'fully_unavailable';
    END IF;

    v_blocks := v_blocks || jsonb_build_array(
      jsonb_build_object(
        'start_time', v_cursor,
        'end_time', v_block_end,
        'state', v_state,
        'available_doctor_ids', to_jsonb(v_available_ids)
      )
    );

    v_cursor := v_cursor + make_interval(mins => v_duration);
  END LOOP;

  RETURN public.rpc_success(
    jsonb_build_object(
      'default_duration_minutes', v_duration,
      'blocks', v_blocks
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('FORBIDDEN', 'INVALID_BRANCH', 'INVALID_DOCTOR') THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view booking slots.');
      END IF;
      IF SQLERRM = 'INVALID_BRANCH' THEN
        RETURN public.rpc_error('INVALID_BRANCH', 'Branch is not valid for this session.');
      END IF;
      RETURN public.rpc_error('INVALID_DOCTOR', 'Doctor is not valid for this branch.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_simplified_booking_slots(
  p_branch_id uuid,
  p_local_date date,
  p_preferred_doctor_id uuid
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_simplified_booking_slots(p_branch_id, p_local_date, p_preferred_doctor_id);
$$;

GRANT EXECUTE ON FUNCTION auth_internal.get_simplified_booking_slots(uuid, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_simplified_booking_slots(uuid, date, uuid) TO authenticated;
