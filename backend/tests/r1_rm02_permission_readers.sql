-- RM02 (R1-SQL-04, R1-SQL-05) — backend org-scoped permission readers
-- completion checks.
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/r1_rm02_permission_readers.sql

BEGIN;

CREATE TEMP TABLE r1_rm02_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

-- Session helper: JWT claims carrying sub, organization_id, branch_ids and the
-- staff_role claim (fresh or stale) exactly like production tokens.
CREATE OR REPLACE FUNCTION pg_temp.r2_set_session(
  p_user_id uuid,
  p_org_id uuid,
  p_branch_ids uuid[] DEFAULT ARRAY[]::uuid[],
  p_staff_role public.staff_role DEFAULT 'doctor'
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'organization_id', COALESCE(p_org_id::text, ''),
      'branch_ids', COALESCE(array_to_string(p_branch_ids::text[], ','), ''),
      'staff_role', p_staff_role::text
    )::text,
    true
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Shared fixture. UUID space 1b…: disjoint from the RM01 1a… fixtures.
--   U1 1b03…01 — staff role administrator (global), membership administrator
--                in A, doctor in B            (R1-SQL-04 subject)
--   U2 1b03…02 — staff role doctor (global compatibility role), membership
--                administrator in B            (member administrator B)
--   U3 1b03…03 — staff role doctor, membership doctor in A and B
--                (R1-SQL-05 reader subject: A denies, B grants)
--   U4 1b03…04 — staff role administrator, membership administrator in A
--   U5 1b03…05 — staff role administrator, bootstrap flag, membership doctor
--                in A                          (bootstrap bypass subject)
--   U6 1b03…06 — staff role administrator, membership doctor in A only
--                (global-role substitution subject)
-- Org A denies the tested doctor keys; org B grants them (the same role), so
-- the pre-fix global-role readers borrowed B's grants inside an A session.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_u1 uuid := '1b030000-0000-4000-8000-000000000001';
  v_u2 uuid := '1b030000-0000-4000-8000-000000000002';
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_u5 uuid := '1b030000-0000-4000-8000-000000000005';
  v_u6 uuid := '1b030000-0000-4000-8000-000000000006';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_branch_b uuid := '1b020000-0000-4000-8000-000000000002';
  v_branch_b2 uuid := '1b020000-0000-4000-8000-000000000003';
  v_key text;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  -- Idempotent cleanup from earlier runs of this file.
  DELETE FROM public.audit_log WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.roles_permissions WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.payments WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.invoices WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.shifts WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.service_branches WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.services WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.insurance_providers WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.visits WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.appointments WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.patients WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_branch_assignments WHERE branch_id IN (
    SELECT id FROM public.branches WHERE organization_id IN (v_org_a, v_org_b)
  );
  DELETE FROM ai_internal.membership WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM ai_internal.user_active_organization WHERE organization_id IN (v_org_a, v_org_b)
    OR user_id IN (v_u1, v_u2, v_u3, v_u4, v_u5, v_u6);
  DELETE FROM public.branches WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_members WHERE auth_user_id IN (v_u1, v_u2, v_u3, v_u4, v_u5, v_u6)
    OR full_name LIKE 'R1 RM02%';
  DELETE FROM auth.users WHERE id IN (v_u1, v_u2, v_u3, v_u4, v_u5, v_u6)
    OR email LIKE 'r1-rm02-%';

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  SELECT
    u.id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    u.email,
    extensions.crypt('pw-r1-rm02', extensions.gen_salt('bf')),
    now(), now(), now()
  FROM (VALUES
    (v_u1, 'r1-rm02-u1'),
    (v_u2, 'r1-rm02-u2'),
    (v_u3, 'r1-rm02-u3'),
    (v_u4, 'r1-rm02-u4'),
    (v_u5, 'r1-rm02-u5'),
    (v_u6, 'r1-rm02-u6')
  ) AS u(id, email);

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'R1 RM02 Org A', v_u4, v_u4),
    (v_org_b, 'R1 RM02 Org B', v_u4, v_u4);

  INSERT INTO public.branches (id, organization_id, name, code, is_active, created_by, updated_by)
  VALUES
    (v_branch_a,  v_org_a, 'R1 RM02 Main A',  'R2A',  true, v_u4, v_u4),
    (v_branch_b,  v_org_b, 'R1 RM02 Main B',  'R2B',  true, v_u4, v_u4),
    (v_branch_b2, v_org_b, 'R1 RM02 Second B','R2B2', true, v_u4, v_u4);

  INSERT INTO public.staff_members (
    id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by
  )
  VALUES
    ('1b040000-0000-4000-8000-000000000001', v_u1, 'R1 RM02 U1', 'administrator', false, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000002', v_u2, 'R1 RM02 U2', 'doctor',         false, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000003', v_u3, 'R1 RM02 U3', 'doctor',         false, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000004', v_u4, 'R1 RM02 U4', 'administrator',  false, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000005', v_u5, 'R1 RM02 U5', 'administrator',  true,  v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000006', v_u6, 'R1 RM02 U6', 'administrator',  false, v_u4, v_u4);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    ('1b040000-0000-4000-8000-000000000001', v_branch_a, true, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000002', v_branch_b, true, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000003', v_branch_a, true, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000004', v_branch_a, true, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000005', v_branch_a, true, v_u4, v_u4),
    ('1b040000-0000-4000-8000-000000000006', v_branch_a, true, v_u4, v_u4);

  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES
    (v_u1, v_org_a, 'administrator'),
    (v_u1, v_org_b, 'doctor'),
    (v_u2, v_org_b, 'administrator'),
    (v_u3, v_org_a, 'doctor'),
    (v_u3, v_org_b, 'doctor'),
    (v_u4, v_org_a, 'administrator'),
    (v_u5, v_org_a, 'doctor'),
    (v_u6, v_org_a, 'doctor');

  INSERT INTO ai_internal.user_active_organization (user_id, organization_id)
  VALUES
    (v_u1, v_org_a),
    (v_u2, v_org_b),
    (v_u3, v_org_a),
    (v_u4, v_org_a),
    (v_u5, v_org_a),
    (v_u6, v_org_a);

  -- Permission matrix. Organization inserts auto-seed the default matrix
  -- (tenant scoping trigger), so upsert every row this suite depends on.
  -- Org A: the tested doctor keys are explicitly denied; org B grants the same
  -- role the same keys (the cross-tenant grant the pre-fix readers borrowed).
  FOR v_key IN
    SELECT unnest(ARRAY[
      'appointments.create', 'appointments.cancel', 'appointments.read',
      'invoices.view', 'payments.record', 'invoices.create',
      'services.view', 'services.manage', 'insurance.manage',
      'patients.create', 'patients.edit', 'patients.view',
      'shifts.manage', 'visits.create', 'visits.edit_soap',
      'visits.upload_attachment'
    ])
  LOOP
    INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
    VALUES (v_org_a, 'doctor', v_key, false, v_u4, v_u4)
    ON CONFLICT (organization_id, role, permission_key) DO UPDATE
      SET is_granted = false, is_deleted = false, updated_at = now(),
          created_by = v_u4, updated_by = v_u4;

    INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
    VALUES (v_org_b, 'doctor', v_key, true, v_u4, v_u4)
    ON CONFLICT (organization_id, role, permission_key) DO UPDATE
      SET is_granted = true, is_deleted = false, updated_at = now(),
          created_by = v_u4, updated_by = v_u4;
  END LOOP;

  -- settings.manage_staff stays denied for doctor in both orgs.
  INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
  VALUES
    (v_org_a, 'doctor', 'settings.manage_staff', false, v_u4, v_u4),
    (v_org_b, 'doctor', 'settings.manage_staff', false, v_u4, v_u4)
  ON CONFLICT (organization_id, role, permission_key) DO UPDATE
    SET is_granted = false, is_deleted = false, updated_at = now(),
        created_by = v_u4, updated_by = v_u4;

  -- Administrator rows used by the A/B administrator sessions.
  INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
  VALUES
    (v_org_a, 'administrator', 'settings.manage_staff', true, v_u4, v_u4),
    (v_org_a, 'administrator', 'services.view',         true, v_u4, v_u4),
    (v_org_a, 'administrator', 'invoices.view',         true, v_u4, v_u4),
    (v_org_a, 'administrator', 'patients.view',         true, v_u4, v_u4),
    (v_org_b, 'administrator', 'settings.manage_staff', true, v_u4, v_u4)
  ON CONFLICT (organization_id, role, permission_key) DO UPDATE
    SET is_granted = true, is_deleted = false, updated_at = now(),
        created_by = v_u4, updated_by = v_u4;

  -- Org A records the readers touch.
  INSERT INTO public.patients (
    id, branch_id, organization_id, full_name, phone, mrn, created_by, updated_by
  )
  VALUES (
    '1b050000-0000-4000-8000-000000000001',
    v_branch_a, v_org_a,
    'R1 RM02 Patient A', '2020000001a1', 'MRN-R1RM02A', v_u4, v_u4
  );

  INSERT INTO public.appointments (
    id, branch_id, organization_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES (
    '1b060000-0000-4000-8000-000000000001',
    v_branch_a, v_org_a, '1b050000-0000-4000-8000-000000000001',
    '1b040000-0000-4000-8000-000000000003',
    now() + interval '1 day', now() + interval '1 day 30 minutes',
    'planned', 'scheduled', v_u4, v_u4
  );

  INSERT INTO public.visits (
    id, branch_id, organization_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES (
    '1b070000-0000-4000-8000-000000000001',
    v_branch_a, v_org_a, '1b060000-0000-4000-8000-000000000001',
    '1b050000-0000-4000-8000-000000000001',
    '1b040000-0000-4000-8000-000000000003',
    current_date, 'in_progress', v_u4, v_u4
  );

  INSERT INTO public.services (
    id, organization_id, name, default_price, global_status, created_by, updated_by
  )
  VALUES
    ('1b080000-0000-4000-8000-000000000001', v_org_a, 'R1 RM02 Service A', 100, 'active', v_u4, v_u4),
    ('1b080000-0000-4000-8000-000000000002', v_org_b, 'R1 RM02 Service B', 200, 'active', v_u4, v_u4);

  INSERT INTO public.service_branches (
    service_id, branch_id, status, organization_id, created_by, updated_by
  )
  VALUES
    ('1b080000-0000-4000-8000-000000000001', v_branch_a, 'active', v_org_a, v_u4, v_u4),
    ('1b080000-0000-4000-8000-000000000002', v_branch_b, 'active', v_org_b, v_u4, v_u4);

  INSERT INTO public.insurance_providers (
    id, organization_id, name, is_active, created_by, updated_by
  )
  VALUES
    ('1b090000-0000-4000-8000-000000000001', v_org_a, 'R1 RM02 Insurance A', true, v_u4, v_u4),
    ('1b090000-0000-4000-8000-000000000002', v_org_b, 'R1 RM02 Insurance B', true, v_u4, v_u4);

  INSERT INTO public.invoices (
    id, branch_id, organization_id, patient_id, visit_id, status, currency, created_by, updated_by
  )
  VALUES (
    '1b0a0000-0000-4000-8000-000000000001',
    v_branch_a, v_org_a, '1b050000-0000-4000-8000-000000000001',
    '1b070000-0000-4000-8000-000000000001',
    'draft', 'EGP', v_u4, v_u4
  );

  INSERT INTO public.payments (
    id, invoice_id, branch_id, method, amount, recorded_by, organization_id, created_by
  )
  VALUES (
    '1b0b0000-0000-4000-8000-000000000001',
    '1b0a0000-0000-4000-8000-000000000001',
    v_branch_a, 'cash', 10,
    '1b040000-0000-4000-8000-000000000003',
    v_org_a, v_u4
  );

  INSERT INTO public.shifts (
    id, branch_id, organization_id, shift_date, start_time, end_time, created_by, updated_by
  )
  VALUES (
    '1b0c0000-0000-4000-8000-000000000001',
    v_branch_a, v_org_a, current_date, '09:00'::time, '17:00'::time, v_u4, v_u4
  );

  INSERT INTO public.organization_billing_settings (organization_id)
  VALUES (v_org_a)
  ON CONFLICT (organization_id) DO NOTHING;

  INSERT INTO r1_rm02_results VALUES ('fixture_setup', true, 'orgs, staff, memberships, permissions and records ready');
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-04 — global staff administrator with membership doctor in B cannot
-- exercise B's administrator authority.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_u1 uuid := '1b030000-0000-4000-8000-000000000001';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
  v_branch_b uuid := '1b020000-0000-4000-8000-000000000002';
  v_before boolean;
  v_after boolean;
  v_single public.rpc_result;
  v_bulk public.rpc_result;
  v_single_stale public.rpc_result;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT rp.is_granted INTO v_before
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor' AND rp.permission_key = 'services.view'
    AND rp.is_deleted = false;

  -- Fresh staff-role claim (matches the global staff role 'administrator').
  PERFORM pg_temp.r2_set_session(v_u1, v_org_b, ARRAY[v_branch_b], 'administrator');
  v_single := public.update_role_permission('doctor', 'services.view', NOT v_before);
  v_bulk := public.update_role_permissions(
    jsonb_build_array(
      jsonb_build_object('role', 'doctor', 'permission_key', 'services.view', 'is_granted', NOT v_before)
    )
  );

  -- Stale staff-role claim ('doctor'): the claim is never the boundary.
  PERFORM pg_temp.r2_set_session(v_u1, v_org_b, ARRAY[v_branch_b], 'doctor');
  v_single_stale := public.update_role_permission('doctor', 'services.view', NOT v_before);

  PERFORM set_config('role', 'postgres', true);
  SELECT rp.is_granted INTO v_after
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor' AND rp.permission_key = 'services.view'
    AND rp.is_deleted = false;

  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-04: global staff administrator with membership doctor in B cannot edit B role permissions',
    NOT v_single.success AND v_single.error_code = 'FORBIDDEN'
      AND NOT v_bulk.success AND v_bulk.error_code = 'FORBIDDEN'
      AND NOT v_single_stale.success AND v_single_stale.error_code = 'FORBIDDEN'
      AND v_after IS NOT DISTINCT FROM v_before,
    'single=' || COALESCE(v_single.error_code, 'ok')
      || ' bulk=' || COALESCE(v_bulk.error_code, 'ok')
      || ' stale_claim_single=' || COALESCE(v_single_stale.error_code, 'ok')
      || ' b_matrix_unchanged=' || (v_after IS NOT DISTINCT FROM v_before)::text
  );
END;
$$;

DO $$
DECLARE
  v_u1 uuid := '1b030000-0000-4000-8000-000000000001';
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
  v_branch_b uuid := '1b020000-0000-4000-8000-000000000002';
  v_staff_u3 uuid := '1b040000-0000-4000-8000-000000000003';
  v_create public.rpc_result;
  v_reset public.rpc_result;
  v_set_active public.rpc_result;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u1, v_org_b, ARRAY[v_branch_b], 'administrator');
  v_create := public.create_staff_account(
    'r2_rm02_probe', 'Rm02Probe', 'R1 RM02 Probe', 'doctor', ARRAY[v_branch_b]
  );
  v_reset := public.admin_reset_staff_password(v_staff_u3, 'Rm02Probe2');
  v_set_active := public.set_staff_active(v_staff_u3, true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-04: global staff administrator with membership doctor in B cannot invoke B administrator-only provisioning',
    NOT v_create.success AND v_create.error_code = 'FORBIDDEN'
      AND NOT v_reset.success AND v_reset.error_code = 'FORBIDDEN'
      AND NOT v_set_active.success AND v_set_active.error_code = 'FORBIDDEN',
    'create_staff=' || COALESCE(v_create.error_code, 'ok')
      || ' reset_password=' || COALESCE(v_reset.error_code, 'ok')
      || ' set_staff_active=' || COALESCE(v_set_active.error_code, 'ok')
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-04 — member administrator B stays authorized; A keeps authority; the
-- bootstrap flag cannot bypass an existing org; NULL membership role denies.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_u2 uuid := '1b030000-0000-4000-8000-000000000002';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
  v_branch_b uuid := '1b020000-0000-4000-8000-000000000002';
  v_before boolean;
  v_single public.rpc_result;
  v_create public.rpc_result;
  v_created_staff uuid;
  v_created_user uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT rp.is_granted INTO v_before
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor' AND rp.permission_key = 'services.view'
    AND rp.is_deleted = false;

  -- Global compatibility role is 'doctor'; the B membership role is
  -- administrator, so B's authority works regardless of the global role.
  PERFORM pg_temp.r2_set_session(v_u2, v_org_b, ARRAY[v_branch_b], 'doctor');
  v_single := public.update_role_permission('doctor', 'services.view', NOT v_before);
  v_create := public.create_staff_account(
    'r2_rm02_member', 'Rm02Member', 'R1 RM02 Member Probe', 'doctor', ARRAY[v_branch_b]
  );

  PERFORM set_config('role', 'postgres', true);
  -- Restore the flipped permission row directly (the postgres session has no
  -- JWT staff context, so the guarded RPC is not usable for the restore).
  UPDATE public.roles_permissions
  SET is_granted = v_before, updated_at = now(), updated_by = v_u2
  WHERE organization_id = v_org_b
    AND role = 'doctor' AND permission_key = 'services.view';
  IF v_create.success AND v_create.data ? 'staff_member_id' THEN
    v_created_staff := (v_create.data ->> 'staff_member_id')::uuid;
    SELECT sm.auth_user_id INTO v_created_user
    FROM public.staff_members sm WHERE sm.id = v_created_staff;
    DELETE FROM public.staff_branch_assignments WHERE staff_member_id = v_created_staff;
    DELETE FROM ai_internal.membership
    WHERE user_id = v_created_user AND organization_id = v_org_b;
    DELETE FROM ai_internal.user_active_organization WHERE user_id = v_created_user;
    DELETE FROM public.staff_members WHERE id = v_created_staff;
    DELETE FROM auth.users WHERE id = v_created_user;
  END IF;
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-04: membership administrator in B stays authorized regardless of the global compatibility role',
    v_single.success AND v_create.success AND v_create.data ? 'staff_member_id',
    'update_role_permission=' || COALESCE(v_single.error_code, 'ok')
      || ' create_staff=' || COALESCE(v_create.error_code, 'ok')
      || ' created=' || COALESCE(v_create.data ->> 'staff_member_id', '<none>')
  );
END;
$$;

DO $$
DECLARE
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_staff_u3 uuid := '1b040000-0000-4000-8000-000000000003';
  v_before_a boolean;
  v_after_a boolean;
  v_before_b boolean;
  v_after_b boolean;
  v_single public.rpc_result;
  v_set_active public.rpc_result;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT rp.is_granted INTO v_before_a
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_a
    AND rp.role = 'doctor' AND rp.permission_key = 'services.view'
    AND rp.is_deleted = false;
  SELECT rp.is_granted INTO v_before_b
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor' AND rp.permission_key = 'services.view'
    AND rp.is_deleted = false;

  PERFORM pg_temp.r2_set_session(v_u4, v_org_a, ARRAY[v_branch_a], 'administrator');
  v_single := public.update_role_permission('doctor', 'services.view', NOT v_before_a);
  v_set_active := public.set_staff_active(v_staff_u3, true);

  PERFORM set_config('role', 'postgres', true);
  SELECT rp.is_granted INTO v_after_a
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_a
    AND rp.role = 'doctor' AND rp.permission_key = 'services.view'
    AND rp.is_deleted = false;
  SELECT rp.is_granted INTO v_after_b
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org_b
    AND rp.role = 'doctor' AND rp.permission_key = 'services.view'
    AND rp.is_deleted = false;

  -- Restore the flipped A row directly (the postgres session has no JWT staff
  -- context, so the guarded RPC is not usable for the restore).
  UPDATE public.roles_permissions
  SET is_granted = v_before_a, updated_at = now(), updated_by = v_u4
  WHERE organization_id = v_org_a
    AND role = 'doctor' AND permission_key = 'services.view';
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-04: membership administrator in A keeps authority in A and B stays unchanged',
    v_single.success
      AND v_set_active.success
      AND v_after_a IS DISTINCT FROM v_before_a
      AND v_after_b IS NOT DISTINCT FROM v_before_b,
    'update_role_permission=' || COALESCE(v_single.error_code, 'ok')
      || ' set_staff_active=' || COALESCE(v_set_active.error_code, 'ok')
      || ' a_flipped=' || (v_after_a IS DISTINCT FROM v_before_a)::text
      || ' b_unchanged=' || (v_after_b IS NOT DISTINCT FROM v_before_b)::text
  );
