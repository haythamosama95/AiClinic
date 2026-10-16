# Stage 11 leftover — Catalog SQL (`record_ai_acceptance`)

Green after runner iteration 2. In-scope IDs for this leftover track are
**S11-022 … S11-029** only (SQL against `public.record_ai_acceptance`).
Worker Stage 11 (S11-001…S11-021) already exists and was **not** edited.
`ai-platform/test/e2e/reports/stage-11.md` and `ai-platform/test/e2e/stage-11-*.test.ts`
were left untouched.

## 1. Chunk map

| File | IDs | Writer |
| --- | --- | --- |
| `backend/tests/catalog/stage-11-record-ai-acceptance.sql` | S11-022 … S11-029 | Writer A |

Leftover range is 8 IDs (< 15), so one writer.

## 2. Writer outcomes

**Writer A** — created `stage-11-record-ai-acceptance.sql` (S11-022…S11-029).
Uses `catalog_common_setup()` then real `update_branch` / `manage_create_branch` /
`create_patient` / `create_appointment` / `create_visit`. Catalog Crockford
examples (`7K2M-9XQD`, `8N3P-QWRA`, `9P4R-SXTC`, `ABCD-EFGH`) are used as-is.

Local `pg_temp.set_clinic_session` overlays `organization_id`,
`branch_ids`, `staff_member_id` after harness `set_authenticated_session`
(frozen harness injects `sub`+`role` only) so `jwt_organization_id()` and
`save_visit_documentation` (`visits.edit_soap` on doctor) work.
S11-026 deliberately uses the harness helper with no overlay.

[SEED] only S11-028: temp `public.test_domain_no_id` +
`ai_internal.acceptance_targets` row in the test transaction; file-level
`ROLLBACK` undoes it.

## 3. Iteration count

| Step | Result |
| --- | --- |
| Writer ×1 | File produced; all 8 IDs recorded |
| Runner 1 | Stage 02 + Stage 06 + Stage 08 + harness smoke PASS. `stage-11-record-ai-acceptance.sql` FAIL in journey setup (`ON_ERROR_STOP=1`) before any `pg_temp.record`. Second `create_visit` for the same doctor: `DOCTOR_ALREADY_IN_PROGRESS`. |
| Fixer ×1 | After opening V, `s11_release_in_progress` (Stage 08 pattern) so V2 can be created. S11-027 sends T0 − 1s because `now()` is transaction-stable and note `updated_at` would otherwise equal setup T0. Conflicts appended. Fixer self-run of this file only: 8/8 pass. |
| Runner 2 | Clean pass of the full catalog suite. Stage declared green from this report, not from the fixer self-report. |

Max iterations used: 1 of 3 fixer rounds (2 runner passes).

## 4. Counts (runner 2)

| Scope | Passed | Skipped | Failed | Missing |
| --- | ---: | ---: | ---: | ---: |
| Files (`run.sh`) | 8 | 0 | 0 | 0 |
| S11-022 … S11-029 | 8 | 0 | 0 | 0 |
| S02-001 … S02-027 | 27 | 0 | 0 | 0 |
| S06-001 … S06-047 | 47 | 0 | 0 | 0 |
| S08-061 … S08-069 | 9 | 0 | 0 | 0 |
| Harness smoke | 3 | 0 | 0 | 0 |

`run.sh` summary: `catalog SQL harness: 8 passed, 0 failed.`

Register 5 handling:

| # | Item | This track |
| --- | --- | --- |
| 12 | PostgREST HTTP shape | S11-028 asserted as SQLSTATE `P0001` (RAISE, not `rpc_error`). S11-029 wrapper-gate / registry as SQLSTATE `42501`. Not HTTP 400/401/403. |

Worker S11-001…021 are out of this leftover controller's scope (already
green on the Worker suite).

## 5. Conflicts + harness gaps

Conflicts (tests follow CODE): `backend/tests/catalog/reports/stage-11-conflicts.md`

| ID / area | Catalog claim | Code behavior |
| --- | --- | --- |
| S11-027 | Retry with original T0 after visit `updated_at` advanced | Stale check uses `visit_clinical_notes.updated_at`; `now()` is transaction-stable so setup T0 equals the post-022 note timestamp. Test sends T0 − 1s; still asserts `STALE_DOCUMENTATION` + domain message. |
| S11-028 stub | Zero-arg `test_domain_no_id()` | Dispatcher `v_nargs = 0` → `INTERNAL_ERROR`. Stub has `p_unused text DEFAULT NULL`; still returns `{}` with no id keys so the RAISE is reachable. |
| S11-028 HTTP | PostgREST HTTP 400 | Register 5 #12: SQLSTATE `P0001`, not HTTP. |
| S11-029 registry | Table-level SELECT deny | Schema `USAGE` revoked; observed 42501 is `permission denied for schema ai_internal`. Wrapper-gate still 42501 `permission denied for function …`. |

**Harness gaps**

- `pg_temp.set_authenticated_session` injects `sub` + `role` only.
  `jwt_organization_id()` / `jwt_branch_ids()` need `organization_id` /
  `branch_ids` / `staff_member_id`. Overlay lives in the stage file
  (`pg_temp.set_clinic_session`); harness was not modified.
- Postgres-owned TEMP tables are not writable as `authenticated`; writers
  `reset_postgres()` before stash/inspect.
- Frozen harness was not modified.

## 6. Remaining failures

None.

## 7. Files touched (this leftover)

Created:

- `backend/tests/catalog/stage-11-record-ai-acceptance.sql`
- `backend/tests/catalog/reports/stage-11-failures.md`
- `backend/tests/catalog/reports/stage-11-conflicts.md`
- `backend/tests/catalog/reports/stage-11.md` (this file)

Not modified: `harness.sql`, `run.sh`, `harness-smoke.sql`,
`backend/supabase/migrations/**`, `ai-platform/**` (including
`ai-platform/test/e2e/stage-11-*.test.ts` and
`ai-platform/test/e2e/reports/stage-11.md`), existing
`backend/tests/*.sql` (including `ai_acceptance_recording.sql`), Stage 02,
Stage 06, and Stage 08 catalog files.
