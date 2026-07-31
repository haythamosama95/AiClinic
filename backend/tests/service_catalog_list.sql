-- Service Catalog (015): list_services verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/service_catalog_list.sql

BEGIN;

CREATE TEMP TABLE service_catalog_list_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.service_catalog_list_record(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO service_catalog_list_results (test_name, passed, detail)
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
  v_org_id uuid := 'c2720000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c2720000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd2720000-0000-4000-8000-0000000000a1';
  v_branch_a2 uuid := 'd2720000-0000-4000-8000-0000000000a2';
  v_branch_b uuid := 'd2720000-0000-4000-8000-0000000000b1';
  v_user_admin uuid := 'e2720000-0000-4000-8000-0000000000a1';
  v_user_admin_b uuid := 'e2720000-0000-4000-8000-0000000000b1';
  v_staff_admin uuid := 'f2720000-0000-4000-8000-0000000000a1';
  v_staff_admin_b uuid := 'f2720000-0000-4000-8000-0000000000b1';
  v_service_active uuid;
  v_service_inactive uuid;
  v_service_other_org uuid := 'b2720000-0000-4000-8000-0000000000b2';
  v_result public.rpc_result;
  v_items jsonb;
  v_total int;
  v_found boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log WHERE organization_id IN (v_org_id, v_org_b);
  DELETE FROM public.service_branches
  WHERE service_id IN (SELECT id FROM public.services WHERE organization_id IN (v_org_id, v_org_b));
  DELETE FROM public.services WHERE organization_id IN (v_org_id, v_org_b);
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id IN (v_staff_admin, v_staff_admin_b);
  DELETE FROM public.staff_members WHERE id IN (v_staff_admin, v_staff_admin_b);
  DELETE FROM public.branches WHERE organization_id IN (v_org_id, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_id, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_user_admin, v_user_admin_b);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-list-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_admin_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-list-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_id, 'List Services Org A', v_user_admin, v_user_admin),
    (v_org_b, 'List Services Org B', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_id, 'Branch A', 'BA', v_user_admin, v_user_admin),
    (v_branch_a2, v_org_id, 'Branch A2', 'BA2', v_user_admin, v_user_admin),
    (v_branch_b, v_org_b, 'Branch B', 'BB', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_admin, v_user_admin, 'Admin A', 'administrator', v_user_admin, v_user_admin),
    (v_staff_admin_b, v_user_admin_b, 'Admin B', 'administrator', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, created_by, updated_by)
  VALUES
    (v_staff_admin, v_branch_a, v_user_admin, v_user_admin),
    (v_staff_admin, v_branch_a2, v_user_admin, v_user_admin),
    (v_staff_admin_b, v_branch_b, v_user_admin_b, v_user_admin_b);

  INSERT INTO public.services (id, organization_id, name, default_price, global_status, created_by, updated_by)
  VALUES
    (v_service_other_org, v_org_b, 'Org B Secret Service', 99.00, 'active', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.service_branches (service_id, branch_id, status, created_by, updated_by)
  VALUES (v_service_other_org, v_branch_b, 'active', v_user_admin_b, v_user_admin_b);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_administrator_jwt(v_user_admin, v_staff_admin, v_org_id, format('%s,%s', v_branch_a, v_branch_a2));

  v_result := public.create_service('Alpha Consultation', 200.00, 'active', false, ARRAY[v_branch_a]);
  v_service_active := (v_result.data ->> 'service_id')::uuid;
  PERFORM pg_temp.service_catalog_list_record(
    'create_service_for_list_setup',
    v_result.success AND v_service_active IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );

  v_result := public.create_service('Beta Inactive Panel', 150.00, 'inactive', false, ARRAY[v_branch_a]);
  v_service_inactive := (v_result.data ->> 'service_id')::uuid;

  v_result := public.create_service('Gamma Searchable Test', 75.00, 'active', false, ARRAY[v_branch_a, v_branch_a2]);
  PERFORM pg_temp.service_catalog_list_record(
    'create_searchable_service',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  -- list_services returns created service
  v_result := public.list_services(NULL, NULL, NULL, 50, 0);
  v_items := v_result.data -> 'items';
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_items) AS item
    WHERE (item ->> 'service_id')::uuid = v_service_active
  )
  INTO v_found;
  PERFORM pg_temp.service_catalog_list_record(
    'list_services_returns_created_service',
    v_result.success AND v_found,
    'found=' || v_found::text
  );

  -- Filter by global_status
  v_result := public.list_services(NULL, 'inactive', NULL, 50, 0);
  v_items := v_result.data -> 'items';
  PERFORM pg_temp.service_catalog_list_record(
    'list_services_filter_global_status',
    v_result.success
      AND COALESCE(
        (SELECT bool_and(item ->> 'global_status' = 'inactive') FROM jsonb_array_elements(v_items) AS item),
        true
      )
      AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS item
        WHERE (item ->> 'service_id')::uuid = v_service_inactive
      ),
    'count=' || COALESCE(jsonb_array_length(v_items)::text, '0')
  );

  -- Search by query substring
  v_result := public.list_services('Searchable', NULL, NULL, 50, 0);
  v_items := v_result.data -> 'items';
  PERFORM pg_temp.service_catalog_list_record(
    'list_services_search_query',
    v_result.success
      AND jsonb_array_length(v_items) >= 1
      AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS item
        WHERE item ->> 'name' ILIKE '%Searchable%'
      ),
    'count=' || COALESCE(jsonb_array_length(v_items)::text, '0')
  );

  -- Pagination limit/offset
  v_result := public.list_services(NULL, NULL, NULL, 1, 0);
  v_total := (v_result.data ->> 'total')::int;
  PERFORM pg_temp.service_catalog_list_record(
    'list_services_pagination_limit',
    v_result.success
      AND jsonb_array_length(v_result.data -> 'items') = 1
      AND v_total >= 3,
    format('page=%s total=%s', jsonb_array_length(v_result.data -> 'items'), v_total)
  );

  v_result := public.list_services(NULL, NULL, NULL, 1, 1);
  PERFORM pg_temp.service_catalog_list_record(
    'list_services_pagination_offset',
    v_result.success AND jsonb_array_length(v_result.data -> 'items') = 1,
    'page=' || jsonb_array_length(v_result.data -> 'items')::text
  );

  -- Cross-org isolation
  v_result := public.list_services('Org B Secret', NULL, NULL, 50, 0);
  v_items := v_result.data -> 'items';
  PERFORM pg_temp.service_catalog_list_record(
    'list_services_cross_org_isolation',
    v_result.success
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS item
        WHERE (item ->> 'service_id')::uuid = v_service_other_org
      ),
    'count=' || COALESCE(jsonb_array_length(v_items)::text, '0')
  );
END;
$$;

DO $$
DECLARE
  v_failed text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT string_agg(test_name || ': ' || detail, E'\n')
  INTO v_failed
  FROM service_catalog_list_results
  WHERE NOT passed;

  IF v_failed IS NOT NULL THEN
    RAISE EXCEPTION 'Service catalog list failures:%', E'\n' || v_failed;
  END IF;
END;
$$;

ROLLBACK;
