-- P5.1 issuer RPC contract tests (E2E-P5.1-04, 05, 08).
-- Run: psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/issuer_rpc.sql

BEGIN;

CREATE TEMP TABLE issuer_rpc_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

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

CREATE OR REPLACE FUNCTION pg_temp.set_authenticated_session(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.capture_contract_version_error(p_sql text)
RETURNS TABLE (
  raised boolean,
  message text,
  detail text
)
LANGUAGE plpgsql
AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    RETURN QUERY SELECT false, '<none>'::text, '<none>'::text;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN QUERY SELECT true, SQLERRM, COALESCE(PG_EXCEPTION_DETAIL, '<null>');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.issuer_rpc_admin_fixture()
RETURNS TABLE (
  user_id uuid,
  staff_id uuid,
  org_id uuid,
  branch_id uuid
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'development', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log WHERE organization_id IS NOT NULL;
  DELETE FROM public.app_settings WHERE true;
  DELETE FROM public.subscription_cache WHERE true;
  IF to_regclass('ai_internal.ai_token_issuance') IS NOT NULL THEN
    DELETE FROM ai_internal.ai_token_issuance WHERE true;
  END IF;
  IF to_regclass('ai_internal.installation_keys') IS NOT NULL THEN
    DELETE FROM ai_internal.installation_keys WHERE true;
  END IF;

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);

  v_result := public.bootstrap_create_organization('Issuer RPC Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'fixture bootstrap_create_organization failed: %', v_result.error_code;
  END IF;
  v_org_id := (v_result.data ->> 'organization_id')::uuid;

  v_result := public.bootstrap_create_branch(v_org_id, 'Issuer RPC Branch', NULL, NULL, 'IRPC', NULL);
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'fixture bootstrap_create_branch failed: %', v_result.error_code;
  END IF;
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  SELECT sm.auth_user_id, v_org_id, sm.role
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_bootstrap_user
    AND sm.is_deleted = false
  ON CONFLICT (user_id, organization_id) DO NOTHING;

  RETURN QUERY SELECT v_bootstrap_user, v_bootstrap_staff, v_org_id, v_branch_id;
END;
$$;

-- E2E-P5.1-04: Version 2 raises CONTRACT_VERSION_UNSUPPORTED and rpc_result carries contract_version.
DO $$
DECLARE
  v_versioned_sig boolean;
  v_rows_before bigint;
  v_rows_after bigint;
  v_v2 boolean;
  v_v2_message text;
  v_v2_detail text;
  v_null boolean;
  v_null_message text;
  v_null_detail text;
  v_admin_user uuid;
  v_admin_staff uuid;
  v_org_id uuid;
  v_branch_id uuid;
  v_billing public.rpc_result;
  v_billing_version int;
  v_passed boolean;
  v_detail text;
BEGIN
  v_versioned_sig := to_regprocedure('public.issue_ai_token(integer)') IS NOT NULL
    AND to_regprocedure('public.issue_billing_token(integer)') IS NOT NULL;

  IF NOT v_versioned_sig THEN
    INSERT INTO issuer_rpc_results VALUES (
      'E2E-P5.1-04 Version 2 raises CONTRACT_VERSION_UNSUPPORTED and rpc_result carries contract_version',
      false,
      'versioned issue_ai_token(integer) or issue_billing_token(integer) is absent'
    );
    RETURN;
  END IF;

  PERFORM set_config('role', 'postgres', true);
  IF to_regclass('ai_internal.ai_token_issuance') IS NOT NULL THEN
    SELECT count(*) INTO v_rows_before FROM ai_internal.ai_token_issuance;
  ELSE
    v_rows_before := 0;
  END IF;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  SELECT r.raised, r.message, r.detail
  INTO v_v2, v_v2_message, v_v2_detail
  FROM pg_temp.capture_contract_version_error('SELECT public.issue_ai_token(2)') r;

  SELECT r.raised, r.message, r.detail
  INTO v_null, v_null_message, v_null_detail
  FROM pg_temp.capture_contract_version_error('SELECT public.issue_ai_token()') r;

  PERFORM set_config('role', 'postgres', true);
  IF to_regclass('ai_internal.ai_token_issuance') IS NOT NULL THEN
    SELECT count(*) INTO v_rows_after FROM ai_internal.ai_token_issuance;
  ELSE
    v_rows_after := 0;
  END IF;

  SELECT f.user_id, f.staff_id, f.org_id, f.branch_id
  INTO v_admin_user, v_admin_staff, v_org_id, v_branch_id
  FROM pg_temp.issuer_rpc_admin_fixture() f;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  IF to_regclass('ai_internal.installation_keys') IS NOT NULL THEN
    PERFORM public.enroll_installation_keypair();
  END IF;

  v_billing := public.issue_billing_token(1);
  v_billing_version := v_billing.contract_version;

  v_passed := v_v2
    AND v_v2_message LIKE '%CONTRACT_VERSION_UNSUPPORTED%'
    AND v_v2_detail LIKE '%accepted_versions%'
    AND v_v2_detail LIKE '%0%'
    AND v_v2_detail LIKE '%1%'
    AND v_null
    AND v_null_message LIKE '%CONTRACT_VERSION_UNSUPPORTED%'
    AND v_null_detail LIKE '%accepted_versions%'
    AND v_rows_before = v_rows_after
    AND v_billing.success
    AND v_billing_version = 1;

  v_detail := 'v2_raised=' || v_v2::text
    || ' v2_msg=' || COALESCE(v_v2_message, '<null>')
    || ' v2_detail=' || COALESCE(v_v2_detail, '<null>')
    || ' null_raised=' || v_null::text
    || ' null_msg=' || COALESCE(v_null_message, '<null>')
    || ' rows_before=' || v_rows_before::text
    || ' rows_after=' || v_rows_after::text
    || ' billing_contract_version=' || COALESCE(v_billing_version::text, '<null>');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO issuer_rpc_results VALUES (
    'E2E-P5.1-04 Version 2 raises CONTRACT_VERSION_UNSUPPORTED and rpc_result carries contract_version',
    v_passed,
    v_detail
  );
END;
$$;

-- E2E-P5.1-05: 21st billing token in 10 min is RATE_LIMITED.
DO $$
DECLARE
  v_admin_user uuid;
  v_admin_staff uuid;
  v_org_id uuid;
  v_branch_id uuid;
  v_result public.rpc_result;
  v_i int;
  v_abo_count int;
  v_passed boolean;
  v_detail text;
BEGIN
  IF to_regprocedure('public.issue_billing_token(integer)') IS NULL THEN
    INSERT INTO issuer_rpc_results VALUES (
      'E2E-P5.1-05 21st billing token in 10 min is RATE_LIMITED',
      false,
      'public.issue_billing_token(integer) is absent'
    );
    RETURN;
  END IF;

  SELECT f.user_id, f.staff_id, f.org_id, f.branch_id
  INTO v_admin_user, v_admin_staff, v_org_id, v_branch_id
  FROM pg_temp.issuer_rpc_admin_fixture() f;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  IF to_regclass('ai_internal.installation_keys') IS NOT NULL THEN
    PERFORM public.enroll_installation_keypair();
  END IF;

  FOR v_i IN 1..20 LOOP
    v_result := public.issue_billing_token(1);
    IF NOT v_result.success THEN
      INSERT INTO issuer_rpc_results VALUES (
        'E2E-P5.1-05 21st billing token in 10 min is RATE_LIMITED',
        false,
        'billing mint ' || v_i::text || ' failed: ' || COALESCE(v_result.error_code, '<null>')
      );
      RETURN;
    END IF;
  END LOOP;

  v_result := public.issue_billing_token(1);

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int
  INTO v_abo_count
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_admin_staff
    AND i.aud = 'abo'
    AND i.is_deleted = false;

  v_passed := (NOT v_result.success)
    AND v_result.error_code = 'RATE_LIMITED'
    AND v_abo_count = 20;

  v_detail := 'success=' || v_result.success::text
    || ' error_code=' || COALESCE(v_result.error_code, '<null>')
    || ' abo_rows=' || v_abo_count::text;

  INSERT INTO issuer_rpc_results VALUES (
    'E2E-P5.1-05 21st billing token in 10 min is RATE_LIMITED',
    v_passed,
    v_detail
  );
END;
$$;

-- E2E-P5.1-08: Membership switched to org B yields token org B.
DO $$
DECLARE
  v_user_id uuid := '08708000-0000-4000-8000-000000000001';
  v_staff_id uuid := '08708100-0000-4000-8000-000000000001';
  v_org_a uuid := '08708200-0000-4000-8000-00000000000a';
  v_org_b uuid := '08708200-0000-4000-8000-00000000000b';
  v_branch_a uuid := '08708300-0000-4000-8000-00000000000a';
  v_branch_b uuid := '08708300-0000-4000-8000-00000000000b';
  v_set public.rpc_result;
  v_hook jsonb;
  v_token text;
  v_payload jsonb;
  v_current_org uuid;
  v_passed boolean;
  v_detail text;
BEGIN
  IF to_regprocedure('public.issue_ai_token(integer)') IS NULL THEN
    INSERT INTO issuer_rpc_results VALUES (
      'E2E-P5.1-08 Membership switched to org B yields token org B',
      false,
      'public.issue_ai_token(integer) is absent'
    );
    RETURN;
  END IF;

  IF to_regprocedure('public.set_active_organization(uuid)') IS NULL THEN
    INSERT INTO issuer_rpc_results VALUES (
      'E2E-P5.1-08 Membership switched to org B yields token org B',
      false,
      'public.set_active_organization is absent'
    );
    RETURN;
  END IF;

  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'development', true);

  DELETE FROM ai_internal.user_active_organization WHERE user_id = v_user_id;
  DELETE FROM ai_internal.membership WHERE user_id = v_user_id;
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id = v_staff_id;
  DELETE FROM public.staff_members WHERE id = v_staff_id;
  DELETE FROM public.audit_log
  WHERE user_id = v_user_id
     OR organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b);
  DELETE FROM public.organization_billing_settings WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users WHERE id = v_user_id;
  IF to_regclass('ai_internal.ai_token_issuance') IS NOT NULL THEN
    DELETE FROM ai_internal.ai_token_issuance WHERE true;
  END IF;
  IF to_regclass('ai_internal.installation_keys') IS NOT NULL THEN
    DELETE FROM ai_internal.installation_keys WHERE true;
  END IF;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'e2e-p51-08',
    extensions.crypt('pw-e2e-p51-08', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  );

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'E2E P5.1 Org A', v_user_id, v_user_id),
    (v_org_b, 'E2E P5.1 Org B', v_user_id, v_user_id);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'E2E P5.1 Branch A', 'P51A', v_user_id, v_user_id),
    (v_branch_b, v_org_b, 'E2E P5.1 Branch B', 'P51B', v_user_id, v_user_id);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES (v_staff_id, v_user_id, 'E2E P5.1 Member 08', 'doctor', v_user_id, v_user_id);

  INSERT INTO public.staff_branch_assignments (
    staff_member_id, branch_id, is_primary, created_by, updated_by
  )
  VALUES
    (v_staff_id, v_branch_a, true, v_user_id, v_user_id),
    (v_staff_id, v_branch_b, false, v_user_id, v_user_id);

  INSERT INTO ai_internal.membership (user_id, organization_id, role, created_at)
  VALUES
    (v_user_id, v_org_a, 'doctor', now() - interval '2 days'),
    (v_user_id, v_org_b, 'doctor', now() - interval '1 day');

  PERFORM pg_temp.set_authenticated_session(v_user_id);
  v_set := public.set_active_organization(v_org_b);
  IF NOT v_set.success THEN
    INSERT INTO issuer_rpc_results VALUES (
      'E2E-P5.1-08 Membership switched to org B yields token org B',
      false,
      'set_active_organization failed: ' || COALESCE(v_set.error_code, '<null>')
    );
    RETURN;
  END IF;

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

  IF to_regclass('ai_internal.installation_keys') IS NOT NULL THEN
    PERFORM public.enroll_installation_keypair();
  END IF;

  v_current_org := public.current_org_id();
  v_token := public.issue_ai_token(1);
  v_payload := pg_temp.decode_jws_payload(v_token);

  v_passed := v_current_org = v_org_b
    AND (v_payload ->> 'org') = v_org_b::text
    AND (v_payload ->> 'org') = v_current_org::text;

  v_detail := 'current_org_id=' || COALESCE(v_current_org::text, '<null>')
    || ' token_org=' || COALESCE(v_payload ->> 'org', '<null>')
    || ' org_b=' || v_org_b::text;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO issuer_rpc_results VALUES (
    'E2E-P5.1-08 Membership switched to org B yields token org B',
    v_passed,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM issuer_rpc_results ORDER BY test_name;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM issuer_rpc_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'issuer_rpc failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM issuer_rpc_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

ROLLBACK;
