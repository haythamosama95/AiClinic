-- Stage 02 catalog SQL: S02-001, S02-002, S02-011 (availability after installation-key drop).
-- Enroll / rotate / revoke RPC cases (S02-003 … S02-014) were removed when
-- installation_keys custody was dropped.

BEGIN;

\ir harness.sql

-- Post-P5.1: installation_keys is dropped; keep catalog_common_setup runnable.
CREATE OR REPLACE FUNCTION pg_temp.reset_keystore()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM ai_internal.ai_token_issuance;
  IF to_regclass('ai_internal.installation_keys') IS NOT NULL THEN
    DELETE FROM ai_internal.installation_keys;
  END IF;
  UPDATE ai_internal.app_settings
  SET
    value_json = '{"enrolled": false, "platform_base_url": null}'::jsonb,
    is_deleted = false,
    deleted_at = NULL,
    deleted_by = NULL
  WHERE key = 'ai.availability';
END;
$$;

SELECT pg_temp.catalog_common_setup();

INSERT INTO ai_internal.membership (user_id, organization_id, role)
SELECT sm.auth_user_id, org.value, sm.role
FROM public.staff_members sm
JOIN catalog_setup org ON org.key = 'org'
JOIN catalog_setup actor ON actor.key = 'boot_auth'
  AND sm.auth_user_id = actor.value
WHERE sm.is_deleted = false
ON CONFLICT (user_id, organization_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- S02-001 — Availability flag returns the seeded default before any enrollment
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doctor_auth uuid;
  v_flag jsonb;
  v_keys_absent boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  v_flag := public.get_ai_availability();

  PERFORM pg_temp.reset_postgres();
  v_keys_absent := to_regclass('ai_internal.installation_keys') IS NULL;

  v_ok := v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb
    AND v_keys_absent;
  v_detail := 'flag=' || COALESCE(v_flag::text, '<null>')
    || ' installation_keys_absent=' || v_keys_absent::text;

  PERFORM pg_temp.record(
    'S02-001 — Availability flag returns the seeded default before any enrollment',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-002 — Availability flag is denied to anon
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_avail_raised boolean := false;
  v_avail_sqlstate text;
  v_avail_msg text;
  v_keys_absent boolean;
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

  PERFORM set_config('role', 'postgres', true);
  PERFORM pg_temp.reset_postgres();
  v_keys_absent := to_regclass('ai_internal.installation_keys') IS NULL;
  SELECT s.value_json INTO v_flag
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability'
    AND s.is_deleted = false;

  v_ok := v_avail_raised
    AND v_avail_sqlstate = '42501'
    AND COALESCE(v_avail_msg, '') ILIKE '%get_ai_availability%'
    AND v_keys_absent
    AND v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb;

  v_detail := 'avail_sqlstate=' || COALESCE(v_avail_sqlstate, '<none>')
    || ' avail_msg=' || COALESCE(v_avail_msg, '<none>')
    || ' installation_keys_absent=' || v_keys_absent::text;

  PERFORM pg_temp.record(
    'S02-002 — Availability flag is denied to anon',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-011 — Availability flag is unchanged without platform enrollment
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
    'S02-011 — Availability flag is unchanged without platform enrollment',
    v_ok,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
