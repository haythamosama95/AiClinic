-- E2E-P1.1-07 — staff membership backfill (FR-001, FR-002).
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/membership_active_org.sql

BEGIN;

CREATE TEMP TABLE membership_active_org_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

-- After migrations, every non-deleted staff member whose database has a
-- non-deleted organisation has exactly one ai_internal.membership row for the
-- earliest such organisation and that staff member's role. A non-deleted staff
-- member and no organisation — the bootstrap administrator from
-- 20260516100400_auth_rbac_seed.sql on a fresh database — has no membership row.
DO $$
DECLARE
  v_bootstrap_user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  v_has_org boolean;
  v_earliest_org_id uuid;
  v_mismatch_count int;
  v_expected_count int;
  v_actual_count int;
  v_bootstrap_staff_count int;
  v_bootstrap_membership_count int;
BEGIN
  -- Absence is an assertion failure. A static reference to the missing
  -- relation aborts the script before this test can record E2E-P1.1-07.
  IF to_regclass('ai_internal.membership') IS NULL THEN
    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-07',
      false,
      'ai_internal.membership is absent'
    );
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.organizations
    WHERE is_deleted = false
  )
  INTO v_has_org;

  IF v_has_org THEN
    SELECT o.id
    INTO v_earliest_org_id
    FROM public.organizations o
    WHERE o.is_deleted = false
    ORDER BY o.created_at
    LIMIT 1;

    WITH expected AS (
      SELECT
        sm.auth_user_id AS user_id,
        v_earliest_org_id AS organization_id,
        sm.role
      FROM public.staff_members sm
      WHERE sm.is_deleted = false
    ),
    actual AS (
      SELECT m.user_id, m.organization_id, m.role
      FROM ai_internal.membership m
      WHERE m.user_id IN (SELECT e.user_id FROM expected e)
    ),
    diff AS (
      SELECT user_id, organization_id, role FROM expected
      EXCEPT
      SELECT user_id, organization_id, role FROM actual
      UNION ALL
      SELECT user_id, organization_id, role FROM actual
      EXCEPT
      SELECT user_id, organization_id, role FROM expected
    )
    SELECT
      (SELECT count(*) FROM diff),
      (SELECT count(*) FROM expected),
      (SELECT count(*) FROM actual)
    INTO v_mismatch_count, v_expected_count, v_actual_count;

    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-07',
      v_mismatch_count = 0 AND v_actual_count = v_expected_count,
      'mismatched_staff=' || v_mismatch_count::text
        || ' expected=' || v_expected_count::text
        || ' actual=' || v_actual_count::text
        || ' earliest_org=' || COALESCE(v_earliest_org_id::text, '<null>')
    );
  ELSE
    SELECT count(*)
    INTO v_bootstrap_staff_count
    FROM public.staff_members sm
    WHERE sm.auth_user_id = v_bootstrap_user_id
      AND sm.is_deleted = false;

    SELECT count(*)
    INTO v_bootstrap_membership_count
    FROM ai_internal.membership m
    WHERE m.user_id = v_bootstrap_user_id;

    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-07',
      v_bootstrap_staff_count = 1 AND v_bootstrap_membership_count = 0,
      'bootstrap_staff=' || v_bootstrap_staff_count::text
        || ' bootstrap_memberships=' || v_bootstrap_membership_count::text
    );
  END IF;
END;
$$;

-- E2E-P1.1-01 — one membership, hook active_org, current_org_id() (FR-003, FR-005).
-- Fails before the migration because current_org_id() and the active_org claim are absent.
DO $$
DECLARE
  v_user_id uuid := '06111000-0000-4000-8000-000000000001';
  v_org_id uuid := '06112000-0000-4000-8000-000000000001';
  v_staff_id uuid := '06113000-0000-4000-8000-000000000001';
  v_bootstrap_user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  v_hook jsonb;
  v_claim_state text;
  v_active_org text;
  v_current_org uuid;
