-- E3 context provider RPC tests (E3-T05..E3-T08).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/context_provider_rpc.sql

BEGIN;

CREATE TEMP TABLE context_provider_rpc_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.set_authenticated_session(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
    true
  );
END;
$$;

DO $$
DECLARE
  v_org_a uuid := 'e3700000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'e3700000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'e3710000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'e3710000-0000-4000-8000-0000000000b2';
  v_user_a uuid := 'e3720000-0000-4000-8000-0000000000a1';
  v_user_b uuid := 'e3720000-0000-4000-8000-0000000000b2';
  v_doctor_user_a uuid := 'e3720000-0000-4000-8000-0000000000a3';
  v_staff_a uuid := 'e3730000-0000-4000-8000-0000000000a1';
  v_staff_b uuid := 'e3730000-0000-4000-8000-0000000000b2';
  v_doctor_a uuid := 'e3730000-0000-4000-8000-0000000000a3';
  v_patient_a uuid := 'e3740000-0000-4000-8000-0000000000a1';
  v_patient_b uuid := 'e3740000-0000-4000-8000-0000000000b2';
  v_appt_a uuid := 'e3750000-0000-4000-8000-0000000000a1';
  v_appt_b uuid := 'e3750000-0000-4000-8000-0000000000b2';
  v_visit_a uuid := 'e3760000-0000-4000-8000-0000000000a1';
  v_visit_b uuid := 'e3760000-0000-4000-8000-0000000000b2';
  v_note_a uuid := 'e3770000-0000-4000-8000-0000000000a1';
  v_result public.rpc_result;
  v_payload jsonb;
  v_passed boolean;
  v_detail text;
  v_arg_names text;
  v_body text;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members
  WHERE id IN (v_staff_a, v_staff_b, v_doctor_a);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users
  WHERE id IN (v_user_a, v_user_b, v_doctor_user_a);

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES
    (v_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'ctx-rpc-a', extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'ctx-rpc-b', extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'ctx-rpc-doc-a', extensions.crypt('pw-doc-a', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'Context RPC Org A', v_user_a, v_user_a),
    (v_org_b, 'Context RPC Org B', v_user_b, v_user_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'CA', v_user_a, v_user_a),
    (v_branch_b, v_org_b, 'Branch B', 'CB', v_user_b, v_user_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_a, v_user_a, 'Owner A', 'administrator', v_user_a, v_user_a),
    (v_staff_b, v_user_b, 'Owner B', 'administrator', v_user_b, v_user_b),
    (v_doctor_a, v_doctor_user_a, 'Doctor A', 'doctor', v_user_a, v_user_a);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_a, v_branch_a, true, v_user_a, v_user_a),
    (v_doctor_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_b, v_branch_b, true, v_user_b, v_user_b);

  INSERT INTO public.patients (id, branch_id, organization_id, full_name, phone, mrn, created_by, updated_by)
  VALUES
    (v_patient_a, v_branch_a, v_org_a, 'Patient A', '201111111301', 'MRN-370001', v_user_a, v_user_a),
    (v_patient_b, v_branch_b, v_org_b, 'Patient B', '201111111302', 'MRN-370002', v_user_b, v_user_b);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES
    (v_appt_a, v_branch_a, v_patient_a, v_doctor_a, now(), now() + interval '30 minutes',
     'planned', 'in_progress', v_user_a, v_user_a),
    (v_appt_b, v_branch_b, v_patient_b, v_staff_b, now(), now() + interval '30 minutes',
     'planned', 'in_progress', v_user_b, v_user_b);

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES
    (v_visit_a, v_branch_a, v_appt_a, v_patient_a, v_doctor_a, current_date, 'in_progress', v_user_a, v_user_a),
    (v_visit_b, v_branch_b, v_appt_b, v_patient_b, v_staff_b, current_date, 'in_progress', v_user_b, v_user_b);

  INSERT INTO public.visit_clinical_notes (
    id, visit_id, complaint, created_by, updated_by, updated_at
  )
  VALUES
    (v_note_a, v_visit_a, 'Persistent headache for three days.', v_user_a, v_user_a,
     '2026-07-31T12:00:00+00'::timestamptz);

  -- E3-T05 context_rpc_returns_declared_shape
  PERFORM pg_temp.set_authenticated_session(v_doctor_user_a);
  v_result := public.get_visit_chief_complaint(v_visit_a);
  v_payload := v_result.data;
  v_passed := v_result.success
    AND v_payload ? 'visit_id'
    AND v_payload ? 'complaint'
    AND (v_payload->>'visit_id') = v_visit_a::text
    AND (v_payload->>'complaint') = 'Persistent headache for three days.';
  v_detail := format('success=%s data=%s', v_result.success, v_payload);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO context_provider_rpc_results VALUES (
    'context_rpc_returns_declared_shape',
    v_passed,
    v_detail
  );

  -- E3-T06 context_rpc_rls_denies_out_of_scope
  PERFORM pg_temp.set_authenticated_session(v_doctor_user_a);
  v_result := public.get_visit_chief_complaint(v_visit_b);
  v_passed := (NOT v_result.success)
    OR (v_result.data IS NULL)
    OR (NOT (v_result.data ? 'complaint'));
  v_detail := format('success=%s error=%s data=%s', v_result.success, v_result.error_code, v_result.data);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO context_provider_rpc_results VALUES (
    'context_rpc_rls_denies_out_of_scope',
    v_passed,
    v_detail
  );

  -- E3-T07 context_rpc_no_ai_specific_parameter
  SELECT string_agg(p.proargnames[i], ', ' ORDER BY i)
  INTO v_arg_names
  FROM pg_proc p
  CROSS JOIN generate_subscripts(p.proargnames, 1) AS i
  WHERE p.proname = 'get_visit_chief_complaint'
    AND p.pronamespace = 'public'::regnamespace
    AND p.proargnames[i] IS NOT NULL
    AND p.proargnames[i] <> '';

  SELECT pg_get_functiondef(p.oid)
  INTO v_body
  FROM pg_proc p
  WHERE p.proname = 'get_visit_chief_complaint'
    AND p.pronamespace = 'auth_internal'::regnamespace;

  v_passed := coalesce(v_arg_names, '') = 'p_visit_id'
    AND v_body NOT ILIKE '%prompt%'
    AND v_body NOT ILIKE '%provider%'
    AND v_body NOT ILIKE '%quota%'
    AND v_body NOT ILIKE '%ai_request%'
    AND v_body NOT ILIKE '%capability%';
  v_detail := format('args=%s', v_arg_names);
  INSERT INTO context_provider_rpc_results VALUES (
    'context_rpc_no_ai_specific_parameter',
    v_passed,
    v_detail
  );

  -- E3-T08 context_rpc_shape_matches_a5_published_key
  PERFORM pg_temp.set_authenticated_session(v_doctor_user_a);
  v_result := public.get_visit_chief_complaint(v_visit_a);
  v_payload := v_result.data;
  v_passed := v_result.success
    AND (v_payload->>'visit_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND jsonb_typeof(v_payload->'complaint') = 'string'
    AND length(v_payload->>'complaint') <= 10000
    AND (
      NOT (v_payload ? 'recorded_at')
      OR (v_payload->>'recorded_at') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$'
    );
  v_detail := format('data=%s', v_payload);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO context_provider_rpc_results VALUES (
    'context_rpc_shape_matches_a5_published_key',
    v_passed,
    v_detail
  );
END;
$$;

DO $$
DECLARE
  v_row record;
BEGIN
  FOR v_row IN
    SELECT test_name, passed, detail
    FROM context_provider_rpc_results
    ORDER BY test_name
  LOOP
    IF NOT v_row.passed THEN
      RAISE EXCEPTION 'Context provider RPC test failed: % — %', v_row.test_name, v_row.detail;
    END IF;
  END LOOP;
END;
$$;

ROLLBACK;