END;
$$;

DO $$
DECLARE
  v_u5 uuid := '1b030000-0000-4000-8000-000000000005';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_single public.rpc_result;
  v_create public.rpc_result;
BEGIN
  -- Bootstrap flag with an existing organization and a doctor membership:
  -- no bypass.
  PERFORM pg_temp.r2_set_session(v_u5, v_org_a, ARRAY[v_branch_a], 'administrator');
  v_single := public.update_role_permission('doctor', 'services.view', true);
  v_create := public.create_staff_account(
    'r2_rm02_boot', 'Rm02Boot', 'R1 RM02 Boot Probe', 'doctor', ARRAY[v_branch_a]
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-04: bootstrap flag does not bypass an existing organization''s membership role',
    NOT v_single.success AND v_single.error_code = 'FORBIDDEN'
      AND NOT v_create.success AND v_create.error_code = 'FORBIDDEN',
    'update_role_permission=' || COALESCE(v_single.error_code, 'ok')
      || ' create_staff=' || COALESCE(v_create.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
  v_branch_b uuid := '1b020000-0000-4000-8000-000000000002';
  v_staff_u3 uuid := '1b040000-0000-4000-8000-000000000003';
  v_service_a uuid := '1b080000-0000-4000-8000-000000000001';
  v_single public.rpc_result;
  v_reset public.rpc_result;
  v_set_active public.rpc_result;
  v_get_service public.rpc_result;
BEGIN
  -- U4 holds a membership only in A but claims org B: no membership context,
  -- so current_org_id()/current_membership_role() are NULL and every
  -- authority check and org-scoped reader denies.
  PERFORM pg_temp.r2_set_session(v_u4, v_org_b, ARRAY[v_branch_b], 'administrator');
  v_single := public.update_role_permission('doctor', 'services.view', true);
  v_reset := public.admin_reset_staff_password(v_staff_u3, 'Rm02Probe3');
  v_set_active := public.set_staff_active(v_staff_u3, true);
  v_get_service := public.get_service(v_service_a);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-04: NULL membership role denies authority checks and org-scoped readers',
    NOT v_single.success AND v_single.error_code = 'FORBIDDEN'
      AND NOT v_reset.success AND v_reset.error_code = 'FORBIDDEN'
      AND NOT v_set_active.success AND v_set_active.error_code = 'FORBIDDEN'
      AND NOT v_get_service.success AND v_get_service.error_code = 'FORBIDDEN',
    'update_role_permission=' || COALESCE(v_single.error_code, 'ok')
      || ' reset_password=' || COALESCE(v_reset.error_code, 'ok')
      || ' set_staff_active=' || COALESCE(v_set_active.error_code, 'ok')
      || ' get_service=' || COALESCE(v_get_service.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_u1 uuid := '1b030000-0000-4000-8000-000000000001';
  v_u2 uuid := '1b030000-0000-4000-8000-000000000002';
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_branch_b uuid := '1b020000-0000-4000-8000-000000000002';
  v_branch_b2 uuid := '1b020000-0000-4000-8000-000000000003';
  v_admin_b2_fallback boolean;
  v_member_admin_b2 boolean;
  v_assigned_own boolean;
  v_assigned_other boolean;
BEGIN
  -- Global/JWT staff-role administrator with membership doctor in B: the
  -- second-branch administrator fallback is gone.
  PERFORM pg_temp.r2_set_session(v_u1, v_org_b, ARRAY[v_branch_b], 'administrator');
  SELECT auth_internal.staff_can_access_branch(v_branch_b2) INTO v_admin_b2_fallback;

  -- Membership administrator in B (staff-role claim 'doctor'): the fallback
  -- works through the membership role.
  PERFORM pg_temp.r2_set_session(v_u2, v_org_b, ARRAY[v_branch_b], 'doctor');
  SELECT auth_internal.staff_can_access_branch(v_branch_b2) INTO v_member_admin_b2;

  -- Assigned-branch path preserved for an ordinary member in A.
  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  SELECT auth_internal.staff_can_access_branch(v_branch_a) INTO v_assigned_own;
  SELECT auth_internal.staff_can_access_branch(v_branch_b2) INTO v_assigned_other;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-04: staff_can_access_branch administrator fallback follows the membership role, not the JWT/global staff role',
    NOT v_admin_b2_fallback
      AND v_member_admin_b2
      AND v_assigned_own
      AND NOT v_assigned_other,
    'global_admin_membership_doctor_b2=' || v_admin_b2_fallback::text
      || ' membership_admin_b2=' || v_member_admin_b2::text
      || ' assigned_own_branch=' || v_assigned_own::text
      || ' assigned_other_branch=' || v_assigned_other::text
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-05 — org A denies the doctor keys, org B grants the same role: A's
-- denial must win for every listed reader (U3 session inside org A).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_appt_a uuid := '1b060000-0000-4000-8000-000000000001';
  v_get public.rpc_result;
  v_admin_get public.rpc_result;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  v_get := public.get_appointment(v_appt_a);

  PERFORM pg_temp.r2_set_session(v_u4, v_org_a, ARRAY[v_branch_a], 'administrator');
  v_admin_get := public.get_appointment(v_appt_a);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: appointment access denial in A wins over B''s grant for the same role',
    NOT v_get.success AND v_get.error_code = 'FORBIDDEN' AND v_admin_get.success,
    'doctor_in_a=' || COALESCE(v_get.error_code, 'ok')
      || ' administrator_in_a=' || COALESCE(v_admin_get.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_doctor_invoices bigint;
  v_doctor_payments bigint;
  v_admin_invoices bigint;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  SELECT count(*) INTO v_doctor_invoices FROM public.invoices;
  SELECT count(*) INTO v_doctor_payments FROM public.payments;

  PERFORM pg_temp.r2_set_session(v_u4, v_org_a, ARRAY[v_branch_a], 'administrator');
  SELECT count(*) INTO v_admin_invoices FROM public.invoices;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: invoices view and payments read denials in A win over B''s grants',
    v_doctor_invoices = 0 AND v_doctor_payments = 0 AND v_admin_invoices >= 1,
    'doctor_invoices=' || v_doctor_invoices::text
      || ' doctor_payments=' || v_doctor_payments::text
      || ' admin_invoices=' || v_admin_invoices::text
  );
END;
$$;

DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_doctor_services bigint;
  v_admin_services bigint;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  SELECT count(*) INTO v_doctor_services FROM public.services;

  PERFORM pg_temp.r2_set_session(v_u4, v_org_a, ARRAY[v_branch_a], 'administrator');
  SELECT count(*) INTO v_admin_services FROM public.services;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: services read denial in A wins over B''s grant',
    v_doctor_services = 0 AND v_admin_services >= 1,
    'doctor_services=' || v_doctor_services::text
      || ' admin_services=' || v_admin_services::text
  );
END;
$$;

DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_shift_a uuid := '1b0c0000-0000-4000-8000-000000000001';
  v_detail jsonb;
  v_is_read_only boolean;
BEGIN
  -- Doctor denied shifts.manage in A (granted in B): today's unassigned shift
  -- is read-only for the A session, so the indication agrees with A.
  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  v_detail := public.get_shift_detail(v_shift_a);
  v_is_read_only := (v_detail -> 'shift' ->> 'is_read_only')::boolean;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: shift manage denial in A wins over B''s grant and is_read_only agrees with A',
    v_detail -> 'shift' ->> 'id' = v_shift_a::text AND v_is_read_only,
    'shift_id=' || COALESCE(v_detail -> 'shift' ->> 'id', '<none>')
      || ' is_read_only=' || COALESCE(v_is_read_only::text, '<none>')
  );
END;
$$;

DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_billing public.rpc_result;
  v_insurance public.rpc_result;
  v_duplicates public.rpc_result;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  v_billing := public.get_billing_settings();
  v_insurance := public.list_insurance_providers();
  v_duplicates := public.check_patient_duplicates('R1 RM02 Patient A', NULL, NULL, NULL);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: billing settings, insurance listing and duplicate check denials in A win over B''s grants',
    NOT v_billing.success AND v_billing.error_code = 'FORBIDDEN'
      AND NOT v_insurance.success AND v_insurance.error_code = 'FORBIDDEN'
      AND NOT v_duplicates.success AND v_duplicates.error_code = 'FORBIDDEN',
    'billing_settings=' || COALESCE(v_billing.error_code, 'ok')
      || ' insurance_providers=' || COALESCE(v_insurance.error_code, 'ok')
      || ' patient_duplicates=' || COALESCE(v_duplicates.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_patient_a uuid := '1b050000-0000-4000-8000-000000000001';
  v_visit_a uuid := '1b070000-0000-4000-8000-000000000001';
  v_safety public.rpc_result;
  v_visit public.rpc_result;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  v_safety := public.get_patient_safety_context(v_patient_a);
  v_visit := public.get_visit(v_visit_a);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: patient safety context and visit read denials in A win over B''s grants',
    NOT v_safety.success AND v_safety.error_code = 'FORBIDDEN'
      AND NOT v_visit.success AND v_visit.error_code = 'FORBIDDEN',
    'patient_safety_context=' || COALESCE(v_safety.error_code, 'ok')
      || ' get_visit=' || COALESCE(v_visit.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_service_a uuid := '1b080000-0000-4000-8000-000000000001';
  v_get public.rpc_result;
  v_price public.rpc_result;
  v_search public.rpc_result;
  v_list public.rpc_result;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  v_get := public.get_service(v_service_a);
  v_price := public.resolve_effective_service_price(v_service_a, v_branch_a);
  v_search := public.search_eligible_services(v_branch_a);
  v_list := public.list_services();

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: service catalog read denials in A win over B''s grants',
    NOT v_get.success AND v_get.error_code = 'FORBIDDEN'
      AND NOT v_price.success AND v_price.error_code = 'FORBIDDEN'
      AND NOT v_search.success AND v_search.error_code = 'FORBIDDEN'
      AND NOT v_list.success AND v_list.error_code = 'FORBIDDEN',
    'get_service=' || COALESCE(v_get.error_code, 'ok')
      || ' resolve_price=' || COALESCE(v_price.error_code, 'ok')
      || ' search_eligible=' || COALESCE(v_search.error_code, 'ok')
      || ' list_services=' || COALESCE(v_list.error_code, 'ok')
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-05 — the global staff role cannot substitute for A's membership role
-- (U6: staff role administrator, membership doctor in A only).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_u6 uuid := '1b030000-0000-4000-8000-000000000006';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_service_a uuid := '1b080000-0000-4000-8000-000000000001';
  v_invoices bigint;
  v_services bigint;
  v_get public.rpc_result;
  v_single public.rpc_result;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u6, v_org_a, ARRAY[v_branch_a], 'administrator');
  SELECT count(*) INTO v_invoices FROM public.invoices;
  SELECT count(*) INTO v_services FROM public.services;
  v_get := public.get_service(v_service_a);
  v_single := public.update_role_permission('doctor', 'services.view', true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: global staff role cannot substitute for A''s membership role',
    v_invoices = 0 AND v_services = 0
      AND NOT v_get.success AND v_get.error_code = 'FORBIDDEN'
      AND NOT v_single.success AND v_single.error_code = 'FORBIDDEN',
    'invoices=' || v_invoices::text
      || ' services=' || v_services::text
      || ' get_service=' || COALESCE(v_get.error_code, 'ok')
      || ' update_role_permission=' || COALESCE(v_single.error_code, 'ok')
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-05 — A's exact grant permits the corresponding read and no B records
-- return (U3 doctor, keys granted in A only for the duration of the checks).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_staff_u3 uuid := '1b040000-0000-4000-8000-000000000003';
  v_appt_a uuid := '1b060000-0000-4000-8000-000000000001';
  v_patient_a uuid := '1b050000-0000-4000-8000-000000000001';
  v_visit_a uuid := '1b070000-0000-4000-8000-000000000001';
  v_shift_a uuid := '1b0c0000-0000-4000-8000-000000000001';
  v_key text;
  v_appt public.rpc_result;
  v_dupes public.rpc_result;
  v_safety public.rpc_result;
  v_visit public.rpc_result;
  v_shift_detail jsonb;
  v_is_read_only boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  -- Grant A's doctor exactly the keys the appointment/patient/visit/shift
  -- readers accept.
  FOR v_key IN
    SELECT unnest(ARRAY[
      'appointments.read', 'patients.create', 'patients.view',
      'visits.create', 'visits.edit_soap', 'shifts.manage'
    ])
  LOOP
    INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
    VALUES (v_org_a, 'doctor', v_key, true, v_u4, v_u4)
    ON CONFLICT (organization_id, role, permission_key) DO UPDATE
      SET is_granted = true, is_deleted = false, updated_at = now(),
          created_by = v_u4, updated_by = v_u4;
  END LOOP;

  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  v_appt := public.get_appointment(v_appt_a);
  v_dupes := public.check_patient_duplicates('R1 RM02 Patient A', NULL, NULL, NULL);
  v_safety := public.get_patient_safety_context(v_patient_a);
  v_visit := public.get_visit(v_visit_a);
  v_shift_detail := public.get_shift_detail(v_shift_a);
  v_is_read_only := (v_shift_detail -> 'shift' ->> 'is_read_only')::boolean;

  PERFORM set_config('role', 'postgres', true);
  -- Restore A's denials.
  FOR v_key IN
    SELECT unnest(ARRAY[
      'appointments.read', 'patients.create', 'patients.view',
      'visits.create', 'visits.edit_soap', 'shifts.manage'
    ])
  LOOP
    UPDATE public.roles_permissions
    SET is_granted = false, updated_at = now(), updated_by = v_u4
    WHERE organization_id = v_org_a AND role = 'doctor' AND permission_key = v_key;
  END LOOP;
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: A''s exact grant permits appointment, patient, visit and shift reads',
    v_appt.success AND v_dupes.success AND v_safety.success AND v_visit.success
      AND NOT v_is_read_only,
    'appointment=' || COALESCE(v_appt.error_code, 'ok')
      || ' duplicates=' || COALESCE(v_dupes.error_code, 'ok')
      || ' safety_context=' || COALESCE(v_safety.error_code, 'ok')
      || ' visit=' || COALESCE(v_visit.error_code, 'ok')
      || ' shift_is_read_only=' || COALESCE(v_is_read_only::text, '<none>')
  );
END;
$$;

DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_insurance_a uuid := '1b090000-0000-4000-8000-000000000001';
  v_insurance_b uuid := '1b090000-0000-4000-8000-000000000002';
  v_key text;
  v_billing public.rpc_result;
  v_insurance public.rpc_result;
  v_provider_count int;
  v_provider_b_listed boolean;
  v_invoices bigint;
  v_payments bigint;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  FOR v_key IN
    SELECT unnest(ARRAY['invoices.view', 'payments.record'])
  LOOP
    INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
    VALUES (v_org_a, 'doctor', v_key, true, v_u4, v_u4)
    ON CONFLICT (organization_id, role, permission_key) DO UPDATE
      SET is_granted = true, is_deleted = false, updated_at = now(),
          created_by = v_u4, updated_by = v_u4;
  END LOOP;

  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  v_billing := public.get_billing_settings();
  v_insurance := public.list_insurance_providers();
  v_provider_count := jsonb_array_length(COALESCE(v_insurance.data -> 'providers', '[]'::jsonb));
  v_provider_b_listed := (
    v_insurance.data -> 'providers' @> jsonb_build_array(
      jsonb_build_object('id', v_insurance_b)
    )
  );
  SELECT count(*) INTO v_invoices FROM public.invoices;
  SELECT count(*) INTO v_payments FROM public.payments;

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.roles_permissions
  SET is_granted = false, updated_at = now(), updated_by = v_u4
  WHERE organization_id = v_org_a AND role = 'doctor'
    AND permission_key IN ('invoices.view', 'payments.record');
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: A''s exact grant permits billing and insurance reads with no B records',
    v_billing.success
      AND v_insurance.success
      AND v_provider_count = 1
      AND NOT COALESCE(v_provider_b_listed, false)
      AND v_invoices = 1
      AND v_payments = 1,
    'billing_settings=' || COALESCE(v_billing.error_code, 'ok')
      || ' providers=' || v_provider_count::text
      || ' b_provider_listed=' || COALESCE(v_provider_b_listed::text, 'false')
      || ' invoices=' || v_invoices::text
      || ' payments=' || v_payments::text
  );
END;
$$;

DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_service_a uuid := '1b080000-0000-4000-8000-000000000001';
  v_service_b uuid := '1b080000-0000-4000-8000-000000000002';
  v_key text;
  v_get public.rpc_result;
  v_price public.rpc_result;
  v_search public.rpc_result;
  v_list public.rpc_result;
  v_list_total int;
  v_b_listed boolean;
  v_services bigint;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  FOR v_key IN
    SELECT unnest(ARRAY['services.view', 'invoices.create'])
  LOOP
    INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
    VALUES (v_org_a, 'doctor', v_key, true, v_u4, v_u4)
    ON CONFLICT (organization_id, role, permission_key) DO UPDATE
      SET is_granted = true, is_deleted = false, updated_at = now(),
          created_by = v_u4, updated_by = v_u4;
  END LOOP;

  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  v_get := public.get_service(v_service_a);
  v_price := public.resolve_effective_service_price(v_service_a, v_branch_a);
  v_search := public.search_eligible_services(v_branch_a);
  v_list := public.list_services();
  v_list_total := COALESCE((v_list.data ->> 'total')::int, -1);
  v_b_listed := (
    v_list.data -> 'items' @> jsonb_build_array(
      jsonb_build_object('service_id', v_service_b)
    )
  );
  SELECT count(*) INTO v_services FROM public.services;

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.roles_permissions
  SET is_granted = false, updated_at = now(), updated_by = v_u4
  WHERE organization_id = v_org_a AND role = 'doctor'
    AND permission_key IN ('services.view', 'invoices.create');
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: A''s exact grant permits service catalog reads with no B services',
    v_get.success AND v_price.success AND v_search.success AND v_list.success
      AND v_list_total = 1
      AND NOT COALESCE(v_b_listed, false)
      AND v_services = 1,
    'get_service=' || COALESCE(v_get.error_code, 'ok')
      || ' resolve_price=' || COALESCE(v_price.error_code, 'ok')
      || ' search_eligible=' || COALESCE(v_search.error_code, 'ok')
      || ' list_total=' || v_list_total::text
      || ' b_service_listed=' || COALESCE(v_b_listed::text, 'false')
      || ' services_rls=' || v_services::text
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-05 — a deactivated staff member denies every org-scoped permission
-- reader (the live-staff predicate inherited from current_org_id()).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_branch_a uuid := '1b020000-0000-4000-8000-000000000001';
  v_staff_u3 uuid := '1b040000-0000-4000-8000-000000000003';
  v_service_a uuid := '1b080000-0000-4000-8000-000000000001';
  v_deactivate public.rpc_result;
  v_reactivate public.rpc_result;
  v_invoices bigint;
  v_branch_access boolean;
  v_get public.rpc_result;
BEGIN
  PERFORM pg_temp.r2_set_session(v_u4, v_org_a, ARRAY[v_branch_a], 'administrator');
  v_deactivate := public.set_staff_active(v_staff_u3, false);

  PERFORM pg_temp.r2_set_session(v_u3, v_org_a, ARRAY[v_branch_a], 'doctor');
  SELECT count(*) INTO v_invoices FROM public.invoices;
  SELECT auth_internal.staff_can_access_branch(v_branch_a) INTO v_branch_access;
  v_get := public.get_service(v_service_a);

  PERFORM pg_temp.r2_set_session(v_u4, v_org_a, ARRAY[v_branch_a], 'administrator');
  v_reactivate := public.set_staff_active(v_staff_u3, true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm02_results VALUES (
    'R1-SQL-05: deactivated staff denies every org-scoped permission reader',
    v_deactivate.success AND v_reactivate.success
      AND v_invoices = 0
      AND NOT v_branch_access
      AND NOT v_get.success AND v_get.error_code = 'FORBIDDEN',
    'deactivate=' || COALESCE(v_deactivate.error_code, 'ok')
      || ' reactivate=' || COALESCE(v_reactivate.error_code, 'ok')
      || ' invoices=' || v_invoices::text
      || ' branch_access=' || v_branch_access::text
      || ' get_service=' || COALESCE(v_get.error_code, 'ok')
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Final verdict and cleanup.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures
  FROM r1_rm02_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'r1_rm02_permission_readers failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM r1_rm02_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

DO $$
DECLARE
  v_u1 uuid := '1b030000-0000-4000-8000-000000000001';
  v_u2 uuid := '1b030000-0000-4000-8000-000000000002';
  v_u3 uuid := '1b030000-0000-4000-8000-000000000003';
  v_u4 uuid := '1b030000-0000-4000-8000-000000000004';
  v_u5 uuid := '1b030000-0000-4000-8000-000000000005';
  v_u6 uuid := '1b030000-0000-4000-8000-000000000006';
  v_org_a uuid := '1b010000-0000-4000-8000-000000000001';
  v_org_b uuid := '1b010000-0000-4000-8000-000000000002';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.audit_log
  WHERE organization_id IN (v_org_a, v_org_b)
    OR user_id IN (v_u1, v_u2, v_u3, v_u4, v_u5, v_u6);
  DELETE FROM public.roles_permissions WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.payments WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.invoices WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.shifts WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.service_branches WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.services WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.insurance_providers WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.visits WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.appointments WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.patients WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_branch_assignments WHERE branch_id IN (
    SELECT id FROM public.branches WHERE organization_id IN (v_org_a, v_org_b)
  );
  DELETE FROM ai_internal.membership WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM ai_internal.user_active_organization WHERE organization_id IN (v_org_a, v_org_b)
    OR user_id IN (v_u1, v_u2, v_u3, v_u4, v_u5, v_u6);
  DELETE FROM public.branches WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_members WHERE auth_user_id IN (v_u1, v_u2, v_u3, v_u4, v_u5, v_u6)
    OR full_name LIKE 'R1 RM02%';
  DELETE FROM auth.users WHERE id IN (v_u1, v_u2, v_u3, v_u4, v_u5, v_u6)
    OR email LIKE 'r1-rm02-%';
END;
$$;

COMMIT;

SELECT test_name, passed, detail
FROM r1_rm02_results
ORDER BY test_name;
