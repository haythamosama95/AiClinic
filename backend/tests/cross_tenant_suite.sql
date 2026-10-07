-- Cross-tenant suite (P1.2). Harness H-BK.
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/cross_tenant_suite.sql

BEGIN;

CREATE TEMP TABLE cross_tenant_suite_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE TEMP TABLE cross_tenant_fixture (
  dual_user_id uuid PRIMARY KEY,
  admin_user_id uuid NOT NULL,
  org_a uuid NOT NULL,
  org_b uuid NOT NULL,
  branch_a uuid NOT NULL,
  branch_b uuid NOT NULL,
  staff_dual uuid NOT NULL,
  staff_b_only uuid NOT NULL,
  patient_a uuid NOT NULL,
  patient_b uuid NOT NULL,
  appt_a uuid NOT NULL,
  appt_b uuid NOT NULL,
  visit_a uuid NOT NULL,
  visit_b uuid NOT NULL,
  service_a uuid NOT NULL,
  service_b uuid NOT NULL,
  invoice_b uuid NOT NULL,
  invoice_item_b uuid NOT NULL,
  shift_b uuid NOT NULL,
  insurance_b uuid NOT NULL,
  attachment_b uuid NOT NULL,
  payment_b uuid NOT NULL,
  staff_nomember uuid NOT NULL
);

