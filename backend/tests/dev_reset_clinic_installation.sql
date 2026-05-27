-- Dev reset RPC: bootstrap admin can wipe org/branch rows for another bootstrap run.
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/dev_reset_clinic_installation.sql

BEGIN;

CREATE TEMP TABLE dev_reset_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_passed boolean;
  v_detail text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.staff_branch_assignments WHERE true;
  DELETE FROM public.audit_log WHERE organization_id IS NOT NULL;
  DELETE FROM public.app_settings WHERE true;
  DELETE FROM public.subscription_cache WHERE true;
  DELETE FROM public.patients WHERE true;
  DELETE FROM public.branches WHERE true;
  DELETE FROM public.organizations WHERE true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Reset Test Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_passed := v_result.success AND v_org_id IS NOT NULL;
  v_detail := COALESCE(v_result.error_code, 'ok');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO dev_reset_results VALUES ('seed_org_for_reset', v_passed, v_detail);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.dev_reset_clinic_installation();
  v_passed := v_result.success;
  v_detail := COALESCE(v_result.error_code, 'ok') || ' orgs=' || COALESCE(v_result.data ->> 'organizations_deleted', '?');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO dev_reset_results VALUES ('dev_reset_returns_success', v_passed, v_detail);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_passed := NOT auth_internal.organization_exists();
  v_detail := 'organization_exists=' || auth_internal.organization_exists()::text;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO dev_reset_results VALUES ('dev_reset_clears_organization', v_passed, v_detail);

  v_passed := EXISTS (
    SELECT 1
    FROM public.audit_log al
    WHERE al.action = 'organization.dev_reset'
  );
  v_detail := 'audit row for organization.dev_reset';

  INSERT INTO dev_reset_results VALUES ('dev_reset_audit_logged', v_passed, v_detail);
END;
$$;

-- Reset must delete patient rows before branches (FK on patients.branch_id).
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_passed boolean;
  v_detail text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.staff_branch_assignments WHERE true;
  DELETE FROM public.audit_log WHERE organization_id IS NOT NULL;
  DELETE FROM public.app_settings WHERE true;
  DELETE FROM public.subscription_cache WHERE true;
  DELETE FROM public.patients WHERE true;
  DELETE FROM public.branches WHERE true;
  DELETE FROM public.organizations WHERE true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Reset With Patients', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;

  v_result := public.bootstrap_create_branch(
    v_org_id,
    'Patient Branch',
    '1 Main St',
    '555',
    'PB1',
    'https://maps.example'
  );
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.patients (branch_id, organization_id, full_name, phone, gender, created_by)
  VALUES (v_branch_id, v_org_id, 'Reset Patient', '01000000001', 'male', v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.dev_reset_clinic_installation();
  v_passed := v_result.success
    AND COALESCE((v_result.data ->> 'patients_deleted')::int, 0) >= 1
    AND NOT auth_internal.organization_exists();

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO dev_reset_results VALUES (
    'dev_reset_deletes_patients_before_branches',
    v_passed,
    COALESCE(v_result.error_code, 'patients_deleted=' || COALESCE(v_result.data ->> 'patients_deleted', '?'))
  );
END;
$$;

-- Non-bootstrap staff must not reset installation (public wrapper is SECURITY INVOKER).
DO $$
DECLARE
  v_non_bootstrap_user uuid := 'f1000000-0000-4000-8000-000000000f04';
  v_non_bootstrap_staff uuid := 'f2000000-0000-4000-8000-000000000f05';
  v_result public.rpc_result;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (
    v_non_bootstrap_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'nonbootstrap',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_active, is_bootstrap_admin, created_by, updated_by)
  VALUES (
    v_non_bootstrap_staff,
    v_non_bootstrap_user,
    'Non Bootstrap Admin',
    'administrator',
    true,
    false,
    'a0000000-0000-4000-8000-000000000001',
    'a0000000-0000-4000-8000-000000000001'
  )
  ON CONFLICT (id) DO UPDATE
  SET is_bootstrap_admin = false, is_active = true, is_deleted = false;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_non_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.dev_reset_clinic_installation();
  v_passed := NOT v_result.success AND v_result.error_code = 'NOT_BOOTSTRAP_ADMIN';

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO dev_reset_results VALUES (
    'non_bootstrap_denied_dev_reset',
    v_passed,
    COALESCE(v_result.error_code, 'unexpected success')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM dev_reset_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'dev_reset_clinic_installation failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM dev_reset_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM dev_reset_results ORDER BY test_name;
