-- Service Catalog (015) US2: pricing resolution + add-to-invoice snapshot tests.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/service_catalog_pricing.sql

BEGIN;

CREATE TEMP TABLE service_catalog_pricing_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.service_catalog_pricing_record(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO service_catalog_pricing_results (test_name, passed, detail)
  VALUES (p_name, p_passed, p_detail);
  PERFORM set_config('role', 'authenticated', true);
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
  v_org_id uuid := 'c2800000-0000-4000-8000-0000000000a1';
  v_branch_a uuid := 'd2800000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd2800000-0000-4000-8000-0000000000a2';
  v_branch_c uuid := 'd2800000-0000-4000-8000-0000000000a3';
  v_user_admin uuid := 'e2800000-0000-4000-8000-0000000000a1';
  v_user_recep uuid := 'e2800000-0000-4000-8000-0000000000a2';
  v_user_doctor uuid := 'e2800000-0000-4000-8000-0000000000a3';
  v_staff_admin uuid := 'f2800000-0000-4000-8000-0000000000a1';
  v_staff_recep uuid := 'f2800000-0000-4000-8000-0000000000a2';
  v_patient_id uuid := 'a2800000-0000-4000-8000-0000000000a1';
  v_doctor_staff uuid := 'b2800000-0000-4000-8000-0000000000a1';
  v_visit_id uuid := 'c2800000-0000-4000-8000-000000000aa1';
  v_appt_id uuid := 'c2800000-0000-4000-8000-000000000ab1';
  v_invoice_id uuid;
  v_service_default uuid;
  v_service_override uuid;
  v_service_promo uuid;
  v_service_inactive uuid;
  v_service_unassigned uuid;
  v_service_branch_inactive uuid;
  v_service_consult uuid;
  v_sb_updated_at timestamptz;
  v_promo_start date;
  v_promo_end date;
  v_result public.rpc_result;
  v_resolution jsonb;
  v_item_id uuid;
  v_unit_price numeric(14, 2);
  v_quantity numeric(14, 2);
  v_description text;
  v_updated_at timestamptz;
  v_search_count int;
  v_promo_price numeric(14, 2);
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log WHERE organization_id = v_org_id;
  DELETE FROM public.invoice_items WHERE invoice_id IN (SELECT id FROM public.invoices WHERE organization_id = v_org_id);
  DELETE FROM public.invoices WHERE organization_id = v_org_id;
  DELETE FROM public.visits WHERE branch_id IN (v_branch_a, v_branch_b, v_branch_c);
  DELETE FROM public.appointments WHERE branch_id IN (v_branch_a, v_branch_b, v_branch_c);
  DELETE FROM public.service_branches
  WHERE service_id IN (SELECT id FROM public.services WHERE organization_id = v_org_id);
  DELETE FROM public.services WHERE organization_id = v_org_id;
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id IN (v_staff_admin, v_staff_recep, v_doctor_staff);
  DELETE FROM public.staff_members WHERE id IN (v_staff_admin, v_staff_recep, v_doctor_staff);
  DELETE FROM public.patients WHERE organization_id = v_org_id;
  DELETE FROM public.branches WHERE organization_id = v_org_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM auth.users WHERE id IN (v_user_admin, v_user_recep, v_user_doctor);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-price-admin',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_recep, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-price-recep',
     extensions.crypt('pw-r', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_doctor, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'svc-price-doc',
     extensions.crypt('pw-d', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_org_id, 'Service Pricing Org', v_user_admin, v_user_admin);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_id, 'Branch A', 'SPA', v_user_admin, v_user_admin),
    (v_branch_b, v_org_id, 'Branch B', 'SPB', v_user_admin, v_user_admin),
    (v_branch_c, v_org_id, 'Branch C', 'SPC', v_user_admin, v_user_admin);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_admin, v_user_admin, 'Admin', 'administrator', v_user_admin, v_user_admin),
    (v_staff_recep, v_user_recep, 'Reception', 'receptionist', v_user_admin, v_user_admin),
    (v_doctor_staff, v_user_doctor, 'Doctor', 'doctor', v_user_admin, v_user_admin);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, created_by, updated_by)
  VALUES
    (v_staff_admin, v_branch_a, v_user_admin, v_user_admin),
    (v_staff_admin, v_branch_b, v_user_admin, v_user_admin),
    (v_staff_admin, v_branch_c, v_user_admin, v_user_admin),
    (v_staff_recep, v_branch_a, v_user_admin, v_user_admin),
    (v_staff_recep, v_branch_b, v_user_admin, v_user_admin),
    (v_doctor_staff, v_branch_a, v_user_admin, v_user_admin);

  INSERT INTO public.patients (id, branch_id, organization_id, full_name, phone, created_by, updated_by)
  VALUES (v_patient_id, v_branch_a, v_org_id, 'Pricing Patient', '+10000000001', v_user_admin, v_user_admin);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES (
    v_appt_id, v_branch_a, v_patient_id, v_doctor_staff,
    now(), now() + interval '30 minutes', 'planned', 'completed', v_user_admin, v_user_admin
  );

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES (
    v_visit_id, v_branch_a, v_appt_id, v_patient_id, v_doctor_staff,
    current_date, 'completed', v_user_admin, v_user_admin
  );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_administrator_jwt(v_user_admin, v_staff_admin, v_org_id, format('%s,%s,%s', v_branch_a, v_branch_b, v_branch_c));

  v_result := public.create_service('Default Consult', 200.00, 'active', false, ARRAY[v_branch_a]);
  v_service_default := (v_result.data ->> 'service_id')::uuid;

  v_result := public.create_service('Override Consult', 200.00, 'active', false, ARRAY[v_branch_a]);
  v_service_override := (v_result.data ->> 'service_id')::uuid;

  v_result := public.create_service('Promo Consult', 200.00, 'active', false, ARRAY[v_branch_a]);
  v_service_promo := (v_result.data ->> 'service_id')::uuid;

  v_result := public.create_service('Inactive Global', 80.00, 'inactive', false, ARRAY[v_branch_a]);
  v_service_inactive := (v_result.data ->> 'service_id')::uuid;

  v_result := public.create_service('Unassigned Service', 90.00, 'active', false, ARRAY[v_branch_b]);
  v_service_unassigned := (v_result.data ->> 'service_id')::uuid;

  v_result := public.create_service('Branch Inactive', 70.00, 'active', false, ARRAY[v_branch_a]);
  v_service_branch_inactive := (v_result.data ->> 'service_id')::uuid;

  PERFORM set_config('role', 'postgres', true);

  UPDATE public.service_branches
  SET price_override = 150.00, updated_by = v_user_admin
  WHERE service_id = v_service_override AND branch_id = v_branch_a;

  UPDATE public.service_branches
  SET
    price_override = 120.00,
    promotion_price = 100.00,
    promotion_start_date = current_date - 1,
    promotion_end_date = current_date + 1,
    updated_by = v_user_admin
  WHERE service_id = v_service_promo AND branch_id = v_branch_a;

  UPDATE public.service_branches
  SET status = 'inactive', updated_by = v_user_admin
  WHERE service_id = v_service_branch_inactive AND branch_id = v_branch_a;

  PERFORM set_config('role', 'authenticated', true);

  -- default price resolution
  v_result := public.resolve_effective_service_price(v_service_default, v_branch_a, current_date);
  v_resolution := v_result.data;
  PERFORM pg_temp.service_catalog_pricing_record(
    'resolve_default_price',
    v_result.success
      AND (v_resolution ->> 'eligible')::boolean = true
      AND v_resolution ->> 'applied_rule' = 'default'
      AND v_resolution ->> 'unit_price' = '200.00',
    COALESCE(v_resolution ->> 'unit_price', v_result.error_code)
  );

  -- override resolution
  v_result := public.resolve_effective_service_price(v_service_override, v_branch_a, current_date);
  v_resolution := v_result.data;
  PERFORM pg_temp.service_catalog_pricing_record(
    'resolve_override_price',
    v_result.success
      AND v_resolution ->> 'applied_rule' = 'override'
      AND v_resolution ->> 'unit_price' = '150.00',
    COALESCE(v_resolution ->> 'unit_price', v_result.error_code)
  );

  -- promo takes priority over override
  v_result := public.resolve_effective_service_price(v_service_promo, v_branch_a, current_date);
  v_resolution := v_result.data;
  PERFORM pg_temp.service_catalog_pricing_record(
    'resolve_promo_priority',
    v_result.success
      AND v_resolution ->> 'applied_rule' = 'promo'
      AND v_resolution ->> 'unit_price' = '100.00',
    COALESCE(v_resolution ->> 'unit_price', v_result.error_code)
  );

  -- ineligible reasons
  v_result := public.resolve_effective_service_price(v_service_inactive, v_branch_a, current_date);
  PERFORM pg_temp.service_catalog_pricing_record(
    'resolve_global_inactive',
    v_result.success AND (v_result.data ->> 'eligible')::boolean = false AND v_result.data ->> 'reason' = 'GLOBAL_INACTIVE',
    COALESCE(v_result.data ->> 'reason', v_result.error_code)
  );

  v_result := public.resolve_effective_service_price(v_service_unassigned, v_branch_a, current_date);
  PERFORM pg_temp.service_catalog_pricing_record(
    'resolve_not_assigned',
    v_result.success AND (v_result.data ->> 'eligible')::boolean = false AND v_result.data ->> 'reason' = 'NOT_ASSIGNED',
    COALESCE(v_result.data ->> 'reason', v_result.error_code)
  );

  v_result := public.resolve_effective_service_price(v_service_branch_inactive, v_branch_a, current_date);
  PERFORM pg_temp.service_catalog_pricing_record(
    'resolve_branch_inactive',
    v_result.success AND (v_result.data ->> 'eligible')::boolean = false AND v_result.data ->> 'reason' = 'BRANCH_INACTIVE',
    COALESCE(v_result.data ->> 'reason', v_result.error_code)
  );

  -- search eligible services
  PERFORM pg_temp.set_reception_jwt(v_user_recep, v_staff_recep, v_org_id, v_branch_a::text);
  v_result := public.search_eligible_services(v_branch_a, 'Consult', current_date, 20);
  SELECT jsonb_array_length(COALESCE(v_result.data -> 'items', '[]'::jsonb))
  INTO v_search_count;
  PERFORM pg_temp.service_catalog_pricing_record(
    'search_eligible_services_filters',
    v_result.success AND v_search_count = 3,
    'count=' || v_search_count::text
  );

  -- invoice from visit for add-to-invoice tests
  v_result := public.create_invoice_from_visit(v_visit_id);
  v_invoice_id := (v_result.data ->> 'invoice_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  v_result := public.add_invoice_item_from_service(v_invoice_id, v_updated_at, v_service_promo);
  v_item_id := (v_result.data ->> 'item_id')::uuid;
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;

  SELECT unit_price, quantity, description
  INTO v_unit_price, v_quantity, v_description
  FROM public.invoice_items
  WHERE id = v_item_id;

  PERFORM pg_temp.service_catalog_pricing_record(
    'add_from_service_snapshot',
    v_result.success
      AND v_unit_price = 100.00
      AND v_quantity = 1
      AND v_description = 'Promo Consult',
    format('unit_price=%s qty=%s', v_unit_price, v_quantity)
  );

  -- create-or-increment
  v_result := public.add_invoice_item_from_service(v_invoice_id, v_updated_at, v_service_promo);
  SELECT updated_at INTO v_updated_at FROM public.invoices WHERE id = v_invoice_id;
  SELECT quantity INTO v_quantity FROM public.invoice_items WHERE id = v_item_id;
  PERFORM pg_temp.service_catalog_pricing_record(
    'add_from_service_increment_quantity',
    v_result.success AND v_quantity = 2,
    'qty=' || v_quantity::text
  );

  -- snapshot immutability after catalog price change
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.services SET default_price = 999.00, updated_by = v_user_admin WHERE id = v_service_promo;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.set_reception_jwt(v_user_recep, v_staff_recep, v_org_id, v_branch_a::text);
  SELECT unit_price INTO v_unit_price FROM public.invoice_items WHERE id = v_item_id;
  PERFORM pg_temp.service_catalog_pricing_record(
    'add_from_service_snapshot_immutable',
    v_unit_price = 100.00,
    'unit_price=' || v_unit_price::text
  );

  -- ineligible rejection
  v_result := public.add_invoice_item_from_service(v_invoice_id, v_updated_at, v_service_inactive);
  PERFORM pg_temp.service_catalog_pricing_record(
    'add_from_service_ineligible_rejected',
    NOT v_result.success AND v_result.error_code = 'SERVICE_NOT_ELIGIBLE',
    COALESCE(v_result.error_code, '<null>')
  );

  PERFORM pg_temp.set_administrator_jwt(
    v_user_admin, v_staff_admin, v_org_id, format('%s,%s,%s', v_branch_a, v_branch_b, v_branch_c)
  );

  -- US3: configure_service_branch override, default fallback, inactive, unassigned rejection
  v_result := public.create_service('Consultation', 200.00, 'active', false, ARRAY[v_branch_a, v_branch_b, v_branch_c]);
  v_service_consult := (v_result.data ->> 'service_id')::uuid;

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_b;

  v_result := public.configure_service_branch(
    v_service_consult, v_branch_b, v_sb_updated_at, 'active', 150.00
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'configure_branch_override',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_c;

  v_result := public.configure_service_branch(
    v_service_consult, v_branch_c, v_sb_updated_at, 'inactive', NULL
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'configure_branch_inactive',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  v_result := public.resolve_effective_service_price(v_service_consult, v_branch_a, current_date);
  PERFORM pg_temp.service_catalog_pricing_record(
    'configure_default_fallback',
    v_result.success AND v_result.data ->> 'unit_price' = '200.00',
    COALESCE(v_result.data ->> 'unit_price', v_result.error_code)
  );

  v_result := public.resolve_effective_service_price(v_service_consult, v_branch_b, current_date);
  PERFORM pg_temp.service_catalog_pricing_record(
    'configure_override_resolution',
    v_result.success AND v_result.data ->> 'unit_price' = '150.00',
    COALESCE(v_result.data ->> 'unit_price', v_result.error_code)
  );

  v_result := public.resolve_effective_service_price(v_service_consult, v_branch_c, current_date);
  PERFORM pg_temp.service_catalog_pricing_record(
    'configure_inactive_not_selectable',
    v_result.success AND (v_result.data ->> 'eligible')::boolean = false,
    COALESCE(v_result.data ->> 'reason', v_result.error_code)
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_unassigned AND sb.branch_id = v_branch_b;

  v_result := public.configure_service_branch(
    v_service_unassigned, v_branch_a, v_sb_updated_at, 'active', NULL
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'configure_unassigned_branch_rejected',
    NOT v_result.success AND v_result.error_code = 'BRANCH_NOT_ASSIGNED',
    COALESCE(v_result.error_code, '<null>')
  );

  -- US4: promotion inclusive boundaries, rejections, replace
  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_c;

  v_result := public.configure_service_branch(
    v_service_consult, v_branch_c, v_sb_updated_at, 'active', 120.00
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_c;

  v_promo_start := make_date(extract(year from current_date)::int, 1, 1);
  v_promo_end := make_date(extract(year from current_date)::int, 1, 31);

  v_result := public.set_service_promotion(
    v_service_consult, v_branch_c, v_sb_updated_at, 100.00, v_promo_start, v_promo_end
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'set_promotion_success',
    v_result.success AND (v_result.data ->> 'has_promotion')::boolean = true,
    COALESCE(v_result.error_code, 'ok')
  );

  v_result := public.resolve_effective_service_price(
    v_service_consult, v_branch_c, make_date(extract(year from current_date)::int, 1, 15)
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'promo_inclusive_mid_window',
    v_result.success AND v_result.data ->> 'unit_price' = '100.00',
    COALESCE(v_result.data ->> 'unit_price', v_result.error_code)
  );

  v_result := public.resolve_effective_service_price(
    v_service_consult, v_branch_c, make_date(extract(year from current_date)::int, 1, 31)
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'promo_inclusive_end_boundary',
    v_result.success AND v_result.data ->> 'unit_price' = '100.00',
    COALESCE(v_result.data ->> 'unit_price', v_result.error_code)
  );

  v_result := public.resolve_effective_service_price(
    v_service_consult, v_branch_c, make_date(extract(year from current_date)::int, 2, 1)
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'promo_after_window_uses_override',
    v_result.success AND v_result.data ->> 'unit_price' = '120.00',
    COALESCE(v_result.data ->> 'unit_price', v_result.error_code)
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_c;

  v_result := public.set_service_promotion(
    v_service_consult, v_branch_c, v_sb_updated_at, 150.00, v_promo_start, v_promo_end
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'promo_exceeds_effective_rejected',
    NOT v_result.success AND v_result.error_code = 'PROMO_EXCEEDS_PRICE',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_c;

  v_result := public.set_service_promotion(
    v_service_consult, v_branch_c, v_sb_updated_at, 100.00, v_promo_start, NULL
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'promo_incomplete_rejected',
    NOT v_result.success AND v_result.error_code = 'PROMO_INCOMPLETE',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_c;

  v_result := public.set_service_promotion(
    v_service_consult, v_branch_c, v_sb_updated_at, 100.00, v_promo_end, v_promo_start
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'promo_invalid_date_range_rejected',
    NOT v_result.success AND v_result.error_code = 'PROMO_DATE_RANGE',
    COALESCE(v_result.error_code, '<null>')
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_c;

  v_result := public.set_service_promotion(
    v_service_consult, v_branch_c, v_sb_updated_at, 90.00, v_promo_start, v_promo_end
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'promo_single_window_replace',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT promotion_price
  INTO v_promo_price
  FROM public.service_branches
  WHERE service_id = v_service_consult AND branch_id = v_branch_c;

  PERFORM pg_temp.service_catalog_pricing_record(
    'promo_single_window_replace_value',
    v_result.success AND v_promo_price = 90.00,
    'promotion_price=' || COALESCE(v_promo_price::text, '<null>')
  );

  SELECT sb.updated_at
  INTO v_sb_updated_at
  FROM public.service_branches sb
  WHERE sb.service_id = v_service_consult AND sb.branch_id = v_branch_c;

  v_result := public.configure_service_branch(
    v_service_consult, v_branch_c, v_sb_updated_at, 'active', 80.00
  );
  PERFORM pg_temp.service_catalog_pricing_record(
    'configure_lowering_override_violates_promo',
    NOT v_result.success AND v_result.error_code = 'PROMO_EXCEEDS_PRICE',
    COALESCE(v_result.error_code, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
  v_row record;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*)::int
  INTO v_failures
  FROM service_catalog_pricing_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    FOR v_row IN
      SELECT test_name, detail
      FROM service_catalog_pricing_results
      WHERE NOT passed
      ORDER BY test_name
    LOOP
      RAISE NOTICE 'FAIL %: %', v_row.test_name, v_row.detail;
    END LOOP;
    RAISE EXCEPTION 'service_catalog_pricing.sql: % test(s) failed', v_failures;
  END IF;
END;
$$;

ROLLBACK;
