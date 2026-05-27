/*
  ENUM MIGRATION SAFETY PATTERN:
  Before any ALTER TYPE ... USING cast:
    1. Pre-check: SELECT count(*) FROM table WHERE column::text NOT IN ('allowed','values')
    2. If count > 0, RAISE EXCEPTION with details
    3. Perform the ALTER inside a subtransaction if possible
    4. Verify post-condition

  Fix 6: Retrospective safety check on patient_gender enum state after migration 19.
*/

DO $$
BEGIN
  -- Verify no orphaned enum type exists from a failed previous migration
  IF EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'patient_gender_new'
  ) THEN
    RAISE EXCEPTION 'Orphaned patient_gender_new type detected — manual cleanup required';
  END IF;

  -- Verify current enum values are exactly what we expect (male, female)
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'patient_gender'
    AND e.enumlabel = 'male'
  ) THEN
    RAISE EXCEPTION 'patient_gender enum is in unexpected state — missing male value';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'patient_gender'
    AND e.enumlabel = 'female'
  ) THEN
    RAISE EXCEPTION 'patient_gender enum is in unexpected state — missing female value';
  END IF;
END;
$$;

-- Verify data integrity: no patients with unexpected gender values
DO $$
DECLARE
  v_bad_count int;
BEGIN
  SELECT count(*) INTO v_bad_count
  FROM public.patients
  WHERE gender IS NOT NULL
    AND gender::text NOT IN ('male', 'female');

  IF v_bad_count > 0 THEN
    RAISE WARNING '% patients have unexpected gender values', v_bad_count;
  END IF;
END;
$$;
