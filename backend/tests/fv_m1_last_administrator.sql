-- FV-M1 (FR01) — membership-based last-administrator guard completion checks.
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/fv_m1_last_administrator.sql

BEGIN;

CREATE TEMP TABLE fv_m1_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.fv_set_session(p_user_id uuid, p_org_id uuid)
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

-- -----------------------------------------------------------------------------
-- Fixture.
--   Org A: X (global doctor, administrator membership A, doctor membership B,
--          assigned to both branches), Z (doctor in A).
--   Org B: BADM (global + membership administrator).
--   Org C: X2 (global + membership administrator), Y (global administrator,
--          membership doctor in C).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org_a uuid := 'f1010000-0000-4000-8000-000000000001';
  v_org_b uuid := 'f1010000-0000-4000-8000-000000000002';
  v_org_c uuid := 'f1010000-0000-4000-8000-000000000003';
  v_br_a uuid := 'f1020000-0000-4000-8000-000000000001';
  v_br_b uuid := 'f1020000-0000-4000-8000-000000000002';
  v_br_c uuid := 'f1020000-0000-4000-8000-000000000003';
  v_x uuid := 'f1030000-0000-4000-8000-000000000001';
  v_z uuid := 'f1030000-0000-4000-8000-000000000002';
  v_badm uuid := 'f1030000-0000-4000-8000-000000000003';
  v_x2 uuid := 'f1030000-0000-4000-8000-000000000004';
  v_y uuid := 'f1030000-0000-4000-8000-000000000005';
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.audit_log WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.roles_permissions WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.staff_branch_assignments WHERE branch_id IN (
    SELECT id FROM public.branches WHERE organization_id IN (v_org_a, v_org_b, v_org_c)
  );
  DELETE FROM ai_internal.ai_token_issuance WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM ai_internal.membership WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM ai_internal.user_active_organization WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.branches WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.staff_members WHERE auth_user_id IN (v_x, v_z, v_badm, v_x2, v_y);
  DELETE FROM auth.users WHERE id IN (v_x, v_z, v_badm, v_x2, v_y);

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  SELECT
    u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    u.email, extensions.crypt('pw-fv-m1', extensions.gen_salt('bf')), now(), now(), now()
  FROM (VALUES
    (v_x,    'fv-m1-x'),
    (v_z,    'fv-m1-z'),
    (v_badm, 'fv-m1-badm'),
    (v_x2,   'fv-m1-x2'),
    (v_y,    'fv-m1-y')
  ) AS u(id, email);

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'FV M1 Org A', v_badm, v_badm),
    (v_org_b, 'FV M1 Org B', v_badm, v_badm),
    (v_org_c, 'FV M1 Org C', v_badm, v_badm);

  INSERT INTO public.branches (id, organization_id, name, code, is_active, created_by, updated_by)
  VALUES
    (v_br_a, v_org_a, 'FV M1 Main A', 'FMA', true, v_badm, v_badm),
    (v_br_b, v_org_b, 'FV M1 Main B', 'FMB', true, v_badm, v_badm),
    (v_br_c, v_org_c, 'FV M1 Main C', 'FMC', true, v_badm, v_badm);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    ('f1040000-0000-4000-8000-000000000001', v_x,    'FV M1 X',    'doctor',        v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000002', v_z,    'FV M1 Z',    'doctor',        v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000003', v_badm, 'FV M1 BADM', 'administrator', v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000004', v_x2,   'FV M1 X2',   'administrator', v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000005', v_y,    'FV M1 Y',    'administrator', v_badm, v_badm);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    ('f1040000-0000-4000-8000-000000000001', v_br_a, true,  v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000001', v_br_b, false, v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000002', v_br_a, true,  v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000003', v_br_b, true,  v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000004', v_br_c, true,  v_badm, v_badm),
    ('f1040000-0000-4000-8000-000000000005', v_br_c, true,  v_badm, v_badm);

  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES
    (v_x,    v_org_a, 'administrator'),
    (v_x,    v_org_b, 'doctor'),
    (v_z,    v_org_a, 'doctor'),
    (v_badm, v_org_b, 'administrator'),
    (v_x2,   v_org_c, 'administrator'),
    (v_y,    v_org_c, 'doctor');

  INSERT INTO ai_internal.user_active_organization (user_id, organization_id)
  VALUES (v_x, v_org_a), (v_z, v_org_a), (v_badm, v_org_b), (v_x2, v_org_c), (v_y, v_org_c);

  -- Organization inserts auto-seed the default matrix; make manage_staff explicit.
  INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted, created_by, updated_by)
  VALUES
    (v_org_a, 'administrator', 'settings.manage_staff', true, v_badm, v_badm),
    (v_org_b, 'administrator', 'settings.manage_staff', true, v_badm, v_badm),
    (v_org_c, 'administrator', 'settings.manage_staff', true, v_badm, v_badm)
  ON CONFLICT (organization_id, role, permission_key) DO UPDATE
    SET is_granted = true, is_deleted = false, updated_at = now(),
        created_by = v_badm, updated_by = v_badm;

  INSERT INTO fv_m1_results VALUES ('fixture_setup', true, 'orgs, staff and memberships ready');
