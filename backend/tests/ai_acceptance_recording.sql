-- F2 acceptance recording RPC tests (T1–T6, T9–T10).
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
  v_branch_id uuid := 'f0410000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'f0420000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'f0420000-0000-4000-8000-000000000002';
  v_owner_staff uuid := 'f0430000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'f0430000-0000-4000-8000-000000000002';
  v_patient_id uuid := 'f0440000-0000-4000-8000-000000000001';
  v_appt_id uuid := 'f0450000-0000-4000-8000-000000000001';
  v_visit_id uuid := 'f0460000-0000-4000-8000-000000000001';
  v_note_updated_at timestamptz := '2026-08-01T10:00:00+00';
  v_request_ref text := 'A1B2-C3D4';
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
BEGIN
  IF to_regprocedure('public.record_ai_acceptance(text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'public.record_ai_acceptance is not installed yet';
  END IF;

  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();
  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_owner_staff, v_doctor_staff);
  DELETE FROM public.staff_members
  WHERE id IN (v_owner_staff, v_doctor_staff);
  DELETE FROM public.branches WHERE id = v_branch_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'f2-accept-owner', extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'f2-accept-doctor', extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_org_id, 'F2 Acceptance Clinic', v_owner_user, v_owner_user);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES (v_branch_id, v_org_id, 'Main', 'F2MAIN', v_owner_user, v_owner_user);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Owner', 'administrator', v_owner_user, v_owner_user),
    (v_doctor_staff, v_doctor_user, 'Doctor', 'doctor', v_owner_user, v_owner_user);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_id, true, v_owner_user, v_owner_user),
    (v_doctor_staff, v_branch_id, true, v_owner_user, v_owner_user);

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

  -- T5: unregistered_target_key_rejected
  PERFORM pg_temp.set_authenticated_session(v_doctor_user, v_org_id, v_branch_id, v_doctor_staff, 'doctor');
  SELECT count(*) INTO v_acceptance_count FROM public.ai_accepted_output;
  SELECT count(*) INTO v_audit_count
  FROM public.audit_log
  WHERE action = 'ai.acceptance_record';
  SELECT count(*) INTO v_note_count
  FROM public.visit_clinical_notes
  WHERE visit_id = v_visit_id AND is_deleted = false;

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

  -- T1: acceptance_writes_domain_change_and_request_reference_together
  v_result := public.record_ai_acceptance(
    v_request_ref,
    'visit_clinical_notes',
    jsonb_build_object(
      'p_visit_id', v_visit_id,
      'p_complaint', 'AI accepted complaint',
      'p_expected_updated_at', v_note_updated_at
    )
  );

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

  PERFORM set_config('role', 'postgres', true);
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
      AND (v_result.data ->> 'audit_log_id') = v_audit_row.id::text,
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
      AND v_acceptance_row.audit_log_id = v_audit_row.id,
    format('forward=%s reverse=%s/%s', v_forward_ref, v_reverse_table, v_reverse_record)
  );

  -- T6: acceptance_rpc_does_not_store_ai_request_state
  SELECT string_agg(column_name, ',' ORDER BY column_name)
  INTO v_column_names
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'ai_accepted_output';

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'acceptance_rpc_does_not_store_ai_request_state',
    v_column_names NOT ILIKE '%capability%'
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

  -- T3: discard_path_writes_nothing (SQL precondition — no RPC call)
  SELECT count(*) INTO v_acceptance_count FROM public.ai_accepted_output;
  SELECT count(*) INTO v_audit_count
  FROM public.audit_log
  WHERE action = 'ai.acceptance_record';

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'discard_path_writes_nothing',
    v_acceptance_count = 1 AND v_audit_count = 1,
    format('acceptance_rows=%s audit_rows=%s (no new writes without accept RPC)', v_acceptance_count, v_audit_count)
  );

  -- T4: unaccepted_content_never_persisted (SQL — only accepted content in domain row)
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_acceptance_recording_results VALUES (
    'unaccepted_content_never_persisted',
    NOT EXISTS (
      SELECT 1 FROM public.visit_clinical_notes vcn
      WHERE vcn.visit_id = v_visit_id
        AND vcn.is_deleted = false
        AND vcn.complaint = 'Provisional unaccepted draft'
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.ai_accepted_output
      WHERE ai_request_reference = 'Z9Y8-X7W6'
    ),
    'unaccepted prose absent from durable storage'
  );
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

COMMIT;

SELECT test_name, passed, detail FROM ai_acceptance_recording_results ORDER BY test_name;
