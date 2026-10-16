-- Stage 02 catalog SQL: S02-001, S02-002, S02-011 (availability flag dropped in P5.2).
-- Enroll / rotate / revoke RPC cases (S02-003 … S02-014) were removed when
-- installation_keys custody was dropped.

BEGIN;

\ir harness.sql

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
-- S02-001 — public.get_ai_availability is absent after P5.2 availability drop
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_public_absent boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();

  v_public_absent := to_regprocedure('public.get_ai_availability()') IS NULL;

  v_ok := v_public_absent;
  v_detail := 'public_get_ai_availability_absent=' || v_public_absent::text;

  PERFORM pg_temp.record(
    'S02-001 — public.get_ai_availability is absent after P5.2 availability drop',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-002 — auth_internal.get_ai_availability is absent after P5.2 availability drop
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_internal_absent boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();

  v_internal_absent := to_regprocedure('auth_internal.get_ai_availability()') IS NULL;

  v_ok := v_internal_absent;
  v_detail := 'auth_internal_get_ai_availability_absent=' || v_internal_absent::text;

  PERFORM pg_temp.record(
    'S02-002 — auth_internal.get_ai_availability is absent after P5.2 availability drop',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S02-011 — ai.availability setting row is absent after P5.2 availability drop
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_row_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();

  SELECT count(*)::int INTO v_row_count
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability';

  v_ok := v_row_count = 0;
  v_detail := 'ai_availability_row_count=' || v_row_count::text;

  PERFORM pg_temp.record(
    'S02-011 — ai.availability setting row is absent after P5.2 availability drop',
    v_ok,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
