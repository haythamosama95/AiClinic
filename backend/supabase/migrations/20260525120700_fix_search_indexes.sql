-- Fix 7: Fix indexes for search performance (trigram + functional).
-- Enables pg_trgm, drops unusable indexes, creates proper search indexes.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Drop the unusable indexes:
-- patients_branch_phone_idx has condition "phone IS NOT NULL" which is always true after
-- migration 20260523150000 made phone NOT NULL (dead condition).
DROP INDEX IF EXISTS public.patients_branch_phone_idx;

-- patients_branch_full_name_idx is a B-tree on (branch_id, full_name) which cannot
-- accelerate lower(full_name) LIKE '%...%' queries.
DROP INDEX IF EXISTS public.patients_branch_full_name_idx;

-- Trigram GIN index for case-insensitive name substring search.
CREATE INDEX patients_org_fullname_trgm_idx
  ON public.patients
  USING gin (lower(full_name) gin_trgm_ops)
  WHERE is_deleted = false;

-- Org-scoped phone index for phone-prefix searches (LIKE 'prefix%').
-- text_pattern_ops allows B-tree to satisfy prefix LIKE without full scan.
CREATE INDEX patients_org_phone_prefix_idx
  ON public.patients (organization_id, phone text_pattern_ops)
  WHERE is_deleted = false;

-- Branch-scoped phone index for branch-filtered phone queries.
CREATE INDEX patients_branch_phone_prefix_idx
  ON public.patients (branch_id, phone text_pattern_ops)
  WHERE is_deleted = false;
