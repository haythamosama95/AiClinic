-- Stage 02 catalog SQL: S02-001 … S02-014 (availability flag + enroll/rotate/revoke).
-- Run via backend/tests/catalog/run.sh (do not execute from a stage-writer task).

BEGIN;

\ir harness.sql

SELECT pg_temp.catalog_common_setup();

CREATE TEMP TABLE catalog_s02_ids (
  key text PRIMARY KEY,
  value text NOT NULL
);

-- -----------------------------------------------------------------------------
-- S02-001 — Availability flag returns the seeded default before any enrollment
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doctor_auth uuid;
  v_flag jsonb;
  v_key_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  v_flag := public.get_ai_availability();

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;

  v_ok := v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb
    AND v_key_count = 0;
  v_detail := 'flag=' || COALESCE(v_flag::text, '<null>')
    || ' keys=' || v_key_count::text;

  PERFORM pg_temp.record(
    'S02-001 — Availability flag returns the seeded default before any enrollment',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-002 — Availability flag and keypair RPCs are denied to anon
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_avail_raised boolean := false;
  v_avail_sqlstate text;
  v_avail_msg text;
  v_enroll_raised boolean := false;
  v_enroll_sqlstate text;
  v_enroll_msg text;
  v_key_count int;
  v_flag jsonb;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.set_anon_session();

  BEGIN
    PERFORM public.get_ai_availability();
    v_avail_raised := false;
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_avail_sqlstate := '42501';
      GET STACKED DIAGNOSTICS v_avail_msg = MESSAGE_TEXT;
      v_avail_raised := true;
    WHEN OTHERS THEN
      v_avail_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_avail_msg = MESSAGE_TEXT;
      v_avail_raised := true;
  END;

  BEGIN
    PERFORM public.enroll_installation_keypair();
    v_enroll_raised := false;
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_enroll_sqlstate := '42501';
      GET STACKED DIAGNOSTICS v_enroll_msg = MESSAGE_TEXT;
      v_enroll_raised := true;
    WHEN OTHERS THEN
      v_enroll_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_enroll_msg = MESSAGE_TEXT;
      v_enroll_raised := true;
  END;

  PERFORM set_config('role', 'postgres', true);
  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;
  SELECT s.value_json INTO v_flag
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability'
    AND s.is_deleted = false;

  v_ok := v_avail_raised
    AND v_avail_sqlstate = '42501'
    AND COALESCE(v_avail_msg, '') ILIKE '%get_ai_availability%'
    AND v_enroll_raised
    AND v_enroll_sqlstate = '42501'
    AND COALESCE(v_enroll_msg, '') ILIKE '%enroll_installation_keypair%'
    AND v_key_count = 0
    AND v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb;

  v_detail := 'avail_sqlstate=' || COALESCE(v_avail_sqlstate, '<none>')
    || ' avail_msg=' || COALESCE(v_avail_msg, '<none>')
    || ' enroll_sqlstate=' || COALESCE(v_enroll_sqlstate, '<none>')
    || ' enroll_msg=' || COALESCE(v_enroll_msg, '<none>')
    || ' keys=' || v_key_count::text;

  PERFORM pg_temp.record(
    'S02-002 — Availability flag and keypair RPCs are denied to anon',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-003 — Rotate before any enroll fails with INSTALLATION_NOT_ENROLLED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_result public.rpc_result;
  v_key_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.rotate_installation_key();

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;

  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'INSTALLATION_NOT_ENROLLED'
    AND v_result.error_message = 'Enroll an installation keypair before rotating.'
    AND v_key_count = 0;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>')
    || ' keys=' || v_key_count::text;

  PERFORM pg_temp.record(
    'S02-003 — Rotate before any enroll fails with INSTALLATION_NOT_ENROLLED',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-004 — Enroll as a non-administrator (doctor) is FORBIDDEN
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doctor_auth uuid;
  v_result public.rpc_result;
  v_key_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  v_result := public.enroll_installation_keypair();

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;

  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'FORBIDDEN'
    AND v_result.error_message = 'Only administrators may enroll installation keys.'
    AND v_key_count = 0;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>')
    || ' keys=' || v_key_count::text;

  PERFORM pg_temp.record(
    'S02-004 — Enroll as a non-administrator (doctor) is FORBIDDEN',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-005 — Rotate as a non-administrator (doctor) is FORBIDDEN
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doctor_auth uuid;
  v_result public.rpc_result;
  v_key_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  v_result := public.rotate_installation_key();

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;

  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'FORBIDDEN'
    AND v_result.error_message = 'Only administrators may rotate installation keys.'
    AND v_key_count = 0;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>')
    || ' keys=' || v_key_count::text;

  PERFORM pg_temp.record(
    'S02-005 — Rotate as a non-administrator (doctor) is FORBIDDEN',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-006 — Revoke as a non-administrator (doctor) is FORBIDDEN, even with a blank kid
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doctor_auth uuid;
  v_result public.rpc_result;
  v_key_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  v_result := public.revoke_installation_key('');

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;

  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'FORBIDDEN'
    AND v_result.error_message = 'Only administrators may revoke installation keys.'
    AND v_key_count = 0;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>')
    || ' keys=' || v_key_count::text;

  PERFORM pg_temp.record(
    'S02-006 — Revoke as a non-administrator (doctor) is FORBIDDEN, even with a blank kid',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-007 — Enroll as a deactivated administrator is FORBIDDEN
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot uuid;
  v_boot_auth uuid;
  v_admin uuid;
  v_admin_auth uuid;
  v_org uuid;
  v_setup public.rpc_result;
  v_restore public.rpc_result;
  v_result public.rpc_result;
  v_admin_active boolean;
  v_key_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot FROM catalog_setup WHERE key = 'boot';
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  SELECT value INTO STRICT v_admin FROM catalog_setup WHERE key = 'admin';
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';

  -- set_staff_active reads jwt_organization_id(); harness JWT is sub+role only.
  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_boot_auth::text,
      'role', 'authenticated',
      'organization_id', v_org::text,
      'staff_member_id', v_boot::text
    )::text,
    true
  );
  v_setup := public.set_staff_active(v_admin, false);

  PERFORM pg_temp.reset_postgres();
  SELECT sm.is_active INTO v_admin_active
  FROM public.staff_members sm
  WHERE sm.id = v_admin;

  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  v_result := public.enroll_installation_keypair();

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;

  v_ok := v_setup.success
    AND v_admin_active IS FALSE
    AND v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'FORBIDDEN'
    AND v_result.error_message = 'Only administrators may enroll installation keys.'
    AND v_key_count = 0;

  v_detail := 'setup=' || COALESCE(v_setup.error_code, 'ok')
    || ' admin_active=' || COALESCE(v_admin_active::text, '<null>')
    || ' success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>')
    || ' keys=' || v_key_count::text;

  PERFORM pg_temp.record(
    'S02-007 — Enroll as a deactivated administrator is FORBIDDEN',
    v_ok,
    v_detail
  );

  -- Restore ADMIN for later scenarios (not part of S02-007 expected side effects).
  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_boot_auth::text,
      'role', 'authenticated',
      'organization_id', v_org::text,
      'staff_member_id', v_boot::text
    )::text,
    true
  );
  v_restore := public.set_staff_active(v_admin, true);
  PERFORM pg_temp.reset_postgres();
  IF NOT v_restore.success THEN
    RAISE EXCEPTION 'S02-007 restore ADMIN failed: % — %',
      COALESCE(v_restore.error_code, '<null>'),
      COALESCE(v_restore.error_message, '');
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-008 — Enroll as an auth user with no staff row is FORBIDDEN
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_dead uuid := 'a0000000-0000-4000-8000-00000000dead';
  v_result public.rpc_result;
  v_key_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_dead);
  v_result := public.enroll_installation_keypair();

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;

  v_ok := v_result.success IS FALSE
    AND v_result.data IS NULL
    AND v_result.error_code = 'FORBIDDEN'
    AND v_result.error_message = 'Only administrators may enroll installation keys.'
    AND v_key_count = 0;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' msg=' || COALESCE(v_result.error_message, '<null>')
    || ' keys=' || v_key_count::text;

  PERFORM pg_temp.record(
    'S02-008 — Enroll as an auth user with no staff row is FORBIDDEN',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-009 — First enroll (happy path) mints installation I0 and key K0
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_result public.rpc_result;
  v_k0 text;
  v_i0 text;
  v_x text;
  v_jwk jsonb;
  v_key_count int;
  v_row ai_internal.installation_keys%ROWTYPE;
  v_encoded text;
  v_issuance_count int;
  v_audit_before int;
  v_audit_after int;
  v_flag jsonb;
  v_settings_updated_at timestamptz;
  v_settings_updated_at_after timestamptz;
  v_data_keys text[];
  v_jwk_keys text[];
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_audit_before FROM public.audit_log;
  SELECT s.updated_at INTO v_settings_updated_at
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.enroll_installation_keypair();

  v_k0 := v_result.data ->> 'kid';
  v_i0 := v_result.data ->> 'installation_id';
  v_jwk := v_result.data -> 'public_jwk';
  v_x := v_jwk ->> 'x';

  SELECT array_agg(key ORDER BY key)
  INTO v_data_keys
  FROM jsonb_object_keys(COALESCE(v_result.data, '{}'::jsonb)) AS t(key);

  SELECT array_agg(key ORDER BY key)
  INTO v_jwk_keys
  FROM jsonb_object_keys(COALESCE(v_jwk, '{}'::jsonb)) AS t(key);

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;
  SELECT * INTO v_row FROM ai_internal.installation_keys WHERE kid = v_k0;
  v_encoded := auth_internal.base64url_encode(v_row.public_key);
  SELECT count(*)::int INTO v_issuance_count FROM ai_internal.ai_token_issuance;
  SELECT count(*)::int INTO v_audit_after FROM public.audit_log;
  SELECT s.value_json, s.updated_at
  INTO v_flag, v_settings_updated_at_after
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability'
    AND s.is_deleted = false;

  v_ok := v_result.success IS TRUE
    AND v_result.error_code IS NULL
    AND v_result.error_message IS NULL
    AND v_data_keys = ARRAY['installation_id', 'kid', 'public_jwk']
    AND v_k0 IS NOT NULL
    AND v_i0 IS NOT NULL
    AND v_k0 ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND v_i0 ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND v_jwk_keys = ARRAY['crv', 'kid', 'kty', 'x']
    AND (v_jwk ->> 'kty') = 'OKP'
    AND (v_jwk ->> 'crv') = 'Ed25519'
    AND (v_jwk ->> 'kid') = v_k0
    AND v_x IS NOT NULL
    AND length(v_x) = 43
    AND v_x ~ '^[A-Za-z0-9_-]{43}$'
    AND position('=' IN v_x) = 0
    AND NOT (v_result.data ? 'secret_key')
    AND v_key_count = 1
    AND v_row.kid = v_k0
    AND v_row.installation_id::text = v_i0
    AND v_row.algorithm = 'EdDSA'
    AND octet_length(v_row.public_key) = 32
    AND octet_length(v_row.secret_key) = 64
    AND v_row.revoked_at IS NULL
    AND v_row.is_deleted IS FALSE
    AND v_row.created_by = v_boot_auth
    AND v_row.updated_by = v_boot_auth
    AND v_row.valid_from > clock_timestamp() - interval '5 seconds'
    AND v_row.created_at > clock_timestamp() - interval '5 seconds'
    AND v_encoded = v_x
    AND v_issuance_count = 0
    AND v_audit_after = v_audit_before
    AND v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb
    AND v_settings_updated_at IS NOT DISTINCT FROM v_settings_updated_at_after;

  IF v_ok THEN
    INSERT INTO catalog_s02_ids (key, value) VALUES
      ('I0', v_i0),
      ('K0', v_k0);
  END IF;

  v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
    || ' code=' || COALESCE(v_result.error_code, '<null>')
    || ' kid=' || COALESCE(v_k0, '<null>')
    || ' iid=' || COALESCE(v_i0, '<null>')
    || ' x_len=' || COALESCE(length(v_x)::text, '<null>')
    || ' keys=' || v_key_count::text
    || ' data_keys=' || COALESCE(v_data_keys::text, '<null>');

  PERFORM pg_temp.record(
    'S02-009 — First enroll (happy path) mints installation I0 and key K0',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-010 — Keystore is not readable by authenticated clients
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_raised boolean := false;
  v_sqlstate text;
  v_msg text;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);

  BEGIN
    PERFORM 1 FROM ai_internal.installation_keys;
    v_raised := false;
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_sqlstate := '42501';
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_raised := true;
    WHEN OTHERS THEN
      v_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_raised := true;
  END;

  PERFORM set_config('role', 'postgres', true);
  PERFORM pg_temp.reset_postgres();

  v_ok := v_raised
    AND v_sqlstate = '42501'
    AND COALESCE(v_msg, '') ILIKE '%ai_internal%';

  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' msg=' || COALESCE(v_msg, '<none>');

  PERFORM pg_temp.record(
    'S02-010 — Keystore is not readable by authenticated clients',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-011 — Keypair enrollment does not touch the availability flag
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doctor_auth uuid;
  v_flag jsonb;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  v_flag := public.get_ai_availability();
  PERFORM pg_temp.reset_postgres();

  v_ok := v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb;
  v_detail := 'flag=' || COALESCE(v_flag::text, '<null>');

  PERFORM pg_temp.record(
    'S02-011 — Keypair enrollment does not touch the availability flag',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-012 — Second enroll while an active key exists fails with ALREADY_ENROLLED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_admin_auth uuid;
  v_k0 text;
  v_result public.rpc_result;
  v_key_count int;
  v_active_k0 boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO v_k0 FROM catalog_s02_ids WHERE key = 'K0';

  IF v_k0 IS NULL THEN
    PERFORM pg_temp.record(
      'S02-012 — Second enroll while an active key exists fails with ALREADY_ENROLLED',
      false,
      'K0 not stashed; S02-009 did not pass'
    );
  ELSE
    PERFORM pg_temp.set_authenticated_session(v_admin_auth);
    v_result := public.enroll_installation_keypair();

    PERFORM pg_temp.reset_postgres();
    SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;
    SELECT EXISTS (
      SELECT 1
      FROM ai_internal.installation_keys ik
      WHERE ik.kid = v_k0
        AND ik.revoked_at IS NULL
        AND ik.is_deleted = false
    ) INTO v_active_k0;

    v_ok := v_result.success IS FALSE
      AND v_result.data IS NULL
      AND v_result.error_code = 'ALREADY_ENROLLED'
      AND v_result.error_message = 'An active installation key already exists. Use rotate_installation_key() to rotate keys.'
      AND v_key_count = 1
      AND v_active_k0;

    v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
      || ' code=' || COALESCE(v_result.error_code, '<null>')
      || ' msg=' || COALESCE(v_result.error_message, '<null>')
      || ' keys=' || v_key_count::text
      || ' k0_active=' || COALESCE(v_active_k0::text, '<null>');

    PERFORM pg_temp.record(
      'S02-012 — Second enroll while an active key exists fails with ALREADY_ENROLLED',
      v_ok,
      v_detail
    );
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-013 — Rotate (happy path) adds key K1 under the same installation I0
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_admin_auth uuid;
  v_boot_auth uuid;
  v_k0 text;
  v_i0 text;
  v_result public.rpc_result;
  v_k1 text;
  v_jwk jsonb;
  v_x text;
  v_data_keys text[];
  v_jwk_keys text[];
  v_key_count int;
  v_k0_row ai_internal.installation_keys%ROWTYPE;
  v_k1_row ai_internal.installation_keys%ROWTYPE;
  v_issuance_count int;
  v_flag jsonb;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  SELECT value INTO v_k0 FROM catalog_s02_ids WHERE key = 'K0';
  SELECT value INTO v_i0 FROM catalog_s02_ids WHERE key = 'I0';

  IF v_k0 IS NULL OR v_i0 IS NULL THEN
    PERFORM pg_temp.record(
      'S02-013 — Rotate (happy path) adds key K1 under the same installation I0',
      false,
      'I0/K0 not stashed; S02-009 did not pass'
    );
  ELSE
    PERFORM pg_temp.set_authenticated_session(v_admin_auth);
    v_result := public.rotate_installation_key();

    v_k1 := v_result.data ->> 'kid';
    v_jwk := v_result.data -> 'public_jwk';
    v_x := v_jwk ->> 'x';

    SELECT array_agg(key ORDER BY key)
    INTO v_data_keys
    FROM jsonb_object_keys(COALESCE(v_result.data, '{}'::jsonb)) AS t(key);

    SELECT array_agg(key ORDER BY key)
    INTO v_jwk_keys
    FROM jsonb_object_keys(COALESCE(v_jwk, '{}'::jsonb)) AS t(key);

    PERFORM pg_temp.reset_postgres();
    SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;
    SELECT * INTO v_k0_row FROM ai_internal.installation_keys WHERE kid = v_k0;
    SELECT * INTO v_k1_row FROM ai_internal.installation_keys WHERE kid = v_k1;
    SELECT count(*)::int INTO v_issuance_count FROM ai_internal.ai_token_issuance;
    SELECT s.value_json INTO v_flag
    FROM ai_internal.app_settings s
    WHERE s.key = 'ai.availability'
      AND s.is_deleted = false;

    v_ok := v_result.success IS TRUE
      AND v_result.error_code IS NULL
      AND v_result.error_message IS NULL
      AND v_data_keys = ARRAY['installation_id', 'kid', 'public_jwk']
      AND v_k1 IS NOT NULL
      AND v_k1 <> v_k0
      AND (v_result.data ->> 'installation_id') = v_i0
      AND v_jwk_keys = ARRAY['crv', 'kid', 'kty', 'x']
      AND (v_jwk ->> 'kty') = 'OKP'
      AND (v_jwk ->> 'crv') = 'Ed25519'
      AND (v_jwk ->> 'kid') = v_k1
      AND length(v_x) = 43
      AND v_x ~ '^[A-Za-z0-9_-]{43}$'
      AND NOT (v_result.data ? 'secret_key')
      AND v_key_count = 2
      AND v_k1_row.installation_id::text = v_i0
      AND v_k1_row.algorithm = 'EdDSA'
      AND v_k1_row.revoked_at IS NULL
      AND v_k1_row.is_deleted IS FALSE
      AND v_k1_row.created_by = v_admin_auth
      AND v_k1_row.updated_by = v_admin_auth
      AND octet_length(v_k1_row.public_key) = 32
      AND octet_length(v_k1_row.secret_key) = 64
      AND v_k0_row.revoked_at IS NULL
      AND v_k0_row.is_deleted IS FALSE
      AND v_k0_row.created_by = v_boot_auth
      AND v_k0_row.updated_by = v_boot_auth
      AND v_k0_row.updated_at IS NULL
      AND v_issuance_count = 0
      AND v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb;

    IF v_ok THEN
      INSERT INTO catalog_s02_ids (key, value) VALUES ('K1', v_k1);
    END IF;

    v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
      || ' code=' || COALESCE(v_result.error_code, '<null>')
      || ' k1=' || COALESCE(v_k1, '<null>')
      || ' iid=' || COALESCE(v_result.data ->> 'installation_id', '<null>')
      || ' keys=' || v_key_count::text;

    PERFORM pg_temp.record(
      'S02-013 — Rotate (happy path) adds key K1 under the same installation I0',
      v_ok,
      v_detail
    );
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-014 — Revoke the superseded key K0 (happy path)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_k0 text;
  v_k1 text;
  v_k1_before ai_internal.installation_keys%ROWTYPE;
  v_result public.rpc_result;
  v_payload_revoked_at timestamptz;
  v_k0_row ai_internal.installation_keys%ROWTYPE;
  v_k1_after ai_internal.installation_keys%ROWTYPE;
  v_key_count int;
  v_issuance_count int;
  v_flag jsonb;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  SELECT value INTO v_k0 FROM catalog_s02_ids WHERE key = 'K0';
  SELECT value INTO v_k1 FROM catalog_s02_ids WHERE key = 'K1';

  IF v_k0 IS NULL OR v_k1 IS NULL THEN
    PERFORM pg_temp.record(
      'S02-014 — Revoke the superseded key K0 (happy path)',
      false,
      'K0/K1 not stashed; S02-009/S02-013 did not pass'
    );
  ELSE
    PERFORM pg_temp.reset_postgres();
    SELECT * INTO v_k1_before FROM ai_internal.installation_keys WHERE kid = v_k1;

    PERFORM pg_temp.set_authenticated_session(v_boot_auth);
    v_result := public.revoke_installation_key(v_k0);

    BEGIN
      v_payload_revoked_at := (v_result.data ->> 'revoked_at')::timestamptz;
    EXCEPTION WHEN OTHERS THEN
      v_payload_revoked_at := NULL;
    END;

    PERFORM pg_temp.reset_postgres();
    SELECT * INTO v_k0_row FROM ai_internal.installation_keys WHERE kid = v_k0;
    SELECT * INTO v_k1_after FROM ai_internal.installation_keys WHERE kid = v_k1;
    SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;
    SELECT count(*)::int INTO v_issuance_count FROM ai_internal.ai_token_issuance;
    SELECT s.value_json INTO v_flag
    FROM ai_internal.app_settings s
    WHERE s.key = 'ai.availability'
      AND s.is_deleted = false;

    v_ok := v_result.success IS TRUE
      AND v_result.error_code IS NULL
      AND v_result.error_message IS NULL
      AND (v_result.data ->> 'kid') = v_k0
      AND v_result.data ? 'revoked_at'
      AND v_payload_revoked_at IS NOT NULL
      AND v_k0_row.revoked_at IS NOT NULL
      AND v_payload_revoked_at IS NOT DISTINCT FROM v_k0_row.revoked_at
      AND v_result.data = jsonb_build_object('kid', v_k0, 'revoked_at', v_k0_row.revoked_at)
      AND v_k0_row.revoked_at > clock_timestamp() - interval '5 seconds'
      AND v_k0_row.revoked_at < clock_timestamp() + interval '5 seconds'
      AND v_k0_row.updated_at IS NOT NULL
      AND v_k0_row.updated_by = v_boot_auth
      AND v_k0_row.is_deleted IS FALSE
      AND v_k1_after.revoked_at IS NULL
      AND v_k1_after.updated_at IS NOT DISTINCT FROM v_k1_before.updated_at
      AND v_k1_after.updated_by IS NOT DISTINCT FROM v_k1_before.updated_by
      AND v_k1_after.created_by = v_k1_before.created_by
      AND v_key_count = 2
      AND v_issuance_count = 0
      AND v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb;

    v_detail := 'success=' || COALESCE(v_result.success::text, '<null>')
      || ' code=' || COALESCE(v_result.error_code, '<null>')
      || ' payload_kid=' || COALESCE(v_result.data ->> 'kid', '<null>')
      || ' row_revoked_at=' || COALESCE(v_k0_row.revoked_at::text, '<null>')
      || ' payload_revoked_at=' || COALESCE(v_payload_revoked_at::text, '<null>')
      || ' keys=' || v_key_count::text
      || ' k1_untouched=' || (v_k1_after.revoked_at IS NULL)::text;

    PERFORM pg_temp.record(
      'S02-014 — Revoke the superseded key K0 (happy path)',
      v_ok,
      v_detail
    );
  END IF;
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
