-- Align issuer missing-settings fallback with MAX_AAT_LIFETIME_SECONDS (600 s).
-- Platform identity guard rejects tokens where exp - iat > 600; fallback must be <= 10 minutes.

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

  v_lifetime_minutes := auth_internal.ai_app_setting_numeric('ai.aat.lifetime_minutes', 10);
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
