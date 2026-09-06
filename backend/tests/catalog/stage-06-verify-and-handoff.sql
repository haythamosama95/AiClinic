-- Stage 06 catalog SQL: S06-033 … S06-047 (clinic verify_aat + mint/claim-shape half).
-- Does not call catalog_common_setup(); implements Baseline B0 locally.
-- Platform HTTP half of S06-041…S06-047 is skipped (Register 5 #17).
-- Run via backend/tests/catalog/run.sh (do not execute from a stage-writer task).

BEGIN;

\ir harness.sql

CREATE TEMP TABLE catalog_s06_ids (
  key text PRIMARY KEY,
  value text NOT NULL
);

CREATE OR REPLACE FUNCTION pg_temp.s06_stash(p_key text, p_value text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- TEMP tables are postgres-owned; authenticated cannot INSERT.
  PERFORM pg_temp.reset_postgres();
  INSERT INTO catalog_s06_ids (key, value)
  VALUES (p_key, p_value)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s06_id(p_key text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_value text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO v_value FROM catalog_s06_ids WHERE key = p_key;
  RETURN v_value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s06_is_compact_jws(p_token text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_token IS NOT NULL
    AND array_length(string_to_array(p_token, '.'), 1) = 3
    AND split_part(p_token, '.', 1) <> ''
    AND split_part(p_token, '.', 2) <> ''
    AND split_part(p_token, '.', 3) <> '';
$$;

-- Copy of backend/tests/ai_token_issuer.sql capture_issue_error (style only).
CREATE OR REPLACE FUNCTION pg_temp.capture_issue_error()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_token text;
BEGIN
  BEGIN
    v_token := public.issue_ai_token();
    RETURN '<none>';
  EXCEPTION
    WHEN undefined_function THEN
      RAISE;
    WHEN OTHERS THEN
      RETURN SQLERRM;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s06_reenroll()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_boot_auth uuid;
  v_result public.rpc_result;
BEGIN
  PERFORM pg_temp.reset_keystore();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.enroll_installation_keypair();
  IF NOT v_result.success THEN
    RAISE EXCEPTION 's06_reenroll failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  PERFORM pg_temp.s06_stash('I0', v_result.data ->> 'installation_id');
  PERFORM pg_temp.s06_stash('K0', v_result.data ->> 'kid');
  PERFORM pg_temp.reset_postgres();
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s06_mint_as_doc()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_doc_auth uuid;
  v_token text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';
  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_token := public.issue_ai_token();
  PERFORM pg_temp.reset_postgres();
  RETURN v_token;
END;
$$;

-- -----------------------------------------------------------------------------
-- Stage 06 Baseline B0 (Nadia Haddad / Lina Khoury / Rami Saleh + enroll)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid := 'a0000000-0000-4000-8000-000000000001';
  v_boot_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_doc uuid;
  v_doc_auth uuid;
  v_adm uuid;
  v_adm_auth uuid;
  v_rec uuid;
  v_rec_auth uuid;
  v_schedule jsonb := '{
    "days": [
      {"day":"monday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"tuesday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"wednesday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"thursday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"friday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"saturday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"sunday","is_working_day":false}
    ]
  }'::jsonb;
BEGIN
  PERFORM pg_temp.reset_postgres();
  PERFORM set_config('app.environment', 'development', true);

  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_boot_staff]::uuid[]);

  -- CONFLICT: catalog B0 usernames nadia.h/lina.k/rami.s contain '.' ;
  -- code auth_internal.assert_valid_username allows [a-z0-9_-] only
  -- (20260521190000). Using nadia_h/lina_k/rami_s so bootstrap can succeed.
  DELETE FROM auth.identities
  WHERE provider = 'email'
    AND provider_id IN ('nadia.h', 'lina.k', 'rami.s', 'nadia_h', 'lina_k', 'rami_s');
  DELETE FROM auth.users
  WHERE lower(email) IN ('nadia.h', 'lina.k', 'rami.s', 'nadia_h', 'lina_k', 'rami_s');

  PERFORM pg_temp.reset_keystore();

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);

  -- 12-arg wrapper (required working_schedule) so the call is not ambiguous
  -- against the leftover 11-arg public overlay. Extra args copied from
  -- catalog_common_setup; staff JSON is Stage 06 B0 (Nadia/Lina/Rami).
  v_result := public.bootstrap_finish_setup(
    'Sunrise Dental Clinic'::text,
    'Main Branch'::text,
    -- CONFLICT: catalog B0 usernames nadia.h/lina.k/rami.s ; code regex [a-z0-9_-]
    '[{"username":"nadia_h","password":"Cl1nic!pass","full_name":"Nadia Haddad","role":"doctor"},{"username":"lina_k","password":"Cl1nic!pass","full_name":"Lina Khoury","role":"administrator"},{"username":"rami_s","password":"Cl1nic!pass","full_name":"Rami Saleh","role":"receptionist"}]'::jsonb,
    '{}'::jsonb,
    NULL::text,
    'EGP'::text,
    'Africa/Cairo'::text,
    'MAIN'::text,
    '12 Nile St, Cairo'::text,
    '+201000000010'::text,
    NULL::text,
    v_schedule
  );

  IF NOT v_result.success THEN
    RAISE EXCEPTION 'stage-06 B0 bootstrap_finish_setup failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM pg_temp.reset_postgres();

  SELECT sm.id, sm.auth_user_id
  INTO STRICT v_doc, v_doc_auth
  FROM public.staff_members sm
  JOIN auth.users u ON u.id = sm.auth_user_id
  WHERE lower(u.email) = 'nadia_h'
    AND sm.is_deleted = false;

  SELECT sm.id, sm.auth_user_id
  INTO STRICT v_adm, v_adm_auth
  FROM public.staff_members sm
  JOIN auth.users u ON u.id = sm.auth_user_id
  WHERE lower(u.email) = 'lina_k'
    AND sm.is_deleted = false;

  SELECT sm.id, sm.auth_user_id
  INTO STRICT v_rec, v_rec_auth
  FROM public.staff_members sm
  JOIN auth.users u ON u.id = sm.auth_user_id
  WHERE lower(u.email) = 'rami_s'
    AND sm.is_deleted = false;

  DELETE FROM catalog_setup;
  INSERT INTO catalog_setup (key, value) VALUES
    ('org', v_org_id),
    ('branch', v_branch_id),
    ('doctor', v_doc),
    ('doctor_auth', v_doc_auth),
    ('admin', v_adm),
    ('admin_auth', v_adm_auth),
    ('rec', v_rec),
    ('rec_auth', v_rec_auth),
    ('boot', v_boot_staff),
    ('boot_auth', v_boot_auth);

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.enroll_installation_keypair();
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'stage-06 B0 enroll_installation_keypair failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  PERFORM pg_temp.s06_stash('I0', v_result.data ->> 'installation_id');
  PERFORM pg_temp.s06_stash('K0', v_result.data ->> 'kid');
  PERFORM pg_temp.reset_postgres();
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-033 — Non-numeric rate-ceiling setting fails with an uncoded cast error
-- CONFLICT: catalog pins SQLSTATE 22P02 / invalid input syntax for type numeric:"abc".
-- CODE (value_json)::numeric on a jsonb string raises 22023
-- "cannot cast jsonb string to type numeric".
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_before int;
  v_after int;
  v_raised boolean := false;
  v_sqlstate text;
  v_msg text;
  v_token text;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';
  SELECT count(*)::int INTO v_before
  FROM ai_internal.ai_token_issuance
  WHERE is_deleted = false;

  -- [SEED]: no RPC writes these settings.
  UPDATE ai_internal.app_settings
  SET value_json = '"abc"'::jsonb
  WHERE key = 'ai.issuer.rate_limit.ceiling';

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  BEGIN
    v_token := public.issue_ai_token();
    v_raised := false;
  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      v_sqlstate := '22023';
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_raised := true;
    WHEN OTHERS THEN
      v_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_raised := true;
  END;

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_after
  FROM ai_internal.ai_token_issuance
  WHERE is_deleted = false;

  UPDATE ai_internal.app_settings
  SET value_json = '100'::jsonb
  WHERE key = 'ai.issuer.rate_limit.ceiling';

  v_ok := v_raised
    AND v_sqlstate = '22023'
    AND COALESCE(v_msg, '') = 'cannot cast jsonb string to type numeric'
    AND v_token IS NULL
    AND v_after = v_before;

  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' msg=' || COALESCE(v_msg, '<none>')
    || ' issuance_before=' || v_before::text
    || ' issuance_after=' || v_after::text;

  PERFORM pg_temp.record(
    'S06-033 — Non-numeric rate-ceiling setting fails with an uncoded cast error',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-034 — Clinic self-test verify_aat accepts a freshly minted token
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_k0 text;
  v_i0 text;
  v_verified boolean;
  v_auth_denied boolean := false;
  v_auth_sqlstate text;
  v_auth_got boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';
  v_k0 := pg_temp.s06_id('K0');
  v_i0 := pg_temp.s06_id('I0');

  v_token := pg_temp.s06_mint_as_doc();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  BEGIN
    v_auth_got := auth_internal.verify_aat(v_token);
    v_auth_sqlstate := '<none>';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_auth_denied := true;
      v_auth_sqlstate := '42501';
    WHEN OTHERS THEN
      v_auth_sqlstate := SQLSTATE;
  END;

  PERFORM pg_temp.reset_postgres();
  v_verified := auth_internal.verify_aat(v_token);

  v_ok := pg_temp.s06_is_compact_jws(v_token)
    AND (v_header ->> 'alg') = 'EdDSA'
    AND (v_header ->> 'kid') = v_k0
    AND (v_payload ->> 'iss') = v_i0
    AND v_auth_denied
    AND v_auth_sqlstate = '42501'
    AND v_verified IS TRUE;

  v_detail := 'verified=' || COALESCE(v_verified::text, '<null>')
    || ' alg=' || COALESCE(v_header ->> 'alg', '<null>')
    || ' kid_match=' || ((v_header ->> 'kid') = v_k0)::text
    || ' iss_match=' || ((v_payload ->> 'iss') = v_i0)::text
    || ' auth_sqlstate=' || COALESCE(v_auth_sqlstate, '<none>');

  PERFORM pg_temp.record(
    'S06-034 — Clinic self-test verify_aat accepts a freshly minted token',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-035 — verify_aat rejects a tampered payload
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_token text;
  v_header_part text;
  v_sig_part text;
  v_payload jsonb;
  v_payload_b64 text;
  v_forged text;
  v_verified boolean;
  v_threw boolean := false;
  v_ok boolean;
  v_detail text;
BEGIN
  v_token := pg_temp.s06_mint_as_doc();
  v_header_part := split_part(v_token, '.', 1);
  v_sig_part := split_part(v_token, '.', 3);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_payload := v_payload || jsonb_build_object('role', 'administrator');
  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload::text, 'utf8'));
  v_forged := v_header_part || '.' || v_payload_b64 || '.' || v_sig_part;

  BEGIN
    v_verified := auth_internal.verify_aat(v_forged);
  EXCEPTION
    WHEN OTHERS THEN
      v_threw := true;
      v_detail := 'threw: ' || SQLERRM;
  END;

  v_ok := (NOT v_threw) AND v_verified IS FALSE AND pg_temp.s06_is_compact_jws(v_forged);

  IF NOT v_threw THEN
    v_detail := 'verified=' || COALESCE(v_verified::text, '<null>')
      || ' role=' || COALESCE(pg_temp.decode_jws_payload(v_forged) ->> 'role', '<null>');
  END IF;

  PERFORM pg_temp.record(
    'S06-035 — verify_aat rejects a tampered payload',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-036 — verify_aat rejects malformed tokens without throwing
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_input text;
  v_got boolean;
  v_threw boolean := false;
  v_fail_detail text;
  v_ok boolean := true;
  v_detail text := '';
  v_cases text[] := ARRAY[NULL::text, '', 'abc', 'a.b', 'a.b.c.d', '!!!.@@@.###'];
BEGIN
  PERFORM pg_temp.reset_postgres();

  FOREACH v_input IN ARRAY v_cases LOOP
    v_threw := false;
    v_got := NULL;
    BEGIN
      v_got := auth_internal.verify_aat(v_input);
    EXCEPTION
      WHEN OTHERS THEN
        v_threw := true;
        v_fail_detail := SQLERRM;
    END;

    IF v_threw OR v_got IS DISTINCT FROM false THEN
      v_ok := false;
      v_detail := v_detail
        || ' FAIL input=' || COALESCE(v_input, '<NULL>')
        || ' got=' || COALESCE(v_got::text, '<null>')
        || ' threw=' || v_threw::text
        || ' err=' || COALESCE(v_fail_detail, '')
        || ';';
    END IF;
  END LOOP;

  IF v_ok THEN
    v_detail := 'all six inputs returned false without exception';
  END IF;

  PERFORM pg_temp.record(
    'S06-036 — verify_aat rejects malformed tokens without throwing',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-037 — verify_aat rejects alg ≠ EdDSA or a missing kid
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_token text;
  v_payload_part text;
  v_sig_part text;
  v_k0 text;
  v_hdr_hs jsonb;
  v_hdr_nokid jsonb;
  v_token_hs text;
  v_token_nokid text;
  v_hs boolean;
  v_nokid boolean;
  v_threw boolean := false;
  v_ok boolean;
  v_detail text;
BEGIN
  v_k0 := pg_temp.s06_id('K0');
  v_token := pg_temp.s06_mint_as_doc();
  v_payload_part := split_part(v_token, '.', 2);
  v_sig_part := split_part(v_token, '.', 3);

  v_hdr_hs := jsonb_build_object('alg', 'HS256', 'kid', v_k0);
  v_hdr_nokid := jsonb_build_object('alg', 'EdDSA');
  v_token_hs := auth_internal.base64url_encode(convert_to(v_hdr_hs::text, 'utf8'))
    || '.' || v_payload_part || '.' || v_sig_part;
  v_token_nokid := auth_internal.base64url_encode(convert_to(v_hdr_nokid::text, 'utf8'))
    || '.' || v_payload_part || '.' || v_sig_part;

  BEGIN
    v_hs := auth_internal.verify_aat(v_token_hs);
    v_nokid := auth_internal.verify_aat(v_token_nokid);
  EXCEPTION
    WHEN OTHERS THEN
      v_threw := true;
      v_detail := 'threw: ' || SQLERRM;
  END;

  v_ok := (NOT v_threw) AND v_hs IS FALSE AND v_nokid IS FALSE;

  IF NOT v_threw THEN
    v_detail := 'hs256=' || COALESCE(v_hs::text, '<null>')
      || ' missing_kid=' || COALESCE(v_nokid::text, '<null>');
  END IF;

  PERFORM pg_temp.record(
    'S06-037 — verify_aat rejects alg ≠ EdDSA or a missing kid',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-038 — verify_aat rejects unknown and revoked kids
-- Rebuilds S06-028 (rotate then revoke K0). Restores keystore afterwards.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_k0 text;
  v_token text;
  v_payload_part text;
  v_sig_part text;
  v_rotate public.rpc_result;
  v_revoke public.rpc_result;
  v_unknown_kid uuid;
  v_hdr jsonb;
  v_unknown_token text;
  v_revoked boolean;
  v_unknown boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_k0 := pg_temp.s06_id('K0');

  v_token := pg_temp.s06_mint_as_doc();
  v_payload_part := split_part(v_token, '.', 2);
  v_sig_part := split_part(v_token, '.', 3);

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_rotate := public.rotate_installation_key();
  IF NOT v_rotate.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-038 — verify_aat rejects unknown and revoked kids',
      false,
      'rotate failed: ' || COALESCE(v_rotate.error_code, '<null>')
        || ' — ' || COALESCE(v_rotate.error_message, '')
    );
    PERFORM pg_temp.s06_reenroll();
    RETURN;
  END IF;

  v_revoke := public.revoke_installation_key(v_k0);
  IF NOT v_revoke.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-038 — verify_aat rejects unknown and revoked kids',
      false,
      'revoke(K0) failed: ' || COALESCE(v_revoke.error_code, '<null>')
        || ' — ' || COALESCE(v_revoke.error_message, '')
    );
    PERFORM pg_temp.s06_reenroll();
    RETURN;
  END IF;

  PERFORM pg_temp.reset_postgres();
  v_revoked := auth_internal.verify_aat(v_token);

  -- Unknown kid: generate a random uuid; do not pin the catalog example.
  v_unknown_kid := gen_random_uuid();
  v_hdr := jsonb_build_object('alg', 'EdDSA', 'kid', v_unknown_kid::text);
  v_unknown_token := auth_internal.base64url_encode(convert_to(v_hdr::text, 'utf8'))
    || '.' || v_payload_part || '.' || v_sig_part;
  v_unknown := auth_internal.verify_aat(v_unknown_token);

  v_ok := v_rotate.success
    AND v_revoke.success
    AND v_revoked IS FALSE
    AND v_unknown IS FALSE
    AND v_unknown_kid::text IS DISTINCT FROM v_k0;

  v_detail := 'revoked_kid_verify=' || COALESCE(v_revoked::text, '<null>')
    || ' unknown_kid_verify=' || COALESCE(v_unknown::text, '<null>')
    || ' rotated=' || COALESCE(v_rotate.data ->> 'kid', '<null>');

  PERFORM pg_temp.record(
    'S06-038 — verify_aat rejects unknown and revoked kids',
    v_ok,
    v_detail
  );

  -- Restore an active K0/I0 so later IDs still mint (039 needs a non-revoked kid).
  PERFORM pg_temp.s06_reenroll();
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-039 — verify_aat rejects an iss that does not match the key's installation
-- [SEED]: postgres reads K0 secret_key and re-signs a foreign iss.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_token text;
  v_header_part text;
  v_payload jsonb;
  v_k0 text;
  v_secret bytea;
  v_foreign_iss uuid;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_crafted text;
  v_verified boolean;
  v_threw boolean := false;
  v_ok boolean;
  v_detail text;
BEGIN
  v_k0 := pg_temp.s06_id('K0');
  v_foreign_iss := gen_random_uuid();

  v_token := pg_temp.s06_mint_as_doc();
  v_header_part := split_part(v_token, '.', 1);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_payload := (v_payload - 'iss') || jsonb_build_object('iss', v_foreign_iss::text);

  SELECT ik.secret_key
  INTO STRICT v_secret
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0
    AND ik.is_deleted = false
    AND ik.revoked_at IS NULL;

  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload::text, 'utf8'));
  v_signing_input := v_header_part || '.' || v_payload_b64;
  v_signature := pgsodium.crypto_sign_detached(
    convert_to(v_signing_input, 'utf8'),
    v_secret
  );
  v_crafted := v_signing_input || '.' || auth_internal.base64url_encode(v_signature);

  BEGIN
    v_verified := auth_internal.verify_aat(v_crafted);
  EXCEPTION
    WHEN OTHERS THEN
      v_threw := true;
      v_detail := 'threw: ' || SQLERRM;
  END;

  v_ok := (NOT v_threw)
    AND v_verified IS FALSE
    AND (pg_temp.decode_jws_header(v_crafted) ->> 'kid') = v_k0
    AND (pg_temp.decode_jws_payload(v_crafted) ->> 'iss') = v_foreign_iss::text
    AND v_foreign_iss::text IS DISTINCT FROM pg_temp.s06_id('I0');

  IF NOT v_threw THEN
    v_detail := 'verified=' || COALESCE(v_verified::text, '<null>')
      || ' iss_ne_i0=' || (v_foreign_iss::text IS DISTINCT FROM pg_temp.s06_id('I0'))::text
      || ' kid_match=' || ((pg_temp.decode_jws_header(v_crafted) ->> 'kid') = v_k0)::text;
  END IF;

  PERFORM pg_temp.record(
    'S06-039 — verify_aat rejects an iss that does not match the key''s installation',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-040 — verify_aat does not evaluate exp
-- CONFLICT: catalog restore-to-15 is stale; CODE seed after 20260905120000 is 10.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_token text;
  v_payload jsonb;
  v_exp bigint;
  v_verified boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.app_settings
  SET value_json = '0.01'::jsonb
  WHERE key = 'ai.aat.lifetime_minutes';

  v_token := pg_temp.s06_mint_as_doc();
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_exp := (v_payload ->> 'exp')::bigint;

  -- now() is transaction-stable; wall-clock passage uses clock_timestamp().
  PERFORM pg_sleep(2);
  v_verified := auth_internal.verify_aat(v_token);

  v_ok := pg_temp.s06_is_compact_jws(v_token)
    AND v_verified IS TRUE
    AND v_exp < extract(epoch FROM clock_timestamp())::bigint;

  v_detail := 'verified=' || COALESCE(v_verified::text, '<null>')
    || ' exp=' || COALESCE(v_exp::text, '<null>')
    || ' clock=' || extract(epoch FROM clock_timestamp())::bigint::text
    || ' exp_lt_clock=' || (v_exp < extract(epoch FROM clock_timestamp())::bigint)::text;

  UPDATE ai_internal.app_settings
  SET value_json = '10'::jsonb
  WHERE key = 'ai.aat.lifetime_minutes';

  PERFORM pg_temp.record(
    'S06-040 — verify_aat does not evaluate exp',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-041 — Minted-then-rejected: wrong audience (clinic mint / claim-shape half)
-- Rebuilds S06-031 audience change. Platform HTTP half skipped — Register 5 #17.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_i0 text;
  v_kid text;
  v_kid_in_keystore boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  v_i0 := pg_temp.s06_id('I0');

  UPDATE ai_internal.app_settings
  SET value_json = '"clinic-portal"'::jsonb
  WHERE key = 'ai.aat.audience';

  v_token := pg_temp.s06_mint_as_doc();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_kid := v_header ->> 'kid';

  SELECT EXISTS (
    SELECT 1
    FROM ai_internal.installation_keys ik
    WHERE ik.kid = v_kid
      AND ik.is_deleted = false
  )
  INTO v_kid_in_keystore;

  v_ok := pg_temp.s06_is_compact_jws(v_token)
    AND (v_payload ->> 'aud') = 'clinic-portal'
    AND (v_payload ->> 'iss') = v_i0
    AND v_kid_in_keystore;

  v_detail := 'aud=' || COALESCE(v_payload ->> 'aud', '<null>')
    || ' iss_match=' || ((v_payload ->> 'iss') = v_i0)::text
    || ' compact_jws=' || pg_temp.s06_is_compact_jws(v_token)::text
    || ' kid_in_keystore=' || COALESCE(v_kid_in_keystore::text, '<null>')
    || ' | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)';

  UPDATE ai_internal.app_settings
  SET value_json = '"ai-platform"'::jsonb
  WHERE key = 'ai.aat.audience';

  PERFORM pg_temp.record(
    'S06-041 — Minted-then-rejected: wrong audience',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-042 — Minted-then-rejected: expired AAT (clinic mint / claim-shape half)
-- Rebuilds S06-040. Platform HTTP half skipped — Register 5 #17.
-- CONFLICT: restore lifetime to CODE seed 10, not catalog 15.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_token text;
  v_payload jsonb;
  v_exp bigint;
  v_verified boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.app_settings
  SET value_json = '0.01'::jsonb
  WHERE key = 'ai.aat.lifetime_minutes';

  v_token := pg_temp.s06_mint_as_doc();
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_exp := (v_payload ->> 'exp')::bigint;

  PERFORM pg_sleep(2);
  v_verified := auth_internal.verify_aat(v_token);

  v_ok := pg_temp.s06_is_compact_jws(v_token)
    AND v_verified IS TRUE
    AND v_exp < extract(epoch FROM clock_timestamp())::bigint;

  v_detail := 'clinic_verify=' || COALESCE(v_verified::text, '<null>')
    || ' exp=' || COALESCE(v_exp::text, '<null>')
    || ' exp_lt_clock=' || (v_exp < extract(epoch FROM clock_timestamp())::bigint)::text
    || ' | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)';

  UPDATE ai_internal.app_settings
  SET value_json = '10'::jsonb
  WHERE key = 'ai.aat.lifetime_minutes';

  PERFORM pg_temp.record(
    'S06-042 — Minted-then-rejected: expired AAT',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-043 — Default lifetime within platform cap (clinic mint / claim-shape half)
-- CONFLICT: catalog S06-019 still says exp − iat = 900; CODE seed is 10 min / 600 s
-- after 20260905120000. Platform HTTP half skipped — Register 5 #17.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_iat bigint;
  v_exp bigint;
  v_kid text;
  v_kid_active boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  v_token := pg_temp.s06_mint_as_doc();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_iat := (v_payload ->> 'iat')::bigint;
  v_exp := (v_payload ->> 'exp')::bigint;
  v_kid := v_header ->> 'kid';

  SELECT EXISTS (
    SELECT 1
    FROM ai_internal.installation_keys ik
    WHERE ik.kid = v_kid
      AND ik.is_deleted = false
      AND ik.revoked_at IS NULL
  )
  INTO v_kid_active;

  v_ok := pg_temp.s06_is_compact_jws(v_token)
    AND (v_exp - v_iat) = 600
    AND v_exp > extract(epoch FROM clock_timestamp())::bigint
    AND v_kid_active;

  v_detail := 'exp_minus_iat=' || COALESCE((v_exp - v_iat)::text, '<null>')
    || ' unexpired=' || (v_exp > extract(epoch FROM clock_timestamp())::bigint)::text
    || ' kid_active=' || COALESCE(v_kid_active::text, '<null>')
    || ' | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)';

  PERFORM pg_temp.record(
    'S06-043 — Default lifetime within platform cap: seed-default tokens are accepted',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-044 — Minted-then-rejected: kid unknown to the platform (clinic half)
-- Rebuilds S06-027 rotate. Platform would reject unknown K1 — Register 5 #17.
-- Isolates afterwards by revoking K1 so later IDs mint under K0.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_i0 text;
  v_k0 text;
  v_k1 text;
  v_rotate public.rpc_result;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_verified boolean;
  v_revoke public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_i0 := pg_temp.s06_id('I0');
  v_k0 := pg_temp.s06_id('K0');

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_rotate := public.rotate_installation_key();
  IF NOT v_rotate.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-044 — Minted-then-rejected: kid unknown to the platform',
      false,
      'rotate failed: ' || COALESCE(v_rotate.error_code, '<null>')
        || ' — ' || COALESCE(v_rotate.error_message, '')
        || ' | platform HTTP half is skipped — Register 5 #17'
    );
    RETURN;
  END IF;
  v_k1 := v_rotate.data ->> 'kid';
  PERFORM pg_temp.s06_stash('K1', v_k1);

  v_token := pg_temp.s06_mint_as_doc();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_verified := auth_internal.verify_aat(v_token);

  v_ok := v_rotate.success
    AND v_k1 IS NOT NULL
    AND v_k1 IS DISTINCT FROM v_k0
    AND pg_temp.s06_is_compact_jws(v_token)
    AND (v_header ->> 'kid') = v_k1
    AND (v_payload ->> 'iss') = v_i0
    AND v_verified IS TRUE;

  v_detail := 'kid=' || COALESCE(v_header ->> 'kid', '<null>')
    || ' kid_is_k1=' || ((v_header ->> 'kid') = v_k1)::text
    || ' iss_match=' || ((v_payload ->> 'iss') = v_i0)::text
    || ' clinic_verify=' || COALESCE(v_verified::text, '<null>')
    || ' | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection); platform would reject unknown K1';

  PERFORM pg_temp.record(
    'S06-044 — Minted-then-rejected: kid unknown to the platform',
    v_ok,
    v_detail
  );

  -- Isolate: revoke K1 so S06-045 can mint under K0 (last-active guard needs K0 live).
  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_revoke := public.revoke_installation_key(v_k1);
  PERFORM pg_temp.reset_postgres();
  IF NOT v_revoke.success THEN
    PERFORM pg_temp.s06_reenroll();
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-045 — Minted-then-rejected: kid revoked platform-side (clinic equivalent)
-- Mint under K0, rotate (last-active guard), revoke K0, clinic verify_aat false.
-- Platform HTTP half skipped — Register 5 #17.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_k0 text;
  v_token text;
  v_header jsonb;
  v_rotate public.rpc_result;
  v_revoke public.rpc_result;
  v_verified boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_k0 := pg_temp.s06_id('K0');

  v_token := pg_temp.s06_mint_as_doc();
  v_header := pg_temp.decode_jws_header(v_token);

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_rotate := public.rotate_installation_key();
  IF NOT v_rotate.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-045 — Minted-then-rejected: kid revoked platform-side',
      false,
      'rotate failed: ' || COALESCE(v_rotate.error_code, '<null>')
        || ' — ' || COALESCE(v_rotate.error_message, '')
        || ' | platform HTTP half is skipped — Register 5 #17'
    );
    RETURN;
  END IF;

  v_revoke := public.revoke_installation_key(v_k0);
  IF NOT v_revoke.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-045 — Minted-then-rejected: kid revoked platform-side',
      false,
      'revoke(K0) failed: ' || COALESCE(v_revoke.error_code, '<null>')
        || ' — ' || COALESCE(v_revoke.error_message, '')
        || ' | platform HTTP half is skipped — Register 5 #17'
    );
    RETURN;
  END IF;

  PERFORM pg_temp.reset_postgres();
  v_verified := auth_internal.verify_aat(v_token);

  v_ok := pg_temp.s06_is_compact_jws(v_token)
    AND (v_header ->> 'kid') = v_k0
    AND v_rotate.success
    AND v_revoke.success
    AND v_verified IS FALSE;

  v_detail := 'mint_kid=' || COALESCE(v_header ->> 'kid', '<null>')
    || ' kid_was_k0=' || ((v_header ->> 'kid') = v_k0)::text
    || ' after_revoke_verify=' || COALESCE(v_verified::text, '<null>')
    || ' | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)';

  PERFORM pg_temp.record(
    'S06-045 — Minted-then-rejected: kid revoked platform-side',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-046 — Minted-then-rejected: ver unknown or retired (clinic mint / claim-shape)
-- Rebuilds S06-030 ver="2". Platform HTTP half skipped — Register 5 #17.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_i0 text;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_kid text;
  v_kid_ok boolean;
  v_verified boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  v_i0 := pg_temp.s06_id('I0');

  UPDATE ai_internal.app_settings
  SET value_json = '"2"'::jsonb
  WHERE key = 'ai.aat.ver';

  v_token := pg_temp.s06_mint_as_doc();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_kid := v_header ->> 'kid';
  v_verified := auth_internal.verify_aat(v_token);

  SELECT EXISTS (
    SELECT 1
    FROM ai_internal.installation_keys ik
    WHERE ik.kid = v_kid
      AND ik.is_deleted = false
      AND ik.revoked_at IS NULL
  )
  INTO v_kid_ok;

  v_ok := pg_temp.s06_is_compact_jws(v_token)
    AND (v_payload ->> 'ver') = '2'
    AND (v_payload ->> 'iss') = v_i0
    AND v_kid_ok
    AND v_verified IS TRUE;

  v_detail := 'ver=' || COALESCE(v_payload ->> 'ver', '<null>')
    || ' clinic_verify=' || COALESCE(v_verified::text, '<null>')
    || ' kid_active=' || COALESCE(v_kid_ok::text, '<null>')
    || ' | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)';

  UPDATE ai_internal.app_settings
  SET value_json = '"1"'::jsonb
  WHERE key = 'ai.aat.ver';

  PERFORM pg_temp.record(
    'S06-046 — Minted-then-rejected: ver unknown or retired platform-side',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-047 — Minted-then-rejected: installation unknown to the platform (clinic half)
-- Clinic has the installation; platform-unknown is HTTP-only. Register 5 #17.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_i0 text;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_kid text;
  v_kid_in_keystore boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  v_i0 := pg_temp.s06_id('I0');
  v_token := pg_temp.s06_mint_as_doc();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_kid := v_header ->> 'kid';

  SELECT EXISTS (
    SELECT 1
    FROM ai_internal.installation_keys ik
    WHERE ik.kid = v_kid
      AND ik.is_deleted = false
      AND ik.installation_id::text = v_i0
  )
  INTO v_kid_in_keystore;

  v_ok := pg_temp.s06_is_compact_jws(v_token)
    AND (v_payload ->> 'iss') = v_i0
    AND v_kid IS NOT NULL
    AND v_kid_in_keystore
    AND (v_header ->> 'alg') = 'EdDSA';

  v_detail := 'iss_match=' || ((v_payload ->> 'iss') = v_i0)::text
    || ' compact_jws=' || pg_temp.s06_is_compact_jws(v_token)::text
    || ' kid_bound_to_i0=' || COALESCE(v_kid_in_keystore::text, '<null>')
    || ' | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection); minting does not register platform D1 state';

  PERFORM pg_temp.record(
    'S06-047 — Minted-then-rejected: installation unknown to the platform',
    v_ok,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