CREATE OR REPLACE FUNCTION pg_temp.cross_tenant_refresh_session(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_hook jsonb;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  v_hook := public.get_custom_claims(
    jsonb_build_object(
      'user_id', p_user_id::text,
      'claims', jsonb_build_object(
        'sub', p_user_id::text,
        'role', 'authenticated'
      )
    )
  );
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', (v_hook -> 'claims')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.cross_tenant_rpc_acceptable(p_result public.rpc_result)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_result IS NULL THEN
    RETURN false;
  END IF;
  IF NOT p_result.success THEN
    RETURN p_result.error_code IN (
      'NOT_FOUND', 'FORBIDDEN', 'PERMISSION_DENIED', 'INVALID_INPUT',
      'INVALID_BRANCH', 'INVALID_DOCTOR',
      'PERMISSION_NOT_DELEGABLE', 'INVALID_PERMISSION', 'VALIDATION_ERROR',
      'CONFLICT', 'STALE', 'CONTEXT_REQUIRED', 'DOMAIN_ERROR'
    );
  END IF;
  IF p_result.data IS NULL THEN
    RETURN true;
  END IF;
  IF p_result.data ? 'items' THEN
    RETURN jsonb_array_length(COALESCE(p_result.data -> 'items', '[]'::jsonb)) = 0;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.cross_tenant_exception_acceptable(p_state text, p_message text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN p_state IN ('42501', 'P0001')
    OR p_message LIKE '%FORBIDDEN%'
    OR p_message LIKE '%NOT_FOUND%'
    OR p_message LIKE '%PERMISSION%'
    OR p_message LIKE '%STAFF_NOT_FOUND%'
    OR p_message LIKE '%BRANCH_NOT_FOUND%'
    OR p_message LIKE '%INSTALLATION_NOT_ENROLLED%';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.cross_tenant_b_snapshot()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_org_b uuid;
  v_table text;
  v_part text;
  v_digest text := '';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT f.org_b INTO v_org_b FROM pg_temp.cross_tenant_fixture f;

  FOREACH v_table IN ARRAY ARRAY[
    'public.patients',
    'public.appointments',
    'public.visits',
    'public.visit_clinical_notes',
    'public.visit_vital_signs',
    'public.visit_investigations',
    'public.visit_attachments',
    'public.treatment_plans',
    'public.invoices',
    'public.invoice_items',
    'public.payments',
    'public.invoice_number_sequences',
    'public.patient_allergies',
    'public.patient_medications',
    'public.patient_chronic_conditions',
    'public.service_branches',
    'public.shift_assignments',
    'public.roles_permissions',
    'public.branches',
    'public.services',
    'public.shifts',
    'public.insurance_providers',
    'public.investigations',
    'public.medications',
    'public.predefined_vital_signs',
    'public.app_settings',
    'public.organization_billing_settings',
    'public.subscription_cache',
    'public.ai_accepted_output',
    'ai_internal.ai_token_issuance'
  ]
  LOOP
    EXECUTE format(
      'SELECT md5(coalesce(string_agg(row_to_json(t)::text, '''' ORDER BY row_to_json(t)::text), '''')) FROM %s t WHERE t.organization_id = $1',
      v_table
    )
    INTO v_part
    USING v_org_b;
    v_digest := v_digest || v_table || '=' || coalesce(v_part, '') || ';';
  END LOOP;

  RETURN v_digest;
END;
$$;

-- Direct read of one inventoried table. A missing organization_id column fails
-- this assertion; it does not abort the suite on an undefined column.
CREATE OR REPLACE FUNCTION pg_temp.cross_tenant_org_leak(
  p_table regclass,
  p_org uuid,
  p_allow_unreadable boolean DEFAULT false
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_b int;
  v_visible int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  EXECUTE format('SELECT count(*) FROM %s WHERE organization_id = $1', p_table)
    INTO v_b
    USING p_org;
  IF v_b = 0 THEN
    PERFORM set_config('role', 'authenticated', true);
    RETURN p_table::text || ' has no organisation B row';
  END IF;

  PERFORM set_config('role', 'authenticated', true);
  EXECUTE format('SELECT count(*) FROM %s WHERE organization_id = $1', p_table)
    INTO v_visible
    USING p_org;
  IF v_visible > 0 THEN
    RETURN p_table::text || '=' || v_visible::text;
  END IF;
  RETURN NULL;
EXCEPTION
  WHEN undefined_column THEN
    PERFORM set_config('role', 'authenticated', true);
    RETURN p_table::text || '.organization_id missing';
  WHEN insufficient_privilege THEN
    PERFORM set_config('role', 'authenticated', true);
    IF p_allow_unreadable THEN
      RETURN NULL;
    END IF;
    RETURN p_table::text || ' not selectable by authenticated';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.decode_jws_payload(p_token text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT convert_from(
    decode(
      rpad(
        translate(split_part(p_token, '.', 2), '-_', '+/'),
        length(split_part(p_token, '.', 2))
          + ((4 - length(split_part(p_token, '.', 2)) % 4) % 4),
        '='
      ),
      'base64'
    ),
    'utf8'
  )::jsonb;
$$;

-- T001: two-org fixture (no E2E assertion).
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_dual_user uuid := '06210000-0000-4000-8000-000000000001';
  v_admin_user uuid := '06210000-0000-4000-8000-000000000003';
  v_staff_b_user uuid := '06210000-0000-4000-8000-000000000002';
  v_nomember_user uuid := '06210000-0000-4000-8000-000000000004';
  v_staff_admin uuid := '06212000-0000-4000-8000-000000000003';
  v_staff_nomember uuid := '06212000-0000-4000-8000-000000000004';
  v_org_a uuid := '06211000-0000-4000-8000-00000000000a';
  v_org_b uuid := '06211000-0000-4000-8000-00000000000b';
  v_branch_a uuid := '06214000-0000-4000-8000-00000000000a';
  v_branch_b uuid := '06214000-0000-4000-8000-00000000000b';
  v_staff_dual uuid := '06212000-0000-4000-8000-000000000001';
  v_staff_b_only uuid := '06212000-0000-4000-8000-000000000002';
  v_patient_a uuid := '06215000-0000-4000-8000-00000000000a';
  v_patient_b uuid := '06215000-0000-4000-8000-00000000000b';
  v_appt_a uuid := '06216000-0000-4000-8000-00000000000a';
  v_appt_b uuid := '06216000-0000-4000-8000-00000000000b';
  v_visit_a uuid := '06217000-0000-4000-8000-00000000000a';
  v_visit_b uuid := '06217000-0000-4000-8000-00000000000b';
  v_service_a uuid := '06218000-0000-4000-8000-00000000000a';
  v_service_b uuid := '06218000-0000-4000-8000-00000000000b';
  v_invoice_b uuid := '06219000-0000-4000-8000-00000000000b';
  v_invoice_item_b uuid := '06219100-0000-4000-8000-00000000000b';
  v_shift_b uuid := '0621a000-0000-4000-8000-00000000000b';
  v_insurance_b uuid := '0621b000-0000-4000-8000-00000000000b';
  v_payment_b uuid := '0621c000-0000-4000-8000-00000000000b';
  v_attachment_b uuid := '0621d000-0000-4000-8000-00000000000b';
  v_start timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '10 hours';
  v_note_ts timestamptz := '2026-10-02T10:00:00+00';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'development', true);

  DELETE FROM ai_internal.ai_token_issuance
  WHERE actor_staff_id IN (v_staff_dual, v_staff_b_only, v_staff_admin, v_staff_nomember)
     OR organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.ai_accepted_output WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.audit_log
  WHERE user_id IN (v_dual_user, v_staff_b_user, v_admin_user, v_nomember_user)
     OR organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.payments WHERE invoice_id = v_invoice_b OR id = v_payment_b;
  DELETE FROM public.invoice_number_sequences WHERE branch_id IN (v_branch_a, v_branch_b);
  DELETE FROM public.patient_allergies WHERE patient_id IN (v_patient_a, v_patient_b);
  DELETE FROM public.patient_medications WHERE patient_id IN (v_patient_a, v_patient_b);
  DELETE FROM public.patient_chronic_conditions WHERE patient_id IN (v_patient_a, v_patient_b);
  DELETE FROM public.visit_vital_signs WHERE visit_id IN (v_visit_a, v_visit_b);
  DELETE FROM public.visit_investigations WHERE visit_id IN (v_visit_a, v_visit_b);
  DELETE FROM public.treatment_plans WHERE visit_id IN (v_visit_a, v_visit_b);
  DELETE FROM public.app_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.subscription_cache WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.investigations WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.medications WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.predefined_vital_signs WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.payments WHERE id = v_payment_b;
  DELETE FROM public.invoice_items WHERE id = v_invoice_item_b;
  DELETE FROM public.invoices WHERE id = v_invoice_b;
  DELETE FROM public.visit_attachments WHERE id = v_attachment_b;
  DELETE FROM public.shift_assignments WHERE shift_id = v_shift_b;
  DELETE FROM public.shifts WHERE id = v_shift_b;
  DELETE FROM public.service_branches WHERE service_id IN (v_service_a, v_service_b);
  DELETE FROM public.visit_clinical_notes WHERE visit_id IN (v_visit_a, v_visit_b);
  DELETE FROM public.visits WHERE id IN (v_visit_a, v_visit_b);
  DELETE FROM public.appointments WHERE id IN (v_appt_a, v_appt_b);
  DELETE FROM public.patients WHERE id IN (v_patient_a, v_patient_b);
  DELETE FROM public.services WHERE id IN (v_service_a, v_service_b);
  DELETE FROM public.insurance_providers WHERE id = v_insurance_b;
  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_staff_dual, v_staff_b_only, v_staff_admin, v_staff_nomember);
  DELETE FROM ai_internal.user_active_organization
  WHERE user_id IN (v_dual_user, v_staff_b_user, v_admin_user, v_nomember_user);
  DELETE FROM ai_internal.membership
  WHERE user_id IN (v_dual_user, v_staff_b_user, v_admin_user, v_nomember_user);
  DELETE FROM public.staff_members
  WHERE id IN (v_staff_dual, v_staff_b_only, v_staff_admin, v_staff_nomember);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_dual_user, v_staff_b_user, v_admin_user, v_nomember_user);

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES
    (v_dual_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'e2e-p12-dual', extensions.crypt('pw-e2e-p12-dual', extensions.gen_salt('bf')), now(), now(), now()),
    (v_staff_b_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'e2e-p12-b-staff', extensions.crypt('pw-e2e-p12-b', extensions.gen_salt('bf')), now(), now(), now()),
    (v_admin_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'e2e-p12-admin-a', extensions.crypt('pw-e2e-p12-admin', extensions.gen_salt('bf')), now(), now(), now()),
    (v_nomember_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'e2e-p12-nomember', extensions.crypt('pw-e2e-p12-nomember', extensions.gen_salt('bf')), now(), now(), now());

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'E2E P1.2 Org A', v_dual_user, v_dual_user),
    (v_org_b, 'E2E P1.2 Org B', v_dual_user, v_dual_user);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'P1.2 Branch A', 'P12A', v_dual_user, v_dual_user),
    (v_branch_b, v_org_b, 'P1.2 Branch B', 'P12B', v_dual_user, v_dual_user);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_dual, v_dual_user, 'E2E P1.2 Dual Member', 'doctor', v_dual_user, v_dual_user),
    (v_staff_b_only, v_staff_b_user, 'E2E P1.2 B Only', 'doctor', v_dual_user, v_dual_user),
    (v_staff_admin, v_admin_user, 'E2E P1.2 Admin A', 'administrator', v_dual_user, v_dual_user),
    (v_staff_nomember, v_nomember_user, 'E2E P1.2 Branch A No Membership', 'doctor', v_dual_user, v_dual_user);

  INSERT INTO ai_internal.membership (user_id, organization_id, role, created_at)
  VALUES
    (v_dual_user, v_org_a, 'doctor', now() - interval '2 days'),
    (v_dual_user, v_org_b, 'doctor', now() - interval '1 day'),
    (v_staff_b_user, v_org_b, 'doctor', now()),
    (v_admin_user, v_org_a, 'administrator', now()),
    (v_nomember_user, v_org_b, 'doctor', now());

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_dual, v_branch_a, true, v_dual_user, v_dual_user),
    (v_staff_dual, v_branch_b, false, v_dual_user, v_dual_user),
    (v_staff_b_only, v_branch_b, true, v_dual_user, v_dual_user),
    (v_staff_admin, v_branch_a, true, v_dual_user, v_dual_user),
    (v_staff_nomember, v_branch_a, true, v_dual_user, v_dual_user);

  INSERT INTO public.patients (
    id, branch_id, organization_id, full_name, phone, mrn, created_by, updated_by
  )
  VALUES
    (v_patient_a, v_branch_a, v_org_a, 'P1.2 Patient A', '201062000001', 'MRN-P12A', v_dual_user, v_dual_user),
    (v_patient_b, v_branch_b, v_org_b, 'P1.2 Patient B', '201062000002', 'MRN-P12B', v_dual_user, v_dual_user);

  INSERT INTO public.services (id, organization_id, name, default_price, created_by, updated_by)
  VALUES
    (v_service_a, v_org_a, 'P1.2 Service A', 100, v_dual_user, v_dual_user),
    (v_service_b, v_org_b, 'P1.2 Service B', 100, v_dual_user, v_dual_user);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES
    (v_appt_a, v_branch_a, v_patient_a, v_staff_dual, v_start, v_start + interval '30 minutes', 'planned', 'scheduled', v_dual_user, v_dual_user),
    (v_appt_b, v_branch_b, v_patient_b, v_staff_b_only, v_start, v_start + interval '30 minutes', 'planned', 'scheduled', v_dual_user, v_dual_user);

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES
    (v_visit_a, v_branch_a, v_appt_a, v_patient_a, v_staff_dual, current_date, 'in_progress', v_dual_user, v_dual_user),
    (v_visit_b, v_branch_b, v_appt_b, v_patient_b, v_staff_b_only, current_date, 'in_progress', v_dual_user, v_dual_user);

  INSERT INTO public.visit_clinical_notes (
    visit_id, complaint, created_by, updated_by, updated_at
  )
  VALUES (v_visit_b, 'P1.2 baseline note', v_dual_user, v_dual_user, v_note_ts);

  INSERT INTO public.insurance_providers (id, organization_id, name, created_by, updated_by)
  VALUES (v_insurance_b, v_org_b, 'P1.2 Insurance B', v_dual_user, v_dual_user);

  INSERT INTO public.invoices (
    id, branch_id, organization_id, patient_id, visit_id, status, currency, created_by, updated_by
  )
  VALUES (v_invoice_b, v_branch_b, v_org_b, v_patient_b, v_visit_b, 'draft', 'EGP', v_dual_user, v_dual_user);

  INSERT INTO public.invoice_items (
    id, invoice_id, description, quantity, unit_price, line_subtotal, line_total,
    created_by, updated_by
  )
  VALUES (v_invoice_item_b, v_invoice_b, 'P1.2 line', 1, 100, 100, 100, v_dual_user, v_dual_user);

  INSERT INTO public.shifts (
    id, branch_id, organization_id, shift_date, start_time, end_time, created_by, updated_by
  )
  VALUES (
    v_shift_b, v_branch_b, v_org_b, current_date, '09:00'::time, '17:00'::time,
    v_dual_user, v_dual_user
  );

  INSERT INTO public.visit_vital_signs (visit_id, name, value, organization_id, created_by, updated_by)
  VALUES (v_visit_b, 'P1.2 BP', '120', v_org_b, v_dual_user, v_dual_user);

  INSERT INTO public.visit_investigations (visit_id, name, organization_id, created_by, updated_by)
  VALUES (v_visit_b, 'P1.2 CBC', v_org_b, v_dual_user, v_dual_user);

  INSERT INTO public.visit_attachments (
    id, visit_id, file_path, file_type, uploaded_by, size_bytes, organization_id, created_by, updated_by
  )
  VALUES (
    v_attachment_b, v_visit_b, 'p12/b.pdf', 'pdf', v_staff_b_only, 100, v_org_b, v_dual_user, v_dual_user
  );

  INSERT INTO public.treatment_plans (
    visit_id, patient_id, medication_name, organization_id, created_by, updated_by
  )
  VALUES (v_visit_b, v_patient_b, 'P1.2 med', v_org_b, v_dual_user, v_dual_user);

  INSERT INTO public.payments (
    id, invoice_id, branch_id, method, amount, recorded_by, organization_id, created_by
  )
  VALUES (v_payment_b, v_invoice_b, v_branch_b, 'cash', 10, v_staff_b_only, v_org_b, v_dual_user);

  INSERT INTO public.invoice_number_sequences (branch_id, organization_id)
  VALUES (v_branch_b, v_org_b);

  INSERT INTO public.patient_allergies (patient_id, substance, organization_id, created_by, updated_by)
  VALUES (v_patient_b, 'P1.2 penicillin', v_org_b, v_dual_user, v_dual_user);

  INSERT INTO public.patient_medications (patient_id, name, organization_id, created_by, updated_by)
  VALUES (v_patient_b, 'P1.2 aspirin', v_org_b, v_dual_user, v_dual_user);

  INSERT INTO public.patient_chronic_conditions (patient_id, name, organization_id, created_by, updated_by)
  VALUES (v_patient_b, 'P1.2 asthma', v_org_b, v_dual_user, v_dual_user);

  INSERT INTO public.service_branches (service_id, branch_id, organization_id, created_by, updated_by)
  VALUES (v_service_b, v_branch_b, v_org_b, v_dual_user, v_dual_user);

  INSERT INTO public.shift_assignments (shift_id, staff_member_id, organization_id, created_by, updated_by)
  VALUES (v_shift_b, v_staff_b_only, v_org_b, v_dual_user, v_dual_user);

  INSERT INTO public.investigations (organization_id, name, created_by, updated_by)
  VALUES (v_org_b, 'P1.2 Investigation B', v_dual_user, v_dual_user);

  INSERT INTO public.medications (organization_id, name, created_by, updated_by)
  VALUES (v_org_b, 'P1.2 Medication B', v_dual_user, v_dual_user);

  INSERT INTO public.predefined_vital_signs (organization_id, name, created_by, updated_by)
  VALUES (v_org_b, 'P1.2 Vital B', v_dual_user, v_dual_user);

  INSERT INTO public.organization_billing_settings (organization_id)
  VALUES (v_org_b)
  ON CONFLICT (organization_id) DO NOTHING;

  INSERT INTO public.subscription_cache (organization_id, tier)
  VALUES (v_org_b, 'trial');

  INSERT INTO public.app_settings (organization_id, key, value_json, created_by, updated_by)
  VALUES (v_org_b, 'p12.probe', '{"v":1}'::jsonb, v_dual_user, v_dual_user);

  INSERT INTO public.audit_log (organization_id, user_id, action, table_name)
  VALUES (v_org_b, v_staff_b_user, 'p12.probe', 'organizations');

  INSERT INTO public.ai_accepted_output (
    organization_id, table_name, record_id, ai_request_reference, accepted_by, audit_log_id
  )
  SELECT v_org_b, 'visit_clinical_notes', v_visit_b, 'P12B-SEED', v_staff_b_user, al.id
  FROM public.audit_log al
  WHERE al.organization_id = v_org_b
    AND al.action = 'p12.probe'
  ORDER BY al.created_at DESC
  LIMIT 1;

  INSERT INTO ai_internal.user_active_organization (user_id, organization_id)
  VALUES (v_staff_b_user, v_org_b);

  INSERT INTO cross_tenant_fixture VALUES (
    v_dual_user, v_admin_user, v_org_a, v_org_b, v_branch_a, v_branch_b,
    v_staff_dual, v_staff_b_only, v_patient_a, v_patient_b,
    v_appt_a, v_appt_b, v_visit_a, v_visit_b, v_service_a, v_service_b,
    v_invoice_b, v_invoice_item_b, v_shift_b, v_insurance_b, v_attachment_b, v_payment_b,
    v_staff_nomember
  );

  IF NOT EXISTS (
    SELECT 1
    FROM ai_internal.issuer_key ik
    WHERE ik.status = 'signing'
  ) THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM auth_internal.insert_issuer_kid();
    PERFORM set_config('request.jwt.claims', '', true);
  END IF;

  INSERT INTO ai_internal.ai_token_issuance (
    jti, actor_staff_id, organization_id, created_by, aud
  )
  VALUES (
    '0621e000-0000-4000-8000-00000000000b'::uuid,
    v_staff_b_only,
    v_org_b,
    v_dual_user,
    'ai-platform'
  );
