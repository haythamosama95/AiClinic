-- Service Catalog (015) US1: create + branch-assignment CRUD verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/service_catalog_crud.sql

BEGIN;

CREATE TEMP TABLE service_catalog_crud_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.service_catalog_crud_record(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO service_catalog_crud_results (test_name, passed, detail)
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
  v_org_id uuid := 'c2700000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c2700000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd2700000-0000-4000-8000-0000000000a1';
  v_branch_a2 uuid := 'd2700000-0000-4000-8000-0000000000a2';
  v_branch_a3 uuid := 'd2700000-0000-4000-8000-0000000000a3';
  v_branch_b uuid := 'd2700000-0000-4000-8000-0000000000b1';
  v_user_admin uuid := 'e2700000-0000-4000-8000-0000000000a1';
  v_user_admin_b uuid := 'e2700000-0000-4000-8000-0000000000b1';
  v_staff_admin uuid := 'f2700000-0000-4000-8000-0000000000a1';
  v_staff_admin_b uuid := 'f2700000-0000-4000-8000-0000000000b1';
  v_service_id uuid;
  v_result public.rpc_result;
  v_assigned_count int;
  v_branch_ids uuid[];
  v_updated_at timestamptz;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log WHERE organization_id IN (v_org_id, v_org_b);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_id, v_org_b);
  DELETE FROM public.service_branches
  WHERE service_id IN (SELECT id FROM public.services WHERE organization_id IN (v_org_id, v_org_b));
  DELETE FROM public.services WHERE organization_id IN (v_org_id, v_org_b);
  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_staff_admin, v_staff_admin_b);
  DELETE FROM public.staff_members WHERE id IN (v_staff_admin, v_staff_admin_b);
  DELETE FROM public.branches WHERE organization_id IN (v_org_id, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_id, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_user_admin, v_user_admin_b);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-admin-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_admin_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-admin-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_id, 'Service Catalog Org A', v_user_admin, v_user_admin),
    (v_org_b, 'Service Catalog Org B', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_id, 'Branch A', 'BA', v_user_admin, v_user_admin),
    (v_branch_a2, v_org_id, 'Branch A2', 'BA2', v_user_admin, v_user_admin),
    (v_branch_a3, v_org_id, 'Branch A3', 'BA3', v_user_admin, v_user_admin),
    (v_branch_b, v_org_b, 'Branch B', 'BB', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_admin, v_user_admin, 'Admin A', 'administrator', v_user_admin, v_user_admin),
    (v_staff_admin_b, v_user_admin_b, 'Admin B', 'administrator', v_user_admin_b, v_user_admin_b);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, created_by, updated_by)
  VALUES
    (v_staff_admin, v_branch_a, v_user_admin, v_user_admin),
    (v_staff_admin, v_branch_a2, v_user_admin, v_user_admin),
    (v_staff_admin, v_branch_a3, v_user_admin, v_user_admin),
    (v_staff_admin_b, v_branch_b, v_user_admin_b, v_user_admin_b);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_administrator_jwt(v_user_admin, v_staff_admin, v_org_id, format('%s,%s,%s', v_branch_a, v_branch_a2, v_branch_a3));

  -- selected branches: two of three
  v_result := public.create_service('Consultation', 200.00, 'active', false, ARRAY[v_branch_a, v_branch_a2]);
  v_service_id := (v_result.data ->> 'service_id')::uuid;
  PERFORM pg_temp.service_catalog_crud_record(
    'create_service_selected_branches_success',
    v_result.success AND v_service_id IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT count(*)::int
  INTO v_assigned_count
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_id
    AND sb.is_deleted = false;

  PERFORM pg_temp.service_catalog_crud_record(
    'create_service_selected_branches_count',
    v_assigned_count = 2,
    'assigned=' || v_assigned_count::text
  );

  v_result := public.create_service('Consultation', 150.00, 'active', true, '{}'::uuid[]);
  PERFORM pg_temp.service_catalog_crud_record(
    'create_service_duplicate_name_rejected',
    NOT v_result.success AND v_result.error_code = 'DUPLICATE_NAME',
    COALESCE(v_result.error_code, '<null>')
  );

  v_result := public.create_service('X-Ray', -10.00, 'active', true, '{}'::uuid[]);
  PERFORM pg_temp.service_catalog_crud_record(
    'create_service_negative_price_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_PRICE',
    COALESCE(v_result.error_code, '<null>')
  );

  v_result := public.create_service('Blood Test', 50.00, 'active', true, '{}'::uuid[]);
  v_service_id := (v_result.data ->> 'service_id')::uuid;
  SELECT COALESCE(array_agg(sb.branch_id ORDER BY sb.branch_id), '{}'::uuid[])
  INTO v_branch_ids
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_id
    AND sb.is_deleted = false;

  PERFORM pg_temp.service_catalog_crud_record(
    'create_service_all_branches_expansion',
    v_result.success AND cardinality(v_branch_ids) = 3,
    'branches=' || cardinality(v_branch_ids)::text
  );

  v_result := public.create_service('Foreign Branch', 25.00, 'active', false, ARRAY[v_branch_b]);
  PERFORM pg_temp.service_catalog_crud_record(
    'create_service_foreign_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'BRANCH_NOT_IN_ORG',
    COALESCE(v_result.error_code, '<null>')
  );

  v_result := public.set_service_branch_assignment(v_service_id, ARRAY[v_branch_a3], false);
  PERFORM pg_temp.service_catalog_crud_record(
    'set_service_branch_assignment_unassign',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT count(*)::int
  INTO v_assigned_count
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_id
    AND sb.is_deleted = false;

  PERFORM pg_temp.service_catalog_crud_record(
    'set_service_branch_assignment_unassign_count',
    v_assigned_count = 2,
    'remaining=' || v_assigned_count::text
  );

  v_result := public.set_service_branch_assignment(v_service_id, ARRAY[v_branch_a3], true);
  PERFORM pg_temp.service_catalog_crud_record(
    'set_service_branch_assignment_reassign',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  v_result := public.get_service(v_service_id);
  PERFORM pg_temp.service_catalog_crud_record(
    'get_service_success',
    v_result.success AND (v_result.data -> 'service' ->> 'name') = 'Blood Test',
    COALESCE(v_result.error_code, 'ok')
  );

  -- US5: edit history stability + soft-delete of referenced service
  v_result := public.create_service('History Service', 200.00, 'active', false, ARRAY[v_branch_a]);
  v_service_id := (v_result.data ->> 'service_id')::uuid;

  SELECT updated_at INTO v_updated_at FROM public.services WHERE id = v_service_id;

  v_result := public.update_service(
    v_service_id, v_updated_at, 'General Consultation', 220.00, 'inactive'
  );
  PERFORM pg_temp.service_catalog_crud_record(
    'update_service_rename_price_status',
    v_result.success AND (v_result.data ->> 'service_id')::uuid = v_service_id,
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT updated_at INTO v_updated_at FROM public.services WHERE id = v_service_id;

  v_result := public.set_service_global_status(v_service_id, v_updated_at, 'inactive');
  PERFORM pg_temp.service_catalog_crud_record(
    'set_service_global_status_success',
    v_result.success AND v_result.data ->> 'global_status' = 'inactive',
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT updated_at INTO v_updated_at FROM public.services WHERE id = v_service_id;
  v_result := public.soft_delete_service(v_service_id, v_updated_at);
  PERFORM pg_temp.service_catalog_crud_record(
    'soft_delete_service_success',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  PERFORM pg_temp.service_catalog_crud_record(
    'soft_delete_service_hidden_from_get',
    NOT (public.get_service(v_service_id)).success,
    'deleted service should not be readable'
  );

  -- US7: copy branch configuration (merge/replace + audit)
  v_result := public.create_service('Copy Source', 200.00, 'active', false, ARRAY[v_branch_a]);
  v_service_id := (v_result.data ->> 'service_id')::uuid;

  SELECT updated_at INTO v_updated_at
  FROM public.service_branches
  WHERE service_id = v_service_id AND branch_id = v_branch_a;

  v_result := public.configure_service_branch(v_service_id, v_branch_a, v_updated_at, 'active', 150.00);
  PERFORM pg_temp.service_catalog_crud_record(
    'copy_setup_source_branch_override',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  v_result := public.copy_service_branch_configuration(v_branch_a, v_branch_a3, 'merge', ARRAY[v_service_id]);
  PERFORM pg_temp.service_catalog_crud_record(
    'copy_merge_to_empty_target',
    v_result.success AND jsonb_array_length(v_result.data -> 'affected_service_ids') = 1,
    COALESCE(v_result.error_code, 'ok')
  );

  PERFORM pg_temp.service_catalog_crud_record(
    'copy_merge_creates_matching_override',
    EXISTS (
      SELECT 1
      FROM public.service_branches sb
      WHERE sb.service_id = v_service_id
        AND sb.branch_id = v_branch_a3
        AND sb.is_deleted = false
        AND sb.price_override = 150.00
    ),
    'target override after merge'
  );

  SELECT updated_at INTO v_updated_at
  FROM public.service_branches
  WHERE service_id = v_service_id AND branch_id = v_branch_a3;

  v_result := public.configure_service_branch(v_service_id, v_branch_a3, v_updated_at, 'active', 175.00);
  PERFORM pg_temp.service_catalog_crud_record(
    'copy_merge_modify_target_before_second_merge',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  v_result := public.copy_service_branch_configuration(v_branch_a, v_branch_a3, 'merge', ARRAY[v_service_id]);
  PERFORM pg_temp.service_catalog_crud_record(
    'copy_merge_leaves_existing_target_untouched',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.service_branches sb
        WHERE sb.service_id = v_service_id
          AND sb.branch_id = v_branch_a3
          AND sb.is_deleted = false
          AND sb.price_override = 175.00
      ),
    'merge should not overwrite existing target row'
  );

  v_result := public.copy_service_branch_configuration(v_branch_a, v_branch_a3, 'replace', ARRAY[v_service_id]);
  PERFORM pg_temp.service_catalog_crud_record(
    'copy_replace_overwrites_target',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.service_branches sb
        WHERE sb.service_id = v_service_id
          AND sb.branch_id = v_branch_a3
          AND sb.is_deleted = false
          AND sb.price_override = 150.00
      ),
    'replace should match source'
  );

  PERFORM pg_temp.service_catalog_crud_record(
    'copy_replace_audit_payload',
    EXISTS (
      SELECT 1
      FROM public.audit_log al
      WHERE al.organization_id = v_org_id
        AND al.action = 'service.branch.copy'
        AND al.new_data_json ->> 'mode' = 'replace'
        AND al.new_data_json ? 'affected_service_ids'
        AND (al.new_data_json -> 'affected_service_ids') @> to_jsonb(ARRAY[v_service_id::text])
    ),
    'audit includes affected services'
  );

  v_result := public.copy_service_branch_configuration(v_branch_a, v_branch_a, 'merge', NULL);
  PERFORM pg_temp.service_catalog_crud_record(
    'copy_same_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_COPY_TARGET',
    COALESCE(v_result.error_code, '<null>')
  );

  v_result := public.setup_new_branch_services(v_branch_a3, 'select', ARRAY[v_service_id], NULL, 'merge');
  PERFORM pg_temp.service_catalog_crud_record(
    'setup_new_branch_services_select',
    v_result.success AND (v_result.data -> 'assigned_service_ids') @> to_jsonb(ARRAY[v_service_id::text]),
    COALESCE(v_result.error_code, 'ok')
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
  FROM service_catalog_crud_results
  WHERE NOT passed;

  IF v_failed IS NOT NULL THEN
    RAISE EXCEPTION 'Service catalog CRUD failures:%', E'\n' || v_failed;
  END IF;
END;
$$;

ROLLBACK;
