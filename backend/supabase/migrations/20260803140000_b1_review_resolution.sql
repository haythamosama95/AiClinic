-- =============================================================================
-- B1 review resolution: apply hardened keystore/issuer behavior on DBs that
-- already ran 20260801120000–20260801120200. Idempotent with the updated
-- originals (CREATE OR REPLACE / IF NOT EXISTS patterns).
-- =============================================================================

REVOKE ALL ON SCHEMA ai_internal FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA ai_internal TO postgres;
-- Later F2 registry reads (acceptance_targets) re-grant service_role USAGE.

-- Enrollment SECURITY DEFINER owner must hold keymaker (§4.2.1).
GRANT pgsodium_keymaker TO postgres;

CREATE OR REPLACE FUNCTION ai_internal.enforce_single_installation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing uuid;
BEGIN
  IF NEW.is_deleted THEN
    RETURN NEW;
  END IF;

  SELECT ik.installation_id
  INTO v_existing
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.kid IS DISTINCT FROM NEW.kid
  ORDER BY ik.valid_from ASC, ik.kid ASC
  LIMIT 1;

  IF v_existing IS NOT NULL AND v_existing IS DISTINCT FROM NEW.installation_id THEN
    RAISE EXCEPTION 'SINGLE_INSTALLATION_VIOLATION'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS installation_keys_single_installation
  ON ai_internal.installation_keys;

CREATE TRIGGER installation_keys_single_installation
  BEFORE INSERT OR UPDATE OF installation_id, is_deleted
  ON ai_internal.installation_keys
  FOR EACH ROW
  EXECUTE FUNCTION ai_internal.enforce_single_installation();

DROP INDEX IF EXISTS ai_internal.installation_keys_active_idx;
CREATE INDEX installation_keys_active_idx
  ON ai_internal.installation_keys (installation_id, valid_from DESC, kid DESC)
  WHERE revoked_at IS NULL AND is_deleted = false;
