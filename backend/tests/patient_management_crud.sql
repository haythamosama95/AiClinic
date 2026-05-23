-- V1-3 patient management RPC verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_management_crud.sql

BEGIN;

CREATE TEMP TABLE patient_crud_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1000000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b1000000-0000-4000-8000-000000000101';
  v_receptionist_user uuid := 'a1000000-0000-4000-8000-000000000102';
  v_receptionist_staff uuid := 'b1000000-0000-4000-8000-000000000102';
  v_lab_user uuid := 'a1000000-0000-4000-8000-000000000103';
  v_lab_staff uuid := 'b1000000-0000-4000-8000-000000000103';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_branch_second uuid;
  v_patient_main uuid;
  v_patient_second uuid;
  v_updated_at timestamptz;
  v_total int;
  v_items jsonb;
  v_audit_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.patients;
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id NOT IN (v_bootstrap_staff);
  DELETE FROM public.audit_log;
  DELETE FROM public.branches;
  DELETE FROM public.organizations;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_receptionist_user, v_lab_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v13-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_receptionist_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v13-reception',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v13-lab',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V13 Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Second', NULL, NULL, 'SEC', NULL);
  v_branch_second := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'owner', false, v_bootstrap_user, v_bootstrap_user),
    (v_receptionist_staff, v_receptionist_user, 'Reception', 'receptionist', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Lab Tech', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_main, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_receptionist_staff), (v_lab_staff)) AS s(id);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_owner_staff, v_branch_second, false, v_bootstrap_user, v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text || ',' || v_branch_second::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  -- Trivial: blank name rejected on create.
  v_result := public.create_patient(v_branch_main, '   ', NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'create_rejects_blank_name',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: invalid phone length.
  v_result := public.create_patient(v_branch_main, 'Test Patient', '123', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'create_rejects_short_phone',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: future date of birth.
  v_result := public.create_patient(
    v_branch_main,
    'Future Baby',
    NULL,
    (current_date + 1),
    NULL,
    NULL,
    NULL,
    false
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'create_rejects_future_dob',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Register patient at main branch.
  v_result := public.create_patient(
    v_branch_main,
    'Ahmed Hassan',
    '+20 100 555 1234',
    '1990-05-15'::date,
    'male',
    'NAT-001',
    'Notes',
    false
  );
  v_patient_main := (v_result.data ->> 'patient_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'create_patient_success',
    v_result.success AND v_patient_main IS NOT NULL,
    COALESCE(v_result.error_code, v_patient_main::text)
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.record_id = v_patient_main AND al.action = 'patient.create';
  INSERT INTO patient_crud_results VALUES (
    'create_writes_audit_log',
    v_audit_count = 1,
    'count=' || v_audit_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- National ID hard block for duplicate.
  v_result := public.create_patient(
    v_branch_main,
    'Another Person',
    NULL,
    NULL,
    NULL,
    'nat-001',
    NULL,
    false
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'create_blocks_duplicate_national_id',
    NOT v_result.success AND v_result.error_code = 'NATIONAL_ID_EXISTS',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Duplicate advisory (phone) without acknowledge.
  v_result := public.create_patient(
    v_branch_main,
    'Different Name',
    '201005551234',
    NULL,
    NULL,
    NULL,
    NULL,
    false
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'create_duplicate_warning_phone',
    NOT v_result.success
      AND v_result.error_code = 'DUPLICATE_WARNING'
      AND jsonb_array_length(COALESCE(v_result.data -> 'candidates', '[]'::jsonb)) >= 1,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Proceed after duplicate acknowledge.
  v_result := public.create_patient(
    v_branch_main,
    'Different Name',
    '201005551234',
    NULL,
    NULL,
    NULL,
    NULL,
    true
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'create_with_duplicate_acknowledge',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Register at second branch for scope tests.
  v_result := public.create_patient(v_branch_second, 'Branch Two Patient', '2099887766', NULL, NULL, NULL, NULL, false);
  v_patient_second := (v_result.data ->> 'patient_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'create_at_second_branch',
    v_result.success AND v_patient_second IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Branch scope search returns only main branch patients by default filter.
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_branch_scope_filters',
    v_result.success
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_main
      )
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_second
      ),
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Organization scope includes both branches.
  v_result := public.search_patients(NULL, 'organization', NULL, 25, 0);
  v_total := (v_result.data ->> 'total_count')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_organization_scope_includes_all_branches',
    v_result.success AND v_total >= 3,
    'total=' || v_total::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Name contains search (min 3 chars).
  v_result := public.search_patients('ahm', 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_name_contains',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(v_result.data -> 'items', '[]'::jsonb)) item
        WHERE lower(item ->> 'full_name') LIKE '%ahm%'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Name search too short.
  v_result := public.search_patients('ab', 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_name_too_short_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Phone prefix search (min 2 digits).
  v_result := public.search_patients('2010', 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_phone_prefix',
    v_result.success
      AND jsonb_array_length(COALESCE(v_result.data -> 'items', '[]'::jsonb)) >= 1,
    COALESCE(v_result.error_code, 'count=0')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Phone prefix too short.
  v_result := public.search_patients('2', 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_phone_too_short_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_patient returns profile.
  v_result := public.get_patient(v_patient_main);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'get_patient_success',
    v_result.success AND (v_result.data ->> 'full_name') = 'Ahmed Hassan',
    COALESCE(v_result.error_code, v_result.data ->> 'full_name')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_patient(v_patient_main);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;

  -- Cross-branch edit (patient registered at main, still editable).
  v_result := public.update_patient(
    v_patient_main,
    'Ahmed Hassan Updated',
    v_updated_at,
    '209911112233',
    '1990-05-15'::date,
    'male',
    'NAT-001',
    'Updated notes',
    true
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'update_patient_cross_branch_same_org',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_patient(v_patient_main);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;

  -- Stale update rejected.
  v_result := public.update_patient(
    v_patient_main,
    'Stale Name',
    v_updated_at - interval '1 hour',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    false
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'update_stale_patient_rejected',
    NOT v_result.success AND v_result.error_code = 'STALE_PATIENT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Archive patient.
  v_result := public.archive_patient(v_patient_main);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'archive_patient_success',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );

  INSERT INTO patient_crud_results VALUES (
    'archive_sets_is_deleted',
    (SELECT is_deleted FROM public.patients p WHERE p.id = v_patient_main),
    'is_deleted flag'
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Archived patient excluded from search.
  v_result := public.search_patients('Ahmed', 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_excludes_archived',
    v_result.success
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(v_result.data -> 'items', '[]'::jsonb)) item
        WHERE (item ->> 'id')::uuid = v_patient_main
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_patient denies archived in normal flow.
  v_result := public.get_patient(v_patient_main);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'get_patient_archived_denied',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ARCHIVED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- lab_staff view-only: cannot create.
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
  v_result := public.create_patient(v_branch_main, 'Lab Attempt', NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'lab_staff_create_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- lab_staff can search/view.
  v_result := public.search_patients(NULL, 'branch', v_branch_main, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'lab_staff_search_allowed',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Invalid scope value.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.search_patients(NULL, 'everywhere', v_branch_main, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_invalid_scope_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Branch scope without branch id.
  v_result := public.search_patients(NULL, 'branch', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_crud_results VALUES (
    'search_branch_scope_requires_branch',
    NOT v_result.success AND v_result.error_code = 'BRANCH_REQUIRED',
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
  FROM patient_crud_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM patient_crud_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'patient_management_crud: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