END;
$$;

-- FV-M1 scenario 1: X is A's only administrator membership with global role
-- doctor. Self-demotion in A is refused and A's membership is unchanged.
DO $$
DECLARE
  v_org_a uuid := 'f1010000-0000-4000-8000-000000000001';
  v_x uuid := 'f1030000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_role text;
BEGIN
  PERFORM pg_temp.fv_set_session(v_x, v_org_a);
  v_result := public.update_staff_member(
    'f1040000-0000-4000-8000-000000000001', 'FV M1 X', 'receptionist',
    ARRAY['f1020000-0000-4000-8000-000000000001'::uuid],
    NULL, 'f1020000-0000-4000-8000-000000000001'::uuid, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT m.role::text INTO v_role FROM ai_internal.membership m
  WHERE m.user_id = v_x AND m.organization_id = v_org_a;
  INSERT INTO fv_m1_results VALUES (
    'FV-M1: only membership administrator with divergent global role cannot be demoted',
    NOT v_result.success AND v_result.error_code = 'LAST_ADMINISTRATOR' AND v_role = 'administrator',
    COALESCE(v_result.error_code, 'ok') || ' membership=' || COALESCE(v_role, '<none>')
  );
END;
$$;

-- FV-M1 scenario 2: Y has global role administrator but membership doctor in
-- C. Y is not counted, so X2's demotion is refused.
DO $$
DECLARE
  v_org_c uuid := 'f1010000-0000-4000-8000-000000000003';
  v_x2 uuid := 'f1030000-0000-4000-8000-000000000004';
  v_result public.rpc_result;
  v_role text;
BEGIN
  PERFORM pg_temp.fv_set_session(v_x2, v_org_c);
  v_result := public.update_staff_member(
    'f1040000-0000-4000-8000-000000000004', 'FV M1 X2', 'doctor',
    ARRAY['f1020000-0000-4000-8000-000000000003'::uuid],
    NULL, 'f1020000-0000-4000-8000-000000000003'::uuid, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT m.role::text INTO v_role FROM ai_internal.membership m
  WHERE m.user_id = v_x2 AND m.organization_id = v_org_c;
  INSERT INTO fv_m1_results VALUES (
    'FV-M1: global administrator without administrator membership is not counted',
    NOT v_result.success AND v_result.error_code = 'LAST_ADMINISTRATOR' AND v_role = 'administrator',
    COALESCE(v_result.error_code, 'ok') || ' membership=' || COALESCE(v_role, '<none>')
  );
END;
$$;

-- FV-M1 scenario 3: BADM (org B administrator) deactivates X from org B, where
-- X is not an administrator. Refused while X is A's only administrator.
DO $$
DECLARE
  v_org_b uuid := 'f1010000-0000-4000-8000-000000000002';
  v_badm uuid := 'f1030000-0000-4000-8000-000000000003';
  v_result public.rpc_result;
  v_active boolean;
BEGIN
  PERFORM pg_temp.fv_set_session(v_badm, v_org_b);
  v_result := public.set_staff_active('f1040000-0000-4000-8000-000000000001', false);
  PERFORM set_config('role', 'postgres', true);
  SELECT sm.is_active INTO v_active FROM public.staff_members sm
  WHERE sm.id = 'f1040000-0000-4000-8000-000000000001';
  INSERT INTO fv_m1_results VALUES (
    'FV-M1: deactivation from another org is refused while target is the last administrator elsewhere',
    NOT v_result.success AND v_result.error_code = 'LAST_ADMINISTRATOR' AND v_active,
    COALESCE(v_result.error_code, 'ok') || ' active=' || COALESCE(v_active::text, '<null>')
  );
END;
$$;

-- FV-M1 regression: once another administrator membership exists in A, the
-- demotion succeeds, and the same change in A is now allowed.
DO $$
DECLARE
  v_org_a uuid := 'f1010000-0000-4000-8000-000000000001';
  v_x uuid := 'f1030000-0000-4000-8000-000000000001';
  v_z uuid := 'f1030000-0000-4000-8000-000000000002';
  v_result public.rpc_result;
  v_role text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  UPDATE ai_internal.membership SET role = 'administrator'
  WHERE user_id = v_z AND organization_id = v_org_a;

  PERFORM pg_temp.fv_set_session(v_x, v_org_a);
  v_result := public.update_staff_member(
    'f1040000-0000-4000-8000-000000000001', 'FV M1 X', 'receptionist',
    ARRAY['f1020000-0000-4000-8000-000000000001'::uuid],
    NULL, 'f1020000-0000-4000-8000-000000000001'::uuid, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT m.role::text INTO v_role FROM ai_internal.membership m
  WHERE m.user_id = v_x AND m.organization_id = v_org_a;
  INSERT INTO fv_m1_results VALUES (
    'FV-M1: single-org demotion succeeds when another administrator membership exists',
    v_result.success AND v_role = 'receptionist',
    COALESCE(v_result.error_code, 'ok') || ' membership=' || COALESCE(v_role, '<none>')
  );
END;
$$;

-- Cleanup.
DO $$
DECLARE
  v_org_a uuid := 'f1010000-0000-4000-8000-000000000001';
  v_org_b uuid := 'f1010000-0000-4000-8000-000000000002';
  v_org_c uuid := 'f1010000-0000-4000-8000-000000000003';
  v_users uuid[] := ARRAY[
    'f1030000-0000-4000-8000-000000000001', 'f1030000-0000-4000-8000-000000000002',
    'f1030000-0000-4000-8000-000000000003', 'f1030000-0000-4000-8000-000000000004',
    'f1030000-0000-4000-8000-000000000005'
  ]::uuid[];
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.audit_log
  WHERE organization_id IN (v_org_a, v_org_b, v_org_c) OR user_id = ANY (v_users);
  DELETE FROM public.roles_permissions WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.staff_branch_assignments WHERE branch_id IN (
    SELECT id FROM public.branches WHERE organization_id IN (v_org_a, v_org_b, v_org_c)
  );
  DELETE FROM ai_internal.ai_token_issuance WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM ai_internal.membership WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM ai_internal.user_active_organization WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.branches WHERE organization_id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b, v_org_c);
  DELETE FROM public.staff_members WHERE auth_user_id = ANY (v_users);
  DELETE FROM auth.users WHERE id = ANY (v_users);
END;
$$;

COMMIT;

SELECT test_name, passed, detail
FROM fv_m1_results
ORDER BY test_name;
