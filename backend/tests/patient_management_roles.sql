-- V1-3 patient management: role-based access control matrix.
-- Tests all five staff roles against all patient RPCs.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_management_roles.sql

BEGIN;

CREATE TEMP TABLE patient_role_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(
  p_user uuid,
  p_staff uuid,
  p_role text,
  p_org uuid,
  p_branch uuid
)
RETURNS void
LANGUAGE plpgsql
AS $jwt$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user::text,
      'role', 'authenticated',
      'organization_id', p_org::text,
      'branch_ids', p_branch::text,
      'staff_member_id', p_staff::text,
      'staff_role', p_role,
      'setup_required', false
    )::text,
    true
  );
END;
$jwt$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a3000000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b3000000-0000-4000-8000-000000000001';
  v_admin_user uuid := 'a3000000-0000-4000-8000-000000000002';
  v_admin_staff uuid := 'b3000000-0000-4000-8000-000000000002';
  v_doctor_user uuid := 'a3000000-0000-4000-8000-000000000003';
  v_doctor_staff uuid := 'b3000000-0000-4000-8000-000000000003';
  v_receptionist_user uuid := 'a3000000-0000-4000-8000-000000000004';
  v_receptionist_staff uuid := 'b3000000-0000-4000-8000-000000000004';
  v_lab_user uuid := 'a3000000-0000-4000-8000-000000000005';
  v_lab_staff uuid := 'b3000000-0000-4000-8000-000000000005';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_patient_id uuid;
  v_updated_at timestamptz;