-- =============================================================================
-- B1 slice: installation keypair enrollment, rotation, and revocation.
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.enroll_installation_keypair()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, auth_internal
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_installation_id uuid;
  v_keypair record;
  v_kid text;
  v_public_jwk jsonb;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
  ORDER BY ik.valid_from ASC, ik.kid ASC
  LIMIT 1;

  IF v_installation_id IS NULL THEN
    v_installation_id := gen_random_uuid();
  END IF;

  SELECT kp.public, kp.secret
  INTO v_keypair
  FROM pgsodium.crypto_sign_new_keypair() kp;

  v_kid := gen_random_uuid()::text;

  INSERT INTO ai_internal.installation_keys (
    kid,
    installation_id,
    public_key,
    secret_key,
    algorithm,
    valid_from,
    created_at,
    created_by,
    updated_by
  )
  VALUES (
    v_kid,
    v_installation_id,
    v_keypair.public,
    v_keypair.secret,
    'EdDSA',
    clock_timestamp(),
    clock_timestamp(),
    v_caller.auth_user_id,
    v_caller.auth_user_id
  );

  v_public_jwk := jsonb_build_object(
    'kty', 'OKP',
    'crv', 'Ed25519',
    'x', auth_internal.base64url_encode(v_keypair.public),
    'kid', v_kid
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'kid', v_kid,
      'installation_id', v_installation_id,
      'public_jwk', v_public_jwk
    )
  );
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may enroll installation keys.');
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may enroll installation keys.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.rotate_installation_key()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, auth_internal
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_installation_id uuid;
  v_keypair record;
  v_kid text;
  v_public_jwk jsonb;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
  ORDER BY ik.valid_from ASC, ik.kid ASC
  LIMIT 1;

  IF v_installation_id IS NULL THEN
    RETURN public.rpc_error(
      'INSTALLATION_NOT_ENROLLED',
      'Enroll an installation keypair before rotating.'
    );
  END IF;

  SELECT kp.public, kp.secret
  INTO v_keypair
  FROM pgsodium.crypto_sign_new_keypair() kp;

  v_kid := gen_random_uuid()::text;

  INSERT INTO ai_internal.installation_keys (
    kid,
    installation_id,
    public_key,
    secret_key,
    algorithm,
    valid_from,
    created_at,
    created_by,
    updated_by
  )
  VALUES (
    v_kid,
    v_installation_id,
    v_keypair.public,
    v_keypair.secret,
    'EdDSA',
    clock_timestamp(),
    clock_timestamp(),
    v_caller.auth_user_id,
    v_caller.auth_user_id
  );

  v_public_jwk := jsonb_build_object(
    'kty', 'OKP',
    'crv', 'Ed25519',
    'x', auth_internal.base64url_encode(v_keypair.public),
    'kid', v_kid
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'kid', v_kid,
      'installation_id', v_installation_id,
      'public_jwk', v_public_jwk
    )
  );
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may rotate installation keys.');
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may rotate installation keys.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.revoke_installation_key(p_kid text)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_row ai_internal.installation_keys%ROWTYPE;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF NULLIF(trim(p_kid), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Key id is required.');
  END IF;

  SELECT *
  INTO v_row
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = p_kid
    AND ik.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('KEY_NOT_FOUND', 'Installation key was not found.');
  END IF;

  IF v_row.revoked_at IS NOT NULL THEN
    RETURN public.rpc_success(
      jsonb_build_object('kid', v_row.kid, 'revoked_at', v_row.revoked_at)
    );
  END IF;

  UPDATE ai_internal.installation_keys ik
  SET
    revoked_at = clock_timestamp(),
    updated_at = clock_timestamp(),
    updated_by = v_caller.auth_user_id
  WHERE ik.kid = p_kid;

  RETURN public.rpc_success(
    jsonb_build_object('kid', p_kid, 'revoked_at', clock_timestamp())
  );
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may revoke installation keys.');
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may revoke installation keys.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.enroll_installation_keypair()
RETURNS public.rpc_result
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.enroll_installation_keypair();
$$;

CREATE OR REPLACE FUNCTION public.rotate_installation_key()
RETURNS public.rpc_result
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.rotate_installation_key();
$$;

CREATE OR REPLACE FUNCTION public.revoke_installation_key(p_kid text)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.revoke_installation_key(p_kid);
$$;

REVOKE EXECUTE ON FUNCTION auth_internal.enroll_installation_keypair() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.rotate_installation_key() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.revoke_installation_key(text) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.enroll_installation_keypair() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rotate_installation_key() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_installation_key(text) FROM anon, PUBLIC;

GRANT EXECUTE ON FUNCTION public.enroll_installation_keypair() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rotate_installation_key() TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_installation_key(text) TO authenticated;

-- =============================================================================
-- B1 slice: AAT issuer RPC and clinic-side verifier self-test helper.
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.base64url_encode(p_bytes bytea)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT rtrim(
    translate(replace(encode(p_bytes, 'base64'), E'\n', ''), '+/', '-_'),
    '='
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.base64url_decode(p_text text)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT decode(
    rpad(
      translate(p_text, '-_', '+/'),
      length(p_text) + ((4 - length(p_text) % 4) % 4),
      '='
    ),
    'base64'
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.ai_app_setting_numeric(
  p_key text,
  p_default numeric
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ai_internal
AS $$
  SELECT COALESCE(
    (
      SELECT (s.value_json)::numeric
      FROM ai_internal.app_settings s
      WHERE s.key = p_key
        AND s.is_deleted = false
    ),
    p_default
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.ai_app_setting_text(
  p_key text,
  p_default text
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ai_internal
AS $$
  SELECT COALESCE(
    (
      SELECT trim(both '"' from s.value_json::text)
      FROM ai_internal.app_settings s
      WHERE s.key = p_key
        AND s.is_deleted = false
    ),
    p_default
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_valid_ai_session()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid uuid;
  v_claims jsonb;
  v_exp bigint;
BEGIN
  v_uid := auth.uid();

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  BEGIN
    v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  EXCEPTION
    WHEN OTHERS THEN
      v_claims := '{}'::jsonb;
  END;

  IF NULLIF(v_claims ->> 'sub', '') IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  IF v_claims ? 'exp' THEN
    v_exp := (v_claims ->> 'exp')::bigint;
    IF v_exp IS NOT NULL
       AND v_exp < extract(epoch FROM now())::bigint THEN
      RAISE EXCEPTION 'SESSION_EXPIRED';
    END IF;
  END IF;

  RETURN v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.issue_ai_token(p_scopes text[] DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, auth_internal
AS $$
DECLARE
  v_uid uuid;
  v_claims jsonb;
  v_staff public.staff_members%ROWTYPE;
  v_branch_id uuid;
  v_installation_id uuid;
  v_signing_key ai_internal.installation_keys%ROWTYPE;
  v_scopes jsonb;
  v_jti uuid;
  v_iat bigint;
  v_exp bigint;
  v_lifetime_minutes numeric;
  v_rate_ceiling int;
  v_rate_window_seconds int;
  v_recent_mints int;
  v_header_text text;
  v_payload_text text;
  v_header_b64 text;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_token text;
BEGIN
  v_uid := auth_internal.assert_valid_ai_session();

  v_claims := auth_internal.build_staff_claims(v_uid);
  IF v_claims = '{}'::jsonb
     OR NULLIF(v_claims ->> 'staff_member_id', '') IS NULL THEN
    RAISE EXCEPTION 'STAFF_NOT_FOUND';
  END IF;

  SELECT sm.*
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.id = (v_claims ->> 'staff_member_id')::uuid
    AND sm.is_deleted = false
    AND sm.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'STAFF_NOT_FOUND';
  END IF;

  SELECT b.id
  INTO v_branch_id
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  WHERE sba.staff_member_id = v_staff.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.is_active = true
  ORDER BY sba.is_primary DESC, b.name
  LIMIT 1;

  IF v_branch_id IS NULL THEN
    RAISE EXCEPTION 'BRANCH_NOT_FOUND';
  END IF;

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
  ORDER BY ik.valid_from ASC, ik.kid ASC
  LIMIT 1;

  IF v_installation_id IS NULL THEN
    RAISE EXCEPTION 'INSTALLATION_NOT_ENROLLED';
  END IF;

  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.installation_keys ik
  WHERE ik.installation_id = v_installation_id
    AND ik.is_deleted = false
    AND ik.revoked_at IS NULL
  ORDER BY ik.valid_from DESC, ik.kid DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INSTALLATION_NOT_ENROLLED';
  END IF;

  v_lifetime_minutes := auth_internal.ai_app_setting_numeric('ai.aat.lifetime_minutes', 15);
  v_rate_ceiling := auth_internal.ai_app_setting_numeric('ai.issuer.rate_limit.ceiling', 100)::int;
  v_rate_window_seconds := auth_internal.ai_app_setting_numeric(
    'ai.issuer.rate_limit.window_seconds',
    3600
  )::int;

  -- Serialize per-actor mint counting against the ledger insert (§4.2 rate limit).
  PERFORM pg_advisory_xact_lock(
    87201401,
    hashtext(v_staff.id::text)
  );

  SELECT count(*)::int
  INTO v_recent_mints
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_staff.id
    AND i.is_deleted = false
    AND i.iat >= now() - make_interval(secs => v_rate_window_seconds);

  IF v_recent_mints >= v_rate_ceiling THEN
    RAISE EXCEPTION 'RATE_LIMITED';
  END IF;

  SELECT coalesce(
    jsonb_agg(rp.permission_key ORDER BY rp.permission_key),
    '[]'::jsonb
  )
  INTO v_scopes
  FROM public.roles_permissions rp
  WHERE rp.role = v_staff.role
    AND rp.permission_key LIKE 'ai.%'
    AND rp.is_granted = true
    AND rp.is_deleted = false;

  IF jsonb_array_length(v_scopes) < 1 THEN
    RAISE EXCEPTION 'AI_ACCESS_DENIED';
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + (v_lifetime_minutes * 60)::bigint;

  v_header_text := jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid
  )::text;

  v_payload_text := jsonb_build_object(
    'iss', v_installation_id::text,
    'aud', auth_internal.ai_app_setting_text('ai.aat.audience', 'ai-platform'),
    'sub', v_staff.id::text,
    'org', (v_claims ->> 'organization_id'),
    'branch', v_branch_id::text,
    'role', v_staff.role::text,
    'scopes', v_scopes,
    'jti', v_jti::text,
    'iat', v_iat,
    'exp', v_exp,
    'ver', auth_internal.ai_app_setting_text('ai.aat.ver', '1')
  )::text;

  v_header_b64 := auth_internal.base64url_encode(convert_to(v_header_text, 'utf8'));
  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload_text, 'utf8'));
  v_signing_input := v_header_b64 || '.' || v_payload_b64;

  v_signature := pgsodium.crypto_sign_detached(
    convert_to(v_signing_input, 'utf8'),
    v_signing_key.secret_key
  );

  v_token := v_signing_input || '.' || auth_internal.base64url_encode(v_signature);

  INSERT INTO ai_internal.ai_token_issuance (
    installation_id,
    jti,
    actor_staff_id,
    iat,
    created_by,
    updated_by
  )
  VALUES (
    v_installation_id,
    v_jti,
    v_staff.id,
    to_timestamp(v_iat),
    v_uid,
    v_uid
  );

  RETURN v_token;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.verify_aat(p_token text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ai_internal, pgsodium, auth_internal
AS $$
DECLARE
  v_header_part text;
  v_payload_part text;
  v_signature_part text;
  v_header jsonb;
  v_payload jsonb;
  v_kid text;
  v_iss text;
  v_key ai_internal.installation_keys%ROWTYPE;
  v_signing_input text;
  v_signature bytea;
BEGIN
  IF p_token IS NULL OR p_token = '' THEN
    RETURN false;
  END IF;

  v_header_part := split_part(p_token, '.', 1);
  v_payload_part := split_part(p_token, '.', 2);
  v_signature_part := split_part(p_token, '.', 3);

  IF v_header_part = ''
     OR v_payload_part = ''
     OR v_signature_part = ''
     OR array_length(string_to_array(p_token, '.'), 1) <> 3 THEN
    RETURN false;
  END IF;

  BEGIN
    v_header := convert_from(
      auth_internal.base64url_decode(v_header_part),
      'utf8'
    )::jsonb;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN false;
  END;

  v_kid := v_header ->> 'kid';
  IF v_kid IS NULL OR (v_header ->> 'alg') IS DISTINCT FROM 'EdDSA' THEN
    RETURN false;
  END IF;

  SELECT ik.*
  INTO v_key
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_kid
    AND ik.is_deleted = false;

  IF NOT FOUND OR v_key.revoked_at IS NOT NULL THEN
    RETURN false;
  END IF;

  BEGIN
    v_payload := convert_from(
      auth_internal.base64url_decode(v_payload_part),
      'utf8'
    )::jsonb;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN false;
  END;

  v_iss := v_payload ->> 'iss';
  IF v_iss IS NULL OR v_iss IS DISTINCT FROM v_key.installation_id::text THEN
    RETURN false;
  END IF;

  -- Clinic self-test does not evaluate exp; platform verifier (B3) enforces expiry (§4.2.1 / §5.6).

  v_signing_input := v_header_part || '.' || v_payload_part;

  BEGIN
    v_signature := auth_internal.base64url_decode(v_signature_part);
    RETURN pgsodium.crypto_sign_verify_detached(
      v_signature,
      convert_to(v_signing_input, 'utf8'),
      v_key.public_key
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN false;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_ai_token(p_scopes text[] DEFAULT NULL)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.issue_ai_token(p_scopes);
$$;

REVOKE EXECUTE ON FUNCTION auth_internal.base64url_encode(bytea) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.base64url_decode(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.ai_app_setting_numeric(text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.ai_app_setting_text(text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.assert_valid_ai_session() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.issue_ai_token(text[]) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.verify_aat(text) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.issue_ai_token(text[]) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.issue_ai_token(text[]) TO authenticated;

-- Preserve F2 service_role read path if acceptance_targets already exists.
DO $$
BEGIN
  IF to_regclass('ai_internal.acceptance_targets') IS NOT NULL THEN
    EXECUTE 'GRANT USAGE ON SCHEMA ai_internal TO service_role';
  END IF;
END;
$$;
