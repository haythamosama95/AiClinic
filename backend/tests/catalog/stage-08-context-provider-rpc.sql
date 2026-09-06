-- Stage 08 catalog SQL: S08-061 … S08-069 (context provider RPC only).
-- Run via backend/tests/catalog/run.sh (do not execute from a stage-writer task).
--
-- CONFLICT: catalog visit UUID 5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b is a
--   documentation alias (Register 5 #14 class); real visit ids come from
--   public.create_visit.
-- CONFLICT: catalog S08-061/062/067 also describe Worker ingress POST
--   (S08-049 / S08-046). This file asserts the RPC half only (no HTTP).
-- CONFLICT: catalog S08-069 names PostgREST HTTP 401/403 and a
--   function-level deny from GRANT EXECUTE … TO authenticated only
--   (S02-002 class). Register 5 #12 requires SQLSTATE 42501 here, not
--   HTTP. CODE grants EXECUTE to authenticated without REVOKE FROM
--   PUBLIC, so anon enters the SECURITY INVOKER wrapper and is denied
--   with 42501 `permission denied for schema auth_internal`.
-- CODE: recorded_at is to_char(created_at AT TIME ZONE 'UTC',
--   'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') after 20260805120000.

BEGIN;

\ir harness.sql

SELECT pg_temp.catalog_common_setup();

-- -----------------------------------------------------------------------------
-- Stage-local helpers (harness API stays frozen).
-- -----------------------------------------------------------------------------

CREATE TEMP TABLE catalog_s08_ids (
  key text PRIMARY KEY,
  value uuid NOT NULL
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
  -- jwt_branch_ids() and current_staff_member_row() match production JWTs.
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

CREATE OR REPLACE FUNCTION pg_temp.s08_stash(p_key text, p_value uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.reset_postgres();
  INSERT INTO catalog_s08_ids (key, value)
  VALUES (p_key, p_value)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s08_id(p_key text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_value uuid;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT t.value INTO STRICT v_value FROM catalog_s08_ids t WHERE t.key = p_key;
  RETURN v_value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s08_working_schedule()
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
CREATE OR REPLACE FUNCTION pg_temp.s08_same_day_slot(p_hour int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_tz text := 'Africa/Cairo';
  v_day_start timestamptz;
BEGIN
  IF p_hour < 0 OR p_hour > 22 THEN
    RAISE EXCEPTION 's08_same_day_slot: hour must be 0..22, got %', p_hour;
  END IF;
  v_day_start := date_trunc('day', now() AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  RETURN v_day_start + make_interval(hours => p_hour);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s08_open_visit(
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

-- [SEED] Flip the linked appointment off in_progress. complete_visit RPC
-- requires documentation, which would pollute the no-note / deleted-note cases.
CREATE OR REPLACE FUNCTION pg_temp.s08_release_in_progress(p_visit_id uuid)
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

-- -----------------------------------------------------------------------------
-- Journey setup: visits/notes (real ids, never the catalog alias).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_admin uuid;
  v_admin_auth uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_rec uuid;
  v_rec_auth uuid;
  v_north uuid;
  v_result public.rpc_result;
  v_patient uuid;
  v_visit uuid;
  v_updated_at timestamptz;
  v_branch_name text;
  v_branch_code text;
  v_catalog_alias uuid := '5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b';
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
    pg_temp.s08_working_schedule(),
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

  v_result := public.create_staff_account(
    's08_reception',
    'Layla#Desk2026!',
    'Layla Reception',
    'receptionist',
    ARRAY[v_branch]::uuid[],
    v_branch,
    NULL
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_staff_account receptionist failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_rec := (v_result.data ->> 'staff_member_id')::uuid;

  v_result := public.manage_create_branch(
    'North Branch',
    pg_temp.s08_working_schedule(),
    'NORTH',
    NULL,
    NULL,
    NULL
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'manage_create_branch failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_north := (v_result.data ->> 'branch_id')::uuid;

  PERFORM pg_temp.reset_postgres();
  SELECT sm.auth_user_id INTO STRICT v_rec_auth
  FROM public.staff_members sm
  WHERE sm.id = v_rec;

  -- [SEED] Assign Omar to North so create_appointment can use him there.
  -- jwt_branch_ids for the RPC under test stays main-only.
  INSERT INTO public.staff_branch_assignments (
    staff_member_id, branch_id, is_primary, created_by, updated_by
  )
  VALUES (v_doctor, v_north, false, v_admin_auth, v_admin_auth);

  PERFORM pg_temp.s08_stash('rec', v_rec);
  PERFORM pg_temp.s08_stash('rec_auth', v_rec_auth);
  PERFORM pg_temp.s08_stash('north', v_north);

  -- Main-branch visits (distinct patients: same-day booking is per patient).
  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );

  v_result := public.create_patient(
    v_branch, 'S08 Complaint Patient', '201800008061', NULL, NULL, NULL, NULL, false
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_patient 061 failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_patient := (v_result.data ->> 'patient_id')::uuid;
  v_visit := pg_temp.s08_open_visit(
    v_branch, v_patient, v_doctor, pg_temp.s08_same_day_slot(10)
  );
  IF v_visit = v_catalog_alias THEN
    RAISE EXCEPTION 'visit 061 collided with catalog documentation alias';
  END IF;
  PERFORM pg_temp.s08_stash('visit_061', v_visit);
  PERFORM pg_temp.s08_release_in_progress(v_visit);

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.create_patient(
    v_branch, 'S08 No Note Patient', '201800008062', NULL, NULL, NULL, NULL, false
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_patient 062 failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_patient := (v_result.data ->> 'patient_id')::uuid;
  v_visit := pg_temp.s08_open_visit(
    v_branch, v_patient, v_doctor, pg_temp.s08_same_day_slot(11)
  );
  PERFORM pg_temp.s08_stash('visit_062', v_visit);
  PERFORM pg_temp.s08_release_in_progress(v_visit);

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.create_patient(
    v_branch, 'S08 Null Complaint Patient', '201800008063', NULL, NULL, NULL, NULL, false
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_patient 063 failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_patient := (v_result.data ->> 'patient_id')::uuid;
  v_visit := pg_temp.s08_open_visit(
    v_branch, v_patient, v_doctor, pg_temp.s08_same_day_slot(12)
  );
  PERFORM pg_temp.s08_stash('visit_063', v_visit);
  PERFORM pg_temp.s08_release_in_progress(v_visit);

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.create_patient(
    v_branch, 'S08 Deleted Note Patient', '201800008064', NULL, NULL, NULL, NULL, false
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_patient 064 failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_patient := (v_result.data ->> 'patient_id')::uuid;
  v_visit := pg_temp.s08_open_visit(
    v_branch, v_patient, v_doctor, pg_temp.s08_same_day_slot(13)
  );
  PERFORM pg_temp.s08_stash('visit_064', v_visit);
  PERFORM pg_temp.s08_release_in_progress(v_visit);

  -- North-branch visit (S08-066 / S08-068). Caller JWT will be main-only.
  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_north, v_doctor, 'doctor'
  );
  v_result := public.create_patient(
    v_north, 'S08 North Patient', '201800008066', NULL, NULL, NULL, NULL, false
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_patient north failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_patient := (v_result.data ->> 'patient_id')::uuid;
  v_visit := pg_temp.s08_open_visit(
    v_north, v_patient, v_doctor, pg_temp.s08_same_day_slot(10)
  );
  PERFORM pg_temp.s08_stash('visit_north', v_visit);
  PERFORM pg_temp.s08_release_in_progress(v_visit);

  -- S08-061 live complaint via RPC, then [SEED] pin created_at (save uses now()).
  v_visit := pg_temp.s08_id('visit_061');
  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  SELECT v.updated_at INTO STRICT v_updated_at
  FROM public.visits v
  WHERE v.id = v_visit;
  v_result := public.save_visit_documentation(
    v_visit,
    'Patient reports headache for 3 days.',
    NULL,
    NULL,
    NULL,
    NULL,
    v_updated_at
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'save_visit_documentation 061 failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  PERFORM pg_temp.reset_postgres();
  UPDATE public.visit_clinical_notes vcn
  SET created_at = '2026-09-05T08:15:00.000Z'::timestamptz
  WHERE vcn.visit_id = v_visit
    AND vcn.is_deleted = false;

  -- [SEED] S08-063: note with complaint NULL (no RPC creates that row shape).
  INSERT INTO public.visit_clinical_notes (
    visit_id, complaint, created_by, updated_by, created_at
  )
  VALUES (
    pg_temp.s08_id('visit_063'),
    NULL,
    v_doctor_auth,
    v_doctor_auth,
    '2026-09-05T09:00:00.000Z'::timestamptz
  );

  -- [SEED] S08-064: only note is soft-deleted.
  INSERT INTO public.visit_clinical_notes (
    visit_id, complaint, created_by, updated_by, is_deleted, deleted_at, deleted_by
  )
  VALUES (
    pg_temp.s08_id('visit_064'),
    'This deleted complaint must not appear.',
    v_doctor_auth,
    v_doctor_auth,
    true,
    now(),
    v_doctor_auth
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-061 — Context provider RPC happy path supplies visit.chief_complaint@v1, full journey to accepted
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
  v_catalog_alias uuid := '5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b';
  v_expected jsonb;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s08_id('visit_061');

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.get_visit_chief_complaint(v_visit);

  PERFORM pg_temp.reset_postgres();
  v_expected := jsonb_build_object(
    'visit_id', v_visit,
    'complaint', 'Patient reports headache for 3 days.',
    'recorded_at', '2026-09-05T08:15:00.000Z'
  );
  v_ok := v_result.success IS TRUE
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND v_result.data = v_expected
    AND (v_result.data ->> 'visit_id') IS DISTINCT FROM v_catalog_alias::text;
  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' data=' || COALESCE(v_result.data::text, '<null>')
    || '; ingress POST covered by existing Worker S08-049 (do not HTTP)';

  PERFORM pg_temp.record(
    'S08-061 — Context provider RPC happy path supplies visit.chief_complaint@v1, full journey to accepted',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-062 — RPC with no clinical note row succeeds with visit_id only; client omits the key and gets context_required
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s08_id('visit_062');

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.get_visit_chief_complaint(v_visit);

  PERFORM pg_temp.reset_postgres();
  v_ok := v_result.success IS TRUE
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND v_result.data = jsonb_build_object('visit_id', v_visit)
    AND NOT (v_result.data ? 'complaint')
    AND NOT (v_result.data ? 'recorded_at');
  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' data=' || COALESCE(v_result.data::text, '<null>')
    || '; ingress POST covered by existing Worker S08-046 (do not HTTP)';

  PERFORM pg_temp.record(
    'S08-062 — RPC with no clinical note row succeeds with visit_id only; client omits the key and gets context_required',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-063 — RPC with a note whose complaint is NULL omits only the complaint key
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
  v_expected jsonb;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s08_id('visit_063');

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.get_visit_chief_complaint(v_visit);

  PERFORM pg_temp.reset_postgres();
  v_expected := jsonb_build_object(
    'visit_id', v_visit,
    'recorded_at', '2026-09-05T09:00:00.000Z'
  );
  v_ok := v_result.success IS TRUE
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND v_result.data = v_expected
    AND NOT (v_result.data ? 'complaint');
  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' data=' || COALESCE(v_result.data::text, '<null>');

  PERFORM pg_temp.record(
    'S08-063 — RPC with a note whose complaint is NULL omits only the complaint key',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-064 — RPC ignores soft-deleted notes
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s08_id('visit_064');

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.get_visit_chief_complaint(v_visit);

  PERFORM pg_temp.reset_postgres();
  v_ok := v_result.success IS TRUE
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND v_result.data = jsonb_build_object('visit_id', v_visit)
    AND NOT (v_result.data ? 'complaint')
    AND NOT (v_result.data ? 'recorded_at');
  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' data=' || COALESCE(v_result.data::text, '<null>');

  PERFORM pg_temp.record(
    'S08-064 — RPC ignores soft-deleted notes',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-065 — RPC with an unknown visit UUID returns NOT_FOUND
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.get_visit_chief_complaint(
    '00000000-0000-4000-8000-000000000099'::uuid
  );

  PERFORM pg_temp.reset_postgres();
  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'NOT_FOUND'
    AND v_result.error_message = 'Visit was not found.';
  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>');

  PERFORM pg_temp.record(
    'S08-065 — RPC with an unknown visit UUID returns NOT_FOUND',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-066 — RPC for a visit outside the caller's branch scope returns NOT_FOUND (not FORBIDDEN)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_doctor uuid;
  v_doctor_auth uuid;
  v_visit uuid;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_visit := pg_temp.s08_id('visit_north');

  -- JWT branch_ids = main only; visit lives in North.
  PERFORM pg_temp.set_clinic_session(
    v_doctor_auth, v_org, v_branch, v_doctor, 'doctor'
  );
  v_result := public.get_visit_chief_complaint(v_visit);

  PERFORM pg_temp.reset_postgres();
  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'NOT_FOUND'
    AND v_result.error_code IS DISTINCT FROM 'FORBIDDEN'
    AND v_result.error_message = 'Visit was not found.';
  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>');

  PERFORM pg_temp.record(
    'S08-066 — RPC for a visit outside the caller''s branch scope returns NOT_FOUND (not FORBIDDEN)',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-067 — RPC without visit clinical read permission returns FORBIDDEN
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_rec uuid;
  v_rec_auth uuid;
  v_visit uuid;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  v_rec := pg_temp.s08_id('rec');
  v_rec_auth := pg_temp.s08_id('rec_auth');
  v_visit := pg_temp.s08_id('visit_061');

  PERFORM pg_temp.set_clinic_session(
    v_rec_auth, v_org, v_branch, v_rec, 'receptionist'
  );
  v_result := public.get_visit_chief_complaint(v_visit);

  PERFORM pg_temp.reset_postgres();
  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'FORBIDDEN'
    AND v_result.error_message = 'You do not have permission to view this visit clinical data.';
  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>')
    || '; ingress POST without the key is Worker S08-046 (do not HTTP)';

  PERFORM pg_temp.record(
    'S08-067 — RPC without visit clinical read permission returns FORBIDDEN',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-068 — RPC check order: out-of-scope visit + no clinical permission yields NOT_FOUND (scope precedes permission)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_rec uuid;
  v_rec_auth uuid;
  v_visit uuid;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  v_rec := pg_temp.s08_id('rec');
  v_rec_auth := pg_temp.s08_id('rec_auth');
  v_visit := pg_temp.s08_id('visit_north');

  PERFORM pg_temp.set_clinic_session(
    v_rec_auth, v_org, v_branch, v_rec, 'receptionist'
  );
  v_result := public.get_visit_chief_complaint(v_visit);

  PERFORM pg_temp.reset_postgres();
  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'NOT_FOUND'
    AND v_result.error_code IS DISTINCT FROM 'FORBIDDEN'
    AND v_result.error_message = 'Visit was not found.';
  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>');

  PERFORM pg_temp.record(
    'S08-068 — RPC check order: out-of-scope visit + no clinical permission yields NOT_FOUND (scope precedes permission)',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S08-069 — RPC is not callable by anonymous clients
-- CODE: no REVOKE FROM PUBLIC on public.get_visit_chief_complaint, so
--   anon enters the invoker wrapper and is denied on schema
--   auth_internal (42501), not at function EXECUTE.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_visit uuid;
  v_result public.rpc_result;
  v_raised boolean := false;
  v_sqlstate text;
  v_msg text;
  v_ok boolean;
  v_detail text;
BEGIN
  v_visit := pg_temp.s08_id('visit_061');

  PERFORM pg_temp.set_anon_session();

  BEGIN
    v_result := public.get_visit_chief_complaint(v_visit);
    v_raised := false;
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_sqlstate := '42501';
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_raised := true;
    WHEN OTHERS THEN
      v_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_raised := true;
  END;

  PERFORM pg_temp.reset_postgres();
  -- CODE deny: 42501 permission denied for schema auth_internal.
  -- Do not require ILIKE '%get_visit_chief_complaint%' (S02-002
  -- REVOKE-FROM-PUBLIC shape). Call must RAISE; no rpc_result.
  v_ok := v_raised
    AND v_sqlstate = '42501'
    AND COALESCE(v_msg, '') ILIKE '%permission denied%'
    AND COALESCE(v_msg, '') ILIKE '%auth_internal%'
    AND v_result IS NULL;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' msg=' || COALESCE(v_msg, '<none>')
    || ' result_assigned=' || (v_result IS NOT NULL)::text
    || '; Register 5 #12 SQLSTATE 42501 (do not assert PostgREST HTTP 401/403)';

  PERFORM pg_temp.record(
    'S08-069 — RPC is not callable by anonymous clients',
    v_ok,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
