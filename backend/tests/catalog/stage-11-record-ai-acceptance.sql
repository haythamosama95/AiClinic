-- Stage 11 catalog SQL: S11-022 … S11-029 (record_ai_acceptance only).
-- Run via backend/tests/catalog/run.sh (do not execute from a stage-writer task).
--
-- CONFLICT: catalog S11-028 seeds public.test_domain_no_id() with zero
--   arguments. CODE (20260802150000_ai_acceptance_recording.sql ~L114-117
--   and 20260805150000_f2_review_resolution.sql) returns
--   rpc_error('INTERNAL_ERROR', 'Domain function is not configured.') when
--   v_nargs = 0, so a no-arg stub never reaches the RAISE. This file gives
--   the stub one named argument (p_unused text DEFAULT NULL) so dispatch
--   actually invokes it; the function still returns rpc_success('{}'::jsonb)
--   with no record_id/visit_id/id key.
-- CONFLICT: catalog S11-028 side effects mention PostgREST HTTP 400.
--   Register 5 #12 requires SQLSTATE P0001 here, not HTTP.
-- CONFLICT: catalog S11-027 retries with setup T0 after visit updated_at
--   advanced to T1. CODE compares note.updated_at when a note exists
--   (20260628140000 L382-388). trg_visit_clinical_notes_set_updated_at
--   stamps now() on UPDATE, and now() is transaction-stable, so T0 equals
--   the S11-022 note timestamp. This file sends T0 - 1s so STALE fires;
--   assertions stay the domain code and message.
-- CONFLICT: catalog S11-029 says ai_internal.acceptance_targets is
--   unreadable by authenticated (SELECT granted to postgres only). CODE
--   also REVOKE ALL ON SCHEMA ai_internal FROM authenticated, so the
--   observed 42501 is `permission denied for schema ai_internal` (S02-010
--   class), not a table-level deny after USAGE.
-- CODE: public.save_visit_documentation argument order is
--   p_visit_id, p_complaint, …, p_plan, p_expected_updated_at; the
--   dispatcher binds JSON keys by proargnames, so catalog keys still work.

BEGIN;

\ir harness.sql

SELECT pg_temp.catalog_common_setup();

-- -----------------------------------------------------------------------------
-- Stage-local helpers (harness API stays frozen).
-- -----------------------------------------------------------------------------

CREATE TEMP TABLE catalog_s11_ids (
  key text PRIMARY KEY,
  value uuid NOT NULL
);

CREATE TEMP TABLE catalog_s11_ts (
  key text PRIMARY KEY,
  value timestamptz NOT NULL
);

