-- Installation keystore RLS and rotation tests (B1 slice T01–T06).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/ai_keystore_rls.sql

BEGIN;

CREATE TEMP TABLE ai_keystore_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

-- T01: anon cannot read the installation keystore.
DO $$
DECLARE
  v_denied boolean := false;
  v_detail text;
BEGIN
  PERFORM set_config('role', 'anon', true);

  BEGIN
    PERFORM count(*) FROM ai_internal.installation_keys;
    v_detail := 'select succeeded unexpectedly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_denied := true;
      v_detail := SQLERRM;
    WHEN OTHERS THEN
      v_denied := false;
      v_detail := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_keystore_rls_results VALUES (
    'T01_keystore_anon_read_denied',
    v_denied,
    v_detail
  );
END;
$$;

-- T02: authenticated cannot read the installation keystore.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_denied boolean := false;
  v_detail text;
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  BEGIN
    PERFORM count(*) FROM ai_internal.installation_keys;
    v_detail := 'select succeeded unexpectedly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_denied := true;
      v_detail := SQLERRM;
    WHEN OTHERS THEN
      v_denied := false;
      v_detail := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_keystore_rls_results VALUES (
    'T02_keystore_authenticated_read_denied',
    v_denied,
    v_detail
  );
END;
$$;

-- T03: SECURITY DEFINER keypair enrollment reaches the keystore.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_kid text;
  v_installation_id uuid;
  v_has_secret boolean;
  v_passed boolean;
  v_detail text;
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

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('AI Keystore Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;

  v_result := public.bootstrap_create_branch(
    v_org_id,
    'Keystore Branch',
    '1 Main St',
    '555',
    'KSB1',
    NULL
  );
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  BEGIN
    v_result := public.enroll_installation_keypair();
    v_kid := v_result.data ->> 'kid';
    v_installation_id := (v_result.data ->> 'installation_id')::uuid;

    PERFORM set_config('role', 'postgres', true);

    SELECT EXISTS (
      SELECT 1
      FROM ai_internal.installation_keys ik
      WHERE ik.kid = v_kid
        AND ik.installation_id = v_installation_id
        AND ik.secret_key IS NOT NULL
        AND octet_length(ik.secret_key) > 0
        AND ik.revoked_at IS NULL
    )
    INTO v_has_secret;

    v_passed := v_result.success
      AND v_kid IS NOT NULL
      AND v_installation_id IS NOT NULL
      AND v_has_secret;
    v_detail := COALESCE(v_result.error_code, 'ok')
      || ' kid=' || COALESCE(v_kid, '<null>')
      || ' has_secret=' || v_has_secret::text;
  EXCEPTION
    WHEN undefined_function OR undefined_table THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
  END;

  INSERT INTO ai_keystore_rls_results VALUES (
    'T03_issuing_function_reads_keystore',
    v_passed,
    v_detail
  );
END;
$$;

-- T04: rotation is additive — previous key remains active with a distinct kid.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_installation_id uuid;
  v_kid1 text;
  v_kid2 text;
  v_active_count int;
  v_distinct_kids int;
  v_passed boolean;
  v_detail text;
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

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('AI Rotation Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Rotation Branch', NULL, NULL, 'RTB1', NULL);

  BEGIN
    v_result := public.enroll_installation_keypair();
    v_kid1 := v_result.data ->> 'kid';
    v_installation_id := (v_result.data ->> 'installation_id')::uuid;

    v_result := public.rotate_installation_key();
    v_kid2 := v_result.data ->> 'kid';

    PERFORM set_config('role', 'postgres', true);

    SELECT count(*)::int, count(DISTINCT kid)::int
    INTO v_active_count, v_distinct_kids
    FROM ai_internal.installation_keys ik
    WHERE ik.installation_id = v_installation_id
      AND ik.revoked_at IS NULL
      AND ik.is_deleted = false;

    v_passed := v_result.success
      AND v_kid1 IS NOT NULL
      AND v_kid2 IS NOT NULL
      AND v_kid1 <> v_kid2
      AND v_active_count = 2
      AND v_distinct_kids = 2;
    v_detail := COALESCE(v_result.error_code, 'ok')
      || ' active=' || v_active_count::text
      || ' kids=' || COALESCE(v_kid1, '<null>') || ',' || COALESCE(v_kid2, '<null>');
  EXCEPTION
    WHEN undefined_function OR undefined_table THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
  END;

  INSERT INTO ai_keystore_rls_results VALUES (
    'T04_rotation_additive',
    v_passed,
    v_detail
  );
END;
$$;

-- T05: AAT minted under the previous key still verifies after rotation.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_token text;
  v_verified boolean;
  v_passed boolean;
  v_detail text;
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

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('AI Verify Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Verify Branch', NULL, NULL, 'VRB1', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_bootstrap_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  BEGIN
    v_result := public.enroll_installation_keypair();
    IF NOT v_result.success THEN
      RAISE EXCEPTION '%', COALESCE(v_result.error_code, 'enroll failed');
    END IF;

    v_token := public.issue_ai_token();

    v_result := public.rotate_installation_key();

    PERFORM set_config('role', 'postgres', true);
    v_verified := auth_internal.verify_aat(v_token);

    v_passed := v_result.success
      AND v_token IS NOT NULL
      AND v_verified IS TRUE;
    v_detail := 'verified=' || COALESCE(v_verified::text, '<null>')
      || ' token_present=' || (v_token IS NOT NULL)::text;
  EXCEPTION
    WHEN undefined_function OR undefined_table THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
  END;

  INSERT INTO ai_keystore_rls_results VALUES (
    'T05_previous_key_aat_verifies',
    v_passed,
    v_detail
  );
END;
$$;

-- T06: revoked signing key rejects verification.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_kid text;
  v_token text;
  v_verified boolean;
  v_passed boolean;
  v_detail text;
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

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('AI Revoke Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Revoke Branch', NULL, NULL, 'RVB1', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_bootstrap_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_bootstrap_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  BEGIN
    v_result := public.enroll_installation_keypair();
    v_kid := v_result.data ->> 'kid';

    v_token := public.issue_ai_token();

    v_result := public.revoke_installation_key(v_kid);

    PERFORM set_config('role', 'postgres', true);
    v_verified := auth_internal.verify_aat(v_token);

    v_passed := v_result.success
      AND v_token IS NOT NULL
      AND v_verified IS FALSE;
    v_detail := 'verified=' || COALESCE(v_verified::text, '<null>')
      || ' kid=' || COALESCE(v_kid, '<null>');
  EXCEPTION
    WHEN undefined_function OR undefined_table THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
  END;

  INSERT INTO ai_keystore_rls_results VALUES (
    'T06_revoked_key_rejected',
    v_passed,
    v_detail
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM ai_keystore_rls_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'ai_keystore_rls failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM ai_keystore_rls_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM ai_keystore_rls_results ORDER BY test_name;
