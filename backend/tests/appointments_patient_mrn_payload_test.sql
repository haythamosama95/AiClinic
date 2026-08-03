-- Appointment list RPC payloads include patient MRN (016 US6).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/appointments_patient_mrn_payload_test.sql

BEGIN;

CREATE TEMP TABLE appointment_mrn_payload_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1500000-0000-4000-8000-000000000601';
  v_owner_staff uuid := 'b1500000-0000-4000-8000-000000000601';
  v_doctor_user uuid := 'a1500000-0000-4000-8000-000000000602';
  v_doctor_staff uuid := 'b1500000-0000-4000-8000-000000000602';
  v_result public.rpc_result;
  v_list public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_id uuid;
  v_patient_mrn text;
  v_appt_id uuid;
  v_items jsonb;
  v_item jsonb;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_mrn_format_ok boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appt-mrn-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appt-mrn-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Appointment MRN Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Appointment Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Appointment Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user);

  PERFORM setval('public.patient_mrn_seq', 1, false);

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

  v_result := public.create_patient(v_branch_main, 'Appointment MRN Patient', '201800000101', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_patient_mrn := v_result.data ->> 'mrn';

  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '1 day';

  v_result := public.create_appointment(
    v_branch_main,
    v_patient_id,
    v_doctor_staff,
    'planned',
    v_day_start + interval '11 hours',
    30,
    NULL,
    NULL
  );
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;

  v_mrn_format_ok := v_patient_mrn ~ '^MRN-\d{6,}$';

  v_list := public.list_appointments(
    v_branch_main,
    v_day_start,
    v_day_end,
    NULL,
    NULL,
    v_patient_id
  );
  v_items := v_list.data -> 'items';
  v_item := (
    SELECT elem
    FROM jsonb_array_elements(v_items) AS elem
    WHERE (elem ->> 'id')::uuid = v_appt_id
    LIMIT 1
  );

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO appointment_mrn_payload_results VALUES (
    'list_appointments_includes_patient_mrn',
    v_list.success
      AND v_mrn_format_ok
      AND v_item IS NOT NULL
      AND (v_item ->> 'patient_mrn') = v_patient_mrn,
    format(
      'success=%s mrn=%s item_mrn=%s',
      v_list.success,
      v_patient_mrn,
      COALESCE(v_item ->> 'patient_mrn', '<null>')
    )
  );
END;
$$;

DO $$
DECLARE
  v_failures text;
BEGIN
  SELECT string_agg(test_name || ': ' || detail, E'\n')
  INTO v_failures
  FROM appointment_mrn_payload_results
  WHERE NOT passed;

  IF v_failures IS NOT NULL THEN
    RAISE EXCEPTION 'appointments_patient_mrn_payload_test failed: %', v_failures;
  END IF;
END;
$$;

ROLLBACK;
