-- ui/014 visit documentation complete validation (BE-003..BE-005).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/visit_documentation_complete_validation.sql
--
-- Covers visit_has_documentation via complete_visit RPC:
--   BE-003 vital sign alone satisfies documentation
--   BE-004 empty visit rejected
--   BE-005 patient safety alone does NOT satisfy
--
-- Limitation: runs as psql superuser (postgres), bypassing EXECUTE checks PostgREST
-- enforces for role authenticated. Grant regressions belong in dedicated grant tests.

BEGIN;

CREATE TEMP TABLE visit_documentation_complete_validation_results (
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
  v_owner_user uuid := 'a1700000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b1700000-0000-4000-8000-000000000101';
  v_doctor_user uuid := 'a1700000-0000-4000-8000-000000000102';
  v_doctor_staff uuid := 'b1700000-0000-4000-8000-000000000102';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_id uuid;
  v_appt_id uuid;
  v_visit_id uuid;
  v_vital_sign_id uuid;
  v_start timestamptz;
  v_i int;
  v_sd_patient uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.app_settings WHERE key IN ('appointment.default_duration_minutes');
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v17-doc-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v17-doc-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V17 Doc Complete Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
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

  v_result := public.create_patient(v_branch_main, 'Doc Complete Patient', '201000000171', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  CREATE TEMP TABLE same_day_slot_patients (slot int PRIMARY KEY, patient_id uuid NOT NULL);
  FOR v_i IN 2..3 LOOP
    v_result := public.create_patient(
      v_branch_main,
      'V17 Doc Slot ' || v_i,
      '2010000171' || lpad(v_i::text, 2, '0'),
      NULL,
      NULL,
      NULL,
      NULL,
      false
    );
    INSERT INTO same_day_slot_patients (slot, patient_id)
    VALUES (v_i, (v_result.data ->> 'patient_id')::uuid);
  END LOOP;

  -- BE-003: vital sign alone satisfies visit_has_documentation.
  v_start := pg_temp.test_appointment_same_day_slot(1);
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;

  v_result := public.create_visit_vital_sign(v_visit_id, 'Blood Pressure', '120/80', 'mmHg', NULL);
  v_vital_sign_id := (v_result.data ->> 'vital_sign_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_documentation_complete_validation_results VALUES (
    'BE-003_setup_vital_sign_only',
    v_result.success
      AND v_vital_sign_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.visit_clinical_notes vcn
        WHERE vcn.visit_id = v_visit_id AND vcn.is_deleted = false
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.complete_visit(v_visit_id, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_documentation_complete_validation_results VALUES (
    'BE-003_complete_visit_vital_sign_only_satisfies_documentation',
    v_result.success
      AND (v_result.data ->> 'visit_status') = 'completed'
      AND (v_result.data ->> 'appointment_status') = 'completed'
      AND EXISTS (
        SELECT 1
        FROM public.visits v
        WHERE v.id = v_visit_id AND v.status = 'completed'
      ),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-004: empty visit rejected on complete_visit.
  PERFORM pg_temp.release_doctor_in_progress(v_doctor_staff);
  v_start := pg_temp.test_appointment_same_day_slot(2);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 2;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;

  v_result := public.complete_visit(v_visit_id, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_documentation_complete_validation_results VALUES (
    'BE-004_complete_visit_empty_visit_rejected',
    NOT v_result.success AND v_result.error_code = 'DOCUMENTATION_REQUIRED_FOR_COMPLETE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.release_doctor_in_progress(v_doctor_staff);

  -- BE-005: patient safety alone does NOT satisfy visit_has_documentation.
  v_start := pg_temp.test_appointment_same_day_slot(3);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 3;
  v_result := public.create_appointment(
    v_branch_main, v_sd_patient, v_doctor_staff, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;

  v_result := public.create_patient_allergy(v_sd_patient, 'Penicillin', 'Rash');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_documentation_complete_validation_results VALUES (
    'BE-005_setup_patient_allergy_only',
    v_result.success
      AND (v_result.data ->> 'id') IS NOT NULL
      AND NOT auth_internal.visit_has_documentation(v_visit_id),
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.complete_visit(v_visit_id, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_documentation_complete_validation_results VALUES (
    'BE-005_complete_visit_patient_safety_only_rejected',
    NOT v_result.success AND v_result.error_code = 'DOCUMENTATION_REQUIRED_FOR_COMPLETE',
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
  FROM visit_documentation_complete_validation_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM visit_documentation_complete_validation_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'visit_documentation_complete_validation: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
