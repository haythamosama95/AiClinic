-- V1-6 billing US1 RPC verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/billing_crud.sql

BEGIN;

CREATE TEMP TABLE billing_crud_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.test_appointment_same_day_slot(p_offset_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_day_start timestamptz;
BEGIN
  IF p_offset_hours < 1 OR p_offset_hours > 23 THEN
    RAISE EXCEPTION 'test_appointment_same_day_slot: offset must be 1..23, got %', p_offset_hours;
  END IF;
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  RETURN v_day_start + make_interval(hours => p_offset_hours);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.billing_crud_record(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_crud_results (test_name, passed, detail)
  VALUES (p_name, p_passed, p_detail);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_owner_jwt(
  p_user uuid,
  p_staff uuid,
  p_org uuid,
  p_branches text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user::text,
      'role', 'authenticated',
      'organization_id', p_org::text,
      'branch_ids', p_branches,
      'staff_member_id', p_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.seed_completed_visit(
  p_branch_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_owner_user uuid,
  p_offset_hours int
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_appt_id uuid := gen_random_uuid();
  v_visit_id uuid := gen_random_uuid();
  v_start timestamptz;
BEGIN
  v_start := pg_temp.test_appointment_same_day_slot(p_offset_hours);
  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES (
    v_appt_id,
    p_branch_id,
    p_patient_id,
    p_doctor_id,
    v_start,
    v_start + interval '30 minutes',
    'planned',
    'completed',
    p_owner_user,
    p_owner_user
  );

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES (
    v_visit_id,
    p_branch_id,
    v_appt_id,
    p_patient_id,
    p_doctor_id,
    current_date,
    'completed',
    p_owner_user,
    p_owner_user
  );

  RETURN v_visit_id;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_reception_jwt(
  p_user uuid,
  p_staff uuid,
  p_org uuid,
  p_branches text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user::text,
      'role', 'authenticated',
      'organization_id', p_org::text,
      'branch_ids', p_branches,
      'staff_member_id', p_staff::text,
      'staff_role', 'receptionist',
      'setup_required', false
    )::text,
    true
  );
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1600000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b1600000-0000-4000-8000-000000000101';
  v_doctor_user uuid := 'a1600000-0000-4000-8000-000000000103';
  v_doctor_staff uuid := 'b1600000-0000-4000-8000-000000000103';
  v_reception_user uuid := 'a1600000-0000-4000-8000-000000000102';
  v_reception_staff uuid := 'b1600000-0000-4000-8000-000000000102';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_branch_no_code uuid;
  v_patient_id uuid;
  v_appt_completed uuid;
  v_appt_in_progress uuid;
  v_visit_completed uuid;
  v_visit_in_progress uuid;
  v_invoice_id uuid;
  v_invoice_no_code uuid;
  v_item_id uuid;
  v_item2_id uuid;
  v_updated_at timestamptz;
  v_invoice_number text;
  v_invoice_number2 text;
  v_start timestamptz;
  v_detail public.rpc_result;
  v_list public.rpc_result;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.payments;
  DELETE FROM public.invoice_items;
  DELETE FROM public.invoices;
  DELETE FROM public.invoice_number_sequences;
  DELETE FROM public.visit_attachments;
  DELETE FROM public.soap_notes;
  DELETE FROM public.treatment_plans;
  DELETE FROM public.visits;
  DELETE FROM public.appointments;
  DELETE FROM public.patients;
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id NOT IN (v_bootstrap_staff);
  DELETE FROM public.audit_log;
  DELETE FROM public.branches;
  PERFORM auth_internal.delete_billing_dependents();
  DELETE FROM public.organizations;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_reception_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-crud-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_reception_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-crud-recep',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-crud-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Billing CRUD Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'No Code Branch', NULL, NULL, NULL, NULL);
  v_branch_no_code := (v_result.data ->> 'branch_id')::uuid;

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
  WHERE b.id IN (v_branch_main, v_branch_no_code);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Owner', 'owner', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_reception_staff, v_reception_user, 'Reception', 'receptionist', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_owner_staff, v_branch_no_code, false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_no_code, false, v_bootstrap_user, v_bootstrap_user),
    (v_reception_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_reception_staff, v_branch_no_code, false, v_bootstrap_user, v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', format('%s,%s', v_branch_main, v_branch_no_code),
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_branch_main, 'Billing Patient', '201600000101', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  v_start := pg_temp.test_appointment_same_day_slot(10);
  v_appt_in_progress := gen_random_uuid();
  v_visit_in_progress := gen_random_uuid();
  v_appt_completed := gen_random_uuid();
  v_visit_completed := gen_random_uuid();

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES
    (
      v_appt_in_progress, v_branch_main, v_patient_id, v_doctor_staff,
      v_start, v_start + interval '30 minutes', 'planned', 'checked_in', v_owner_user, v_owner_user
    ),
    (
      v_appt_completed, v_branch_main, v_patient_id, v_doctor_staff,
      v_start + interval '1 hour', v_start + interval '90 minutes', 'planned', 'completed', v_owner_user, v_owner_user
    );

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES
    (
      v_visit_in_progress, v_branch_main, v_appt_in_progress, v_patient_id, v_doctor_staff,
      current_date, 'in_progress', v_owner_user, v_owner_user
    ),
    (
      v_visit_completed, v_branch_main, v_appt_completed, v_patient_id, v_doctor_staff,
      current_date, 'completed', v_owner_user, v_owner_user
    );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  -- missing visit_id
  v_result := public.create_invoice_from_visit(NULL);
  PERFORM pg_temp.billing_crud_record(
    'create_invoice_missing_visit_id',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- in_progress visit rejected
  v_result := public.create_invoice_from_visit(v_visit_in_progress);
  PERFORM pg_temp.billing_crud_record(
    'create_invoice_rejects_in_progress_visit',
    NOT v_result.success AND v_result.error_code = 'VISIT_NOT_COMPLETED',
    COALESCE(v_result.error_code, '<null>')
  );

  -- completed visit succeeds
  v_result := public.create_invoice_from_visit(v_visit_completed);
  v_invoice_id := (v_result.data ->> 'invoice_id')::uuid;
  PERFORM pg_temp.billing_crud_record(
    'create_invoice_from_completed_visit',
    v_result.success AND v_invoice_id IS NOT NULL,
    COALESCE(v_result.error_code, 'ok')
  );

  -- duplicate active invoice rejected
  v_result := public.create_invoice_from_visit(v_visit_completed);
  PERFORM pg_temp.billing_crud_record(
    'create_invoice_rejects_duplicate_active',
    NOT v_result.success AND v_result.error_code = 'ACTIVE_INVOICE_EXISTS',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  -- draft item mutations
  v_result := public.add_invoice_item(v_invoice_id, v_updated_at, 'Consultation', 1, 100.00);
  v_item_id := (v_result.data ->> 'item_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  v_result := public.add_invoice_item(v_invoice_id, v_updated_at, 'Lab test', 2, 25.50);
  v_item2_id := (v_result.data ->> 'item_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  v_result := public.update_invoice_item(v_item_id, v_updated_at, 'Consultation extended', 1, 120.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  v_result := public.remove_invoice_item(v_item2_id, v_updated_at);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  PERFORM pg_temp.billing_crud_record(
    'draft_item_add_update_remove',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  -- issue without items on a fresh draft
  PERFORM set_config('role', 'postgres', true);
  v_visit_completed := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 12
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_completed);
  v_invoice_no_code := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_no_code;
  v_result := public.issue_invoice(v_invoice_no_code, v_updated_at);
  PERFORM pg_temp.billing_crud_record(
    'issue_rejects_no_items',
    NOT v_result.success AND v_result.error_code = 'NO_ITEMS',
    COALESCE(v_result.error_code, '<null>')
  );

  -- issue on branch without code
  PERFORM set_config('role', 'postgres', true);
  v_visit_completed := pg_temp.seed_completed_visit(
    v_branch_no_code, v_patient_id, v_doctor_staff, v_owner_user, 14
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_completed);
  v_invoice_no_code := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_no_code;
  v_result := public.add_invoice_item(v_invoice_no_code, v_updated_at, 'Service', 1, 50.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_no_code;
  v_result := public.issue_invoice(v_invoice_no_code, v_updated_at);
  PERFORM pg_temp.billing_crud_record(
    'issue_rejects_branch_code_missing',
    NOT v_result.success AND v_result.error_code = 'BRANCH_CODE_MISSING',
    COALESCE(v_result.error_code, '<null>')
  );

  -- issue success + monotonic numbering
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.issue_invoice(v_invoice_id, v_updated_at);
  v_invoice_number := v_result.data ->> 'invoice_number';
  PERFORM pg_temp.billing_crud_record(
    'issue_invoice_success',
    v_result.success
      AND v_invoice_number LIKE 'INV-MAIN-%'
      AND EXISTS (
        SELECT 1 FROM public.invoices i
        WHERE i.id = v_invoice_id AND i.status = 'issued' AND i.invoice_number = v_invoice_number
      ),
    COALESCE(v_invoice_number, v_result.error_code)
  );

  -- issued invoice rejects item mutation
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.add_invoice_item(v_invoice_id, v_updated_at, 'Late item', 1, 10.00);
  PERFORM pg_temp.billing_crud_record(
    'issued_invoice_rejects_item_add',
    NOT v_result.success AND v_result.error_code = 'INVOICE_NOT_IN_DRAFT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- second issued invoice increments sequence
  PERFORM set_config('role', 'postgres', true);
  v_visit_completed := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 13
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_completed);
  v_invoice_id := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.add_invoice_item(v_invoice_id, v_updated_at, 'Follow-up', 1, 80.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.issue_invoice(v_invoice_id, v_updated_at);
  v_invoice_number2 := v_result.data ->> 'invoice_number';
  PERFORM pg_temp.billing_crud_record(
    'invoice_number_monotonic_per_branch',
    v_result.success
      AND v_invoice_number2 LIKE 'INV-MAIN-%'
      AND lpad(split_part(v_invoice_number2, '-', 3), 6, '0')
          > lpad(split_part(v_invoice_number, '-', 3), 6, '0'),
    format('%s -> %s', v_invoice_number, v_invoice_number2)
  );

  v_detail := public.get_invoice_detail((SELECT id FROM public.invoices WHERE invoice_number = v_invoice_number2));
  v_list := public.list_invoices(jsonb_build_object('visit_id', v_visit_completed::text), 10, 0);
  PERFORM pg_temp.billing_crud_record(
    'get_invoice_detail_and_list_queries',
    v_detail.success AND v_list.success AND jsonb_array_length(v_list.data -> 'items') >= 1,
    COALESCE(v_detail.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_fail billing_crud_results%ROWTYPE;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  FOR v_fail IN
    SELECT * FROM billing_crud_results WHERE NOT passed
  LOOP
    RAISE EXCEPTION 'Billing CRUD test failed: % — %', v_fail.test_name, v_fail.detail;
  END LOOP;
END;
$$;

COMMIT;

DO $$ BEGIN PERFORM set_config('role', 'postgres', true); END; $$;
SELECT test_name, passed, detail
FROM billing_crud_results
ORDER BY test_name;
