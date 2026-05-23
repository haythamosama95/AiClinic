-- JWT custom claims contract for auth Phase 1-4 (staff_role regression).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/jwt_claims_contract.sql

BEGIN;

CREATE TEMP TABLE jwt_claims_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff_id uuid := 'b0000000-0000-4000-8000-000000000001';
  v_claims jsonb;
  v_staff_role text;
  v_setup_required text;
  v_bootstrap_result public.rpc_result;
BEGIN
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id <> v_bootstrap_staff_id;
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE email IN ('owner-one', 'owner-two', 'reception')
     OR email LIKE 'us6-%';
  DELETE FROM public.subscription_cache;
  DELETE FROM public.patients;
  DELETE FROM public.branches;
  DELETE FROM public.organizations;

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user_id);
  v_staff_role := v_claims ->> 'staff_role';
  v_setup_required := v_claims ->> 'setup_required';

  INSERT INTO jwt_claims_results (test_name, passed, detail)
  VALUES (
    'build_staff_claims_includes_staff_role',
    v_staff_role IS NOT NULL AND v_staff_role <> '',
    'staff_role=' || COALESCE(v_staff_role, '<null>')
  );

  INSERT INTO jwt_claims_results (test_name, passed, detail)
  VALUES (
    'build_staff_claims_no_job_title_as_role_key',
    NOT (v_claims ? 'role' AND (v_claims ->> 'role') IN ('owner', 'administrator', 'doctor', 'receptionist', 'lab_staff')),
    'keys=' || (SELECT string_agg(key, ',') FROM jsonb_object_keys(v_claims) AS key)
  );

  INSERT INTO jwt_claims_results (test_name, passed, detail)
  VALUES (
    'bootstrap_admin_setup_required_without_org',
    v_setup_required = 'true',
    'setup_required=' || COALESCE(v_setup_required, '<null>')
  );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user_id::text, 'role', 'authenticated')::text,
    true
  );

  v_bootstrap_result := public.bootstrap_create_organization(
    'Claims Org Test', '{}'::jsonb, NULL, 'EGP', 'UTC'
  );
  IF NOT v_bootstrap_result.success THEN
    RAISE EXCEPTION 'bootstrap_create_organization failed: %', v_bootstrap_result.error_code;
  END IF;

  PERFORM set_config('role', 'postgres', true);

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user_id);

  INSERT INTO jwt_claims_results (test_name, passed, detail)
  VALUES (
    'unassigned_staff_still_gets_organization_id',
    (v_claims ->> 'organization_id') IS NOT NULL
      AND (v_claims ->> 'organization_id') = (v_bootstrap_result.data ->> 'organization_id'),
    'organization_id=' || COALESCE(v_claims ->> 'organization_id', '<null>')
  );

  -- Decision 5 (T059): inactive branches must not appear in branch_ids claims.
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id = v_bootstrap_staff_id;

  INSERT INTO public.branches (id, organization_id, name, code, is_active, created_by, updated_by)
  VALUES (
    'c1000000-0000-4000-8000-000000000099',
    (v_bootstrap_result.data ->> 'organization_id')::uuid,
    'Inactive Only Branch',
    'INACT',
    false,
    v_bootstrap_user_id,
    v_bootstrap_user_id
  )
  ON CONFLICT (id) DO UPDATE SET is_active = false;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (
    v_bootstrap_staff_id,
    'c1000000-0000-4000-8000-000000000099',
    true,
    v_bootstrap_user_id,
    v_bootstrap_user_id
  )
  ON CONFLICT (staff_member_id, branch_id) DO NOTHING;

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user_id);

  INSERT INTO jwt_claims_results (test_name, passed, detail)
  VALUES (
    'build_staff_claims_excludes_inactive_branch',
    COALESCE(v_claims ->> 'branch_ids', '') = '',
    'branch_ids=' || COALESCE(v_claims ->> 'branch_ids', '<empty>')
  );

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user_id::text,
      'role', 'authenticated',
      'staff_role', v_staff_role
    )::text,
    true
  );

  INSERT INTO jwt_claims_results (test_name, passed, detail)
  VALUES (
    'jwt_staff_role_reads_staff_role_claim',
    public.jwt_staff_role()::text = v_staff_role,
    'jwt_staff_role=' || COALESCE(public.jwt_staff_role()::text, '<null>')
  );
END;
$$;

-- get_custom_claims(uuid) overload must not exist (ambiguous hook call regression).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'get_custom_claims'
      AND pg_get_function_identity_arguments(p.oid) = 'uuid'
  ) THEN
    INSERT INTO jwt_claims_results (test_name, passed, detail)
    VALUES ('get_custom_claims_uuid_overload_removed', false, 'uuid overload still present');
  ELSE
    INSERT INTO jwt_claims_results (test_name, passed, detail)
    VALUES ('get_custom_claims_uuid_overload_removed', true, 'only jsonb hook remains');
  END IF;
END;
$$;

-- Legacy fallback: jwt_staff_role reads old "role" claim when staff_role absent.
DO $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('role', 'doctor')::text,
    true
  );
  INSERT INTO jwt_claims_results (test_name, passed, detail)
  VALUES (
    'jwt_staff_role_legacy_role_fallback',
    public.jwt_staff_role()::text = 'doctor',
    'parsed=' || COALESCE(public.jwt_staff_role()::text, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM jwt_claims_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'jwt_claims_contract failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM jwt_claims_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM jwt_claims_results ORDER BY test_name;
