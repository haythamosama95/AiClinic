-- V1-4 cross-org and cross-branch denial for appointments.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/appointment_management_rls.sql

BEGIN;

CREATE TEMP TABLE appointment_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_org_a uuid := 'c2400000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c2400000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd2400000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd2400000-0000-4000-8000-0000000000b2';
  v_branch_a2 uuid := 'd2400000-0000-4000-8000-0000000000a2';
  v_user_a uuid := 'e2400000-0000-4000-8000-0000000000a1';
  v_user_b uuid := 'e2400000-0000-4000-8000-0000000000b2';
  v_staff_a uuid := 'f2400000-0000-4000-8000-0000000000a1';
  v_staff_b uuid := 'f2400000-0000-4000-8000-0000000000b2';
  v_doctor_user_a uuid := 'e2400000-0000-4000-8000-0000000000a3';
  v_doctor_a uuid := 'f2400000-0000-4000-8000-0000000000a3';
  v_patient_a uuid := 'a2400000-0000-4000-8000-0000000000a1';
  v_patient_b uuid := 'a2400000-0000-4000-8000-0000000000b2';
  v_appt_a uuid := 'c2400000-0000-4000-8000-00000000aa01';
  v_appt_b uuid := 'c2400000-0000-4000-8000-00000000bb01';
  v_result public.rpc_result;
  v_visible_count int;
  v_dml_failed boolean;
  v_create_denied boolean;
  v_create_detail text;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.appointments;
  DELETE FROM public.patients;
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id IN (v_staff_a, v_staff_b, v_doctor_a);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b, v_branch_a2);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_user_a, v_user_b, v_doctor_user_a);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-appt-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-appt-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-appt-doc-a',
     extensions.crypt('pw-doc-a', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Appt Org A', v_user_a, v_user_a),
    (v_org_b, 'RLS Appt Org B', v_user_b, v_user_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'PA', v_user_a, v_user_a),
    (v_branch_a2, v_org_a, 'Branch A2', 'PA2', v_user_a, v_user_a),
    (v_branch_b, v_org_b, 'Branch B', 'PB', v_user_b, v_user_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_a, v_user_a, 'Owner A', 'owner', v_user_a, v_user_a),
    (v_staff_b, v_user_b, 'Owner B', 'owner', v_user_b, v_user_b),
    (v_doctor_a, v_doctor_user_a, 'Doctor A', 'doctor', v_user_a, v_user_a);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_a, v_branch_a2, false, v_user_a, v_user_a),
    (v_doctor_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_b, v_branch_b, true, v_user_b, v_user_b);

  INSERT INTO public.patients (id, branch_id, organization_id, full_name, phone, created_by, updated_by)
  VALUES
    (v_patient_a, v_branch_a, v_org_a, 'Patient A', '201111111141', v_user_a, v_user_a),
    ('a2400000-0000-4000-8000-0000000000a2', v_branch_a2, v_org_a, 'Patient A2', '201111111142', v_user_a, v_user_a),
    (v_patient_b, v_branch_b, v_org_b, 'Patient B', '201234567891', v_user_b, v_user_b);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES
    (
      v_appt_a,
      v_branch_a,
      v_patient_a,
      v_doctor_a,
      now() + interval '1 day',
      now() + interval '1 day 30 minutes',
      'planned',
      'scheduled',
      v_user_a,
      v_user_a
    ),
    (
      'c2400000-0000-4000-8000-00000000aa02',
      v_branch_a2,
      'a2400000-0000-4000-8000-0000000000a2',
      v_doctor_a,
      now() + interval '2 days',
      now() + interval '2 days 30 minutes',
      'planned',
      'scheduled',
      v_user_a,
      v_user_a
    ),
    (
      v_appt_b,
      v_branch_b,
      v_patient_b,
      v_staff_b,
      now() + interval '1 day',
      now() + interval '1 day 30 minutes',
      'planned',
      'scheduled',
      v_user_b,
      v_user_b
    );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_a::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int
  INTO v_visible_count
  FROM public.appointments a
  WHERE a.id = v_appt_b;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_rls_results VALUES (
    'cross_org_direct_select_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.list_appointments(
    v_branch_b,
    now() - interval '1 day',
    now() + interval '7 days',
    NULL,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_rls_results VALUES (
    'cross_org_list_other_branch_denied',
    NOT v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.cancel_appointment(v_appt_b, 'hack');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_rls_results VALUES (
    'cross_org_cancel_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cross-branch within org: user assigned only to branch A cannot list branch B appointments via RPC.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_a::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int
  INTO v_visible_count
  FROM public.appointments a
  WHERE a.branch_id = v_branch_a2;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_rls_results VALUES (
    'cross_branch_direct_select_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Direct DML denied.
  v_dml_failed := false;
  BEGIN
    INSERT INTO public.appointments (
      branch_id, patient_id, doctor_id, start_time, end_time, type, status
    )
    VALUES (
      v_branch_a,
      v_patient_a,
      v_doctor_a,
      now(),
      now() + interval '30 minutes',
      'planned',
      'scheduled'
    );
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_dml_failed := true;
    WHEN OTHERS THEN
      v_dml_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_rls_results VALUES (
    'direct_insert_denied',
    v_dml_failed,
    CASE WHEN v_dml_failed THEN 'denied' ELSE 'allowed' END
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cross-org create via RPC denied.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_a::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  v_create_denied := false;
  v_create_detail := 'ok';
  BEGIN
    v_result := public.create_appointment(
      v_branch_b,
      v_patient_b,
      v_doctor_a,
      'planned',
      now() + interval '2 days',
      30,
      NULL,
      NULL
    );
    v_create_denied := NOT v_result.success;
    v_create_detail := COALESCE(v_result.error_code, 'ok');
  EXCEPTION
    WHEN OTHERS THEN
      v_create_denied := SQLERRM IN ('INVALID_BRANCH', 'FORBIDDEN', 'NOT_FOUND');
      v_create_detail := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_rls_results VALUES (
    'cross_org_create_appointment_denied',
    v_create_denied,
    v_create_detail
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  SELECT count(*)::int
  INTO v_failed
  FROM appointment_rls_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM appointment_rls_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'appointment_management_rls: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
