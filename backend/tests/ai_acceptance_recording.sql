-- F2 acceptance recording RPC tests (T1–T6, T9–T10 + review coverage).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/ai_acceptance_recording.sql

BEGIN;

CREATE TEMP TABLE ai_acceptance_recording_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.set_authenticated_session(
  p_user_id uuid,
  p_org_id uuid,
  p_branch_id uuid,
  p_staff_id uuid,
  p_staff_role text DEFAULT 'doctor'
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'organization_id', p_org_id::text,
      'branch_ids', p_branch_id::text,
      'staff_member_id', p_staff_id::text,
      'staff_role', p_staff_role,
      'setup_required', false
    )::text,
    true
  );
END;
$$;

DO $$
DECLARE
  v_org_id uuid := 'f0400000-0000-4000-8000-000000000001';
  v_org2_id uuid := 'f0400000-0000-4000-8000-000000000002';
  v_branch_id uuid := 'f0410000-0000-4000-8000-000000000001';
  v_branch2_id uuid := 'f0410000-0000-4000-8000-000000000002';
  v_owner_user uuid := 'f0420000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'f0420000-0000-4000-8000-000000000002';
  v_reception_user uuid := 'f0420000-0000-4000-8000-000000000003';
  v_org2_user uuid := 'f0420000-0000-4000-8000-000000000004';
  v_owner_staff uuid := 'f0430000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'f0430000-0000-4000-8000-000000000002';
  v_reception_staff uuid := 'f0430000-0000-4000-8000-000000000003';
  v_org2_staff uuid := 'f0430000-0000-4000-8000-000000000004';
  v_patient_id uuid := 'f0440000-0000-4000-8000-000000000001';
  v_appt_id uuid := 'f0450000-0000-4000-8000-000000000001';
  v_visit_id uuid := 'f0460000-0000-4000-8000-000000000001';
  v_note_updated_at timestamptz := '2026-08-01T10:00:00+00';
  v_request_ref text := 'A1B2-C3D4';
  v_request_ref2 text := 'E5F6-G7H8';
  v_result public.rpc_result;
  v_acceptance_count int;
  v_audit_count int;
  v_note_count int;
  v_column_names text;
  v_registry_row record;
  v_audit_row record;
  v_acceptance_row record;
  v_forward_ref text;
  v_reverse_table text;
  v_reverse_record uuid;
  v_complaint text;
  v_raised boolean;
  v_cross_count int;
  v_has_unique boolean;
  v_has_ref_idx boolean;
  v_has_table_idx boolean;
  v_has_check boolean;
  v_can_execute_internal boolean;
  v_seed_audit_id uuid;