BEGIN
  IF to_regprocedure('public.current_org_id()') IS NULL THEN
    v_hook := public.get_custom_claims(
      jsonb_build_object(
        'user_id', v_bootstrap_user_id::text,
        'claims', jsonb_build_object(
          'sub', v_bootstrap_user_id::text,
          'role', 'authenticated'
        )
      )
    );
    IF COALESCE((v_hook -> 'claims') ? 'active_org', false) THEN
      v_claim_state := 'present';
    ELSE
      v_claim_state := 'absent';
    END IF;

    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-01',
      false,
      'current_org_id() is absent; active_org claim is ' || v_claim_state
    );
    RETURN;
  END IF;

  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id = v_org_id;
  DELETE FROM ai_internal.user_active_organization WHERE user_id = v_user_id;
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id = v_org_id;
  DELETE FROM auth.users WHERE id = v_user_id;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'e2e-p11-01',
    extensions.crypt('pw-e2e-p11-01', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  );

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_org_id, 'E2E P1.1 Org 01', v_user_id, v_user_id);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES (v_staff_id, v_user_id, 'E2E P1.1 Member 01', 'administrator', v_user_id, v_user_id);

  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES (v_user_id, v_org_id, 'administrator');

  v_hook := public.get_custom_claims(
    jsonb_build_object(
      'user_id', v_user_id::text,
      'claims', jsonb_build_object(
        'sub', v_user_id::text,
        'role', 'authenticated'
      )
    )
  );
  v_active_org := v_hook -> 'claims' ->> 'active_org';

  PERFORM set_config('request.jwt.claims', (v_hook -> 'claims')::text, true);
  v_current_org := public.current_org_id();

  INSERT INTO membership_active_org_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.1-01',
    v_active_org = v_org_id::text AND v_current_org = v_org_id,
    'active_org=' || COALESCE(v_active_org, '<null>')
      || ' current_org_id=' || COALESCE(v_current_org::text, '<null>')
  );

  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM ai_internal.user_active_organization WHERE user_id = v_user_id;
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id = v_org_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- E2E-P1.1-02 — set_active_organization(B), refresh, tenant rows (FR-004, FR-008).
-- Fails before the migration because set_active_organization is absent.
DO $$
DECLARE
  v_user_id uuid := '06121000-0000-4000-8000-000000000002';
  v_org_a uuid := '06122000-0000-4000-8000-00000000000a';
  v_org_b uuid := '06122000-0000-4000-8000-00000000000b';
  v_branch_a uuid := '06124000-0000-4000-8000-00000000000a';
  v_branch_b uuid := '06124000-0000-4000-8000-00000000000b';
  v_staff_id uuid := '06123000-0000-4000-8000-000000000002';
  v_patient_a uuid := '06125000-0000-4000-8000-00000000000a';
  v_patient_b uuid := '06125000-0000-4000-8000-00000000000b';
  v_appt_a uuid := '06126000-0000-4000-8000-00000000000a';
  v_appt_b uuid := '06126000-0000-4000-8000-00000000000b';
  v_set public.rpc_result;
  v_hook jsonb;
  v_current_org uuid;
  v_list_b public.rpc_result;
  v_list_a public.rpc_result;
  v_b_only boolean;
  v_a_hidden boolean;