END;
$$;

-- E2E-P1.2-01 — admin of A edits roles_permissions; B unchanged
DO $$
DECLARE
  v_admin_user uuid;
  v_dual_user uuid;
  v_org_a uuid;
  v_org_b uuid;
  v_single public.rpc_result;
  v_bulk public.rpc_result;
  v_b_before boolean;
  v_b_after_single boolean;
  v_b_after_bulk boolean;
  v_a_after_single boolean;
  v_perm text;
BEGIN
  SELECT admin_user_id, dual_user_id, org_a, org_b
  INTO v_admin_user, v_dual_user, v_org_a, v_org_b
  FROM cross_tenant_fixture;

  PERFORM set_config('role', 'postgres', true);
  SELECT rp.permission_key
  INTO v_perm
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor'
    AND rp.permission_key LIKE 'ai.%'
    AND rp.is_granted = true
    AND rp.is_deleted = false
  ORDER BY rp.permission_key
  LIMIT 1;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_dual_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM public.set_active_organization(v_org_b);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
  SELECT rp.is_granted INTO v_b_before
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor'
    AND rp.permission_key = v_perm
    AND rp.is_deleted = false;

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM public.set_active_organization(v_org_a);
  PERFORM pg_temp.cross_tenant_refresh_session(v_admin_user);
  v_single := public.update_role_permission('doctor', v_perm, NOT v_b_before);

  SELECT rp.is_granted INTO v_a_after_single
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_a
    AND rp.role = 'doctor'
    AND rp.permission_key = v_perm
    AND rp.is_deleted = false;

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_dual_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM public.set_active_organization(v_org_b);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
  SELECT rp.is_granted INTO v_b_after_single
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor'
    AND rp.permission_key = v_perm
    AND rp.is_deleted = false;

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM public.set_active_organization(v_org_a);
  PERFORM pg_temp.cross_tenant_refresh_session(v_admin_user);
  v_bulk := public.update_role_permissions(
    jsonb_build_array(
      jsonb_build_object(
        'role', 'doctor',
        'permission_key', v_perm,
        'is_granted', v_b_before
      )
    )
  );

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_dual_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM public.set_active_organization(v_org_b);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
  SELECT rp.is_granted INTO v_b_after_bulk
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor'
    AND rp.permission_key = v_perm
    AND rp.is_deleted = false;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO cross_tenant_suite_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.2-01',
    v_perm IS NOT NULL
      AND v_single.success
      AND v_bulk.success
      AND v_b_before IS NOT NULL
      AND v_a_after_single IS NOT NULL
      AND v_a_after_single IS DISTINCT FROM v_b_before
      AND v_b_after_single IS NOT DISTINCT FROM v_b_before
      AND v_b_after_bulk IS NOT DISTINCT FROM v_b_before,
    'perm=' || COALESCE(v_perm, '<null>')
      || ' single=' || COALESCE(v_single.success::text, '<null>')
      || ' bulk=' || COALESCE(v_bulk.success::text, '<null>')
      || ' b_before=' || COALESCE(v_b_before::text, '<null>')
      || ' a_after_single=' || COALESCE(v_a_after_single::text, '<null>')
      || ' b_after_single=' || COALESCE(v_b_after_single::text, '<null>')
      || ' b_after_bulk=' || COALESCE(v_b_after_bulk::text, '<null>')
  );

  UPDATE public.roles_permissions
  SET is_granted = v_b_before, updated_by = NULL
  WHERE organization_id = v_org_a
    AND role = 'doctor'
    AND permission_key = v_perm
    AND is_deleted = false;
END;
$$;

