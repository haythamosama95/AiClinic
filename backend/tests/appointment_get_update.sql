-- V1-4 get_appointment and update_appointment (branch move) verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/appointment_get_update.sql

BEGIN;

CREATE TEMP TABLE appointment_get_update_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.test_appointment_same_day_slot(p_offset_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_tz text := 'UTC';
  v_day_start timestamptz;
BEGIN
  IF p_offset_hours < 1 OR p_offset_hours > 23 THEN
    RAISE EXCEPTION 'test_appointment_same_day_slot: offset must be 1..23, got %', p_offset_hours;
  END IF;
  v_day_start := date_trunc('day', now() AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  RETURN v_day_start + make_interval(hours => p_offset_hours);
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1500000-0000-4000-8000-000000000701';
  v_owner_staff uuid := 'b1500000-0000-4000-8000-000000000701';
  v_doctor_user uuid := 'a1500000-0000-4000-8000-000000000702';
  v_doctor_staff uuid := 'b1500000-0000-4000-8000-000000000702';
  v_result public.rpc_result;
  v_org_id uuid;
  v_main_branch_id uuid;
  v_second_branch_id uuid;
  v_patient_id uuid;
  v_patient_second uuid;
  v_patient_confirmed uuid;
  v_patient_invalid_branch uuid;
  v_appt_id uuid;
  v_appt_second_branch uuid;
  v_appt_confirmed uuid;
  v_appt_invalid_branch uuid;
  v_start timestamptz;
  v_start_move timestamptz;
  v_start_second timestamptz;
  v_db_branch_id uuid;
  v_audit_count int;
  v_random_uuid uuid := 'f1500000-0000-4000-8000-000000000799';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-get-upd-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-get-upd-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V15 Get Update Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_main_branch_id := (v_result.data ->> 'branch_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Second', NULL, NULL, 'SEC', NULL);
  v_second_branch_id := (v_result.data ->> 'branch_id')::uuid;

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
  WHERE b.id IN (v_main_branch_id, v_second_branch_id);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Dr Smith', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_main_branch_id, true, v_bootstrap_user, v_bootstrap_user),
    (v_owner_staff, v_second_branch_id, false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_main_branch_id, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_second_branch_id, false, v_bootstrap_user, v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_main_branch_id::text || ',' || v_second_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_main_branch_id, 'Get Update Patient', '201500000701', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_main_branch_id, 'Second Branch Patient', '201500000702', NULL, NULL, NULL, NULL, false);
  v_patient_second := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_main_branch_id, 'Confirmed Patient', '201500000703', NULL, NULL, NULL, NULL, false);
  v_patient_confirmed := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_main_branch_id, 'Invalid Branch Patient', '201500000704', NULL, NULL, NULL, NULL, false);
  v_patient_invalid_branch := (v_result.data ->> 'patient_id')::uuid;

  v_start_move := pg_temp.test_appointment_same_day_slot(3);
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, v_doctor_staff, 'planned', v_start_move, 30, NULL, 'Branch move test'
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  IF NOT v_result.success OR v_appt_id IS NULL THEN
    RAISE EXCEPTION 'setup main appointment failed: %', COALESCE(v_result.error_code, '?');
  END IF;

  -- get_appointment: success
  v_result := public.get_appointment(v_appt_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_get_update_results VALUES (
    'get_appointment_success',
    v_result.success
      AND (v_result.data ->> 'id')::uuid = v_appt_id
      AND v_result.data ->> 'patient_name' = 'Get Update Patient'
      AND v_result.data ->> 'status' = 'scheduled'
      AND (v_result.data ->> 'branch_id')::uuid = v_main_branch_id,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_appointment: NOT_FOUND for random uuid
  v_result := public.get_appointment(v_random_uuid);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_get_update_results VALUES (
    'get_appointment_not_found_random',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Appointment in second branch, JWT limited to main only.
  v_start_second := date_trunc('day', now() + interval '10 days') + interval '14 hours';
  v_result := public.create_appointment(
    v_second_branch_id, v_patient_second, v_doctor_staff, 'planned', v_start_second, 30, NULL, 'Second branch appt'
  );
  v_appt_second_branch := (v_result.data ->> 'appointment_id')::uuid;
  IF NOT v_result.success OR v_appt_second_branch IS NULL THEN
    RAISE EXCEPTION 'setup second-branch appointment failed: %', COALESCE(v_result.error_code, '?');
  END IF;

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

  v_result := public.get_appointment(v_appt_second_branch);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_get_update_results VALUES (
    'get_appointment_not_found_wrong_branch_jwt',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore JWT with both branches for update tests.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_main_branch_id::text || ',' || v_second_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  -- update_appointment: move scheduled appointment to second branch
  v_result := public.update_appointment(
    v_appt_id,
    v_patient_id,
    v_doctor_staff,
    v_start_move,
    30,
    NULL,
    'Moved to second branch',
    v_second_branch_id
  );
  SELECT a.branch_id INTO v_db_branch_id FROM public.appointments a WHERE a.id = v_appt_id;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_get_update_results VALUES (
    'update_appointment_branch_move_success',
    v_result.success AND v_db_branch_id = v_second_branch_id,
    format('db_branch=%s expected=%s', v_db_branch_id, v_second_branch_id)
  );
  PERFORM set_config('role', 'authenticated', true);

  -- update_appointment: reject branch change when confirmed
  v_start := date_trunc('day', now() + interval '11 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_confirmed, v_doctor_staff, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_confirmed := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_confirmed, 'confirmed');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'setup confirm failed: %', COALESCE(v_result.error_code, '?');
  END IF;
  v_result := public.update_appointment(
    v_appt_confirmed,
    v_patient_confirmed,
    v_doctor_staff,
    v_start,
    30,
    NULL,
    NULL,
    v_second_branch_id
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_get_update_results VALUES (
    'update_appointment_rejects_branch_change_when_confirmed',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- update_appointment: INVALID_BRANCH when p_branch_id not in JWT
  v_start := date_trunc('day', now() + interval '12 days') + interval '10 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_invalid_branch, v_doctor_staff, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_invalid_branch := (v_result.data ->> 'appointment_id')::uuid;
  IF NOT v_result.success OR v_appt_invalid_branch IS NULL THEN
    RAISE EXCEPTION 'setup invalid-branch appointment failed: %', COALESCE(v_result.error_code, '?');
  END IF;

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

  v_result := public.update_appointment(
    v_appt_invalid_branch,
    v_patient_invalid_branch,
    v_doctor_staff,
    v_start,
    30,
    NULL,
    NULL,
    v_second_branch_id
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_get_update_results VALUES (
    'update_appointment_rejects_invalid_branch_jwt',
    NOT v_result.success AND v_result.error_code = 'INVALID_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Audit log on successful branch move (first update)
  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.record_id = v_appt_id
    AND al.action = 'appointment.update'
    AND al.new_data_json ->> 'branch_id' = v_second_branch_id::text;

  INSERT INTO appointment_get_update_results VALUES (
    'update_appointment_writes_audit_log',
    v_audit_count >= 1,
    'audit_count=' || v_audit_count::text
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
  FROM appointment_get_update_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM appointment_get_update_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'appointment_get_update: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
