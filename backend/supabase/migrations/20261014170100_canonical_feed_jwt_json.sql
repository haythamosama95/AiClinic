-- Re-emit the internal feed token with RFC 8785 canonical header/payload bytes
-- so ai-platform validateTokenClaims byte-equality accepts it.

CREATE OR REPLACE FUNCTION auth_internal.issue_feed_token()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, vault, auth_internal
AS $$
DECLARE
  v_signing_key ai_internal.issuer_key%ROWTYPE;
  v_secret_key bytea;
  v_jti uuid;
  v_iat bigint;
  v_exp bigint;
  v_header_text text;
  v_payload_text text;
  v_header_b64 text;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_token text;
BEGIN
  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.issuer_key ik
  WHERE ik.status = 'signing'
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ISSUER_KEY_NOT_CONFIGURED';
  END IF;

  SELECT decode(ds.decrypted_secret, 'base64')
  INTO v_secret_key
  FROM vault.decrypted_secrets ds
  WHERE ds.id = v_signing_key.secret_ref;

  IF v_secret_key IS NULL THEN
    RAISE EXCEPTION 'ISSUER_KEY_NOT_CONFIGURED';
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + 120;

  v_header_text := auth_internal.canonical_issuer_jwt_json(jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid,
    'typ', 'JWT'
  ));

  v_payload_text := auth_internal.canonical_issuer_jwt_json(jsonb_build_object(
    'iss', auth_internal.ai_app_setting_text('ai.issuer_id', 'issuer-test'),
    'aud', 'ai-platform-feed',
    'sub', 'backend-feed',
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

  RETURN v_signing_input || '.' || auth_internal.base64url_encode(v_signature);
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.issue_feed_token() FROM PUBLIC, anon, authenticated, service_role;
