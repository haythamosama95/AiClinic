-- R2-C2: preserve the negotiated RPC version on every billing issuer error.

CREATE OR REPLACE FUNCTION auth_internal.issue_billing_token(p_contract_version integer)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, vault, auth_internal
AS $$
DECLARE
  v_uid uuid;
  v_org uuid;
  v_staff public.staff_members%ROWTYPE;
  v_branch_id uuid;
  v_signing_key ai_internal.issuer_key%ROWTYPE;
  v_secret_key bytea;
  v_jti uuid;
  v_iat bigint;
  v_exp bigint;
  v_recent_mints int;
  v_abo_base_url text;
  v_header_text text;
  v_payload_text text;
  v_header_b64 text;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_token text;
BEGIN
  v_uid := auth_internal.assert_valid_ai_session();

  IF public.current_membership_role() IS DISTINCT FROM 'administrator' THEN
    RETURN public.rpc_error('FORBIDDEN_ROLE', 'Only administrators can issue billing tokens.', p_contract_version);
  END IF;

  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.', p_contract_version);
  END IF;

  SELECT sm.*
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_uid
    AND sm.is_deleted = false
    AND sm.is_active = true;

  IF NOT FOUND THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found.', p_contract_version);
  END IF;

  SELECT b.id
  INTO v_branch_id
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  WHERE sba.staff_member_id = v_staff.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.is_active = true
    AND b.organization_id = v_org
  ORDER BY sba.is_primary DESC, b.name
  LIMIT 1;

  IF v_branch_id IS NULL THEN
    RETURN public.rpc_error('BRANCH_NOT_FOUND', 'No active branch is assigned for this organization.', p_contract_version);
  END IF;

  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.issuer_key ik
  WHERE ik.status = 'signing'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN public.rpc_error('ISSUER_KEY_NOT_CONFIGURED', 'Issuer signing key is not configured.', p_contract_version);
  END IF;

  SELECT decode(ds.decrypted_secret, 'base64')
  INTO v_secret_key
  FROM vault.decrypted_secrets ds
  WHERE ds.id = v_signing_key.secret_ref;

  IF v_secret_key IS NULL THEN
    RETURN public.rpc_error('ISSUER_KEY_NOT_CONFIGURED', 'Issuer signing key is not configured.', p_contract_version);
  END IF;

  PERFORM pg_advisory_xact_lock(
    87201402,
    hashtext(v_staff.id::text || ':abo')
  );

  SELECT count(*)::int
  INTO v_recent_mints
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_staff.id
    AND i.aud = 'abo'
    AND i.is_deleted = false
    AND i.iat >= now() - interval '10 minutes';

  IF v_recent_mints >= 20 THEN
    RETURN public.rpc_error('RATE_LIMITED', 'Billing token rate limit exceeded.', p_contract_version);
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + 300;
  v_abo_base_url := auth_internal.ai_app_setting_text('ai.abo_base_url', 'http://127.0.0.1:8788');

  v_header_text := auth_internal.canonical_issuer_jwt_json(jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid,
    'typ', 'JWT'
  ));

  v_payload_text := auth_internal.canonical_issuer_jwt_json(jsonb_build_object(
    'iss', auth_internal.ai_app_setting_text('ai.issuer_id', 'issuer-test'),
    'aud', 'abo',
    'sub', v_staff.id::text,
    'org', v_org::text,
    'branch', v_branch_id::text,
    'role', 'administrator',
    'jti', v_jti::text,
    'iat', v_iat,
    'exp', v_exp,
    'ver', '2'
  ));

  v_header_b64 := auth_internal.base64url_encode(convert_to(v_header_text, 'utf8'));
  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload_text, 'utf8'));
  v_signing_input := v_header_b64 || '.' || v_payload_b64;

  v_signature := pgsodium.crypto_sign_detached(
    convert_to(v_signing_input, 'utf8'),
    v_secret_key
  );

  v_token := v_signing_input || '.' || auth_internal.base64url_encode(v_signature);

  INSERT INTO ai_internal.ai_token_issuance (
    jti,
    actor_staff_id,
    organization_id,
    aud,
    iat,
    created_by,
    updated_by
  )
  VALUES (
    v_jti,
    v_staff.id,
    v_org,
    'abo',
    to_timestamp(v_iat),
    v_uid,
    v_uid
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'token', v_token,
      'abo_base_url', v_abo_base_url,
      'expires_at', to_timestamp(v_exp)
    ),
    p_contract_version
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('UNAUTHENTICATED', 'SESSION_EXPIRED') THEN
      RETURN public.rpc_error(SQLERRM, SQLERRM, p_contract_version);
    END IF;
    RAISE;
END;
$$;
