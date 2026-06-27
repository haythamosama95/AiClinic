-- ui/010-queue backend QA tests (BE-001..BE-006).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/appointment_queue_qa.sql
--
-- Covers list_appointments queue fields (updated_at, wait timestamps),
-- status transition guards (DOCTOR_ALREADY_IN_PROGRESS, day-gated check-in),
-- and wait-timestamp persistence on checked_in / in_progress.

BEGIN;

CREATE TEMP TABLE appointment_queue_qa_results (
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
  v_owner_user uuid := 'a6100000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b6100000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'a6100000-0000-4000-8000-000000000002';
  c_doctor_staff_id constant uuid := 'b6100000-0000-4000-8000-000000000002';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_patient_id uuid;
  v_patient2_id uuid;
  v_appt_a uuid;
  v_appt_b uuid;
  v_start timestamptz;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_items jsonb;
  v_status text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'queue-qa-owner',
      extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'queue-qa-doctor',
      extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Queue QA Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'QQ', NULL);
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
    (v_owner_staff, v_owner_user, 'Queue Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (c_doctor_staff_id, v_doctor_user, 'Dr Queue', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user),
    (c_doctor_staff_id, v_branch_id, false, v_bootstrap_user, v_bootstrap_user);

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

  v_result := public.create_patient(v_branch_id, 'Queue Patient A', '201610000001', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_branch_id, 'Queue Patient B', '201610000002', NULL, NULL, NULL, NULL, false);
  v_patient2_id := (v_result.data ->> 'patient_id')::uuid;

  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '1 day';

  -- ---------------------------------------------------------------------------
  -- BE-006 — Future day check-in rejected (INVALID_TRANSITION)
  -- ---------------------------------------------------------------------------
  v_start := date_trunc('hour', now() + interval '20 days');
  v_result := public.create_appointment(
    v_branch_id, v_patient2_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_b := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_b, 'confirmed');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'BE-006 setup confirm failed: %', COALESCE(v_result.error_code, '?');
  END IF;

  v_result := public.update_appointment_status(v_appt_b, 'checked_in');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_queue_qa_results VALUES (
    'BE_006_future_day_check_in_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_TRANSITION',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------------------------
  -- BE-004 — checked_in sets checked_in_at; in_progress_at remains NULL
  -- ---------------------------------------------------------------------------
  v_start := pg_temp.test_appointment_same_day_slot(9);
  v_result := public.create_appointment(
    v_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_a := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_a, 'confirmed');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'BE-004 setup confirm failed: %', COALESCE(v_result.error_code, '?');
  END IF;

  v_result := public.update_appointment_status(v_appt_a, 'checked_in');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_queue_qa_results VALUES (
    'BE_004_checked_in_sets_checked_in_at',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.appointments a
        WHERE a.id = v_appt_a
          AND a.status = 'checked_in'
          AND a.checked_in_at IS NOT NULL
          AND a.in_progress_at IS NULL
      ),
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------------------------
  -- BE-005 — in_progress sets in_progress_at; checked_in_at preserved
  -- ---------------------------------------------------------------------------
  v_result := public.update_appointment_status(v_appt_a, 'in_progress');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_queue_qa_results VALUES (
    'BE_005_in_progress_sets_in_progress_at',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.appointments a
        WHERE a.id = v_appt_a
          AND a.status = 'in_progress'
          AND a.checked_in_at IS NOT NULL
          AND a.in_progress_at IS NOT NULL
      ),
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------------------------
  -- BE-001 — list_appointments returns updated_at for today's queue
  -- Migration: 20260621120000_list_appointments_updated_at.sql
  -- ---------------------------------------------------------------------------
  v_result := public.list_appointments(v_branch_id, v_day_start, v_day_end, NULL, NULL);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_queue_qa_results VALUES (
    'BE_001_list_appointments_returns_updated_at',
    v_result.success
      AND jsonb_array_length(v_items) > 0
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) item
        WHERE item ->> 'updated_at' IS NULL
          OR (item ->> 'updated_at')::timestamptz IS NULL
      ),
    'count=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------------------------
  -- BE-002 — list_appointments returns wait timestamps when set
  -- Migration: 20260627120000_appointment_wait_timestamps.sql
  -- ---------------------------------------------------------------------------
  v_result := public.list_appointments(v_branch_id, v_day_start, v_day_end, NULL, NULL);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_queue_qa_results VALUES (
    'BE_002_list_appointments_returns_wait_timestamps',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) item
        WHERE (item ->> 'id')::uuid = v_appt_a
          AND item ? 'checked_in_at'
          AND item ? 'in_progress_at'
          AND item ->> 'checked_in_at' IS NOT NULL
          AND (item ->> 'checked_in_at')::timestamptz IS NOT NULL
          AND item ->> 'in_progress_at' IS NOT NULL
          AND (item ->> 'in_progress_at')::timestamptz IS NOT NULL
      ),
    'appt_a=' || v_appt_a::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------------------------
  -- BE-003 — Second in_progress for same doctor rejected (DOCTOR_ALREADY_IN_PROGRESS)
  -- Doctor D has appointment A in_progress; appointment B checked_in with doctor D.
  -- ---------------------------------------------------------------------------
  v_start := pg_temp.test_appointment_same_day_slot(10);
  v_result := public.create_appointment(
    v_branch_id, v_patient2_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_b := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_b, 'confirmed');
  v_result := public.update_appointment_status(v_appt_b, 'checked_in');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'BE-003 setup checked_in failed: %', COALESCE(v_result.error_code, '?');
  END IF;

  v_result := public.update_appointment_status(v_appt_b, 'in_progress');
  PERFORM set_config('role', 'postgres', true);
  SELECT a.status::text INTO v_status FROM public.appointments a WHERE a.id = v_appt_b;
  INSERT INTO appointment_queue_qa_results VALUES (
    'BE_003_second_in_progress_same_doctor_rejected',
    NOT v_result.success
      AND v_result.error_code = 'DOCTOR_ALREADY_IN_PROGRESS'
      AND v_status = 'checked_in',
    COALESCE(v_result.error_code, '<null>') || '; status=' || COALESCE(v_status, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM appointment_queue_qa_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM appointment_queue_qa_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'appointment_queue_qa: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
