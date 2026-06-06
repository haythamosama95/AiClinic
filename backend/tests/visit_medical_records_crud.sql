-- V1-5 visit medical records RPC verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/visit_medical_records_crud.sql
--
-- Limitation: runs as psql superuser (postgres), bypassing EXECUTE checks PostgREST
-- enforces for role authenticated. Grant regressions belong in dedicated grant tests.

BEGIN;

CREATE TEMP TABLE visit_crud_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.test_appointment_same_day_slot(p_offset_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_tz text := 'UTC';
  v_day_start timestamptz;
BEGIN
  IF p_offset_hours < 1 OR p_offset_hours > 23 THEN
    RAISE EXCEPTION 'test_appointment_same_day_slot: offset must be 1..23, got %', p_offset_hours;
  END IF;
  v_day_start := date_trunc('day', now() AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  RETURN v_day_start + make_interval(hours => p_offset_hours);
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1500000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b1500000-0000-4000-8000-000000000101';
  v_doctor_user uuid := 'a1500000-0000-4000-8000-000000000102';
  v_doctor_staff uuid := 'b1500000-0000-4000-8000-000000000102';
  v_lab_user uuid := 'a1500000-0000-4000-8000-000000000103';
  v_lab_staff uuid := 'b1500000-0000-4000-8000-000000000103';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_id uuid;
  v_patient2_id uuid;
  v_sd_patient uuid;
  v_appt_id uuid;
  v_appt2_id uuid;
  v_visit_id uuid;
  v_visit2_id uuid;
  v_completed_visit_id uuid;
  v_completed_appt_id uuid;
  v_visit_updated_at timestamptz;
  v_soap_updated_at timestamptz;
  v_plan_id uuid;
  v_attachment_id uuid;
  v_file_path text;
  v_start timestamptz;
  v_items jsonb;
  v_appt_status text;
  v_i int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.app_settings WHERE key IN ('appointment.default_duration_minutes', 'specialty.form_schema_json');
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user, v_lab_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v15-lab',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V15 Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = jsonb_build_object(
    'days',
    jsonb_build_array(
      jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59')
    )
  )
  WHERE b.id = v_branch_main;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'owner', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Dr Smith', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Lab Tech', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_main, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_doctor_staff), (v_lab_staff)) AS s(id);

  INSERT INTO public.app_settings (organization_id, branch_id, key, value_json, created_by, updated_by)
  VALUES (
    v_org_id,
    NULL,
    'specialty.form_schema_json',
    '{"type":"object","properties":{"pain_score":{"type":"number","title":"Pain score"},"notes":{"type":"string","title":"Notes"}},"required":["pain_score"]}'::jsonb,
    v_bootstrap_user,
    v_bootstrap_user
  );

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

  v_result := public.create_patient(v_branch_main, 'Visit Patient', '201000000151', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_branch_main, 'Visit Patient 2', '201000000152', NULL, NULL, NULL, NULL, false);
  v_patient2_id := (v_result.data ->> 'patient_id')::uuid;

  CREATE TEMP TABLE same_day_slot_patients (slot int PRIMARY KEY, patient_id uuid NOT NULL);
  FOR v_i IN 2..15 LOOP
    v_result := public.create_patient(
      v_branch_main,
      'V15 Slot ' || v_i,
      '2010000015' || lpad(v_i::text, 2, '0'),
      NULL,
      NULL,
      NULL,
      NULL,
      false
    );
    INSERT INTO same_day_slot_patients (slot, patient_id)
    VALUES (v_i, (v_result.data ->> 'patient_id')::uuid);
  END LOOP;

  -- APPOINTMENT_NOT_ELIGIBLE: scheduled appointment cannot create visit.
  v_start := pg_temp.test_appointment_same_day_slot(1);
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.create_visit(v_appt_id, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_visit_rejects_scheduled_appointment',
    NOT v_result.success AND v_result.error_code = 'APPOINTMENT_NOT_ELIGIBLE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- DOCTOR_REQUIRED: checked-in appointment without doctor.
  v_start := pg_temp.test_appointment_same_day_slot(2);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 2;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, NULL, 'planned', v_start, 20, NULL, 'no doctor'
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_visit_doctor_required',
    NOT v_result.success AND v_result.error_code = 'DOCTOR_REQUIRED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_visit(v_appt_id, v_doctor_staff);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_visit_with_doctor_selection',
    v_result.success
      AND (v_result.data ->> 'status') = 'in_progress'
      AND EXISTS (
        SELECT 1
        FROM public.appointments a
        WHERE a.id = v_appt_id
          AND a.status = 'in_progress'
          AND a.doctor_id = v_doctor_staff
      ),
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- create_visit from checked_in advances appointment to in_progress.
  v_start := pg_temp.test_appointment_same_day_slot(3);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 3;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  SELECT status::text INTO v_appt_status FROM public.appointments WHERE id = v_appt_id;
  v_result := public.create_visit(v_appt_id, NULL);
  v_visit2_id := (v_result.data ->> 'visit_id')::uuid;
  SELECT status::text INTO v_appt_status FROM public.appointments WHERE id = v_appt_id;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_visit_from_checked_in_advances_appointment',
    v_result.success
      AND (v_result.data ->> 'status') = 'in_progress'
      AND v_appt_status = 'in_progress',
    COALESCE(v_result.error_code, 'appt=' || COALESCE(v_appt_status, '<null>'))
  );
  PERFORM set_config('role', 'authenticated', true);

  -- create_visit from in_progress (appointment already in_progress).
  v_start := pg_temp.test_appointment_same_day_slot(4);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 4;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.update_appointment_status(v_appt_id, 'in_progress');
  v_result := public.create_visit(v_appt_id, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_visit_from_in_progress',
    v_result.success AND (v_result.data ->> 'status') = 'in_progress',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- VISIT_ALREADY_EXISTS duplicate.
  v_result := public.create_visit(v_appt_id, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_visit_duplicate_rejected',
    NOT v_result.success AND v_result.error_code = 'VISIT_ALREADY_EXISTS',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_visit_by_appointment returns in-progress visit for linked appointment.
  v_result := public.get_visit_by_appointment(v_appt_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_visit_by_appointment_in_progress',
    v_result.success
      AND (v_result.data ->> 'visit_id') IS NOT NULL
      AND (v_result.data ->> 'status') = 'in_progress',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_visit_by_appointment empty when no visit exists.
  v_start := pg_temp.test_appointment_same_day_slot(15);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 15;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt2_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt2_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt2_id, 'checked_in');
  v_result := public.get_visit_by_appointment(v_appt2_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_visit_by_appointment_no_visit',
    v_result.success
      AND (v_result.data ->> 'visit_id') IS NULL
      AND (v_result.data ->> 'status') IS NULL,
    COALESCE(v_result.error_code, 'visit_id=' || COALESCE(v_result.data ->> 'visit_id', '<null>'))
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SOAP workflow on a dedicated visit.
  v_start := pg_temp.test_appointment_same_day_slot(5);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 5;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_completed_appt_id := v_appt_id;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;
  SELECT v.updated_at INTO v_visit_updated_at FROM public.visits v WHERE v.id = v_visit_id;

  v_result := public.save_soap_note(
    v_visit_id,
    v_visit_updated_at,
    'Partial subjective only.',
    NULL,
    NULL,
    NULL,
    NULL
  );
  v_soap_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'save_soap_note_partial_save',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.soap_notes sn
        WHERE sn.visit_id = v_visit_id
          AND sn.subjective = 'Partial subjective only.'
          AND sn.objective IS NULL
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.save_soap_note(
    v_visit_id,
    v_visit_updated_at - interval '1 second',
    'Stale attempt.',
    NULL,
    NULL,
    NULL,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'save_soap_note_stale_conflict',
    NOT v_result.success AND v_result.error_code = 'STALE_SOAP',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SOAP_REQUIRED_FOR_COMPLETE when all sections empty.
  v_start := pg_temp.test_appointment_same_day_slot(6);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 6;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  v_visit2_id := (v_result.data ->> 'visit_id')::uuid;
  SELECT v.updated_at INTO v_visit_updated_at FROM public.visits v WHERE v.id = v_visit2_id;
  v_result := public.save_soap_note(v_visit2_id, v_visit_updated_at, '   ', '  ', NULL, NULL, NULL);
  v_soap_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.complete_visit(v_visit2_id, v_soap_updated_at);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'complete_visit_requires_soap_content',
    NOT v_result.success AND v_result.error_code = 'SOAP_REQUIRED_FOR_COMPLETE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- complete_visit with SOAP completes appointment.
  SELECT sn.updated_at
  INTO v_soap_updated_at
  FROM public.soap_notes sn
  WHERE sn.visit_id = v_visit_id
    AND sn.is_deleted = false;

  v_result := public.save_soap_note(
    v_visit_id,
    v_soap_updated_at,
    'Chief complaint.',
    'Exam findings.',
    NULL,
    NULL,
    NULL
  );
  v_soap_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.complete_visit(v_visit_id, v_soap_updated_at);
  v_completed_visit_id := v_visit_id;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'complete_visit_with_soap_completes_appointment',
    v_result.success
      AND (v_result.data ->> 'visit_status') = 'completed'
      AND (v_result.data ->> 'appointment_status') = 'completed'
      AND EXISTS (
        SELECT 1
        FROM public.appointments a
        WHERE a.id = v_completed_appt_id AND a.status = 'completed'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_visit clinical detail and get_visit_by_appointment (completed visit).
  v_result := public.get_visit(v_completed_visit_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_visit_clinical_includes_soap',
    v_result.success
      AND (v_result.data ? 'soap')
      AND (v_result.data -> 'soap' ->> 'subjective') = 'Chief complaint.',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_lab_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_lab_staff::text,
      'staff_role', 'lab_staff',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.get_visit(v_completed_visit_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_visit_lab_staff_metadata_only',
    v_result.success
      AND NOT (v_result.data ? 'soap')
      AND (v_result.data ->> 'status') = 'completed',
    COALESCE(v_result.error_code, '<null>')
  );
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

  v_result := public.get_visit_by_appointment(v_completed_appt_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_visit_by_appointment',
    v_result.success
      AND (v_result.data ->> 'visit_id')::uuid = v_completed_visit_id
      AND (v_result.data ->> 'status') = 'completed',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- SOAP save on completed visit (post-submit corrections).
  SELECT sn.updated_at INTO v_soap_updated_at
  FROM public.soap_notes sn
  WHERE sn.visit_id = v_completed_visit_id AND sn.is_deleted = false;
  v_result := public.save_soap_note(
    v_completed_visit_id,
    v_soap_updated_at,
    'Chief complaint (corrected).',
    'Exam findings.',
    NULL,
    NULL,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'save_soap_note_on_completed_visit',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.soap_notes sn
        WHERE sn.visit_id = v_completed_visit_id
          AND sn.is_deleted = false
          AND sn.subjective = 'Chief complaint (corrected).'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Treatment plan create / update / archive.
  v_start := pg_temp.test_appointment_same_day_slot(7);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 7;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;

  v_result := public.create_treatment_plan(
    v_visit_id,
    'Amoxicillin',
    '500mg',
    'twice daily',
    current_date,
    current_date + 7,
    'Take with food'
  );
  v_plan_id := (v_result.data ->> 'treatment_plan_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_treatment_plan',
    v_result.success AND v_plan_id IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_treatment_plan(v_plan_id, 'Amoxicillin XR', '875mg', NULL, NULL, NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'update_treatment_plan',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.treatment_plans tp
        WHERE tp.id = v_plan_id
          AND tp.medication_name = 'Amoxicillin XR'
          AND tp.dosage = '875mg'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_treatment_plan(v_plan_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'archive_treatment_plan',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.treatment_plans tp
        WHERE tp.id = v_plan_id AND tp.is_deleted = true
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Treatment plan duration field.
  v_result := public.create_treatment_plan(
    v_visit_id, 'Duration Med', NULL, NULL, NULL, NULL, NULL, '14 days'
  );
  v_plan_id := (v_result.data ->> 'treatment_plan_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_treatment_plan_with_duration',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.treatment_plans tp
        WHERE tp.id = v_plan_id AND tp.duration = '14 days'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_treatment_plan(
    v_visit_id, 'Too Long', NULL, NULL, NULL, NULL, NULL, repeat('x', 201)
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_treatment_plan_rejects_duration_too_long',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_visit includes treatment plans (non-archived).
  v_result := public.create_treatment_plan(
    v_visit_id, 'Ibuprofen', '200mg', 'as needed', NULL, NULL, 'For pain'
  );
  v_plan_id := (v_result.data ->> 'treatment_plan_id')::uuid;
  v_result := public.get_visit(v_visit_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_visit_includes_treatment_plans',
    v_result.success
      AND jsonb_array_length(COALESCE(v_result.data -> 'treatment_plans', '[]'::jsonb)) >= 1,
    'count=' || COALESCE(jsonb_array_length(COALESCE(v_result.data -> 'treatment_plans', '[]'::jsonb))::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Treatment plan on completed visit (corrections allowed).
  SELECT v.updated_at INTO v_visit_updated_at FROM public.visits v WHERE v.id = v_visit_id;
  v_result := public.save_soap_note(v_visit_id, v_visit_updated_at, 'Chief complaint for tp.', NULL, NULL, NULL, NULL);
  v_soap_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.complete_visit(v_visit_id, v_soap_updated_at);

  v_result := public.create_treatment_plan(
    v_visit_id, 'Post-visit Med', '100mg', 'once daily', NULL, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'create_treatment_plan_on_completed_visit',
    v_result.success AND (v_result.data ->> 'treatment_plan_id') IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- register_visit_attachment (storage.objects seeded as postgres).
  v_file_path := v_org_id::text || '/' || v_branch_main::text || '/' || v_visit_id::text || '/lab-result.pdf';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO storage.objects (bucket_id, name, owner, metadata)
  VALUES ('visit-attachments', v_file_path, v_owner_user, '{}'::jsonb)
  ON CONFLICT (bucket_id, name) DO NOTHING;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.register_visit_attachment(v_visit_id, v_file_path, 'pdf', 1024, 'Lab PDF');
  v_attachment_id := (v_result.data ->> 'attachment_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'register_visit_attachment',
    v_result.success
      AND v_attachment_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.visit_attachments va
        WHERE va.id = v_attachment_id AND va.file_path = v_file_path
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_visit_attachment_download allowed for clinical staff on any visit attachment.
  v_result := public.get_visit_attachment_download(v_attachment_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_visit_attachment_download_clinical',
    v_result.success
      AND (v_result.data ->> 'file_path') = v_file_path
      AND COALESCE(v_result.data ->> 'filename', '') <> '',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- register_visit_attachment rejects disallowed file types.
  v_result := public.register_visit_attachment(
    v_visit_id,
    v_org_id::text || '/' || v_branch_main::text || '/' || v_visit_id::text || '/bad.exe',
    'exe',
    512,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'register_visit_attachment_invalid_file_type',
    NOT v_result.success AND v_result.error_code = 'INVALID_FILE_TYPE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- register_visit_attachment rejects oversize metadata.
  v_result := public.register_visit_attachment(
    v_visit_id,
    v_file_path,
    'pdf',
    26214401,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'register_visit_attachment_file_too_large',
    NOT v_result.success AND v_result.error_code = 'FILE_TOO_LARGE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_visit lists attachment metadata with can_download for clinical caller.
  v_result := public.get_visit(v_visit_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_visit_includes_attachments',
    v_result.success
      AND jsonb_array_length(COALESCE(v_result.data -> 'attachments', '[]'::jsonb)) >= 1
      AND COALESCE((v_result.data -> 'attachments' -> 0 ->> 'can_download')::boolean, false),
    'count=' || COALESCE(jsonb_array_length(COALESCE(v_result.data -> 'attachments', '[]'::jsonb))::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- list_patient_visits pagination metadata (multiple completed visits).
  v_start := pg_temp.test_appointment_same_day_slot(8);
  v_result := public.create_appointment(
    v_branch_main, v_patient2_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt2_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt2_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt2_id, 'checked_in');
  v_result := public.create_visit(v_appt2_id, NULL);
  v_visit2_id := (v_result.data ->> 'visit_id')::uuid;
  SELECT v.updated_at INTO v_visit_updated_at FROM public.visits v WHERE v.id = v_visit2_id;
  v_result := public.save_soap_note(v_visit2_id, v_visit_updated_at, 'Second visit note.', NULL, NULL, NULL, NULL);
  v_soap_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.complete_visit(v_visit2_id, v_soap_updated_at);

  v_result := public.list_patient_visits(v_patient2_id, 1, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'list_patient_visits_pagination_metadata',
    v_result.success
      AND (v_result.data ->> 'limit')::int = 1
      AND (v_result.data ->> 'offset')::int = 0
      AND (v_result.data ->> 'total_count')::int >= 1
      AND jsonb_array_length(v_result.data -> 'items') = 1,
    'total=' || COALESCE(v_result.data ->> 'total_count', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_specialty_form_schema.
  v_result := public.get_specialty_form_schema();
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'get_specialty_form_schema',
    v_result.success
      AND (v_result.data -> 'schema_json' ? 'properties'),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- save_soap_note persists valid specialty_form_json.
  v_result := public.save_soap_note(
    v_visit_id,
    v_soap_updated_at,
    'Subjective with specialty.',
    NULL,
    NULL,
    NULL,
    '{"pain_score": 4}'::jsonb
  );
  v_soap_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'save_soap_note_specialty_json_valid',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.soap_notes sn
        WHERE sn.visit_id = v_visit_id
          AND sn.subjective = 'Subjective with specialty.'
          AND (sn.specialty_form_json ->> 'pain_score') = '4'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- save_soap_note rejects unknown specialty field keys.
  v_result := public.save_soap_note(
    v_visit_id,
    v_soap_updated_at,
    'Subjective with invalid specialty.',
    NULL,
    NULL,
    NULL,
    '{"unknown_field": 1}'::jsonb
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'save_soap_note_specialty_json_unknown_field',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- save_soap_note rejects specialty JSON missing required pain_score.
  v_result := public.save_soap_note(
    v_visit_id,
    v_soap_updated_at,
    'Subjective missing required specialty field.',
    NULL,
    NULL,
    NULL,
    '{"notes": "only notes"}'::jsonb
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'save_soap_note_specialty_json_missing_required',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- set_specialty_form_schema upserts org schema and round-trips via get_specialty_form_schema.
  v_result := public.set_specialty_form_schema(
    '{"type":"object","properties":{"severity":{"type":"string","title":"Severity"}},"required":["severity"]}'::jsonb
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'set_specialty_form_schema_success',
    v_result.success
      AND v_result.data -> 'schema_json' ? 'properties'
      AND v_result.data -> 'schema_json' -> 'properties' ? 'severity',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_specialty_form_schema();
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'set_specialty_form_schema_round_trip',
    v_result.success
      AND v_result.data -> 'schema_json' -> 'properties' ? 'severity',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- set_specialty_form_schema rejects invalid schema shape.
  v_result := public.set_specialty_form_schema('[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'set_specialty_form_schema_invalid_input',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- set_specialty_form_schema clear with empty object.
  v_result := public.set_specialty_form_schema('{}'::jsonb);
  v_result := public.get_specialty_form_schema();
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'set_specialty_form_schema_clear',
    v_result.success AND v_result.data -> 'schema_json' = '{}'::jsonb,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore schema for subsequent save_soap_note specialty tests if needed.
  v_result := public.set_specialty_form_schema(
    '{"type":"object","properties":{"pain_score":{"type":"number","title":"Pain score"},"notes":{"type":"string","title":"Notes"}},"required":["pain_score"]}'::jsonb
  );

  -- set_specialty_form_schema forbidden for doctor role.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_doctor_staff::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.set_specialty_form_schema('{}'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'set_specialty_form_schema_forbidden_doctor',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
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

  -- update_appointment_status in_progress -> completed requires visit completion.
  v_start := pg_temp.test_appointment_same_day_slot(9);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 9;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.update_appointment_status(v_appt_id, 'in_progress');
  v_result := public.update_appointment_status(v_appt_id, 'completed');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_crud_results VALUES (
    'update_appointment_status_requires_visit_for_completion',
    NOT v_result.success AND v_result.error_code = 'VISIT_REQUIRED_FOR_COMPLETION',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'postgres', true);
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  SELECT count(*)::int
  INTO v_failed
  FROM visit_crud_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM visit_crud_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'visit_medical_records_crud: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
