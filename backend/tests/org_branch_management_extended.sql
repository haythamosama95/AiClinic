-- V1-2 org/branch/staff management: extended coverage.
-- Covers: branch metadata update, code case sensitivity, role restrictions,
-- staff self-management, edge cases in deactivation, audit trail.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_extended.sql

BEGIN;

CREATE TEMP TABLE org_ext_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a6000000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b6000000-0000-4000-8000-000000000001';
  v_admin_user uuid := 'a6000000-0000-4000-8000-000000000002';
  v_admin_staff uuid := 'b6000000-0000-4000-8000-000000000002';
  v_doctor_user uuid := 'a6000000-0000-4000-8000-000000000003';
  v_doctor_staff uuid := 'b6000000-0000-4000-8000-000000000003';
  v_receptionist_user uuid := 'a6000000-0000-4000-8000-000000000004';
  v_receptionist_staff uuid := 'b6000000-0000-4000-8000-000000000004';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_branch_second uuid;
  v_branch_third uuid;
  v_staff_name text;
  v_branch_name text;
  v_audit_count int;
  v_active_count int;
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
  -- ===========================================================================
  -- FIXTURE SETUP
  -- ===========================================================================
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_admin_user, v_doctor_user, v_receptionist_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'org-ext-owner',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_admin_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'org-ext-admin',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'org-ext-doctor',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_receptionist_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'org-ext-recep',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.bootstrap_create_organization('Org Ext Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', '1 Main St', '+1234567890', 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_admin_staff, v_admin_user, 'Admin', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_receptionist_staff, v_receptionist_user, 'Receptionist', 'receptionist', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_main, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_admin_staff), (v_doctor_staff), (v_receptionist_staff)) AS s(id);

  -- ===========================================================================
  -- BRANCH CREATE: role restrictions
  -- ===========================================================================

  -- Doctor cannot create branch.
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
  v_result := public.manage_create_branch('Doctor Branch', v_working_schedule, 'DOC', NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_create_doctor_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Receptionist cannot create branch.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_receptionist_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_receptionist_staff::text,
      'staff_role', 'receptionist',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.manage_create_branch('Recep Branch', v_working_schedule, 'REC', NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_create_receptionist_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Owner can create branch.
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
  v_result := public.manage_create_branch('Second Branch', v_working_schedule, 'SEC', '2 Sec St', '+9876543210', NULL);
  v_branch_second := (v_result.data ->> 'branch_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_create_owner_success',
    v_result.success AND v_branch_second IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- BRANCH CREATE: empty name rejected
  -- ===========================================================================

  v_result := public.manage_create_branch('   ', v_working_schedule, 'EMPTY', NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_create_empty_name_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- BRANCH CREATE: empty code rejected
  -- ===========================================================================

  v_result := public.manage_create_branch('No Code', v_working_schedule, '   ', NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_create_empty_code_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- BRANCH CREATE: duplicate code (case-insensitive)
  -- ===========================================================================

  v_result := public.manage_create_branch('Third Branch', v_working_schedule, 'sec', NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_create_duplicate_code_case_insensitive',
    NOT v_result.success AND v_result.error_code = 'DUPLICATE_CODE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Unique code succeeds.
  v_result := public.manage_create_branch('Third Branch', v_working_schedule, 'THR', NULL, NULL, NULL);
  v_branch_third := (v_result.data ->> 'branch_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_create_unique_code_success',
    v_result.success AND v_branch_third IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- BRANCH DEACTIVATION: cannot deactivate last active branch
  -- ===========================================================================

  -- Deactivate two branches, then try to deactivate the last one.
  v_result := public.set_branch_active(v_branch_second, false);
  v_result := public.set_branch_active(v_branch_third, false);
  v_result := public.set_branch_active(v_branch_main, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_deactivate_last_prevented',
    NOT v_result.success AND v_result.error_code = 'LAST_ACTIVE_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Reactivate all for subsequent tests.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches SET is_active = true
  WHERE id IN (v_branch_main, v_branch_second, v_branch_third);
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- BRANCH ACTIVATION: reactivate succeeds
  -- ===========================================================================

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text || ',' || v_branch_second::text || ',' || v_branch_third::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.set_branch_active(v_branch_second, false);
  v_result := public.set_branch_active(v_branch_second, true);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'branch_reactivate_success',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- ORGANIZATION UPDATE: metadata fields persisted correctly
  -- ===========================================================================

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
  v_result := public.update_organization('Updated Clinic Name', 'https://logo.png', 'EGP', 'Africa/Cairo', '{"lang":"ar"}'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'org_update_all_fields_success',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT name INTO v_branch_name FROM public.organizations WHERE id = v_org_id;
  INSERT INTO org_ext_results VALUES (
    'org_update_name_persisted',
    v_branch_name = 'Updated Clinic Name',
    'name=' || COALESCE(v_branch_name, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- STAFF: create_staff_account with empty username rejected
  -- ===========================================================================

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
  v_result := public.create_staff_account('', 'password1', 'Empty User', 'receptionist', ARRAY[v_branch_main]);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'staff_create_empty_username_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Empty password rejected.
  v_result := public.create_staff_account('valid-user', '', 'Empty Pass', 'receptionist', ARRAY[v_branch_main]);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'staff_create_empty_password_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Empty branches rejected.
  v_result := public.create_staff_account('valid-user2', 'password1', 'No Branch', 'receptionist', ARRAY[]::uuid[]);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'staff_create_empty_branches_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- STAFF DEACTIVATION: cannot deactivate self
  -- ===========================================================================

  v_result := public.set_staff_active(v_owner_staff, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'staff_self_deactivation_rejected',
    NOT v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- PERMISSION MATRIX: non-existent permission key
  -- ===========================================================================

  v_result := public.update_role_permission('receptionist', 'non.existent.key', true);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO org_ext_results VALUES (
    'permission_nonexistent_key_rejected',
    NOT v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- ORGANIZATION UPDATE: audit trail written
  -- ===========================================================================

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_audit_count
  FROM public.audit_log al
  WHERE al.organization_id = v_org_id AND al.action = 'organization.update';
  INSERT INTO org_ext_results VALUES (
    'org_update_audit_log_written',
    v_audit_count >= 1,
    'count=' || v_audit_count::text
  );

  -- ===========================================================================
  -- BRANCH: deactivation writes audit
  -- ===========================================================================
  SELECT count(*)::int INTO v_audit_count
  FROM public.audit_log al
  WHERE al.organization_id = v_org_id AND al.action LIKE 'branch.%';
  INSERT INTO org_ext_results VALUES (
    'branch_deactivation_has_audit',
    v_audit_count >= 1,
    'count=' || v_audit_count::text
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM org_ext_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM org_ext_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'org_branch_management_extended: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
