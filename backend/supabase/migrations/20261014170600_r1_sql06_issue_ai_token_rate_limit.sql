-- =============================================================================
-- R1-SQL-06 (P2): Final AI issuer drops its issuance rate limit.
--
-- The previous final text[] issuer serialized per-staff ledger counting and
-- enforced the configured rate ceiling/window
-- (20261002150000_tenant_scoping.sql, advisory lock 87201401 keyed on the
-- staff id). The custody integer replacement
-- (20261007180000_issuer_key_custody.sql, T012) signs and inserts on every
-- permitted call with no lock, count or refusal, so an authenticated AI member
-- could drive unbounded signing and issuance-ledger writes. 03 §3.2 and spec
-- 087 FR-007 preserve per-audience rate limits.
--
-- Forward override of auth_internal.issue_ai_token(integer) restoring:
--   * the per-staff advisory transaction lock (87201401, hashtext(staff id)) —
--     distinct from the billing mint's 87201402/':abo' lock, so concurrent AI
--     mints cannot overshoot and billing mints never consume AI quota;
--   * the configured ceiling/window from
--     ai.issuer.rate_limit.ceiling (default 100) and
--     ai.issuer.rate_limit.window_seconds (default 3600), counting ledger rows
--     for this staff member with aud = 'ai-platform' and is_deleted = false;
--   * the RATE_LIMITED refusal placed before issuer-key loading, signing and
--     ledger insertion.
--
-- The 600s lifetime and the membership/branch/scope validation are unchanged;
-- billing's independent 20-per-10-minutes counter is untouched.
-- Forward-only migration; never edit an applied migration file.
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.issue_ai_token(p_contract_version integer)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, vault, auth_internal
AS $$
DECLARE
  v_uid uuid;
  v_org uuid;
  v_staff public.staff_members%ROWTYPE;
  v_branch_id uuid;
  v_rate_ceiling int;
  v_rate_window_seconds int;
  v_recent_mints int;
  v_signing_key ai_internal.issuer_key%ROWTYPE;
  v_secret_key bytea;
  v_scopes jsonb;
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
  v_uid := auth_internal.assert_valid_ai_session();

  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT sm.*
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_uid
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
    AND b.organization_id = v_org
  ORDER BY sba.is_primary DESC, b.name
  LIMIT 1;

  IF v_branch_id IS NULL THEN
    RAISE EXCEPTION 'BRANCH_NOT_FOUND';
  END IF;

  -- R1-SQL-06: serialize per-staff mint counting against the ledger insert
  -- and enforce the configured ceiling/window before any key material is
  -- loaded, before signing and before the ledger insert.
  v_rate_ceiling := auth_internal.ai_app_setting_numeric('ai.issuer.rate_limit.ceiling', 100)::int;
  v_rate_window_seconds := auth_internal.ai_app_setting_numeric(
    'ai.issuer.rate_limit.window_seconds',
    3600
  )::int;

  PERFORM pg_advisory_xact_lock(
    87201401,
    hashtext(v_staff.id::text)
  );

  SELECT count(*)::int
  INTO v_recent_mints
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_staff.id
    AND i.aud = 'ai-platform'
    AND i.is_deleted = false
    AND i.iat >= now() - make_interval(secs => v_rate_window_seconds);

  IF v_recent_mints >= v_rate_ceiling THEN
    RAISE EXCEPTION 'RATE_LIMITED';
  END IF;

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

  SELECT coalesce(
    jsonb_agg(rp.permission_key ORDER BY rp.permission_key),
    '[]'::jsonb
  )
  INTO v_scopes
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org
    AND rp.role = public.current_membership_role()
    AND rp.permission_key LIKE 'ai.%'
    AND rp.is_granted = true
    AND rp.is_deleted = false;

  IF jsonb_array_length(v_scopes) < 1 THEN
    RAISE EXCEPTION 'AI_ACCESS_DENIED';
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + 600;

  v_header_text := jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid,
    'typ', 'JWT'
  )::text;

  v_payload_text := jsonb_build_object(
    'iss', auth_internal.ai_app_setting_text('ai.issuer_id', 'issuer-test'),
    'aud', 'ai-platform',
    'sub', v_staff.id::text,
    'org', v_org::text,
    'branch', v_branch_id::text,
    'role', public.current_membership_role()::text,
    'scopes', v_scopes,
    'jti', v_jti::text,
    'iat', v_iat,
    'exp', v_exp,
    'ver', '2'
  )::text;

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
    'ai-platform',
    to_timestamp(v_iat),
    v_uid,
    v_uid
  );

  RETURN v_token;
END;
$$;

-- ACLs unchanged: public wrapper keeps its grants
-- (20261007180000_issuer_key_custody.sql); the internal function stays
-- non-executable for client roles.