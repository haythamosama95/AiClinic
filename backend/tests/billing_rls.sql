-- V1-6 cross-org and cross-branch denial for billing tables.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/billing_rls.sql

BEGIN;

CREATE TEMP TABLE billing_rls_results (
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
  v_user_owner uuid := 'e2600000-0000-4000-8000-0000000000a1';
  v_user_reception uuid := 'e2600000-0000-4000-8000-0000000000a2';
  v_user_doctor uuid := 'e2600000-0000-4000-8000-0000000000a3';
  v_user_lab uuid := 'e2600000-0000-4000-8000-0000000000a4';
  v_user_owner_b uuid := 'e2600000-0000-4000-8000-0000000000b2';
  v_staff_owner uuid := 'f2600000-0000-4000-8000-0000000000a1';
  v_staff_reception uuid := 'f2600000-0000-4000-8000-0000000000a2';
  v_staff_doctor uuid := 'f2600000-0000-4000-8000-0000000000a3';
  v_staff_lab uuid := 'f2600000-0000-4000-8000-0000000000a4';
  v_staff_owner_b uuid := 'f2600000-0000-4000-8000-0000000000b2';
  v_patient_a uuid := 'a2600000-0000-4000-8000-0000000000a1';
  v_patient_a2 uuid := 'a2600000-0000-4000-8000-0000000000a2';
  v_patient_b uuid := 'a2600000-0000-4000-8000-0000000000b2';
  v_appt_a uuid := 'c2600000-0000-4000-8000-00000000aa01';
  v_appt_a2 uuid := 'c2600000-0000-4000-8000-00000000aa02';
  v_appt_b uuid := 'c2600000-0000-4000-8000-00000000bb01';
  v_visit_a uuid := 'f2600000-0000-4000-8000-00000000aa01';
  v_visit_a2 uuid := 'f2600000-0000-4000-8000-00000000aa02';
  v_visit_b uuid := 'f2600000-0000-4000-8000-00000000bb01';
  v_invoice_a uuid := 'b2600000-0000-4000-8000-0000000000a1';
  v_invoice_a2 uuid := 'b2600000-0000-4000-8000-0000000000a2';
  v_invoice_b uuid := 'b2600000-0000-4000-8000-0000000000b2';
  v_item_a uuid := 'b2600000-0000-4000-8000-000000000001';
  v_payment_a uuid := 'b2600000-0000-4000-8000-000000000002';
  v_provider_a uuid := 'b2600000-0000-4000-8000-000000000003';
  v_provider_b uuid := 'b2600000-0000-4000-8000-000000000004';
  v_visible_count int;
  v_dml_failed boolean;
  v_role_perm_result public.rpc_result;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();

  DELETE FROM public.payments WHERE id = v_payment_a;
  DELETE FROM public.invoice_items WHERE id = v_item_a;
  DELETE FROM public.invoices WHERE id IN (v_invoice_a, v_invoice_a2, v_invoice_b);
  DELETE FROM public.insurance_providers WHERE id IN (v_provider_a, v_provider_b);
  DELETE FROM public.visits WHERE id IN (v_visit_a, v_visit_a2, v_visit_b);
  DELETE FROM public.appointments WHERE id IN (v_appt_a, v_appt_a2, v_appt_b);
  DELETE FROM public.patients WHERE id IN (v_patient_a, v_patient_a2, v_patient_b);
  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_staff_owner, v_staff_reception, v_staff_doctor, v_staff_lab, v_staff_owner_b);
  DELETE FROM public.staff_members
  WHERE id IN (v_staff_owner, v_staff_reception, v_staff_doctor, v_staff_lab, v_staff_owner_b);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b, v_branch_a2);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users
  WHERE id IN (v_user_owner, v_user_reception, v_user_doctor, v_user_lab, v_user_owner_b);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-bill-owner-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_reception, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-bill-recep-a',
     extensions.crypt('pw-r', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_doctor, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-bill-doc-a',
     extensions.crypt('pw-d', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_lab, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-bill-lab-a',
     extensions.crypt('pw-l', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_owner_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-bill-owner-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Billing Org A', v_user_owner, v_user_owner),
    (v_org_b, 'RLS Billing Org B', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'BA', v_user_owner, v_user_owner),
    (v_branch_a2, v_org_a, 'Branch A2', 'BA2', v_user_owner, v_user_owner),
    (v_branch_b, v_org_b, 'Branch B', 'BB', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_owner, v_user_owner, 'Owner A', 'administrator', v_user_owner, v_user_owner),
    (v_staff_reception, v_user_reception, 'Reception A', 'receptionist', v_user_owner, v_user_owner),
    (v_staff_doctor, v_user_doctor, 'Doctor A', 'doctor', v_user_owner, v_user_owner),
    (v_staff_lab, v_user_lab, 'Lab A', 'lab_staff', v_user_owner, v_user_owner),
    (v_staff_owner_b, v_user_owner_b, 'Owner B', 'administrator', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_owner, v_branch_a, true, v_user_owner, v_user_owner),
    (v_staff_owner, v_branch_a2, false, v_user_owner, v_user_owner),
    (v_staff_reception, v_branch_a, true, v_user_owner, v_user_owner),
    (v_staff_doctor, v_branch_a, true, v_user_owner, v_user_owner),
    (v_staff_lab, v_branch_a, true, v_user_owner, v_user_owner),
    (v_staff_owner_b, v_branch_b, true, v_user_owner_b, v_user_owner_b);

  INSERT INTO public.patients (id, branch_id, organization_id, full_name, phone, created_by, updated_by)
  VALUES
    (v_patient_a, v_branch_a, v_org_a, 'Patient A', '201111111261', v_user_owner, v_user_owner),
    (v_patient_a2, v_branch_a2, v_org_a, 'Patient A2', '201111111262', v_user_owner, v_user_owner),
    (v_patient_b, v_branch_b, v_org_b, 'Patient B', '201234567961', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES
    (v_appt_a, v_branch_a, v_patient_a, v_staff_doctor, now(), now() + interval '30 minutes', 'planned', 'completed', v_user_owner, v_user_owner),
    (v_appt_a2, v_branch_a2, v_patient_a2, v_staff_doctor, now() + interval '1 hour', now() + interval '90 minutes', 'planned', 'completed', v_user_owner, v_user_owner),
    (v_appt_b, v_branch_b, v_patient_b, v_staff_owner_b, now(), now() + interval '30 minutes', 'planned', 'completed', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES
    (v_visit_a, v_branch_a, v_appt_a, v_patient_a, v_staff_doctor, current_date, 'completed', v_user_owner, v_user_owner),
    (v_visit_a2, v_branch_a2, v_appt_a2, v_patient_a2, v_staff_doctor, current_date, 'completed', v_user_owner, v_user_owner),
    (v_visit_b, v_branch_b, v_appt_b, v_patient_b, v_staff_owner_b, current_date, 'completed', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.insurance_providers (id, organization_id, name, created_by, updated_by)
  VALUES
    (v_provider_a, v_org_a, 'Provider A', v_user_owner, v_user_owner),
    (v_provider_b, v_org_b, 'Provider B', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.invoices (
    id, organization_id, branch_id, patient_id, visit_id, status, subtotal, currency, created_by, updated_by
  )
  VALUES
    (v_invoice_a, v_org_a, v_branch_a, v_patient_a, v_visit_a, 'issued', 100.00, 'USD', v_user_owner, v_user_owner),
    (v_invoice_a2, v_org_a, v_branch_a2, v_patient_a2, v_visit_a2, 'issued', 50.00, 'USD', v_user_owner, v_user_owner),
    (v_invoice_b, v_org_b, v_branch_b, v_patient_b, v_visit_b, 'issued', 75.00, 'USD', v_user_owner_b, v_user_owner_b);

  INSERT INTO public.invoice_items (
    id, invoice_id, description, quantity, unit_price, line_subtotal, line_discount_amount, line_total, created_by, updated_by
  )
  VALUES
    (v_item_a, v_invoice_a, 'Consultation', 1, 100.00, 100.00, 0.00, 100.00, v_user_owner, v_user_owner);

  INSERT INTO public.payments (
    id, invoice_id, branch_id, method, amount, recorded_by, created_by
  )
  VALUES
    (v_payment_a, v_invoice_a, v_branch_a, 'cash', 25.00, v_staff_owner, v_user_owner);

  -- Owner A JWT scoped to branch A only
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int INTO v_visible_count FROM public.invoices i WHERE i.id = v_invoice_b;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES ('cross_org_invoice_hidden', v_visible_count = 0, 'count=' || v_visible_count::text);

  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*)::int INTO v_visible_count FROM public.invoices i WHERE i.id = v_invoice_a2;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES ('cross_branch_invoice_hidden', v_visible_count = 0, 'count=' || v_visible_count::text);

  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*)::int INTO v_visible_count FROM public.invoice_items ii WHERE ii.id = v_item_a;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES ('invoice_items_branch_scoped', v_visible_count = 1, 'count=' || v_visible_count::text);

  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*)::int INTO v_visible_count FROM public.payments p WHERE p.id = v_payment_a;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES ('payments_branch_scoped', v_visible_count = 1, 'count=' || v_visible_count::text);

  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*)::int INTO v_visible_count FROM public.insurance_providers ip WHERE ip.id = v_provider_b;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES ('cross_org_insurance_provider_hidden', v_visible_count = 0, 'count=' || v_visible_count::text);

  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*)::int INTO v_visible_count
  FROM public.organization_billing_settings obs
  WHERE obs.organization_id = v_org_b;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES ('cross_org_billing_settings_hidden', v_visible_count = 0, 'count=' || v_visible_count::text);

  -- Receptionist cannot directly mutate billing settings (RLS deny)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_reception::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_reception::text,
      'staff_role', 'receptionist',
      'setup_required', false
    )::text,
    true
  );

  v_dml_failed := false;
  BEGIN
    UPDATE public.organization_billing_settings
    SET allow_partial_payments = true
    WHERE organization_id = v_org_a;
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_dml_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES (
    'receptionist_billing_settings_update_denied',
    v_dml_failed OR NOT EXISTS (
      SELECT 1
      FROM public.organization_billing_settings obs
      WHERE obs.organization_id = v_org_a
        AND obs.allow_partial_payments = true
    ),
    'dml_failed=' || v_dml_failed::text
  );

  -- Doctor cannot read invoices
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_doctor::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_doctor::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int INTO v_visible_count FROM public.invoices i WHERE i.id = v_invoice_a;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES ('doctor_invoice_hidden', v_visible_count = 0, 'count=' || v_visible_count::text);

  -- Lab staff cannot read invoices
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_lab::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_lab::text,
      'staff_role', 'lab_staff',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int INTO v_visible_count FROM public.invoices i WHERE i.id = v_invoice_a;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES ('lab_staff_invoice_hidden', v_visible_count = 0, 'count=' || v_visible_count::text);

  -- Non-delegable settings.billing.manage for receptionist via role-permission RPC
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_role_perm_result := public.update_role_permission('receptionist', 'settings.billing.manage', true);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES (
    'settings_billing_manage_non_delegable',
    NOT v_role_perm_result.success AND v_role_perm_result.error_code = 'PERMISSION_NOT_DELEGABLE',
    COALESCE(v_role_perm_result.error_code, '<null>')
  );

  -- Payments table must not allow UPDATE/DELETE for authenticated (T071 security).
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_dml_failed := false;
  BEGIN
    UPDATE public.payments SET amount = 999.00 WHERE id = v_payment_a;
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_dml_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES (
    'payments_update_denied_for_authenticated',
    v_dml_failed OR NOT EXISTS (
      SELECT 1 FROM public.payments p WHERE p.id = v_payment_a AND p.amount = 999.00
    ),
    'dml_failed=' || v_dml_failed::text
  );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_dml_failed := false;
  BEGIN
    DELETE FROM public.payments WHERE id = v_payment_a;
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_dml_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO billing_rls_results VALUES (
    'payments_delete_denied_for_authenticated',
    v_dml_failed OR EXISTS (SELECT 1 FROM public.payments p WHERE p.id = v_payment_a),
    'dml_failed=' || v_dml_failed::text
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
  v_detail text;
BEGIN
  SELECT count(*)::int
  INTO v_failures
  FROM billing_rls_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    SELECT string_agg(test_name || ': ' || detail, '; ')
    INTO v_detail
    FROM billing_rls_results
    WHERE NOT passed;

    RAISE EXCEPTION 'billing_rls.sql: % failing assertion(s): %', v_failures, v_detail;
  END IF;
END;
$$;

SELECT test_name, passed, detail FROM billing_rls_results ORDER BY test_name;

ROLLBACK;
