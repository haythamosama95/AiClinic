-- Auth security extensions for Phase 1-4 (RLS, anon RPC deny, permissions seed, inactive staff).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/auth_security_extensions.sql

BEGIN;

CREATE TEMP TABLE auth_security_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

-- Permission matrix spot checks (seed migration).
DO $$
DECLARE
  v_doctor_manage_staff boolean;
  v_lab_patient_keys int;
  v_owner_grants int;
BEGIN
  SELECT is_granted INTO v_doctor_manage_staff
  FROM public.roles_permissions
  WHERE role = 'doctor' AND permission_key = 'settings.manage_staff' AND is_deleted = false;

  SELECT count(*) INTO v_lab_patient_keys
  FROM public.roles_permissions
  WHERE role = 'lab_staff'
    AND permission_key LIKE 'patients.%'
    AND is_granted = true
    AND is_deleted = false;

  SELECT count(*) INTO v_owner_grants
  FROM public.roles_permissions
  WHERE role = 'administrator' AND is_granted = true AND is_deleted = false;

  INSERT INTO auth_security_results VALUES
    ('doctor_denied_manage_staff', COALESCE(NOT v_doctor_manage_staff, true), 'doctor settings.manage_staff'),
    ('lab_staff_single_patient_grant', v_lab_patient_keys = 1, 'lab patient grants=' || v_lab_patient_keys::text),
    ('owner_has_grants', v_owner_grants > 5, 'owner grants=' || v_owner_grants::text);
END;
$$;

-- Inactive staff: empty claims.
DO $$
DECLARE
  v_inactive_user uuid := 'f1000000-0000-4000-8000-000000000f01';
  v_inactive_staff uuid := 'f2000000-0000-4000-8000-000000000f02';
  v_claims jsonb;
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (
    v_inactive_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'inactive',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_active, created_by, updated_by)
  VALUES (
    v_inactive_staff,
    v_inactive_user,
    'Inactive Staff',
    'receptionist',
    false,
    v_inactive_user,
    v_inactive_user
  )
  ON CONFLICT (id) DO NOTHING;

  v_claims := auth_internal.build_staff_claims(v_inactive_user);

  INSERT INTO auth_security_results VALUES (
    'inactive_staff_empty_claims',
    v_claims = '{}'::jsonb OR v_claims IS NULL,
    'claims=' || COALESCE(v_claims::text, '<null>')
  );
END;
$$;

-- Auth user without staff row: empty claims.
DO $$
DECLARE
  v_orphan_user uuid := 'f1000000-0000-4000-8000-000000000f03';
  v_claims jsonb;
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (
    v_orphan_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'orphan',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  v_claims := auth_internal.build_staff_claims(v_orphan_user);

  INSERT INTO auth_security_results VALUES (
    'orphan_auth_user_empty_claims',
    v_claims = '{}'::jsonb OR v_claims IS NULL,
    'claims=' || COALESCE(v_claims::text, '<null>')
  );
END;
$$;

-- Subscription cache expiry must not block claims (login not subscription-gated in V1-1).
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_claims jsonb;
BEGIN
  INSERT INTO public.subscription_cache (organization_id, tier, valid_until, last_checked_at)
  SELECT o.id, 'expired', now() - interval '1 day', now()
  FROM public.organizations o
  LIMIT 1
  ON CONFLICT (organization_id) DO UPDATE
  SET tier = EXCLUDED.tier, valid_until = EXCLUDED.valid_until, last_checked_at = EXCLUDED.last_checked_at;

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user);

  INSERT INTO auth_security_results VALUES (
    'subscription_expired_does_not_block_claims',
    v_claims ? 'staff_member_id',
    'has_staff_member_id=' || (v_claims ? 'staff_member_id')::text
  );
END;
$$;

-- RLS write-deny: authenticated role cannot mutate audit_log or subscription_cache.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_org_id uuid;
  v_insert_failed boolean;
  v_rows int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT o.id
  INTO v_org_id
  FROM public.organizations o
  JOIN public.staff_members sm ON sm.auth_user_id = v_bootstrap_user
  WHERE sm.is_deleted = false
  LIMIT 1;

  IF v_org_id IS NULL THEN
    SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
  END IF;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', COALESCE(v_org_id::text, ''),
      'branch_ids', '',
      'staff_member_id', v_bootstrap_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_insert_failed := false;
  BEGIN
    INSERT INTO public.audit_log (user_id, organization_id, action, table_name)
    VALUES (v_bootstrap_user, v_org_id, 'test.insert', 'organizations');
  EXCEPTION
    WHEN OTHERS THEN
      v_insert_failed := true;
  END;
  IF NOT v_insert_failed THEN
    SELECT count(*)::int INTO v_rows
    FROM public.audit_log
    WHERE action = 'test.insert' AND user_id = v_bootstrap_user;
    v_insert_failed := v_rows = 0;
  END IF;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_security_results VALUES (
    'authenticated_audit_log_insert_denied',
    v_insert_failed,
    'insert blocked or 0 rows'
  );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', COALESCE(v_org_id::text, ''),
      'branch_ids', '',
      'staff_member_id', v_bootstrap_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_insert_failed := false;
  v_rows := 0;
  BEGIN
    UPDATE public.audit_log
    SET action = 'test.update'
    WHERE organization_id = v_org_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    WHEN OTHERS THEN
      v_insert_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_security_results VALUES (
    'authenticated_audit_log_update_denied',
    v_insert_failed OR v_rows = 0,
    'updated_rows=' || v_rows::text
  );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', COALESCE(v_org_id::text, ''),
      'branch_ids', '',
      'staff_member_id', v_bootstrap_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_insert_failed := false;
  v_rows := 0;
  BEGIN
    DELETE FROM public.audit_log WHERE organization_id = v_org_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    WHEN OTHERS THEN
      v_insert_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_security_results VALUES (
    'authenticated_audit_log_delete_denied',
    v_insert_failed OR v_rows = 0,
    'deleted_rows=' || v_rows::text
  );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', COALESCE(v_org_id::text, ''),
      'branch_ids', '',
      'staff_member_id', v_bootstrap_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_insert_failed := false;
  BEGIN
    INSERT INTO public.subscription_cache (organization_id, tier, valid_until, last_checked_at)
    VALUES (v_org_id, 'test-tier', now() + interval '30 days', now());
  EXCEPTION
    WHEN OTHERS THEN
      v_insert_failed := true;
  END;
  IF NOT v_insert_failed THEN
    SELECT count(*)::int INTO v_rows
    FROM public.subscription_cache
    WHERE organization_id = v_org_id AND tier = 'test-tier';
    v_insert_failed := v_rows = 0;
  END IF;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth_security_results VALUES (
    'authenticated_subscription_cache_insert_denied',
    v_insert_failed,
    'insert blocked or 0 rows'
  );
END;
$$;

-- Anon cannot execute privileged RPCs.
DO $$
BEGIN
  SET LOCAL role anon;
  BEGIN
    PERFORM public.bootstrap_create_organization('Anon Org');
    PERFORM set_config('role', 'postgres', true);
    INSERT INTO auth_security_results VALUES ('anon_bootstrap_denied', false, 'rpc succeeded');
    PERFORM set_config('role', 'postgres', true);
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    INSERT INTO auth_security_results VALUES ('anon_bootstrap_denied', true, SQLERRM);
  END;
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM auth_security_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'auth_security_extensions failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM auth_security_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM auth_security_results ORDER BY test_name;
