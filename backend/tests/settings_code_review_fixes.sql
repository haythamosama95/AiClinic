-- Code review fix verification: permission gates, batch updates, org-scoped branches, delete precedence.
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/settings_code_review_fixes.sql

BEGIN;

CREATE TEMP TABLE settings_code_review_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_admin_user uuid := 'a1000000-0000-4000-8000-000000000001';
  v_admin_staff uuid := 'b1000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'd0000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'd1000000-0000-4000-8000-000000000001';
  v_other_org_id uuid;
  v_other_branch_id uuid;
  v_org_id uuid;
  v_branch_id uuid;
  v_receptionist_staff_id uuid;
  v_result public.rpc_result;
  v_username_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff, v_admin_staff, v_doctor_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_admin_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_admin_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scr-admin',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scr-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('SCR Primary Clinic');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', '1 Main St', '+1', 'MAIN', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  v_result := public.bootstrap_create_organization('SCR Other Clinic');
  v_other_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_other_org_id, 'Other', '2 Other St', '+2', 'OTHR', NULL);
  v_other_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_admin_staff, v_admin_user, 'SCR Admin', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'SCR Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_id, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_admin_staff), (v_doctor_staff)) AS s(id);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_staff_account(
    'scr-reception',
    'password1',
    'SCR Receptionist',
    'receptionist',
    ARRAY[v_branch_id]
  );
  v_receptionist_staff_id := (v_result.data ->> 'staff_member_id')::uuid;

  -- staff_login_usernames allowed for manage_staff caller.
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO settings_code_review_results VALUES (
    'staff_login_usernames_admin_can_query',
    EXISTS (
      SELECT 1
      FROM public.staff_login_usernames(ARRAY[v_receptionist_staff_id]) u
      WHERE u.username = 'scr-reception'
    ),
    'admin with manage_staff'
  );

  -- staff_login_usernames denied for doctor without manage_staff.
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

  SELECT count(*)::int INTO v_username_count
  FROM public.staff_login_usernames(ARRAY[v_receptionist_staff_id]);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO settings_code_review_results VALUES (
    'staff_login_usernames_doctor_denied',
    v_username_count = 0,
    'doctor rows=' || v_username_count::text
  );

  -- Cross-org branch assignment rejected.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_staff_account(
    'scr-cross-org',
    'password1',
    'Cross Org Staff',
    'receptionist',
    ARRAY[v_other_branch_id]
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO settings_code_review_results VALUES (
    'create_staff_cross_org_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Active last administrator delete returns STAFF_STILL_ACTIVE (not LAST_ADMINISTRATOR).
  UPDATE public.roles_permissions
  SET is_granted = true, updated_at = now()
  WHERE role = 'doctor' AND permission_key = 'settings.manage_staff' AND is_deleted = false;

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

  v_result := public.delete_staff_member(v_admin_staff);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO settings_code_review_results VALUES (
    'delete_active_last_admin_returns_still_active',
    NOT v_result.success AND v_result.error_code = 'STAFF_STILL_ACTIVE',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Batch role permission update applies atomically.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.update_role_permissions(
    jsonb_build_array(
      jsonb_build_object('role', 'doctor', 'permission_key', 'patients.view', 'is_granted', false),
      jsonb_build_object('role', 'doctor', 'permission_key', 'patients.view', 'is_granted', true)
    )
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO settings_code_review_results VALUES (
    'update_role_permissions_batch_success',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_failures FROM settings_code_review_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'settings_code_review_fixes failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM settings_code_review_results WHERE NOT passed
    );
  END IF;
END;
$$;

ROLLBACK;
