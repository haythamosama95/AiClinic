# Stage 11 catalog-vs-code conflicts

Catalog remains the journey spec. CODE (migrations) is authoritative for
assertions in `backend/tests/catalog/stage-11-record-ai-acceptance.sql`.
Tests follow CODE.

## S11-027

- **Catalog claim:** After S11-022, visit V's `updated_at` has advanced to T1; the client retries `record_ai_acceptance` with the original T0 and gets `STALE_DOCUMENTATION`.
- **Code behavior:** When a clinical note exists, `save_visit_documentation` compares `p_expected_updated_at` to **`visit_clinical_notes.updated_at`**, not `visits.updated_at`. `trg_visit_clinical_notes_set_updated_at` stamps `now()` on every UPDATE, and `now()` is stable for the catalog SQL transaction, so setup T0 equals the S11-022 note timestamp and is not stale. The test sends T0 − 1 second so `IS DISTINCT FROM` fires, and still asserts the domain `STALE_DOCUMENTATION` code and message.
- **File:line:** `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql:382-388` (note vs visit timestamp); `backend/supabase/migrations/20260516100100_auth_rbac_audit_triggers.sql:23-32` (`set_updated_at` uses `now()`); `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql:178` (trigger attached). Test: `backend/tests/catalog/stage-11-record-ai-acceptance.sql` (S11-027 `v_stale`).

## S11-028

- **Catalog claim:** [SEED] `public.test_domain_no_id()` with **zero arguments**, returning `rpc_success('{}')` with no id key, so `record_ai_acceptance` raises `Domain write did not return a record id.`
- **Code behavior:** `invoke_acceptance_domain_rpc` returns `rpc_error('INTERNAL_ERROR', 'Domain function is not configured.')` when `v_nargs = 0`, so a no-arg stub never reaches the RAISE. The test stub takes one named argument (`p_unused text DEFAULT NULL`) and still returns `rpc_success('{}'::jsonb)` with no `record_id`/`visit_id`/`id` key.
- **File:line:** `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:114-117`; restated at `backend/supabase/migrations/20260805150000_f2_review_resolution.sql:60-63`. RAISE at `20260802150000_ai_acceptance_recording.sql:214-217`.

- **Catalog claim:** Side effects mention PostgREST HTTP 400 for the exception path.
- **Code behavior:** The migration `RAISE EXCEPTION` surfaces as SQLSTATE `P0001`. Register 5 #12 requires SQLSTATE here, not HTTP. Non-automatable note 6 in the catalog already defers the PostgREST status/body mapping.
- **File:line:** `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:214-217` (`RAISE EXCEPTION`); `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:227-228` (propagation comment).

## S11-029

- **Catalog claim:** `ai_internal.acceptance_targets` is unreadable by authenticated (`SELECT` granted to postgres only) — a table-level deny after schema USAGE. Wrapper-gate failures are `permission denied for function …`.
- **Code behavior:** `REVOKE ALL ON SCHEMA ai_internal FROM authenticated` (and PUBLIC/anon/service_role). Observed 42501 is `permission denied for schema ai_internal` (S02-010 class), not a table-level deny. Wrapper-gate calls still fail with 42501 `permission denied for function record_ai_acceptance` / `invoke_acceptance_domain_rpc`.
- **File:line:** `backend/supabase/migrations/20260803140000_b1_review_resolution.sql:7-8` (schema revoke); `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:11-13` (table grants); `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:294-297` (function revokes).
