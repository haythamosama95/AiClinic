-- E2E-P1.1-07 — staff membership backfill (FR-001, FR-002).
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/membership_active_org.sql

BEGIN;

CREATE TEMP TABLE membership_active_org_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

-- After migrations, every non-deleted staff member whose database has a
-- non-deleted organisation has exactly one ai_internal.membership row for the
-- earliest such organisation and that staff member's role. A non-deleted staff
-- member and no organisation — the bootstrap administrator from
-- 20260516100400_auth_rbac_seed.sql on a fresh database — has no membership row.
DO $$
DECLARE
  v_bootstrap_user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  v_has_org boolean;
  v_earliest_org_id uuid;
  v_mismatch_count int;
  v_expected_count int;
  v_actual_count int;
  v_bootstrap_staff_count int;
  v_bootstrap_membership_count int;
BEGIN
  -- Absence is an assertion failure. A static reference to the missing
  -- relation aborts the script before this test can record E2E-P1.1-07.
  IF to_regclass('ai_internal.membership') IS NULL THEN
    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-07',
      false,
      'ai_internal.membership is absent'
    );
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.organizations
    WHERE is_deleted = false
  )
  INTO v_has_org;

  IF v_has_org THEN
    SELECT o.id
    INTO v_earliest_org_id
    FROM public.organizations o
    WHERE o.is_deleted = false
    ORDER BY o.created_at
    LIMIT 1;

    WITH expected AS (
      SELECT
        sm.auth_user_id AS user_id,
        v_earliest_org_id AS organization_id,
        sm.role
      FROM public.staff_members sm
      WHERE sm.is_deleted = false
    ),
    actual AS (
      SELECT m.user_id, m.organization_id, m.role
      FROM ai_internal.membership m
      WHERE m.user_id IN (SELECT e.user_id FROM expected e)
    ),
    diff AS (
      SELECT user_id, organization_id, role FROM expected
      EXCEPT
      SELECT user_id, organization_id, role FROM actual
      UNION ALL
      SELECT user_id, organization_id, role FROM actual
      EXCEPT
      SELECT user_id, organization_id, role FROM expected
    )
    SELECT
      (SELECT count(*) FROM diff),
      (SELECT count(*) FROM expected),
      (SELECT count(*) FROM actual)
    INTO v_mismatch_count, v_expected_count, v_actual_count;

    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-07',
      v_mismatch_count = 0 AND v_actual_count = v_expected_count,
      'mismatched_staff=' || v_mismatch_count::text
        || ' expected=' || v_expected_count::text
        || ' actual=' || v_actual_count::text
        || ' earliest_org=' || COALESCE(v_earliest_org_id::text, '<null>')
    );
  ELSE
    SELECT count(*)
    INTO v_bootstrap_staff_count
    FROM public.staff_members sm
    WHERE sm.auth_user_id = v_bootstrap_user_id
      AND sm.is_deleted = false;

    SELECT count(*)
    INTO v_bootstrap_membership_count
    FROM ai_internal.membership m
    WHERE m.user_id = v_bootstrap_user_id;

    INSERT INTO membership_active_org_results (test_name, passed, detail)
    VALUES (
      'E2E-P1.1-07',
      v_bootstrap_staff_count = 1 AND v_bootstrap_membership_count = 0,
      'bootstrap_staff=' || v_bootstrap_staff_count::text
        || ' bootstrap_memberships=' || v_bootstrap_membership_count::text
    );
  END IF;
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures
  FROM membership_active_org_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'membership_active_org failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM membership_active_org_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail
FROM membership_active_org_results
ORDER BY test_name;