BEGIN
  IF to_regprocedure('public.record_ai_acceptance(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'public.record_ai_acceptance is not installed yet';
  END IF;

  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();
  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_owner_staff, v_doctor_staff, v_reception_staff, v_org2_staff);
  DELETE FROM public.staff_members
  WHERE id IN (v_owner_staff, v_doctor_staff, v_reception_staff, v_org2_staff);
  DELETE FROM public.branches WHERE id IN (v_branch_id, v_branch2_id);
  DELETE FROM public.organizations WHERE id IN (v_org_id, v_org2_id);
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user, v_reception_user, v_org2_user);

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'f2-accept-owner', extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'f2-accept-doctor', extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_reception_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'f2-accept-reception', extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_org2_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'f2-accept-org2', extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_id, 'F2 Acceptance Clinic', v_owner_user, v_owner_user),
    (v_org2_id, 'F2 Other Org', v_org2_user, v_org2_user);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_id, v_org_id, 'Main', 'F2MAIN', v_owner_user, v_owner_user),
    (v_branch2_id, v_org2_id, 'Other', 'F2OTH', v_org2_user, v_org2_user);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Owner', 'administrator', v_owner_user, v_owner_user),
    (v_doctor_staff, v_doctor_user, 'Doctor', 'doctor', v_owner_user, v_owner_user),
    (v_reception_staff, v_reception_user, 'Reception', 'receptionist', v_owner_user, v_owner_user),
    (v_org2_staff, v_org2_user, 'Org2 Doc', 'doctor', v_org2_user, v_org2_user);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_id, true, v_owner_user, v_owner_user),
    (v_doctor_staff, v_branch_id, true, v_owner_user, v_owner_user),
    (v_reception_staff, v_branch_id, true, v_owner_user, v_owner_user),
    (v_org2_staff, v_branch2_id, true, v_org2_user, v_org2_user);

  INSERT INTO public.patients (id, branch_id, organization_id, full_name, phone, mrn, created_by, updated_by)
  VALUES (v_patient_id, v_branch_id, v_org_id, 'F2 Patient', '201040000001', 'MRN-F2001', v_owner_user, v_owner_user);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES (
    v_appt_id, v_branch_id, v_patient_id, v_doctor_staff,
    now(), now() + interval '30 minutes', 'planned', 'in_progress', v_owner_user, v_owner_user
  );

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES (
    v_visit_id, v_branch_id, v_appt_id, v_patient_id, v_doctor_staff,
    current_date, 'in_progress', v_owner_user, v_owner_user
  );

  INSERT INTO public.visit_clinical_notes (
    visit_id, complaint, created_by, updated_by, updated_at
  )
  VALUES (
    v_visit_id, 'Baseline complaint', v_owner_user, v_owner_user, v_note_updated_at
  );

  INSERT INTO ai_acceptance_recording_results VALUES ('fixture_setup', true, 'visit fixture ready');

  -- Malformed request reference rejected before any write
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_acceptance_count FROM public.ai_accepted_output;
  SELECT count(*) INTO v_note_count
  FROM public.visit_clinical_notes
  WHERE visit_id = v_visit_id AND is_deleted = false;

  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');
  v_result := public.record_ai_acceptance(
    'bad-ref',
    'visit_clinical_notes',
    jsonb_build_object(
      'p_visit_id', v_visit_id,
      'p_complaint', 'Should not persist malformed',
      'p_expected_updated_at', v_note_updated_at
    )
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'malformed_request_reference_rejected',
    (NOT v_result.success)
      AND v_result.error_code = 'INVALID_INPUT'
      AND (SELECT count(*) FROM public.ai_accepted_output) = v_acceptance_count
      AND (SELECT count(*) FROM public.visit_clinical_notes
           WHERE visit_id = v_visit_id AND is_deleted = false
             AND complaint = 'Baseline complaint') = 1,
    format('success=%s error=%s', v_result.success, v_result.error_code)
  );

  -- T5: unregistered_target_key_rejected
  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_acceptance_count FROM public.ai_accepted_output;
  SELECT count(*) INTO v_audit_count
  FROM public.audit_log
  WHERE action = 'ai.acceptance_record';
  SELECT count(*) INTO v_note_count
  FROM public.visit_clinical_notes
  WHERE visit_id = v_visit_id AND is_deleted = false;
  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');

  v_result := public.record_ai_acceptance(
    v_request_ref,
    'nonexistent_target_key',
    jsonb_build_object('p_visit_id', v_visit_id)
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'unregistered_target_key_rejected',
    (NOT v_result.success)
      AND v_result.error_code IS NOT NULL
      AND (SELECT count(*) FROM public.ai_accepted_output) = v_acceptance_count
      AND (SELECT count(*) FROM public.audit_log WHERE action = 'ai.acceptance_record') = v_audit_count
      AND (SELECT count(*) FROM public.visit_clinical_notes
           WHERE visit_id = v_visit_id AND is_deleted = false) = v_note_count,
    format('success=%s error=%s', v_result.success, v_result.error_code)
  );

  -- Acceptance grants no privilege: receptionist lacks visits.edit_soap
  PERFORM pg_temp.set_authenticated_session(
    v_reception_user, v_org_id, v_branch_id, v_reception_staff, 'receptionist'
  );
  v_result := public.record_ai_acceptance(
    v_request_ref,
    'visit_clinical_notes',
    jsonb_build_object(
      'p_visit_id', v_visit_id,
      'p_complaint', 'Reception must not write',
      'p_expected_updated_at', v_note_updated_at
    )
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'acceptance_grants_no_privilege_without_edit_soap',
    (NOT v_result.success)
      AND v_result.error_code = 'FORBIDDEN'
      AND NOT EXISTS (
        SELECT 1 FROM public.ai_accepted_output
        WHERE ai_request_reference = v_request_ref
      )
      AND EXISTS (
        SELECT 1 FROM public.visit_clinical_notes
        WHERE visit_id = v_visit_id
          AND is_deleted = false
          AND complaint = 'Baseline complaint'
      ),
    format('success=%s code=%s', v_result.success, v_result.error_code)
  );

  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');
  -- T9: delegated_rpc_errors_pass_through_unchanged
  v_result := public.record_ai_acceptance(
    v_request_ref,
    'visit_clinical_notes',
    jsonb_build_object(
      'p_visit_id', v_visit_id,
      'p_complaint', 'Should not persist',
      'p_expected_updated_at', '2020-01-01T00:00:00+00'
    )
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'delegated_rpc_errors_pass_through_unchanged',
    (NOT v_result.success)
      AND v_result.error_code = 'STALE_DOCUMENTATION'
      AND v_result.error_message IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.ai_accepted_output
        WHERE ai_request_reference = v_request_ref
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.audit_log
        WHERE action = 'ai.acceptance_record'
          AND record_id = v_visit_id
      ),
    format('success=%s code=%s msg=%s', v_result.success, v_result.error_code, v_result.error_message)
  );

  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');
  v_result := public.record_ai_acceptance(
    v_request_ref,
    'visit_clinical_notes',
    jsonb_build_object(
      'p_visit_id', v_visit_id,
      'p_complaint', 'AI accepted complaint',
      'p_expected_updated_at', v_note_updated_at
    )
  );

  PERFORM set_config('role', 'postgres', true);
  SELECT * INTO v_acceptance_row
  FROM public.ai_accepted_output
  WHERE ai_request_reference = v_request_ref
    AND table_name = 'visit_clinical_notes'
    AND record_id = v_visit_id;

  SELECT * INTO v_audit_row
  FROM public.audit_log
  WHERE action = 'ai.acceptance_record'
    AND table_name = 'visit_clinical_notes'
    AND record_id = v_visit_id
  ORDER BY created_at DESC
  LIMIT 1;

  SELECT updated_at INTO v_note_updated_at
  FROM public.visit_clinical_notes
  WHERE visit_id = v_visit_id AND is_deleted = false;

  INSERT INTO ai_acceptance_recording_results VALUES (
    'acceptance_writes_domain_change_and_request_reference_together',
    v_result.success
      AND v_acceptance_row.id IS NOT NULL
      AND v_audit_row.id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.visit_clinical_notes vcn
        WHERE vcn.visit_id = v_visit_id
          AND vcn.is_deleted = false
          AND vcn.complaint = 'AI accepted complaint'
      )
      AND (v_result.data ->> 'acceptance_id') = v_acceptance_row.id::text
      AND (v_result.data ->> 'audit_log_id') = v_audit_row.id::text
      AND (v_result.data ->> 'visit_id') = v_visit_id::text
      AND (v_result.data ->> 'updated_at') IS NOT NULL
      AND (v_result.data ->> 'record_id') = v_visit_id::text
      AND v_acceptance_row.branch_id = v_branch_id,
    format('success=%s acceptance=%s audit=%s', v_result.success, v_acceptance_row.id, v_audit_row.id)
  );

  -- T2: acceptance_audit_log_bidirectional_provenance
  SELECT v_audit_row.new_data_json ->> 'ai_request_reference' INTO v_forward_ref;
  SELECT table_name, record_id
  INTO v_reverse_table, v_reverse_record
  FROM public.ai_accepted_output
  WHERE ai_request_reference = v_request_ref
  LIMIT 1;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'acceptance_audit_log_bidirectional_provenance',
    v_forward_ref = v_request_ref
      AND v_reverse_table = 'visit_clinical_notes'
      AND v_reverse_record = v_visit_id
      AND v_acceptance_row.audit_log_id = v_audit_row.id
      AND (v_audit_row.new_data_json ->> 'acceptance_id') = v_acceptance_row.id::text,
    format('forward=%s reverse=%s/%s', v_forward_ref, v_reverse_table, v_reverse_record)
  );

  -- Duplicate acceptance: clean reject before second domain write
  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');
  v_result := public.record_ai_acceptance(
    v_request_ref,
    'visit_clinical_notes',
    jsonb_build_object(
      'p_visit_id', v_visit_id,
      'p_complaint', 'Duplicate should not overwrite',
      'p_expected_updated_at', v_note_updated_at
    )
  );

  PERFORM set_config('role', 'postgres', true);
  SELECT complaint INTO v_complaint
  FROM public.visit_clinical_notes
  WHERE visit_id = v_visit_id AND is_deleted = false;

  INSERT INTO ai_acceptance_recording_results VALUES (
    'duplicate_acceptance_rejected_cleanly',
    (NOT v_result.success)
      AND v_result.error_code = 'INVALID_INPUT'
      AND v_complaint = 'AI accepted complaint'
      AND (SELECT count(*) FROM public.ai_accepted_output
           WHERE ai_request_reference = v_request_ref) = 1,
    format('success=%s code=%s complaint=%s', v_result.success, v_result.error_code, v_complaint)
  );

  -- Partial-failure atomicity at acceptance-write stage: domain write succeeds,
  -- then acceptance unique_violation must roll the domain change back with the
  -- nested block (same transaction semantics the RPC relies on when it re-raises).
  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');
  -- Keep JWT claims; RESET ROLE so simulated acceptance inserts run as postgres.
  RESET ROLE;
  v_raised := false;
  BEGIN
    v_result := public.save_visit_documentation(
      v_visit_id,
      'Should roll back with acceptance failure',
      NULL, NULL, NULL, NULL,
      v_note_updated_at
    );
    IF NOT v_result.success THEN
      RAISE EXCEPTION 'setup domain write failed: %', v_result.error_code;
    END IF;

    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
    VALUES (
      v_doctor_user, v_org_id, 'ai.acceptance_record', 'visit_clinical_notes', v_visit_id,
      jsonb_build_object('ai_request_reference', v_request_ref2, 'acceptance_id', gen_random_uuid())
    )
    RETURNING id INTO v_seed_audit_id;

    -- Collide on (table_name, record_id, ai_request_reference) with the T1 row.
    INSERT INTO public.ai_accepted_output (
      organization_id, branch_id, table_name, record_id,
      ai_request_reference, accepted_by, audit_log_id
    )
    VALUES (
      v_org_id, v_branch_id, 'visit_clinical_notes', v_visit_id,
      v_request_ref, v_doctor_user, v_seed_audit_id
    );
  EXCEPTION
    WHEN unique_violation THEN
      v_raised := true;
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT complaint, updated_at INTO v_complaint, v_note_updated_at
  FROM public.visit_clinical_notes
  WHERE visit_id = v_visit_id AND is_deleted = false;

  INSERT INTO ai_acceptance_recording_results VALUES (
    'acceptance_write_failure_rolls_back_domain_change',
    v_raised
      AND v_complaint = 'AI accepted complaint'
      AND (SELECT count(*) FROM public.ai_accepted_output
           WHERE ai_request_reference = v_request_ref) = 1,
    format('raised=%s complaint=%s', v_raised, v_complaint)
  );

  -- Registry-driven enablement: alternate target_key → same domain_function works
  -- without a new dispatcher branch.
  INSERT INTO ai_internal.acceptance_targets (target_key, domain_function, table_name)
  VALUES ('visit_clinical_notes_alias', 'save_visit_documentation', 'visit_clinical_notes')
  ON CONFLICT (target_key) DO NOTHING;

  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');
  v_result := public.record_ai_acceptance(
    'J1K2-M3N4',
    'visit_clinical_notes_alias',
    jsonb_build_object(
      'p_visit_id', v_visit_id,
      'p_complaint', 'Alias registry target',
      'p_expected_updated_at', v_note_updated_at
    )
  );

  PERFORM set_config('role', 'postgres', true);
  SELECT updated_at INTO v_note_updated_at
  FROM public.visit_clinical_notes
  WHERE visit_id = v_visit_id AND is_deleted = false;

  INSERT INTO ai_acceptance_recording_results VALUES (
    'registry_row_enables_dispatch_without_hardcoded_branch',
    v_result.success
      AND EXISTS (
        SELECT 1 FROM public.ai_accepted_output
        WHERE ai_request_reference = 'J1K2-M3N4'
          AND record_id = v_visit_id
      )
      AND EXISTS (
        SELECT 1 FROM public.visit_clinical_notes
        WHERE visit_id = v_visit_id
          AND complaint = 'Alias registry target'
      ),
    format('success=%s code=%s', v_result.success, v_result.error_code)
  );

  DELETE FROM ai_internal.acceptance_targets WHERE target_key = 'visit_clinical_notes_alias';

  -- T6: required columns + constraints + indexes; no AI request-state columns
  SELECT string_agg(column_name, ',' ORDER BY column_name)
  INTO v_column_names
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'ai_accepted_output';

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ai_accepted_output_unique_domain_reference'
  ) INTO v_has_unique;

  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'ai_accepted_output_request_reference_idx'
  ) INTO v_has_ref_idx;

  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'ai_accepted_output_table_record_idx'
  ) INTO v_has_table_idx;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ai_accepted_output_request_reference_format'
  ) INTO v_has_check;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'acceptance_rpc_does_not_store_ai_request_state',
    v_column_names LIKE '%organization_id%'
      AND v_column_names LIKE '%branch_id%'
      AND v_column_names LIKE '%table_name%'
      AND v_column_names LIKE '%record_id%'
      AND v_column_names LIKE '%ai_request_reference%'
      AND v_column_names LIKE '%accepted_by%'
      AND v_column_names LIKE '%accepted_at%'
      AND v_column_names LIKE '%audit_log_id%'
      AND v_has_unique AND v_has_ref_idx AND v_has_table_idx AND v_has_check
      AND v_column_names NOT ILIKE '%capability%'
      AND v_column_names NOT ILIKE '%model%'
      AND v_column_names NOT ILIKE '%provider%'
      AND v_column_names NOT ILIKE '%prompt%'
      AND v_column_names NOT ILIKE '%token%'
      AND v_column_names NOT ILIKE '%cost%'
      AND v_column_names NOT ILIKE '%request_state%',
    'columns=' || coalesce(v_column_names, '<none>')
  );

  -- T10: demonstration_target_does_not_promote_capability
  SELECT * INTO v_registry_row
  FROM ai_internal.acceptance_targets
  WHERE target_key = 'visit_clinical_notes';

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'demonstration_target_does_not_promote_capability',
    v_registry_row.target_key = 'visit_clinical_notes'
      AND v_registry_row.domain_function = 'save_visit_documentation'
      AND v_registry_row.table_name = 'visit_clinical_notes'
      AND NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'ai_capability_manifests'
      ),
    format('registry=%s/%s', v_registry_row.domain_function, v_registry_row.table_name)
  );

  -- Wrapper-gate: auth_internal halves are not executable by authenticated
  SELECT has_function_privilege(
    'authenticated',
    'auth_internal.record_ai_acceptance(text,text,jsonb)',
    'EXECUTE'
  ) INTO v_can_execute_internal;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'auth_internal_acceptance_not_granted_to_authenticated',
    NOT coalesce(v_can_execute_internal, true),
    format('execute_granted=%s', v_can_execute_internal)
  );

  -- RLS tenant isolation: other org cannot SELECT acceptance rows
  PERFORM pg_temp.set_authenticated_session(v_org2_user, v_org2_id, v_branch2_id, v_org2_staff, 'doctor');
  SELECT count(*) INTO v_cross_count
  FROM public.ai_accepted_output
  WHERE organization_id = v_org_id;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'ai_accepted_output_rls_tenant_isolation',
    v_cross_count = 0,
    format('cross_tenant_rows=%s', v_cross_count)
  );

  -- T3/T4 are Flutter-proven (discard + unaccepted never persisted). SQL no longer
  -- records tautological row-count assertions for those names.
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM ai_acceptance_recording_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'ai_acceptance_recording failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM ai_acceptance_recording_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

ROLLBACK;
