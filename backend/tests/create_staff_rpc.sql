-- create_staff_account RPC verification for US6 (staff provisioning + FR-022c).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/create_staff_rpc.sql

BEGIN;

CREATE TEMP TABLE create_staff_rpc_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_admin_user uuid := 'e0000000-0000-4000-8000-0000000000a1';
  v_admin_staff uuid := 'f0000000-0000-4000-8000-0000000000a1';
  v_doctor_user uuid := 'd0000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'd1000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_owner_staff_id uuid;
  v_owner_auth_user uuid;
  v_receptionist_staff_id uuid;
  v_receptionist_auth_user uuid;
  v_receptionist_claims jsonb;
  v_owner_count int;
BEGIN
  -- Extra staff rows for denial tests.
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (
      v_admin_user,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'staff-admin',
      extensions.crypt('test-password', extensions.gen_salt('bf')),
      now(),
      now(),
      now()
    ),
    (
      v_doctor_user,
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
    (v_admin_staff, v_admin_user, 'Clinic Admin', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Clinic Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members
  WHERE id NOT IN (v_bootstrap_staff, v_admin_staff, v_doctor_staff);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE email LIKE 'us6-%'
     OR email IN ('owner-one', 'owner-two', 'reception');
  DELETE FROM public.patients;
  DELETE FROM public.branches;
  DELETE FROM public.organizations;

  UPDATE public.staff_members
  SET role = 'administrator', is_bootstrap_admin = true, is_active = true, is_deleted = false
  WHERE id = v_bootstrap_staff;

  PERFORM set_config('role', 'authenticated', true);

  -- Trivial: provisioning blocked before organization exists.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.create_staff_account(
    'us6-norg',
    'secret12',
    'No Org Receptionist',
    'receptionist',
    ARRAY[]::uuid[]
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_blocked_before_org_setup',
    NOT v_result.success AND v_result.error_code = 'ORG_SETUP_INCOMPLETE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Bootstrap org + branch for remaining tests.
  v_result := public.bootstrap_create_organization('US6 Test Clinic');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main Branch', '1 Test St', '+1', 'MAIN', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'fixture_org_and_branch_ready',
    v_org_id IS NOT NULL AND v_branch_id IS NOT NULL,
    'org=' || COALESCE(v_org_id::text, '<null>') || ' branch=' || COALESCE(v_branch_id::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid usage: empty branch list.
  v_result := public.create_staff_account(
    'us6-empty-branches',
    'secret12',
    'Empty Branches',
    'receptionist',
    ARRAY[]::uuid[]
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_empty_branch_ids_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Trivial: whitespace-only required fields.
  v_result := public.create_staff_account('   ', 'secret12', 'Whitespace Username', 'receptionist', ARRAY[v_branch_id]);
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_empty_username_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_staff_account('us6-nopass', '   ', 'No Password', 'receptionist', ARRAY[v_branch_id]);
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_empty_password_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_staff_account('us6-noname', 'secret12', '   ', 'receptionist', ARRAY[v_branch_id]);
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_empty_full_name_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Corner case: unknown branch id.
  v_result := public.create_staff_account(
    'us6-bad-branch',
    'secret12',
    'Bad Branch',
    'receptionist',
    ARRAY['00000000-0000-0000-0000-000000000099'::uuid]
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_invalid_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Corner case: primary branch outside assignment list.
  v_result := public.create_staff_account(
    'us6-bad-primary',
    'secret12',
    'Bad Primary',
    'receptionist',
    ARRAY[v_branch_id],
    '00000000-0000-0000-0000-000000000099'::uuid
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_primary_not_in_assignments_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Advanced: doctor role cannot provision staff.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_doctor_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.create_staff_account(
    'us6-doctor-create',
    'secret12',
    'Doctor Attempt',
    'receptionist',
    ARRAY[v_branch_id]
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_doctor_caller_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  -- FR-022c: bootstrap admin may create the first owner.
  v_result := public.create_staff_account(
    'owner-one',
    'owner-pass-1',
    '  First Owner  ',
    'owner',
    ARRAY[v_branch_id],
    v_branch_id
  );
  v_owner_staff_id := (v_result.data ->> 'staff_member_id')::uuid;
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'bootstrap_creates_first_owner',
    v_result.success AND v_owner_staff_id IS NOT NULL,
    'staff_id=' || COALESCE(v_owner_staff_id::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'owner_full_name_trimmed',
    EXISTS (
      SELECT 1
      FROM public.staff_members sm
      WHERE sm.id = v_owner_staff_id AND sm.full_name = 'First Owner'
    ),
    'stored name must be trimmed'
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Bootstrap admin cannot create a second owner once one exists.
  v_result := public.create_staff_account(
    'owner-bootstrap-second',
    'owner-pass-2',
    'Bootstrap Second Owner',
    'owner',
    ARRAY[v_branch_id]
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'bootstrap_blocked_second_owner',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN_OWNER_CREATE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Non-bootstrap administrator cannot create owner when owner exists.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_admin_staff, v_branch_id, true, v_admin_user, v_admin_user)
  ON CONFLICT DO NOTHING;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_staff_account(
    'owner-admin-attempt',
    'owner-pass9',
    'Admin Owner Attempt',
    'owner',
    ARRAY[v_branch_id]
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'admin_cannot_create_owner_when_owner_exists',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN_OWNER_CREATE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Happy path: administrator creates receptionist.
  v_result := public.create_staff_account(
    'reception',
    'recept-pass1',
    'Front Desk',
    'receptionist',
    ARRAY[v_branch_id]
  );
  v_receptionist_staff_id := (v_result.data ->> 'staff_member_id')::uuid;
PERFORM set_config('role', 'postgres', true);
  SELECT sm.auth_user_id
  INTO v_receptionist_auth_user
  FROM public.staff_members sm
  WHERE sm.id = v_receptionist_staff_id;
  INSERT INTO create_staff_rpc_results VALUES (
'provisioned_auth_user_gotrue_token_columns',
    NOT EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE u.id = v_receptionist_auth_user
        AND (
          u.confirmation_token IS NULL
          OR u.recovery_token IS NULL
          OR u.email_change IS NULL
          OR u.email_change_token_new IS NULL
        )
    ),
    'auth_user_id=' || COALESCE(v_receptionist_auth_user::text, '<null>')
  );

  v_receptionist_claims := auth_internal.build_staff_claims(v_receptionist_auth_user);
  INSERT INTO create_staff_rpc_results VALUES (
'provisioned_staff_jwt_claims_ready',
    (v_receptionist_claims ->> 'staff_member_id') = v_receptionist_staff_id::text
      AND (v_receptionist_claims ->> 'staff_role') = 'receptionist'
      AND COALESCE(v_receptionist_claims ->> 'branch_ids', '') <> '',
    'claims=' || v_receptionist_claims::text
  );

  INSERT INTO create_staff_rpc_results VALUES (
'admin_creates_receptionist',
    v_result.success
      AND v_receptionist_staff_id IS NOT NULL
      AND (v_result.data ->> 'username') = 'reception',
    'staff_id=' || COALESCE(v_receptionist_staff_id::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'receptionist_branch_assignment_primary',
    EXISTS (
      SELECT 1
      FROM public.staff_branch_assignments sba
      WHERE sba.staff_member_id = v_receptionist_staff_id
        AND sba.branch_id = v_branch_id
        AND sba.is_primary = true
        AND sba.is_deleted = false
    ),
    'primary branch assignment'
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Duplicate username rejected.
  v_result := public.create_staff_account(
    'reception',
    'other-pass1',
    'Duplicate Username',
    'doctor',
    ARRAY[v_branch_id]
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'staff_duplicate_username_rejected',
    NOT v_result.success AND v_result.error_code = 'USERNAME_EXISTS',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Owner may create an additional owner.
  PERFORM set_config('role', 'postgres', true);
  SELECT sm.auth_user_id
  INTO v_owner_auth_user
  FROM public.staff_members sm
  WHERE sm.id = v_owner_staff_id;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner_auth_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT v_owner_staff_id, v_branch_id, true, sm.auth_user_id, sm.auth_user_id
  FROM public.staff_members sm
  WHERE sm.id = v_owner_staff_id
  ON CONFLICT DO NOTHING;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_staff_account(
    'owner-two',
    'owner-pass-2',
    'Second Owner',
    'owner',
    ARRAY[v_branch_id]
  );
PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'owner_creates_additional_owner',
    v_result.success AND (v_result.data ->> 'staff_member_id') IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int
  INTO v_owner_count
  FROM public.staff_members sm
  WHERE sm.role = 'owner' AND sm.is_deleted = false;
  PERFORM set_config('role', 'authenticated', true);

PERFORM set_config('role', 'postgres', true);
  INSERT INTO create_staff_rpc_results VALUES (
'two_active_owners_exist',
    v_owner_count >= 2,
    'owner_count=' || v_owner_count::text
  );
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_failures FROM create_staff_rpc_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'create_staff_rpc failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM create_staff_rpc_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM create_staff_rpc_results ORDER BY test_name;
