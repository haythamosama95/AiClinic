-- Fix 24: Concurrent access test for patient phone uniqueness.
-- Verifies that the unique index (patients_org_phone_unique_idx) catches duplicate
-- phone numbers within the same organization, simulating what would happen if two
-- concurrent transactions both passed the advisory check.
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/patient_management_concurrent.sql

BEGIN;

CREATE TEMP TABLE concurrent_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_org_id uuid;
  v_branch_id uuid;
  v_patient1_id uuid;
  v_patient2_id uuid;
  v_got_violation boolean := false;
  v_result public.rpc_result;
BEGIN
  -- Setup: ensure org and branch exist
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.patients WHERE true;
  DELETE FROM public.staff_branch_assignments WHERE true;
  DELETE FROM public.audit_log WHERE true;
  DELETE FROM public.branches WHERE true;
  PERFORM auth_internal.delete_billing_dependents();
  DELETE FROM public.organizations WHERE true;

  -- Create org and branch directly for test isolation
  INSERT INTO public.organizations (id, name, currency_code, timezone, created_by, updated_by)
  VALUES ('d1000000-0000-4000-8000-000000000c01', 'Concurrent Test Org', 'EGP', 'UTC', v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  v_org_id := 'd1000000-0000-4000-8000-000000000c01';

  INSERT INTO public.branches (id, organization_id, name, code, is_active, created_by, updated_by)
  VALUES ('d2000000-0000-4000-8000-000000000c02', v_org_id, 'Concurrent Branch', 'CONC', true, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  v_branch_id := 'd2000000-0000-4000-8000-000000000c02';

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_bootstrap_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (staff_member_id, branch_id) DO UPDATE
  SET is_deleted = false, is_primary = true;

  -- Insert first patient with phone '01001234567'
  v_patient1_id := gen_random_uuid();
  INSERT INTO public.patients (id, organization_id, branch_id, full_name, phone, is_deleted, created_by, updated_by)
  VALUES (v_patient1_id, v_org_id, v_branch_id, 'Patient One', '01001234567', false, v_bootstrap_user, v_bootstrap_user);

  -- Attempt to insert second patient with the same phone in same org
  BEGIN
    v_patient2_id := gen_random_uuid();
    INSERT INTO public.patients (id, organization_id, branch_id, full_name, phone, is_deleted, created_by, updated_by)
    VALUES (v_patient2_id, v_org_id, v_branch_id, 'Patient Two', '01001234567', false, v_bootstrap_user, v_bootstrap_user);
  EXCEPTION
    WHEN unique_violation THEN
      v_got_violation := true;
  END;

  INSERT INTO concurrent_results (test_name, passed, detail)
  VALUES (
    'unique_index_blocks_duplicate_phone_same_org',
    v_got_violation,
    CASE WHEN v_got_violation THEN 'unique_violation raised as expected' ELSE 'ERROR: duplicate insert succeeded' END
  );

  -- Verify the first patient still exists
  INSERT INTO concurrent_results (test_name, passed, detail)
  VALUES (
    'first_patient_survives_after_conflict',
    EXISTS (SELECT 1 FROM public.patients WHERE id = v_patient1_id AND is_deleted = false),
    'patient1 exists'
  );

  -- Verify a different org CAN have the same phone (no cross-org conflict)
  v_got_violation := false;
  INSERT INTO public.organizations (id, name, currency_code, timezone, created_by, updated_by)
  VALUES ('d1000000-0000-4000-8000-000000000c99', 'Other Org', 'USD', 'UTC', v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.branches (id, organization_id, name, code, is_active, created_by, updated_by)
  VALUES ('d2000000-0000-4000-8000-000000000c99', 'd1000000-0000-4000-8000-000000000c99', 'Other Branch', 'OTH', true, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  BEGIN
    INSERT INTO public.patients (id, organization_id, branch_id, full_name, phone, is_deleted, created_by, updated_by)
    VALUES (gen_random_uuid(), 'd1000000-0000-4000-8000-000000000c99', 'd2000000-0000-4000-8000-000000000c99', 'Patient Other Org', '01001234567', false, v_bootstrap_user, v_bootstrap_user);
  EXCEPTION
    WHEN unique_violation THEN
      v_got_violation := true;
  END;

  INSERT INTO concurrent_results (test_name, passed, detail)
  VALUES (
    'different_org_same_phone_allowed',
    NOT v_got_violation,
    CASE WHEN v_got_violation THEN 'ERROR: cross-org conflict raised' ELSE 'no conflict across orgs' END
  );

  -- Verify soft-deleted patient does NOT block new patient with same phone
  v_got_violation := false;
  UPDATE public.patients SET is_deleted = true WHERE id = v_patient1_id;

  BEGIN
    INSERT INTO public.patients (id, organization_id, branch_id, full_name, phone, is_deleted, created_by, updated_by)
    VALUES (gen_random_uuid(), v_org_id, v_branch_id, 'Patient Replacement', '01001234567', false, v_bootstrap_user, v_bootstrap_user);
  EXCEPTION
    WHEN unique_violation THEN
      v_got_violation := true;
  END;

  INSERT INTO concurrent_results (test_name, passed, detail)
  VALUES (
    'soft_deleted_patient_does_not_block_phone_reuse',
    NOT v_got_violation,
    CASE WHEN v_got_violation THEN 'ERROR: soft-deleted record blocked insert' ELSE 'phone reused after archive' END
  );

  -- Test the create_patient RPC handles unique_violation gracefully
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'staff_member_id', v_bootstrap_staff::text,
      'staff_role', 'owner',
      'branch_ids', v_branch_id::text
    )::text,
    true
  );

  v_result := public.create_patient(
    v_branch_id,
    'Duplicate Phone Patient',
    '01001234567',
    NULL,
    NULL,
    NULL,
    NULL,
    true
  );

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO concurrent_results (test_name, passed, detail)
  VALUES (
    'create_patient_rpc_returns_duplicate_phone_error',
    NOT v_result.success AND v_result.error_code = 'DUPLICATE_PHONE',
    'error_code=' || COALESCE(v_result.error_code, '<null>') || ' success=' || v_result.success::text
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM concurrent_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'patient_management_concurrent failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM concurrent_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM concurrent_results ORDER BY test_name;
