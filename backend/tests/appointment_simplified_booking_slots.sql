-- V1-4 get_simplified_booking_slots verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/appointment_simplified_booking_slots.sql

BEGIN;

CREATE TEMP TABLE simplified_booking_slots_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1500000-0000-4000-8000-000000000703';
  v_owner_staff uuid := 'b1500000-0000-4000-8000-000000000703';
  v_doctor_user uuid := 'a1500000-0000-4000-8000-000000000704';
  v_doctor_staff uuid := 'b1500000-0000-4000-8000-000000000704';
  v_doctor2_user uuid := 'a1500000-0000-4000-8000-000000000705';
  v_doctor2_staff uuid := 'b1500000-0000-4000-8000-000000000705';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_patient_id uuid;
  v_today date;
  v_day_name text;
  v_blocks jsonb;
  v_default int;
  v_found boolean;
  v_start timestamptz;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user, v_doctor2_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-slots-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-slots-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor2_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-slots-doctor2',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V15 Slots Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  v_today := (now() AT TIME ZONE 'UTC')::date;
  v_day_name := CASE extract(isodow FROM v_today)
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
    (v_doctor_staff, v_doctor_user, 'Dr Smith', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor2_staff, v_doctor2_user, 'Dr Jones', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor2_staff, v_branch_id, false, v_bootstrap_user, v_bootstrap_user);

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

  v_result := public.create_patient(v_branch_id, 'Slots Patient', '201500000703', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  -- Success on working day
  v_result := public.get_simplified_booking_slots(v_branch_id, v_today, v_doctor_staff);
  v_blocks := v_result.data -> 'blocks';
  v_default := (v_result.data ->> 'default_duration_minutes')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_booking_slots_results VALUES (
    'slots_success_on_working_day',
    v_result.success
      AND jsonb_typeof(v_blocks) = 'array'
      AND jsonb_array_length(v_blocks) > 0
      AND v_default IS NOT NULL
      AND v_default >= 5,
    format('blocks=%s default=%s', jsonb_array_length(v_blocks), v_default)
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Date > 90 days ahead
  v_result := public.get_simplified_booking_slots(v_branch_id, v_today + 91, v_doctor_staff);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_booking_slots_results VALUES (
    'slots_rejects_date_over_90_days',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Date in the past
  v_result := public.get_simplified_booking_slots(v_branch_id, v_today - 1, v_doctor_staff);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_booking_slots_results VALUES (
    'slots_rejects_past_date',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Non-working day: mark today as closed
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = jsonb_set(
    b.working_schedule,
    ARRAY['days'],
    (
      SELECT jsonb_agg(
        CASE
          WHEN lower(trim(elem ->> 'day')) = v_day_name
            THEN jsonb_set(elem, '{is_working_day}', 'false'::jsonb)
          ELSE elem
        END
      )
      FROM jsonb_array_elements(b.working_schedule -> 'days') AS elem
    )
  )
  WHERE b.id = v_branch_id;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_simplified_booking_slots(v_branch_id, v_today, v_doctor_staff);
  v_blocks := v_result.data -> 'blocks';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_booking_slots_results VALUES (
    'slots_empty_on_non_working_day',
    v_result.success
      AND jsonb_typeof(v_blocks) = 'array'
      AND jsonb_array_length(v_blocks) = 0,
    'blocks=' || COALESCE(jsonb_array_length(v_blocks)::text, '0')
  );

  -- Restore full-day schedule for doctor filter test
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

  -- Doctor filter: preferred doctor in available_doctor_ids for a free slot
  v_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '14 hours';
  v_result := public.get_simplified_booking_slots(v_branch_id, v_today, v_doctor_staff);
  v_blocks := v_result.data -> 'blocks';

  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_blocks) AS block
    WHERE block -> 'available_doctor_ids' @> to_jsonb(ARRAY[v_doctor_staff::text])
      AND (block ->> 'start_time')::timestamptz >= v_start
  )
  INTO v_found;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO simplified_booking_slots_results VALUES (
    'slots_preferred_doctor_in_available_ids',
    v_result.success AND v_found,
    'found=' || v_found::text
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  SELECT count(*)::int
  INTO v_failed
  FROM simplified_booking_slots_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM simplified_booking_slots_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'appointment_simplified_booking_slots: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
