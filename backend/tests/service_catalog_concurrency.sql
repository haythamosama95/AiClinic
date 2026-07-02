-- Service Catalog (015) US3: optimistic concurrency on branch configuration.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/service_catalog_concurrency.sql

BEGIN;

CREATE TEMP TABLE service_catalog_concurrency_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.service_catalog_concurrency_record(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO service_catalog_concurrency_results (test_name, passed, detail)
  VALUES (p_name, p_passed, p_detail);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_administrator_jwt(
  p_user uuid,
  p_staff uuid,
  p_org uuid,
  p_branches text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user::text,
      'role', 'authenticated',
      'organization_id', p_org::text,
      'branch_ids', p_branches,
      'staff_member_id', p_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
END;
$$;

DO $$
DECLARE
  v_org_id uuid := 'c2800000-0000-4000-8000-0000000000b1';
  v_branch_a uuid := 'd2800000-0000-4000-8000-0000000000b1';
  v_user_admin uuid := 'e2800000-0000-4000-8000-0000000000b1';
  v_staff_admin uuid := 'f2800000-0000-4000-8000-0000000000b1';
  v_service_id uuid;
  v_sb_updated_at timestamptz;
  v_stale_updated_at timestamptz := '2000-01-01 00:00:00+00'::timestamptz;
  v_result public.rpc_result;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log WHERE organization_id = v_org_id;
  DELETE FROM public.service_branches
  WHERE service_id IN (SELECT id FROM public.services WHERE organization_id = v_org_id);
  DELETE FROM public.services WHERE organization_id = v_org_id;
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id = v_staff_admin;
  DELETE FROM public.staff_members WHERE id = v_staff_admin;
  DELETE FROM public.branches WHERE organization_id = v_org_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM auth.users WHERE id = v_user_admin;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (
    v_user_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'svc-concurrency-admin', extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_org_id, 'Service Concurrency Org', v_user_admin, v_user_admin);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES (v_branch_a, v_org_id, 'Branch A', 'SCA', v_user_admin, v_user_admin);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES (v_staff_admin, v_user_admin, 'Admin', 'administrator', v_user_admin, v_user_admin);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, created_by, updated_by)
  VALUES (v_staff_admin, v_branch_a, v_user_admin, v_user_admin);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_administrator_jwt(v_user_admin, v_staff_admin, v_org_id, v_branch_a::text);

  v_result := public.create_service('Concurrency Service', 100.00, 'active', false, ARRAY[v_branch_a]);
  v_service_id := (v_result.data ->> 'service_id')::uuid;

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_id AND sb.branch_id = v_branch_a;

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.service_branches
  SET updated_at = '2099-01-01 00:00:00+00'::timestamptz
  WHERE service_id = v_service_id AND branch_id = v_branch_a;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.configure_service_branch(
    v_service_id, v_branch_a, v_stale_updated_at, 'active', 90.00
  );
  PERFORM pg_temp.service_catalog_concurrency_record(
    'stale_service_branch_rejects_configure',
    NOT v_result.success AND v_result.error_code = 'STALE_SERVICE_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_id AND sb.branch_id = v_branch_a;

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.service_branches
  SET updated_at = '2099-01-02 00:00:00+00'::timestamptz
  WHERE service_id = v_service_id AND branch_id = v_branch_a;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.set_service_promotion(
    v_service_id, v_branch_a, v_stale_updated_at, 80.00, current_date, current_date + 7
  );
  PERFORM pg_temp.service_catalog_concurrency_record(
    'stale_service_branch_rejects_promotion',
    NOT v_result.success AND v_result.error_code = 'STALE_SERVICE_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
  v_row record;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*)::int
  INTO v_failures
  FROM service_catalog_concurrency_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    FOR v_row IN
      SELECT test_name, detail
      FROM service_catalog_concurrency_results
      WHERE NOT passed
      ORDER BY test_name
    LOOP
      RAISE NOTICE 'FAIL %: %', v_row.test_name, v_row.detail;
    END LOOP;
    RAISE EXCEPTION 'service_catalog_concurrency.sql: % test(s) failed', v_failures;
  END IF;
END;
$$;

ROLLBACK;
