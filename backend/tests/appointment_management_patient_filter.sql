-- V1-4 appointment management: list_appointments patient filter tests (QA LA-BE-001..003).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/appointment_management_patient_filter.sql

BEGIN;

CREATE TEMP TABLE appointment_patient_filter_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a5100000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b5100000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'a5100000-0000-4000-8000-000000000002';
  v_doctor_staff uuid := 'b5100000-0000-4000-8000-000000000002';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_target_patient uuid;
  v_patient_id uuid;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_start timestamptz;
  v_items jsonb;
  v_i int;
  v_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appt-filter-owner',
      extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appt-filter-doctor',
      extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.bootstrap_create_organization('Appt Filter Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'AF', NULL);
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
    (v_owner_staff, v_owner_user, 'Appt Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Appt Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_id, false, v_bootstrap_user, v_bootstrap_user);

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

  v_result := public.create_patient(v_branch_id, 'Target Patient', '201510000001', NULL, NULL, NULL, NULL, false);
  v_target_patient := (v_result.data ->> 'patient_id')::uuid;

  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '2 days';

  -- 2 appointments for target patient on different days, 8 for others (10 total).
  FOR v_i IN 1..2 LOOP
    v_start := v_day_start + make_interval(days => v_i - 1, hours => 10);
    v_result := public.create_appointment(
      v_branch_id, v_target_patient, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
    );
    IF NOT v_result.success THEN
      RAISE EXCEPTION 'target appt % failed: %', v_i, COALESCE(v_result.error_code, '?');
    END IF;
  END LOOP;

  FOR v_i IN 1..8 LOOP
    v_result := public.create_patient(
      v_branch_id,
      'Slot Patient ' || v_i,
      '201510002' || lpad(v_i::text, 2, '0'),
      NULL,
      NULL,
      NULL,
      NULL,
      false
    );
    v_patient_id := (v_result.data ->> 'patient_id')::uuid;
    v_start := v_day_start + make_interval(hours => v_i + 11);
    v_result := public.create_appointment(
      v_branch_id, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
    );
    IF NOT v_result.success THEN
      RAISE EXCEPTION 'other appt % failed: %', v_i, COALESCE(v_result.error_code, '?');
    END IF;
  END LOOP;

  -- LA-BE-001: patient filter returns only target patient's appointments.
  v_result := public.list_appointments(
    v_branch_id, v_day_start, v_day_end, NULL, NULL, v_target_patient
  );
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_count := jsonb_array_length(v_items);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_patient_filter_results VALUES (
    'LA_BE_001_list_appointments_patient_filter',
    v_result.success
      AND v_count = 2
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) item
        WHERE (item ->> 'patient_id')::uuid <> v_target_patient
      ),
    'count=' || v_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- LA-BE-002: null patient filter returns all branch appointments.
  v_result := public.list_appointments(v_branch_id, v_day_start, v_day_end, NULL, NULL, NULL);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_count := jsonb_array_length(v_items);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_patient_filter_results VALUES (
    'LA_BE_002_list_appointments_null_patient_filter',
    v_result.success AND v_count = 10,
    'count=' || v_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Omit 6th arg (default NULL) — backward compatible with 5-arg callers passing explicit NULL patient.
  v_result := public.list_appointments(v_branch_id, v_day_start, v_day_end, NULL, NULL);
  v_count := jsonb_array_length(COALESCE(v_result.data -> 'items', '[]'::jsonb));
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_patient_filter_results VALUES (
    'LA_BE_002_list_appointments_five_arg_backward_compat',
    v_result.success AND v_count = 10,
    'count=' || v_count::text
  );
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

-- LA-BE-003: legacy 5-parameter overload must not exist (ambiguous with 6-arg default).
DO $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_patient_filter_results VALUES (
    'LA_BE_003_legacy_5_arg_overload_dropped',
    NOT EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'list_appointments'
        AND pg_get_function_identity_arguments(p.oid) = 'uuid, timestamp with time zone, timestamp with time zone, uuid, text[]'
    ),
    'only 6-arg public.list_appointments should remain'
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM appointment_patient_filter_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM appointment_patient_filter_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'appointment_management_patient_filter: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
