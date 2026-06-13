-- delete_staff_member RPC verification for settings staff lifecycle.
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/delete_staff_member.sql

BEGIN;

CREATE TEMP TABLE delete_staff_member_results (
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
  v_deleted_count int;
  v_audit_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff, v_owner_staff, v_doctor_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dsm-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dsm-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('DSM Delete Clinic');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', '1 Main St', '+1', 'MAIN', NULL);
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
    'dsm-reception',
    'password1',
    'DSM Receptionist',
    'receptionist',
    ARRAY[v_branch_id]
  );
  v_receptionist_id := (v_result.data ->> 'staff_member_id')::uuid;

  -- Active staff cannot be deleted.
  v_result := public.delete_staff_member(v_receptionist_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO delete_staff_member_results VALUES (
    'delete_active_staff_rejected',
    NOT v_result.success AND v_result.error_code = 'STAFF_STILL_ACTIVE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cannot delete own account.
  v_result := public.delete_staff_member(v_owner_staff);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO delete_staff_member_results VALUES (
    'delete_self_rejected',
    NOT v_result.success AND v_result.error_code = 'CANNOT_DELETE_SELF',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Deactivate then delete succeeds.
  v_result := public.set_staff_active(v_receptionist_id, false);
  v_result := public.delete_staff_member(v_receptionist_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO delete_staff_member_results VALUES (
    'delete_inactive_staff_success',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT count(*)::int INTO v_deleted_count
  FROM public.staff_members sm
  WHERE sm.id = v_receptionist_id AND sm.is_deleted = true;
  INSERT INTO delete_staff_member_results VALUES (
    'delete_marks_is_deleted',
    v_deleted_count = 1,
    'deleted_rows=' || v_deleted_count::text
  );

  SELECT count(*)::int INTO v_audit_count
  FROM public.audit_log al
  WHERE al.organization_id = v_org_id AND al.action = 'staff.delete' AND al.record_id = v_receptionist_id;
  INSERT INTO delete_staff_member_results VALUES (
    'delete_writes_audit_log',
    v_audit_count >= 1,
    'count=' || v_audit_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Second delete is not found (soft-deleted row excluded).
  v_result := public.delete_staff_member(v_receptionist_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO delete_staff_member_results VALUES (
    'delete_already_deleted_rejected',
    NOT v_result.success AND v_result.error_code = 'STAFF_NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Doctor without manage_staff permission is forbidden.
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
  v_result := public.delete_staff_member(v_doctor_staff);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO delete_staff_member_results VALUES (
    'delete_doctor_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM delete_staff_member_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM delete_staff_member_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'delete_staff_member: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