BEGIN
  -- ===========================================================================
  -- FIXTURE SETUP
  -- ===========================================================================
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.patients;
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id NOT IN (v_bootstrap_staff);
  DELETE FROM public.audit_log;
  DELETE FROM public.branches;
  PERFORM auth_internal.delete_billing_dependents();
  DELETE FROM public.organizations;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_admin_user, v_doctor_user, v_receptionist_user, v_lab_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'role-owner',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_admin_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'role-admin',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'role-doctor',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_receptionist_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'role-receptionist',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'role-lab',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Roles Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'ROLE', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Owner', 'owner', false, v_bootstrap_user, v_bootstrap_user),
    (v_admin_staff, v_admin_user, 'Admin', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_receptionist_staff, v_receptionist_user, 'Receptionist', 'receptionist', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Lab Tech', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_id, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_admin_staff), (v_doctor_staff), (v_receptionist_staff), (v_lab_staff)) AS s(id);

  -- Ensure default permission grants are in place.
  UPDATE public.roles_permissions SET is_granted = true, updated_at = now()
  WHERE permission_key IN ('patients.view', 'patients.create', 'patients.edit', 'patients.delete')
    AND role IN ('owner', 'administrator', 'doctor', 'receptionist')
    AND is_deleted = false;
  UPDATE public.roles_permissions SET is_granted = true, updated_at = now()
  WHERE permission_key = 'patients.view'
    AND role = 'lab_staff'
    AND is_deleted = false;
  UPDATE public.roles_permissions SET is_granted = false, updated_at = now()
  WHERE permission_key IN ('patients.create', 'patients.edit', 'patients.delete')
    AND role = 'lab_staff'
    AND is_deleted = false;

  -- ===========================================================================
  -- OWNER: full access
  -- ===========================================================================
  PERFORM pg_temp.set_jwt(v_owner_user, v_owner_staff, 'owner', v_org_id, v_branch_id);

  v_result := public.search_patients(NULL, 'branch', v_branch_id, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('owner_search', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_owner_user, v_owner_staff, 'owner', v_org_id, v_branch_id);
  v_result := public.create_patient(v_branch_id, 'Owner Patient', '201000000101', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('owner_create', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_owner_user, v_owner_staff, 'owner', v_org_id, v_branch_id);
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('owner_get', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_owner_user, v_owner_staff, 'owner', v_org_id, v_branch_id);
  v_result := public.update_patient(v_patient_id, 'Owner Patient Ed', v_updated_at, NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('owner_update', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_owner_user, v_owner_staff, 'owner', v_org_id, v_branch_id);
  v_result := public.check_patient_duplicates('Owner Patient Ed', '201000000101', NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('owner_check_dup', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_owner_user, v_owner_staff, 'owner', v_org_id, v_branch_id);
  v_result := public.archive_patient(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('owner_archive', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- ADMINISTRATOR: full access
  -- ===========================================================================
  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_id);

  v_result := public.search_patients(NULL, 'branch', v_branch_id, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('admin_search', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_id);
  v_result := public.create_patient(v_branch_id, 'Admin Patient', '201000000102', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('admin_create', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_id);
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('admin_get', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_id);
  v_result := public.update_patient(v_patient_id, 'Admin Patient Ed', v_updated_at, NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('admin_update', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_id);
  v_result := public.check_patient_duplicates('Admin Patient Ed', '201000000102', NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('admin_check_dup', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_id);
  v_result := public.archive_patient(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('admin_archive', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- DOCTOR: full access (default permissions grant patients.*)
  -- ===========================================================================
  PERFORM pg_temp.set_jwt(v_doctor_user, v_doctor_staff, 'doctor', v_org_id, v_branch_id);

  v_result := public.search_patients(NULL, 'branch', v_branch_id, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('doctor_search', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_doctor_user, v_doctor_staff, 'doctor', v_org_id, v_branch_id);
  v_result := public.create_patient(v_branch_id, 'Doctor Patient', '201000000103', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('doctor_create', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_doctor_user, v_doctor_staff, 'doctor', v_org_id, v_branch_id);
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('doctor_get', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_doctor_user, v_doctor_staff, 'doctor', v_org_id, v_branch_id);
  v_result := public.update_patient(v_patient_id, 'Doctor Patient Ed', v_updated_at, NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('doctor_update', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_doctor_user, v_doctor_staff, 'doctor', v_org_id, v_branch_id);
  v_result := public.archive_patient(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('doctor_archive', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- RECEPTIONIST: full access (default permissions grant patients.*)
  -- ===========================================================================
  PERFORM pg_temp.set_jwt(v_receptionist_user, v_receptionist_staff, 'receptionist', v_org_id, v_branch_id);

  v_result := public.search_patients(NULL, 'branch', v_branch_id, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('receptionist_search', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_receptionist_user, v_receptionist_staff, 'receptionist', v_org_id, v_branch_id);
  v_result := public.create_patient(v_branch_id, 'Reception Patient', '201000000104', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('receptionist_create', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_receptionist_user, v_receptionist_staff, 'receptionist', v_org_id, v_branch_id);
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('receptionist_get', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_receptionist_user, v_receptionist_staff, 'receptionist', v_org_id, v_branch_id);
  v_result := public.update_patient(v_patient_id, 'Reception Patient Ed', v_updated_at, NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('receptionist_update', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_receptionist_user, v_receptionist_staff, 'receptionist', v_org_id, v_branch_id);
  v_result := public.check_patient_duplicates('Reception Patient Ed', '201000000104', NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('receptionist_check_dup', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_receptionist_user, v_receptionist_staff, 'receptionist', v_org_id, v_branch_id);
  v_result := public.archive_patient(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('receptionist_archive', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- LAB_STAFF: view only (search + get), all mutations forbidden
  -- ===========================================================================
  PERFORM pg_temp.set_jwt(v_lab_user, v_lab_staff, 'lab_staff', v_org_id, v_branch_id);

  v_result := public.search_patients(NULL, 'branch', v_branch_id, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('lab_search', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  -- Create a patient as owner for lab to view.
  PERFORM pg_temp.set_jwt(v_owner_user, v_owner_staff, 'owner', v_org_id, v_branch_id);
  v_result := public.create_patient(v_branch_id, 'Lab View Target', '201000000105', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;

  PERFORM pg_temp.set_jwt(v_lab_user, v_lab_staff, 'lab_staff', v_org_id, v_branch_id);
  v_result := public.get_patient(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES ('lab_get', v_result.success, COALESCE(v_result.error_code, 'ok'));
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_lab_user, v_lab_staff, 'lab_staff', v_org_id, v_branch_id);
  v_result := public.create_patient(v_branch_id, 'Lab Create Attempt', '201000000106', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES (
    'lab_create_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_lab_user, v_lab_staff, 'lab_staff', v_org_id, v_branch_id);
  v_result := public.update_patient(v_patient_id, 'Lab Update', v_updated_at, NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES (
    'lab_update_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_lab_user, v_lab_staff, 'lab_staff', v_org_id, v_branch_id);
  v_result := public.archive_patient(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES (
    'lab_archive_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_lab_user, v_lab_staff, 'lab_staff', v_org_id, v_branch_id);
  v_result := public.check_patient_duplicates('Lab View Target', '201000000105', NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES (
    'lab_check_dup_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- PERMISSION REVOCATION: revoke patients.create from receptionist then test
  -- ===========================================================================
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.roles_permissions
  SET is_granted = false, updated_at = now()
  WHERE role = 'receptionist' AND permission_key = 'patients.create' AND is_deleted = false;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_receptionist_user, v_receptionist_staff, 'receptionist', v_org_id, v_branch_id);
  v_result := public.create_patient(v_branch_id, 'Revoked Create', '201000000107', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES (
    'receptionist_revoked_create_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Restore permission for cleanup.
  UPDATE public.roles_permissions
  SET is_granted = true, updated_at = now()
  WHERE role = 'receptionist' AND permission_key = 'patients.create' AND is_deleted = false;
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- PERMISSION REVOCATION: revoke patients.view from lab_staff
  -- ===========================================================================
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.roles_permissions
  SET is_granted = false, updated_at = now()
  WHERE role = 'lab_staff' AND permission_key = 'patients.view' AND is_deleted = false;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_jwt(v_lab_user, v_lab_staff, 'lab_staff', v_org_id, v_branch_id);
  v_result := public.search_patients(NULL, 'branch', v_branch_id, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_role_results VALUES (
    'lab_revoked_view_search_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Restore.
  UPDATE public.roles_permissions
  SET is_granted = true, updated_at = now()
  WHERE role = 'lab_staff' AND permission_key = 'patients.view' AND is_deleted = false;
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM patient_role_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM patient_role_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'patient_management_roles: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
