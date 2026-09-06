-- Catalog SQL harness smoke. NOT a catalog scenario.
-- Proves helpers + Stage 02 common setup against local Supabase.
-- Run via backend/tests/catalog/run.sh (or psql -v ON_ERROR_STOP=1 -f this file).

BEGIN;

\ir harness.sql

SELECT pg_temp.catalog_common_setup();

DO $$
DECLARE
  v_ok boolean;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT EXISTS (
    SELECT 1
    FROM public.staff_members sm
    WHERE sm.id = 'b0000000-0000-4000-8000-000000000001'
      AND sm.auth_user_id = 'a0000000-0000-4000-8000-000000000001'
      AND sm.role = 'administrator'
      AND sm.is_bootstrap_admin = true
      AND sm.is_deleted = false
      AND sm.is_active = true
  ) INTO v_ok;
  PERFORM pg_temp.record(
    'HARNESS-001 — bootstrap admin exists',
    v_ok,
    CASE WHEN v_ok THEN 'ok' ELSE 'missing seeded bootstrap administrator' END
  );
END;
$$;

DO $$
DECLARE
  v_org uuid;
  v_branch uuid;
  v_admin uuid;
  v_doctor uuid;
  v_admin_auth uuid;
  v_doctor_auth uuid;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO v_admin FROM catalog_setup WHERE key = 'admin';
  SELECT value INTO v_doctor FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';

  v_ok := v_org IS NOT NULL
    AND v_branch IS NOT NULL
    AND v_admin IS NOT NULL
    AND v_doctor IS NOT NULL
    AND v_admin_auth IS NOT NULL
    AND v_doctor_auth IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.organizations o
      WHERE o.id = v_org AND o.name = 'Sunrise Dental Clinic' AND o.is_deleted = false
    )
    AND EXISTS (
      SELECT 1 FROM public.branches b
      WHERE b.id = v_branch AND b.name = 'Main Branch' AND b.is_deleted = false
    )
    AND EXISTS (
      SELECT 1 FROM public.staff_members sm
      WHERE sm.id = v_admin
        AND sm.auth_user_id = v_admin_auth
        AND sm.full_name = 'Nadia Karim'
        AND sm.role = 'administrator'
        AND sm.is_bootstrap_admin = false
    )
    AND EXISTS (
      SELECT 1 FROM public.staff_members sm
      WHERE sm.id = v_doctor
        AND sm.auth_user_id = v_doctor_auth
        AND sm.full_name = 'Omar Haddad'
        AND sm.role = 'doctor'
    );

  v_detail := 'org=' || COALESCE(v_org::text, '<null>')
    || ' branch=' || COALESCE(v_branch::text, '<null>')
    || ' admin=' || COALESCE(v_admin::text, '<null>')
    || ' doctor=' || COALESCE(v_doctor::text, '<null>');

  PERFORM pg_temp.record('HARNESS-002 — common setup stashes Sunrise ids', v_ok, v_detail);
END;
$$;

DO $$
DECLARE
  v_key_count int;
  v_issuance_count int;
  v_flag jsonb;
  v_ok boolean;
BEGIN
  PERFORM pg_temp.reset_keystore();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;
  SELECT count(*)::int INTO v_issuance_count FROM ai_internal.ai_token_issuance;
  SELECT s.value_json INTO v_flag
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability'
    AND s.is_deleted = false;

  v_ok := v_key_count = 0
    AND v_issuance_count = 0
    AND v_flag = '{"enrolled": false, "platform_base_url": null}'::jsonb;

  PERFORM pg_temp.record(
    'HARNESS-003 — empty keystore after reset',
    v_ok,
    'keys=' || v_key_count::text
      || ' issuance=' || v_issuance_count::text
      || ' flag=' || COALESCE(v_flag::text, '<null>')
  );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;

SELECT pg_temp.fail_if_any();

ROLLBACK;