CREATE OR REPLACE FUNCTION pg_temp.set_clinic_session(
  p_user_id uuid,
  p_org_id uuid,
  p_branch_id uuid,
  p_staff_id uuid,
  p_staff_role text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Harness injects only sub+role. Overlay org/branch/staff so
  -- jwt_organization_id() / jwt_branch_ids() match production JWTs.
  PERFORM pg_temp.set_authenticated_session(p_user_id);
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

CREATE OR REPLACE FUNCTION pg_temp.s11_stash(p_key text, p_value uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.reset_postgres();
  INSERT INTO catalog_s11_ids (key, value)
  VALUES (p_key, p_value)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s11_id(p_key text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_value uuid;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT t.value INTO STRICT v_value FROM catalog_s11_ids t WHERE t.key = p_key;
  RETURN v_value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s11_stash_ts(p_key text, p_value timestamptz)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.reset_postgres();
  INSERT INTO catalog_s11_ts (key, value)
  VALUES (p_key, p_value)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s11_ts(p_key text)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_value timestamptz;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT t.value INTO STRICT v_value FROM catalog_s11_ts t WHERE t.key = p_key;
  RETURN v_value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s11_working_schedule()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT '{
    "days": [
      {"day":"monday","is_working_day":true,"open_time":"00:00","close_time":"23:59"},
      {"day":"tuesday","is_working_day":true,"open_time":"00:00","close_time":"23:59"},
      {"day":"wednesday","is_working_day":true,"open_time":"00:00","close_time":"23:59"},
      {"day":"thursday","is_working_day":true,"open_time":"00:00","close_time":"23:59"},
      {"day":"friday","is_working_day":true,"open_time":"00:00","close_time":"23:59"},
      {"day":"saturday","is_working_day":true,"open_time":"00:00","close_time":"23:59"},
      {"day":"sunday","is_working_day":true,"open_time":"00:00","close_time":"23:59"}
    ]
  }'::jsonb;
$$;

-- Same-day slot in the org timezone so checked_in is allowed today.
CREATE OR REPLACE FUNCTION pg_temp.s11_same_day_slot(p_hour int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_tz text := 'Africa/Cairo';
  v_day_start timestamptz;
BEGIN
  IF p_hour < 0 OR p_hour > 22 THEN
    RAISE EXCEPTION 's11_same_day_slot: hour must be 0..22, got %', p_hour;
  END IF;
  v_day_start := date_trunc('day', now() AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  RETURN v_day_start + make_interval(hours => p_hour);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s11_open_visit(
  p_branch_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_start timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_result public.rpc_result;
  v_appt uuid;
  v_visit uuid;
BEGIN
  v_result := public.create_appointment(
    p_branch_id, p_patient_id, p_doctor_id, 'planned', p_start, 30, NULL, NULL
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_appointment failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_appt := (v_result.data ->> 'appointment_id')::uuid;

  v_result := public.update_appointment_status(v_appt, 'confirmed');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'update_appointment_status confirmed failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  v_result := public.update_appointment_status(v_appt, 'checked_in');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'update_appointment_status checked_in failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  v_result := public.create_visit(v_appt, NULL);
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_visit failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_visit := (v_result.data ->> 'visit_id')::uuid;
  RETURN v_visit;
END;
$$;

-- Unblock create_visit for a second same-doctor visit. complete_visit
-- requires documentation and would pollute V (S11-022 must be the first
-- SOAP write). Same pattern as Stage 08 s08_release_in_progress. This
-- only moves appointments.status off in_progress — not an S11-028 [SEED]
-- of the acceptance target. save_visit_documentation / record_ai_acceptance
-- do not require the visit to remain in_progress.
CREATE OR REPLACE FUNCTION pg_temp.s11_release_in_progress(p_visit_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.reset_postgres();
  UPDATE public.appointments a
  SET
    status = 'completed',
    updated_at = now()
  FROM public.visits v
  WHERE v.id = p_visit_id
    AND v.appointment_id = a.id
    AND a.is_deleted = false
    AND a.status = 'in_progress';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s11_accept_args(
  p_visit_id uuid,
  p_expected_updated_at timestamptz,
  p_plan text
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'p_visit_id', p_visit_id,
    'p_expected_updated_at', p_expected_updated_at,
    'p_plan', p_plan
  );
$$;

-- -----------------------------------------------------------------------------
-- Journey setup: clinic hours, visit V (S11-022), visit V2 (S11-025), extra
-- branch for S11-029(d). Real RPCs only (no [SEED] except S11-028 later).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_admin uuid;
  v_admin_auth uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_result public.rpc_result;
  v_patient uuid;
  v_visit uuid;
  v_t0 timestamptz;
  v_other_branch uuid;
  v_branch_name text;
  v_branch_code text;
  v_note_count int;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_admin FROM catalog_setup WHERE key = 'admin';
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  SELECT b.name, b.code INTO STRICT v_branch_name, v_branch_code
  FROM public.branches b
  WHERE b.id = v_branch;

  -- Widen hours so Sunday (catalog run date) can book and check in today.
  PERFORM pg_temp.set_clinic_session(
    v_admin_auth, v_org, v_branch, v_admin, 'administrator'
  );
  v_result := public.update_branch(
    v_branch,
    v_branch_name,
    pg_temp.s11_working_schedule(),
    v_branch_code,
    NULL,
    NULL,
    NULL
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'update_branch failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  v_result := public.manage_create_branch(
    'S11 Other Branch',
    pg_temp.s11_working_schedule(),
    'S11OTH',
    NULL,
    NULL,
    NULL
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'manage_create_branch failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_other_branch := (v_result.data ->> 'branch_id')::uuid;
  PERFORM pg_temp.s11_stash('branch_other', v_other_branch);

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.create_patient(
    v_branch, 'S11 Acceptance Patient', '201800011022', NULL, NULL, NULL, NULL, false
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_patient V failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_patient := (v_result.data ->> 'patient_id')::uuid;
  v_visit := pg_temp.s11_open_visit(
    v_branch, v_patient, v_doctor, pg_temp.s11_same_day_slot(10)
  );

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_note_count
  FROM public.visit_clinical_notes n
  WHERE n.visit_id = v_visit
    AND n.is_deleted = false;
  IF v_note_count <> 0 THEN
    RAISE EXCEPTION 'visit V already has a clinical note before S11-022';
  END IF;
  PERFORM pg_temp.s11_stash('visit', v_visit);

  -- CODE: one in-progress visit per doctor (DOCTOR_ALREADY_IN_PROGRESS).
  -- Catalog S11-025 only needs a second visit in the same branch.
  PERFORM pg_temp.s11_release_in_progress(v_visit);

  -- Capture T0 after release so p_expected_updated_at matches visits.updated_at
  -- if the appointment UPDATE also moved the visit row.
  PERFORM pg_temp.reset_postgres();
  SELECT v.updated_at INTO STRICT v_t0
  FROM public.visits v
  WHERE v.id = v_visit
    AND v.is_deleted = false;
  PERFORM pg_temp.s11_stash_ts('t0', v_t0);

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.create_patient(
    v_branch, 'S11 Duplicate Patient', '201800011025', NULL, NULL, NULL, NULL, false
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_patient V2 failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_patient := (v_result.data ->> 'patient_id')::uuid;
  v_visit := pg_temp.s11_open_visit(
    v_branch, v_patient, v_doctor, pg_temp.s11_same_day_slot(11)
  );
  PERFORM pg_temp.s11_release_in_progress(v_visit);
  PERFORM pg_temp.reset_postgres();
  SELECT v.updated_at INTO STRICT v_t0
  FROM public.visits v
  WHERE v.id = v_visit
    AND v.is_deleted = false;
  PERFORM pg_temp.s11_stash('visit2', v_visit);
  PERFORM pg_temp.s11_stash_ts('t0_v2', v_t0);
END;
$$;

-- -----------------------------------------------------------------------------
-- S11-022 — record_ai_acceptance happy path writes acceptance, audit log, and merged rpc_success
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_t0 timestamptz;
  v_result public.rpc_result;
  v_acceptance public.ai_accepted_output%ROWTYPE;
  v_audit public.audit_log%ROWTYPE;
  v_note_id uuid;
  v_note_plan text;
  v_note_count int;
  v_accept_count int;
  v_audit_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s11_id('visit');
  v_t0 := pg_temp.s11_ts('t0');

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.record_ai_acceptance(
    '7K2M-9XQD',
    'visit_clinical_notes',
    pg_temp.s11_accept_args(
      v_visit,
      v_t0,
      'Rest and hydration. AI-drafted summary accepted.'
    )
  );

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_note_count
  FROM public.visit_clinical_notes n
  WHERE n.visit_id = v_visit
    AND n.is_deleted = false;
  SELECT n.id, n.plan
  INTO v_note_id, v_note_plan
  FROM public.visit_clinical_notes n
  WHERE n.visit_id = v_visit
    AND n.is_deleted = false;
  SELECT * INTO v_acceptance
  FROM public.ai_accepted_output a
  WHERE a.ai_request_reference = '7K2M-9XQD';
  SELECT count(*)::int INTO v_accept_count
  FROM public.ai_accepted_output a
  WHERE a.ai_request_reference = '7K2M-9XQD';
  SELECT * INTO v_audit
  FROM public.audit_log al
  WHERE al.action = 'ai.acceptance_record'
    AND al.table_name = 'visit_clinical_notes'
    AND al.record_id = v_visit
  ORDER BY al.created_at DESC
  LIMIT 1;
  SELECT count(*)::int INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'ai.acceptance_record'
    AND al.new_data_json ->> 'ai_request_reference' = '7K2M-9XQD';

  v_ok := v_result.success IS TRUE
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND (v_result.data ->> 'visit_id') = v_visit::text
    AND (v_result.data ->> 'updated_at') IS NOT NULL
    AND (v_result.data ->> 'acceptance_id') = v_acceptance.id::text
    AND (v_result.data ->> 'table_name') = 'visit_clinical_notes'
    AND (v_result.data ->> 'record_id') = v_visit::text
    AND (v_result.data ->> 'record_id') IS DISTINCT FROM v_note_id::text
    AND (v_result.data ->> 'audit_log_id') = v_audit.id::text
    AND v_note_count = 1
    AND v_note_plan = 'Rest and hydration. AI-drafted summary accepted.'
    AND v_accept_count = 1
    AND v_audit_count = 1
    AND v_audit.action = 'ai.acceptance_record'
    AND v_audit.table_name = 'visit_clinical_notes'
    AND v_audit.record_id = v_visit
    AND v_audit.user_id = v_doctor_auth
    AND v_audit.organization_id = v_org
    AND v_audit.new_data_json ->> 'ai_request_reference' = '7K2M-9XQD'
    AND v_audit.new_data_json ->> 'acceptance_id' = v_acceptance.id::text
    AND v_acceptance.id IS NOT NULL
    AND v_acceptance.organization_id = v_org
    AND v_acceptance.branch_id = v_branch
    AND v_acceptance.table_name = 'visit_clinical_notes'
    AND v_acceptance.record_id = v_visit
    AND v_acceptance.ai_request_reference = '7K2M-9XQD'
    AND v_acceptance.accepted_by = v_doctor_auth
    AND v_acceptance.audit_log_id = v_audit.id
    AND v_acceptance.accepted_at IS NOT NULL;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' data=' || COALESCE(v_result.data::text, '<null>')
    || ' note_id=' || COALESCE(v_note_id::text, '<null>')
    || ' acceptance=' || COALESCE(v_acceptance.id::text, '<null>')
    || ' audit=' || COALESCE(v_audit.id::text, '<null>');

  IF v_ok THEN
    PERFORM pg_temp.s11_stash('acceptance', v_acceptance.id);
  END IF;

  PERFORM pg_temp.record(
    'S11-022 — record_ai_acceptance happy path writes acceptance, audit log, and merged rpc_success',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S11-023 — record_ai_acceptance rejects malformed request references
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_before_accept int;
  v_before_audit int;
  v_before_notes int;
  v_a public.rpc_result;
  v_b public.rpc_result;
  v_c public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  SELECT count(*)::int INTO v_before_accept FROM public.ai_accepted_output;
  SELECT count(*)::int INTO v_before_audit
  FROM public.audit_log
  WHERE action = 'ai.acceptance_record';
  SELECT count(*)::int INTO v_before_notes
  FROM public.visit_clinical_notes
  WHERE is_deleted = false;

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_a := public.record_ai_acceptance(NULL, 'visit_clinical_notes', '{}'::jsonb);
  v_b := public.record_ai_acceptance(
    '7k2m-9xqd', 'visit_clinical_notes', '{}'::jsonb
  );
  v_c := public.record_ai_acceptance(
    '7K2M9XQD', 'visit_clinical_notes', '{}'::jsonb
  );

  PERFORM pg_temp.reset_postgres();
  v_ok := v_a.success IS FALSE
    AND v_a.error_code = 'INVALID_INPUT'
    AND v_a.error_message = 'Request reference must use the standard format.'
    AND v_b.success IS FALSE
    AND v_b.error_code = 'INVALID_INPUT'
    AND v_b.error_message = 'Request reference must use the standard format.'
    AND v_c.success IS FALSE
    AND v_c.error_code = 'INVALID_INPUT'
    AND v_c.error_message = 'Request reference must use the standard format.'
    AND (SELECT count(*)::int FROM public.ai_accepted_output) = v_before_accept
    AND (
      SELECT count(*)::int FROM public.audit_log
      WHERE action = 'ai.acceptance_record'
    ) = v_before_audit
    AND (
      SELECT count(*)::int FROM public.visit_clinical_notes
      WHERE is_deleted = false
    ) = v_before_notes;

  v_detail := 'a=' || COALESCE(v_a.error_code, '<null>')
    || '/' || COALESCE(v_a.error_message, '<null>')
    || ' b=' || COALESCE(v_b.error_code, '<null>')
    || '/' || COALESCE(v_b.error_message, '<null>')
    || ' c=' || COALESCE(v_c.error_code, '<null>')
    || '/' || COALESCE(v_c.error_message, '<null>');

  PERFORM pg_temp.record(
    'S11-023 — record_ai_acceptance rejects malformed request references',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S11-024 — record_ai_acceptance rejects unregistered acceptance targets
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_t0 timestamptz;
  v_before_accept int;
  v_before_audit int;
  v_before_notes int;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s11_id('visit');
  v_t0 := pg_temp.s11_ts('t0');

  SELECT count(*)::int INTO v_before_accept FROM public.ai_accepted_output;
  SELECT count(*)::int INTO v_before_audit
  FROM public.audit_log
  WHERE action = 'ai.acceptance_record';
  SELECT count(*)::int INTO v_before_notes
  FROM public.visit_clinical_notes
  WHERE is_deleted = false;

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.record_ai_acceptance(
    '7K2M-9XQD',
    'billing_invoices',
    jsonb_build_object(
      'p_visit_id', v_visit,
      'p_expected_updated_at', v_t0
    )
  );

  PERFORM pg_temp.reset_postgres();
  v_ok := v_result.success IS FALSE
    AND v_result.error_code = 'INVALID_INPUT'
    AND v_result.error_message = 'Acceptance target is not registered.'
    AND (SELECT count(*)::int FROM public.ai_accepted_output) = v_before_accept
    AND (
      SELECT count(*)::int FROM public.audit_log
      WHERE action = 'ai.acceptance_record'
    ) = v_before_audit
    AND (
      SELECT count(*)::int FROM public.visit_clinical_notes
      WHERE is_deleted = false
    ) = v_before_notes;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>');

  PERFORM pg_temp.record(
    'S11-024 — record_ai_acceptance rejects unregistered acceptance targets',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S11-025 — record_ai_acceptance rejects duplicate acceptance before any domain write
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_visit2 uuid;
  v_t0 timestamptz;
  v_t0_v2 timestamptz;
  v_plan_before text;
  v_notes_v2_before int;
  v_a public.rpc_result;
  v_b public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s11_id('visit');
  v_visit2 := pg_temp.s11_id('visit2');
  v_t0 := pg_temp.s11_ts('t0');
  v_t0_v2 := pg_temp.s11_ts('t0_v2');

  SELECT n.plan INTO STRICT v_plan_before
  FROM public.visit_clinical_notes n
  WHERE n.visit_id = v_visit
    AND n.is_deleted = false;
  SELECT count(*)::int INTO v_notes_v2_before
  FROM public.visit_clinical_notes n
  WHERE n.visit_id = v_visit2
    AND n.is_deleted = false;

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  -- (a) Repeat S11-022 exact call (same ref, same visit, original T0).
  v_a := public.record_ai_acceptance(
    '7K2M-9XQD',
    'visit_clinical_notes',
    pg_temp.s11_accept_args(
      v_visit,
      v_t0,
      'Rest and hydration. AI-drafted summary accepted.'
    )
  );
  -- (b) Same ref + target, different visit V2.
  v_b := public.record_ai_acceptance(
    '7K2M-9XQD',
    'visit_clinical_notes',
    pg_temp.s11_accept_args(
      v_visit2,
      v_t0_v2,
      'Should not persist on V2.'
    )
  );

  PERFORM pg_temp.reset_postgres();
  v_ok := v_a.success IS FALSE
    AND v_a.error_code = 'INVALID_INPUT'
    AND v_a.error_message = 'This AI output was already accepted for this record.'
    AND v_b.success IS FALSE
    AND v_b.error_code = 'INVALID_INPUT'
    AND v_b.error_message = 'This AI output was already accepted for this record.'
    AND (
      SELECT count(*)::int FROM public.ai_accepted_output a
      WHERE a.ai_request_reference = '7K2M-9XQD'
    ) = 1
    AND (
      SELECT count(*)::int FROM public.audit_log al
      WHERE al.action = 'ai.acceptance_record'
        AND al.new_data_json ->> 'ai_request_reference' = '7K2M-9XQD'
    ) = 1
    AND (
      SELECT n.plan FROM public.visit_clinical_notes n
      WHERE n.visit_id = v_visit AND n.is_deleted = false
    ) = v_plan_before
    AND (
      SELECT count(*)::int FROM public.visit_clinical_notes n
      WHERE n.visit_id = v_visit2 AND n.is_deleted = false
    ) = v_notes_v2_before;

  v_detail := 'a=' || COALESCE(v_a.error_code, '<null>')
    || '/' || COALESCE(v_a.error_message, '<null>')
    || ' b=' || COALESCE(v_b.error_code, '<null>')
    || '/' || COALESCE(v_b.error_message, '<null>')
    || ' plan=' || COALESCE(v_plan_before, '<null>');

  PERFORM pg_temp.record(
    'S11-025 — record_ai_acceptance rejects duplicate acceptance before any domain write',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S11-026 — record_ai_acceptance requires organization context
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doctor_auth uuid;
  v_visit uuid;
  v_t0 timestamptz;
  v_before_accept int;
  v_before_audit int;
  v_before_notes int;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s11_id('visit');
  v_t0 := pg_temp.s11_ts('t0');

  SELECT count(*)::int INTO v_before_accept FROM public.ai_accepted_output;
  SELECT count(*)::int INTO v_before_audit
  FROM public.audit_log
  WHERE action = 'ai.acceptance_record';
  SELECT count(*)::int INTO v_before_notes
  FROM public.visit_clinical_notes
  WHERE is_deleted = false;

  -- Harness only: sub+role, no organization_id overlay.
  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  v_result := public.record_ai_acceptance(
    '8N3P-QWRA',
    'visit_clinical_notes',
    pg_temp.s11_accept_args(v_visit, v_t0, 'x')
  );

  PERFORM pg_temp.reset_postgres();
  v_ok := v_result.success IS FALSE
    AND v_result.error_code = 'FORBIDDEN'
    AND v_result.error_message = 'Organization context is required.'
    AND NOT EXISTS (
      SELECT 1 FROM public.ai_accepted_output a
      WHERE a.ai_request_reference = '8N3P-QWRA'
    )
    AND (SELECT count(*)::int FROM public.ai_accepted_output) = v_before_accept
    AND (
      SELECT count(*)::int FROM public.audit_log
      WHERE action = 'ai.acceptance_record'
    ) = v_before_audit
    AND (
      SELECT count(*)::int FROM public.visit_clinical_notes
      WHERE is_deleted = false
    ) = v_before_notes;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>');

  PERFORM pg_temp.record(
    'S11-026 — record_ai_acceptance requires organization context',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S11-027 — record_ai_acceptance passes through delegated domain failures unchanged
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_t0 timestamptz;
  v_stale timestamptz;
  v_missing uuid := gen_random_uuid();
  v_a public.rpc_result;
  v_b public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s11_id('visit');
  v_t0 := pg_temp.s11_ts('t0');

  IF v_missing IN (v_visit, pg_temp.s11_id('visit2')) THEN
    v_missing := gen_random_uuid();
  END IF;

  -- Catalog: client retries with T0 after visit updated_at advanced to T1.
  -- CODE compares p_expected_updated_at to note.updated_at when a note
  -- exists (20260628140000 L382-388). trg_visit_clinical_notes_set_updated_at
  -- stamps now() on UPDATE, and now() is transaction-stable, so setup T0
  -- equals the S11-022 note timestamp and is not stale. Send T0 - 1s so
  -- IS DISTINCT FROM fires; still assert the domain STALE_DOCUMENTATION
  -- code and message.
  v_stale := v_t0 - interval '1 second';

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  -- (a) Stale expected timestamp; domain STALE_DOCUMENTATION pass-through.
  v_a := public.record_ai_acceptance(
    '9P4R-SXTC',
    'visit_clinical_notes',
    pg_temp.s11_accept_args(v_visit, v_stale, 'stale edit')
  );
  -- (b) Unknown visit uuid, same shape.
  v_b := public.record_ai_acceptance(
    '9P4R-SXTC',
    'visit_clinical_notes',
    pg_temp.s11_accept_args(v_missing, v_t0, 'stale edit')
  );

  PERFORM pg_temp.reset_postgres();
  v_ok := v_a.success IS FALSE
    AND v_a.error_code = 'STALE_DOCUMENTATION'
    AND v_a.error_message = 'This documentation was updated elsewhere. Reload and try again.'
    AND v_a.data IS NULL
    AND NOT (COALESCE(v_a.data, '{}'::jsonb) ? 'acceptance_id')
    AND v_b.success IS FALSE
    AND v_b.error_code = 'NOT_FOUND'
    AND v_b.error_message = 'Visit was not found.'
    AND v_b.data IS NULL
    AND NOT (COALESCE(v_b.data, '{}'::jsonb) ? 'acceptance_id')
    AND NOT EXISTS (
      SELECT 1 FROM public.ai_accepted_output a
      WHERE a.ai_request_reference = '9P4R-SXTC'
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.audit_log al
      WHERE al.action = 'ai.acceptance_record'
        AND al.new_data_json ->> 'ai_request_reference' = '9P4R-SXTC'
    );

  v_detail := 'a=' || COALESCE(v_a.error_code, '<null>')
    || '/' || COALESCE(v_a.error_message, '<null>')
    || ' b=' || COALESCE(v_b.error_code, '<null>')
    || '/' || COALESCE(v_b.error_message, '<null>');

  PERFORM pg_temp.record(
    'S11-027 — record_ai_acceptance passes through delegated domain failures unchanged',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S11-028 [SEED] — domain stub.
-- Catalog: public.test_domain_no_id() zero-arg. CODE refuses v_nargs = 0
-- (INTERNAL_ERROR, never RAISE). Dummy p_unused lets dispatch invoke it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.test_domain_no_id(p_unused text DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.audit_log (
    user_id, organization_id, action, table_name, record_id, new_data_json
  )
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'test.domain_no_id',
    'visit_clinical_notes',
    '00000000-0000-4000-8000-000000000028'::uuid,
    jsonb_build_object('seed', 's11-028')
  );
  RETURN public.rpc_success('{}'::jsonb);
END;
$$;

-- Dispatcher is SECURITY DEFINER (migration owner, typically
-- supabase_admin). Default privileges revoke PUBLIC EXECUTE, so grant
-- broadly inside this rolled-back transaction.
GRANT EXECUTE ON FUNCTION public.test_domain_no_id(text) TO PUBLIC;

-- -----------------------------------------------------------------------------
-- S11-028 — record_ai_acceptance rolls back everything when the domain write returns no record id
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_result public.rpc_result;
  v_raised boolean := false;
  v_sqlstate text;
  v_msg text;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  INSERT INTO ai_internal.acceptance_targets (target_key, domain_function, table_name)
  VALUES ('test_no_record_id', 'test_domain_no_id', 'visit_clinical_notes');

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );

  BEGIN
    v_result := public.record_ai_acceptance(
      'ABCD-EFGH',
      'test_no_record_id',
      '{}'::jsonb
    );
    v_raised := false;
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      v_sqlstate := 'P0001';
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_raised := true;
    WHEN OTHERS THEN
      v_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_raised := true;
  END;

  PERFORM pg_temp.reset_postgres();
  -- Register 5 #12: SQLSTATE P0001, not PostgREST HTTP 400.
  v_ok := v_raised
    AND v_sqlstate = 'P0001'
    AND v_msg = 'Domain write did not return a record id.'
    AND v_result IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.ai_accepted_output a
      WHERE a.ai_request_reference = 'ABCD-EFGH'
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.audit_log al
      WHERE al.action = 'test.domain_no_id'
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.audit_log al
      WHERE al.action = 'ai.acceptance_record'
        AND al.new_data_json ->> 'ai_request_reference' = 'ABCD-EFGH'
    );

  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' msg=' || COALESCE(v_msg, '<none>')
    || ' result_assigned=' || (v_result IS NOT NULL)::text
    || '; Register 5 #12 SQLSTATE P0001 (do not assert PostgREST HTTP 400)';

  PERFORM pg_temp.record(
    'S11-028 — record_ai_acceptance rolls back everything when the domain write returns no record id',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S11-029 — record_ai_acceptance wrapper gate and ai_accepted_output RLS visibility
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_other_branch uuid;
  v_org2 uuid := gen_random_uuid();
  v_branch2 uuid := gen_random_uuid();
  v_u2 uuid := gen_random_uuid();
  v_u2_staff uuid := gen_random_uuid();
  v_fn_a_raised boolean := false;
  v_fn_a_state text;
  v_fn_a_msg text;
  v_fn_b_raised boolean := false;
  v_fn_b_state text;
  v_fn_b_msg text;
  v_reg_raised boolean := false;
  v_reg_state text;
  v_reg_msg text;
  v_result_a public.rpc_result;
  v_result_b public.rpc_result;
  v_cross_count int;
  v_own_count int;
  v_other_branch_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_other_branch := pg_temp.s11_id('branch_other');

  -- Fixture (not catalog [SEED] of the acceptance target): second org + U2.
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  VALUES (
    v_u2,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    's11_org2_doc',
    extensions.crypt('Cl1nic!pass', extensions.gen_salt('bf')),
    now(),
    '',
    '',
    '',
    '',
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    '{}'::jsonb,
    now(),
    now()
  );

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_org2, 'S11 Second Org', v_u2, v_u2);

  INSERT INTO public.branches (
    id, organization_id, name, code, working_schedule, created_by, updated_by
  )
  VALUES (
    v_branch2,
    v_org2,
    'Org2 Main',
    'S11O2',
    pg_temp.s11_working_schedule(),
    v_u2,
    v_u2
  );

  INSERT INTO public.staff_members (
    id, auth_user_id, full_name, role, created_by, updated_by
  )
  VALUES (
    v_u2_staff, v_u2, 'S11 Org2 Doctor', 'doctor', v_u2, v_u2
  );

  INSERT INTO public.staff_branch_assignments (
    staff_member_id, branch_id, is_primary, created_by, updated_by
  )
  VALUES (v_u2_staff, v_branch2, true, v_u2, v_u2);

  -- (a) Wrapper gate: auth_internal halves are not executable by authenticated.
  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );

  BEGIN
    v_result_a := auth_internal.record_ai_acceptance(
      '7K2M-9XQD', 'visit_clinical_notes', '{}'::jsonb
    );
    v_fn_a_raised := false;
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_fn_a_state := '42501';
      GET STACKED DIAGNOSTICS v_fn_a_msg = MESSAGE_TEXT;
      v_fn_a_raised := true;
    WHEN OTHERS THEN
      v_fn_a_state := SQLSTATE;
      GET STACKED DIAGNOSTICS v_fn_a_msg = MESSAGE_TEXT;
      v_fn_a_raised := true;
  END;

  BEGIN
    v_result_b := auth_internal.invoke_acceptance_domain_rpc(
      'save_visit_documentation', '{}'::jsonb
    );
    v_fn_b_raised := false;
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_fn_b_state := '42501';
      GET STACKED DIAGNOSTICS v_fn_b_msg = MESSAGE_TEXT;
      v_fn_b_raised := true;
    WHEN OTHERS THEN
      v_fn_b_state := SQLSTATE;
      GET STACKED DIAGNOSTICS v_fn_b_msg = MESSAGE_TEXT;
      v_fn_b_raised := true;
  END;

  BEGIN
    PERFORM 1 FROM ai_internal.acceptance_targets;
    v_reg_raised := false;
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_reg_state := '42501';
      GET STACKED DIAGNOSTICS v_reg_msg = MESSAGE_TEXT;
      v_reg_raised := true;
    WHEN OTHERS THEN
      v_reg_state := SQLSTATE;
      GET STACKED DIAGNOSTICS v_reg_msg = MESSAGE_TEXT;
      v_reg_raised := true;
  END;

  -- (b) U2 / ORG2: RLS hides ORG's acceptance row.
  PERFORM pg_temp.set_clinic_session(
    v_u2, v_org2, v_branch2, v_u2_staff, 'doctor'
  );
  SELECT count(*)::int INTO v_cross_count
  FROM public.ai_accepted_output
  WHERE ai_request_reference = '7K2M-9XQD';

  -- (c) U with clinic JWT: one row.
  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  SELECT count(*)::int INTO v_own_count
  FROM public.ai_accepted_output
  WHERE ai_request_reference = '7K2M-9XQD';

  -- (d) U with branch_ids that exclude BR.
  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_other_branch, v_doctor, 'doctor'
  );
  SELECT count(*)::int INTO v_other_branch_count
  FROM public.ai_accepted_output
  WHERE ai_request_reference = '7K2M-9XQD';

  PERFORM pg_temp.reset_postgres();
  v_ok := v_fn_a_raised
    AND v_fn_a_state = '42501'
    AND COALESCE(v_fn_a_msg, '') ILIKE '%permission denied%'
    AND COALESCE(v_fn_a_msg, '') ILIKE '%record_ai_acceptance%'
    AND v_result_a IS NULL
    AND v_fn_b_raised
    AND v_fn_b_state = '42501'
    AND COALESCE(v_fn_b_msg, '') ILIKE '%permission denied%'
    AND COALESCE(v_fn_b_msg, '') ILIKE '%invoke_acceptance_domain_rpc%'
    AND v_result_b IS NULL
    AND v_cross_count = 0
    AND v_own_count = 1
    AND v_other_branch_count = 0
    AND v_reg_raised
    AND v_reg_state = '42501'
    AND COALESCE(v_reg_msg, '') ILIKE '%permission denied%';

  v_detail := 'fn_a=' || COALESCE(v_fn_a_state, '<none>')
    || '/' || COALESCE(v_fn_a_msg, '<none>')
    || ' fn_b=' || COALESCE(v_fn_b_state, '<none>')
    || '/' || COALESCE(v_fn_b_msg, '<none>')
    || ' cross=' || v_cross_count::text
    || ' own=' || v_own_count::text
    || ' other_branch=' || v_other_branch_count::text
    || ' registry=' || COALESCE(v_reg_state, '<none>')
    || '/' || COALESCE(v_reg_msg, '<none>')
    || '; Register 5 #12 SQLSTATE 42501 (do not assert PostgREST HTTP)';

  PERFORM pg_temp.record(
    'S11-029 — record_ai_acceptance wrapper gate and ai_accepted_output RLS visibility',
    v_ok,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
