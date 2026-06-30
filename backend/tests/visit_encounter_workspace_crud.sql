-- 014 US6/US7 visit encounter workspace RPC verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/visit_encounter_workspace_crud.sql
--
-- Limitation: runs as psql superuser (postgres), bypassing EXECUTE checks PostgREST
-- enforces for role authenticated. Grant regressions belong in dedicated grant tests.

BEGIN;

CREATE TEMP TABLE visit_encounter_crud_results (
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

CREATE OR REPLACE FUNCTION pg_temp.release_doctor_in_progress(p_doctor_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);

  UPDATE public.visits v
  SET
    status = 'completed',
    updated_at = now()
  FROM public.appointments a
  WHERE v.appointment_id = a.id
    AND v.is_deleted = false
    AND v.status = 'in_progress'
    AND a.doctor_id = p_doctor_id
    AND a.is_deleted = false;

  UPDATE public.appointments a
  SET
    status = 'completed',
    updated_at = now()
  WHERE a.doctor_id = p_doctor_id
    AND a.is_deleted = false
    AND a.status = 'in_progress';

  PERFORM set_config('role', 'authenticated', true);
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1600000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b1600000-0000-4000-8000-000000000101';
  v_doctor_user uuid := 'a1600000-0000-4000-8000-000000000102';
  v_doctor_staff uuid := 'b1600000-0000-4000-8000-000000000102';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_id uuid;
  v_appt_id uuid;
  v_visit_id uuid;
  v_allergy_id uuid;
  v_medication_record_id uuid;
  v_condition_id uuid;
  v_catalog_diag_id uuid;
  v_visit_diag_id uuid;
  v_visit_updated_at timestamptz;
  v_plan_updated_at timestamptz;
  v_start timestamptz;
  v_vital_sign_id uuid;
  v_measured_at timestamptz := '2026-06-15 10:30:00+00';
  v_prior_investigation_line_id uuid;
  v_followup_visit_id uuid;
  v_followup_appt_id uuid;
  v_result_recorded_at timestamptz;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.app_settings WHERE key IN ('appointment.default_duration_minutes');
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v16-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v16-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V16 Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
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
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Dr Smith', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_main, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_doctor_staff)) AS s(id);

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

  v_result := public.create_patient(v_branch_main, 'Encounter Patient', '201000000161', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  v_start := pg_temp.test_appointment_same_day_slot(1);
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;
  SELECT v.updated_at INTO v_visit_updated_at FROM public.visits v WHERE v.id = v_visit_id;

  -- get_patient_safety_context: empty before any records exist.
  v_result := public.get_patient_safety_context(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'get_patient_safety_context_empty',
    v_result.success
      AND jsonb_array_length(COALESCE(v_result.data -> 'allergies', '[]'::jsonb)) = 0
      AND jsonb_array_length(COALESCE(v_result.data -> 'current_medications', '[]'::jsonb)) = 0
      AND jsonb_array_length(COALESCE(v_result.data -> 'chronic_conditions', '[]'::jsonb)) = 0,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Patient allergy CRUD.
  v_result := public.create_patient_allergy(v_patient_id, 'Penicillin', 'Rash');
  v_allergy_id := (v_result.data ->> 'id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_patient_allergy',
    v_result.success AND v_allergy_id IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_patient_allergy(v_allergy_id, 'Penicillin V', 'Hives');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'update_patient_allergy',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.patient_allergies pa
        WHERE pa.id = v_allergy_id
          AND pa.substance = 'Penicillin V'
          AND pa.reaction = 'Hives'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Patient medication CRUD.
  v_result := public.create_patient_medication(v_patient_id, 'Metformin', NULL, '500mg daily');
  v_medication_record_id := (v_result.data ->> 'id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_patient_medication',
    v_result.success AND v_medication_record_id IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_patient_medication(v_medication_record_id, 'Metformin XR', NULL, '1000mg daily');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'update_patient_medication',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.patient_medications pm
        WHERE pm.id = v_medication_record_id
          AND pm.name = 'Metformin XR'
          AND pm.note = '1000mg daily'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Patient chronic condition CRUD.
  v_result := public.create_patient_chronic_condition(v_patient_id, 'Hypertension', NULL, 'Controlled');
  v_condition_id := (v_result.data ->> 'id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_patient_chronic_condition',
    v_result.success AND v_condition_id IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_patient_chronic_condition(v_condition_id, 'Essential Hypertension', NULL, 'On medication');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'update_patient_chronic_condition',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.patient_chronic_conditions pcc
        WHERE pcc.id = v_condition_id
          AND pcc.name = 'Essential Hypertension'
          AND pcc.note = 'On medication'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- get_patient_safety_context: populated after creates.
  v_result := public.get_patient_safety_context(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'get_patient_safety_context_after_create',
    v_result.success
      AND jsonb_array_length(COALESCE(v_result.data -> 'allergies', '[]'::jsonb)) >= 1
      AND jsonb_array_length(COALESCE(v_result.data -> 'current_medications', '[]'::jsonb)) >= 1
      AND jsonb_array_length(COALESCE(v_result.data -> 'chronic_conditions', '[]'::jsonb)) >= 1,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_patient_allergy(v_allergy_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'archive_patient_allergy',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.patient_allergies pa
        WHERE pa.id = v_allergy_id AND pa.is_deleted = true
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_patient_medication(v_medication_record_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'archive_patient_medication',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.patient_medications pm
        WHERE pm.id = v_medication_record_id AND pm.is_deleted = true
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_patient_chronic_condition(v_condition_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'archive_patient_chronic_condition',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.patient_chronic_conditions pcc
        WHERE pcc.id = v_condition_id AND pcc.is_deleted = true
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Diagnosis catalog: explicit create then search (test orgs are not migration-seeded).
  v_result := public.create_catalog_diagnosis_code('Searchable Diagnosis', 'S99');
  v_catalog_diag_id := (v_result.data ->> 'id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_catalog_diagnosis_code_first_insert',
    v_result.success
      AND v_catalog_diag_id IS NOT NULL
      AND COALESCE((v_result.data ->> 'created')::boolean, false) = true,
    COALESCE(v_result.error_code, 'created=' || COALESCE(v_result.data ->> 'created', '<null>'))
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_catalog_diagnosis_code('Searchable Diagnosis', 'S99');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_catalog_diagnosis_code_idempotent',
    v_result.success
      AND (v_result.data ->> 'id')::uuid = v_catalog_diag_id
      AND COALESCE((v_result.data ->> 'created')::boolean, true) = false,
    COALESCE(v_result.error_code, 'created=' || COALESCE(v_result.data ->> 'created', '<null>'))
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.search_diagnosis_codes('Searchable', 10);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'search_diagnosis_codes_prefix',
    v_result.success
      AND jsonb_array_length(COALESCE(v_result.data -> 'items', '[]'::jsonb)) >= 1,
    'count=' || COALESCE(jsonb_array_length(COALESCE(v_result.data -> 'items', '[]'::jsonb))::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Visit diagnosis code create/archive.
  v_result := public.create_visit_diagnosis_code(
    v_visit_id,
    'Essential hypertension',
    'I10',
    v_catalog_diag_id
  );
  v_visit_diag_id := (v_result.data ->> 'visit_diagnosis_code_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_visit_diagnosis_code',
    v_result.success
      AND v_visit_diag_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.visit_diagnosis_codes vdc
        WHERE vdc.id = v_visit_diag_id
          AND vdc.visit_id = v_visit_id
          AND vdc.label = 'Essential hypertension'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_visit_diagnosis_code(v_visit_diag_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'archive_visit_diagnosis_code',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.visit_diagnosis_codes vdc
        WHERE vdc.id = v_visit_diag_id AND vdc.is_deleted = true
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- save_visit_plan_details: first save uses visit updated_at as expected timestamp.
  v_result := public.save_visit_plan_details(
    v_visit_id,
    'in 2 weeks',
    (current_date + 14)::date,
    'Take medication with food.',
    'Cardiology referral',
    NULL,
    NULL,
    NULL,
    v_visit_updated_at
  );
  v_plan_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'save_visit_plan_details_first_save',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.visit_plan_details vpd
        WHERE vpd.visit_id = v_visit_id
          AND vpd.is_deleted = false
          AND vpd.follow_up_interval = 'in 2 weeks'
          AND vpd.patient_instructions = 'Take medication with food.'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.save_visit_plan_details(
    v_visit_id,
    'Stale attempt',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    v_visit_updated_at - interval '1 second'
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'save_visit_plan_details_stale_conflict',
    NOT v_result.success AND v_result.error_code = 'STALE_PLAN_DETAILS',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- US8: vital sign measured_at and investigation result capture.
  v_result := public.create_visit_vital_sign(
    v_visit_id, 'Heart Rate', '72', 'bpm', NULL, v_measured_at
  );
  v_vital_sign_id := (v_result.data ->> 'vital_sign_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_visit_vital_sign_measured_at',
    v_result.success
      AND v_vital_sign_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.visit_vital_signs vvs
        WHERE vvs.id = v_vital_sign_id
          AND vvs.measured_at = v_measured_at
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_visit_vital_sign(
    v_vital_sign_id, NULL, NULL, NULL, NULL, v_measured_at + interval '1 hour'
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'update_visit_vital_sign_measured_at',
    v_result.success
      AND EXISTS (
        SELECT 1
        FROM public.visit_vital_signs vvs
        WHERE vvs.id = v_vital_sign_id
          AND vvs.measured_at = v_measured_at + interval '1 hour'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Investigation ordered on the current visit (prior relative to follow-up).
  v_result := public.create_visit_investigation(v_visit_id, 'Complete Blood Count', 'Fasting', NULL);
  v_prior_investigation_line_id := (v_result.data ->> 'investigation_line_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_prior_visit_investigation',
    v_result.success AND v_prior_investigation_line_id IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Follow-up visit records result against prior investigation.
  PERFORM pg_temp.release_doctor_in_progress(v_doctor_staff);
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.appointments
  SET status = 'completed', is_deleted = true, deleted_at = now(), updated_at = now()
  WHERE id = v_appt_id;
  UPDATE public.visits SET status = 'completed', updated_at = now() WHERE id = v_visit_id;
  PERFORM set_config('role', 'authenticated', true);

  v_start := pg_temp.test_appointment_same_day_slot(2);
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 30, NULL, NULL
  );
  v_followup_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_followup_appointment',
    v_result.success AND v_followup_appt_id IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.update_appointment_status(v_followup_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_followup_appt_id, 'checked_in');
  v_result := public.create_visit(v_followup_appt_id, NULL);
  v_followup_visit_id := (v_result.data ->> 'visit_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'create_followup_visit',
    v_result.success AND v_followup_visit_id IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_visit(v_followup_visit_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'get_visit_pending_investigations_before_result',
    v_result.success
      AND jsonb_array_length(COALESCE(v_result.data -> 'pending_investigations', '[]'::jsonb)) = 1,
    'pending=' || COALESCE(jsonb_array_length(COALESCE(v_result.data -> 'pending_investigations', '[]'::jsonb))::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.record_investigation_result(
    v_prior_investigation_line_id,
    'WBC 7.2, Hgb 14.1 — within normal limits'
  );
  v_result_recorded_at := (v_result.data ->> 'result_recorded_at')::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'record_investigation_result',
    v_result.success
      AND v_result_recorded_at IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.visit_investigations vi
        WHERE vi.id = v_prior_investigation_line_id
          AND vi.result LIKE 'WBC 7.2%'
          AND vi.result_recorded_at IS NOT NULL
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_visit(v_followup_visit_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_crud_results VALUES (
    'get_visit_pending_investigations_after_result',
    v_result.success
      AND jsonb_array_length(COALESCE(v_result.data -> 'pending_investigations', '[]'::jsonb)) = 0,
    'pending=' || COALESCE(jsonb_array_length(COALESCE(v_result.data -> 'pending_investigations', '[]'::jsonb))::text, '<null>')
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
  FROM visit_encounter_crud_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM visit_encounter_crud_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'visit_encounter_workspace_crud: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
