-- Owner role removal migration verification.
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/owner_role_migration.sql

BEGIN;

CREATE TEMP TABLE owner_role_migration_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_enum_labels text[];
BEGIN
  SELECT array_agg(e.enumlabel ORDER BY e.enumsortorder)
  INTO v_enum_labels
  FROM pg_enum e
  JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname = 'staff_role';

  INSERT INTO owner_role_migration_results VALUES (
    'staff_role_enum_has_no_owner',
    NOT ('owner' = ANY(v_enum_labels)),
    'labels=' || array_to_string(v_enum_labels, ',')
  );

  INSERT INTO owner_role_migration_results VALUES (
    'staff_role_enum_includes_administrator',
    'administrator' = ANY(v_enum_labels),
    'labels=' || array_to_string(v_enum_labels, ',')
  );

  INSERT INTO owner_role_migration_results VALUES (
    'roles_permissions_has_no_owner_rows',
    NOT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.role = 'owner'
        AND rp.is_deleted = false
    ),
    'owner permission rows must be removed'
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM owner_role_migration_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'owner_role_migration failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM owner_role_migration_results WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM owner_role_migration_results ORDER BY test_name;