BEGIN
  IF to_regprocedure('public.set_active_organization(uuid)') IS NULL THEN
    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-02',
      false,
      'set_active_organization is absent'
    );
    RETURN;
  END IF;

  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.appointments WHERE id IN (v_appt_a, v_appt_b);
  DELETE FROM public.patients WHERE id IN (v_patient_a, v_patient_b);
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id = v_staff_id;
  DELETE FROM ai_internal.user_active_organization WHERE user_id = v_user_id;
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'e2e-p11-02',
    extensions.crypt('pw-e2e-p11-02', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  );

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'E2E P1.1 Org A', v_user_id, v_user_id),
    (v_org_b, 'E2E P1.1 Org B', v_user_id, v_user_id);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'E2E P1.1 Branch A', 'P11A', v_user_id, v_user_id),
    (v_branch_b, v_org_b, 'E2E P1.1 Branch B', 'P11B', v_user_id, v_user_id);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES (v_staff_id, v_user_id, 'E2E P1.1 Member 02', 'doctor', v_user_id, v_user_id);

  INSERT INTO public.staff_branch_assignments (
    staff_member_id, branch_id, is_primary, created_by, updated_by
  )
  VALUES
    (v_staff_id, v_branch_a, true, v_user_id, v_user_id),
    (v_staff_id, v_branch_b, false, v_user_id, v_user_id);

  INSERT INTO public.patients (
    id, branch_id, organization_id, full_name, phone, mrn, created_by, updated_by
  )
  VALUES
    (v_patient_a, v_branch_a, v_org_a, 'E2E P1.1 Patient A', '201000000011', 'MRN-E2EP1102A', v_user_id, v_user_id),
    (v_patient_b, v_branch_b, v_org_b, 'E2E P1.1 Patient B', '201000000012', 'MRN-E2EP1102B', v_user_id, v_user_id);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES
    (
      v_appt_a, v_branch_a, v_patient_a, v_staff_id,
      now() + interval '1 day', now() + interval '1 day 30 minutes',
      'planned', 'scheduled', v_user_id, v_user_id
    ),
    (
      v_appt_b, v_branch_b, v_patient_b, v_staff_id,
      now() + interval '1 day', now() + interval '1 day 30 minutes',
      'planned', 'scheduled', v_user_id, v_user_id
    );

  INSERT INTO ai_internal.membership (user_id, organization_id, role, created_at)
  VALUES
    (v_user_id, v_org_a, 'doctor', now() - interval '2 days'),
    (v_user_id, v_org_b, 'doctor', now() - interval '1 day');

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_id::text,
      'role', 'authenticated'
    )::text,
    true
  );
  v_set := public.set_active_organization(v_org_b);
  PERFORM set_config('role', 'postgres', true);

  v_hook := public.get_custom_claims(
    jsonb_build_object(
      'user_id', v_user_id::text,
      'claims', jsonb_build_object(
        'sub', v_user_id::text,
        'role', 'authenticated'
      )
    )
  );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', (v_hook -> 'claims')::text, true);
  v_current_org := public.current_org_id();
  v_list_b := public.list_appointments(
    v_branch_b,
    now() - interval '1 day',
    now() + interval '7 days',
    NULL,
    NULL
  );
  v_list_a := public.list_appointments(
    v_branch_a,
    now() - interval '1 day',
    now() + interval '7 days',
    NULL,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);

  v_b_only := v_list_b.success
    AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(COALESCE(v_list_b.data -> 'items', '[]'::jsonb)) item
      WHERE item ->> 'id' = v_appt_b::text
    )
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(COALESCE(v_list_b.data -> 'items', '[]'::jsonb)) item
      WHERE item ->> 'id' = v_appt_a::text
    );
  v_a_hidden := NOT v_list_a.success
    OR NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(COALESCE(v_list_a.data -> 'items', '[]'::jsonb)) item
      WHERE item ->> 'id' = v_appt_a::text
    );

  INSERT INTO membership_active_org_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.1-02',
    v_set.success
      AND v_set.error_code IS NULL
      AND v_set.error_message IS NULL
      AND (v_set.data ->> 'organization_id') = v_org_b::text
      AND v_current_org = v_org_b
      AND v_b_only
      AND v_a_hidden,
    'set_success=' || COALESCE(v_set.success::text, '<null>')
      || ' current_org_id=' || COALESCE(v_current_org::text, '<null>')
      || ' list_b=' || COALESCE(v_list_b.error_code, 'ok')
      || ' list_a=' || COALESCE(v_list_a.error_code, 'ok')
  );

  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM public.appointments WHERE id IN (v_appt_a, v_appt_b);
  DELETE FROM public.patients WHERE id IN (v_patient_a, v_patient_b);
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id = v_staff_id;
  DELETE FROM ai_internal.user_active_organization WHERE user_id = v_user_id;
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- E2E-P1.1-03 — set_active_organization(C) is forbidden (FR-004).
-- Fails before the migration because set_active_organization is absent.
DO $$
DECLARE
  v_user_id uuid := '06131000-0000-4000-8000-000000000003';
  v_org_a uuid := '06132000-0000-4000-8000-00000000000a';
  v_org_c uuid := '06132000-0000-4000-8000-00000000000c';
  v_staff_id uuid := '06133000-0000-4000-8000-000000000003';
  v_hook_before jsonb;
  v_hook_after jsonb;
  v_claim_before text;
  v_claim_after text;
  v_row_before uuid;
  v_row_after uuid;
  v_set public.rpc_result;
