-- V1-2 org/branch/staff/permission management RPC verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_crud.sql

BEGIN;

CREATE TEMP TABLE org_branch_crud_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1000000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b1000000-0000-4000-8000-000000000001';
  v_admin_user uuid := 'e0000000-0000-4000-8000-0000000000a1';
  v_admin_staff uuid := 'f0000000-0000-4000-8000-0000000000a1';
  v_doctor_user uuid := 'd0000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'd1000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_branch_second uuid;
  v_receptionist_id uuid;
  v_active_count int;
  v_org_name text;
  v_grant boolean;
  v_audit_count int;
  v_staff_active boolean;
  v_working_schedule jsonb := '{
    "days": [
      {"day":"monday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"tuesday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"wednesday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"thursday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"friday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"saturday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"sunday","is_working_day":false}
    ]
  }'::jsonb;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_admin_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v12-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_admin_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v12-admin',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v12-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V12 Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_admin_staff, v_admin_user, 'Clinic Admin', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Clinic Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_main, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_admin_staff), (v_doctor_staff)) AS s(id);

  PERFORM set_config('role', 'authenticated', true);

  -- Trivial: empty organization name rejected.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.update_organization('   ', NULL, NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'org_update_rejects_blank_name',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: invalid currency code.
  v_result := public.update_organization('V12 Clinic', NULL, 'usd', NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'org_update_rejects_invalid_currency',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: invalid timezone identifier.
  v_result := public.update_organization('V12 Clinic', NULL, NULL, 'Not/A/Zone', NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'org_update_rejects_invalid_timezone',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Owner updates organization profile.
  v_result := public.update_organization(
    'V12 Clinic Updated',
    'https://logo.example',
    'EGP',
    'Africa/Cairo',
    '{"locale":"ar"}'::jsonb
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT o.name INTO v_org_name FROM public.organizations o WHERE o.id = v_org_id;
  INSERT INTO org_branch_crud_results VALUES (
    'org_update_owner_success',
    v_result.success AND v_org_name = 'V12 Clinic Updated',
    COALESCE(v_result.error_code, v_org_name)
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.organization_id = v_org_id
    AND al.action = 'organization.update'
    AND al.table_name = 'organizations';
  INSERT INTO org_branch_crud_results VALUES (
    'org_update_writes_audit_log',
    v_audit_count >= 1,
    'count=' || v_audit_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Administrator can update organization profile.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.update_organization('V12 Admin Updated', NULL, NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  SELECT o.name INTO v_org_name FROM public.organizations o WHERE o.id = v_org_id;
  INSERT INTO org_branch_crud_results VALUES (
    'org_update_administrator_success',
    v_result.success AND v_org_name = 'V12 Admin Updated',
    COALESCE(v_result.error_code, v_org_name)
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore owner claims for subsequent tests.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  -- Doctor denied organization update.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_doctor_staff::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.update_organization('Hacked Name', NULL, NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'org_update_doctor_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Administrator creates second branch.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.manage_create_branch('North Wing', v_working_schedule, 'NORTH', '2 North St', '+2', NULL);
  v_branch_second := (v_result.data ->> 'branch_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'branch_create_admin_success',
    v_result.success AND v_branch_second IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: duplicate branch code.
  v_result := public.manage_create_branch('Duplicate Code Branch', v_working_schedule, 'NORTH', NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'branch_create_duplicate_code_rejected',
    NOT v_result.success AND v_result.error_code = 'DUPLICATE_CODE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- LAST_ACTIVE_BRANCH: cannot deactivate sole active branch when only one is active.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches SET is_active = true WHERE id IN (v_branch_main, v_branch_second);
  UPDATE public.branches SET is_active = false WHERE id = v_branch_second;
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.set_branch_active(v_branch_main, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'branch_deactivate_last_active_blocked',
    NOT v_result.success AND v_result.error_code = 'LAST_ACTIVE_BRANCH',
    COALESCE(v_result.error_code, '<null>') || ' success=' || v_result.success::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Reactivate second branch then deactivate main (allowed).
  v_result := public.set_branch_active(v_branch_second, true);
  v_result := public.set_branch_active(v_branch_main, false);
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_active_count
  FROM public.branches b
  WHERE b.organization_id = v_org_id AND b.is_deleted = false AND b.is_active = true;
  INSERT INTO org_branch_crud_results VALUES (
    'branch_deactivate_non_last_success',
    v_result.success AND v_active_count = 1,
    'active=' || v_active_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Create receptionist for staff lifecycle tests.
  v_result := public.create_staff_account(
    'v12-reception',
    'secret12',
    'Front Desk',
    'receptionist',
    ARRAY[v_branch_second],
    v_branch_second
  );
  v_receptionist_id := (v_result.data ->> 'staff_member_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_create_fixture',
    v_receptionist_id IS NOT NULL,
    COALESCE(v_receptionist_id::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Ensure both branches active for staff assignment update.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches SET is_active = true WHERE id IN (v_branch_main, v_branch_second);
  PERFORM set_config('role', 'authenticated', true);

  -- Corner case: primary branch must be in assignment list.
  v_result := public.update_staff_member(
    v_receptionist_id,
    'Front Desk',
    'receptionist',
    ARRAY[v_branch_second],
    NULL,
    v_branch_main,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_update_primary_not_in_assignments_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Corner case: inactive branch assignment rejected.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches SET is_active = false WHERE id = v_branch_second;
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.update_staff_member(
    v_receptionist_id,
    'Front Desk',
    'receptionist',
    ARRAY[v_branch_second],
    NULL,
    v_branch_second,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_update_inactive_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );
  UPDATE public.branches SET is_active = true WHERE id = v_branch_second;
  PERFORM set_config('role', 'authenticated', true);

  -- Administrator may promote staff to administrator.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.update_staff_member(
    v_receptionist_id,
    'Front Desk',
    'administrator',
    ARRAY[v_branch_second],
    NULL,
    v_branch_second,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_update_admin_assigns_administrator_role',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Update staff member assignments and phone (active branches only).
  v_result := public.update_staff_member(
    v_receptionist_id,
    'Front Desk Updated',
    'receptionist',
    ARRAY[v_branch_second],
    '+20123456789',
    v_branch_second,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_update_success',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: empty branch list on update.
  v_result := public.update_staff_member(
    v_receptionist_id,
    'Front Desk',
    'receptionist',
    ARRAY[]::uuid[],
    NULL,
    NULL,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_update_empty_branches_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Deactivate staff.
  v_result := public.set_staff_active(v_receptionist_id, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_deactivate_success',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Reactivate staff after deactivation.
  v_result := public.set_staff_active(v_receptionist_id, true);
  PERFORM set_config('role', 'postgres', true);
  SELECT sm.is_active INTO v_staff_active
  FROM public.staff_members sm
  WHERE sm.id = v_receptionist_id;
  INSERT INTO org_branch_crud_results VALUES (
    'staff_reactivate_success',
    v_result.success AND v_staff_active = true,
    COALESCE(v_result.error_code, v_staff_active::text)
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Last-administrator guard: leave a single active administrator in the org.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.set_staff_active(v_admin_staff, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_deactivate_second_administrator_success',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.set_staff_active(v_bootstrap_staff, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_deactivate_bootstrap_administrator_success',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_staff_member(
    v_owner_staff,
    'Clinic Owner',
    'doctor',
    ARRAY[v_branch_main],
    NULL,
    v_branch_main,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_update_demote_last_administrator_rejected',
    NOT v_result.success AND v_result.error_code = 'LAST_ADMINISTRATOR',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.roles_permissions (role, permission_key, is_granted)
  VALUES ('doctor', 'settings.manage_staff', true)
  ON CONFLICT (role, permission_key) DO UPDATE
  SET is_granted = true, is_deleted = false, updated_at = now();
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_doctor_staff::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.set_staff_active(v_owner_staff, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'staff_deactivate_last_administrator_rejected',
    NOT v_result.success AND v_result.error_code = 'LAST_ADMINISTRATOR',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.roles_permissions
  WHERE role = 'doctor' AND permission_key = 'settings.manage_staff';
  UPDATE public.staff_members SET is_active = true WHERE id IN (v_admin_staff, v_bootstrap_staff);
  PERFORM set_config('role', 'authenticated', true);

  -- Administrator may toggle permission matrix; other roles denied.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.update_role_permission('administrator', 'settings.manage_branches', false);
  PERFORM set_config('role', 'postgres', true);
  SELECT rp.is_granted INTO v_grant
  FROM public.roles_permissions rp
  WHERE rp.role = 'administrator' AND rp.permission_key = 'settings.manage_branches' AND rp.is_deleted = false;
  INSERT INTO org_branch_crud_results VALUES (
    'permission_matrix_primary_admin_write',
    v_result.success AND v_grant = false,
    COALESCE(v_result.error_code, v_grant::text)
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.update_role_permission('doctor', 'patients.view', false);
  PERFORM set_config('role', 'postgres', true);
  SELECT rp.is_granted INTO v_grant
  FROM public.roles_permissions rp
  WHERE rp.role = 'doctor' AND rp.permission_key = 'patients.view' AND rp.is_deleted = false;
  INSERT INTO org_branch_crud_results VALUES (
    'permission_matrix_admin_write',
    v_result.success AND v_grant = false,
    COALESCE(v_result.error_code, v_grant::text)
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_doctor_staff::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.update_role_permission('lab_staff', 'patients.view', false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_branch_crud_results VALUES (
    'permission_matrix_doctor_denied',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Restore matrix grants for downstream tests.
  UPDATE public.roles_permissions
  SET is_granted = true, updated_at = now()
  WHERE role = 'administrator' AND permission_key = 'settings.manage_branches' AND is_deleted = false;
  UPDATE public.roles_permissions
  SET is_granted = true, updated_at = now()
  WHERE role = 'doctor' AND permission_key = 'patients.view' AND is_deleted = false;
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*)::int
  INTO v_failures
  FROM org_branch_crud_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'org_branch_management_crud failed % test(s): %',
      v_failures,
      (SELECT string_agg(test_name || ' (' || detail || ')', ', ') FROM org_branch_crud_results WHERE NOT passed);
  END IF;
END;
$$;

ROLLBACK;
