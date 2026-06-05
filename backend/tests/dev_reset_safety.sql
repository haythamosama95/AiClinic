-- Fix 25: Dev reset safety test — environment guard and permission checks.
-- Verifies that dev_reset_clinic_installation respects the app.environment setting
-- and blocks non-bootstrap users.
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/dev_reset_safety.sql

BEGIN;

CREATE TEMP TABLE dev_reset_safety_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

-- Test 1: Non-bootstrap user is denied even in dev environment
DO $$
DECLARE
  v_non_bootstrap_user uuid := 'f1000000-0000-4000-8000-00000000aa01';
  v_non_bootstrap_staff uuid := 'f2000000-0000-4000-8000-00000000aa02';
  v_result public.rpc_result;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  -- Ensure app.environment is set to development
  PERFORM set_config('app.environment', 'development', true);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (
    v_non_bootstrap_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'safety-nonboot',
    extensions.crypt('test-pass1', extensions.gen_salt('bf')),
    now(), now(), now()
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_active, is_bootstrap_admin, created_by, updated_by)
  VALUES (
    v_non_bootstrap_staff,
    v_non_bootstrap_user,
    'Safety Non Bootstrap',
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

  INSERT INTO dev_reset_safety_results VALUES (
    'non_bootstrap_denied_in_dev_environment',
    v_passed,
    'error_code=' || COALESCE(v_result.error_code, 'unexpected: ' || v_result.success::text)
  );
END;
$$;

-- Test 2: Bootstrap admin is denied in production environment
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  -- Simulate production environment
  PERFORM set_config('app.environment', 'production', true);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.dev_reset_clinic_installation();
  v_passed := NOT v_result.success AND v_result.error_code = 'FORBIDDEN';

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO dev_reset_safety_results VALUES (
    'bootstrap_admin_denied_in_production',
    v_passed,
    'error_code=' || COALESCE(v_result.error_code, 'unexpected: ' || v_result.success::text)
  );
END;
$$;

-- Test 3: Bootstrap admin is denied when app.environment is NULL (unset)
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  -- Simulate missing environment setting (production default)
  PERFORM set_config('app.environment', '', true);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.dev_reset_clinic_installation();
  v_passed := NOT v_result.success AND v_result.error_code = 'FORBIDDEN';

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO dev_reset_safety_results VALUES (
    'bootstrap_admin_denied_when_env_unset',
    v_passed,
    'error_code=' || COALESCE(v_result.error_code, 'unexpected: ' || v_result.success::text)
  );
END;
$$;

-- Test 4: Bootstrap admin succeeds in development environment
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_org_id uuid;
  v_result public.rpc_result;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  -- Set to development
  PERFORM set_config('app.environment', 'development', true);

  -- Ensure there's something to reset (FK-safe cleanup order)
  DELETE FROM public.patients WHERE true;
  DELETE FROM public.staff_branch_assignments WHERE true;
  DELETE FROM public.audit_log WHERE true;
  DELETE FROM public.branches WHERE true;
  PERFORM auth_internal.delete_billing_dependents();
  DELETE FROM public.organizations WHERE true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  -- Create an org so there's something to reset
  v_result := public.bootstrap_create_organization('Safety Org', '{}'::jsonb, NULL, 'EGP', 'UTC');

  -- Now reset
  v_result := public.dev_reset_clinic_installation();
  v_passed := v_result.success;

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO dev_reset_safety_results VALUES (
    'bootstrap_admin_allowed_in_development',
    v_passed,
    CASE WHEN v_passed THEN 'reset succeeded' ELSE 'error_code=' || COALESCE(v_result.error_code, '?') END
  );
END;
$$;

-- Test 5: Bootstrap admin succeeds in 'local' environment
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'local', true);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.dev_reset_clinic_installation();
  v_passed := v_result.success;

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO dev_reset_safety_results VALUES (
    'bootstrap_admin_allowed_in_local',
    v_passed,
    CASE WHEN v_passed THEN 'reset succeeded' ELSE 'error_code=' || COALESCE(v_result.error_code, '?') END
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM dev_reset_safety_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'dev_reset_safety failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM dev_reset_safety_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM dev_reset_safety_results ORDER BY test_name;
