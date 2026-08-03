-- V1-3 transfer_patient and restore_patient verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_transfer_restore.sql

BEGIN;

CREATE TEMP TABLE patient_transfer_restore_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1600000-0000-4000-8000-000000000801';
  v_owner_staff uuid := 'b1600000-0000-4000-8000-000000000801';
  v_other_org_user uuid := 'a1600000-0000-4000-8000-000000000802';
  v_other_org_staff uuid := 'b1600000-0000-4000-8000-000000000802';
  v_other_org_id uuid := 'c1600000-0000-4000-8000-000000000801';
  v_other_branch_id uuid := 'd1600000-0000-4000-8000-000000000801';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_branch_second uuid;
  v_patient_id uuid;
  v_db_branch_id uuid;
  v_audit_count int;
  v_is_deleted boolean;
  v_random_uuid uuid := 'f1600000-0000-4000-8000-000000000899';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id IN (v_other_org_staff);
  DELETE FROM public.staff_members WHERE id IN (v_other_org_staff);
  DELETE FROM public.branches WHERE id = v_other_branch_id;
  DELETE FROM public.organizations WHERE id = v_other_org_id;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_other_org_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v16-transfer-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_other_org_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v16-other-org',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V16 Transfer Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Second', NULL, NULL, 'SEC', NULL);
  v_branch_second := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_other_org_id, 'Other Org', v_other_org_user, v_other_org_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES (v_other_branch_id, v_other_org_id, 'Other Branch', 'OTH', v_other_org_user, v_other_org_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_other_org_staff, v_other_org_user, 'Other Admin', 'administrator', false, v_other_org_user, v_other_org_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_owner_staff, v_branch_second, false, v_bootstrap_user, v_bootstrap_user),
    (v_other_org_staff, v_other_branch_id, true, v_other_org_user, v_other_org_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text || ',' || v_branch_second::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_branch_main, 'Transfer Patient', '201600000801', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  -- transfer_patient: success between branches same org
  v_result := public.transfer_patient(v_patient_id, v_branch_second);
  SELECT p.branch_id INTO v_db_branch_id FROM public.patients p WHERE p.id = v_patient_id;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_transfer_restore_results VALUES (
    'transfer_patient_success',
    v_result.success AND v_db_branch_id = v_branch_second,
    format('branch=%s', v_db_branch_id)
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.record_id = v_patient_id
    AND al.action = 'patient.transfer'
    AND al.new_data_json ->> 'branch_id' = v_branch_second::text;
  INSERT INTO patient_transfer_restore_results VALUES (
    'transfer_patient_writes_audit_log',
    v_audit_count = 1,
    'audit_count=' || v_audit_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- transfer_patient: idempotent when same branch
  v_result := public.transfer_patient(v_patient_id, v_branch_second);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_transfer_restore_results VALUES (
    'transfer_patient_idempotent_same_branch',
    v_result.success AND (v_result.data ->> 'new_branch_id')::uuid = v_branch_second,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- transfer_patient: PATIENT_ARCHIVED
  v_result := public.archive_patient(v_patient_id);
  v_result := public.transfer_patient(v_patient_id, v_branch_main);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_transfer_restore_results VALUES (
    'transfer_patient_rejects_archived',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ARCHIVED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- restore_patient: success after archive
  v_result := public.restore_patient(v_patient_id);
  SELECT p.is_deleted INTO v_is_deleted FROM public.patients p WHERE p.id = v_patient_id;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_transfer_restore_results VALUES (
    'restore_patient_success',
    v_result.success AND NOT v_is_deleted,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- transfer_patient: INVALID_BRANCH for branch in different org
  v_result := public.transfer_patient(v_patient_id, v_other_branch_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_transfer_restore_results VALUES (
    'transfer_patient_rejects_cross_org_branch',
    NOT v_result.success AND v_result.error_code = 'INVALID_BRANCH',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- restore_patient: INVALID_STATE when not archived
  v_result := public.restore_patient(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_transfer_restore_results VALUES (
    'restore_patient_rejects_not_archived',
    NOT v_result.success AND v_result.error_code = 'INVALID_STATE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- restore_patient: NOT_FOUND for random uuid
  v_result := public.restore_patient(v_random_uuid);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_transfer_restore_results VALUES (
    'restore_patient_not_found',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  SELECT count(*)::int
  INTO v_failed
  FROM patient_transfer_restore_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM patient_transfer_restore_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'patient_transfer_restore: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
