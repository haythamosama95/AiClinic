-- 011 simplified slot booking RPC verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/simplified_slot_booking.sql

BEGIN;

CREATE TEMP TABLE simplified_slot_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1500000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b1500000-0000-4000-8000-000000000101';
  v_doctor_user uuid := 'a1500000-0000-4000-8000-000000000102';
  c_doctor_a constant uuid := 'b1500000-0000-4000-8000-000000000102';
  v_doctor2_user uuid := 'a1500000-0000-4000-8000-000000000103';
  c_doctor_b constant uuid := 'b1500000-0000-4000-8000-000000000103';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_patient_id uuid;
  v_patient2_id uuid;
  v_start timestamptz;
  v_blocks jsonb;
  v_block jsonb;
  v_today date;
  v_future date;
  v_slot_time time := time '10:00';
  v_has_past boolean := false;
  v_has_available boolean := false;
  v_has_alternate boolean := false;
  v_has_fully_unavailable boolean := false;
  v_ids_match boolean := false;
  v_appt_id uuid;
  v_day_name text;
  c_invalid_branch constant uuid := '00000000-0000-0000-0000-000000000099';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.app_settings WHERE key = 'appointment.default_duration_minutes';
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user, v_doctor2_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-doctor-a',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor2_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-doctor-b',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V15 Slot Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = jsonb_build_object(
    'days',
    jsonb_build_array(
      jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59')
    )
  )
  WHERE b.id = v_branch_id;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (c_doctor_a, v_doctor_user, 'Dr Alpha', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (c_doctor_b, v_doctor2_user, 'Dr Beta', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_id, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (c_doctor_a), (c_doctor_b)) AS s(id);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_branch_id, 'Slot Patient', '201000000151', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_branch_id, 'Slot Patient 2', '201000000152', NULL, NULL, NULL, NULL, false);
  v_patient2_id := (v_result.data ->> 'patient_id')::uuid;

  PERFORM public.set_appointment_default_duration(30, v_branch_id);

  v_today := (now() AT TIME ZONE 'UTC')::date;
  v_future := v_today + 5;

  -- BE-L01: Today includes past blocks.
  v_result := public.get_simplified_booking_slots(v_branch_id, v_today, c_doctor_a);
  v_blocks := COALESCE(v_result.data -> 'blocks', '[]'::jsonb);
  FOR v_block IN SELECT value FROM jsonb_array_elements(v_blocks)
  LOOP
    IF v_block ->> 'state' = 'past' THEN
      v_has_past := true;
    END IF;
  END LOOP;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'today_includes_past_blocks',
    v_result.success AND v_has_past,
    'blocks=' || jsonb_array_length(v_blocks)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L02: Reject past date.
  v_result := public.get_simplified_booking_slots(v_branch_id, v_today - 1, c_doctor_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'reject_date_before_today',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L03: Reject date beyond 90 days.
  v_result := public.get_simplified_booking_slots(v_branch_id, v_today + 91, c_doctor_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'reject_date_beyond_90_days',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L04: Available when preferred doctor is free.
  v_future := v_today + 5;
  v_start := (v_future::timestamp + v_slot_time) AT TIME ZONE 'UTC';
  v_result := public.get_simplified_booking_slots(v_branch_id, v_future, c_doctor_a);
  v_blocks := COALESCE(v_result.data -> 'blocks', '[]'::jsonb);
  FOR v_block IN SELECT value FROM jsonb_array_elements(v_blocks)
  LOOP
    IF (v_block ->> 'start_time')::timestamptz = v_start THEN
      v_has_available := (v_block ->> 'state') = 'available';
      EXIT;
    END IF;
  END LOOP;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'available_when_preferred_doctor_free',
    v_result.success AND v_has_available,
    'start=' || v_start::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L05: Alternate doctors when preferred busy and another doctor is free.
  v_future := v_today + 6;
  v_start := (v_future::timestamp + v_slot_time) AT TIME ZONE 'UTC';
  v_result := public.create_appointment(v_branch_id, v_patient_id, c_doctor_a, 'planned', v_start, 30, NULL, NULL);
  v_result := public.get_simplified_booking_slots(v_branch_id, v_future, c_doctor_a);
  v_blocks := COALESCE(v_result.data -> 'blocks', '[]'::jsonb);
  FOR v_block IN SELECT value FROM jsonb_array_elements(v_blocks)
  LOOP
    IF (v_block ->> 'start_time')::timestamptz = v_start THEN
      v_has_alternate := (v_block ->> 'state') = 'alternate_doctors_available'
        AND (v_block -> 'available_doctor_ids') @> jsonb_build_array(c_doctor_b::text);
      EXIT;
    END IF;
  END LOOP;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'alternate_when_preferred_busy_other_free',
    v_result.success AND v_has_alternate,
    'start=' || v_start::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L06: Fully unavailable when all doctors are busy.
  v_future := v_today + 7;
  v_start := (v_future::timestamp + v_slot_time) AT TIME ZONE 'UTC';
  v_result := public.create_appointment(v_branch_id, v_patient_id, c_doctor_a, 'planned', v_start, 30, NULL, NULL);
  v_result := public.create_appointment(v_branch_id, v_patient2_id, c_doctor_b, 'planned', v_start, 30, NULL, NULL);
  v_result := public.get_simplified_booking_slots(v_branch_id, v_future, c_doctor_a);
  v_blocks := COALESCE(v_result.data -> 'blocks', '[]'::jsonb);
  FOR v_block IN SELECT value FROM jsonb_array_elements(v_blocks)
  LOOP
    IF (v_block ->> 'start_time')::timestamptz = v_start THEN
      v_has_fully_unavailable := (v_block ->> 'state') = 'fully_unavailable';
      EXIT;
    END IF;
  END LOOP;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'fully_unavailable_when_all_doctors_busy',
    v_result.success AND v_has_fully_unavailable,
    'start=' || v_start::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L07: Per-doctor overlap allows different doctors at the same time.
  v_future := v_today + 8;
  v_start := (v_future::timestamp + v_slot_time) AT TIME ZONE 'UTC';
  v_result := public.create_appointment(v_branch_id, v_patient_id, c_doctor_a, 'planned', v_start, 30, NULL, NULL);
  v_result := public.create_appointment(v_branch_id, v_patient2_id, c_doctor_b, 'planned', v_start, 30, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'per_doctor_overlap_allows_different_doctors',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L08: Per-doctor overlap blocks the same doctor at the same time.
  v_result := public.create_appointment(v_branch_id, v_patient_id, c_doctor_a, 'planned', v_start, 30, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'per_doctor_overlap_blocks_same_doctor',
    NOT v_result.success AND v_result.error_code = 'SCHEDULE_CONFLICT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L09: Two doctor-less planned appointments at the same time are allowed.
  v_future := v_today + 9;
  v_start := (v_future::timestamp + v_slot_time) AT TIME ZONE 'UTC';
  v_result := public.create_appointment(v_branch_id, v_patient_id, NULL, 'planned', v_start, 15, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'doctorless_overlap_first_planned',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_appointment(v_branch_id, v_patient2_id, NULL, 'planned', v_start, 15, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'doctorless_overlap_same_time_allowed',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L10: Invalid branch id is rejected.
  v_result := public.get_simplified_booking_slots(c_invalid_branch, v_today + 5, c_doctor_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'reject_invalid_branch',
    NOT v_result.success AND v_result.error_code = 'INVALID_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L11: Non-doctor staff id is rejected as preferred doctor.
  v_result := public.get_simplified_booking_slots(v_branch_id, v_today + 5, v_owner_staff);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'reject_invalid_doctor',
    NOT v_result.success AND v_result.error_code = 'INVALID_DOCTOR',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L14: available_doctor_ids lists only free doctors for mixed availability.
  v_future := v_today + 10;
  v_start := (v_future::timestamp + v_slot_time) AT TIME ZONE 'UTC';
  v_result := public.create_appointment(v_branch_id, v_patient_id, c_doctor_a, 'planned', v_start, 30, NULL, NULL);
  v_result := public.get_simplified_booking_slots(v_branch_id, v_future, c_doctor_a);
  v_blocks := COALESCE(v_result.data -> 'blocks', '[]'::jsonb);
  v_ids_match := false;
  FOR v_block IN SELECT value FROM jsonb_array_elements(v_blocks)
  LOOP
    IF (v_block ->> 'start_time')::timestamptz = v_start THEN
      v_ids_match :=
        (v_block -> 'available_doctor_ids') @> jsonb_build_array(c_doctor_b::text)
        AND NOT ((v_block -> 'available_doctor_ids') @> jsonb_build_array(c_doctor_a::text));
      EXIT;
    END IF;
  END LOOP;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'available_doctor_ids_match_free_doctors_only',
    v_result.success AND v_ids_match,
    'start=' || v_start::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L15: Response includes branch default duration setting.
  PERFORM public.set_appointment_default_duration(45, v_branch_id);
  v_future := v_today + 11;
  v_result := public.get_simplified_booking_slots(v_branch_id, v_future, c_doctor_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'response_includes_default_duration_minutes',
    v_result.success AND (v_result.data ->> 'default_duration_minutes')::int = 45,
    COALESCE(v_result.data ->> 'default_duration_minutes', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L12: Null working schedule returns empty blocks successfully.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches SET working_schedule = NULL WHERE id = v_branch_id;
  PERFORM set_config('role', 'authenticated', true);
  v_future := v_today + 12;
  v_result := public.get_simplified_booking_slots(v_branch_id, v_future, c_doctor_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'null_working_schedule_returns_empty_blocks',
    v_result.success AND jsonb_array_length(COALESCE(v_result.data -> 'blocks', '[]'::jsonb)) = 0,
    'blocks=' || jsonb_array_length(COALESCE(v_result.data -> 'blocks', '[]'::jsonb))::text
  );

  -- Restore working schedule for closed-day test.
  UPDATE public.branches b
  SET working_schedule = jsonb_build_object(
    'days',
    jsonb_build_array(
      jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59')
    )
  )
  WHERE b.id = v_branch_id;
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L13: Non-working weekday returns empty blocks.
  v_future := v_today + 20;
  v_day_name := CASE extract(isodow FROM v_future)
    WHEN 1 THEN 'monday'
    WHEN 2 THEN 'tuesday'
    WHEN 3 THEN 'wednesday'
    WHEN 4 THEN 'thursday'
    WHEN 5 THEN 'friday'
    WHEN 6 THEN 'saturday'
    ELSE 'sunday'
  END;
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = (
    SELECT jsonb_build_object(
      'days',
      jsonb_agg(
        CASE
          WHEN lower(trim(d.value ->> 'day')) = v_day_name THEN
            jsonb_set(d.value, '{is_working_day}', 'false'::jsonb)
          ELSE d.value
        END
      )
    )
    FROM jsonb_array_elements(b.working_schedule -> 'days') AS d(value)
  )
  WHERE b.id = v_branch_id;
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.get_simplified_booking_slots(v_branch_id, v_future, c_doctor_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'closed_day_returns_empty_blocks',
    v_result.success AND jsonb_array_length(COALESCE(v_result.data -> 'blocks', '[]'::jsonb)) = 0,
    'day=' || v_day_name
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-L16: Reschedule to a time occupied by a different doctor is allowed.
  v_future := v_today + 21;
  v_start := (v_future::timestamp + v_slot_time) AT TIME ZONE 'UTC';
  v_result := public.create_appointment(v_branch_id, v_patient_id, c_doctor_a, 'planned', v_start, 30, NULL, NULL);
  v_result := public.create_appointment(
    v_branch_id, v_patient2_id, c_doctor_b, 'planned', v_start + interval '4 hours', 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.reschedule_appointment(v_appt_id, v_start, 30, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_slot_results VALUES (
    'reschedule_cross_doctor_same_time_allowed',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('role', 'postgres', true);
END;
$$;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT test_name, passed, detail FROM simplified_slot_results WHERE NOT passed
  LOOP
    RAISE EXCEPTION 'FAIL %: %', r.test_name, r.detail;
  END LOOP;
END;
$$;

SELECT test_name, passed, detail FROM simplified_slot_results ORDER BY test_name;

ROLLBACK;