BEGIN
  IF to_regprocedure('public.set_active_organization(uuid)') IS NULL THEN
    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-03',
      false,
      'set_active_organization is absent'
    );
    RETURN;
  END IF;

  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id IN (v_org_a, v_org_c);
  DELETE FROM ai_internal.user_active_organization WHERE user_id = v_user_id;
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_c);
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'e2e-p11-03',
    extensions.crypt('pw-e2e-p11-03', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  );

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'E2E P1.1 Org A3', v_user_id, v_user_id),
    (v_org_c, 'E2E P1.1 Org C', v_user_id, v_user_id);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES (v_staff_id, v_user_id, 'E2E P1.1 Member 03', 'administrator', v_user_id, v_user_id);

  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES (v_user_id, v_org_a, 'administrator');

  v_hook_before := public.get_custom_claims(
    jsonb_build_object(
      'user_id', v_user_id::text,
      'claims', jsonb_build_object(
        'sub', v_user_id::text,
        'role', 'authenticated'
      )
    )
  );
  v_claim_before := v_hook_before -> 'claims' ->> 'active_org';

  SELECT u.organization_id
  INTO v_row_before
  FROM ai_internal.user_active_organization u
  WHERE u.user_id = v_user_id;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_id::text,
      'role', 'authenticated'
    )::text,
    true
  );
  v_set := public.set_active_organization(v_org_c);
  PERFORM set_config('role', 'postgres', true);

  SELECT u.organization_id
  INTO v_row_after
  FROM ai_internal.user_active_organization u
  WHERE u.user_id = v_user_id;

  v_hook_after := public.get_custom_claims(
    jsonb_build_object(
      'user_id', v_user_id::text,
      'claims', jsonb_build_object(
        'sub', v_user_id::text,
        'role', 'authenticated'
      )
    )
  );
  v_claim_after := v_hook_after -> 'claims' ->> 'active_org';

  INSERT INTO membership_active_org_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.1-03',
    v_set.success = false
      AND v_set.data IS NULL
      AND v_set.error_code = 'FORBIDDEN'
      AND v_set.error_message = 'You do not have a membership in that organisation.'
      AND v_row_before = v_org_a
      AND v_row_after IS NOT DISTINCT FROM v_row_before
      AND v_claim_before = v_org_a::text
      AND v_claim_after IS NOT DISTINCT FROM v_claim_before,
    'success=' || COALESCE(v_set.success::text, '<null>')
      || ' error_code=' || COALESCE(v_set.error_code, '<null>')
      || ' row_before=' || COALESCE(v_row_before::text, '<null>')
      || ' row_after=' || COALESCE(v_row_after::text, '<null>')
      || ' claim_before=' || COALESCE(v_claim_before, '<null>')
      || ' claim_after=' || COALESCE(v_claim_after, '<null>')
  );

  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM ai_internal.user_active_organization WHERE user_id = v_user_id;
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id IN (v_org_a, v_org_c);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_c);
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- E2E-P1.1-04 — membership deleted while claims remain (FR-005, FR-008).
-- Fails before the migration because current_org_id() is absent.
DO $$
DECLARE
  v_user_id uuid := '06141000-0000-4000-8000-000000000004';
  v_org_id uuid := '06142000-0000-4000-8000-000000000004';
  v_branch_id uuid := '06144000-0000-4000-8000-000000000004';
  v_staff_id uuid := '06143000-0000-4000-8000-000000000004';
  v_claims text;
  v_org_before uuid;
  v_org_after uuid;
  v_branch_count int;
  v_list public.rpc_result;
  v_forbidden boolean := false;
  v_list_detail text;
