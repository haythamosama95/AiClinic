-- Service Catalog (015) US1: RLS denial verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/service_catalog_rls.sql

BEGIN;

CREATE TEMP TABLE service_catalog_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.service_catalog_rls_record(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO service_catalog_rls_results (test_name, passed, detail)
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
  v_org_a uuid := 'c2710000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c2710000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd2710000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd2710000-0000-4000-8000-0000000000b2';
  v_user_admin_a uuid := 'e2710000-0000-4000-8000-0000000000a1';
  v_user_admin_b uuid := 'e2710000-0000-4000-8000-0000000000b2';
  v_staff_admin_a uuid := 'f2710000-0000-4000-8000-0000000000a1';
  v_staff_admin_b uuid := 'f2710000-0000-4000-8000-0000000000b2';
  v_service_a uuid := 'b2710000-0000-4000-8000-0000000000a1';
  v_service_b uuid := 'b2710000-0000-4000-8000-0000000000b2';
  v_service_branch_a uuid := 'b2710000-0000-4000-8000-000000000001';
  v_visible_count int;
  v_dml_failed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.service_branches WHERE service_id IN (v_service_a, v_service_b);
  DELETE FROM public.services WHERE id IN (v_service_a, v_service_b);
  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_staff_admin_a, v_staff_admin_b);
  DELETE FROM public.staff_members WHERE id IN (v_staff_admin_a, v_staff_admin_b);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_user_admin_a, v_user_admin_b);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_admin_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-rls-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_admin_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-rls-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Service Org A', v_user_admin_a, v_user_admin_a),
    (v_org_b, 'RLS Service Org B', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'BA', v_user_admin_a, v_user_admin_a),
    (v_branch_b, v_org_b, 'Branch B', 'BB', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_admin_a, v_user_admin_a, 'Admin A', 'administrator', v_user_admin_a, v_user_admin_a),
    (v_staff_admin_b, v_user_admin_b, 'Admin B', 'administrator', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, created_by, updated_by)
  VALUES
    (v_staff_admin_a, v_branch_a, v_user_admin_a, v_user_admin_a),
    (v_staff_admin_b, v_branch_b, v_user_admin_b, v_user_admin_b);

  INSERT INTO public.services (id, organization_id, name, default_price, global_status, created_by, updated_by)
  VALUES
    (v_service_a, v_org_a, 'Org A Service', 100.00, 'active', v_user_admin_a, v_user_admin_a),
    (v_service_b, v_org_b, 'Org B Service', 100.00, 'active', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.service_branches (id, service_id, branch_id, status, created_by, updated_by)
  VALUES
    (v_service_branch_a, v_service_a, v_branch_a, 'active', v_user_admin_a, v_user_admin_a);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_administrator_jwt(v_user_admin_a, v_staff_admin_a, v_org_a, v_branch_a::text);

  SELECT count(*)::int
  INTO v_visible_count
  FROM public.services s
  WHERE s.id = v_service_b;

  PERFORM pg_temp.service_catalog_rls_record(
    'cross_org_services_select_denied',
    v_visible_count = 0,
    'visible=' || v_visible_count::text
  );

  SELECT count(*)::int
  INTO v_visible_count
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_b;

  PERFORM pg_temp.service_catalog_rls_record(
    'cross_org_service_branches_select_denied',
    v_visible_count = 0,
    'visible=' || v_visible_count::text
  );

  v_dml_failed := false;
  BEGIN
    INSERT INTO public.services (organization_id, name, default_price, global_status, created_by, updated_by)
    VALUES (v_org_a, 'Direct Insert', 10.00, 'active', v_user_admin_a, v_user_admin_a);
  EXCEPTION
    WHEN OTHERS THEN
      v_dml_failed := true;
  END;
  PERFORM pg_temp.service_catalog_rls_record('services_direct_insert_denied', v_dml_failed, 'insert blocked');

  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_administrator_jwt(v_user_admin_a, v_staff_admin_a, v_org_a, v_branch_a::text);

  UPDATE public.services SET name = 'Hacked' WHERE id = v_service_a;
  PERFORM pg_temp.service_catalog_rls_record(
    'services_direct_update_denied',
    NOT EXISTS (SELECT 1 FROM public.services WHERE id = v_service_a AND name = 'Hacked'),
    'name unchanged'
  );

  DELETE FROM public.services WHERE id = v_service_a;
  PERFORM pg_temp.service_catalog_rls_record(
    'services_direct_delete_denied',
    EXISTS (SELECT 1 FROM public.services WHERE id = v_service_a AND is_deleted = false),
    'row retained'
  );

  v_dml_failed := false;
  BEGIN
    INSERT INTO public.service_branches (service_id, branch_id, status, created_by, updated_by)
    VALUES (v_service_a, v_branch_a, 'active', v_user_admin_a, v_user_admin_a);
  EXCEPTION
    WHEN OTHERS THEN
      v_dml_failed := true;
  END;
  PERFORM pg_temp.service_catalog_rls_record('service_branches_direct_insert_denied', v_dml_failed, 'insert blocked');
END;
$$;

DO $$
DECLARE
  v_failed text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT string_agg(test_name || ': ' || detail, E'\n')
  INTO v_failed
  FROM service_catalog_rls_results
  WHERE NOT passed;

  IF v_failed IS NOT NULL THEN
    RAISE EXCEPTION 'Service catalog RLS failures:%', E'\n' || v_failed;
  END IF;
END;
$$;

ROLLBACK;
