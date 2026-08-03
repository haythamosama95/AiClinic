-- Invoice RPC payloads include patient MRN (016 US5).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/invoices_patient_mrn_payload_test.sql

BEGIN;

CREATE TEMP TABLE invoice_mrn_payload_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1000000-0000-4000-8000-000000000301';
  v_owner_staff uuid := 'b1000000-0000-4000-8000-000000000301';
  v_doctor_user uuid := 'a1000000-0000-4000-8000-000000000302';
  v_doctor_staff uuid := 'b1000000-0000-4000-8000-000000000302';
  v_result public.rpc_result;
  v_detail public.rpc_result;
  v_list public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_id uuid;
  v_patient_mrn text;
  v_visit_completed uuid;
  v_invoice_id uuid;
  v_items jsonb;
  v_item jsonb;
  v_patient jsonb;
  v_mrn_format_ok boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inv-mrn-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inv-mrn-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Invoice MRN Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Invoice Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Invoice Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
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

  v_result := public.create_patient(v_branch_main, 'Invoice MRN Patient', '201700000101', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_patient_mrn := v_result.data ->> 'mrn';

  v_visit_completed := gen_random_uuid();
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES (
    gen_random_uuid(),
    v_branch_main,
    v_patient_id,
    v_doctor_staff,
    date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '10 hours',
    date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '10 hours 30 minutes',
    'planned',
    'completed',
    v_owner_user,
    v_owner_user
  );

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  SELECT
    v_visit_completed,
    v_branch_main,
    a.id,
    v_patient_id,
    v_doctor_staff,
    current_date,
    'completed',
    v_owner_user,
    v_owner_user
  FROM public.appointments a
  WHERE a.patient_id = v_patient_id
  ORDER BY a.created_at DESC
  LIMIT 1;

  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_invoice_from_visit(v_visit_completed);
  v_invoice_id := (v_result.data ->> 'invoice_id')::uuid;

  v_mrn_format_ok := v_patient_mrn ~ '^MRN-\d{6,}$';

  PERFORM set_config('role', 'postgres', true);

  -- list_invoices includes patient_mrn on each row.
  PERFORM set_config('role', 'authenticated', true);
  v_list := public.list_invoices(jsonb_build_object('patient_id', v_patient_id::text), 50, 0);
  v_items := v_list.data -> 'items';
  v_item := (
    SELECT elem
    FROM jsonb_array_elements(v_items) AS elem
    WHERE (elem ->> 'id')::uuid = v_invoice_id
    LIMIT 1
  );

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO invoice_mrn_payload_results VALUES (
    'list_invoices_includes_patient_mrn',
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

  -- get_invoice_detail patient sub-object includes mrn and patient_mrn.
  PERFORM set_config('role', 'authenticated', true);
  v_detail := public.get_invoice_detail(v_invoice_id);
  v_patient := v_detail.data -> 'patient';

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO invoice_mrn_payload_results VALUES (
    'get_invoice_detail_patient_includes_mrn',
    v_detail.success
      AND v_mrn_format_ok
      AND v_patient IS NOT NULL
      AND (v_patient ->> 'mrn') = v_patient_mrn
      AND (v_patient ->> 'patient_mrn') = v_patient_mrn,
    format(
      'success=%s mrn=%s patient.mrn=%s patient.patient_mrn=%s',
      v_detail.success,
      v_patient_mrn,
      COALESCE(v_patient ->> 'mrn', '<null>'),
      COALESCE(v_patient ->> 'patient_mrn', '<null>')
    )
  );

  INSERT INTO invoice_mrn_payload_results VALUES (
    'get_invoice_detail_patient_includes_phone',
    v_detail.success
      AND v_patient IS NOT NULL
      AND (v_patient ->> 'phone') = '201700000101',
    format(
      'success=%s patient.phone=%s',
      v_detail.success,
      COALESCE(v_patient ->> 'phone', '<null>')
    )
  );

  -- list_patient_invoices includes patient_mrn (delegates to list_invoices).
  PERFORM set_config('role', 'authenticated', true);
  v_list := public.list_patient_invoices(v_patient_id, 50, 0);
  v_items := v_list.data -> 'items';
  v_item := (
    SELECT elem
    FROM jsonb_array_elements(v_items) AS elem
    WHERE (elem ->> 'id')::uuid = v_invoice_id
    LIMIT 1
  );

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO invoice_mrn_payload_results VALUES (
    'list_patient_invoices_includes_patient_mrn',
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
  FROM invoice_mrn_payload_results
  WHERE NOT passed;

  IF v_failures IS NOT NULL THEN
    RAISE EXCEPTION 'invoices_patient_mrn_payload_test failed: %', v_failures;
  END IF;
END;
$$;

ROLLBACK;