BEGIN
  IF to_regprocedure('public.current_org_id()') IS NULL THEN
    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-04',
      false,
      'current_org_id() is absent'
    );
    RETURN;
  END IF;

  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id = v_org_id;
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.branches WHERE id = v_branch_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'e2e-p11-04',
    extensions.crypt('pw-e2e-p11-04', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  );

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_org_id, 'E2E P1.1 Org 04', v_user_id, v_user_id);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES (v_branch_id, v_org_id, 'E2E P1.1 Branch 04', 'P114', v_user_id, v_user_id);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES (v_staff_id, v_user_id, 'E2E P1.1 Member 04', 'administrator', v_user_id, v_user_id);

  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES (v_user_id, v_org_id, 'administrator');

  v_claims := json_build_object(
    'sub', v_user_id::text,
    'role', 'authenticated',
    'active_org', v_org_id::text,
    'organization_id', v_org_id::text,
    'branch_ids', v_branch_id::text,
    'staff_member_id', v_staff_id::text,
    'staff_role', 'administrator'
  )::text;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', v_claims, true);
  v_org_before := public.current_org_id();

  PERFORM set_config('role', 'postgres', true);
  DELETE FROM ai_internal.membership
  WHERE user_id = v_user_id
    AND organization_id = v_org_id;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', v_claims, true);
  v_org_after := public.current_org_id();

  SELECT count(*)::int
  INTO v_branch_count
  FROM public.branches
  WHERE id = v_branch_id;

  BEGIN
    v_list := public.list_appointments(
      v_branch_id,
      now() - interval '1 day',
      now() + interval '7 days',
      NULL,
      NULL
    );
    v_forbidden := NOT v_list.success AND v_list.error_code = 'FORBIDDEN';
    v_list_detail := COALESCE(v_list.error_code, 'ok');
  EXCEPTION
    WHEN OTHERS THEN
      v_forbidden := SQLERRM = 'FORBIDDEN';
      v_list_detail := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);

  INSERT INTO membership_active_org_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.1-04',
    v_org_before = v_org_id
      AND v_org_after IS NULL
      AND v_branch_count = 0
      AND v_forbidden,
    'org_before=' || COALESCE(v_org_before::text, '<null>')
      || ' org_after=' || COALESCE(v_org_after::text, '<null>')
      || ' branches=' || COALESCE(v_branch_count::text, '<null>')
      || ' list=' || COALESCE(v_list_detail, '<null>')
  );

  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id = v_org_id;
  DELETE FROM public.branches WHERE id = v_branch_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- E2E-P1.1-05 — crafted active_org and organization_id with no membership (FR-005, FR-006).
-- Fails before the migration because current_org_id() is absent.
DO $$
DECLARE
  v_user_id uuid := '06151000-0000-4000-8000-000000000005';
  v_active_org uuid := '06152000-0000-4000-8000-00000000005a';
  v_legacy_org uuid := '06152000-0000-4000-8000-00000000005b';
  v_from_active uuid;
  v_from_legacy uuid;
BEGIN
  IF to_regprocedure('public.current_org_id()') IS NULL THEN
    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-05',
      false,
      'current_org_id() is absent'
    );
    RETURN;
  END IF;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_id::text,
      'role', 'authenticated',
      'active_org', v_active_org::text
    )::text,
    true
  );
  v_from_active := public.current_org_id();

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_id::text,
      'role', 'authenticated',
      'organization_id', v_legacy_org::text
    )::text,
    true
  );
  v_from_legacy := public.current_org_id();

  INSERT INTO membership_active_org_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.1-05',
    v_from_active IS NULL AND v_from_legacy IS NULL,
    'active_org=' || COALESCE(v_from_active::text, '<null>')
      || ' organization_id=' || COALESCE(v_from_legacy::text, '<null>')
  );

  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

