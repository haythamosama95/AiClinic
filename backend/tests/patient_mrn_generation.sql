-- MRN generation constitution: sequential assignment, unique index, archived MRN not reused.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_mrn_generation.sql

BEGIN;

CREATE TEMP TABLE mrn_generation_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1000000-0000-4000-8000-000000000201';
  v_owner_staff uuid := 'b1000000-0000-4000-8000-000000000201';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_1 uuid;
  v_patient_2 uuid;
  v_patient_3 uuid;
  v_mrn_1 text;
  v_mrn_2 text;
  v_mrn_3 text;
  v_archived_mrn text;
  v_dup_failed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'development', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mrn-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('MRN Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES (v_owner_staff, v_owner_user, 'MRN Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user);

  PERFORM setval('public.patient_mrn_seq', 1, false);

  PERFORM set_config('role', 'authenticated', true);
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

  -- Consecutive create_patient calls return MRN-000001, MRN-000002, ...
  v_result := public.create_patient(v_branch_main, 'Patient One', '201000000101', NULL, NULL, NULL, NULL, false);
  v_patient_1 := (v_result.data ->> 'patient_id')::uuid;
  v_mrn_1 := v_result.data ->> 'mrn';

  v_result := public.create_patient(v_branch_main, 'Patient Two', '201000000102', NULL, NULL, NULL, NULL, false);
  v_patient_2 := (v_result.data ->> 'patient_id')::uuid;
  v_mrn_2 := v_result.data ->> 'mrn';

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO mrn_generation_results VALUES (
    'consecutive_create_returns_sequential_mrns',
    v_result.success
      AND v_mrn_1 = 'MRN-000001'
      AND v_mrn_2 = 'MRN-000002',
    'mrn1=' || COALESCE(v_mrn_1, '<null>') || ' mrn2=' || COALESCE(v_mrn_2, '<null>')
  );

  -- Manual duplicate INSERT rejected by unique index.
  v_dup_failed := false;
  BEGIN
  PERFORM set_config('role', 'postgres', true);
    INSERT INTO public.patients (branch_id, organization_id, full_name, phone, mrn, created_by, updated_by)
    VALUES (v_branch_main, v_org_id, 'Dup Patient', '201000000199', 'MRN-000001', v_owner_user, v_owner_user);
  EXCEPTION
    WHEN unique_violation THEN
      v_dup_failed := true;
  END;

  INSERT INTO mrn_generation_results VALUES (
    'unique_index_rejects_manual_duplicate_mrn',
    v_dup_failed,
    'duplicate insert ' || CASE WHEN v_dup_failed THEN 'rejected' ELSE 'succeeded unexpectedly' END
  );

  -- Archived patient's MRN is not reused; next create advances past archived value.
  PERFORM set_config('role', 'authenticated', true);
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

  SELECT mrn INTO v_archived_mrn FROM public.patients WHERE id = v_patient_1;
  v_result := public.archive_patient(v_patient_1);

  v_result := public.create_patient(v_branch_main, 'Patient Three', '201000000103', NULL, NULL, NULL, NULL, false);
  v_patient_3 := (v_result.data ->> 'patient_id')::uuid;
  v_mrn_3 := v_result.data ->> 'mrn';

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO mrn_generation_results VALUES (
    'archived_mrn_not_reused',
    v_result.success
      AND v_archived_mrn = 'MRN-000001'
      AND v_mrn_3 = 'MRN-000003'
      AND v_mrn_3 <> v_archived_mrn,
    'archived=' || COALESCE(v_archived_mrn, '<null>')
      || ' next=' || COALESCE(v_mrn_3, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM mrn_generation_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'patient_mrn_generation failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM mrn_generation_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM mrn_generation_results ORDER BY test_name;
