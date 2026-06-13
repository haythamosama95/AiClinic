-- V1-3 patient management: search_patients filter/sort tests (QA SP-BE-007..014).
-- Covers p_last_visit_filter, p_sort_field, response schema extensions, permission gate.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_management_search_filters.sql

BEGIN;

CREATE TEMP TABLE patient_search_filter_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.insert_completed_visit(
  p_branch_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_user uuid,
  p_visit_date date
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_appt_id uuid := gen_random_uuid();
  v_visit_id uuid := gen_random_uuid();
  v_start timestamptz;
BEGIN
  v_start := p_visit_date::timestamptz + interval '10 hours';
  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES (
    v_appt_id,
    p_branch_id,
    p_patient_id,
    p_doctor_id,
    v_start,
    v_start + interval '30 minutes',
    'planned',
    'completed',
    p_user,
    p_user
  );
  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES (
    v_visit_id,
    p_branch_id,
    v_appt_id,
    p_patient_id,
    p_doctor_id,
    p_visit_date,
    'completed',
    p_user,
    p_user
  );
  RETURN v_visit_id;
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a5000000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b5000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'a5000000-0000-4000-8000-000000000002';
  v_doctor_staff uuid := 'b5000000-0000-4000-8000-000000000002';
  v_lab_user uuid := 'a5000000-0000-4000-8000-000000000003';
  v_lab_staff uuid := 'b5000000-0000-4000-8000-000000000003';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_never uuid;
  v_patient_recent uuid;
  v_patient_old uuid;
  v_patient_zulu uuid;
  v_patient_alpha uuid;
  v_items jsonb;
  v_total int;
  v_item jsonb;
  v_first_name text;
  v_ids uuid[];
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user, v_lab_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'filter-owner',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'filter-doctor',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'filter-lab',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.bootstrap_create_organization('Filter Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'FM', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Filter Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Filter Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Filter Lab', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_main, false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_branch_main, 'Never Visited', '201500000001', NULL, NULL, NULL, NULL, false);
  v_patient_never := (v_result.data ->> 'patient_id')::uuid;

  v_result := public.create_patient(v_branch_main, 'Recent Visit', '201500000002', NULL, NULL, NULL, NULL, false);
  v_patient_recent := (v_result.data ->> 'patient_id')::uuid;

  v_result := public.create_patient(v_branch_main, 'Old Visit', '201500000003', NULL, NULL, NULL, NULL, false);
  v_patient_old := (v_result.data ->> 'patient_id')::uuid;

  v_result := public.create_patient(v_branch_main, 'Zulu Sort', '201500000004', NULL, NULL, NULL, NULL, false);
  v_patient_zulu := (v_result.data ->> 'patient_id')::uuid;

  v_result := public.create_patient(v_branch_main, 'Alpha Sort', '201500000005', NULL, NULL, NULL, NULL, false);
  v_patient_alpha := (v_result.data ->> 'patient_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  PERFORM pg_temp.insert_completed_visit(
    v_branch_main, v_patient_recent, v_doctor_staff, v_owner_user, CURRENT_DATE - 10
  );
  PERFORM pg_temp.insert_completed_visit(
    v_branch_main, v_patient_old, v_doctor_staff, v_owner_user, CURRENT_DATE - 100
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SP-BE-001: permission denied without patients.view
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.roles_permissions
  SET is_granted = false, updated_at = now()
  WHERE role = 'lab_staff' AND permission_key = 'patients.view' AND is_deleted = false;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_lab_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_lab_staff::text,
      'staff_role', 'lab_staff',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_001_search_patients_permission_denied',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  UPDATE public.roles_permissions
  SET is_granted = true, updated_at = now()
  WHERE role = 'lab_staff' AND permission_key = 'patients.view' AND is_deleted = false;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  -- SP-BE-007: last_visit_filter never
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 100, 0, 'never', 'name_asc');
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_total := (v_result.data ->> 'total_count')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_007_last_visit_filter_never',
    v_result.success
      AND v_total >= 1
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_never
      )
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_recent
      ),
    'total=' || v_total::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SP-BE-008: last_visit_filter last_30_days
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 100, 0, 'last_30_days', 'name_asc');
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_008_last_visit_filter_30_days',
    v_result.success
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_recent
      )
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_old
      ),
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SP-BE-009: last_visit_filter over_90_days
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 100, 0, 'over_90_days', 'name_asc');
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_009_last_visit_filter_over_90_days',
    v_result.success
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_old
      )
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_never
      ),
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SP-BE-010: sort name_desc
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 100, 0, 'any', 'name_desc');
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_first_name := v_items -> 0 ->> 'full_name';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_010_sort_name_desc',
    v_result.success
      AND v_first_name = 'Zulu Sort',
    'first=' || COALESCE(v_first_name, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SP-BE-011: invalid filter value
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 25, 0, 'invalid', 'name_asc');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_011_invalid_last_visit_filter',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SP-BE-014: response schema includes last_visit_at and next_appointment_at
  v_result := public.search_patients('Recent', 'branch', v_branch_main, 25, 0, 'any', 'name_asc');
  v_item := COALESCE(v_result.data -> 'items', '[]'::jsonb) -> 0;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_014_response_has_last_visit_at',
    v_item ? 'last_visit_at',
    'has=' || (v_item ? 'last_visit_at')::text
  );
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_014_response_has_next_appointment_at',
    v_item ? 'next_appointment_at',
    'has=' || (v_item ? 'next_appointment_at')::text
  );
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_014_recent_patient_has_last_visit_at_value',
    (v_item ->> 'last_visit_at') IS NOT NULL,
    'last_visit_at=' || COALESCE(v_item ->> 'last_visit_at', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Filter + sort combo: never + name asc includes never patient first among never-only set
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 100, 0, 'never', 'name_asc');
  v_total := (v_result.data ->> 'total_count')::int;
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 100, 50, 'never', 'name_asc');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_filter_results VALUES (
    'SP_BE_filter_sort_pagination_count_consistent',
    v_result.success AND (v_result.data ->> 'total_count')::int = v_total,
    'total=' || COALESCE(v_result.data ->> 'total_count', '<null>')
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
  SELECT count(*)::int INTO v_failed FROM patient_search_filter_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM patient_search_filter_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'patient_management_search_filters: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
