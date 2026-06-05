-- V1-3 patient management: extended coverage (boundary, normalization, field preservation).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_management_extended.sql

BEGIN;

CREATE TEMP TABLE patient_ext_results (
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
  v_branch_inactive uuid;
  v_patient_id uuid;
  v_patient_b uuid;
  v_updated_at timestamptz;
  v_phone_stored text;
  v_name_stored text;
  v_gender_stored text;
  v_marital_stored text;
  v_notes_stored text;
  v_dob_stored date;
  v_audit_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.patients;
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id NOT IN (v_bootstrap_staff);
  DELETE FROM public.audit_log;
  DELETE FROM public.branches;
  PERFORM auth_internal.delete_billing_dependents();
  DELETE FROM public.organizations;
  DELETE FROM auth.users WHERE id = v_owner_user;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ext-owner',
    extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('ExtTest Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'EXT', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.branches (id, organization_id, name, code, is_active, created_by, updated_by)
  VALUES ('d3000000-0000-4000-8000-000000000001', v_org_id, 'Inactive', 'INACT', false,
    v_bootstrap_user, v_bootstrap_user);
  v_branch_inactive := 'd3000000-0000-4000-8000-000000000001';

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES (v_owner_staff, v_owner_user, 'Test Owner', 'owner', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  -- =========================================================================
  -- PHONE BOUNDARY CONDITIONS
  -- =========================================================================

  -- Phone exactly 8 digits (minimum valid).
  v_result := public.create_patient(v_branch_main, 'Phone Min', '12345678', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'phone_exactly_8_digits_accepted',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Phone exactly 15 digits (maximum valid).
  v_result := public.create_patient(v_branch_main, 'Phone Max', '123456789012345', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'phone_exactly_15_digits_accepted',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Phone 7 digits (below minimum).
  v_result := public.create_patient(v_branch_main, 'Phone Short', '1234567', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'phone_7_digits_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Phone 16 digits (above maximum).
  v_result := public.create_patient(v_branch_main, 'Phone Long', '1234567890123456', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'phone_16_digits_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- PHONE NORMALIZATION
  -- =========================================================================

  -- Phone with spaces, dashes, plus sign normalized to digits only.
  v_result := public.create_patient(v_branch_main, 'Phone Format', '+20 100-555-1234', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  SELECT phone INTO v_phone_stored FROM public.patients WHERE id = v_patient_id;
  INSERT INTO patient_ext_results VALUES (
    'phone_normalized_strips_non_digits',
    v_result.success AND v_phone_stored = '201005551234',
    'stored=' || COALESCE(v_phone_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Phone with parentheses and dots.
  v_result := public.create_patient(v_branch_main, 'Phone Parens', '(020)555.1234.99', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  SELECT phone INTO v_phone_stored FROM public.patients WHERE id = (v_result.data ->> 'patient_id')::uuid;
  INSERT INTO patient_ext_results VALUES (
    'phone_normalized_parens_dots',
    v_result.success AND v_phone_stored = '020555123499',
    'stored=' || COALESCE(v_phone_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- NAME TRIMMING
  -- =========================================================================

  -- Leading/trailing whitespace is trimmed on create.
  v_result := public.create_patient(v_branch_main, '   Trimmed Name   ', '201000000011', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  SELECT full_name INTO v_name_stored FROM public.patients WHERE id = (v_result.data ->> 'patient_id')::uuid;
  INSERT INTO patient_ext_results VALUES (
    'create_trims_name_whitespace',
    v_result.success AND v_name_stored = 'Trimmed Name',
    'stored=' || COALESCE(v_name_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- MARITAL STATUS VALIDATION
  -- =========================================================================

  -- Valid marital statuses accepted.
  v_result := public.create_patient(v_branch_main, 'MS Single', '201000000022', NULL, NULL, 'single', NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_marital_status_single',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient(v_branch_main, 'MS Married', '201000000033', NULL, NULL, 'married', NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_marital_status_married',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient(v_branch_main, 'MS Divorced', '201000000034', NULL, NULL, 'divorced', NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_marital_status_divorced',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient(v_branch_main, 'MS Widowed', '201000000035', NULL, NULL, 'widowed', NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_marital_status_widowed',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Invalid marital status rejected.
  v_result := public.create_patient(v_branch_main, 'MS Invalid', '201000000036', NULL, NULL, 'complicated', NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_invalid_marital_status_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- GENDER VALIDATION (post-migration: only male/female)
  -- =========================================================================

  -- Valid genders accepted.
  v_result := public.create_patient(v_branch_main, 'Gender Male', '201000000037', NULL, 'male', NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_gender_male',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient(v_branch_main, 'Gender Female', '201000000038', NULL, 'female', NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_gender_female',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Gender 'other' rejected after enum migration.
  v_result := public.create_patient(v_branch_main, 'Gender Other', '201000000039', NULL, 'other', NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_gender_other_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Gender 'unknown' rejected after enum migration.
  v_result := public.create_patient(v_branch_main, 'Gender Unknown', '201000000040', NULL, 'unknown', NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_gender_unknown_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Empty-string gender treated as omitted (NULL stored).
  v_result := public.create_patient(v_branch_main, 'Gender Empty', '201000000041', NULL, '', NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  SELECT gender::text INTO v_gender_stored FROM public.patients WHERE id = (v_result.data ->> 'patient_id')::uuid;
  INSERT INTO patient_ext_results VALUES (
    'create_empty_gender_stores_null',
    v_result.success AND v_gender_stored IS NULL,
    'gender=' || COALESCE(v_gender_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- DATE OF BIRTH BOUNDARY
  -- =========================================================================

  -- DOB = today is valid.
  v_result := public.create_patient(v_branch_main, 'Born Today', '201000000042', current_date, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_dob_today_accepted',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- DOB = yesterday is valid.
  v_result := public.create_patient(v_branch_main, 'Born Yesterday', '201000000043', current_date - 1, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_dob_yesterday_accepted',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Very old DOB accepted (1900-01-01).
  v_result := public.create_patient(v_branch_main, 'Very Old', '201000000044', '1900-01-01'::date, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_dob_very_old_accepted',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- NOTES BOUNDARY
  -- =========================================================================

  -- Notes exactly 4000 chars accepted.
  v_result := public.create_patient(v_branch_main, 'Long Notes OK', '201000000045', NULL, NULL, NULL, repeat('x', 4000), false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_notes_exactly_4000_accepted',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Notes empty string stored as NULL.
  v_result := public.create_patient(v_branch_main, 'Empty Notes', '201000000046', NULL, NULL, NULL, '', false);
  PERFORM set_config('role', 'postgres', true);
  SELECT notes INTO v_notes_stored FROM public.patients WHERE id = (v_result.data ->> 'patient_id')::uuid;
  INSERT INTO patient_ext_results VALUES (
    'create_empty_notes_stored_as_null',
    v_result.success AND v_notes_stored IS NULL,
    'notes=' || COALESCE(v_notes_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Whitespace-only notes stored as NULL.
  v_result := public.create_patient(v_branch_main, 'Whitespace Notes', '201000000047', NULL, NULL, NULL, '   ', false);
  PERFORM set_config('role', 'postgres', true);
  SELECT notes INTO v_notes_stored FROM public.patients WHERE id = (v_result.data ->> 'patient_id')::uuid;
  INSERT INTO patient_ext_results VALUES (
    'create_whitespace_notes_stored_as_null',
    v_result.success AND v_notes_stored IS NULL,
    'notes=' || COALESCE(v_notes_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- INACTIVE / DELETED BRANCH ON CREATE
  -- =========================================================================

  -- Create at inactive branch rejected.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text || ',' || v_branch_inactive::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.create_patient(v_branch_inactive, 'Inactive Branch', '201000000048', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_at_inactive_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore normal JWT.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  -- =========================================================================
  -- FIELD PRESERVATION ON UPDATE (NULL params preserve old values)
  -- =========================================================================

  -- Create a fully-populated patient.
  v_result := public.create_patient(
    v_branch_main,
    'Full Patient',
    '201099887766',
    '1985-03-20'::date,
    'female',
    'married',
    'Important notes here',
    false
  );
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;

  -- Update only name; phone/dob/gender/marital_status/notes should all be preserved.
  v_result := public.update_patient(
    v_patient_id,
    'Full Patient Renamed',
    v_updated_at,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    false
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT phone, date_of_birth, gender::text, marital_status::text, notes
  INTO v_phone_stored, v_dob_stored, v_gender_stored, v_marital_stored, v_notes_stored
  FROM public.patients WHERE id = v_patient_id;
  INSERT INTO patient_ext_results VALUES (
    'update_preserves_phone_when_null',
    v_result.success AND v_phone_stored = '201099887766',
    'phone=' || COALESCE(v_phone_stored, '<null>')
  );
  INSERT INTO patient_ext_results VALUES (
    'update_preserves_dob_when_null',
    v_result.success AND v_dob_stored = '1985-03-20'::date,
    'dob=' || COALESCE(v_dob_stored::text, '<null>')
  );
  INSERT INTO patient_ext_results VALUES (
    'update_preserves_gender_when_null',
    v_gender_stored = 'female',
    'gender=' || COALESCE(v_gender_stored, '<null>')
  );
  INSERT INTO patient_ext_results VALUES (
    'update_preserves_marital_status_when_null',
    v_marital_stored = 'married',
    'marital=' || COALESCE(v_marital_stored, '<null>')
  );
  INSERT INTO patient_ext_results VALUES (
    'update_preserves_notes_when_null',
    v_notes_stored = 'Important notes here',
    'notes=' || COALESCE(v_notes_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Update gender to male; confirm change applied.
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.update_patient(v_patient_id, 'Full Patient Renamed', v_updated_at, NULL, NULL, 'male', NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  SELECT gender::text INTO v_gender_stored FROM public.patients WHERE id = v_patient_id;
  INSERT INTO patient_ext_results VALUES (
    'update_changes_gender_when_provided',
    v_result.success AND v_gender_stored = 'male',
    'gender=' || COALESCE(v_gender_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Update marital_status; confirm change applied.
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.update_patient(v_patient_id, 'Full Patient Renamed', v_updated_at, NULL, NULL, NULL, 'divorced', NULL, false);
  PERFORM set_config('role', 'postgres', true);
  SELECT marital_status::text INTO v_marital_stored FROM public.patients WHERE id = v_patient_id;
  INSERT INTO patient_ext_results VALUES (
    'update_changes_marital_status_when_provided',
    v_result.success AND v_marital_stored = 'divorced',
    'marital=' || COALESCE(v_marital_stored, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Invalid marital status on update rejected.
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.update_patient(v_patient_id, 'Full Patient Renamed', v_updated_at, NULL, NULL, NULL, 'partnered', NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_invalid_marital_status_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Invalid gender on update rejected.
  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.update_patient(v_patient_id, 'Full Patient Renamed', v_updated_at, NULL, NULL, 'nonbinary', NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_invalid_gender_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- UPDATE: PHONE VALIDATION BOUNDARIES
  -- =========================================================================

  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.update_patient(v_patient_id, 'Full Patient Renamed', v_updated_at, '1234567', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_phone_7_digits_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_patient(v_patient_id);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.update_patient(v_patient_id, 'Full Patient Renamed', v_updated_at, '1234567890123456', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_phone_16_digits_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- UPDATE: EXPECTED TIMESTAMP (NULL rejected)
  -- =========================================================================

  v_result := public.update_patient(v_patient_id, 'Full Patient Renamed', NULL, NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_null_expected_timestamp_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- ARCHIVE AUDIT LOG
  -- =========================================================================

  v_result := public.create_patient(v_branch_main, 'Archivable', '201000000050', NULL, NULL, NULL, NULL, false);
  v_patient_b := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.archive_patient(v_patient_b);
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_audit_count
  FROM public.audit_log al
  WHERE al.record_id = v_patient_b AND al.action = 'patient.archive';
  INSERT INTO patient_ext_results VALUES (
    'archive_writes_audit_log',
    v_result.success AND v_audit_count = 1,
    'count=' || v_audit_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- GET PATIENT: CREATED_BY_DISPLAY FIELD
  -- =========================================================================

  v_result := public.create_patient(v_branch_main, 'Display Test', '201000000051', NULL, NULL, NULL, NULL, false);
  v_patient_b := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.get_patient(v_patient_b);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'get_patient_has_created_by_display',
    v_result.success AND (v_result.data ->> 'created_by_display') = 'Test Owner',
    'display=' || COALESCE(v_result.data ->> 'created_by_display', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- GET PATIENT: MARITAL STATUS IN RESPONSE
  -- =========================================================================

  v_result := public.create_patient(v_branch_main, 'MS Response', '201000000052', NULL, NULL, 'widowed', NULL, false);
  v_patient_b := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.get_patient(v_patient_b);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'get_patient_includes_marital_status',
    v_result.success AND (v_result.data ->> 'marital_status') = 'widowed',
    'marital=' || COALESCE(v_result.data ->> 'marital_status', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- DUPLICATE LOGIC EDGE CASES
  -- =========================================================================

  -- Same name but different DOB does NOT trigger duplicate.
  v_result := public.create_patient(v_branch_main, 'Dup Name A', '201000000053', '1990-01-01'::date, NULL, NULL, NULL, false);
  v_result := public.create_patient(v_branch_main, 'Dup Name A', '201000000054', '1995-06-15'::date, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'duplicate_name_different_dob_no_warning',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Same DOB but different name does NOT trigger duplicate.
  v_result := public.create_patient(v_branch_main, 'Unique Name ABC', '201000000055', '1980-12-25'::date, NULL, NULL, NULL, false);
  v_result := public.create_patient(v_branch_main, 'Different Name XYZ', '201000000056', '1980-12-25'::date, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'duplicate_different_name_same_dob_no_warning',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Same name + same DOB triggers DUPLICATE_WARNING.
  v_result := public.create_patient(v_branch_main, 'Dup Name A', '201000000057', '1990-01-01'::date, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'duplicate_same_name_same_dob_warns',
    NOT v_result.success AND v_result.error_code = 'DUPLICATE_WARNING',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Acknowledge duplicate allows creation.
  v_result := public.create_patient(v_branch_main, 'Dup Name A', '201000000057', '1990-01-01'::date, NULL, NULL, NULL, true);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'duplicate_acknowledged_allows_create',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- NULL BRANCH ID ON CREATE
  -- =========================================================================

  v_result := public.create_patient(NULL, 'No Branch', '201000000058', NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_null_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- FULL CREATE WITH ALL FIELDS
  -- =========================================================================

  v_result := public.create_patient(
    v_branch_main,
    'Complete Patient',
    '+20-100-999-8877',
    '1992-07-04'::date,
    'female',
    'single',
    'Some important clinical notes',
    false
  );
  v_patient_b := (v_result.data ->> 'patient_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'create_all_fields_success',
    v_result.success AND v_patient_b IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_patient(v_patient_b);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'get_all_fields_correct',
    v_result.success
      AND (v_result.data ->> 'full_name') = 'Complete Patient'
      AND (v_result.data ->> 'phone') = '201009998877'
      AND (v_result.data ->> 'date_of_birth') = '1992-07-04'
      AND (v_result.data ->> 'gender') = 'female'
      AND (v_result.data ->> 'marital_status') = 'single'
      AND (v_result.data ->> 'notes') = 'Some important clinical notes',
    'name=' || COALESCE(v_result.data ->> 'full_name', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- UPDATE ARCHIVED PATIENT REJECTED
  -- =========================================================================

  v_result := public.create_patient(v_branch_main, 'Will Archive', '201000000059', NULL, NULL, NULL, NULL, false);
  v_patient_b := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.get_patient(v_patient_b);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.archive_patient(v_patient_b);
  v_result := public.update_patient(v_patient_b, 'Updated After Archive', v_updated_at, NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_archived_patient_rejected',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ARCHIVED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- ARCHIVE NON-EXISTENT PATIENT
  -- =========================================================================

  v_result := public.archive_patient('99999999-9999-4999-8999-999999999999');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'archive_nonexistent_patient_not_found',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- UPDATE NON-EXISTENT PATIENT
  -- =========================================================================

  v_result := public.update_patient('99999999-9999-4999-8999-999999999999', 'Ghost', now(), NULL, NULL, NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_nonexistent_patient_not_found',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- FUTURE DOB ON UPDATE
  -- =========================================================================

  v_result := public.create_patient(v_branch_main, 'Future DOB Update', '201000000060', '2000-01-01'::date, NULL, NULL, NULL, false);
  v_patient_b := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.get_patient(v_patient_b);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.update_patient(v_patient_b, 'Future DOB Update', v_updated_at, NULL, (current_date + 1), NULL, NULL, NULL, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_future_dob_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- =========================================================================
  -- OVERSIZED NOTES ON UPDATE
  -- =========================================================================

  v_result := public.get_patient(v_patient_b);
  v_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.update_patient(v_patient_b, 'Future DOB Update', v_updated_at, NULL, NULL, NULL, NULL, repeat('y', 4001), false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_ext_results VALUES (
    'update_oversized_notes_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM patient_ext_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM patient_ext_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'patient_management_extended: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
