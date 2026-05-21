-- RLS isolation verification for V1-1 auth/RBAC tables.
-- Run against a database with migrations applied:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/rls_isolation.sql

BEGIN;

CREATE TEMP TABLE rls_test_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_org_a uuid := 'c0000000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c0000000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd0000000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd0000000-0000-4000-8000-0000000000b2';
  v_user_a uuid := 'e0000000-0000-4000-8000-0000000000a1';
  v_user_b uuid := 'e0000000-0000-4000-8000-0000000000b2';
  v_staff_a uuid := 'f0000000-0000-4000-8000-0000000000a1';
  v_staff_b uuid := 'f0000000-0000-4000-8000-0000000000b2';
  v_visible int;
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (
      v_user_a,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'rls-a',
      extensions.crypt('test-password-a', extensions.gen_salt('bf')),
      now(),
      now(),
      now()
    ),
    (
      v_user_b,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'rls-b',
      extensions.crypt('test-password-b', extensions.gen_salt('bf')),
      now(),
      now(),
      now()
    )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Org A', v_user_a, v_user_a),
    (v_org_b, 'RLS Org B', v_user_b, v_user_b)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.branches (id, organization_id, name, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', v_user_a, v_user_a),
    (v_branch_b, v_org_b, 'Branch B', v_user_b, v_user_b)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_a, v_user_a, 'Staff A', 'administrator', v_user_a, v_user_a),
    (v_staff_b, v_user_b, 'Staff B', 'administrator', v_user_b, v_user_b)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_b, v_branch_b, true, v_user_b, v_user_b)
  ON CONFLICT (staff_member_id, branch_id) DO NOTHING;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name)
  VALUES
    (v_user_a, v_org_a, 'test.audit', 'organizations'),
    (v_user_b, v_org_b, 'test.audit', 'organizations');

  INSERT INTO public.app_settings (organization_id, branch_id, key, value_json, created_by, updated_by)
  VALUES
    (v_org_a, NULL, 'org_wide', '{"org":"a"}'::jsonb, v_user_a, v_user_a),
    (v_org_b, NULL, 'org_wide', '{"org":"b"}'::jsonb, v_user_b, v_user_b);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_a::text,
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int
  INTO v_visible
  FROM public.branches
  WHERE is_deleted = false;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO rls_test_results (test_name, passed, detail)
  VALUES (
    'branch_isolation_user_a',
    v_visible = 1,
    format('user A sees %s branch rows (expected 1)', v_visible)
  );

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_b::text,
      'role', 'authenticated',
      'organization_id', v_org_b::text,
      'branch_ids', v_branch_b::text,
      'staff_member_id', v_staff_b::text,
      'setup_required', false
    )::text,
    true
  );
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*)::int
  INTO v_visible
  FROM public.organizations
  WHERE is_deleted = false;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO rls_test_results (test_name, passed, detail)
  VALUES (
    'organization_isolation_user_b',
    v_visible = 1,
    format('user B sees %s organization rows (expected 1)', v_visible)
  );

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_b::text,
      'role', 'authenticated',
      'organization_id', v_org_b::text,
      'branch_ids', v_branch_b::text,
      'staff_member_id', v_staff_b::text,
      'setup_required', false
    )::text,
    true
  );
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*)::int
  INTO v_visible
  FROM public.branches b
  WHERE b.id = v_branch_a
    AND b.is_deleted = false;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO rls_test_results (test_name, passed, detail)
  VALUES (
    'cross_org_branch_denied_user_b',
    v_visible = 0,
    format('user B sees %s rows for org A branch (expected 0)', v_visible)
  );

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_b::text,
      'role', 'authenticated',
      'organization_id', v_org_b::text,
      'branch_ids', v_branch_b::text,
      'staff_member_id', v_staff_b::text,
      'setup_required', false
    )::text,
    true
  );
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*)::int
  INTO v_visible
  FROM public.audit_log
  WHERE organization_id = v_org_a;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO rls_test_results (test_name, passed, detail)
  VALUES (
    'audit_log_isolation_user_b',
    v_visible = 0,
    format('user B sees %s org A audit rows (expected 0)', v_visible)
  );

  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*)::int
  INTO v_visible
  FROM public.app_settings
  WHERE organization_id = v_org_a
    AND is_deleted = false;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO rls_test_results (test_name, passed, detail)
  VALUES (
    'app_settings_isolation_user_b',
    v_visible = 0,
    format('user B sees %s org A app_settings rows (expected 0)', v_visible)
  );
END;
$$;

DO $$
DECLARE
  v_failed int;
BEGIN
  SELECT count(*)::int
  INTO v_failed
  FROM rls_test_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'RLS isolation verification failed for % test(s)', v_failed;
  END IF;
END;
$$;

SELECT test_name, passed, detail
FROM rls_test_results
ORDER BY test_name;

ROLLBACK;
