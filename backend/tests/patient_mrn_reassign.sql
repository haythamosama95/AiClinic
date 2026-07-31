-- MRN reassignment: admin-only, duplicate validation, audit trail.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_mrn_reassign.sql

BEGIN;

CREATE TEMP TABLE mrn_reassign_results (
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
  v_admin_user uuid := 'a2000000-0000-4000-8000-000000000301';
  v_admin_staff uuid := 'b2000000-0000-4000-8000-000000000301';
  v_receptionist_user uuid := 'a2000000-0000-4000-8000-000000000302';
  v_receptionist_staff uuid := 'b2000000-0000-4000-8000-000000000302';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_1 uuid;
  v_patient_2 uuid;
  v_patient_archived uuid;
  v_mrn_1 text;
  v_mrn_2 text;
  v_new_mrn text := 'MRN-000099';
  v_stored_mrn text;
  v_audit_action text;
  v_audit_old_mrn text;
  v_audit_new_mrn text;
  v_audit_user_id uuid;
  v_audit_org_id uuid;
  v_audit_timestamp timestamptz;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'development', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_admin_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mrn-reassign-admin',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_receptionist_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mrn-reassign-receptionist',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('MRN Reassign Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MRN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_admin_staff, v_admin_user, 'MRN Admin', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_receptionist_staff, v_receptionist_user, 'MRN Receptionist', 'receptionist', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_admin_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_receptionist_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user);

  PERFORM setval('public.patient_mrn_seq', 1, false);

  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_main);

  v_result := public.create_patient(v_branch_main, 'Patient One', '201000000201', NULL, NULL, NULL, NULL, false);
  v_patient_1 := (v_result.data ->> 'patient_id')::uuid;
  v_mrn_1 := v_result.data ->> 'mrn';

  v_result := public.create_patient(v_branch_main, 'Patient Two', '201000000202', NULL, NULL, NULL, NULL, false);
  v_patient_2 := (v_result.data ->> 'patient_id')::uuid;
  v_mrn_2 := v_result.data ->> 'mrn';

  -- Administrator succeeds.
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.audit_log;
  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_main);
  v_result := public.reassign_patient_mrn(v_patient_1, v_new_mrn);

  PERFORM set_config('role', 'postgres', true);
  SELECT mrn INTO v_stored_mrn FROM public.patients WHERE id = v_patient_1;

  SELECT action, old_data_json ->> 'mrn', new_data_json ->> 'mrn', user_id, organization_id, created_at
  INTO v_audit_action, v_audit_old_mrn, v_audit_new_mrn, v_audit_user_id, v_audit_org_id, v_audit_timestamp
  FROM public.audit_log
  WHERE action = 'patient.mrn_reassign'
    AND record_id = v_patient_1
  ORDER BY created_at DESC
  LIMIT 1;

  INSERT INTO mrn_reassign_results VALUES (
    'administrator_reassign_succeeds',
    v_result.success
      AND (v_result.data ->> 'mrn') = v_new_mrn
      AND (v_result.data ->> 'patient_id')::uuid = v_patient_1
      AND v_stored_mrn = v_new_mrn,
    'result_mrn=' || COALESCE(v_result.data ->> 'mrn', '<null>')
      || ' stored=' || COALESCE(v_stored_mrn, '<null>')
  );

  INSERT INTO mrn_reassign_results VALUES (
    'audit_row_patient_mrn_reassign',
    v_audit_action = 'patient.mrn_reassign'
      AND v_audit_old_mrn = v_mrn_1
      AND v_audit_new_mrn = v_new_mrn
      AND v_audit_user_id = v_admin_user
      AND v_audit_org_id = v_org_id
      AND v_audit_timestamp IS NOT NULL,
    'action=' || COALESCE(v_audit_action, '<null>')
      || ' old=' || COALESCE(v_audit_old_mrn, '<null>')
      || ' new=' || COALESCE(v_audit_new_mrn, '<null>')
  );

  -- Non-administrator → FORBIDDEN.
  PERFORM pg_temp.set_jwt(v_receptionist_user, v_receptionist_staff, 'receptionist', v_org_id, v_branch_main);
  v_result := public.reassign_patient_mrn(v_patient_2, 'MRN-000088');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO mrn_reassign_results VALUES (
    'non_administrator_forbidden',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Duplicate target → MRN_EXISTS; target row unchanged.
  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_main);
  v_result := public.reassign_patient_mrn(v_patient_2, v_new_mrn);

  PERFORM set_config('role', 'postgres', true);
  SELECT mrn INTO v_stored_mrn FROM public.patients WHERE id = v_patient_2;

  INSERT INTO mrn_reassign_results VALUES (
    'duplicate_mrn_exists_target_unchanged',
    NOT v_result.success
      AND v_result.error_code = 'MRN_EXISTS'
      AND v_stored_mrn = v_mrn_2,
    'error=' || COALESCE(v_result.error_code, '<null>')
      || ' stored=' || COALESCE(v_stored_mrn, '<null>')
  );

  -- Malformed value → INVALID_INPUT.
  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_main);
  v_result := public.reassign_patient_mrn(v_patient_2, 'BAD-FORMAT');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO mrn_reassign_results VALUES (
    'malformed_mrn_invalid_input',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Same-as-current → INVALID_INPUT.
  v_result := public.reassign_patient_mrn(v_patient_2, v_mrn_2);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO mrn_reassign_results VALUES (
    'same_as_current_invalid_input',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- Archived patient → PATIENT_ARCHIVED.
  PERFORM pg_temp.set_jwt(v_admin_user, v_admin_staff, 'administrator', v_org_id, v_branch_main);
  v_result := public.archive_patient(v_patient_2);
  v_patient_archived := v_patient_2;

  v_result := public.reassign_patient_mrn(v_patient_archived, 'MRN-000077');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO mrn_reassign_results VALUES (
    'archived_patient_rejected',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ARCHIVED',
    COALESCE(v_result.error_code, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM mrn_reassign_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'patient_mrn_reassign failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM mrn_reassign_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM mrn_reassign_results ORDER BY test_name;
