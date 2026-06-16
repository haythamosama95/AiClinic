-- Calendar backend integrity (CAL-J*, CAL-A06, CAL-H07).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/appointment_calendar_backend_integrity.sql

BEGIN;

CREATE TEMP TABLE calendar_integrity_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.test_appointment_same_day_slot(p_offset_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_day_start timestamptz;
BEGIN
  IF p_offset_hours < 1 OR p_offset_hours > 23 THEN
    RAISE EXCEPTION 'test_appointment_same_day_slot: offset must be 1..23, got %', p_offset_hours;
  END IF;
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  RETURN v_day_start + make_interval(hours => p_offset_hours);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.expect_invalid_duration(p_duration int)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM auth_internal.assert_appointment_duration_bounds(p_duration);
  RETURN false;
EXCEPTION
  WHEN OTHERS THEN
    RETURN SQLERRM = 'INVALID_DURATION';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_duration_bounds_ok(p_duration int)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM auth_internal.assert_appointment_duration_bounds(p_duration);
  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RETURN false;
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a2800000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b2800000-0000-4000-8000-000000000101';
  v_doctor_user uuid := 'a2800000-0000-4000-8000-000000000102';
  c_doctor_staff_id constant uuid := 'b2800000-0000-4000-8000-000000000102';
  v_lab_user uuid := 'a2800000-0000-4000-8000-000000000103';
  v_lab_staff uuid := 'b2800000-0000-4000-8000-000000000103';
  v_doctor2_staff uuid := 'b2800000-0000-4000-8000-000000000104';
  v_doctor2_user uuid := 'a2800000-0000-4000-8000-000000000104';
  v_result public.rpc_result;
  v_org_id uuid;
  v_main_branch_id uuid;
  v_patient_id uuid;
  v_patient2_id uuid;
  v_appt_id uuid;
  v_start timestamptz;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_month_end timestamptz;
  v_items jsonb;
  v_settings jsonb;
  v_audit_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user, v_lab_user, v_doctor2_user);

  -- CAL-J01: duration below minimum raises INVALID_DURATION.
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J01_duration_bounds_rejects_4_min',
    pg_temp.expect_invalid_duration(4),
    'assert_appointment_duration_bounds(4)'
  );

  -- CAL-J02: duration 241 min is allowed (no upper cap).
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J02_duration_bounds_accepts_241_min',
    pg_temp.assert_duration_bounds_ok(241),
    'assert_appointment_duration_bounds(241)'
  );

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cal-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cal-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cal-lab',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor2_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cal-doctor2',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('CAL Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'CALM', NULL);
  v_main_branch_id := (v_result.data ->> 'branch_id')::uuid;

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
  WHERE b.id = v_main_branch_id;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (c_doctor_staff_id, v_doctor_user, 'Dr Smith', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Lab Tech', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor2_staff, v_doctor2_user, 'Dr Jones', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_main_branch_id, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (c_doctor_staff_id), (v_lab_staff), (v_doctor2_staff)) AS s(id);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_main_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_main_branch_id, 'CAL Patient', '201000000281', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_main_branch_id, 'CAL Patient 2', '201000000282', NULL, NULL, NULL, NULL, false);
  v_patient2_id := (v_result.data ->> 'patient_id')::uuid;

  -- CAL-J03: get_appointment_settings omits max_duration_minutes.
  v_result := public.get_appointment_settings(v_main_branch_id);
  v_settings := v_result.data;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J03_get_settings_no_max_duration',
    v_result.success
      AND v_settings ? 'default_duration_minutes'
      AND v_settings ? 'min_duration_minutes'
      AND NOT (v_settings ? 'max_duration_minutes'),
    COALESCE(v_result.error_code, 'keys=' || (SELECT string_agg(key, ',') FROM jsonb_object_keys(v_settings) AS key))
  );
  PERFORM set_config('role', 'authenticated', true);

  -- CAL-J04: create with 300 min duration succeeds.
  v_start := date_trunc('day', now() + interval '5 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 300, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J04_create_300_min_succeeds',
    v_result.success AND v_appt_id IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- CAL-J05 / CAL-H07: reschedule to 300 min succeeds (no 240 cap).
  v_start := date_trunc('day', now() + interval '6 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient2_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.reschedule_appointment(v_appt_id, v_start, 300, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J05_reschedule_300_min_succeeds',
    v_result.success AND (v_result.data ->> 'appointment_id') IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-H07_resize_over_240_min_succeeds',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- CAL-J06: reschedule outside working hours → INVALID_INPUT.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = jsonb_build_object(
    'days',
    jsonb_build_array(
      jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00')
    )
  )
  WHERE b.id = v_main_branch_id;
  PERFORM set_config('role', 'authenticated', true);

  v_start := date_trunc('day', now() + interval '17 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.reschedule_appointment(
    v_appt_id,
    date_trunc('day', now() + interval '17 days') + interval '2 hours',
    30,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J06_reschedule_outside_hours_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

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
  WHERE b.id = v_main_branch_id;
  PERFORM set_config('role', 'authenticated', true);

  -- CAL-J07: patient already booked same day on reschedule.
  v_start := date_trunc('day', now() + interval '18 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient2_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_start := date_trunc('day', now() + interval '19 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient2_id, v_doctor2_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.reschedule_appointment(
    v_appt_id,
    date_trunc('day', now() + interval '18 days') + interval '14 hours',
    20,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J07_reschedule_same_day_patient_rejected',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ALREADY_BOOKED_SAME_DAY',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- CAL-J08: reschedule writes audit_log entry.
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.audit_log;
  PERFORM set_config('role', 'authenticated', true);
  v_start := date_trunc('day', now() + interval '20 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.reschedule_appointment(v_appt_id, v_start + interval '1 hour', 30, NULL);
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.record_id = v_appt_id
    AND al.action = 'appointment.reschedule';
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J08_reschedule_writes_audit_log',
    v_result.success AND v_audit_count >= 1,
    'audit_count=' || COALESCE(v_audit_count::text, '0')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- CAL-J09: list_appointments UTC day bounds (local day → UTC window).
  v_day_start := date_trunc('day', (now() + interval '25 days') AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '1 day';
  v_start := v_day_start + interval '12 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;

  v_result := public.list_appointments(v_main_branch_id, v_day_start, v_day_end, NULL, NULL);
  v_items := v_result.data -> 'items';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J09_list_appointments_utc_day_bounds',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS item
        WHERE (item ->> 'id')::uuid = v_appt_id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS item
        WHERE (item ->> 'start_time')::timestamptz < v_day_start
           OR (item ->> 'start_time')::timestamptz >= v_day_end
      ),
    'day_start=' || v_day_start::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- CAL-J10: list_appointments UTC month bounds.
  v_month_start := date_trunc('month', (now() + interval '60 days') AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_month_end := v_month_start + interval '1 month';
  v_start := v_month_start + interval '15 days' + interval '11 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient2_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;

  v_result := public.list_appointments(v_main_branch_id, v_month_start, v_month_end, NULL, NULL);
  v_items := v_result.data -> 'items';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-J10_list_appointments_utc_month_bounds',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS item
        WHERE (item ->> 'id')::uuid = v_appt_id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS item
        WHERE (item ->> 'start_time')::timestamptz < v_month_start
           OR (item ->> 'start_time')::timestamptz >= v_month_end
      ),
    'month_start=' || v_month_start::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- CAL-A06: reschedule without appointments.create → FORBIDDEN.
  v_start := date_trunc('day', now() + interval '30 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_lab_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_main_branch_id::text,
      'staff_member_id', v_lab_staff::text,
      'staff_role', 'lab_staff',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.reschedule_appointment(v_appt_id, v_start + interval '1 hour', 30, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO calendar_integrity_results VALUES (
    'CAL-A06_reschedule_without_create_permission_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
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
  FROM calendar_integrity_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM calendar_integrity_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'appointment_calendar_backend_integrity: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
