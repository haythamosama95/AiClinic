-- Auth/RBAC extended coverage: JWT manipulation, auth_internal exposure,
-- missing claims, anon access denial, setup_required behavior, edge cases.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/auth_rbac_extended.sql

BEGIN;

CREATE TEMP TABLE auth_ext_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a5000000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b5000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'a5000000-0000-4000-8000-000000000002';
  v_doctor_staff uuid := 'b5000000-0000-4000-8000-000000000002';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_claims jsonb;
  v_claims_text text;
  v_exception_caught boolean;
BEGIN
  -- ===========================================================================
  -- FIXTURE SETUP
  -- ===========================================================================
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.patients;
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id NOT IN (v_bootstrap_staff);
  DELETE FROM public.audit_log;
  DELETE FROM public.branches;
  PERFORM auth_internal.delete_billing_dependents();
  DELETE FROM public.organizations;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'auth-ext-owner',
      extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'auth-ext-doctor',
      extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.bootstrap_create_organization('Auth Ext Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'AE', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Auth Owner', 'owner', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Auth Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user);

  -- ===========================================================================
  -- ANON ROLE: cannot access patient RPCs
  -- ===========================================================================

  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  v_exception_caught := false;
  BEGIN
    v_result := public.search_patients(NULL, 'organization', NULL, 25, 0);
  EXCEPTION WHEN OTHERS THEN
    v_exception_caught := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'anon_search_patients_denied',
    v_exception_caught OR (NOT v_result.success),
    CASE WHEN v_exception_caught THEN 'exception' ELSE COALESCE(v_result.error_code, 'success?!') END
  );

  PERFORM set_config('role', 'anon', true);
  v_exception_caught := false;
  BEGIN
    v_result := public.create_patient(v_branch_id, 'Anon Patient', '12345678', NULL, NULL, NULL, NULL, false);
  EXCEPTION WHEN OTHERS THEN
    v_exception_caught := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'anon_create_patient_denied',
    v_exception_caught OR (NOT v_result.success),
    CASE WHEN v_exception_caught THEN 'exception' ELSE COALESCE(v_result.error_code, 'success?!') END
  );

  PERFORM set_config('role', 'anon', true);
  v_exception_caught := false;
  BEGIN
    v_result := public.bootstrap_create_organization('Anon Org');
  EXCEPTION WHEN OTHERS THEN
    v_exception_caught := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'anon_bootstrap_create_org_denied',
    v_exception_caught OR (NOT v_result.success),
    CASE WHEN v_exception_caught THEN 'exception' ELSE COALESCE(v_result.error_code, 'success?!') END
  );

  -- ===========================================================================
  -- MISSING ORGANIZATION_ID IN JWT: RPCs that require org context
  -- ===========================================================================

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.search_patients(NULL, 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'missing_org_id_search_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.create_patient(v_branch_id, 'No Org', '12345678', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'missing_org_id_create_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- EMPTY BRANCH_IDS IN JWT: branch-scope search
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', '',
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.search_patients(NULL, 'branch', v_branch_id, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'empty_branch_ids_search_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- But org-scope should still work (doesn't need branch_ids).
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', '',
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.search_patients(NULL, 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'empty_branch_ids_org_scope_works',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- auth_internal.build_staff_claims: information disclosure
  -- (any authenticated user can call this on any UUID)
  -- ===========================================================================

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  v_exception_caught := false;
  BEGIN
    SELECT auth_internal.build_staff_claims(v_bootstrap_user)::text INTO v_claims_text;
  EXCEPTION WHEN OTHERS THEN
    v_exception_caught := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'auth_internal_build_claims_callable_by_authenticated',
    NOT v_exception_caught AND v_claims_text IS NOT NULL,
    CASE WHEN v_exception_caught THEN 'denied' ELSE 'callable (info leak)' END
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- dev_reset_clinic_installation: non-bootstrap user denied
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.dev_reset_clinic_installation();
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'dev_reset_non_bootstrap_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_BOOTSTRAP_ADMIN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- JWT HELPER FUNCTIONS: accessible to authenticated
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'jwt_organization_id_returns_correct_value',
    public.jwt_organization_id() = v_org_id,
    'org=' || COALESCE(public.jwt_organization_id()::text, '<null>')
  );

  INSERT INTO auth_ext_results VALUES (
    'jwt_staff_member_id_returns_correct_value',
    public.jwt_staff_member_id() = v_owner_staff,
    'staff=' || COALESCE(public.jwt_staff_member_id()::text, '<null>')
  );

  INSERT INTO auth_ext_results VALUES (
    'jwt_staff_role_returns_correct_value',
    public.jwt_staff_role() = 'owner',
    'role=' || COALESCE(public.jwt_staff_role()::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- BOOTSTRAP: duplicate organization creation rejected
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.bootstrap_create_organization('Should Fail Org');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'bootstrap_duplicate_org_rejected',
    NOT v_result.success AND v_result.error_code = 'ORG_ALREADY_EXISTS',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- CREATE STAFF: non-admin/owner cannot create staff
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_doctor_staff::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.create_staff_account(
    'doctor-create-attempt',
    'password123',
    'Unauthorized Staff',
    'receptionist',
    ARRAY[v_branch_id]
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'doctor_create_staff_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- ADMIN RESET PASSWORD: empty password rejected
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.admin_reset_staff_password(v_owner_staff, '');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'admin_reset_empty_password_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- ADMIN RESET PASSWORD: unknown staff ID
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.admin_reset_staff_password('99999999-9999-4999-8999-999999999999', 'newpass123');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'admin_reset_unknown_staff_rejected',
    NOT v_result.success AND v_result.error_code = 'STAFF_NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- BOOTSTRAP CREATE BRANCH: non-bootstrap user denied
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.bootstrap_create_branch(v_org_id, 'Hacked Branch', NULL, NULL, 'HACK', NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'bootstrap_branch_non_bootstrap_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_BOOTSTRAP_ADMIN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- RPC CONTRACT: function signatures exist with correct parameters
  -- ===========================================================================

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_ext_results VALUES (
    'rpc_search_patients_exists',
    EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'search_patients' AND p.pronamespace = 'public'::regnamespace),
    'exists'
  );
  INSERT INTO auth_ext_results VALUES (
    'rpc_get_patient_exists',
    EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'get_patient' AND p.pronamespace = 'public'::regnamespace),
    'exists'
  );
  INSERT INTO auth_ext_results VALUES (
    'rpc_create_patient_exists',
    EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'create_patient' AND p.pronamespace = 'public'::regnamespace),
    'exists'
  );
  INSERT INTO auth_ext_results VALUES (
    'rpc_update_patient_exists',
    EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'update_patient' AND p.pronamespace = 'public'::regnamespace),
    'exists'
  );
  INSERT INTO auth_ext_results VALUES (
    'rpc_archive_patient_exists',
    EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'archive_patient' AND p.pronamespace = 'public'::regnamespace),
    'exists'
  );
  INSERT INTO auth_ext_results VALUES (
    'rpc_check_patient_duplicates_exists',
    EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'check_patient_duplicates' AND p.pronamespace = 'public'::regnamespace),
    'exists'
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM auth_ext_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM auth_ext_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'auth_rbac_extended: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
