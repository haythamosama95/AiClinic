# Stage 08 leftover — Catalog SQL (context provider RPC)

Green after runner iteration 2. In-scope IDs for this leftover track are
**S08-061 … S08-069** only (RPC against `public.get_visit_chief_complaint`).
Worker Stage 08 (S08-001…S08-060) already exists and was **not** edited.
`ai-platform/test/e2e/reports/stage-08.md` was left untouched.

Ingress POST halves of S08-061 / S08-062 / S08-067 are **not** implemented
here. Those journeys are already Worker **S08-049** (happy-path `accepted`)
and **S08-046** (`context_required`). The RPC IDs themselves are recorded
and passed; `detail` cites the Worker coverage. IDs were not dropped.

## 1. Chunk map

| File | IDs | Writer |
| --- | --- | --- |
| `backend/tests/catalog/stage-08-context-provider-rpc.sql` | S08-061 … S08-069 | Writer A |

Leftover range is 9 IDs (< 15), so one writer.

## 2. Writer outcomes

**Writer A** — created `stage-08-context-provider-rpc.sql` (S08-061…S08-069).
Uses `catalog_common_setup()` then real `create_patient` /
`create_appointment` / `create_visit` / `save_visit_documentation` /
`create_staff_account` / `manage_create_branch`. Catalog visit UUID
`5a1f9c2e-…` is treated as a documentation alias; tests look up real ids.

Local `pg_temp.set_clinic_session` overlays `organization_id`,
`branch_ids`, `staff_member_id` after harness `set_authenticated_session`
(frozen harness injects `sub`+`role` only) so `assert_visit_branch_scope`
and `staff_has_visit_clinical_access` work.

[SEED] only where no public RPC can create the state: pin `created_at` for
recorded_at (S08-061/063; `save_visit_documentation` stamps `now()`),
soft-deleted note, North-branch staff assignment, appointment
`status = completed` after each `create_visit`.
S08-063's NULL-complaint note is created via
`save_visit_documentation(visit, NULL, …)`, not a full-row INSERT.

S08-061/062/067 assert RPC outcomes only; `detail` notes Worker S08-049/046.
S08-069 asserts SQLSTATE `42501` (Register 5 #12), not PostgREST HTTP.

## 3. Iteration count

| Step | Result |
| --- | --- |
| Writer ×1 | File produced; all 9 IDs recorded |
| Runner 1 | Stage 02 + Stage 06 + harness smoke PASS. `stage-08-context-provider-rpc.sql` FAIL on S08-069 (`fail_if_any`). S08-061…068 passed. Anon got `42501` `permission denied for schema auth_internal`; assertion also required `ILIKE '%get_visit_chief_complaint%'`. |
| Fixer ×1 | Followed CODE: keep RAISE + SQLSTATE `42501` + no `rpc_result`; drop function-name ILIKE (S02-002 REVOKE-FROM-PUBLIC shape, which this RPC does not have). Conflict appended to `stage-08-conflicts.md`. |
| Runner 2 | Clean pass. Stage declared green from this report, not from the fixer self-report. |

Max iterations used: 1 of 3 fixer rounds (2 runner passes).

## 4. Counts (runner 2)

| Scope | Passed | Skipped | Failed | Missing |
| --- | ---: | ---: | ---: | ---: |
| Files (`run.sh`) | 7 | 0 | 0 | 0 |
| S08-061 … S08-069 | 9 | 0 | 0 | 0 |
| S02-001 … S02-027 | 27 | 0 | 0 | 0 |
| S06-001 … S06-047 | 47 | 0 | 0 | 0 |
| Harness smoke | 3 | 0 | 0 | 0 |

`run.sh` summary: `catalog SQL harness: 7 passed, 0 failed.`

Register 5 handling:

| # | Item | This track |
| --- | --- | --- |
| 12 | PostgREST HTTP shape | Asserted as SQLSTATE `42501` (S08-069), not HTTP 401/403 |
| 41 | Context-provider RPC vs workers pool | **This is that track** — all nine IDs run against local Supabase |

Worker S08-001…060 are out of this leftover controller's scope (already
green on the Worker suite).

## 5. Conflicts + harness gaps

Conflicts (tests follow CODE): `backend/tests/catalog/reports/stage-08-conflicts.md`

| ID / area | Catalog claim | Code behavior |
| --- | --- | --- |
| Visit UUID | Catalog uses `5a1f9c2e-…` | Documentation alias; tests use real `create_visit` ids |
| S08-061/062/067 | Also describe Worker ingress POST | RPC-only here; Worker S08-049 / S08-046 already cover POST |
| S08-069 | Function-level deny / PostgREST 401/403 | No `REVOKE FROM PUBLIC`; anon enters the invoker wrapper and hits `42501` `permission denied for schema auth_internal`. Register 5 #12: SQLSTATE, not HTTP. GRANT at `20260802120000_context_provider_chief_complaint.sql:65` |

**Harness gaps**

- `pg_temp.set_authenticated_session` injects `sub` + `role` only.
  `jwt_branch_ids()` / `current_staff_member_row()` need `branch_ids` /
  `organization_id` / `staff_member_id`. Overlay lives in the stage file
  (`pg_temp.set_clinic_session`); harness was not modified.
- Postgres-owned TEMP tables are not writable as `authenticated`; writers
  `reset_postgres()` before stash/inspect.
- Frozen harness was not modified.

## 6. Remaining failures

None.

## 7. Files touched (this leftover)

Created:

- `backend/tests/catalog/stage-08-context-provider-rpc.sql`
- `backend/tests/catalog/reports/stage-08-failures.md`
- `backend/tests/catalog/reports/stage-08-conflicts.md`
- `backend/tests/catalog/reports/stage-08.md` (this file)

Not modified: `harness.sql`, `run.sh`, `harness-smoke.sql`,
`backend/supabase/migrations/**`, `ai-platform/**` (including
`ai-platform/test/e2e/stage-08-*.test.ts` and
`ai-platform/test/e2e/reports/stage-08.md`), existing
`backend/tests/*.sql` (including `context_provider_rpc.sql`), Stage 02
and Stage 06 catalog files.
