-- Stage 02 catalog SQL: S02-015 … S02-027 (revoke / rotate / availability).
-- Independent of Writer A's file: rebuilds S02-009…S02-014 end state via RPCs
-- as setup only (those IDs are not recorded).

BEGIN;

\ir harness.sql

SELECT pg_temp.catalog_common_setup();

CREATE TEMP TABLE catalog_s02_ids (
  key text PRIMARY KEY,
  value text NOT NULL
);

CREATE OR REPLACE FUNCTION pg_temp.s02_stash(p_key text, p_value text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO catalog_s02_ids (key, value)
  VALUES (p_key, p_value)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s02_id(p_key text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT value FROM catalog_s02_ids WHERE key = p_key;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s02_jwk_ok(p_data jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_data ? 'kid'
    AND p_data ? 'installation_id'
    AND p_data ? 'public_jwk'
    AND NOT (p_data ? 'secret_key')
    AND jsonb_typeof(p_data -> 'public_jwk') = 'object'
    AND NOT (p_data -> 'public_jwk' ? 'd')
    AND (p_data -> 'public_jwk' ->> 'kty') = 'OKP'
    AND (p_data -> 'public_jwk' ->> 'crv') = 'Ed25519'
    AND (p_data -> 'public_jwk' ->> 'kid') = (p_data ->> 'kid')
    AND length(p_data -> 'public_jwk' ->> 'x') = 43
    AND position('=' IN COALESCE(p_data -> 'public_jwk' ->> 'x', '')) = 0;
$$;

-- Prior-state bootstrap (S02-009 enroll, S02-013 rotate, S02-014 revoke).
-- Not recorded as catalog IDs.
DO $$
DECLARE
  v_boot_auth uuid;
  v_admin_auth uuid;
  v_result public.rpc_result;
  v_i0 text;
  v_k0 text;
  v_k1 text;
  v_k0_revoked_at timestamptz;
  v_k1_revoked_at timestamptz;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.enroll_installation_keypair();
  IF NOT v_result.success OR NOT pg_temp.s02_jwk_ok(v_result.data) THEN
    RAISE EXCEPTION 'prior-state enroll failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;
  v_i0 := v_result.data ->> 'installation_id';
  v_k0 := v_result.data ->> 'kid';

  PERFORM pg_temp.reset_postgres();
  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  v_result := public.rotate_installation_key();
  IF NOT v_result.success
     OR NOT pg_temp.s02_jwk_ok(v_result.data)
     OR (v_result.data ->> 'installation_id') IS DISTINCT FROM v_i0
     OR (v_result.data ->> 'kid') IS NOT DISTINCT FROM v_k0 THEN
    RAISE EXCEPTION 'prior-state rotate failed: % — % kid=%',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, ''),
      COALESCE(v_result.data ->> 'kid', '<null>');
  END IF;
  v_k1 := v_result.data ->> 'kid';

  PERFORM pg_temp.reset_postgres();
  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.revoke_installation_key(v_k0);
  IF NOT v_result.success
     OR (v_result.data ->> 'kid') IS DISTINCT FROM v_k0 THEN
    RAISE EXCEPTION 'prior-state revoke(K0) failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  PERFORM pg_temp.reset_postgres();
  SELECT ik.revoked_at INTO STRICT v_k0_revoked_at
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0 AND ik.is_deleted = false;
  SELECT ik.revoked_at INTO STRICT v_k1_revoked_at
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k1 AND ik.is_deleted = false;

  IF v_k0_revoked_at IS NULL OR v_k1_revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'prior-state end-state wrong: K0.revoked_at=% K1.revoked_at=%',
      v_k0_revoked_at, v_k1_revoked_at;
  END IF;

  PERFORM pg_temp.s02_stash('I0', v_i0);
  PERFORM pg_temp.s02_stash('K0', v_k0);
  PERFORM pg_temp.s02_stash('K1', v_k1);
  PERFORM pg_temp.s02_stash('T0', v_k0_revoked_at::text);
END;
$$;

-- S02-015 — Re-revoking an already-revoked key is idempotent
DO $$
DECLARE
  v_boot_auth uuid;
  v_k0 text;
  v_t0 timestamptz;
  v_updated_before timestamptz;
  v_updated_after timestamptz;
  v_revoked_after timestamptz;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_k0 := pg_temp.s02_id('K0');

  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_t0, v_updated_before
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0
    AND ik.is_deleted = false;

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.revoke_installation_key(v_k0);

  PERFORM pg_temp.reset_postgres();
  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_revoked_after, v_updated_after
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0
    AND ik.is_deleted = false;

  v_ok := v_result.success
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND v_result.data = jsonb_build_object('kid', v_k0, 'revoked_at', v_t0)
    AND v_revoked_after IS NOT DISTINCT FROM v_t0
    AND v_updated_after IS NOT DISTINCT FROM v_updated_before;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' error_code=' || COALESCE(v_result.error_code, '<null>')
    || ' data=' || COALESCE(v_result.data::text, '<null>')
    || ' t0=' || COALESCE(v_t0::text, '<null>')
    || ' updated_at_unchanged=' || (v_updated_after IS NOT DISTINCT FROM v_updated_before)::text;

  PERFORM pg_temp.record(
    'S02-015 — Re-revoking an already-revoked key is idempotent',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-016 — Revoke with a blank kid fails with INVALID_INPUT
DO $$
DECLARE
  v_boot_auth uuid;
  v_k0 text;
  v_k1 text;
  v_k0_revoked_at timestamptz;
  v_k0_updated_at timestamptz;
  v_k1_revoked_at timestamptz;
  v_k1_updated_at timestamptz;
  v_k0_revoked_after timestamptz;
  v_k0_updated_after timestamptz;
  v_k1_revoked_after timestamptz;
  v_k1_updated_after timestamptz;
  v_empty public.rpc_result;
  v_ws public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_k0 := pg_temp.s02_id('K0');
  v_k1 := pg_temp.s02_id('K1');

  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_k0_revoked_at, v_k0_updated_at
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0 AND ik.is_deleted = false;
  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_k1_revoked_at, v_k1_updated_at
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k1 AND ik.is_deleted = false;

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_empty := public.revoke_installation_key('');
  v_ws := public.revoke_installation_key('   ');

  PERFORM pg_temp.reset_postgres();
  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_k0_revoked_after, v_k0_updated_after
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0 AND ik.is_deleted = false;
  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_k1_revoked_after, v_k1_updated_after
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k1 AND ik.is_deleted = false;

  v_ok := (NOT v_empty.success)
    AND v_empty.data IS NULL
    AND v_empty.error_code = 'INVALID_INPUT'
    AND v_empty.error_message = 'Key id is required.'
    AND (NOT v_ws.success)
    AND v_ws.data IS NULL
    AND v_ws.error_code = 'INVALID_INPUT'
    AND v_ws.error_message = 'Key id is required.'
    AND v_k0_revoked_after IS NOT DISTINCT FROM v_k0_revoked_at
    AND v_k0_updated_after IS NOT DISTINCT FROM v_k0_updated_at
    AND v_k1_revoked_after IS NOT DISTINCT FROM v_k1_revoked_at
    AND v_k1_updated_after IS NOT DISTINCT FROM v_k1_updated_at;

  v_detail := 'empty=['
    || COALESCE(v_empty.success::text, '<null>')
    || ',' || COALESCE(v_empty.error_code, '<null>')
    || ',' || COALESCE(v_empty.error_message, '')
    || '] ws=['
    || COALESCE(v_ws.success::text, '<null>')
    || ',' || COALESCE(v_ws.error_code, '<null>')
    || ',' || COALESCE(v_ws.error_message, '')
    || ']';

  PERFORM pg_temp.record(
    'S02-016 — Revoke with a blank kid fails with INVALID_INPUT',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-017 — Revoke with an unknown kid fails with KEY_NOT_FOUND
DO $$
DECLARE
  v_boot_auth uuid;
  v_k0 text;
  v_k1 text;
  v_k0_revoked_at timestamptz;
  v_k0_updated_at timestamptz;
  v_k1_revoked_at timestamptz;
  v_k1_updated_at timestamptz;
  v_k0_revoked_after timestamptz;
  v_k0_updated_after timestamptz;
  v_k1_revoked_after timestamptz;
  v_k1_updated_after timestamptz;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_k0 := pg_temp.s02_id('K0');
  v_k1 := pg_temp.s02_id('K1');

  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_k0_revoked_at, v_k0_updated_at
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0 AND ik.is_deleted = false;
  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_k1_revoked_at, v_k1_updated_at
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k1 AND ik.is_deleted = false;

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.revoke_installation_key('00000000-0000-0000-0000-000000000000');

  PERFORM pg_temp.reset_postgres();
  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_k0_revoked_after, v_k0_updated_after
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0 AND ik.is_deleted = false;
  SELECT ik.revoked_at, ik.updated_at
  INTO STRICT v_k1_revoked_after, v_k1_updated_after
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k1 AND ik.is_deleted = false;

  v_ok := (NOT v_result.success)
    AND v_result.data IS NULL
    AND v_result.error_code = 'KEY_NOT_FOUND'
    AND v_result.error_message = 'Installation key was not found.'
    AND v_k0_revoked_after IS NOT DISTINCT FROM v_k0_revoked_at
    AND v_k0_updated_after IS NOT DISTINCT FROM v_k0_updated_at
    AND v_k1_revoked_after IS NOT DISTINCT FROM v_k1_revoked_at
    AND v_k1_updated_after IS NOT DISTINCT FROM v_k1_updated_at;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' error_code=' || COALESCE(v_result.error_code, '<null>')
    || ' error_message=' || COALESCE(v_result.error_message, '');

  PERFORM pg_temp.record(
    'S02-017 — Revoke with an unknown kid fails with KEY_NOT_FOUND',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-018 — Revoke with a soft-deleted kid fails with KEY_NOT_FOUND
DO $$
DECLARE
  v_boot_auth uuid;
  v_k0 text;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
  v_still_deleted boolean;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_k0 := pg_temp.s02_id('K0');

  -- [SEED] privileged soft-delete (no RPC soft-deletes key rows)
  UPDATE ai_internal.installation_keys
  SET is_deleted = true,
      deleted_at = now()
  WHERE kid = v_k0;

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.revoke_installation_key(v_k0);

  PERFORM pg_temp.reset_postgres();
  SELECT ik.is_deleted
  INTO STRICT v_still_deleted
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0;

  v_ok := (NOT v_result.success)
    AND v_result.data IS NULL
    AND v_result.error_code = 'KEY_NOT_FOUND'
    AND v_result.error_message = 'Installation key was not found.'
    AND v_still_deleted;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' error_code=' || COALESCE(v_result.error_code, '<null>')
    || ' error_message=' || COALESCE(v_result.error_message, '')
    || ' still_deleted=' || v_still_deleted::text;

  -- restore so later scenarios see K0 as revoked-but-visible
  UPDATE ai_internal.installation_keys
  SET is_deleted = false,
      deleted_at = NULL,
      deleted_by = NULL
  WHERE kid = v_k0;

  PERFORM pg_temp.record(
    'S02-018 — Revoke with a soft-deleted kid fails with KEY_NOT_FOUND',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-019 — Revoking the last active key fails with CANNOT_REVOKE_LAST_ACTIVE_KEY
DO $$
DECLARE
  v_boot_auth uuid;
  v_k1 text;
  v_active_before int;
  v_active_after int;
  v_k1_revoked_at timestamptz;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_k1 := pg_temp.s02_id('K1');

  SELECT count(*)::int INTO v_active_before
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL;

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.revoke_installation_key(v_k1);

  PERFORM pg_temp.reset_postgres();
  SELECT ik.revoked_at INTO STRICT v_k1_revoked_at
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k1
    AND ik.is_deleted = false;

  SELECT count(*)::int INTO v_active_after
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL;

  v_ok := v_active_before = 1
    AND (NOT v_result.success)
    AND v_result.data IS NULL
    AND v_result.error_code = 'CANNOT_REVOKE_LAST_ACTIVE_KEY'
    AND v_result.error_message = 'Cannot revoke the last active installation key. Rotate a replacement key first.'
    AND v_k1_revoked_at IS NULL
    AND v_active_after = 1;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' error_code=' || COALESCE(v_result.error_code, '<null>')
    || ' error_message=' || COALESCE(v_result.error_message, '')
    || ' active_before=' || v_active_before::text
    || ' k1_revoked_at=' || COALESCE(v_k1_revoked_at::text, '<null>');

  PERFORM pg_temp.record(
    'S02-019 — Revoking the last active key fails with CANNOT_REVOKE_LAST_ACTIVE_KEY',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-020 — Production rotation order: rotate to K2, then revoke K1 succeeds
DO $$
DECLARE
  v_boot_auth uuid;
  v_admin_auth uuid;
  v_i0 text;
  v_k0 text;
  v_k1 text;
  v_k2 text;
  v_rotate public.rpc_result;
  v_revoke public.rpc_result;
  v_row_count int;
  v_distinct_install int;
  v_active_count int;
  v_k0_revoked boolean;
  v_k1_revoked boolean;
  v_k2_active boolean;
  v_k2_created_by uuid;
  v_k1_updated_by uuid;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  v_i0 := pg_temp.s02_id('I0');
  v_k0 := pg_temp.s02_id('K0');
  v_k1 := pg_temp.s02_id('K1');

  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  v_rotate := public.rotate_installation_key();
  v_k2 := v_rotate.data ->> 'kid';

  PERFORM pg_temp.reset_postgres();
  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_revoke := public.revoke_installation_key(v_k1);

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int,
         count(DISTINCT ik.installation_id)::int
  INTO v_row_count, v_distinct_install
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false;

  SELECT count(*)::int INTO v_active_count
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL;

  SELECT ik.revoked_at IS NOT NULL INTO STRICT v_k0_revoked
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k0 AND ik.is_deleted = false;
  SELECT ik.revoked_at IS NOT NULL, ik.updated_by
  INTO STRICT v_k1_revoked, v_k1_updated_by
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k1 AND ik.is_deleted = false;
  SELECT ik.revoked_at IS NULL, ik.created_by
  INTO STRICT v_k2_active, v_k2_created_by
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = v_k2 AND ik.is_deleted = false;

  v_ok := v_rotate.success
    AND v_rotate.error_code IS NULL
    AND v_rotate.error_message IS NULL
    AND pg_temp.s02_jwk_ok(v_rotate.data)
    AND (v_rotate.data ->> 'installation_id') = v_i0
    AND v_k2 IS NOT NULL
    AND v_k2 IS DISTINCT FROM v_k0
    AND v_k2 IS DISTINCT FROM v_k1
    AND v_revoke.success
    AND v_revoke.error_code IS NULL
    AND v_revoke.error_message IS NULL
    AND (v_revoke.data ->> 'kid') = v_k1
    AND v_revoke.data ? 'revoked_at'
    AND v_row_count = 3
    AND v_distinct_install = 1
    AND v_active_count = 1
    AND v_k0_revoked
    AND v_k1_revoked
    AND v_k2_active
    AND v_k2_created_by = v_admin_auth
    AND v_k1_updated_by = v_boot_auth
    AND NOT EXISTS (
      SELECT 1
      FROM ai_internal.installation_keys ik
      WHERE ik.is_deleted = false
        AND ik.installation_id::text IS DISTINCT FROM v_i0
    );

  IF v_k2 IS NOT NULL THEN
    PERFORM pg_temp.s02_stash('K2', v_k2);
  END IF;

  v_detail := 'rotate_ok=' || COALESCE(v_rotate.success::text, '<null>')
    || ' k2=' || COALESCE(v_k2, '<null>')
    || ' revoke_ok=' || COALESCE(v_revoke.success::text, '<null>')
    || ' revoke_code=' || COALESCE(v_revoke.error_code, '<null>')
    || ' rows=' || v_row_count::text
    || ' active=' || v_active_count::text;

  PERFORM pg_temp.record(
    'S02-020 — Production rotation order: rotate to K2, then revoke K1 succeeds',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-021 — Single-installation trigger rejects a second installation_id
DO $$
DECLARE
  v_i0 text;
  v_raised boolean := false;
  v_msg text;
  v_state text;
  v_distinct_install int;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  v_i0 := pg_temp.s02_id('I0');

  BEGIN
    -- ACTION (not seed): privileged INSERT with a second installation_id
    INSERT INTO ai_internal.installation_keys (
      kid, installation_id, public_key, secret_key, algorithm
    )
    VALUES (
      gen_random_uuid()::text,
      gen_random_uuid(),
      decode('00', 'hex'),
      decode('00', 'hex'),
      'EdDSA'
    );
    v_msg := 'INSERT succeeded unexpectedly';
    v_state := NULL;
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      GET STACKED DIAGNOSTICS
        v_msg = MESSAGE_TEXT,
        v_state = RETURNED_SQLSTATE;
      v_raised := (v_state = 'P0001' AND v_msg = 'SINGLE_INSTALLATION_VIOLATION');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_msg = MESSAGE_TEXT,
        v_state = RETURNED_SQLSTATE;
      v_raised := false;
  END;

  SELECT count(DISTINCT ik.installation_id)::int
  INTO v_distinct_install
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false;

  v_ok := v_raised
    AND v_distinct_install = 1
    AND NOT EXISTS (
      SELECT 1
      FROM ai_internal.installation_keys ik
      WHERE ik.is_deleted = false
        AND ik.installation_id::text IS DISTINCT FROM v_i0
    );

  v_detail := 'raised=' || v_raised::text
    || ' sqlstate=' || COALESCE(v_state, '<null>')
    || ' message=' || COALESCE(v_msg, '')
    || ' distinct_installation_id=' || v_distinct_install::text;

  PERFORM pg_temp.record(
    'S02-021 — Single-installation trigger rejects a second installation_id',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-022 — Recovery re-enroll after all keys are revoked reuses installation I0
DO $$
DECLARE
  v_boot_auth uuid;
  v_i0 text;
  v_k0 text;
  v_k1 text;
  v_k2 text;
  v_kx text;
  v_active_before int;
  v_active_after int;
  v_row_count int;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  v_i0 := pg_temp.s02_id('I0');
  v_k0 := pg_temp.s02_id('K0');
  v_k1 := pg_temp.s02_id('K1');
  v_k2 := pg_temp.s02_id('K2');

  -- [SEED] privileged revoke-all (zero-active is unreachable via the revoke RPC)
  UPDATE ai_internal.installation_keys
  SET revoked_at = clock_timestamp()
  WHERE is_deleted = false
    AND revoked_at IS NULL;

  SELECT count(*)::int INTO v_active_before
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL;

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.enroll_installation_keypair();
  v_kx := v_result.data ->> 'kid';

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_active_after
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL;
  SELECT count(*)::int INTO v_row_count
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false;

  v_ok := v_active_before = 0
    AND v_result.success
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND pg_temp.s02_jwk_ok(v_result.data)
    AND (v_result.data ->> 'installation_id') = v_i0
    AND v_kx IS NOT NULL
    AND v_kx IS DISTINCT FROM v_k0
    AND v_kx IS DISTINCT FROM v_k1
    AND v_kx IS DISTINCT FROM v_k2
    AND v_active_after = 1
    AND v_row_count = 4
    AND EXISTS (
      SELECT 1
      FROM ai_internal.installation_keys ik
      WHERE ik.kid = v_kx
        AND ik.installation_id::text = v_i0
        AND ik.revoked_at IS NULL
        AND ik.is_deleted = false
    )
    AND NOT EXISTS (
      SELECT 1
      FROM ai_internal.installation_keys ik
      WHERE ik.is_deleted = false
        AND ik.kid IS DISTINCT FROM v_kx
        AND ik.revoked_at IS NULL
    );

  IF v_kx IS NOT NULL THEN
    PERFORM pg_temp.s02_stash('KX', v_kx);
  END IF;
  IF v_result.data IS NOT NULL THEN
    PERFORM pg_temp.s02_stash('s022_data', v_result.data::text);
  END IF;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' error_code=' || COALESCE(v_result.error_code, '<null>')
    || ' kx=' || COALESCE(v_kx, '<null>')
    || ' installation_id=' || COALESCE(v_result.data ->> 'installation_id', '<null>')
    || ' active_before=' || v_active_before::text
    || ' active_after=' || v_active_after::text;

  PERFORM pg_temp.record(
    'S02-022 — Recovery re-enroll after all keys are revoked reuses installation I0',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-023 — Rotate succeeds when every key is revoked but rows exist
DO $$
DECLARE
  v_admin_auth uuid;
  v_i0 text;
  v_k0 text;
  v_k1 text;
  v_k2 text;
  v_kx text;
  v_k3 text;
  v_active_before int;
  v_active_after int;
  v_row_count int;
  v_result public.rpc_result;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  v_i0 := pg_temp.s02_id('I0');
  v_k0 := pg_temp.s02_id('K0');
  v_k1 := pg_temp.s02_id('K1');
  v_k2 := pg_temp.s02_id('K2');
  v_kx := pg_temp.s02_id('KX');

  -- [SEED] re-apply privileged revoke-all (revoke KX; rows remain)
  UPDATE ai_internal.installation_keys
  SET revoked_at = clock_timestamp()
  WHERE is_deleted = false
    AND revoked_at IS NULL;

  SELECT count(*)::int INTO v_active_before
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL;

  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  v_result := public.rotate_installation_key();
  v_k3 := v_result.data ->> 'kid';

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_active_after
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL;
  SELECT count(*)::int INTO v_row_count
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false;

  v_ok := v_active_before = 0
    AND v_result.success
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND pg_temp.s02_jwk_ok(v_result.data)
    AND (v_result.data ->> 'installation_id') = v_i0
    AND v_k3 IS NOT NULL
    AND v_k3 IS DISTINCT FROM v_k0
    AND v_k3 IS DISTINCT FROM v_k1
    AND v_k3 IS DISTINCT FROM v_k2
    AND v_k3 IS DISTINCT FROM v_kx
    AND v_active_after = 1
    AND v_row_count = 5
    AND EXISTS (
      SELECT 1
      FROM ai_internal.installation_keys ik
      WHERE ik.kid = v_k3
        AND ik.installation_id::text = v_i0
        AND ik.revoked_at IS NULL
        AND ik.is_deleted = false
        AND ik.created_by = v_admin_auth
    )
    AND EXISTS (
      SELECT 1
      FROM ai_internal.installation_keys ik
      WHERE ik.kid = v_kx
        AND ik.revoked_at IS NOT NULL
        AND ik.is_deleted = false
    );

  IF v_k3 IS NOT NULL THEN
    PERFORM pg_temp.s02_stash('K3', v_k3);
  END IF;
  IF v_result.data IS NOT NULL THEN
    PERFORM pg_temp.s02_stash('s023_data', v_result.data::text);
  END IF;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' error_code=' || COALESCE(v_result.error_code, '<null>')
    || ' k3=' || COALESCE(v_k3, '<null>')
    || ' installation_id=' || COALESCE(v_result.data ->> 'installation_id', '<null>')
    || ' active_before=' || v_active_before::text
    || ' active_after=' || v_active_after::text;

  PERFORM pg_temp.record(
    'S02-023 — Rotate succeeds when every key is revoked but rows exist',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-024 — Availability flag flip after Stage 3 platform enrollment
-- Stage 3 Worker enrollment is simulated: BOOT calls set_ai_availability only.
DO $$
DECLARE
  v_boot_auth uuid;
  v_doctor_auth uuid;
  v_created_before uuid;
  v_created_after uuid;
  v_updated_after uuid;
  v_value jsonb;
  v_set public.rpc_result;
  v_get jsonb;
  v_expected jsonb := '{"enrolled": true, "platform_base_url": "http://127.0.0.1:8787"}'::jsonb;
  v_ok boolean := false;
  v_detail text;
  v_set_err text;
  v_set_state text;
  v_get_err text;
  v_get_state text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  SELECT s.created_by INTO v_created_before
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  BEGIN
    v_set := public.set_ai_availability(true, 'http://127.0.0.1:8787'::text);
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_set_err = MESSAGE_TEXT,
        v_set_state = RETURNED_SQLSTATE;
      v_set := NULL;
  END;

  PERFORM pg_temp.reset_postgres();
  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  BEGIN
    v_get := public.get_ai_availability();
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_get_err = MESSAGE_TEXT,
        v_get_state = RETURNED_SQLSTATE;
      v_get := NULL;
  END;

  PERFORM pg_temp.reset_postgres();
  SELECT s.value_json, s.created_by, s.updated_by
  INTO STRICT v_value, v_created_after, v_updated_after
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability'
    AND s.is_deleted = false;

  v_ok := (v_set.success IS TRUE)
    AND v_set.error_code IS NULL
    AND v_set.error_message IS NULL
    AND v_set.data = v_expected
    AND v_get = v_expected
    AND v_value = v_expected
    AND v_updated_after = v_boot_auth
    AND v_created_after = v_boot_auth;

  v_detail := 'set_success=' || COALESCE(v_set.success::text, '<null>')
    || ' set_data=' || COALESCE(v_set.data::text, '<null>')
    || ' get=' || COALESCE(v_get::text, '<null>')
    || ' updated_by=' || COALESCE(v_updated_after::text, '<null>')
    || ' created_by=' || COALESCE(v_created_after::text, '<null>')
    || ' created_before=' || COALESCE(v_created_before::text, '<null>')
    || ' set_err=' || COALESCE(v_set_state, '<none>')
    || ':' || COALESCE(v_set_err, '')
    || ' get_err=' || COALESCE(v_get_state, '<none>')
    || ':' || COALESCE(v_get_err, '');

  PERFORM pg_temp.record(
    'S02-024 — Availability flag flip after Stage 3 platform enrollment',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-025 — Availability falls back to the COALESCE default when the row is missing/soft-deleted
DO $$
DECLARE
  v_admin_auth uuid;
  v_got jsonb;
  v_expected jsonb := '{"enrolled": false, "platform_base_url": null}'::jsonb;
  v_ok boolean := false;
  v_detail text;
  v_call_err text;
  v_call_state text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';

  -- [SEED] privileged soft-delete (no RPC mutates this row this way)
  UPDATE ai_internal.app_settings
  SET is_deleted = true,
      deleted_at = now()
  WHERE key = 'ai.availability';

  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  BEGIN
    v_got := public.get_ai_availability();
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_call_err = MESSAGE_TEXT,
        v_call_state = RETURNED_SQLSTATE;
      v_got := NULL;
  END;

  PERFORM pg_temp.reset_postgres();
  v_ok := v_got = v_expected AND v_got IS NOT NULL;

  v_detail := 'got=' || COALESCE(v_got::text, '<null>')
    || ' call_err=' || COALESCE(v_call_state, '<none>')
    || ':' || COALESCE(v_call_err, '');

  UPDATE ai_internal.app_settings
  SET is_deleted = false,
      deleted_at = NULL,
      deleted_by = NULL
  WHERE key = 'ai.availability';

  PERFORM pg_temp.record(
    'S02-025 — Availability falls back to the COALESCE default when the row is missing/soft-deleted',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-026 — Administrator holds the ai.visit_summary grant; doctor does not
DO $$
DECLARE
  v_admin_auth uuid;
  v_admin_access boolean;
  v_admin_summary boolean;
  v_doctor_access boolean;
  v_granted_summary_others int;
  v_false_visible int;
  v_ok boolean := false;
  v_detail text;
  v_call_err text;
  v_call_state text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';

  -- As ADMIN: harness JWT uses role=authenticated (PostgREST session role).
  -- CODE jwt_staff_role() reads staff_role, then falls back to role; overlay
  -- staff_role so RLS that calls jwt_staff_role() matches production claims.
  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_auth::text,
      'role', 'authenticated',
      'staff_role', 'administrator'
    )::text,
    true
  );
  BEGIN
    SELECT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.is_deleted = false
        AND rp.role = 'administrator'::public.staff_role
        AND rp.permission_key = 'ai.access'
        AND rp.is_granted = true
    ) INTO v_admin_access;

    SELECT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.is_deleted = false
        AND rp.role = 'administrator'::public.staff_role
        AND rp.permission_key = 'ai.visit_summary'
        AND rp.is_granted = true
    ) INTO v_admin_summary;

    SELECT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.is_deleted = false
        AND rp.role = 'doctor'::public.staff_role
        AND rp.permission_key = 'ai.access'
        AND rp.is_granted = true
    ) INTO v_doctor_access;

    SELECT count(*)::int INTO v_granted_summary_others
    FROM public.roles_permissions rp
    WHERE rp.permission_key = 'ai.visit_summary'
      AND rp.is_deleted = false
      AND rp.is_granted = true
      AND rp.role IN (
        'doctor'::public.staff_role,
        'receptionist'::public.staff_role,
        'lab_staff'::public.staff_role
      );

    SELECT count(*)::int INTO v_false_visible
    FROM public.roles_permissions rp
    WHERE rp.permission_key LIKE 'ai.%'
      AND rp.is_deleted = false
      AND rp.is_granted = false;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_call_err = MESSAGE_TEXT,
        v_call_state = RETURNED_SQLSTATE;
  END;

  PERFORM pg_temp.reset_postgres();

  v_ok := v_admin_access IS TRUE
    AND v_admin_summary IS TRUE
    AND v_doctor_access IS TRUE
    AND v_granted_summary_others = 0
    AND v_false_visible > 0;

  v_detail := 'admin_access=' || COALESCE(v_admin_access::text, '<null>')
    || ' admin_visit_summary=' || COALESCE(v_admin_summary::text, '<null>')
    || ' doctor_access=' || COALESCE(v_doctor_access::text, '<null>')
    || ' granted_summary_others=' || COALESCE(v_granted_summary_others::text, '<null>')
    || ' false_rows_visible_to_admin=' || COALESCE(v_false_visible::text, '<null>')
    || ' call_err=' || COALESCE(v_call_state, '<none>')
    || ':' || COALESCE(v_call_err, '');

  PERFORM pg_temp.record(
    'S02-026 — Administrator holds the ai.visit_summary grant; doctor does not',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-027 — Stage 3 handoff: enroll output is exactly what platform enrollment consumes
-- Catalog Action SQL cites K0 (setup note: K2); after S02-023 the newest ACTIVE key is K3.
DO $$
DECLARE
  v_i0 text;
  v_rpc jsonb;
  v_kid text;
  v_handoff jsonb;
  v_secret_on_row boolean;
  v_ok boolean := false;
  v_detail text;
  v_call_err text;
  v_call_state text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  v_i0 := pg_temp.s02_id('I0');
  BEGIN
    v_rpc := pg_temp.s02_id('s023_data')::jsonb;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_call_err = MESSAGE_TEXT,
        v_call_state = RETURNED_SQLSTATE;
      v_rpc := NULL;
  END;

  BEGIN
    SELECT jsonb_build_object(
             'installation_id', ik.installation_id,
             'kid', ik.kid,
             'public_key', auth_internal.base64url_encode(ik.public_key),
             'algorithm', 'EdDSA'
           ),
           ik.kid,
           (ik.secret_key IS NOT NULL AND octet_length(ik.secret_key) = 64)
    INTO STRICT v_handoff, v_kid, v_secret_on_row
    FROM ai_internal.installation_keys ik
    WHERE ik.is_deleted = false
      AND ik.revoked_at IS NULL
    ORDER BY ik.valid_from DESC, ik.kid DESC
    LIMIT 1;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_call_err = MESSAGE_TEXT,
        v_call_state = RETURNED_SQLSTATE;
      v_handoff := NULL;
      v_kid := NULL;
      v_secret_on_row := NULL;
  END;

  v_ok := v_rpc IS NOT NULL
    AND (v_handoff ->> 'installation_id') = v_i0
    AND (v_handoff ->> 'installation_id') = (v_rpc ->> 'installation_id')
    AND (v_handoff ->> 'kid') = (v_rpc ->> 'kid')
    AND v_kid = (v_rpc ->> 'kid')
    AND (v_handoff ->> 'public_key') = (v_rpc -> 'public_jwk' ->> 'x')
    AND (v_handoff ->> 'algorithm') = 'EdDSA'
    AND pg_temp.s02_jwk_ok(v_rpc)
    AND NOT (v_rpc ? 'secret_key')
    AND NOT (v_handoff ? 'secret_key')
    AND v_secret_on_row IS TRUE
    AND v_kid = pg_temp.s02_id('K3');

  v_detail := 'handoff=' || COALESCE(v_handoff::text, '<null>')
    || ' rpc_kid=' || COALESCE(v_rpc ->> 'kid', '<null>')
    || ' newest_kid=' || COALESCE(v_kid, '<null>')
    || ' has_row_secret=' || COALESCE(v_secret_on_row::text, '<null>')
    || ' call_err=' || COALESCE(v_call_state, '<none>')
    || ':' || COALESCE(v_call_err, '');

  PERFORM pg_temp.record(
    'S02-027 — Stage 3 handoff: enroll output is exactly what platform enrollment consumes',
    v_ok,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
