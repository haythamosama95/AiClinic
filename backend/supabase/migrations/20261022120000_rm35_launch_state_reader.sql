-- =============================================================================
-- RM35 (R9-RT1): read-only launch-state reader for the operator launch check.
--
-- Creates a NOLOGIN role `launch_check_reader` whose only privilege is EXECUTE
-- on one SECURITY DEFINER function, `ai_internal.launch_state()`. The function
-- returns a JSON object with exactly these keys: `database_name` (current_database()),
-- `contract_versions` (the `ai.contract_versions` setting) and
-- `set_ai_availability_present` (whether a `set_ai_availability` function exists).
-- The live source parser (ops/launch/live-sources.mjs) requires exactly these keys; a test
-- (R9-RT1 backend launch_state keys match the live source parser) compares them. It reads only
-- and writes nothing.
--
-- This migration creates no login. The operator creates a LOGIN role outside
-- the repository and grants it this role, for example:
--   CREATE ROLE <login> LOGIN PASSWORD '<secret kept outside the repo>';
--   GRANT launch_check_reader TO <login>;
-- The checker connects with default_transaction_read_only=on.
--
-- Forward-only migration; existing migrations are not edited.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'launch_check_reader') THEN
    CREATE ROLE launch_check_reader NOLOGIN;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION ai_internal.launch_state()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, ai_internal
AS $$
DECLARE
  v_contract_versions jsonb;
BEGIN
  SELECT s.value_json
  INTO v_contract_versions
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.contract_versions';

  RETURN jsonb_build_object(
    'database_name', current_database(),
    'contract_versions', v_contract_versions,
    'set_ai_availability_present', EXISTS (
      SELECT 1
      FROM pg_proc p
      WHERE p.proname = 'set_ai_availability'
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_internal.launch_state() FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA ai_internal TO launch_check_reader;
GRANT EXECUTE ON FUNCTION ai_internal.launch_state() TO launch_check_reader;
