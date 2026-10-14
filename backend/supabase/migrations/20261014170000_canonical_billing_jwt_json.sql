-- Billing JWTs are signed by PostgreSQL, so their JSON bytes must match the
-- RFC 8785 contract used by the Worker verifier. PostgreSQL's jsonb::text is
-- semantically equivalent JSON but includes whitespace and is not JCS.

CREATE OR REPLACE FUNCTION auth_internal.canonical_issuer_jwt_json(p_value jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, auth_internal
AS $$
DECLARE
  v_kind text := jsonb_typeof(p_value);
  v_result text;
  v_number numeric;
BEGIN
  CASE v_kind
    WHEN 'object' THEN
      -- The issuer header and claims have fixed ASCII member names. Restrict
      -- keys to ASCII so byte ordering is the RFC 8785 UTF-16 ordering too.
      IF EXISTS (
        SELECT 1
        FROM jsonb_object_keys(p_value) AS entry(key)
        WHERE length(entry.key) <> octet_length(entry.key)
      ) THEN
        RAISE EXCEPTION 'issuer JWT JSON keys must be ASCII';
      END IF;

      SELECT COALESCE(
        string_agg(
          to_json(entry.key)::text || ':' ||
            auth_internal.canonical_issuer_jwt_json(entry.value),
          ',' ORDER BY entry.key COLLATE "C"
        ),
        ''
      )
      INTO v_result
      FROM jsonb_each(p_value) AS entry(key, value);
      RETURN '{' || v_result || '}';
    WHEN 'array' THEN
      SELECT COALESCE(
        string_agg(
          auth_internal.canonical_issuer_jwt_json(item.value),
          ',' ORDER BY item.ordinality
        ),
        ''
      )
      INTO v_result
      FROM jsonb_array_elements(p_value) WITH ORDINALITY AS item(value, ordinality);
      RETURN '[' || v_result || ']';
    WHEN 'string' THEN
      -- jsonb's scalar text form uses JSON string escaping. It matches the
      -- JCS string form for valid PostgreSQL text, including UTF-8 characters.
      RETURN p_value::text;
    WHEN 'number' THEN
      -- Issuer JWT numeric claims are integer Unix timestamps. Limit output to
      -- IEEE-754 safe integers so PostgreSQL numeric formatting is identical
      -- to the RFC 8785 number form used by the shared TypeScript verifier.
      v_number := (p_value #>> '{}')::numeric;
      IF v_number <> trunc(v_number)
        OR abs(v_number) > 9007199254740991::numeric THEN
        RAISE EXCEPTION 'issuer JWT numbers must be safe integers';
      END IF;
      RETURN v_number::bigint::text;
    WHEN 'boolean' THEN
      RETURN p_value::text;
    WHEN 'null' THEN
      RETURN 'null';
    ELSE
      RAISE EXCEPTION 'unsupported issuer JWT JSON value: %', v_kind;
  END CASE;
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.canonical_issuer_jwt_json(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

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
    RETURN public.rpc_error('FORBIDDEN_ROLE', 'Only administrators can issue billing tokens.');
  END IF;

  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  SELECT sm.*
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_uid
    AND sm.is_deleted = false
    AND sm.is_active = true;

  IF NOT FOUND THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found.');
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
    RETURN public.rpc_error('BRANCH_NOT_FOUND', 'No active branch is assigned for this organization.');
  END IF;

  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.issuer_key ik
  WHERE ik.status = 'signing'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN public.rpc_error('ISSUER_KEY_NOT_CONFIGURED', 'Issuer signing key is not configured.');
  END IF;

  SELECT decode(ds.decrypted_secret, 'base64')
  INTO v_secret_key
  FROM vault.decrypted_secrets ds
  WHERE ds.id = v_signing_key.secret_ref;

  IF v_secret_key IS NULL THEN
    RETURN public.rpc_error('ISSUER_KEY_NOT_CONFIGURED', 'Issuer signing key is not configured.');
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
      RETURN public.rpc_error(SQLERRM, SQLERRM);
    END IF;
    RAISE;
END;
$$;

REVOKE EXECUTE ON FUNCTION auth_internal.issue_billing_token(integer)
  FROM PUBLIC, anon, authenticated, service_role;