-- E2E-P1.1-06 — membership role ignores roles_permissions (FR-007).
-- Fails before the migration because current_membership_role() is absent.
DO $$
DECLARE
  v_user_id uuid := '06161000-0000-4000-8000-000000000006';
  v_org_admin uuid := '06162000-0000-4000-8000-00000000006a';
  v_org_doctor uuid := '06162000-0000-4000-8000-00000000006b';
  v_staff_id uuid := '06163000-0000-4000-8000-000000000006';
  v_perm_id uuid;
  v_perm_key text;
  v_granted boolean;
  v_admin public.staff_role;
  v_doctor public.staff_role;
  v_admin_after public.staff_role;
  v_doctor_after public.staff_role;
  v_updated int := 0;
BEGIN
  IF to_regprocedure('public.current_membership_role()') IS NULL THEN
    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-06',
      false,
      'current_membership_role() is absent'
    );
    RETURN;
  END IF;

  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id IN (v_org_admin, v_org_doctor);
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.organizations WHERE id IN (v_org_admin, v_org_doctor);
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'e2e-p11-06',
    extensions.crypt('pw-e2e-p11-06', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  );

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_admin, 'E2E P1.1 Org Admin', v_user_id, v_user_id),
    (v_org_doctor, 'E2E P1.1 Org Doctor', v_user_id, v_user_id);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES (v_staff_id, v_user_id, 'E2E P1.1 Member 06', 'receptionist', v_user_id, v_user_id);

  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES
    (v_user_id, v_org_admin, 'administrator'),
    (v_user_id, v_org_doctor, 'doctor');

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_id::text,
      'role', 'authenticated',
      'active_org', v_org_admin::text
    )::text,
    true
  );
  v_admin := public.current_membership_role();

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_id::text,
      'role', 'authenticated',
      'active_org', v_org_doctor::text
    )::text,
    true
  );
  v_doctor := public.current_membership_role();

  PERFORM set_config('role', 'postgres', true);
  SELECT rp.id, rp.permission_key, rp.is_granted
  INTO v_perm_id, v_perm_key, v_granted
  FROM public.roles_permissions rp
  WHERE rp.role = 'administrator'
    AND rp.is_deleted = false
  ORDER BY rp.permission_key
  LIMIT 1;

  IF v_perm_id IS NOT NULL THEN
    UPDATE public.roles_permissions
    SET is_granted = NOT v_granted
    WHERE id = v_perm_id;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
  END IF;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_id::text,
      'role', 'authenticated',
      'active_org', v_org_admin::text
    )::text,
    true
  );
  v_admin_after := public.current_membership_role();

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_id::text,
      'role', 'authenticated',
      'active_org', v_org_doctor::text
    )::text,
    true
  );
  v_doctor_after := public.current_membership_role();

  PERFORM set_config('role', 'postgres', true);
  IF v_perm_id IS NOT NULL THEN
    UPDATE public.roles_permissions
    SET is_granted = v_granted
    WHERE id = v_perm_id;
  END IF;

  INSERT INTO membership_active_org_results (test_name, passed, detail)
  VALUES (
    'E2E-P1.1-06',
    v_admin = 'administrator'::public.staff_role
      AND v_doctor = 'doctor'::public.staff_role
      AND v_admin_after = 'administrator'::public.staff_role
      AND v_doctor_after = 'doctor'::public.staff_role
      AND v_updated = 1,
    'admin=' || COALESCE(v_admin::text, '<null>')
      || ' doctor=' || COALESCE(v_doctor::text, '<null>')
      || ' admin_after=' || COALESCE(v_admin_after::text, '<null>')
      || ' doctor_after=' || COALESCE(v_doctor_after::text, '<null>')
      || ' updated=' || v_updated::text
      || ' permission=' || COALESCE(v_perm_key, '<null>')
  );

  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id IN (v_org_admin, v_org_doctor);
  DELETE FROM public.organizations WHERE id IN (v_org_admin, v_org_doctor);
  DELETE FROM public.audit_log WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures
  FROM membership_active_org_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'membership_active_org failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM membership_active_org_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail
FROM membership_active_org_results
ORDER BY test_name;
