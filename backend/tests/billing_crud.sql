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

CREATE OR REPLACE FUNCTION pg_temp.set_doctor_jwt(
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
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_administrator_jwt(
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
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_lab_staff_jwt(
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
      'staff_role', 'lab_staff',
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
  v_admin_user uuid := 'a1600000-0000-4000-8000-000000000104';
  v_admin_staff uuid := 'b1600000-0000-4000-8000-000000000104';
  v_lab_user uuid := 'a1600000-0000-4000-8000-000000000105';
  v_lab_staff uuid := 'b1600000-0000-4000-8000-000000000105';
  v_draft_discard uuid;
  v_stale_updated_at timestamptz;
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
  v_payment_id uuid;
  v_invoice_pay uuid;
  v_invoice_for_payment uuid;
  v_visit_pay uuid;
  v_status public.invoice_status;
  v_balance numeric(14, 2);
  v_audit_count int;
  v_allow_partial boolean;
  v_line_discount_amount numeric(14, 2);
  v_invoice_discount_amount numeric(14, 2);
  v_prior_kind public.discount_kind;
  v_prior_value numeric(14, 2);
  v_subtotal numeric(14, 2);
  v_trigger_blocked boolean;
  v_provider_id uuid;
  v_provider_other_org uuid;
  v_org_other uuid;
  v_list_providers public.rpc_result;
  v_provider_count int;
  v_detail_data jsonb;
  v_list_item_count int;
  v_first_list_id uuid;
  v_second_list_id uuid;
  v_side_visit uuid;
  v_side_invoice uuid;
  v_visit_void uuid;
  v_invoice_void_issued uuid;
  v_invoice_void_partial uuid;
  v_visit_void_perm uuid;
  v_invoice_void_perm uuid;
  v_visit_paid_void uuid;
  v_invoice_paid_void uuid;
  v_void_reason text;
  v_clamp_visit uuid;
  v_clamp_invoice uuid;
  v_clamp_item uuid;
  v_insurance_covered numeric(14, 2);
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_reception_user, v_doctor_user, v_admin_user, v_lab_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-crud-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_reception_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-crud-recep',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-crud-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_admin_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-crud-admin',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-crud-lab',
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

  PERFORM set_config('role', 'postgres', true);
  SELECT obs.allow_partial_payments
  INTO v_allow_partial
  FROM public.organization_billing_settings obs
  WHERE obs.organization_id = v_org_id;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.billing_crud_record(
    'billing_settings_default_false_on_org_create',
    coalesce(v_allow_partial, true) = false,
    coalesce(v_allow_partial::text, 'null')
  );

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
    (v_reception_staff, v_reception_user, 'Reception', 'receptionist', false, v_bootstrap_user, v_bootstrap_user),
    (v_admin_staff, v_admin_user, 'Administrator', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Lab', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_owner_staff, v_branch_no_code, false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_no_code, false, v_bootstrap_user, v_bootstrap_user),
    (v_reception_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_reception_staff, v_branch_no_code, false, v_bootstrap_user, v_bootstrap_user),
    (v_admin_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user);

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

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'invoice.create_from_visit'
    AND al.record_id = v_invoice_id;
  PERFORM pg_temp.billing_crud_record(
    'invoice_create_from_visit_audited',
    v_audit_count = 1,
    v_audit_count::text
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

  v_result := public.add_invoice_item(v_invoice_id, v_updated_at, repeat('x', 501), 1, 10.00);
  PERFORM pg_temp.billing_crud_record(
    'add_invoice_item_rejects_long_description',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_message, v_result.error_code)
  );

  v_result := public.update_invoice_item(v_item_id, v_updated_at, 'Consultation extended', 1, 120.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  v_result := public.update_invoice_item(v_item_id, v_updated_at, repeat('y', 501), 1, 120.00);
  PERFORM pg_temp.billing_crud_record(
    'update_invoice_item_rejects_long_description',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_message, v_result.error_code)
  );

  v_result := public.remove_invoice_item(v_item2_id, v_updated_at);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  PERFORM pg_temp.billing_crud_record(
    'draft_item_add_update_remove',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  -- US3: line discount valid (10% on 120.00 line)
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'percentage', 10.00);
  SELECT line_discount_amount, line_total
  INTO v_line_discount_amount, v_subtotal
  FROM public.invoice_items
  WHERE id = v_item_id;
  SELECT subtotal INTO v_invoice_discount_amount FROM public.invoices WHERE id = v_invoice_id;
  PERFORM pg_temp.billing_crud_record(
    'line_discount_percentage_valid',
    v_result.success
      AND v_line_discount_amount = 12.00
      AND v_subtotal = 108.00
      AND v_invoice_discount_amount = 108.00,
    format('discount=%s line_total=%s subtotal=%s', v_line_discount_amount, v_subtotal, v_invoice_discount_amount)
  );

  -- US3: line discount invalid bounds
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'percentage', 150.00);
  PERFORM pg_temp.billing_crud_record(
    'line_discount_percentage_out_of_bounds',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'fixed', 200.00);
  PERFORM pg_temp.billing_crud_record(
    'line_discount_fixed_exceeds_line_subtotal',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- US3: invoice discount rejected while line discount active
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_invoice_discount(v_invoice_id, v_updated_at, 'fixed', 5.00);
  PERFORM pg_temp.billing_crud_record(
    'invoice_discount_rejected_when_line_discount_active',
    NOT v_result.success AND v_result.error_code = 'DISCOUNT_SCOPE_CONFLICT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- US3: trigger blocks direct SQL that would violate mutual exclusion
  v_trigger_blocked := false;
  BEGIN
    PERFORM set_config('role', 'postgres', true);
    UPDATE public.invoices
    SET discount_amount = 5.00, discount_kind = 'fixed', discount_value = 5.00
    WHERE id = v_invoice_id;
    PERFORM set_config('role', 'authenticated', true);
  EXCEPTION
    WHEN OTHERS THEN
      v_trigger_blocked := SQLERRM = 'discount_scope_conflict';
      PERFORM set_config('role', 'authenticated', true);
  END;
  PERFORM pg_temp.billing_crud_record(
    'trigger_blocks_concurrent_discount_scope_violation',
    v_trigger_blocked,
    CASE WHEN v_trigger_blocked THEN 'blocked' ELSE 'not blocked' END
  );

  -- US3: clearing line discount re-enables invoice discount
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, NULL, NULL);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_invoice_discount(v_invoice_id, v_updated_at, 'fixed', 10.00);
  SELECT discount_amount INTO v_invoice_discount_amount FROM public.invoices WHERE id = v_invoice_id;
  PERFORM pg_temp.billing_crud_record(
    'invoice_discount_valid_after_clearing_line_scope',
    v_result.success AND v_invoice_discount_amount = 10.00,
    COALESCE(v_invoice_discount_amount::text, v_result.error_code)
  );

  -- US3: invoice discount invalid bounds
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_invoice_discount(v_invoice_id, v_updated_at, 'percentage', 150.00);
  PERFORM pg_temp.billing_crud_record(
    'invoice_discount_percentage_out_of_bounds',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_invoice_discount(v_invoice_id, v_updated_at, 'fixed', 500.00);
  PERFORM pg_temp.billing_crud_record(
    'invoice_discount_fixed_exceeds_subtotal',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- US3: line discount rejected while invoice discount active
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'percentage', 5.00);
  PERFORM pg_temp.billing_crud_record(
    'line_discount_rejected_when_invoice_discount_active',
    NOT v_result.success AND v_result.error_code = 'DISCOUNT_SCOPE_CONFLICT',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_invoice_discount(v_invoice_id, v_updated_at, 'percentage', 0.00);
  SELECT discount_kind, discount_value, discount_amount
  INTO v_prior_kind, v_prior_value, v_invoice_discount_amount
  FROM public.invoices
  WHERE id = v_invoice_id;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'fixed', 5.00);
  PERFORM pg_temp.billing_crud_record(
    'invoice_discount_zero_percentage_clears_and_allows_line_discount',
    v_result.success
      AND v_prior_kind IS NULL
      AND v_prior_value IS NULL
      AND v_invoice_discount_amount = 0.00,
    format('kind=%s amount=%s line_ok=%s', v_prior_kind, v_invoice_discount_amount, v_result.success)
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, NULL, NULL);
  PERFORM pg_temp.billing_crud_record(
    'apply_line_discount_clear_noop_without_line_discount',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  -- US3: clearing invoice discount re-enables line discount
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_invoice_discount(v_invoice_id, v_updated_at, NULL, NULL);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'fixed', 15.00);
  SELECT line_discount_amount INTO v_line_discount_amount FROM public.invoice_items WHERE id = v_item_id;
  PERFORM pg_temp.billing_crud_record(
    'line_discount_valid_after_clearing_invoice_scope',
    v_result.success AND v_line_discount_amount = 15.00,
    COALESCE(v_line_discount_amount::text, v_result.error_code)
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'invoice.discount.apply'
    AND al.new_data_json ->> 'scope' = 'line'
    AND al.record_id = v_item_id;
  PERFORM pg_temp.billing_crud_record(
    'line_discount_apply_audited',
    v_audit_count >= 1,
    v_audit_count::text
  );

  -- US3: doctor without discount permission denied
  PERFORM pg_temp.set_doctor_jwt(
    v_doctor_user,
    v_doctor_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'percentage', 5.00);
  PERFORM pg_temp.billing_crud_record(
    'discount_apply_permission_denied_without_key',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  -- US4: insurance provider upsert and set coverage
  v_result := public.insurance_provider_upsert(NULL, 'Acme Insurance', 'claims@acme.test', true);
  v_provider_id := (v_result.data ->> 'provider_id')::uuid;

  -- Critical #1: lowering unit price below existing line discount must not abort
  PERFORM set_config('role', 'postgres', true);
  v_clamp_visit := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 21
  );
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.create_invoice_from_visit(v_clamp_visit);
  v_clamp_invoice := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.add_invoice_item(v_clamp_invoice, v_updated_at, 'Discounted service', 1, 100.00);
  v_clamp_item := (v_result.data ->> 'item_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.apply_line_discount(v_clamp_item, v_updated_at, 'fixed', 50.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.update_invoice_item(v_clamp_item, v_updated_at, 'Discounted service reduced', 1, 10.00);
  SELECT line_discount_amount, line_total
  INTO v_line_discount_amount, v_subtotal
  FROM public.invoice_items
  WHERE id = v_clamp_item;
  PERFORM pg_temp.billing_crud_record(
    'update_item_clamps_line_discount_when_subtotal_drops',
    v_result.success
      AND v_line_discount_amount = 10.00
      AND v_subtotal = 0.00,
    format('discount=%s line_total=%s', v_line_discount_amount, v_subtotal)
  );

  -- Critical #2: item removal clamps discount and insurance when subtotal drops to zero
  PERFORM set_config('role', 'postgres', true);
  v_clamp_visit := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 22
  );
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.create_invoice_from_visit(v_clamp_visit);
  v_clamp_invoice := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.add_invoice_item(v_clamp_invoice, v_updated_at, 'Single service', 1, 200.00);
  v_clamp_item := (v_result.data ->> 'item_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.apply_invoice_discount(v_clamp_invoice, v_updated_at, 'fixed', 50.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.set_insurance_coverage(v_clamp_invoice, v_updated_at, v_provider_id, 100.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.remove_invoice_item(v_clamp_item, v_updated_at);
  SELECT discount_amount, insurance_covered_amount, subtotal
  INTO v_invoice_discount_amount, v_insurance_covered, v_subtotal
  FROM public.invoices
  WHERE id = v_clamp_invoice;
  PERFORM pg_temp.billing_crud_record(
    'remove_item_clamps_discount_and_insurance_when_subtotal_drops',
    v_result.success
      AND v_subtotal = 0.00
      AND v_invoice_discount_amount = 0.00
      AND v_insurance_covered = 0.00,
    format('subtotal=%s discount=%s insurance=%s', v_subtotal, v_invoice_discount_amount, v_insurance_covered)
  );

  -- Critical #3: apply_invoice_discount clamps insurance when net total shrinks
  PERFORM set_config('role', 'postgres', true);
  v_clamp_visit := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 23
  );
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.create_invoice_from_visit(v_clamp_visit);
  v_clamp_invoice := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.add_invoice_item(v_clamp_invoice, v_updated_at, 'Coverage test', 1, 200.00);
  v_clamp_item := (v_result.data ->> 'item_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.set_insurance_coverage(v_clamp_invoice, v_updated_at, v_provider_id, 150.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.apply_invoice_discount(v_clamp_invoice, v_updated_at, 'percentage', 50.00);
  SELECT discount_amount, insurance_covered_amount
  INTO v_invoice_discount_amount, v_insurance_covered
  FROM public.invoices
  WHERE id = v_clamp_invoice;
  PERFORM pg_temp.billing_crud_record(
    'apply_invoice_discount_clamps_insurance_covered_amount',
    v_result.success
      AND v_invoice_discount_amount = 100.00
      AND v_insurance_covered = 100.00,
    format('discount=%s insurance=%s', v_invoice_discount_amount, v_insurance_covered)
  );

  -- Critical #3: apply_line_discount clamps insurance when subtotal shrinks
  PERFORM set_config('role', 'postgres', true);
  v_clamp_visit := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 20
  );
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.create_invoice_from_visit(v_clamp_visit);
  v_clamp_invoice := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.add_invoice_item(v_clamp_invoice, v_updated_at, 'Line discount test', 1, 200.00);
  v_clamp_item := (v_result.data ->> 'item_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.set_insurance_coverage(v_clamp_invoice, v_updated_at, v_provider_id, 150.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_clamp_invoice;
  v_result := public.apply_line_discount(v_clamp_item, v_updated_at, 'percentage', 50.00);
  SELECT insurance_covered_amount, subtotal
  INTO v_insurance_covered, v_subtotal
  FROM public.invoices
  WHERE id = v_clamp_invoice;
  PERFORM pg_temp.billing_crud_record(
    'apply_line_discount_clamps_insurance_covered_amount',
    v_result.success
      AND v_subtotal = 100.00
      AND v_insurance_covered = 100.00,
    format('subtotal=%s insurance=%s', v_subtotal, v_insurance_covered)
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.set_insurance_coverage(v_invoice_id, v_updated_at, v_provider_id, 50.00);
  v_detail := public.get_invoice_detail(v_invoice_id);
  v_balance := (v_detail.data -> 'invoice' ->> 'balance')::numeric(14, 2);
  PERFORM pg_temp.billing_crud_record(
    'insurance_coverage_valid_updates_balance',
    v_result.success AND v_balance = 55.00,
    format('balance=%s', v_balance)
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.set_insurance_coverage(v_invoice_id, v_updated_at, v_provider_id, -1.00);
  PERFORM pg_temp.billing_crud_record(
    'insurance_coverage_rejects_negative_amount',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.set_insurance_coverage(v_invoice_id, v_updated_at, v_provider_id, 200.00);
  PERFORM pg_temp.billing_crud_record(
    'insurance_coverage_rejects_amount_above_net_total',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  v_result := public.insurance_provider_deactivate(v_provider_id);
  v_list_providers := public.list_insurance_providers(true);
  SELECT jsonb_array_length(COALESCE(v_list_providers.data -> 'providers', '[]'::jsonb))
  INTO v_provider_count;
  PERFORM pg_temp.billing_crud_record(
    'deactivated_provider_hidden_from_active_selector',
    v_result.success AND v_provider_count = 0,
    v_provider_count::text
  );

  v_list_providers := public.list_insurance_providers(false);
  SELECT jsonb_array_length(COALESCE(v_list_providers.data -> 'providers', '[]'::jsonb))
  INTO v_provider_count;
  v_detail := public.get_invoice_detail(v_invoice_id);
  v_detail_data := v_detail.data;
  PERFORM pg_temp.billing_crud_record(
    'deactivated_provider_preserved_in_history_and_detail',
    v_provider_count >= 1
      AND v_detail.success
      AND (v_detail_data -> 'insurance_provider' ->> 'name') = 'Acme Insurance'
      AND (v_detail_data -> 'invoice' ->> 'insurance_covered_amount')::numeric = 50.00,
    COALESCE(v_detail_data -> 'insurance_provider' ->> 'name', '<null>')
  );

  PERFORM set_config('role', 'postgres', true);
  v_org_other := gen_random_uuid();
  v_provider_other_org := gen_random_uuid();
  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_org_other, 'Other Billing Org', v_bootstrap_user, v_bootstrap_user);
  INSERT INTO public.insurance_providers (id, organization_id, name, created_by, updated_by)
  VALUES (v_provider_other_org, v_org_other, 'Foreign Insurer', v_bootstrap_user, v_bootstrap_user);
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.set_insurance_coverage(v_invoice_id, v_updated_at, v_provider_other_org, 10.00);
  PERFORM pg_temp.billing_crud_record(
    'insurance_coverage_rejects_cross_org_provider',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'invoice.insurance.set'
    AND al.record_id = v_invoice_id;
  PERFORM pg_temp.billing_crud_record(
    'insurance_coverage_set_audited',
    v_audit_count >= 1,
    v_audit_count::text
  );

  -- restore draft totals before issue/payment scenarios
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.set_insurance_coverage(v_invoice_id, v_updated_at, NULL, 0);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, NULL, NULL);

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

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'invoice.issue'
    AND al.record_id = v_invoice_id;
  PERFORM pg_temp.billing_crud_record(
    'invoice_issue_audited',
    v_audit_count >= 1,
    v_audit_count::text
  );

  v_invoice_for_payment := v_invoice_id;

  -- issued invoice rejects item mutation
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.add_invoice_item(v_invoice_id, v_updated_at, 'Late item', 1, 10.00);
  PERFORM pg_temp.billing_crud_record(
    'issued_invoice_rejects_item_add',
    NOT v_result.success AND v_result.error_code = 'INVOICE_NOT_IN_DRAFT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- US3: issued invoice rejects discount mutation
  SELECT ii.id, i.updated_at
  INTO v_item_id, v_updated_at
  FROM public.invoice_items ii
  JOIN public.invoices i ON i.id = ii.invoice_id
  WHERE i.id = v_invoice_id
    AND ii.is_deleted = false
  LIMIT 1;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'percentage', 5.00);
  PERFORM pg_temp.billing_crud_record(
    'issued_invoice_rejects_line_discount',
    NOT v_result.success AND v_result.error_code = 'INVOICE_NOT_IN_DRAFT',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.apply_invoice_discount(v_invoice_id, v_updated_at, 'fixed', 5.00);
  PERFORM pg_temp.billing_crud_record(
    'issued_invoice_rejects_invoice_discount',
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

  -- US2: partial patient-tender rejected when allow_partial_payments is off (default)
  v_result := public.record_payment(v_invoice_for_payment, 'cash', 50.00, NULL, NULL);
  PERFORM pg_temp.billing_crud_record(
    'partial_patient_payment_rejected_when_setting_off',
    NOT v_result.success AND v_result.error_code = 'PARTIAL_PAYMENTS_DISABLED',
    COALESCE(v_result.error_code, '<null>')
  );

  -- US2: full payment marks invoice paid
  v_result := public.record_payment(v_invoice_for_payment, 'cash', 120.00, 'RCPT-1', 'Full payment');
  v_payment_id := (v_result.data ->> 'payment_id')::uuid;
  SELECT status INTO v_status FROM public.invoices WHERE id = v_invoice_for_payment;
  v_detail := public.get_invoice_detail(v_invoice_for_payment);
  v_balance := (v_detail.data -> 'invoice' ->> 'balance')::numeric;
  PERFORM pg_temp.billing_crud_record(
    'full_payment_marks_paid',
    v_result.success
      AND v_payment_id IS NOT NULL
      AND v_status = 'paid'
      AND v_balance = 0.00,
    format('status=%s balance=%s', v_status, v_balance)
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'payment.record'
    AND al.record_id = v_payment_id
    AND al.new_data_json ->> 'prior_status' = 'issued'
    AND al.new_data_json ->> 'new_status' = 'paid';
  PERFORM pg_temp.billing_crud_record(
    'payment_status_transition_audited',
    v_audit_count = 1,
    v_audit_count::text
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'payment.record'
    AND al.record_id = v_payment_id
    AND al.new_data_json ->> 'reference' = 'RCPT-1'
    AND al.new_data_json ->> 'note' = 'Full payment';
  PERFORM pg_temp.billing_crud_record(
    'record_payment_audit_includes_reference_and_note',
    v_audit_count = 1,
    v_audit_count::text
  );

  v_detail := public.get_invoice_detail(v_invoice_for_payment);
  PERFORM pg_temp.billing_crud_record(
    'get_invoice_detail_payment_recorded_by_includes_display_name',
    v_detail.success
      AND jsonb_typeof(v_detail.data -> 'payments' -> 0 -> 'recorded_by') = 'object'
      AND (v_detail.data -> 'payments' -> 0 -> 'recorded_by' ->> 'id') = v_reception_staff::text
      AND (v_detail.data -> 'payments' -> 0 -> 'recorded_by' ->> 'display_name') = 'Reception',
    COALESCE(v_detail.data -> 'payments' -> 0 -> 'recorded_by' ->> 'display_name', '<null>')
  );

  -- US2: partial payments with setting ON
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.organization_billing_settings
  SET allow_partial_payments = true
  WHERE organization_id = v_org_id;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  PERFORM set_config('role', 'postgres', true);
  v_visit_pay := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 15
  );
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.create_invoice_from_visit(v_visit_pay);
  v_invoice_pay := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_pay;
  v_result := public.add_invoice_item(v_invoice_pay, v_updated_at, 'Partial test', 1, 100.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_pay;
  v_result := public.issue_invoice(v_invoice_pay, v_updated_at);

  v_result := public.record_payment(v_invoice_pay, 'card', 40.00, NULL, NULL);
  SELECT status INTO v_status FROM public.invoices WHERE id = v_invoice_pay;
  v_detail := public.get_invoice_detail(v_invoice_pay);
  v_balance := (v_detail.data -> 'invoice' ->> 'balance')::numeric;
  PERFORM pg_temp.billing_crud_record(
    'partial_payment_moves_to_partially_paid_when_setting_on',
    v_result.success AND v_status = 'partially_paid' AND v_balance = 60.00,
    format('status=%s balance=%s', v_status, v_balance)
  );

  -- US2: insurance_settlement partial allowed even when setting OFF
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.organization_billing_settings
  SET allow_partial_payments = false
  WHERE organization_id = v_org_id;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  PERFORM set_config('role', 'postgres', true);
  v_visit_pay := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 16
  );
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.create_invoice_from_visit(v_visit_pay);
  v_invoice_pay := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_pay;
  v_result := public.add_invoice_item(v_invoice_pay, v_updated_at, 'Insurance split', 1, 100.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_pay;
  v_result := public.issue_invoice(v_invoice_pay, v_updated_at);

  v_result := public.record_payment(v_invoice_pay, 'insurance_settlement', 30.00, 'CLM-1', NULL);
  SELECT status INTO v_status FROM public.invoices WHERE id = v_invoice_pay;
  PERFORM pg_temp.billing_crud_record(
    'insurance_settlement_partial_allowed_when_setting_off',
    v_result.success AND v_status = 'partially_paid',
    COALESCE(v_result.error_code, v_status::text)
  );

  -- US2: overpayment rejected
  v_result := public.record_payment(v_invoice_pay, 'cash', 80.00, NULL, NULL);
  PERFORM pg_temp.billing_crud_record(
    'overpayment_rejected',
    NOT v_result.success AND v_result.error_code = 'OVERPAYMENT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- US2: refund moves status back from paid
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.record_refund(v_invoice_for_payment, 'cash', 50.00, 'Patient overpaid');
  SELECT status INTO v_status FROM public.invoices WHERE id = v_invoice_for_payment;
  v_detail := public.get_invoice_detail(v_invoice_for_payment);
  v_balance := (v_detail.data -> 'invoice' ->> 'balance')::numeric;
  PERFORM pg_temp.billing_crud_record(
    'refund_moves_status_back_from_paid',
    v_result.success AND v_status = 'partially_paid' AND v_balance = 50.00,
    format('status=%s balance=%s', v_status, v_balance)
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'payment.refund'
    AND al.new_data_json ->> 'invoice_id' = v_invoice_for_payment::text
    AND al.new_data_json ->> 'prior_status' = 'paid';
  PERFORM pg_temp.billing_crud_record(
    'refund_status_transition_audited',
    v_audit_count >= 1,
    v_audit_count::text
  );

  -- US8: billing settings read/update permissions and audit
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  v_result := public.get_billing_settings();
  PERFORM pg_temp.billing_crud_record(
    'owner_can_read_billing_settings',
    v_result.success
      AND coalesce((v_result.data ->> 'allow_partial_payments')::boolean, true) = false,
    COALESCE(v_result.error_code, v_result.data::text)
  );

  v_result := public.update_billing_settings(true);
  PERFORM pg_temp.billing_crud_record(
    'owner_can_update_billing_settings',
    v_result.success
      AND coalesce((v_result.data ->> 'allow_partial_payments')::boolean, false) = true,
    COALESCE(v_result.error_code, v_result.data::text)
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'billing_settings.update'
    AND al.organization_id = v_org_id
    AND al.old_data_json ->> 'allow_partial_payments' = 'false'
    AND al.new_data_json ->> 'allow_partial_payments' = 'true';
  PERFORM pg_temp.billing_crud_record(
    'billing_settings_update_audited',
    v_audit_count >= 1,
    v_audit_count::text
  );

  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  v_result := public.get_billing_settings();
  PERFORM pg_temp.billing_crud_record(
    'receptionist_can_read_billing_settings',
    v_result.success
      AND coalesce((v_result.data ->> 'allow_partial_payments')::boolean, false) = true,
    COALESCE(v_result.error_code, v_result.data::text)
  );

  v_result := public.update_billing_settings(false);
  PERFORM pg_temp.billing_crud_record(
    'receptionist_billing_settings_update_denied',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_doctor_jwt(
    v_doctor_user,
    v_doctor_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  v_result := public.get_billing_settings();
  PERFORM pg_temp.billing_crud_record(
    'doctor_billing_settings_read_denied',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_lab_staff_jwt(
    v_lab_user,
    v_lab_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  v_result := public.get_billing_settings();
  PERFORM pg_temp.billing_crud_record(
    'lab_staff_billing_settings_read_denied',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_administrator_jwt(
    v_admin_user,
    v_admin_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  v_result := public.update_billing_settings(false);
  PERFORM pg_temp.billing_crud_record(
    'administrator_can_update_billing_settings',
    v_result.success
      AND coalesce((v_result.data ->> 'allow_partial_payments')::boolean, true) = false,
    COALESCE(v_result.error_code, v_result.data::text)
  );

  -- discard_draft_invoice on fresh draft
  PERFORM set_config('role', 'postgres', true);
  v_visit_completed := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 17
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_completed);
  v_draft_discard := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_draft_discard;
  v_result := public.discard_draft_invoice(v_draft_discard, v_updated_at);
  PERFORM pg_temp.billing_crud_record(
    'discard_draft_invoice_success',
    v_result.success
      AND NOT EXISTS (
        SELECT 1 FROM public.invoices i
        WHERE i.id = v_draft_discard AND i.is_deleted = false
      ),
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'invoice.discard_draft'
    AND al.record_id = v_draft_discard;
  PERFORM pg_temp.billing_crud_record(
    'discard_draft_invoice_audited',
    v_audit_count >= 1,
    v_audit_count::text
  );

  v_result := public.discard_draft_invoice(v_invoice_for_payment, now());
  PERFORM pg_temp.billing_crud_record(
    'discard_draft_rejects_issued_invoice',
    NOT v_result.success AND v_result.error_code = 'INVOICE_NOT_IN_DRAFT',
    COALESCE(v_result.error_code, '<null>')
  );

  -- STALE_INVOICE optimistic concurrency
  PERFORM set_config('role', 'postgres', true);
  v_visit_completed := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 18
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_completed);
  v_draft_discard := (v_result.data ->> 'invoice_id')::uuid;
  v_stale_updated_at := '2000-01-01 00:00:00+00'::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.invoices
  SET updated_at = '2099-01-01 00:00:00+00'::timestamptz
  WHERE id = v_draft_discard;
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.add_invoice_item(v_draft_discard, v_stale_updated_at, 'Stale test', 1, 10.00);
  PERFORM pg_temp.billing_crud_record(
    'stale_invoice_rejects_item_add',
    NOT v_result.success AND v_result.error_code = 'STALE_INVOICE',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_draft_discard;
  v_result := public.add_invoice_item(v_draft_discard, v_updated_at, 'Item', 1, 10.00);
  v_stale_updated_at := '2000-01-02 00:00:00+00'::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.invoices
  SET updated_at = '2099-01-02 00:00:00+00'::timestamptz
  WHERE id = v_draft_discard;
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.issue_invoice(v_draft_discard, v_stale_updated_at);
  PERFORM pg_temp.billing_crud_record(
    'stale_invoice_rejects_issue',
    NOT v_result.success AND v_result.error_code = 'STALE_INVOICE',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_draft_discard;
  v_result := public.add_invoice_item(v_draft_discard, v_updated_at, 'Discount line', 1, 50.00);
  v_item_id := (v_result.data ->> 'item_id')::uuid;
  v_stale_updated_at := '2000-01-03 00:00:00+00'::timestamptz;
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.invoices
  SET updated_at = '2099-01-03 00:00:00+00'::timestamptz
  WHERE id = v_draft_discard;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.apply_line_discount(v_item_id, v_stale_updated_at, 'percentage', 5.00);
  PERFORM pg_temp.billing_crud_record(
    'stale_invoice_rejects_line_discount',
    NOT v_result.success AND v_result.error_code = 'STALE_INVOICE',
    COALESCE(v_result.error_code, '<null>')
  );

  -- discount boundary: 100% line discount and fixed at exact subtotal
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_draft_discard;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'percentage', 100.00);
  SELECT line_discount_amount, line_total
  INTO v_line_discount_amount, v_subtotal
  FROM public.invoice_items
  WHERE id = v_item_id;
  PERFORM pg_temp.billing_crud_record(
    'line_discount_percentage_100_valid',
    v_result.success AND v_line_discount_amount = 50.00 AND v_subtotal = 0.00,
    format('discount=%s line_total=%s', v_line_discount_amount, v_subtotal)
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_draft_discard;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, NULL, NULL);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_draft_discard;
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'fixed', 50.00);
  SELECT line_discount_amount INTO v_line_discount_amount FROM public.invoice_items WHERE id = v_item_id;
  PERFORM pg_temp.billing_crud_record(
    'line_discount_fixed_at_line_subtotal_valid',
    v_result.success AND v_line_discount_amount = 50.00,
    COALESCE(v_line_discount_amount::text, v_result.error_code)
  );

  -- US5: list_invoices query scenarios
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches SET code = 'SIDE' WHERE id = v_branch_no_code;
  v_side_visit := pg_temp.seed_completed_visit(
    v_branch_no_code, v_patient_id, v_doctor_staff, v_owner_user, 20
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_side_visit);
  v_side_invoice := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_side_invoice;
  v_result := public.add_invoice_item(v_side_invoice, v_updated_at, 'Side branch visit', 1, 60.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_side_invoice;
  v_result := public.issue_invoice(v_side_invoice, v_updated_at);

  v_detail := public.get_invoice_detail(v_invoice_pay);
  v_balance := (v_detail.data -> 'invoice' ->> 'balance')::numeric;
  v_result := public.record_payment(v_invoice_pay, 'cash', v_balance, NULL, 'List test full pay');

  v_list := public.list_invoices('{}'::jsonb, 50, 0);
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_returns_rows_with_required_fields',
    v_list.success
      AND jsonb_array_length(v_list.data -> 'items') >= 1
      AND (v_list.data -> 'items' -> 0 ->> 'patient_display_name') IS NOT NULL
      AND (v_list.data -> 'items' -> 0 ->> 'balance') IS NOT NULL
      AND (v_list.data -> 'items' -> 0 ->> 'paid_amount') IS NOT NULL,
    jsonb_array_length(v_list.data -> 'items')::text
  );

  v_list := public.list_invoices(jsonb_build_object('statuses', jsonb_build_array('paid')), 50, 0);
  SELECT count(*)::int
  INTO v_list_item_count
  FROM jsonb_array_elements(v_list.data -> 'items') elem
  WHERE elem ->> 'status' <> 'paid';
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_status_filter_paid',
    v_list.success AND v_list_item_count = 0 AND jsonb_array_length(v_list.data -> 'items') >= 1,
    v_list_item_count::text
  );

  v_list := public.list_invoices(jsonb_build_object('patient_search', 'Billing'), 50, 0);
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_patient_search',
    v_list.success AND jsonb_array_length(v_list.data -> 'items') >= 1,
    jsonb_array_length(v_list.data -> 'items')::text
  );

  v_list := public.list_invoices(jsonb_build_object('visit_id', v_side_visit::text), 50, 0);
  SELECT count(*)::int
  INTO v_list_item_count
  FROM jsonb_array_elements(v_list.data -> 'items') elem
  WHERE (elem ->> 'id')::uuid <> v_side_invoice;
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_visit_id_filter',
    v_list.success
      AND jsonb_array_length(v_list.data -> 'items') = 1
      AND v_list_item_count = 0
      AND (v_list.data -> 'items' -> 0 ->> 'id')::uuid = v_side_invoice,
    format('count=%s', jsonb_array_length(v_list.data -> 'items'))
  );

  v_list := public.list_invoices(jsonb_build_object('invoice_number', '%'), 50, 0);
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_invoice_number_escapes_percent_wildcard',
    v_list.success AND jsonb_array_length(v_list.data -> 'items') = 0,
    jsonb_array_length(v_list.data -> 'items')::text
  );

  v_list := public.list_invoices(jsonb_build_object('invoice_number', 'INV-MAIN'), 50, 0);
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_invoice_number_prefix_still_works',
    v_list.success AND jsonb_array_length(v_list.data -> 'items') >= 1,
    jsonb_array_length(v_list.data -> 'items')::text
  );

  v_list := public.list_invoices(
    jsonb_build_object(
      'date_from', (now() - interval '1 day')::text,
      'date_to', (now() + interval '1 day')::text
    ),
    50,
    0
  );
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_date_range_includes_recent',
    v_list.success AND jsonb_array_length(v_list.data -> 'items') >= 1,
    jsonb_array_length(v_list.data -> 'items')::text
  );

  v_list := public.list_invoices(
    jsonb_build_object('date_to', (now() - interval '2 days')::text),
    50,
    0
  );
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_date_range_excludes_recent',
    v_list.success AND jsonb_array_length(v_list.data -> 'items') = 0,
    jsonb_array_length(v_list.data -> 'items')::text
  );

  v_list := public.list_invoices(
    jsonb_build_object('branch_ids', jsonb_build_array(v_branch_main::text)),
    50,
    0
  );
  SELECT count(*)::int
  INTO v_list_item_count
  FROM jsonb_array_elements(v_list.data -> 'items') elem
  WHERE elem ->> 'branch_code' = 'SIDE';
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_branch_intersection',
    v_list.success AND v_list_item_count = 0,
    v_list_item_count::text
  );

  v_list := public.list_invoices('{}'::jsonb, 1, 0);
  v_list_item_count := jsonb_array_length(v_list.data -> 'items');
  v_list := public.list_invoices('{}'::jsonb, 2, 0);
  SELECT count(DISTINCT elem ->> 'id')::int
  INTO v_audit_count
  FROM jsonb_array_elements(v_list.data -> 'items') elem;
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_pagination_boundary',
    v_list.success
      AND v_list_item_count = 1
      AND jsonb_array_length(v_list.data -> 'items') = 2
      AND v_audit_count = 2,
    format('limit1=%s limit2=%s distinct=%s', v_list_item_count, jsonb_array_length(v_list.data -> 'items'), v_audit_count)
  );

  v_list := public.list_invoices('{}'::jsonb, 1, 0);
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_has_more_when_extra_row_exists',
    v_list.success
      AND jsonb_array_length(v_list.data -> 'items') = 1
      AND COALESCE((v_list.data ->> 'has_more')::boolean, false) = true,
    format('items=%s has_more=%s', jsonb_array_length(v_list.data -> 'items'), v_list.data ->> 'has_more')
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.invoices i
  WHERE i.is_deleted = false
    AND i.branch_id = ANY (ARRAY[v_branch_main, v_branch_no_code]::uuid[]);
  v_list := public.list_invoices('{}'::jsonb, v_audit_count, 0);
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_has_more_false_on_last_page',
    v_list.success
      AND jsonb_array_length(v_list.data -> 'items') <= v_audit_count
      AND COALESCE((v_list.data ->> 'has_more')::boolean, false) = false,
    format('items=%s has_more=%s', jsonb_array_length(v_list.data -> 'items'), v_list.data ->> 'has_more')
  );

  v_list := public.list_invoices('{}'::jsonb, 1, 1);
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_offset_skips_first_row',
    v_list.success AND jsonb_array_length(v_list.data -> 'items') <= 1,
    jsonb_array_length(v_list.data -> 'items')::text
  );

  v_list := public.list_patient_invoices(v_patient_id, 50, 0);
  PERFORM pg_temp.billing_crud_record(
    'list_patient_invoices_for_profile',
    v_list.success AND jsonb_array_length(v_list.data -> 'items') >= 1,
    jsonb_array_length(v_list.data -> 'items')::text
  );

  PERFORM pg_temp.set_doctor_jwt(
    v_doctor_user,
    v_doctor_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_list := public.list_invoices('{}'::jsonb, 10, 0);
  PERFORM pg_temp.billing_crud_record(
    'list_invoices_permission_denied_for_doctor',
    NOT v_list.success AND v_list.error_code = 'FORBIDDEN',
    COALESCE(v_list.error_code, '<null>')
  );

  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  -- US6: void invoice scenarios
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  PERFORM set_config('role', 'postgres', true);
  v_visit_void := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 21
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_void);
  v_invoice_void_issued := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_issued;
  v_result := public.add_invoice_item(v_invoice_void_issued, v_updated_at, 'Void test item', 1, 50.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_issued;
  v_result := public.issue_invoice(v_invoice_void_issued, v_updated_at);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_issued;
  v_result := public.void_invoice(v_invoice_void_issued, v_updated_at, 'Created in error');
  SELECT status, void_reason
  INTO v_status, v_void_reason
  FROM public.invoices
  WHERE id = v_invoice_void_issued;
  PERFORM pg_temp.billing_crud_record(
    'void_issued_invoice_succeeds',
    v_result.success AND v_status = 'voided' AND v_void_reason = 'Created in error',
    format('status=%s reason=%s', v_status, v_void_reason)
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'invoice.void'
    AND al.record_id = v_invoice_void_issued
    AND al.new_data_json ->> 'prior_status' = 'issued'
    AND al.new_data_json ->> 'new_status' = 'voided';
  PERFORM pg_temp.billing_crud_record(
    'void_invoice_audited',
    v_audit_count >= 1,
    v_audit_count::text
  );

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.organization_billing_settings
  SET allow_partial_payments = true
  WHERE organization_id = v_org_id;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  PERFORM set_config('role', 'postgres', true);
  v_visit_pay := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 22
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_pay);
  v_invoice_void_partial := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_partial;
  v_result := public.add_invoice_item(v_invoice_void_partial, v_updated_at, 'Partial void test', 1, 100.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_partial;
  v_result := public.issue_invoice(v_invoice_void_partial, v_updated_at);
  v_result := public.record_payment(v_invoice_void_partial, 'cash', 40.00, NULL, 'Partial before void');
  SELECT status INTO v_status FROM public.invoices WHERE id = v_invoice_void_partial;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_partial;
  v_result := public.void_invoice(v_invoice_void_partial, v_updated_at, 'Patient cancelled');
  SELECT status, void_reason
  INTO v_status, v_void_reason
  FROM public.invoices
  WHERE id = v_invoice_void_partial;
  PERFORM pg_temp.billing_crud_record(
    'void_partially_paid_invoice_succeeds',
    v_result.success AND v_status = 'voided' AND v_void_reason = 'Patient cancelled',
    format('status=%s reason=%s', v_status, v_void_reason)
  );

  PERFORM set_config('role', 'postgres', true);
  v_visit_paid_void := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 19
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_paid_void);
  v_invoice_paid_void := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_paid_void;
  v_result := public.add_invoice_item(v_invoice_paid_void, v_updated_at, 'Paid void guard', 1, 75.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_paid_void;
  v_result := public.issue_invoice(v_invoice_paid_void, v_updated_at);
  v_result := public.record_payment(v_invoice_paid_void, 'cash', 75.00, NULL, 'Paid in full');
  SELECT status INTO v_status FROM public.invoices WHERE id = v_invoice_paid_void;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_paid_void;
  v_result := public.void_invoice(v_invoice_paid_void, v_updated_at, 'Should fail on paid');
  PERFORM pg_temp.billing_crud_record(
    'void_paid_invoice_rejected',
    v_status = 'paid'
      AND NOT v_result.success
      AND v_result.error_code = 'INVOICE_NOT_VOIDABLE',
    format('status=%s code=%s', v_status, COALESCE(v_result.error_code, '<null>'))
  );

  v_result := public.record_payment(v_invoice_void_issued, 'cash', 10.00, NULL, NULL);
  PERFORM pg_temp.billing_crud_record(
    'voided_invoice_rejects_payment',
    NOT v_result.success AND v_result.error_code = 'INVOICE_VOIDED',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_issued;
  v_result := public.add_invoice_item(v_invoice_void_issued, v_updated_at, 'Late item', 1, 10.00);
  PERFORM pg_temp.billing_crud_record(
    'voided_invoice_rejects_item_add',
    NOT v_result.success AND v_result.error_code = 'INVOICE_VOIDED',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT ii.id, i.updated_at
  INTO v_item_id, v_updated_at
  FROM public.invoice_items ii
  JOIN public.invoices i ON i.id = ii.invoice_id
  WHERE i.id = v_invoice_void_issued
    AND ii.is_deleted = false
  LIMIT 1;
  -- Voided invoices must return INVOICE_VOIDED (spec US6: distinct from issued/paid INVOICE_NOT_IN_DRAFT).
  v_result := public.apply_line_discount(v_item_id, v_updated_at, 'percentage', 5.00);
  PERFORM pg_temp.billing_crud_record(
    'voided_invoice_rejects_line_discount',
    NOT v_result.success AND v_result.error_code = 'INVOICE_VOIDED',
    COALESCE(v_result.error_code, '<null>')
  );

  v_detail := public.get_invoice_detail(v_invoice_void_issued);
  PERFORM pg_temp.billing_crud_record(
    'voided_invoice_visible_in_detail',
    v_detail.success
      AND v_detail.data -> 'invoice' ->> 'status' = 'voided'
      AND v_detail.data -> 'invoice' ->> 'void_reason' = 'Created in error',
    COALESCE(v_detail.data -> 'invoice' ->> 'void_reason', '<null>')
  );

  v_balance := (v_detail.data -> 'invoice' ->> 'balance')::numeric;
  PERFORM pg_temp.billing_crud_record(
    'voided_invoice_balance_zero_for_reporting',
    v_balance = 0.00,
    v_balance::text
  );

  v_result := public.create_invoice_from_visit(v_visit_void);
  PERFORM pg_temp.billing_crud_record(
    'new_invoice_allowed_after_void',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  PERFORM set_config('role', 'postgres', true);
  v_visit_void_perm := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 23
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.create_invoice_from_visit(v_visit_void_perm);
  v_invoice_void_perm := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_perm;
  v_result := public.add_invoice_item(v_invoice_void_perm, v_updated_at, 'Permission test', 1, 25.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_perm;
  v_result := public.issue_invoice(v_invoice_void_perm, v_updated_at);

  v_stale_updated_at := '2000-01-01 00:00:00+00'::timestamptz;
  v_result := public.void_invoice(v_invoice_void_perm, v_stale_updated_at, 'Stale void attempt');
  PERFORM pg_temp.billing_crud_record(
    'stale_invoice_rejects_void',
    NOT v_result.success AND v_result.error_code = 'STALE_INVOICE',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_void_perm;
  v_result := public.void_invoice(v_invoice_void_perm, v_updated_at, 'Unauthorized void');
  PERFORM pg_temp.billing_crud_record(
    'void_permission_denied_for_receptionist',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );

  -- payment/refund permission and edge inputs
  PERFORM pg_temp.set_doctor_jwt(
    v_doctor_user,
    v_doctor_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.record_payment(v_invoice_for_payment, 'cash', 10.00, NULL, NULL);
  PERFORM pg_temp.billing_crud_record(
    'record_payment_permission_denied_for_doctor',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  v_result := public.record_refund(v_invoice_for_payment, 'cash', 10.00, 'Unauthorized refund');
  PERFORM pg_temp.billing_crud_record(
    'record_refund_permission_denied_for_doctor',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.record_payment(v_invoice_for_payment, 'cash', 0.00, NULL, NULL);
  PERFORM pg_temp.billing_crud_record(
    'record_payment_rejects_zero_amount',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );

  v_result := public.record_payment(v_draft_discard, 'cash', 10.00, NULL, NULL);
  PERFORM pg_temp.billing_crud_record(
    'record_payment_rejects_draft_invoice',
    NOT v_result.success AND v_result.error_code = 'INVOICE_NOT_PAYABLE',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_owner_jwt(
    v_owner_user,
    v_owner_staff,
    v_org_id,
    format('%s,%s', v_branch_main, v_branch_no_code)
  );
  v_result := public.record_refund(v_invoice_for_payment, 'cash', 500.00, 'Excessive refund');
  PERFORM pg_temp.billing_crud_record(
    'record_refund_rejects_amount_exceeding_net_payments',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
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
