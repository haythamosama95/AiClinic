-- Bootstrap RPC verification for US5 (organization + first branch).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/bootstrap_rpc.sql

BEGIN;

CREATE TEMP TABLE bootstrap_rpc_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_non_bootstrap_user uuid := 'e0000000-0000-4000-8000-0000000000a1';
  v_non_bootstrap_staff uuid := 'f0000000-0000-4000-8000-0000000000a1';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_assignment_count int;
  v_claims jsonb;
  v_setup_required text;
BEGIN
  -- Isolate from prior suite scripts (e.g. jwt_claims_contract) that may create an org.
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.audit_log;
  DELETE FROM public.patients;
  DELETE FROM public.branches;
  DELETE FROM public.organizations;

  -- Ensure a non-bootstrap administrator exists for denial tests.
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (
    v_non_bootstrap_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'bootstrap-deny',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES (
    v_non_bootstrap_staff,
    v_non_bootstrap_user,
    'Non Bootstrap Admin',
    'administrator',
    false,
    v_non_bootstrap_user,
    v_non_bootstrap_user
  )
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  -- Trivial: whitespace-only organization name is rejected.
  v_result := public.bootstrap_create_organization('   ');
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'org_empty_name_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>') || ': ' || COALESCE(v_result.error_message, '')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Advanced: non-bootstrap administrator cannot create organization.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_non_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.bootstrap_create_organization('Denied Org');
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'non_bootstrap_admin_denied_org',
    NOT v_result.success AND v_result.error_code = 'NOT_BOOTSTRAP_ADMIN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  -- Corner case: second organization attempt when one already exists.
  IF auth_internal.organization_exists() THEN
    v_result := public.bootstrap_create_organization('Second Org Attempt');
    PERFORM set_config('role', 'postgres', true);
    INSERT INTO bootstrap_rpc_results VALUES (
      'org_second_create_blocked',
      NOT v_result.success AND v_result.error_code = 'ORG_ALREADY_EXISTS',
      COALESCE(v_result.error_code, '<null>')
    );
    PERFORM set_config('role', 'authenticated', true);
  ELSE
    PERFORM set_config('role', 'postgres', true);
    INSERT INTO bootstrap_rpc_results VALUES (
      'org_second_create_blocked',
      true,
      'skipped — no organization present to test duplicate guard'
    );
    PERFORM set_config('role', 'authenticated', true);
  END IF;

  -- Happy path: reset installation org/branch rows, then bootstrap org + branch.
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id NOT IN (v_bootstrap_staff, v_non_bootstrap_staff);
  DELETE FROM public.audit_log;
  DELETE FROM public.patients;
  DELETE FROM public.branches;
  DELETE FROM public.organizations;
  DELETE FROM auth.users
  WHERE email LIKE 'owner-%'
     OR email IN ('reception', 'owner-one', 'owner-two');

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('  Sunrise Clinic  ', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'org_happy_path_creates_single_org',
    v_result.success AND v_org_id IS NOT NULL,
    'success=' || v_result.success::text || ' org_id=' || COALESCE(v_org_id::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'org_name_trimmed',
    EXISTS (
      SELECT 1
      FROM public.organizations o
      WHERE o.id = v_org_id AND o.name = 'Sunrise Clinic'
    ),
    'stored name must be trimmed'
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.bootstrap_create_organization('Duplicate Org');
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'org_duplicate_immediately_blocked',
    NOT v_result.success AND v_result.error_code = 'ORG_ALREADY_EXISTS',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: branch before valid organization id.
  v_result := public.bootstrap_create_branch(
    '00000000-0000-0000-0000-000000000099',
    'Ghost Branch'
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'branch_unknown_org_rejected',
    NOT v_result.success AND v_result.error_code = 'ORG_NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.bootstrap_create_branch(v_org_id, '   ');
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'branch_empty_name_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.bootstrap_create_branch(
    v_org_id,
    'Main Street',
    '123 Main St',
    '+1-555-0100',
    'MAIN',
    'https://maps.example/main'
  );
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'branch_happy_path_creates_branch',
    v_result.success AND v_branch_id IS NOT NULL,
    'branch_id=' || COALESCE(v_branch_id::text, '<null>')
  );
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*)::int
  INTO v_assignment_count
  FROM public.staff_branch_assignments sba
  WHERE sba.staff_member_id = v_bootstrap_staff
    AND sba.branch_id = v_branch_id
    AND sba.is_primary = true
    AND sba.is_deleted = false;

  INSERT INTO bootstrap_rpc_results VALUES (
'branch_assigns_bootstrap_admin_primary',
    v_assignment_count = 1,
    'assignments=' || v_assignment_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user);
  v_setup_required := v_claims ->> 'setup_required';
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'claims_setup_required_false_after_bootstrap',
    v_setup_required = 'false',
    'setup_required=' || COALESCE(v_setup_required, '<null>') || ' org=' || COALESCE(v_claims ->> 'organization_id', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'claims_include_branch_ids_after_bootstrap',
    COALESCE(v_claims ->> 'branch_ids', '') <> '',
    'branch_ids=' || COALESCE(v_claims ->> 'branch_ids', '<empty>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Advanced: optional branch fields stored trimmed / null.
PERFORM set_config('role', 'postgres', true);
  INSERT INTO bootstrap_rpc_results VALUES (
'branch_optional_fields_persisted',
    EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = v_branch_id
        AND b.code = 'MAIN'
        AND b.address = '123 Main St'
        AND b.phone = '+1-555-0100'
        AND b.maps_url = 'https://maps.example/main'
    ),
    'branch metadata row check'
  );
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_failures FROM bootstrap_rpc_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'bootstrap_rpc failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM bootstrap_rpc_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM bootstrap_rpc_results ORDER BY test_name;
