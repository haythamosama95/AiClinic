-- Verifies public RPC signatures match specs/002-auth-rbac/contracts/*.md (Phase 11 T062).
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/rpc_contract_alignment.sql

BEGIN;

CREATE TEMP TABLE rpc_contract_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

-- bootstrap_create_organization(p_name, p_settings_json, p_logo_url, p_currency_code, p_timezone)
INSERT INTO rpc_contract_results
SELECT
  'bootstrap_create_organization_signature',
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'bootstrap_create_organization'
      AND pg_get_function_identity_arguments(p.oid) =
        'p_name text, p_settings_json jsonb, p_logo_url text, p_currency_code text, p_timezone text'
  ),
  coalesce(
    (SELECT pg_get_function_identity_arguments(p.oid)
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'bootstrap_create_organization'
     LIMIT 1),
    '<missing>'
  );

-- bootstrap_create_branch: implementation order (address/phone before code per migration 20260521110000).
INSERT INTO rpc_contract_results
SELECT
  'bootstrap_create_branch_signature',
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'bootstrap_create_branch'
      AND pg_get_function_identity_arguments(p.oid) =
        'p_organization_id uuid, p_name text, p_address text, p_phone text, p_code text, p_maps_url text'
  ),
  coalesce(
    (SELECT pg_get_function_identity_arguments(p.oid)
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'bootstrap_create_branch'
     LIMIT 1),
    '<missing>'
  );

INSERT INTO rpc_contract_results
SELECT
  'create_staff_account_signature',
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'create_staff_account'
      AND pg_get_function_identity_arguments(p.oid) =
        'p_username text, p_password text, p_full_name text, p_role staff_role, p_branch_ids uuid[], p_primary_branch_id uuid, p_phone text'
  ),
  coalesce(
    (SELECT pg_get_function_identity_arguments(p.oid)
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'create_staff_account'
     LIMIT 1),
    '<missing>'
  );

INSERT INTO rpc_contract_results
SELECT
  'admin_reset_staff_password_signature',
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'admin_reset_staff_password'
      AND pg_get_function_identity_arguments(p.oid) = 'p_staff_member_id uuid, p_new_password text'
  ),
  coalesce(
    (SELECT pg_get_function_identity_arguments(p.oid)
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_reset_staff_password'
     LIMIT 1),
    '<missing>'
  );

-- GoTrue hook: only get_custom_claims(event jsonb) — uuid overload must not exist.
INSERT INTO rpc_contract_results
SELECT
  'get_custom_claims_event_jsonb_only',
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'get_custom_claims'
      AND pg_get_function_identity_arguments(p.oid) = 'event jsonb'
  )
  AND NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'get_custom_claims'
      AND pg_get_function_identity_arguments(p.oid) = 'p_user_id uuid'
  ),
  (SELECT string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'get_custom_claims');

DO $$
DECLARE
  v_failed int;
BEGIN
  SELECT count(*) INTO v_failed FROM rpc_contract_results WHERE NOT passed;

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'rpc_contract_alignment: % failed: %',
      v_failed,
      (SELECT string_agg(test_name || '=' || detail, '; ') FROM rpc_contract_results WHERE NOT passed);
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM rpc_contract_results ORDER BY test_name;
