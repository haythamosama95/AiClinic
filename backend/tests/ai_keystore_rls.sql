-- Installation keystore RLS and rotation tests (B1 slice T01–T10).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/ai_keystore_rls.sql

BEGIN;

CREATE TEMP TABLE ai_keystore_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.decode_jws_header(p_token text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT convert_from(
    decode(
      rpad(
        translate(split_part(p_token, '.', 1), '-_', '+/'),
        length(split_part(p_token, '.', 1))
          + ((4 - length(split_part(p_token, '.', 1)) % 4) % 4),
        '='
      ),
      'base64'
    ),
    'utf8'
  )::jsonb;
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

CREATE OR REPLACE FUNCTION pg_temp.public_jwk_ok(p_data jsonb, p_kid text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_data ? 'public_jwk'
    AND jsonb_typeof(p_data -> 'public_jwk') = 'object'
    AND (p_data -> 'public_jwk' ->> 'kty') = 'OKP'
    AND (p_data -> 'public_jwk' ->> 'crv') = 'Ed25519'
    AND NULLIF(p_data -> 'public_jwk' ->> 'x', '') IS NOT NULL
    AND (p_data -> 'public_jwk' ->> 'kid') = p_kid;
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

-- T03: SECURITY DEFINER keypair enrollment reaches the keystore and returns public_jwk.
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
  v_jwk_ok boolean;
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
    v_jwk_ok := pg_temp.public_jwk_ok(v_result.data, v_kid);

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
      AND v_has_secret
      AND v_jwk_ok;
    v_detail := COALESCE(v_result.error_code, 'ok')
      || ' kid=' || COALESCE(v_kid, '<null>')
      || ' has_secret=' || v_has_secret::text
      || ' public_jwk_ok=' || v_jwk_ok::text
      || ' jwk=' || COALESCE((v_result.data -> 'public_jwk')::text, '<null>');
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

-- T04: rotation is additive — previous key remains active; rotate returns public_jwk.
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
  v_jwk_ok boolean;
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
    v_jwk_ok := pg_temp.public_jwk_ok(v_result.data, v_kid2);

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
      AND v_distinct_kids = 2
      AND v_jwk_ok
      AND (v_result.data ->> 'installation_id')::uuid = v_installation_id;
    v_detail := COALESCE(v_result.error_code, 'ok')
      || ' active=' || v_active_count::text
      || ' kids=' || COALESCE(v_kid1, '<null>') || ',' || COALESCE(v_kid2, '<null>')
      || ' public_jwk_ok=' || v_jwk_ok::text;
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

-- T05: previous key still verifies after rotation (clinic verify_aat does not check exp).
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
    v_detail := 'previous_key_still_verifies_after_rotation'
      || ' verified=' || COALESCE(v_verified::text, '<null>')
      || ' token_present=' || (v_token IS NOT NULL)::text;
  EXCEPTION
    WHEN undefined_function OR undefined_table THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
  END;

  INSERT INTO ai_keystore_rls_results VALUES (
    'T05_previous_key_still_verifies_after_rotation',
    v_passed,
    v_detail
  );
END;
$$;

-- T05b: after rotate in same transaction, new mint header kid equals rotate result kid.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_rotate_kid text;
  v_token text;
  v_header jsonb;
  v_mint_kid text;
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

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);

  v_result := public.bootstrap_create_organization('AI PostRotate Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'PostRotate Branch', NULL, NULL, 'PRB1', NULL);
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

    v_result := public.rotate_installation_key();
    IF NOT v_result.success THEN
      RAISE EXCEPTION '%', COALESCE(v_result.error_code, 'rotate failed');
    END IF;
    v_rotate_kid := v_result.data ->> 'kid';

    v_token := public.issue_ai_token();
    v_header := pg_temp.decode_jws_header(v_token);
    v_mint_kid := v_header ->> 'kid';

    v_passed := v_rotate_kid IS NOT NULL
      AND v_mint_kid IS NOT NULL
      AND v_mint_kid = v_rotate_kid;
    v_detail := 'rotate_kid=' || COALESCE(v_rotate_kid, '<null>')
      || ' mint_kid=' || COALESCE(v_mint_kid, '<null>');
  EXCEPTION
    WHEN undefined_function OR undefined_table THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
    WHEN OTHERS THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_keystore_rls_results VALUES (
    'T05b_post_rotation_mint_uses_new_kid',
    v_passed,
    v_detail
  );
END;
$$;

-- T05c: verify_aat returns false (does not throw) on malformed signature segment.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_token text;
  v_malformed text;
  v_verified boolean;
  v_threw boolean := false;
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

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);

  v_result := public.bootstrap_create_organization('AI MalformedSig Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Malformed Branch', NULL, NULL, 'MSB1', NULL);
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
    v_malformed := split_part(v_token, '.', 1)
      || '.' || split_part(v_token, '.', 2)
      || '.' || '!!!not-valid-base64url-sig!!!';

    PERFORM set_config('role', 'postgres', true);
    BEGIN
      v_verified := auth_internal.verify_aat(v_malformed);
    EXCEPTION
      WHEN OTHERS THEN
        v_threw := true;
        v_detail := 'threw: ' || SQLERRM;
    END;

    v_passed := (NOT v_threw) AND v_verified IS FALSE;
    IF NOT v_threw THEN
      v_detail := 'verified=' || COALESCE(v_verified::text, '<null>');
    END IF;
  EXCEPTION
    WHEN undefined_function OR undefined_table THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
    WHEN OTHERS THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
  END;

  INSERT INTO ai_keystore_rls_results VALUES (
    'T05c_verify_aat_malformed_sig_false',
    v_passed,
    v_detail
  );
END;
$$;

-- T05d: verify_aat returns false when payload iss does not match key row installation_id.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_token text;
  v_header_part text;
  v_payload jsonb;
  v_kid text;
  v_secret bytea;
  v_wrong_iss uuid := 'f1000000-0000-4000-8000-000000000099';
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_tampered text;
  v_verified boolean;
  v_threw boolean := false;
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

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);

  v_result := public.bootstrap_create_organization('AI IssMismatch Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'IssMismatch Branch', NULL, NULL, 'IMB1', NULL);
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
    v_header_part := split_part(v_token, '.', 1);
    v_payload := pg_temp.decode_jws_payload(v_token);
    v_kid := pg_temp.decode_jws_header(v_token) ->> 'kid';

    v_payload := (v_payload - 'iss') || jsonb_build_object('iss', v_wrong_iss::text);

    PERFORM set_config('role', 'postgres', true);
    SELECT ik.secret_key
    INTO v_secret
    FROM ai_internal.installation_keys ik
    WHERE ik.kid = v_kid
      AND ik.is_deleted = false;

    v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload::text, 'utf8'));
    v_signing_input := v_header_part || '.' || v_payload_b64;
    v_signature := pgsodium.crypto_sign_detached(
      convert_to(v_signing_input, 'utf8'),
      v_secret
    );
    v_tampered := v_signing_input || '.' || auth_internal.base64url_encode(v_signature);

    BEGIN
      v_verified := auth_internal.verify_aat(v_tampered);
    EXCEPTION
      WHEN OTHERS THEN
        v_threw := true;
        v_detail := 'threw: ' || SQLERRM;
    END;

    v_passed := (NOT v_threw) AND v_verified IS FALSE;
    IF NOT v_threw THEN
      v_detail := 'verified=' || COALESCE(v_verified::text, '<null>')
        || ' wrong_iss=' || v_wrong_iss::text
        || ' kid=' || COALESCE(v_kid, '<null>');
    END IF;
  EXCEPTION
    WHEN undefined_function OR undefined_table THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
    WHEN OTHERS THEN
      PERFORM set_config('role', 'postgres', true);
      v_passed := false;
      v_detail := SQLERRM;
  END;

  INSERT INTO ai_keystore_rls_results VALUES (
    'T05d_verify_aat_iss_mismatch_false',
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

-- T07: non-administrator gets FORBIDDEN on enroll / rotate / revoke.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'c2000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_enroll_ok boolean;
  v_rotate_ok boolean;
  v_revoke_ok boolean;
  v_passed boolean;
  v_detail text;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'development', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff, v_doctor_staff]::uuid[]);
  DELETE FROM public.audit_log WHERE organization_id IS NOT NULL;
  DELETE FROM public.app_settings WHERE true;
  DELETE FROM public.subscription_cache WHERE true;
  UPDATE public.roles_permissions
  SET updated_by = NULL, created_by = NULL
  WHERE updated_by = v_doctor_user OR created_by = v_doctor_user;
  DELETE FROM auth.users WHERE id = v_doctor_user;
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
    v_doctor_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'ai-keystore-doctor',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  v_result := public.bootstrap_create_organization('AI Forbidden Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Forbidden Branch', NULL, NULL, 'FBB1', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES (
    v_doctor_staff,
    v_doctor_user,
    'AI Keystore Doctor',
    'doctor',
    false,
    v_bootstrap_user,
    v_bootstrap_user
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_doctor_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT DO NOTHING;

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);

  v_result := public.enroll_installation_keypair();
  v_enroll_ok := (NOT v_result.success) AND v_result.error_code = 'FORBIDDEN';

  v_result := public.rotate_installation_key();
  v_rotate_ok := (NOT v_result.success) AND v_result.error_code = 'FORBIDDEN';

  v_result := public.revoke_installation_key('any-kid');
  v_revoke_ok := (NOT v_result.success) AND v_result.error_code = 'FORBIDDEN';

  v_passed := v_enroll_ok AND v_rotate_ok AND v_revoke_ok;
  v_detail := 'enroll_forbidden=' || v_enroll_ok::text
    || ' rotate_forbidden=' || v_rotate_ok::text
    || ' revoke_forbidden=' || v_revoke_ok::text;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_keystore_rls_results VALUES (
    'T07_keypair_admin_forbidden',
    v_passed,
    v_detail
  );
END;
$$;

-- T08: revoke empty kid → INVALID_INPUT.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
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

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  v_result := public.bootstrap_create_organization('AI RevokeEmpty Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  PERFORM public.bootstrap_create_branch(v_org_id, 'RevokeEmpty Branch', NULL, NULL, 'REB1', NULL);

  v_result := public.revoke_installation_key('');
  v_passed := (NOT v_result.success) AND v_result.error_code = 'INVALID_INPUT';
  v_detail := 'success=' || v_result.success::text
    || ' error_code=' || COALESCE(v_result.error_code, '<null>');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_keystore_rls_results VALUES (
    'T08_revoke_empty_kid_invalid_input',
    v_passed,
    v_detail
  );
END;
$$;

-- T09: revoke unknown kid → KEY_NOT_FOUND.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
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

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  v_result := public.bootstrap_create_organization('AI RevokeUnknown Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  PERFORM public.bootstrap_create_branch(v_org_id, 'RevokeUnknown Branch', NULL, NULL, 'RUB1', NULL);

  v_result := public.revoke_installation_key('00000000-0000-4000-8000-ffffffffffff');
  v_passed := (NOT v_result.success) AND v_result.error_code = 'KEY_NOT_FOUND';
  v_detail := 'success=' || v_result.success::text
    || ' error_code=' || COALESCE(v_result.error_code, '<null>');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_keystore_rls_results VALUES (
    'T09_revoke_unknown_kid_key_not_found',
    v_passed,
    v_detail
  );
END;
$$;

-- T10: rotate before enroll → INSTALLATION_NOT_ENROLLED.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
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

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  v_result := public.bootstrap_create_organization('AI RotateEmpty Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  PERFORM public.bootstrap_create_branch(v_org_id, 'RotateEmpty Branch', NULL, NULL, 'RTE1', NULL);

  v_result := public.rotate_installation_key();
  v_passed := (NOT v_result.success) AND v_result.error_code = 'INSTALLATION_NOT_ENROLLED';
  v_detail := 'success=' || v_result.success::text
    || ' error_code=' || COALESCE(v_result.error_code, '<null>');

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_keystore_rls_results VALUES (
    'T10_rotate_before_enroll_not_enrolled',
    v_passed,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM ai_keystore_rls_results ORDER BY test_name;

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

ROLLBACK;
