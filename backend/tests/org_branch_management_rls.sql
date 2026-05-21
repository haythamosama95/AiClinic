-- V1-2 cross-organization denial for management RPCs.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_rls.sql

BEGIN;

CREATE TEMP TABLE org_branch_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_org_a uuid := 'c1000000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c1000000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd1000000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd1000000-0000-4000-8000-0000000000b2';
  v_user_a uuid := 'e1000000-0000-4000-8000-0000000000a1';
  v_user_b uuid := 'e1000000-0000-4000-8000-0000000000b2';
  v_staff_a uuid := 'f1000000-0000-4000-8000-0000000000a1';
  v_staff_b uuid := 'f1000000-0000-4000-8000-0000000000b2';
  v_user_b_target uuid := 'e1000000-0000-4000-8000-0000000000b3';
  v_staff_b_target uuid := 'f1000000-0000-4000-8000-0000000000b3';
  v_result public.rpc_result;
  v_org_b_name text;
  v_branch_b_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-v12-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-v12-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_b_target, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-v12-b-target',
     extensions.crypt('pw-b2', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Org A V12', v_user_a, v_user_a),
    (v_org_b, 'RLS Org B V12', v_user_b, v_user_b)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'A1', v_user_a, v_user_a),
    (v_branch_b, v_org_b, 'Branch B', 'B1', v_user_b, v_user_b)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_a, v_user_a, 'Owner A', 'owner', v_user_a, v_user_a),
    (v_staff_b, v_user_b, 'Owner B', 'owner', v_user_b, v_user_b),
    (v_staff_b_target, v_user_b_target, 'Staff B Target', 'receptionist', v_user_b, v_user_b)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_b, v_branch_b, true, v_user_b, v_user_b),
    (v_staff_b_target, v_branch_b, true, v_user_b, v_user_b)
  ON CONFLICT (staff_member_id, branch_id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_a::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  -- User A cannot update branch in org B.
  v_result := public.update_branch(v_branch_b, 'Hijacked', 'HIJ', NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_rls_results VALUES (
    'cross_org_update_branch_denied',
    NOT v_result.success AND v_result.error_code = 'BRANCH_NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.set_branch_active(v_branch_b, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_rls_results VALUES (
    'cross_org_set_branch_active_denied',
    NOT v_result.success AND v_result.error_code = 'BRANCH_NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_staff_member(
    v_staff_b_target,
    'Hijacked Name',
    'receptionist',
    ARRAY[v_branch_a],
    NULL,
    v_branch_a,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_rls_results VALUES (
    'cross_org_staff_hijack_denied',
    NOT v_result.success AND v_result.error_code = 'CROSS_ORG_DENIED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_staff_member(
    v_staff_b_target,
    'Hijacked Name',
    'receptionist',
    ARRAY[v_branch_b],
    NULL,
    v_branch_b,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_rls_results VALUES (
    'cross_org_update_staff_denied',
    NOT v_result.success
      AND v_result.error_code IN ('CROSS_ORG_DENIED', 'STAFF_NOT_FOUND', 'INVALID_BRANCH'),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.set_staff_active(v_staff_b_target, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_rls_results VALUES (
    'cross_org_set_staff_active_denied',
    NOT v_result.success AND v_result.error_code = 'STAFF_NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Branch create is scoped to caller organization (org B unchanged).
  v_result := public.manage_create_branch('East Wing', 'EAST', NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int
  INTO v_branch_b_count
  FROM public.branches b
  WHERE b.organization_id = v_org_b AND b.is_deleted = false;
  INSERT INTO org_branch_rls_results VALUES (
    'cross_org_manage_create_branch_scoped',
    v_result.success AND v_branch_b_count = 1,
    'org_b_branches=' || v_branch_b_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Organization update affects only session organization.
  v_result := public.update_organization('RLS Org A Renamed', NULL, NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  SELECT o.name INTO v_org_b_name FROM public.organizations o WHERE o.id = v_org_b;
  INSERT INTO org_branch_rls_results VALUES (
    'cross_org_update_organization_isolated',
    v_result.success AND v_org_b_name = 'RLS Org B V12',
    COALESCE(v_org_b_name, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_role_permission('administrator', 'settings.manage_branches', false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_rls_results VALUES (
    'cross_org_update_role_permission_allowed_for_owner',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*)::int
  INTO v_failures
  FROM org_branch_rls_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'org_branch_management_rls failed % test(s): %',
      v_failures,
      (SELECT string_agg(test_name || ' (' || detail || ')', ', ') FROM org_branch_rls_results WHERE NOT passed);
  END IF;
END;
$$;

ROLLBACK;
