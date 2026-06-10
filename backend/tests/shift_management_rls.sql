-- V1-7 cross-org and cross-branch denial for shifts; read-path access for branch staff.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/shift_management_rls.sql

BEGIN;

CREATE TEMP TABLE shift_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_org_a uuid := 'c2700000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c2700000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd2700000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd2700000-0000-4000-8000-0000000000b2';
  v_branch_a2 uuid := 'd2700000-0000-4000-8000-0000000000a2';
  v_user_owner uuid := 'e2700000-0000-4000-8000-0000000000a1';
  v_user_reception uuid := 'e2700000-0000-4000-8000-0000000000a2';
  v_user_owner_b uuid := 'e2700000-0000-4000-8000-0000000000b2';
  v_staff_owner uuid := 'f2700000-0000-4000-8000-0000000000a1';
  v_staff_reception uuid := 'f2700000-0000-4000-8000-0000000000a2';
  v_staff_owner_b uuid := 'f2700000-0000-4000-8000-0000000000b2';
  v_shift_a uuid := 'c2700000-0000-4000-8000-00000000aa01';
  v_shift_a2 uuid := 'c2700000-0000-4000-8000-00000000aa02';
  v_shift_b uuid := 'c2700000-0000-4000-8000-00000000bb01';
  v_assignment_a uuid := 'b2700000-0000-4000-8000-000000000001';
  v_visible_count int;
  v_dml_failed boolean;
  v_list_result jsonb;
  v_detail_result jsonb;
  v_manage_denied boolean;
  v_manage_allowed boolean;
  v_has_manage boolean;
  v_err text;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();

  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_staff_owner, v_staff_reception, v_staff_owner_b);
  DELETE FROM public.staff_members
  WHERE id IN (v_staff_owner, v_staff_reception, v_staff_owner_b);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b, v_branch_a2);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users
  WHERE id IN (v_user_owner, v_user_reception, v_user_owner_b);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-shift-owner-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_reception, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-shift-recep-a',
     extensions.crypt('pw-r', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_owner_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-shift-owner-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, timezone, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Shift Org A', 'UTC', v_user_owner, v_user_owner),
    (v_org_b, 'RLS Shift Org B', 'UTC', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'SA', v_user_owner, v_user_owner),
    (v_branch_a2, v_org_a, 'Branch A2', 'SA2', v_user_owner, v_user_owner),
    (v_branch_b, v_org_b, 'Branch B', 'SB', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_owner, v_user_owner, 'Owner A', 'administrator', v_user_owner, v_user_owner),
    (v_staff_reception, v_user_reception, 'Reception A', 'receptionist', v_user_owner, v_user_owner),
    (v_staff_owner_b, v_user_owner_b, 'Owner B', 'administrator', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_owner, v_branch_a, true, v_user_owner, v_user_owner),
    (v_staff_owner, v_branch_a2, false, v_user_owner, v_user_owner),
    (v_staff_reception, v_branch_a, true, v_user_owner, v_user_owner),
    (v_staff_owner_b, v_branch_b, true, v_user_owner_b, v_user_owner_b);

  INSERT INTO public.shifts (
    id, organization_id, branch_id, shift_date, start_time, end_time, notes, created_by, updated_by
  )
  VALUES
    (
      v_shift_a,
      v_org_a,
      v_branch_a,
      (auth_internal.get_org_today(v_org_a) + 1),
      time '09:00',
      time '17:00',
      'Morning coverage',
      v_user_owner,
      v_user_owner
    ),
    (
      v_shift_a2,
      v_org_a,
      v_branch_a2,
      (auth_internal.get_org_today(v_org_a) + 2),
      time '10:00',
      time '14:00',
      NULL,
      v_user_owner,
      v_user_owner
    ),
    (
      v_shift_b,
      v_org_b,
      v_branch_b,
      (auth_internal.get_org_today(v_org_b) + 1),
      time '08:00',
      time '16:00',
      NULL,
      v_user_owner_b,
      v_user_owner_b
    );

  INSERT INTO public.shift_assignments (id, shift_id, staff_member_id, created_by, updated_by)
  VALUES
    (v_assignment_a, v_shift_a, v_staff_owner, v_user_owner, v_user_owner);

  -- Cross-org direct SELECT hidden.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int INTO v_visible_count FROM public.shifts s WHERE s.id = v_shift_b;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'cross_org_direct_select_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );

  SELECT count(*)::int
  INTO v_visible_count
  FROM public.shift_assignments sa
  WHERE sa.id = v_assignment_a AND sa.shift_id = v_shift_b;
  INSERT INTO shift_rls_results VALUES (
    'cross_org_assignment_select_hidden',
    v_visible_count = 0,
    'assignment_visible=' || v_visible_count::text
  );

  -- Cross-org list_shifts denied.
  PERFORM set_config('role', 'authenticated', true);
  v_list_result := NULL;
  BEGIN
    v_list_result := public.list_shifts(
      v_branch_b,
      auth_internal.get_org_today(v_org_a),
      auth_internal.get_org_today(v_org_a) + 7
    );
  EXCEPTION
    WHEN OTHERS THEN
      v_err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'cross_org_list_other_branch_denied',
    v_list_result IS NULL AND v_err = 'permission_denied',
    COALESCE(v_err, 'ok')
  );

  -- Cross-branch within org: user assigned only to branch A cannot see branch A2 shifts.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int INTO v_visible_count FROM public.shifts s WHERE s.id = v_shift_a2;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'cross_branch_direct_select_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );

  PERFORM set_config('role', 'authenticated', true);
  v_list_result := NULL;
  v_err := NULL;
  BEGIN
    v_list_result := public.list_shifts(
      v_branch_a2,
      auth_internal.get_org_today(v_org_a),
      auth_internal.get_org_today(v_org_a) + 7
    );
  EXCEPTION
    WHEN OTHERS THEN
      v_err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'cross_branch_list_denied',
    v_list_result IS NULL AND v_err = 'permission_denied',
    COALESCE(v_err, 'ok')
  );

  -- Receptionist can list/detail without shifts.manage.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_reception::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_reception::text,
      'staff_role', 'receptionist',
      'setup_required', false
    )::text,
    true
  );

  v_list_result := public.list_shifts(
    v_branch_a,
    auth_internal.get_org_today(v_org_a),
    auth_internal.get_org_today(v_org_a) + 7
  );
  v_detail_result := public.get_shift_detail(v_shift_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'receptionist_list_shifts_allowed',
    jsonb_array_length(v_list_result) >= 1,
    'count=' || jsonb_array_length(v_list_result)::text
  );
  INSERT INTO shift_rls_results VALUES (
    'receptionist_get_shift_detail_allowed',
    (v_detail_result -> 'shift' ->> 'id') = v_shift_a::text,
    COALESCE(v_detail_result -> 'shift' ->> 'id', '<null>')
  );
  INSERT INTO shift_rls_results VALUES (
    'receptionist_detail_is_read_only',
    (v_detail_result -> 'shift' ->> 'is_read_only')::boolean = true,
    COALESCE(v_detail_result -> 'shift' ->> 'is_read_only', '<null>')
  );

  -- Receptionist lacks shifts.manage permission gate.
  PERFORM set_config('role', 'authenticated', true);
  SELECT auth_internal.staff_has_shifts_manage() INTO v_has_manage;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'receptionist_shifts_manage_absent',
    NOT v_has_manage,
    'has_manage=' || v_has_manage::text
  );

  PERFORM set_config('role', 'authenticated', true);
  v_manage_denied := false;
  BEGIN
    PERFORM auth_internal.assert_shifts_manage();
  EXCEPTION
    WHEN OTHERS THEN
      v_manage_denied := SQLERRM = 'permission_denied';
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'receptionist_mutation_gate_denied',
    v_manage_denied,
    'denied=' || v_manage_denied::text
  );

  -- Owner/administrator passes shifts.manage gate.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  SELECT auth_internal.staff_has_shifts_manage() INTO v_has_manage;
  v_manage_allowed := false;
  BEGIN
    PERFORM auth_internal.assert_shifts_manage();
    v_manage_allowed := true;
  EXCEPTION
    WHEN OTHERS THEN
      v_manage_allowed := false;
  END;
  v_detail_result := public.get_shift_detail(v_shift_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'owner_shifts_manage_present',
    v_has_manage,
    'has_manage=' || v_has_manage::text
  );
  INSERT INTO shift_rls_results VALUES (
    'owner_mutation_gate_allowed',
    v_manage_allowed,
    'allowed=' || v_manage_allowed::text
  );
  INSERT INTO shift_rls_results VALUES (
    'owner_detail_not_read_only_future_shift',
    (v_detail_result -> 'shift' ->> 'is_read_only')::boolean = false,
    COALESCE(v_detail_result -> 'shift' ->> 'is_read_only', '<null>')
  );

  -- Direct DML denied for owner (mutations must use RPCs in later phases).
  PERFORM set_config('role', 'authenticated', true);
  v_dml_failed := false;
  BEGIN
    INSERT INTO public.shifts (
      organization_id, branch_id, shift_date, start_time, end_time
    )
    VALUES (
      v_org_a,
      v_branch_a,
      auth_internal.get_org_today(v_org_a) + 3,
      time '09:00',
      time '17:00'
    );
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_dml_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'direct_insert_denied_owner',
    v_dml_failed,
    'dml_failed=' || v_dml_failed::text
  );

  PERFORM set_config('role', 'authenticated', true);
  v_dml_failed := false;
  BEGIN
    INSERT INTO public.shift_assignments (shift_id, staff_member_id)
    VALUES (v_shift_a, v_staff_reception);
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_dml_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_rls_results VALUES (
    'direct_assignment_insert_denied',
    v_dml_failed,
    'dml_failed=' || v_dml_failed::text
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
  v_detail text;
BEGIN
  SELECT count(*)::int
  INTO v_failures
  FROM shift_rls_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    SELECT string_agg(test_name || ': ' || detail, '; ')
    INTO v_detail
    FROM shift_rls_results
    WHERE NOT passed;

    RAISE EXCEPTION 'shift_management_rls.sql: % failing assertion(s): %', v_failures, v_detail;
  END IF;
END;
$$;

SELECT test_name, passed, detail FROM shift_rls_results ORDER BY test_name;

ROLLBACK;
