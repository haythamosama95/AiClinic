-- Fix 33: Ensure gender and marital_status are included in search_patients response.
-- These fields were already added as part of the search pagination fix
-- (20260524110100_fix_search_patients_pagination.sql). This migration serves as a
-- verification that the fields are present.

DO $$
DECLARE
  v_result public.rpc_result;
  v_src text;
BEGIN
  SELECT prosrc INTO v_src
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'auth_internal'
    AND p.proname = 'search_patients';

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'auth_internal.search_patients not found';
  END IF;

  IF v_src NOT LIKE '%gender%' OR v_src NOT LIKE '%marital_status%' THEN
    RAISE EXCEPTION 'search_patients is missing gender or marital_status fields — check migration order';
  END IF;
END;
$$;
