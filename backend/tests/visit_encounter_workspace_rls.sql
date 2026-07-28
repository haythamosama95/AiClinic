-- 014 US6/US7 cross-org and cross-branch denial for patient safety and plan RPCs.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/visit_encounter_workspace_rls.sql

BEGIN;

CREATE TEMP TABLE visit_encounter_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_org_a uuid := 'c2600000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c2600000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd2600000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd2600000-0000-4000-8000-0000000000b2';
  v_branch_a2 uuid := 'd2600000-0000-4000-8000-0000000000a2';
  v_user_a uuid := 'e2600000-0000-4000-8000-0000000000a1';
  v_user_b uuid := 'e2600000-0000-4000-8000-0000000000b2';
  v_doctor_user_a uuid := 'e2600000-0000-4000-8000-0000000000a3';
  v_staff_a uuid := 'f2600000-0000-4000-8000-0000000000a1';
  v_staff_b uuid := 'f2600000-0000-4000-8000-0000000000b2';
  v_doctor_a uuid := 'f2600000-0000-4000-8000-0000000000a3';
  v_patient_a uuid := 'a2600000-0000-4000-8000-0000000000a1';
  v_patient_a2 uuid := 'a2600000-0000-4000-8000-0000000000a2';
  v_patient_b uuid := 'a2600000-0000-4000-8000-0000000000b2';
  v_appt_a uuid := 'c2600000-0000-4000-8000-00000000aa01';
  v_appt_a2 uuid := 'c2600000-0000-4000-8000-00000000aa02';
  v_appt_b uuid := 'c2600000-0000-4000-8000-00000000bb01';
  v_visit_a uuid := 'f2600000-0000-4000-8000-00000000aa01';
  v_visit_a2 uuid := 'f2600000-0000-4000-8000-00000000aa02';
  v_visit_b uuid := 'f2600000-0000-4000-8000-00000000bb01';
  v_allergy_a uuid := 'b2600000-0000-4000-8000-00000000aa01';
  v_allergy_a2 uuid := 'b2600000-0000-4000-8000-00000000aa02';
  v_medication_a uuid := 'b2600000-0000-4000-8000-00000000aa03';
  v_condition_a uuid := 'b2600000-0000-4000-8000-00000000aa04';
  v_result public.rpc_result;
  v_visible_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members
  WHERE id IN (v_staff_a, v_staff_b, v_doctor_a);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b, v_branch_a2);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_user_a, v_user_b, v_doctor_user_a);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-enc-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-enc-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-enc-doc-a',
     extensions.crypt('pw-doc-a', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Encounter Org A', v_user_a, v_user_a),
    (v_org_b, 'RLS Encounter Org B', v_user_b, v_user_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'PA', v_user_a, v_user_a),
    (v_branch_a2, v_org_a, 'Branch A2', 'PA2', v_user_a, v_user_a),
    (v_branch_b, v_org_b, 'Branch B', 'PB', v_user_b, v_user_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_a, v_user_a, 'Owner A', 'administrator', v_user_a, v_user_a),
    (v_staff_b, v_user_b, 'Owner B', 'administrator', v_user_b, v_user_b),
    (v_doctor_a, v_doctor_user_a, 'Doctor A', 'doctor', v_user_a, v_user_a);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_a, v_branch_a2, false, v_user_a, v_user_a),
    (v_doctor_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_b, v_branch_b, true, v_user_b, v_user_b);

  INSERT INTO public.patients (id, branch_id, organization_id, full_name, phone, mrn, created_by, updated_by)
  VALUES
    (v_patient_a, v_branch_a, v_org_a, 'Patient A', '201111111261', 'MRN-708001', v_user_a, v_user_a),
    (v_patient_a2, v_branch_a2, v_org_a, 'Patient A2', '201111111262', 'MRN-708002', v_user_a, v_user_a),
    (v_patient_b, v_branch_b, v_org_b, 'Patient B', '201234567961', 'MRN-708003', v_user_b, v_user_b);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES
    (
      v_appt_a, v_branch_a, v_patient_a, v_doctor_a,
      now(), now() + interval '30 minutes', 'planned', 'in_progress', v_user_a, v_user_a
    ),
    (
      v_appt_a2, v_branch_a2, v_patient_a2, v_doctor_a,
      now() + interval '1 hour', now() + interval '90 minutes', 'planned', 'in_progress', v_user_a, v_user_a
    ),
    (
      v_appt_b, v_branch_b, v_patient_b, v_staff_b,
      now(), now() + interval '30 minutes', 'planned', 'in_progress', v_user_b, v_user_b
    );

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES
    (
      v_visit_a, v_branch_a, v_appt_a, v_patient_a, v_doctor_a,
      current_date, 'in_progress', v_user_a, v_user_a
    ),
    (
      v_visit_a2, v_branch_a2, v_appt_a2, v_patient_a2, v_doctor_a,
      current_date, 'in_progress', v_user_a, v_user_a
    ),
    (
      v_visit_b, v_branch_b, v_appt_b, v_patient_b, v_staff_b,
      current_date, 'in_progress', v_user_b, v_user_b
    );

  INSERT INTO public.patient_allergies (id, patient_id, substance, reaction, created_by, updated_by)
  VALUES
    (v_allergy_a, v_patient_a, 'Peanuts', 'Anaphylaxis', v_user_a, v_user_a),
    (v_allergy_a2, v_patient_a2, 'Latex', 'Rash', v_user_a, v_user_a);

  INSERT INTO public.patient_medications (id, patient_id, name, note, created_by, updated_by)
  VALUES (v_medication_a, v_patient_a, 'Aspirin', 'Daily', v_user_a, v_user_a);

  INSERT INTO public.patient_chronic_conditions (
    id, patient_id, name, note, created_by, updated_by
  )
  VALUES (v_condition_a, v_patient_a, 'Hypertension', 'Stable', v_user_a, v_user_a);

  -- Cross-org denial as org B administrator.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_b::text,
      'role', 'authenticated',
      'organization_id', v_org_b::text,
      'branch_ids', v_branch_b::text,
      'staff_member_id', v_staff_b::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int INTO v_visible_count FROM public.patient_allergies;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_patient_allergies_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*)::int INTO v_visible_count FROM public.patient_medications;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_patient_medications_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*)::int INTO v_visible_count FROM public.patient_chronic_conditions;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_patient_chronic_conditions_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_patient_safety_context(v_patient_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_get_patient_safety_context_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient_allergy(v_patient_a, 'Shellfish', 'Hives');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_create_patient_allergy_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_patient_allergy(v_allergy_a, 'Hijacked', NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_update_patient_allergy_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_patient_allergy(v_allergy_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_archive_patient_allergy_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient_medication(v_patient_a, 'Ibuprofen', NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_create_patient_medication_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_patient_medication(v_medication_a, 'Hijacked', NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_update_patient_medication_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_patient_medication(v_medication_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_archive_patient_medication_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient_chronic_condition(v_patient_a, 'Diabetes', NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_create_patient_chronic_condition_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_patient_chronic_condition(v_condition_a, 'Hijacked', NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_update_patient_chronic_condition_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_patient_chronic_condition(v_condition_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_org_archive_patient_chronic_condition_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cross-branch within org: doctor assigned only to branch A cannot access branch A2 patient safety.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_doctor_a::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int
  INTO v_visible_count
  FROM public.patient_allergies pa
  WHERE pa.id = v_allergy_a2;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_branch_patient_allergies_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_patient_safety_context(v_patient_a2);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_branch_get_patient_safety_context_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient_allergy(v_patient_a2, 'Should not create', NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_branch_create_patient_allergy_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_patient_allergy(v_allergy_a2, 'Should not update', NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_branch_update_patient_allergy_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_patient_allergy(v_allergy_a2);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_branch_archive_patient_allergy_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient_medication(v_patient_a2, 'Should not create', NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_branch_create_patient_medication_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_patient_chronic_condition(v_patient_a2, 'Should not create', NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_encounter_rls_results VALUES (
    'cross_branch_create_patient_chronic_condition_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

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
  FROM visit_encounter_rls_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM visit_encounter_rls_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'visit_encounter_workspace_rls: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
