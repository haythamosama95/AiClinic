-- RM01 (R1-SQL-01, R1-SQL-03, R1-SQL-02, R1-SQL-06) — backend staff lifecycle
-- authority completion checks.
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/r1_rm01_staff_authority.sql

BEGIN;

CREATE TEMP TABLE r1_rm01_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.r1_set_session(p_user_id uuid, p_org_id uuid)
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
      'organization_id', COALESCE(p_org_id::text, '')
    )::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.r1_decode_jws_payload(p_token text)
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

-- -----------------------------------------------------------------------------
-- Shared fixture: two orgs, caller/target administrators, an ordinary member
-- (SQL-01/SQL-03 subject), a soft-delete subject, a dual-membership
-- administrator (SQL-02 cross-org subject) and a reconciliation mismatch row.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_target_user uuid := '1a030000-0000-4000-8000-000000000002';
  v_member_user uuid := '1a030000-0000-4000-8000-000000000003';
  v_delsubj_user uuid := '1a030000-0000-4000-8000-000000000004';
  v_dual_user uuid := '1a030000-0000-4000-8000-000000000005';
  v_recon_user uuid := '1a030000-0000-4000-8000-000000000006';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_org_b uuid := '1a010000-0000-4000-8000-000000000002';
  v_u record;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  -- Idempotent fixture cleanup from earlier runs of this file.
  DELETE FROM public.audit_log WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.roles_permissions WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.patients WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_branch_assignments WHERE branch_id IN (
    SELECT id FROM public.branches WHERE organization_id IN (v_org_a, v_org_b)
  );
  DELETE FROM ai_internal.ai_token_issuance WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM ai_internal.membership WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM ai_internal.user_active_organization WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.branches WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_members WHERE auth_user_id IN (
    v_caller_user, v_target_user, v_member_user, v_delsubj_user, v_dual_user, v_recon_user
  );
  DELETE FROM ai_internal.app_settings
  WHERE key IN ('ai.issuer.rate_limit.ceiling', 'ai.issuer.rate_limit.window_seconds');
  DELETE FROM auth.users WHERE id IN (
    v_caller_user, v_target_user, v_member_user, v_delsubj_user, v_dual_user, v_recon_user
  );

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
    extensions.crypt('pw-r1-rm01', extensions.gen_salt('bf')),
    now(), now(), now()
  FROM (VALUES
    (v_caller_user,  'r1-rm01-caller'),
    (v_target_user,  'r1-rm01-target'),
    (v_member_user,  'r1-rm01-member'),
    (v_delsubj_user, 'r1-rm01-delsubj'),
    (v_dual_user,    'r1-rm01-dual'),
    (v_recon_user,   'r1-rm01-recon')
  ) AS u(id, email);

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'R1 RM01 Org A', v_caller_user, v_caller_user),
    (v_org_b, 'R1 RM01 Org B', v_caller_user, v_caller_user);

  INSERT INTO public.branches (id, organization_id, name, code, is_active, created_by, updated_by)
  VALUES
    ('1a020000-0000-4000-8000-000000000001', v_org_a, 'R1 RM01 Main A', 'R1A', true, v_caller_user, v_caller_user),
    ('1a020000-0000-4000-8000-000000000002', v_org_b, 'R1 RM01 Main B', 'R1B', true, v_caller_user, v_caller_user);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    ('1a040000-0000-4000-8000-000000000001', v_caller_user,  'R1 RM01 Caller',  'administrator',  v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000002', v_target_user,  'R1 RM01 Target',  'administrator',  v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000003', v_member_user,  'R1 RM01 Member',  'doctor',         v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000004', v_delsubj_user, 'R1 RM01 DelSubj', 'doctor',         v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000005', v_dual_user,    'R1 RM01 Dual',    'administrator',  v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000006', v_recon_user,   'R1 RM01 Recon',   'doctor',         v_caller_user, v_caller_user);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    ('1a040000-0000-4000-8000-000000000001', '1a020000-0000-4000-8000-000000000001', true,  v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000002', '1a020000-0000-4000-8000-000000000001', true,  v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000003', '1a020000-0000-4000-8000-000000000001', true,  v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000004', '1a020000-0000-4000-8000-000000000001', true,  v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000005', '1a020000-0000-4000-8000-000000000001', true,  v_caller_user, v_caller_user),
    ('1a040000-0000-4000-8000-000000000006', '1a020000-0000-4000-8000-000000000001', true,  v_caller_user, v_caller_user);

  -- Memberships. The dual user is administrator in A and B (the demotion in A
  -- must keep B unchanged). The recon user has one membership whose role
  -- (administrator) differs from staff.role (doctor): the reconciliation
  -- fixture. The member user holds memberships in A and B so the
  -- deactivated-state sync must NOT fall back to another tenant.
  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES
    (v_caller_user, v_org_a, 'administrator'),
    (v_target_user, v_org_a, 'administrator'),
    (v_member_user, v_org_a, 'doctor'),
    (v_member_user, v_org_b, 'doctor'),
    (v_delsubj_user, v_org_a, 'doctor'),
    (v_dual_user, v_org_a, 'administrator'),
    (v_dual_user, v_org_b, 'administrator'),
    (v_recon_user, v_org_a, 'administrator');

  INSERT INTO ai_internal.user_active_organization (user_id, organization_id)
  VALUES
    (v_caller_user, v_org_a),
    (v_target_user, v_org_a),
    (v_member_user, v_org_a),
    (v_delsubj_user, v_org_a),
    (v_dual_user, v_org_a),
    (v_recon_user, v_org_a);

  -- Permission matrix for org A: RPC authorization for the caller and the AI
  -- scope split used by the R1-SQL-02 reduced-scopes check.
  INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
  VALUES
    (v_org_a, 'administrator', 'settings.manage_staff', true, v_caller_user, v_caller_user),
    (v_org_a, 'administrator', 'ai.visit_summary',     true, v_caller_user, v_caller_user),
    (v_org_a, 'administrator', 'ai.admin_only_flag',   true, v_caller_user, v_caller_user),
    (v_org_a, 'doctor',        'ai.visit_summary',     true, v_caller_user, v_caller_user);

  INSERT INTO public.patients (
    id, branch_id, organization_id, full_name, phone, mrn, created_by, updated_by
  )
  VALUES (
    '1a050000-0000-4000-8000-000000000001',
    '1a020000-0000-4000-8000-000000000001',
    v_org_a,
    'R1 RM01 Patient', '2010000000a1', 'MRN-R1RM01', v_caller_user, v_caller_user
  );

  FOR v_u IN
    SELECT unnest(ARRAY[v_caller_user, v_target_user, v_member_user, v_delsubj_user, v_dual_user, v_recon_user]) AS id
  LOOP
    UPDATE public.staff_members
    SET created_by = v_caller_user, updated_by = v_caller_user
    WHERE auth_user_id = v_u.id;
  END LOOP;

  INSERT INTO r1_rm01_results VALUES ('fixture_setup', true, 'orgs, staff, memberships and permissions ready');
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-01 — direct staff UPDATE is closed; RPC path still works.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_member_user uuid := '1a030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_member_staff uuid := '1a040000-0000-4000-8000-000000000003';
  v_caller_staff uuid := '1a040000-0000-4000-8000-000000000001';
  v_staff_before int;
  v_membership_before int;
  v_audit_before int;
  v_staff_after int;
  v_membership_after int;
  v_audit_after int;
  v_own_row_denied boolean := false;
  v_other_row_denied boolean := false;
  v_own_err text := '<none>';
  v_other_err text := '<none>';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_staff_before FROM public.staff_members WHERE is_deleted = false;
  SELECT count(*) INTO v_membership_before FROM ai_internal.membership;
  SELECT count(*) INTO v_audit_before FROM public.audit_log;

  -- Ordinary member attempts to PATCH their own role to administrator.
  PERFORM pg_temp.r1_set_session(v_member_user, v_org_a);
  BEGIN
    UPDATE public.staff_members
    SET role = 'administrator'
    WHERE id = v_member_staff;
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_own_row_denied := true;
      v_own_err := SQLERRM;
  END;

  -- Ordinary member attempts to edit another person's profile.
  BEGIN
    UPDATE public.staff_members
    SET full_name = 'Hacked Name'
    WHERE id = v_caller_staff;
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_other_row_denied := true;
      v_other_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_staff_after FROM public.staff_members WHERE is_deleted = false;
  SELECT count(*) INTO v_membership_after FROM ai_internal.membership;
  SELECT count(*) INTO v_audit_after FROM public.audit_log;

  INSERT INTO r1_rm01_results VALUES
    (
      'R1-SQL-01: ordinary member cannot update own staff authority column',
      v_own_row_denied,
      'error=' || v_own_err
    ),
    (
      'R1-SQL-01: ordinary member cannot update another member''s profile',
      v_other_row_denied,
      'error=' || v_other_err
    ),
    (
      'R1-SQL-01: denied direct calls leave staff, memberships and audit unchanged',
      v_staff_after = v_staff_before
        AND v_membership_after = v_membership_before
        AND v_audit_after = v_audit_before,
      'staff=' || v_staff_before::text || '->' || v_staff_after::text
        || ' membership=' || v_membership_before::text || '->' || v_membership_after::text
        || ' audit=' || v_audit_before::text || '->' || v_audit_after::text
    );
END;
$$;

DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_member_user uuid := '1a030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_member_staff uuid := '1a040000-0000-4000-8000-000000000003';
  v_result public.rpc_result;
BEGIN
  -- The guarded RPC path keeps working after the grant closure.
  PERFORM pg_temp.r1_set_session(v_caller_user, v_org_a);
  v_result := public.update_staff_member(
    v_member_staff,
    'R1 RM01 Member',
    'doctor',
    ARRAY['1a020000-0000-4000-8000-000000000001'::uuid],
    '2010000111',
    '1a020000-0000-4000-8000-000000000001'::uuid,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-01: authorized RPC update still works',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-03 — deactivated/deleted staff lose tenant context immediately.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_member_user uuid := '1a030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_member_staff uuid := '1a040000-0000-4000-8000-000000000003';
  v_deactivate public.rpc_result;
  v_pref_before timestamptz;
  v_pref_after timestamptz;
  v_pref_org uuid;
  v_current_org uuid;
  v_patient_count bigint;
  v_sync_org uuid;
  v_mint_err text := '<none>';
  v_mint_token text;
  v_set_active public.rpc_result;
BEGIN
  PERFORM pg_temp.r1_set_session(v_caller_user, v_org_a);
  v_deactivate := public.set_staff_active(v_member_staff, false);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-03: fixture deactivate succeeds',
    v_deactivate.success,
    COALESCE(v_deactivate.error_code, 'ok')
  );

  -- Existing session: no tenant context the moment the staff row is inactive.
  PERFORM pg_temp.r1_set_session(v_member_user, v_org_a);
  v_current_org := public.current_org_id();
  SELECT count(*) INTO v_patient_count FROM public.patients;

  -- No fallback to another tenant: the member also holds membership in B.
  PERFORM set_config('role', 'postgres', true);
  v_sync_org := auth_internal.sync_active_organization(v_member_user);

  -- set_active_organization is forbidden and writes nothing.
  PERFORM pg_temp.r1_set_session(v_member_user, v_org_a);
  PERFORM set_config('role', 'postgres', true);
  SELECT updated_at, organization_id INTO v_pref_before, v_pref_org
  FROM ai_internal.user_active_organization WHERE user_id = v_member_user;
  PERFORM pg_temp.r1_set_session(v_member_user, v_org_a);
  v_set_active := public.set_active_organization(v_org_a);
  PERFORM set_config('role', 'postgres', true);
  SELECT updated_at INTO v_pref_after
  FROM ai_internal.user_active_organization WHERE user_id = v_member_user;

  -- Token mints remain blocked.
  PERFORM pg_temp.r1_set_session(v_member_user, v_org_a);
  BEGIN
    v_mint_token := public.issue_ai_token(1);
  EXCEPTION
    WHEN OTHERS THEN
      v_mint_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm01_results VALUES
    (
      'R1-SQL-03: deactivated staff session receives no tenant context immediately',
      v_current_org IS NULL AND v_patient_count = 0,
      'current_org_id=' || COALESCE(v_current_org::text, '<null>')
        || ' patient_rows=' || v_patient_count::text
    ),
    (
      'R1-SQL-03: sync_active_organization returns NULL for deactivated staff without selecting another tenant',
      v_sync_org IS NULL,
      'sync_org=' || COALESCE(v_sync_org::text, '<null>')
    ),
    (
      'R1-SQL-03: set_active_organization forbidden without a write for deactivated staff',
      NOT v_set_active.success
        AND v_set_active.error_code = 'FORBIDDEN'
        AND v_pref_org = '1a010000-0000-4000-8000-000000000001'::uuid
        AND v_pref_after IS NOT DISTINCT FROM v_pref_before,
      'error=' || COALESCE(v_set_active.error_code, '<null>')
        || ' pref_updated_at_unchanged=' || (v_pref_after IS NOT DISTINCT FROM v_pref_before)::text
    ),
    (
      'R1-SQL-03: token mints remain blocked for deactivated staff',
      v_mint_err <> '<none>',
      'error=' || v_mint_err
    );
END;
$$;

DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_member_user uuid := '1a030000-0000-4000-8000-000000000003';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_member_staff uuid := '1a040000-0000-4000-8000-000000000003';
  v_reactivate public.rpc_result;
  v_current_org uuid;
  v_patient_count bigint;
  v_membership_a text;
  v_membership_b text;
  v_pref_org uuid;
BEGIN
  -- Reactivation restores the preserved membership and preference only for
  -- the non-deleted staff member.
  PERFORM pg_temp.r1_set_session(v_caller_user, v_org_a);
  v_reactivate := public.set_staff_active(v_member_staff, true);
  PERFORM pg_temp.r1_set_session(v_member_user, v_org_a);
  v_current_org := public.current_org_id();
  SELECT count(*) INTO v_patient_count FROM public.patients;
  PERFORM set_config('role', 'postgres', true);
  SELECT m.role::text INTO v_membership_a FROM ai_internal.membership m
  WHERE m.user_id = v_member_user AND m.organization_id = v_org_a;
  SELECT m.role::text INTO v_membership_b FROM ai_internal.membership m
  WHERE m.user_id = v_member_user
    AND m.organization_id = '1a010000-0000-4000-8000-000000000002'::uuid;
  SELECT organization_id INTO v_pref_org
  FROM ai_internal.user_active_organization WHERE user_id = v_member_user;

  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-03: reactivation restores preserved memberships only for non-deleted staff',
    v_reactivate.success
      AND v_current_org = v_org_a
      AND v_patient_count = 1
      AND v_membership_a = 'doctor'
      AND v_membership_b = 'doctor'
      AND v_pref_org = v_org_a,
    'reactivate=' || COALESCE(v_reactivate.error_code, 'ok')
      || ' current_org_id=' || COALESCE(v_current_org::text, '<null>')
      || ' patient_rows=' || v_patient_count::text
      || ' membership_a=' || COALESCE(v_membership_a, '<null>')
      || ' membership_b=' || COALESCE(v_membership_b, '<null>')
      || ' pref_org=' || COALESCE(v_pref_org::text, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_delsubj_user uuid := '1a030000-0000-4000-8000-000000000004';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_delsubj_staff uuid := '1a040000-0000-4000-8000-000000000004';
  v_deactivate public.rpc_result;
  v_delete public.rpc_result;
  v_reactivate public.rpc_result;
  v_current_org uuid;
  v_membership_kept boolean;
  v_sync_org uuid;
BEGIN
  PERFORM pg_temp.r1_set_session(v_caller_user, v_org_a);
  v_deactivate := public.set_staff_active(v_delsubj_staff, false);
  v_delete := public.delete_staff_member(v_delsubj_staff);

  -- A deleted staff member's live session gets no tenant context; the
  -- membership row is preserved (no hard delete).
  PERFORM pg_temp.r1_set_session(v_delsubj_user, v_org_a);
  v_current_org := public.current_org_id();
  PERFORM set_config('role', 'postgres', true);
  SELECT EXISTS (
    SELECT 1 FROM ai_internal.membership m
    WHERE m.user_id = v_delsubj_user
      AND m.organization_id = v_org_a
  ) INTO v_membership_kept;
  v_sync_org := auth_internal.sync_active_organization(v_delsubj_user);

  -- Reactivation is not possible for deleted staff.
  PERFORM pg_temp.r1_set_session(v_caller_user, v_org_a);
  v_reactivate := public.set_staff_active(v_delsubj_staff, true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-03: soft-deleted staff loses tenant context, membership preserved, reactivation denied',
    v_deactivate.success
      AND v_delete.success
      AND v_current_org IS NULL
      AND v_membership_kept
      AND v_sync_org IS NULL
      AND NOT v_reactivate.success
      AND v_reactivate.error_code = 'STAFF_NOT_FOUND',
    'delete=' || COALESCE(v_delete.error_code, 'ok')
      || ' current_org_id=' || COALESCE(v_current_org::text, '<null>')
      || ' membership_kept=' || v_membership_kept::text
      || ' reactivate=' || COALESCE(v_reactivate.error_code, '<null>')
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-02 — membership billing authority follows the authorized staff change.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_target_user uuid := '1a030000-0000-4000-8000-000000000002';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_target_staff uuid := '1a040000-0000-4000-8000-000000000002';
  v_result public.rpc_result;
  v_membership_role text;
  v_staff_role text;
  v_billing public.rpc_result;
  v_token text;
  v_payload jsonb;
BEGIN
  -- Demotion through the guarded RPC updates the current-org membership.
  PERFORM pg_temp.r1_set_session(v_caller_user, v_org_a);
  v_result := public.update_staff_member(
    v_target_staff,
    'R1 RM01 Target',
    'doctor',
    ARRAY['1a020000-0000-4000-8000-000000000001'::uuid],
    NULL,
    '1a020000-0000-4000-8000-000000000001'::uuid,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT m.role::text INTO v_membership_role FROM ai_internal.membership m
  WHERE m.user_id = v_target_user AND m.organization_id = v_org_a;
  SELECT sm.role::text INTO v_staff_role FROM public.staff_members sm
  WHERE sm.id = v_target_staff;
  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-02: authorized demotion updates the current-org membership role atomically',
    v_result.success AND v_membership_role = 'doctor' AND v_staff_role = 'doctor',
    'rpc=' || COALESCE(v_result.error_code, 'ok')
      || ' membership_role=' || COALESCE(v_membership_role, '<null>')
      || ' staff_role=' || COALESCE(v_staff_role, '<null>')
  );

  -- Demotion denies all new billing mints immediately after commit.
  PERFORM pg_temp.r1_set_session(v_target_user, v_org_a);
  v_billing := public.issue_billing_token(1);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-02: demotion denies new billing mints immediately after commit',
    NOT v_billing.success AND v_billing.error_code = 'FORBIDDEN_ROLE',
    'error=' || COALESCE(v_billing.error_code, '<none>')
  );

  -- AI tokens carry the reduced membership role and scopes.
  PERFORM pg_temp.r1_set_session(v_target_user, v_org_a);
  BEGIN
    v_token := public.issue_ai_token(1);
    v_payload := pg_temp.r1_decode_jws_payload(v_token);
  EXCEPTION
    WHEN OTHERS THEN
      v_token := NULL;
      v_payload := NULL;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-02: demotion emits reduced AI token role and scopes',
    v_token IS NOT NULL
      AND v_payload ->> 'role' = 'doctor'
      AND v_payload -> 'scopes' = '["ai.visit_summary"]'::jsonb,
    'role=' || COALESCE(v_payload ->> 'role', '<none>')
      || ' scopes=' || COALESCE((v_payload -> 'scopes')::text, '<none>')
  );

  -- Promotion permits new billing mints again.
  PERFORM pg_temp.r1_set_session(v_caller_user, v_org_a);
  v_result := public.update_staff_member(
    v_target_staff,
    'R1 RM01 Target',
    'administrator',
    ARRAY['1a020000-0000-4000-8000-000000000001'::uuid],
    NULL,
    '1a020000-0000-4000-8000-000000000001'::uuid,
    NULL
  );
  PERFORM pg_temp.r1_set_session(v_target_user, v_org_a);
  v_billing := public.issue_billing_token(1);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-02: promotion permits new billing mints',
    v_result.success AND v_billing.success,
    'promote=' || COALESCE(v_result.error_code, 'ok')
      || ' mint=' || COALESCE(v_billing.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_dual_user uuid := '1a030000-0000-4000-8000-000000000005';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_org_b uuid := '1a010000-0000-4000-8000-000000000002';
  v_dual_staff uuid := '1a040000-0000-4000-8000-000000000005';
  v_result public.rpc_result;
  v_membership_a text;
  v_membership_b text;
BEGIN
  -- A user with different roles in A/B keeps B unchanged when A demotes.
  PERFORM pg_temp.r1_set_session(v_caller_user, v_org_a);
  v_result := public.update_staff_member(
    v_dual_staff,
    'R1 RM01 Dual',
    'doctor',
    ARRAY['1a020000-0000-4000-8000-000000000001'::uuid],
    NULL,
    '1a020000-0000-4000-8000-000000000001'::uuid,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT m.role::text INTO v_membership_a FROM ai_internal.membership m
  WHERE m.user_id = v_dual_user AND m.organization_id = v_org_a;
  SELECT m.role::text INTO v_membership_b FROM ai_internal.membership m
  WHERE m.user_id = v_dual_user AND m.organization_id = v_org_b;
  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-02: a user with different roles in A/B keeps B unchanged',
    v_result.success
      AND v_membership_a = 'doctor'
      AND v_membership_b = 'administrator',
    'rpc=' || COALESCE(v_result.error_code, 'ok')
      || ' membership_a=' || COALESCE(v_membership_a, '<null>')
      || ' membership_b=' || COALESCE(v_membership_b, '<null>')
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-02 step 3 (D-1) — read-only reconciliation lists role mismatches.
-- The listing captured here is saved in docs/review/abo-remediation/RM01.md.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_recon_user uuid := '1a030000-0000-4000-8000-000000000006';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_row record;
  v_listing text := '';
  v_listing_after text := '';
  v_recon_listed boolean := false;
  v_recon_listed_after boolean := false;
  v_copy_count int := 0;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  -- Read-only reconciliation (D-1): membership/staff role mismatches with the
  -- user's membership count.
  FOR v_row IN
    SELECT m.user_id, m.organization_id, m.role AS membership_role, sm.role AS staff_role,
      (SELECT count(*) FROM ai_internal.membership m2 WHERE m2.user_id = m.user_id) AS membership_count
    FROM ai_internal.membership m
    JOIN public.staff_members sm ON sm.auth_user_id = m.user_id
    WHERE m.role <> sm.role
    ORDER BY m.user_id, m.organization_id
  LOOP
    v_listing := v_listing || format(
      '(user_id=%s, organization_id=%s, membership.role=%s, staff.role=%s, memberships=%s); ',
      v_row.user_id, v_row.organization_id, v_row.membership_role, v_row.staff_role, v_row.membership_count
    );
    IF v_row.user_id = v_recon_user THEN
      v_recon_listed := true;
    END IF;
  END LOOP;

  -- D-1 single-membership copy (the repair rule): the recon user holds exactly
  -- one membership, so staff.role is copied to it.
  UPDATE ai_internal.membership m
  SET role = sm.role
  FROM public.staff_members sm
  WHERE sm.auth_user_id = m.user_id
    AND m.user_id = v_recon_user
    AND NOT EXISTS (
      SELECT 1 FROM ai_internal.membership m2
      WHERE m2.user_id = m.user_id AND m2.organization_id <> m.organization_id
    )
    AND m.role <> sm.role;
  GET DIAGNOSTICS v_copy_count = ROW_COUNT;

  FOR v_row IN
    SELECT m.user_id
    FROM ai_internal.membership m
    JOIN public.staff_members sm ON sm.auth_user_id = m.user_id
    WHERE m.role <> sm.role
      AND m.user_id = v_recon_user
  LOOP
    v_recon_listed_after := true;
  END LOOP;

  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-02: read-only reconciliation lists membership/staff role mismatches',
    v_recon_listed AND NOT v_recon_listed_after AND v_copy_count = 1,
    'listing=' || COALESCE(NULLIF(btrim(v_listing), ''), '<empty>')
      || ' | after_single_membership_copy: recon user listed=' || v_recon_listed_after::text
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- R1-SQL-06 — the AI issuer enforces its configured rate limit again.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_member_user uuid := '1a030000-0000-4000-8000-000000000003';
  v_target_user uuid := '1a030000-0000-4000-8000-000000000002';
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_member_staff uuid := '1a040000-0000-4000-8000-000000000003';
  v_target_staff uuid := '1a040000-0000-4000-8000-000000000002';
  v_ceiling int := 2;
  v_mint_err text;
  v_token text;
  v_ledger_ai_member int;
  v_ledger_ai_target int;
  v_ledger_abo_target int;
  v_billing public.rpc_result;
BEGIN
  -- Configure a small AI ceiling for the test (window left at the default).
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_internal.app_settings (key, value_json, created_by, updated_by)
  VALUES ('ai.issuer.rate_limit.ceiling', to_jsonb(v_ceiling), v_caller_user, v_caller_user)
  ON CONFLICT (key) DO UPDATE SET value_json = to_jsonb(v_ceiling), is_deleted = false;

  PERFORM pg_temp.r1_set_session(v_member_user, v_org_a);
  v_token := public.issue_ai_token(1);          -- 1st mint ok
  v_token := public.issue_ai_token(1);          -- 2nd mint ok
  v_mint_err := '<none>';
  BEGIN
    v_token := public.issue_ai_token(1);        -- 3rd mint must refuse
  EXCEPTION
    WHEN OTHERS THEN
      v_mint_err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_ledger_ai_member
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_member_staff
    AND i.aud = 'ai-platform'
    AND i.is_deleted = false;

  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-06: the configured AI ceiling''s next call fails without a new ledger row',
    v_mint_err = 'RATE_LIMITED' AND v_ledger_ai_member = v_ceiling,
    'error=' || v_mint_err || ' ledger=' || v_ledger_ai_member::text
  );

  -- Billing mints do not consume AI quota and vice versa.
  PERFORM pg_temp.r1_set_session(v_target_user, v_org_a);
  v_billing := public.issue_billing_token(1);
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_ledger_ai_member
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_member_staff AND i.aud = 'ai-platform' AND i.is_deleted = false;
  SELECT count(*) INTO v_ledger_ai_target
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_target_staff AND i.aud = 'ai-platform' AND i.is_deleted = false;
  SELECT count(*) INTO v_ledger_abo_target
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_target_staff AND i.aud = 'abo' AND i.is_deleted = false;

  PERFORM pg_temp.r1_set_session(v_member_user, v_org_a);
  v_mint_err := '<none>';
  BEGIN
    v_token := public.issue_ai_token(1);
  EXCEPTION
    WHEN OTHERS THEN
      v_mint_err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO r1_rm01_results VALUES (
    'R1-SQL-06: billing mints do not consume AI quota and vice versa',
    v_billing.success
      AND v_ledger_ai_member = v_ceiling
      AND v_ledger_abo_target = 2
      AND v_ledger_ai_target = 1
      AND v_mint_err = 'RATE_LIMITED',
    'billing_ok=' || v_billing.success::text
      || ' member_ai_ledger=' || v_ledger_ai_member::text
      || ' target_ai_ledger=' || v_ledger_ai_target::text
      || ' target_abo_ledger=' || v_ledger_abo_target::text
      || ' member_mint=' || v_mint_err
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
  FROM r1_rm01_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'r1_rm01_staff_authority failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM r1_rm01_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

DO $$
DECLARE
  v_caller_user uuid := '1a030000-0000-4000-8000-000000000001';
  v_target_user uuid := '1a030000-0000-4000-8000-000000000002';
  v_member_user uuid := '1a030000-0000-4000-8000-000000000003';
  v_delsubj_user uuid := '1a030000-0000-4000-8000-000000000004';
  v_dual_user uuid := '1a030000-0000-4000-8000-000000000005';
  v_recon_user uuid := '1a030000-0000-4000-8000-000000000006';
  v_org_a uuid := '1a010000-0000-4000-8000-000000000001';
  v_org_b uuid := '1a010000-0000-4000-8000-000000000002';
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.audit_log
  WHERE organization_id IN (v_org_a, v_org_b)
    OR user_id IN (v_caller_user, v_target_user, v_member_user, v_delsubj_user, v_dual_user, v_recon_user);
  DELETE FROM public.roles_permissions WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.patients WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_branch_assignments WHERE branch_id IN (
    SELECT id FROM public.branches WHERE organization_id IN (v_org_a, v_org_b)
  );
  DELETE FROM ai_internal.ai_token_issuance WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM ai_internal.membership WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM ai_internal.user_active_organization WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.branches WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_members WHERE auth_user_id IN (
    v_caller_user, v_target_user, v_member_user, v_delsubj_user, v_dual_user, v_recon_user
  );
  DELETE FROM ai_internal.app_settings
  WHERE key IN ('ai.issuer.rate_limit.ceiling', 'ai.issuer.rate_limit.window_seconds');
  DELETE FROM auth.users WHERE id IN (
    v_caller_user, v_target_user, v_member_user, v_delsubj_user, v_dual_user, v_recon_user
  );
END;
$$;

COMMIT;

SELECT test_name, passed, detail
FROM r1_rm01_results
ORDER BY test_name;