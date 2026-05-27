-- admin_reset_staff_password RPC verification for US7 (administrator password reset).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/admin_reset_staff_password.sql

BEGIN;

-- Ensure denial-test fixtures exist (other SQL tests may have removed them).
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  (
    'd0000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'staff-doctor',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
VALUES
  (
    'd1000000-0000-4000-8000-000000000001',
    'd0000000-0000-4000-8000-000000000001',
    'Clinic Doctor',
    'doctor',
    false,
    'a0000000-0000-4000-8000-000000000001',
    'a0000000-0000-4000-8000-000000000001'
  )
ON CONFLICT (id) DO NOTHING;

CREATE TEMP TABLE admin_reset_password_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'd0000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'd1000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_receptionist_staff_id uuid;
  v_new_password text := 'reset-pass-42';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id NOT IN (v_bootstrap_staff, v_doctor_staff);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE email LIKE 'us7-%';
  DELETE FROM public.patients;
  DELETE FROM public.branches;
  DELETE FROM public.organizations;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('US7 Reset Clinic');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Reset Branch', '1 Test St', '+1', 'RST', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_reset_password_results VALUES (
    'fixture_org_and_branch_ready',
    v_org_id IS NOT NULL AND v_branch_id IS NOT NULL,
    'org=' || COALESCE(v_org_id::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_staff_account(
    'us7-reception',
    'initial-pass1',
    'US7 Receptionist',
    'receptionist',
    ARRAY[v_branch_id]
  );
  v_receptionist_staff_id := (v_result.data ->> 'staff_member_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_reset_password_results VALUES (
    'fixture_receptionist_created',
    v_receptionist_staff_id IS NOT NULL,
    'staff_id=' || COALESCE(v_receptionist_staff_id::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: empty password.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text
    )::text,
    true
  );
  v_result := public.admin_reset_staff_password(v_receptionist_staff_id, '   ');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_reset_password_results VALUES (
    'reset_empty_password_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Corner case: unknown staff id.
  v_result := public.admin_reset_staff_password('00000000-0000-0000-0000-000000000099', v_new_password);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_reset_password_results VALUES (
    'reset_unknown_staff_rejected',
    NOT v_result.success AND v_result.error_code = 'STAFF_NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Advanced: doctor cannot reset passwords.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'staff_member_id', v_doctor_staff::text
    )::text,
    true
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_doctor_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT DO NOTHING;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.admin_reset_staff_password(v_receptionist_staff_id, v_new_password);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_reset_password_results VALUES (
    'reset_doctor_caller_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Happy path: bootstrap administrator resets receptionist password.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'staff_member_id', v_bootstrap_staff::text
    )::text,
    true
  );
  v_result := public.admin_reset_staff_password(v_receptionist_staff_id, v_new_password);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_reset_password_results VALUES (
    'bootstrap_admin_resets_receptionist_password',
    v_result.success AND (v_result.data ->> 'password_reset')::boolean = true,
    'password_reset=' || COALESCE(v_result.data ->> 'password_reset', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO admin_reset_password_results VALUES (
    'reset_writes_audit_log',
    EXISTS (
      SELECT 1
      FROM public.audit_log al
      WHERE al.action = 'staff.password_reset'
        AND al.record_id = v_receptionist_staff_id
    ),
    'audit row for staff.password_reset'
  );
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_failures FROM admin_reset_password_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'admin_reset_staff_password failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM admin_reset_password_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM admin_reset_password_results ORDER BY test_name;
