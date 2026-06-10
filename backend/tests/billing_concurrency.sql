-- V1-6 billing US2 concurrent payment race verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/billing_concurrency.sql

BEGIN;

CREATE TEMP TABLE billing_concurrency_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.billing_concurrency_record(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_concurrency_results (test_name, passed, detail)
  VALUES (p_name, p_passed, p_detail);
  PERFORM set_config('role', 'authenticated', true);
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

CREATE OR REPLACE FUNCTION pg_temp.test_appointment_same_day_slot(p_offset_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_day_start timestamptz;
BEGIN
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  RETURN v_day_start + make_interval(hours => p_offset_hours);
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

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1600000-0000-4000-8000-000000000201';
  v_owner_staff uuid := 'b1600000-0000-4000-8000-000000000201';
  v_reception_user uuid := 'a1600000-0000-4000-8000-000000000202';
  v_reception_staff uuid := 'b1600000-0000-4000-8000-000000000202';
  v_doctor_user uuid := 'a1600000-0000-4000-8000-000000000203';
  v_doctor_staff uuid := 'b1600000-0000-4000-8000-000000000203';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_id uuid;
  v_visit_id uuid;
  v_invoice_id uuid;
  v_updated_at timestamptz;
  v_balance numeric(14, 2);
  v_detail public.rpc_result;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_reception_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-conc-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_reception_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-conc-recep',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bill-conc-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Billing Concurrency Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
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
    (v_owner_staff, v_owner_user, 'Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_reception_staff, v_reception_user, 'Reception', 'receptionist', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_reception_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    v_branch_main::text
  );

  v_result := public.create_patient(v_branch_main, 'Race Patient', '201600000201', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  v_visit_id := pg_temp.seed_completed_visit(
    v_branch_main, v_patient_id, v_doctor_staff, v_owner_user, 10
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    v_branch_main::text
  );

  v_result := public.create_invoice_from_visit(v_visit_id);
  v_invoice_id := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.add_invoice_item(v_invoice_id, v_updated_at, 'Race item', 1, 100.00);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  v_result := public.issue_invoice(v_invoice_id, v_updated_at);

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.organization_billing_settings
  SET allow_partial_payments = true
  WHERE organization_id = v_org_id;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(
    v_reception_user,
    v_reception_staff,
    v_org_id,
    v_branch_main::text
  );

  -- Emulate two near-simultaneous payments racing to zero balance (sequential txns).
  v_result := public.record_payment(v_invoice_id, 'cash', 60.00, NULL, NULL);
  PERFORM pg_temp.billing_concurrency_record(
    'first_concurrent_payment_accepted',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  v_detail := public.get_invoice_detail(v_invoice_id);
  v_balance := (v_detail.data -> 'invoice' ->> 'balance')::numeric;

  v_result := public.record_payment(v_invoice_id, 'cash', 60.00, NULL, NULL);
  PERFORM pg_temp.billing_concurrency_record(
    'second_concurrent_payment_rejected_overpayment',
    NOT v_result.success AND v_result.error_code = 'OVERPAYMENT',
    COALESCE(v_result.error_code, '<null>')
  );

  v_result := public.record_payment(v_invoice_id, 'cash', v_balance, NULL, 'Final payment');
  PERFORM pg_temp.billing_concurrency_record(
    'remaining_balance_payment_closes_invoice',
    v_result.success
      AND EXISTS (
        SELECT 1 FROM public.invoices i
        WHERE i.id = v_invoice_id AND i.status = 'paid'
      ),
    COALESCE(v_result.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_fail billing_concurrency_results%ROWTYPE;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  FOR v_fail IN
    SELECT * FROM billing_concurrency_results WHERE NOT passed
  LOOP
    RAISE EXCEPTION 'Billing concurrency test failed: % — %', v_fail.test_name, v_fail.detail;
  END LOOP;
END;
$$;

COMMIT;

DO $$ BEGIN PERFORM set_config('role', 'postgres', true); END; $$;
SELECT test_name, passed, detail
FROM billing_concurrency_results
ORDER BY test_name;
