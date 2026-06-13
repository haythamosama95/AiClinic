-- Role permission matrix RPC verification (full catalog + delegation rules).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/role_permissions_matrix.sql

BEGIN;

CREATE TEMP TABLE role_permissions_matrix_results (
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
  v_doctor_user uuid := 'd0000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'd1000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_grant boolean;
  v_catalog_count int;
  v_matrix_count int;
  v_role_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff, v_owner_staff, v_doctor_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rpm-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rpm-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('RPM Matrix Clinic');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Clinic Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_id, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_doctor_staff)) AS s(id);

  SELECT count(DISTINCT permission_key)::int INTO v_catalog_count
  FROM public.roles_permissions
  WHERE is_deleted = false;

  SELECT count(*)::int INTO v_matrix_count
  FROM public.roles_permissions rp
  WHERE rp.is_deleted = false
    AND rp.role IN ('administrator', 'doctor', 'receptionist', 'lab_staff');

  SELECT count(DISTINCT role)::int INTO v_role_count
  FROM public.roles_permissions
  WHERE is_deleted = false
    AND role IN ('administrator', 'doctor', 'receptionist', 'lab_staff');

  INSERT INTO role_permissions_matrix_results VALUES (
    'matrix_has_full_role_coverage',
    v_catalog_count > 0 AND v_matrix_count >= v_catalog_count * v_role_count,
    'catalog=' || v_catalog_count::text || ' matrix=' || v_matrix_count::text || ' roles=' || v_role_count::text
  );

  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
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
  INSERT INTO role_permissions_matrix_results VALUES (
    'administrator_toggle_permission_success',
    v_result.success AND v_grant = false,
    COALESCE(v_result.error_code, v_grant::text)
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore patients.view for downstream suites.
  v_result := public.update_role_permission('doctor', 'patients.view', true);

  v_result := public.update_role_permission('receptionist', 'settings.billing.manage', true);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO role_permissions_matrix_results VALUES (
    'billing_manage_not_delegable_to_receptionist',
    NOT v_result.success AND v_result.error_code = 'PERMISSION_NOT_DELEGABLE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_role_permission('receptionist', 'non.existent.key', true);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO role_permissions_matrix_results VALUES (
    'invalid_permission_key_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_PERMISSION',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_doctor_staff::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.update_role_permission('receptionist', 'patients.view', false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO role_permissions_matrix_results VALUES (
    'doctor_matrix_write_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM role_permissions_matrix_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM role_permissions_matrix_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'role_permissions_matrix: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
