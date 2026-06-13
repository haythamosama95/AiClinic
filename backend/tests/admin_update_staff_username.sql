-- admin_update_staff_username RPC verification for settings staff credential edits.
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/admin_update_staff_username.sql

BEGIN;

CREATE TEMP TABLE admin_update_username_results (
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
  v_receptionist_id uuid;
  v_receptionist_user uuid;
  v_email text;
  v_audit_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user) OR email LIKE 'aus8-%';

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'aus8-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'aus8-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('AUS8 Username Clinic');
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

  v_result := public.create_staff_account(
    'aus8-old',
    'password1',
    'AUS8 Receptionist',
    'receptionist',
    ARRAY[v_branch_id]
  );
  v_receptionist_id := (v_result.data ->> 'staff_member_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  SELECT sm.auth_user_id INTO v_receptionist_user
  FROM public.staff_members sm
  WHERE sm.id = v_receptionist_id;
  PERFORM set_config('role', 'authenticated', true);

  -- Happy path: username updated and normalized.
  v_result := public.admin_update_staff_username(v_receptionist_id, '  AUS8-New  ');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_update_username_results VALUES (
    'update_username_success',
    v_result.success AND (v_result.data ->> 'username') = 'aus8-new',
    COALESCE(v_result.error_code, v_result.data ->> 'username')
  );

  SELECT u.email INTO v_email FROM auth.users u WHERE u.id = v_receptionist_user;
  INSERT INTO admin_update_username_results VALUES (
    'update_username_persisted_in_auth_users',
    v_email = 'aus8-new',
    'email=' || COALESCE(v_email, '<null>')
  );

  -- Mixed-case username with underscore normalized.
  v_result := public.admin_update_staff_username(v_receptionist_id, 'User_Name');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_update_username_results VALUES (
    'update_username_normalize_underscore',
    v_result.success AND (v_result.data ->> 'username') = 'user_name',
    COALESCE(v_result.data ->> 'username', v_result.error_code)
  );
  SELECT u.email INTO v_email FROM auth.users u WHERE u.id = v_receptionist_user;
  INSERT INTO admin_update_username_results VALUES (
    'update_username_normalize_underscore_auth_users',
    v_email = 'user_name',
    'email=' || COALESCE(v_email, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_audit_count
  FROM public.audit_log al
  WHERE al.organization_id = v_org_id AND al.action = 'staff.username_update' AND al.record_id = v_receptionist_id;
  INSERT INTO admin_update_username_results VALUES (
    'update_username_writes_audit',
    v_audit_count >= 1,
    'count=' || v_audit_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Empty username rejected.
  v_result := public.admin_update_staff_username(v_receptionist_id, '   ');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_update_username_results VALUES (
    'update_username_empty_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Invalid username rejected.
  v_result := public.admin_update_staff_username(v_receptionist_id, 'ab');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_update_username_results VALUES (
    'update_username_invalid_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Duplicate username rejected.
  v_result := public.admin_update_staff_username(v_receptionist_id, 'aus8-owner');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_update_username_results VALUES (
    'update_username_exists_rejected',
    NOT v_result.success AND v_result.error_code = 'USERNAME_EXISTS',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Unknown staff id rejected.
  v_result := public.admin_update_staff_username('00000000-0000-4000-8000-000000009999', 'aus8-nobody');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_update_username_results VALUES (
    'update_username_staff_not_found',
    NOT v_result.success AND v_result.error_code = 'STAFF_NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Doctor caller forbidden.
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
  v_result := public.admin_update_staff_username(v_receptionist_id, 'aus8-hacked');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_update_username_results VALUES (
    'update_username_doctor_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cross-org staff id rejected (doctor is in same org; use random UUID as foreign scope).
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
  v_result := public.admin_update_staff_username('00000000-0000-4000-8000-000000009999', 'aus8-cross');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_update_username_results VALUES (
    'update_username_cross_org_denied',
    NOT v_result.success AND v_result.error_code IN ('CROSS_ORG_DENIED', 'STAFF_NOT_FOUND'),
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
  SELECT count(*)::int INTO v_failed FROM admin_update_username_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM admin_update_username_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'admin_update_staff_username: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