-- E2E-P1.2-02 — user of A calls every tenant RPC with B's ids
-- Earlier migrations dropped archive_visit_diagnosis_code, create_catalog_diagnosis_code,
-- create_visit_diagnosis_code, get_specialty_form_schema, save_soap_note,
-- save_visit_plan_details, and search_diagnosis_codes with their tables
-- (research.md §2). They are not live RPCs, so this suite does not call them.
DO $$
DECLARE
  v_dual_user uuid;
  v_org_a uuid;
  v_org_b uuid;
  v_patient_b uuid;
  v_appt_b uuid;
  v_visit_b uuid;
  v_branch_b uuid;
  v_invoice_b uuid;
  v_staff_b_only uuid;
  v_service_b uuid;
  v_shift_b uuid;
  v_insurance_b uuid;
  v_invoice_item_b uuid;
  v_attachment_b uuid;
  v_payment_b uuid;
  v_rpc public.rpc_result;
  v_snap_before text;
  v_snap_after text;
  v_violations text[] := ARRAY[]::text[];
BEGIN
  SELECT dual_user_id, org_a, org_b, patient_b, appt_b, visit_b, branch_b,
         invoice_b, staff_b_only, service_b, shift_b, insurance_b,
         invoice_item_b, attachment_b, payment_b
  INTO v_dual_user, v_org_a, v_org_b, v_patient_b, v_appt_b, v_visit_b, v_branch_b,
       v_invoice_b, v_staff_b_only, v_service_b, v_shift_b, v_insurance_b,
       v_invoice_item_b, v_attachment_b, v_payment_b
  FROM cross_tenant_fixture;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_dual_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM public.set_active_organization(v_org_a);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);

  v_snap_before := pg_temp.cross_tenant_b_snapshot();
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);

  BEGIN
    v_rpc := public.add_invoice_item(v_invoice_b, now(), 'cross-tenant-probe'::text, 0::numeric, 100::numeric);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'add_invoice_item(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_description text, p_quantity numeric, p_unit_price numeric) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'add_invoice_item(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_description text, p_quantity numeric, p_unit_price numeric) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.add_invoice_item_from_service(v_invoice_b, now(), v_service_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'add_invoice_item_from_service(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_service_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'add_invoice_item_from_service(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_service_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.admin_reset_staff_password(v_staff_b_only, 'pw-ct-b'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'admin_reset_staff_password(p_staff_member_id uuid, p_new_password text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'admin_reset_staff_password(p_staff_member_id uuid, p_new_password text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.admin_update_staff_username(v_staff_b_only, 'ct-b-user'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'admin_update_staff_username(p_staff_member_id uuid, p_new_username text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'admin_update_staff_username(p_staff_member_id uuid, p_new_username text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.apply_invoice_discount(v_invoice_b, now(), NULL, 0::numeric);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'apply_invoice_discount(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_kind discount_kind, p_value numeric) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'apply_invoice_discount(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_kind discount_kind, p_value numeric) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.apply_line_discount(v_patient_b, now(), NULL, 0::numeric);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'apply_line_discount(p_item_id uuid, p_expected_updated_at timestamp with time zone, p_kind discount_kind, p_value numeric) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'apply_line_discount(p_item_id uuid, p_expected_updated_at timestamp with time zone, p_kind discount_kind, p_value numeric) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.archive_patient(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'archive_patient(p_patient_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'archive_patient(p_patient_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.archive_patient_allergy(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'archive_patient_allergy(p_allergy_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'archive_patient_allergy(p_allergy_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.archive_patient_chronic_condition(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'archive_patient_chronic_condition(p_condition_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'archive_patient_chronic_condition(p_condition_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.archive_patient_medication(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'archive_patient_medication(p_medication_record_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'archive_patient_medication(p_medication_record_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.archive_treatment_plan(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'archive_treatment_plan(p_treatment_plan_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'archive_treatment_plan(p_treatment_plan_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.archive_visit_investigation(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'archive_visit_investigation(p_investigation_line_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'archive_visit_investigation(p_investigation_line_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.archive_visit_vital_sign(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'archive_visit_vital_sign(p_vital_sign_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'archive_visit_vital_sign(p_vital_sign_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.cancel_appointment(v_appt_b, 'cross-tenant probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'cancel_appointment(p_appointment_id uuid, p_reason text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'cancel_appointment(p_appointment_id uuid, p_reason text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.cancel_shift(v_shift_b, now());
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'cancel_shift(p_shift_id uuid, p_expected_updated_at timestamp with time zone) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'cancel_shift(p_shift_id uuid, p_expected_updated_at timestamp with time zone) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.check_patient_duplicates('Cross Tenant B'::text, '201062000099'::text, current_date, v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'check_patient_duplicates(p_full_name text, p_phone text, p_date_of_birth date, p_exclude_patient_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'check_patient_duplicates(p_full_name text, p_phone text, p_date_of_birth date, p_exclude_patient_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.complete_visit(v_visit_b, now());
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'complete_visit(p_visit_id uuid, p_expected_updated_at timestamp with time zone) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'complete_visit(p_visit_id uuid, p_expected_updated_at timestamp with time zone) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.configure_service_branch(v_service_b, v_branch_b, now(), 'cross-tenant-probe'::text, 100::numeric);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'configure_service_branch(p_service_id uuid, p_branch_id uuid, p_expected_updated_at timestamp with time zone, p_status text, p_price_override numeric) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'configure_service_branch(p_service_id uuid, p_branch_id uuid, p_expected_updated_at timestamp with time zone, p_status text, p_price_override numeric) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.copy_service_branch_configuration(v_branch_b, v_branch_b, 'copy'::text, ARRAY[v_service_b]::uuid[]);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'copy_service_branch_configuration(p_source_branch_id uuid, p_target_branch_id uuid, p_mode text, p_service_ids uuid[]) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'copy_service_branch_configuration(p_source_branch_id uuid, p_target_branch_id uuid, p_mode text, p_service_ids uuid[]) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_appointment(v_branch_b, v_patient_b, v_staff_b_only, 'planned'::text, now(), 30, now(), 'probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_appointment(p_branch_id uuid, p_patient_id uuid, p_doctor_id uuid, p_type text, p_start_time timestamp with time zone, p_duration_minutes integer, p_end_time timestamp with time zone, p_notes text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_appointment(p_branch_id uuid, p_patient_id uuid, p_doctor_id uuid, p_type text, p_start_time timestamp with time zone, p_duration_minutes integer, p_end_time timestamp with time zone, p_notes text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    PERFORM public.create_catalog_investigation('Cross Tenant B'::text);
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_catalog_investigation(p_name text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    PERFORM public.create_catalog_medication('Cross Tenant B'::text);
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_catalog_medication(p_name text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_invoice_from_visit(v_visit_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_invoice_from_visit(p_visit_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_invoice_from_visit(p_visit_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_patient(v_branch_b, 'Cross Tenant B'::text, '201062000099'::text, current_date, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'probe'::text, false, 'MRN-B-CT'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_patient(p_active_branch_id uuid, p_full_name text, p_phone text, p_date_of_birth date, p_gender text, p_marital_status text, p_notes text, p_acknowledge_duplicate boolean, p_mrn text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_patient(p_active_branch_id uuid, p_full_name text, p_phone text, p_date_of_birth date, p_gender text, p_marital_status text, p_notes text, p_acknowledge_duplicate boolean, p_mrn text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_patient_allergy(v_patient_b, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_patient_allergy(p_patient_id uuid, p_substance text, p_reaction text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_patient_allergy(p_patient_id uuid, p_substance text, p_reaction text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_patient_chronic_condition(v_patient_b, 'Cross Tenant B'::text, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_patient_chronic_condition(p_patient_id uuid, p_name text, p_note text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_patient_chronic_condition(p_patient_id uuid, p_name text, p_note text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_patient_medication(v_patient_b, 'Cross Tenant B'::text, v_patient_b, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_patient_medication(p_patient_id uuid, p_name text, p_medication_id uuid, p_note text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_patient_medication(p_patient_id uuid, p_name text, p_medication_id uuid, p_note text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    PERFORM public.create_predefined_vital_sign('Cross Tenant B'::text, 'mmHg'::text);
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_predefined_vital_sign(p_name text, p_default_unit text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_service('Cross Tenant B'::text, 100::numeric, 'active'::text, false, ARRAY[v_branch_b]::uuid[]);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_service(p_name text, p_default_price numeric, p_global_status text, p_assign_all_branches boolean, p_branch_ids uuid[]) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_service(p_name text, p_default_price numeric, p_global_status text, p_assign_all_branches boolean, p_branch_ids uuid[]) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_shift(v_branch_b, current_date, '09:00'::time, '09:00'::time, 'probe'::text, ARRAY[v_staff_b_only]::uuid[]);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_shift(p_branch_id uuid, p_shift_date date, p_start_time time without time zone, p_end_time time without time zone, p_notes text, p_staff_ids uuid[]) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_shift(p_branch_id uuid, p_shift_date date, p_start_time time without time zone, p_end_time time without time zone, p_notes text, p_staff_ids uuid[]) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_staff_account('ct-b-user'::text, 'pw-ct-b'::text, 'Cross Tenant B'::text, 'doctor'::public.staff_role, ARRAY[v_branch_b]::uuid[], v_branch_b, '201062000099'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_staff_account(p_username text, p_password text, p_full_name text, p_role staff_role, p_branch_ids uuid[], p_primary_branch_id uuid, p_phone text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_staff_account(p_username text, p_password text, p_full_name text, p_role staff_role, p_branch_ids uuid[], p_primary_branch_id uuid, p_phone text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_treatment_plan(v_visit_b, 'Cross Tenant B'::text, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'probe'::text, v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_treatment_plan(p_visit_id uuid, p_medication_name text, p_dosage text, p_frequency text, p_duration text, p_notes text, p_medication_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_treatment_plan(p_visit_id uuid, p_medication_name text, p_dosage text, p_frequency text, p_duration text, p_notes text, p_medication_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_visit(v_appt_b, v_staff_b_only);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_visit(p_appointment_id uuid, p_doctor_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_visit(p_appointment_id uuid, p_doctor_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_visit_investigation(v_visit_b, 'Cross Tenant B'::text, 'cross-tenant-probe'::text, v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_visit_investigation(p_visit_id uuid, p_name text, p_note text, p_investigation_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_visit_investigation(p_visit_id uuid, p_name text, p_note text, p_investigation_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.create_visit_vital_sign(v_visit_b, 'Cross Tenant B'::text, 'cross-tenant-probe'::text, 'mmHg'::text, v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'create_visit_vital_sign(p_visit_id uuid, p_name text, p_value text, p_unit text, p_predefined_vital_sign_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'create_visit_vital_sign(p_visit_id uuid, p_name text, p_value text, p_unit text, p_predefined_vital_sign_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.delete_branch(v_branch_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'delete_branch(p_branch_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'delete_branch(p_branch_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.delete_staff_member(v_staff_b_only);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'delete_staff_member(p_staff_member_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'delete_staff_member(p_staff_member_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.delete_visit_attachment(v_attachment_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'delete_visit_attachment(p_attachment_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'delete_visit_attachment(p_attachment_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.discard_draft_invoice(v_invoice_b, now());
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'discard_draft_invoice(p_invoice_id uuid, p_expected_updated_at timestamp with time zone) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'discard_draft_invoice(p_invoice_id uuid, p_expected_updated_at timestamp with time zone) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_appointment(v_appt_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_appointment(p_appointment_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_appointment(p_appointment_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_appointment_settings(v_branch_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_appointment_settings(p_branch_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_appointment_settings(p_branch_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_billing_settings();
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_billing_settings() returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_billing_settings() raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_invoice_detail(v_invoice_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_invoice_detail(p_invoice_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_invoice_detail(p_invoice_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_patient(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_patient(p_patient_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_patient(p_patient_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_patient_safety_context(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_patient_safety_context(p_patient_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_patient_safety_context(p_patient_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_service(v_service_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_service(p_service_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_service(p_service_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_shift_detail(v_shift_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_shift_detail(p_shift_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_shift_detail(p_shift_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_simplified_booking_slots(v_branch_b, current_date, v_staff_b_only);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_simplified_booking_slots(p_branch_id uuid, p_local_date date, p_preferred_doctor_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_simplified_booking_slots(p_branch_id uuid, p_local_date date, p_preferred_doctor_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_visit(v_visit_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_visit(p_visit_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_visit(p_visit_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_visit_attachment_download(v_attachment_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_visit_attachment_download(p_attachment_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_visit_attachment_download(p_attachment_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_visit_by_appointment(v_appt_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_visit_by_appointment(p_appointment_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_visit_by_appointment(p_appointment_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.get_visit_chief_complaint(v_visit_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'get_visit_chief_complaint(p_visit_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'get_visit_chief_complaint(p_visit_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.insurance_provider_deactivate(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'insurance_provider_deactivate(p_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'insurance_provider_deactivate(p_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.insurance_provider_upsert(v_patient_b, 'Cross Tenant B'::text, 'cross-tenant-probe'::text, true);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'insurance_provider_upsert(p_id uuid, p_name text, p_contact_info text, p_is_active boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'insurance_provider_upsert(p_id uuid, p_name text, p_contact_info text, p_is_active boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    PERFORM public.issue_ai_token(1);
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'issue_ai_token(integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.issue_invoice(v_invoice_b, now());
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'issue_invoice(p_invoice_id uuid, p_expected_updated_at timestamp with time zone) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'issue_invoice(p_invoice_id uuid, p_expected_updated_at timestamp with time zone) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.list_appointments(v_branch_b, now(), now(), v_staff_b_only, ARRAY['scheduled']::text[], v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'list_appointments(p_branch_id uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_doctor_id uuid, p_statuses text[], p_patient_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_appointments(p_branch_id uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_doctor_id uuid, p_statuses text[], p_patient_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.list_insurance_providers(true);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'list_insurance_providers(p_only_active boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_insurance_providers(p_only_active boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.list_invoices(jsonb_build_object('branch_id', v_branch_b::text, 'patient_id', v_patient_b::text), 50, 0);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'list_invoices(p_filters jsonb, p_limit integer, p_offset integer) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_invoices(p_filters jsonb, p_limit integer, p_offset integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.list_patient_invoices(v_patient_b, 50, 0);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'list_patient_invoices(p_patient_id uuid, p_limit integer, p_offset integer) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_patient_invoices(p_patient_id uuid, p_limit integer, p_offset integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.list_patient_visit_attachments(v_patient_b, 50, 0);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'list_patient_visit_attachments(p_patient_id uuid, p_limit integer, p_offset integer) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_patient_visit_attachments(p_patient_id uuid, p_limit integer, p_offset integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.list_patient_visits(v_patient_b, 50, 0);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'list_patient_visits(p_patient_id uuid, p_limit integer, p_offset integer) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_patient_visits(p_patient_id uuid, p_limit integer, p_offset integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    PERFORM public.list_predefined_vital_signs();
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_predefined_vital_signs() raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.list_services('cross-tenant-probe'::text, 'active'::text, v_branch_b, 50, 0);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'list_services(p_query text, p_global_status text, p_branch_id uuid, p_limit integer, p_offset integer) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_services(p_query text, p_global_status text, p_branch_id uuid, p_limit integer, p_offset integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.list_shifts(v_branch_b, current_date, current_date, false);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'list_shifts(p_branch_id uuid, p_date_from date, p_date_to date, p_include_cancelled boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'list_shifts(p_branch_id uuid, p_date_from date, p_date_to date, p_include_cancelled boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.manage_create_branch('Cross Tenant B'::text, jsonb_build_object('branch_id', v_branch_b::text, 'patient_id', v_patient_b::text), 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, '201062000099'::text, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'manage_create_branch(p_name text, p_working_schedule jsonb, p_code text, p_address text, p_phone text, p_maps_url text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'manage_create_branch(p_name text, p_working_schedule jsonb, p_code text, p_address text, p_phone text, p_maps_url text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.modify_shift_assignments(v_shift_b, now(), ARRAY[v_staff_b_only]::uuid[], ARRAY[v_staff_b_only]::uuid[]);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'modify_shift_assignments(p_shift_id uuid, p_expected_updated_at timestamp with time zone, p_add_staff_ids uuid[], p_remove_staff_ids uuid[]) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'modify_shift_assignments(p_shift_id uuid, p_expected_updated_at timestamp with time zone, p_add_staff_ids uuid[], p_remove_staff_ids uuid[]) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.reassign_patient_mrn(v_patient_b, 'MRN-B-CT'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'reassign_patient_mrn(p_patient_id uuid, p_new_mrn text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'reassign_patient_mrn(p_patient_id uuid, p_new_mrn text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.record_ai_acceptance('cross-tenant-probe'::text, 'cross-tenant-probe'::text, jsonb_build_object('branch_id', v_branch_b::text, 'patient_id', v_patient_b::text));
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'record_ai_acceptance(p_request_reference text, p_target_key text, p_target_args jsonb) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'record_ai_acceptance(p_request_reference text, p_target_key text, p_target_args jsonb) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.record_investigation_result(v_patient_b, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'record_investigation_result(p_investigation_line_id uuid, p_result text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'record_investigation_result(p_investigation_line_id uuid, p_result text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.record_payment(v_invoice_b, NULL, 0::numeric, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'record_payment(p_invoice_id uuid, p_method payment_method, p_amount numeric, p_note text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'record_payment(p_invoice_id uuid, p_method payment_method, p_amount numeric, p_note text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.record_refund(v_invoice_b, NULL, 0::numeric, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'record_refund(p_invoice_id uuid, p_method payment_method, p_amount numeric, p_note text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'record_refund(p_invoice_id uuid, p_method payment_method, p_amount numeric, p_note text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.register_visit_attachment(v_visit_b, 'ct/b/file'::text, 'image/png'::text, 1024, 'ct'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'register_visit_attachment(p_visit_id uuid, p_file_path text, p_file_type text, p_size_bytes bigint, p_label text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'register_visit_attachment(p_visit_id uuid, p_file_path text, p_file_type text, p_size_bytes bigint, p_label text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.remove_invoice_item(v_patient_b, now());
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'remove_invoice_item(p_item_id uuid, p_expected_updated_at timestamp with time zone) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'remove_invoice_item(p_item_id uuid, p_expected_updated_at timestamp with time zone) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.reschedule_appointment(v_appt_b, now(), 30, now());
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'reschedule_appointment(p_appointment_id uuid, p_start_time timestamp with time zone, p_duration_minutes integer, p_end_time timestamp with time zone) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'reschedule_appointment(p_appointment_id uuid, p_start_time timestamp with time zone, p_duration_minutes integer, p_end_time timestamp with time zone) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.resolve_effective_service_price(v_service_b, v_branch_b, current_date);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'resolve_effective_service_price(p_service_id uuid, p_branch_id uuid, p_on_date date) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'resolve_effective_service_price(p_service_id uuid, p_branch_id uuid, p_on_date date) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.restore_patient(v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'restore_patient(p_patient_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'restore_patient(p_patient_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.save_visit_documentation(v_visit_b, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, now());
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'save_visit_documentation(p_visit_id uuid, p_complaint text, p_history text, p_examination text, p_diagnosis text, p_plan text, p_expected_updated_at timestamp with time zone) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'save_visit_documentation(p_visit_id uuid, p_complaint text, p_history text, p_examination text, p_diagnosis text, p_plan text, p_expected_updated_at timestamp with time zone) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.search_eligible_services(v_branch_b, 'cross-tenant-probe'::text, current_date, 50);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'search_eligible_services(p_branch_id uuid, p_query text, p_on_date date, p_limit integer) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'search_eligible_services(p_branch_id uuid, p_query text, p_on_date date, p_limit integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.search_investigations('cross-tenant-probe'::text, 50);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'search_investigations(p_query text, p_limit integer) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'search_investigations(p_query text, p_limit integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.search_medications('cross-tenant-probe'::text, 50);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'search_medications(p_query text, p_limit integer) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'search_medications(p_query text, p_limit integer) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.search_patients('cross-tenant-probe'::text, 'cross-tenant-probe'::text, v_branch_b, 50, 0, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'search_patients(p_query text, p_scope text, p_branch_id uuid, p_limit integer, p_offset integer, p_last_visit_filter text, p_sort_field text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'search_patients(p_query text, p_scope text, p_branch_id uuid, p_limit integer, p_offset integer, p_last_visit_filter text, p_sort_field text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.set_appointment_default_duration(30, v_branch_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'set_appointment_default_duration(p_duration_minutes integer, p_branch_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'set_appointment_default_duration(p_duration_minutes integer, p_branch_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.set_branch_active(v_branch_b, true);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'set_branch_active(p_branch_id uuid, p_is_active boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'set_branch_active(p_branch_id uuid, p_is_active boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.set_insurance_coverage(v_invoice_b, now(), v_insurance_b, 0::numeric);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'set_insurance_coverage(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_provider_id uuid, p_covered_amount numeric) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'set_insurance_coverage(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_provider_id uuid, p_covered_amount numeric) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.set_service_branch_assignment(v_service_b, ARRAY[v_branch_b]::uuid[], false);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'set_service_branch_assignment(p_service_id uuid, p_branch_ids uuid[], p_assign boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'set_service_branch_assignment(p_service_id uuid, p_branch_ids uuid[], p_assign boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.set_service_global_status(v_service_b, now(), 'active'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'set_service_global_status(p_service_id uuid, p_expected_updated_at timestamp with time zone, p_global_status text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'set_service_global_status(p_service_id uuid, p_expected_updated_at timestamp with time zone, p_global_status text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.set_service_promotion(v_service_b, v_branch_b, now(), 100::numeric, current_date, current_date);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'set_service_promotion(p_service_id uuid, p_branch_id uuid, p_expected_updated_at timestamp with time zone, p_promotion_price numeric, p_start_date date, p_end_date date) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'set_service_promotion(p_service_id uuid, p_branch_id uuid, p_expected_updated_at timestamp with time zone, p_promotion_price numeric, p_start_date date, p_end_date date) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.set_specialty_form_schema(jsonb_build_object('branch_id', v_branch_b::text, 'patient_id', v_patient_b::text));
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'set_specialty_form_schema(p_schema_json jsonb) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'set_specialty_form_schema(p_schema_json jsonb) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.set_staff_active(v_staff_b_only, true);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'set_staff_active(p_staff_member_id uuid, p_is_active boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'set_staff_active(p_staff_member_id uuid, p_is_active boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.setup_new_branch_services(v_branch_b, 'copy'::text, ARRAY[v_service_b]::uuid[], v_branch_b, 'copy'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'setup_new_branch_services(p_target_branch_id uuid, p_method text, p_service_ids uuid[], p_source_branch_id uuid, p_mode text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'setup_new_branch_services(p_target_branch_id uuid, p_method text, p_service_ids uuid[], p_source_branch_id uuid, p_mode text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.soft_delete_service(v_service_b, now());
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'soft_delete_service(p_service_id uuid, p_expected_updated_at timestamp with time zone) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'soft_delete_service(p_service_id uuid, p_expected_updated_at timestamp with time zone) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    -- Returns a set. No row is the existing denial; a row is a leak.
    IF EXISTS (
      SELECT 1 FROM public.staff_login_usernames(ARRAY[v_staff_b_only]::uuid[])
    ) THEN
      v_violations := array_append(v_violations, 'staff_login_usernames(p_staff_ids uuid[]) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'staff_login_usernames(p_staff_ids uuid[]) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.transfer_patient(v_patient_b, v_branch_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'transfer_patient(p_patient_id uuid, p_new_branch_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'transfer_patient(p_patient_id uuid, p_new_branch_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_appointment(v_appt_b, v_patient_b, v_staff_b_only, now(), 30, now(), 'probe'::text, v_branch_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_appointment(p_appointment_id uuid, p_patient_id uuid, p_doctor_id uuid, p_start_time timestamp with time zone, p_duration_minutes integer, p_end_time timestamp with time zone, p_notes text, p_branch_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_appointment(p_appointment_id uuid, p_patient_id uuid, p_doctor_id uuid, p_start_time timestamp with time zone, p_duration_minutes integer, p_end_time timestamp with time zone, p_notes text, p_branch_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_appointment_status(v_appt_b, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_appointment_status(p_appointment_id uuid, p_new_status text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_appointment_status(p_appointment_id uuid, p_new_status text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_billing_settings(false);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_billing_settings(p_allow_partial_payments boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_billing_settings(p_allow_partial_payments boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_branch(v_branch_b, 'Cross Tenant B'::text, jsonb_build_object('branch_id', v_branch_b::text, 'patient_id', v_patient_b::text), 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, '201062000099'::text, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_branch(p_branch_id uuid, p_name text, p_working_schedule jsonb, p_code text, p_address text, p_phone text, p_maps_url text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_branch(p_branch_id uuid, p_name text, p_working_schedule jsonb, p_code text, p_address text, p_phone text, p_maps_url text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_invoice_item(v_patient_b, now(), 'cross-tenant-probe'::text, 0::numeric, 100::numeric);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_invoice_item(p_item_id uuid, p_expected_updated_at timestamp with time zone, p_description text, p_quantity numeric, p_unit_price numeric) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_invoice_item(p_item_id uuid, p_expected_updated_at timestamp with time zone, p_description text, p_quantity numeric, p_unit_price numeric) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_organization('Cross Tenant B'::text, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, jsonb_build_object('branch_id', v_branch_b::text, 'patient_id', v_patient_b::text));
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_organization(p_name text, p_logo_url text, p_currency_code text, p_timezone text, p_settings_json jsonb) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_organization(p_name text, p_logo_url text, p_currency_code text, p_timezone text, p_settings_json jsonb) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_patient(v_patient_b, 'Cross Tenant B'::text, now(), '201062000099'::text, current_date, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'probe'::text, false, false, false, false, false);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_patient(p_patient_id uuid, p_full_name text, p_expected_updated_at timestamp with time zone, p_phone text, p_date_of_birth date, p_gender text, p_marital_status text, p_notes text, p_acknowledge_duplicate boolean, p_clear_gender boolean, p_clear_date_of_birth boolean, p_clear_marital_status boolean, p_clear_notes boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_patient(p_patient_id uuid, p_full_name text, p_expected_updated_at timestamp with time zone, p_phone text, p_date_of_birth date, p_gender text, p_marital_status text, p_notes text, p_acknowledge_duplicate boolean, p_clear_gender boolean, p_clear_date_of_birth boolean, p_clear_marital_status boolean, p_clear_notes boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_patient_allergy(v_patient_b, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_patient_allergy(p_allergy_id uuid, p_substance text, p_reaction text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_patient_allergy(p_allergy_id uuid, p_substance text, p_reaction text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_patient_chronic_condition(v_patient_b, 'Cross Tenant B'::text, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_patient_chronic_condition(p_condition_id uuid, p_name text, p_note text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_patient_chronic_condition(p_condition_id uuid, p_name text, p_note text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_patient_medication(v_patient_b, 'Cross Tenant B'::text, v_patient_b, 'cross-tenant-probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_patient_medication(p_medication_record_id uuid, p_name text, p_medication_id uuid, p_note text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_patient_medication(p_medication_record_id uuid, p_name text, p_medication_id uuid, p_note text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_role_permission('doctor'::public.staff_role, 'patients.view'::text, false);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_role_permission(p_role staff_role, p_permission_key text, p_is_granted boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_role_permission(p_role staff_role, p_permission_key text, p_is_granted boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_role_permissions(jsonb_build_object('branch_id', v_branch_b::text, 'patient_id', v_patient_b::text));
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_role_permissions(p_changes jsonb) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_role_permissions(p_changes jsonb) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_service(v_service_b, now(), 'Cross Tenant B'::text, 100::numeric, 'active'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_service(p_service_id uuid, p_expected_updated_at timestamp with time zone, p_name text, p_default_price numeric, p_global_status text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_service(p_service_id uuid, p_expected_updated_at timestamp with time zone, p_name text, p_default_price numeric, p_global_status text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_shift(v_shift_b, now(), current_date, '09:00'::time, '09:00'::time, 'probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_shift(p_shift_id uuid, p_expected_updated_at timestamp with time zone, p_shift_date date, p_start_time time without time zone, p_end_time time without time zone, p_notes text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_shift(p_shift_id uuid, p_expected_updated_at timestamp with time zone, p_shift_date date, p_start_time time without time zone, p_end_time time without time zone, p_notes text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_staff_member(v_staff_b_only, 'Cross Tenant B'::text, 'doctor'::public.staff_role, ARRAY[v_branch_b]::uuid[], '201062000099'::text, v_branch_b, true);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_staff_member(p_staff_member_id uuid, p_full_name text, p_role staff_role, p_branch_ids uuid[], p_phone text, p_primary_branch_id uuid, p_is_active boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_staff_member(p_staff_member_id uuid, p_full_name text, p_role staff_role, p_branch_ids uuid[], p_phone text, p_primary_branch_id uuid, p_is_active boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_treatment_plan(v_patient_b, 'Cross Tenant B'::text, v_patient_b, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'cross-tenant-probe'::text, 'probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_treatment_plan(p_treatment_plan_id uuid, p_medication_name text, p_medication_id uuid, p_dosage text, p_frequency text, p_duration text, p_notes text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_treatment_plan(p_treatment_plan_id uuid, p_medication_name text, p_medication_id uuid, p_dosage text, p_frequency text, p_duration text, p_notes text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_visit_investigation(v_patient_b, 'Cross Tenant B'::text, 'cross-tenant-probe'::text, v_patient_b, false);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_visit_investigation(p_investigation_line_id uuid, p_name text, p_note text, p_investigation_id uuid, p_clear_investigation_id boolean) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_visit_investigation(p_investigation_line_id uuid, p_name text, p_note text, p_investigation_id uuid, p_clear_investigation_id boolean) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.update_visit_vital_sign(v_patient_b, 'Cross Tenant B'::text, 'cross-tenant-probe'::text, 'mmHg'::text, v_patient_b);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'update_visit_vital_sign(p_vital_sign_id uuid, p_name text, p_value text, p_unit text, p_predefined_vital_sign_id uuid) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'update_visit_vital_sign(p_vital_sign_id uuid, p_name text, p_value text, p_unit text, p_predefined_vital_sign_id uuid) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;
  BEGIN
    v_rpc := public.void_invoice(v_invoice_b, now(), 'cross-tenant probe'::text);
    IF NOT pg_temp.cross_tenant_rpc_acceptable(v_rpc) THEN
      v_violations := array_append(v_violations, 'void_invoice(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_reason text) returned data');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF NOT pg_temp.cross_tenant_exception_acceptable(SQLSTATE, SQLERRM) THEN
        v_violations := array_append(v_violations, 'void_invoice(p_invoice_id uuid, p_expected_updated_at timestamp with time zone, p_reason text) raised ' || SQLSTATE || ': ' || left(SQLERRM, 120));
      END IF;
  END;

  v_snap_after := pg_temp.cross_tenant_b_snapshot();

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO cross_tenant_suite_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.2-02',
    cardinality(v_violations) = 0 AND v_snap_before = v_snap_after,
    CASE
      WHEN cardinality(v_violations) > 0 THEN array_to_string(v_violations, '; ')
      WHEN v_snap_before <> v_snap_after THEN 'B row snapshot changed'
      ELSE 'ok'
    END
  );
END;
$$;

-- E2E-P1.2-03 — direct reads by A return zero B rows
DO $$
DECLARE
  v_dual_user uuid;
  v_staff_dual uuid;
  v_staff_b_only uuid;
  v_staff_nomember uuid;
  v_org_a uuid;
  v_org_b uuid;
  v_branch_a uuid;
  v_branch_b uuid;
  v_count int;
  v_org_count int;
  v_table regclass;
  v_leak text;
  v_leaks text[] := ARRAY[]::text[];
BEGIN
  SELECT dual_user_id, staff_dual, staff_b_only, staff_nomember, org_a, org_b, branch_a, branch_b
  INTO v_dual_user, v_staff_dual, v_staff_b_only, v_staff_nomember, v_org_a, v_org_b, v_branch_a, v_branch_b
  FROM cross_tenant_fixture;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM public.set_active_organization(v_org_a);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);

  FOREACH v_table IN ARRAY ARRAY[
    'public.ai_accepted_output'::regclass,
    'public.app_settings'::regclass,
    'public.appointments'::regclass,
    'public.audit_log'::regclass,
    'public.branches'::regclass,
    'public.insurance_providers'::regclass,
    'public.investigations'::regclass,
    'public.invoice_items'::regclass,
    'public.invoice_number_sequences'::regclass,
    'public.invoices'::regclass,
    'public.medications'::regclass,
    'public.organization_billing_settings'::regclass,
    'public.patient_allergies'::regclass,
    'public.patient_chronic_conditions'::regclass,
    'public.patient_medications'::regclass,
    'public.patients'::regclass,
    'public.payments'::regclass,
    'public.predefined_vital_signs'::regclass,
    'public.roles_permissions'::regclass,
    'public.service_branches'::regclass,
    'public.services'::regclass,
    'public.shift_assignments'::regclass,
    'public.shifts'::regclass,
    'public.subscription_cache'::regclass,
    'public.treatment_plans'::regclass,
    'public.visit_attachments'::regclass,
    'public.visit_clinical_notes'::regclass,
    'public.visit_investigations'::regclass,
    'public.visit_vital_signs'::regclass,
    'public.visits'::regclass,
    'ai_internal.ai_token_issuance'::regclass
  ]
  LOOP
    v_leak := pg_temp.cross_tenant_org_leak(v_table, v_org_b, false);
    IF v_leak IS NOT NULL THEN
      v_leaks := array_append(v_leaks, v_leak);
    END IF;
    PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
  END LOOP;

  v_leak := pg_temp.cross_tenant_org_leak('ai_internal.membership'::regclass, v_org_b, true);
  IF v_leak IS NOT NULL THEN
    v_leaks := array_append(v_leaks, v_leak);
  END IF;
  v_leak := pg_temp.cross_tenant_org_leak('ai_internal.user_active_organization'::regclass, v_org_b, true);
  IF v_leak IS NOT NULL THEN
    v_leaks := array_append(v_leaks, v_leak);
  END IF;
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_org_count
  FROM public.organizations
  WHERE id = v_org_b AND is_deleted = false;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
  SELECT count(*) INTO v_count FROM public.organizations WHERE id = v_org_b;
  IF v_org_count = 0 THEN
    v_leaks := array_append(v_leaks, 'organizations has no organisation B row');
  ELSIF v_count > 0 THEN
    v_leaks := array_append(v_leaks, 'organizations=' || v_count::text);
  END IF;

  SELECT count(*) INTO v_count FROM public.staff_members WHERE id = v_staff_b_only;
  IF v_count > 0 THEN
    v_leaks := array_append(v_leaks, 'staff_members=' || v_count::text);
  END IF;

  SELECT count(*) INTO v_count FROM public.staff_members WHERE id = v_staff_nomember;
  IF v_count > 0 THEN
    v_leaks := array_append(v_leaks, 'staff_members_nomember=' || v_count::text);
  END IF;

  SELECT count(*) INTO v_count FROM public.staff_members WHERE id = v_staff_dual;
  IF v_count <> 1 THEN
    v_leaks := array_append(v_leaks, 'staff_members_active=' || v_count::text);
  END IF;

  SELECT count(*) INTO v_count
  FROM public.staff_branch_assignments
  WHERE staff_member_id = v_staff_nomember
    AND branch_id = v_branch_a
    AND is_deleted = false;
  IF v_count > 0 THEN
    v_leaks := array_append(v_leaks, 'staff_branch_assignments_nomember=' || v_count::text);
  END IF;

  SELECT count(*) INTO v_count
  FROM public.staff_branch_assignments
  WHERE branch_id = v_branch_b
    AND is_deleted = false;
  IF v_count > 0 THEN
    v_leaks := array_append(v_leaks, 'staff_branch_assignments=' || v_count::text);
  END IF;

  SELECT count(*) INTO v_count
  FROM public.staff_branch_assignments
  WHERE staff_member_id = v_staff_dual
    AND branch_id = v_branch_a
    AND is_deleted = false;
  IF v_count <> 1 THEN
    v_leaks := array_append(v_leaks, 'staff_branch_assignments_active=' || v_count::text);
  END IF;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO cross_tenant_suite_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.2-03',
    cardinality(v_leaks) = 0,
    CASE
      WHEN cardinality(v_leaks) = 0 THEN 'ok'
      ELSE array_to_string(v_leaks, '; ')
    END
  );
END;
$$;

-- E2E-P1.2-04 — dual-membership user sees only the active org
DO $$
DECLARE
  v_dual_user uuid;
  v_staff_dual uuid;
  v_staff_b_only uuid;
  v_staff_nomember uuid;
  v_org_a uuid;
  v_branch_a uuid;
  v_branch_b uuid;
  v_set public.rpc_result;
  v_staff_b_count int;
  v_staff_nomember_count int;
  v_staff_active_count int;
  v_assign_b_count int;
  v_assign_nomember_count int;
  v_assign_active_count int;
  v_branch_b_in_jwt boolean;
BEGIN
  SELECT dual_user_id, staff_dual, staff_b_only, staff_nomember, org_a, branch_a, branch_b
  INTO v_dual_user, v_staff_dual, v_staff_b_only, v_staff_nomember, v_org_a, v_branch_a, v_branch_b
  FROM cross_tenant_fixture;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_dual_user::text, 'role', 'authenticated')::text,
    true
  );
  v_set := public.set_active_organization(v_org_a);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
  v_branch_b_in_jwt := v_branch_b = ANY (public.jwt_branch_ids());

  SELECT count(*) INTO v_staff_b_count
  FROM public.staff_members
  WHERE id = v_staff_b_only AND is_deleted = false;

  SELECT count(*) INTO v_staff_nomember_count
  FROM public.staff_members
  WHERE id = v_staff_nomember AND is_deleted = false;

  SELECT count(*) INTO v_staff_active_count
  FROM public.staff_members
  WHERE id = v_staff_dual AND is_deleted = false;

  SELECT count(*) INTO v_assign_b_count
  FROM public.staff_branch_assignments
  WHERE staff_member_id = v_staff_dual
    AND branch_id = v_branch_b
    AND is_deleted = false;

  SELECT count(*) INTO v_assign_nomember_count
  FROM public.staff_branch_assignments
  WHERE staff_member_id = v_staff_nomember
    AND branch_id = v_branch_a
    AND is_deleted = false;

  SELECT count(*) INTO v_assign_active_count
  FROM public.staff_branch_assignments
  WHERE staff_member_id = v_staff_dual
    AND branch_id = v_branch_a
    AND is_deleted = false;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO cross_tenant_suite_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.2-04',
    v_set.success
      AND NOT v_branch_b_in_jwt
      AND v_staff_b_count = 0
      AND v_staff_nomember_count = 0
      AND v_staff_active_count = 1
      AND v_assign_b_count = 0
      AND v_assign_nomember_count = 0
      AND v_assign_active_count = 1,
    'set_active=' || COALESCE(v_set.success::text, '<null>')
      || ' branch_b_in_jwt=' || v_branch_b_in_jwt::text
      || ' staff_b=' || v_staff_b_count::text
      || ' staff_nomember=' || v_staff_nomember_count::text
      || ' staff_active=' || v_staff_active_count::text
      || ' assign_b=' || v_assign_b_count::text
      || ' assign_nomember=' || v_assign_nomember_count::text
      || ' assign_active=' || v_assign_active_count::text
  );
END;
$$;

-- E2E-P1.2-05 — AI RPCs write organization_id = current_org_id()
DO $$
DECLARE
  v_dual_user uuid;
  v_org_a uuid;
  v_org_b uuid;
  v_staff_dual uuid;
  v_visit_b uuid;
  v_branch_b uuid;
  v_note_ts timestamptz := '2026-10-02T10:00:00+00';
  v_current uuid;
  v_accept public.rpc_result;
  v_token text;
  v_payload jsonb;
  v_accept_org uuid;
  v_token_org text;
  v_jti uuid;
  v_issuance_org uuid;
  v_other_org_rows int := -1;
  v_own_org_rows int := -1;
  v_passed boolean := false;
  v_detail text;
BEGIN
  SELECT dual_user_id, org_a, org_b, staff_dual, visit_b, branch_b
  INTO v_dual_user, v_org_a, v_org_b, v_staff_dual, v_visit_b, v_branch_b
  FROM cross_tenant_fixture;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_dual_user::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM public.set_active_organization(v_org_b);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
  v_current := public.current_org_id();

  v_accept := public.record_ai_acceptance(
    'B1C2-D3E4',
    'visit_clinical_notes',
    jsonb_build_object(
      'p_visit_id', v_visit_b,
      'p_complaint', 'cross-tenant probe',
      'p_expected_updated_at', v_note_ts
    )
  );

  PERFORM set_config('role', 'postgres', true);
  SELECT a.organization_id INTO v_accept_org
  FROM public.ai_accepted_output a
  WHERE a.table_name = 'visit_clinical_notes'
    AND a.ai_request_reference = 'B1C2-D3E4'
  ORDER BY a.accepted_at DESC
  LIMIT 1;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
  BEGIN
    v_token := public.issue_ai_token(1);
    v_payload := pg_temp.decode_jws_payload(v_token);
    v_token_org := v_payload ->> 'org';
    v_jti := (v_payload ->> 'jti')::uuid;
  EXCEPTION
    WHEN OTHERS THEN
      v_token_org := '<error:' || left(SQLERRM, 80) || '>';
  END;

  IF v_jti IS NOT NULL THEN
    PERFORM set_config('role', 'postgres', true);
    SELECT organization_id INTO v_issuance_org
    FROM ai_internal.ai_token_issuance
    WHERE jti = v_jti;

    PERFORM set_config('role', 'authenticated', true);
    PERFORM pg_temp.cross_tenant_refresh_session(v_dual_user);
    SELECT count(*) INTO v_other_org_rows
    FROM ai_internal.ai_token_issuance
    WHERE organization_id = v_org_a
      AND is_deleted = false;
    SELECT count(*) INTO v_own_org_rows
    FROM ai_internal.ai_token_issuance
    WHERE organization_id = v_current
      AND is_deleted = false;
  END IF;

  v_passed := v_accept.success
    AND v_accept_org = v_current
    AND v_token_org = v_current::text
    AND v_issuance_org = v_current
    AND v_other_org_rows = 0
    AND v_own_org_rows >= 1;

  v_detail := 'current_org=' || COALESCE(v_current::text, '<null>')
    || ' accept_org=' || COALESCE(v_accept_org::text, '<null>')
    || ' token_org=' || COALESCE(v_token_org, '<null>')
    || ' issuance_org=' || COALESCE(v_issuance_org::text, '<null>')
    || ' other_org_rows=' || v_other_org_rows::text
    || ' own_org_rows=' || v_own_org_rows::text;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO cross_tenant_suite_results (test_name, passed, detail)
  VALUES ('E2E-P1.2-05', v_passed, v_detail);
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures
  FROM cross_tenant_suite_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'cross_tenant_suite failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM cross_tenant_suite_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail
FROM cross_tenant_suite_results
ORDER BY test_name;
