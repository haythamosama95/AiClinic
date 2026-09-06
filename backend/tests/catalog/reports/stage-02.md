# Stage 02 — Catalog SQL (clinic keypair / pgTAP)

Green after runner iteration 2. All 27 catalog IDs (S02-001 … S02-027) are in
scope for this track and have a recorded test. Worker HTTP tests were not
implemented; `ai-platform/test/e2e/reports/stage-02.md` was left untouched.

## 1. Chunk map

| File | IDs | Writer |
| --- | --- | --- |
| `backend/tests/catalog/stage-02-availability-and-enroll.sql` | S02-001 … S02-014 | Writer A |
| `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` | S02-015 … S02-027 | Writer B |

Writer B rebuilds S02-009…S02-014 end state via real enroll/rotate/revoke RPCs
(setup only; those IDs are recorded in Writer A's file).

## 2. Writer outcomes

**Writer A** — created `stage-02-availability-and-enroll.sql` (S02-001…S02-014).
After S02-007, ADMIN is reactivated via `set_staff_active(..., true)` as BOOT so
S02-012/S02-013 can use Nadia. S02-014 asserts payload `revoked_at` present/≈now
and exact equality on the stored row (catalog doc-drift #4).

**Writer B** — created `stage-02-revoke-rotate-availability.sql` (S02-015…S02-027).
S02-018/S02-022/S02-023/S02-025 use [SEED] only where the catalog says [SEED].
S02-024 simulates Stage 3 with `set_ai_availability(true, 'http://127.0.0.1:8787')`
as BOOT (no Worker call). S02-021 asserts trigger SQLSTATE `P0001`
(`SINGLE_INSTALLATION_VIOLATION`), not an `rpc_result` envelope.

## 3. Iteration count

| Step | Result |
| --- | --- |
| Writers (parallel) | Both files produced |
| Runner 1 | `stage-02-availability-and-enroll.sql` pass (14/14). `stage-02-revoke-rotate-availability.sql` aborted on S02-024 (`set_ai_availability` missing from local DB). S02-015…S02-023 had already recorded pass; S02-025…S02-027 missing. |
| Environment | Controller applied repo migration `20260905120100_set_ai_availability_rpc.sql` to `127.0.0.1:54322` (file not modified). Function now exists as `(boolean, text)`. |
| Fixer ×1 (Writer B file) | Explicit `::text` cast; missing-function caught as a recorded failure instead of abort; CODE-side assertions for `created_by` / newest-active-key. |
| Runner 2 | Clean pass. Stage declared green from this report, not from the fixer self-report. |

Max iterations used: 1 of 3.

## 4. Counts (runner 2)

| Scope | Passed | Skipped | Failed | Missing |
| --- | ---: | ---: | ---: | ---: |
| Files (`run.sh`) | 3 | 0 | 0 | 0 |
| S02-001 … S02-027 | 27 | 0 | 0 | 0 |
| Harness smoke | 3 | 0 | 0 | 0 |

`run.sh` summary: `catalog SQL harness: 3 passed, 0 failed.`

Register 5 #12 and #15 were **not** skipped: S02-002/S02-010 assert SQLSTATE
`42501`; enroll/rotate ran against local Supabase (pgsodium). Register 5 #12's
PostgREST HTTP mapping is out of band; SQL-level denial is what this track
asserts.

## 5. Conflicts + harness gaps

Conflicts (tests follow CODE): `backend/tests/catalog/reports/stage-02-conflicts.md`

| ID | Catalog claim | Code behavior |
| --- | --- | --- |
| S02-024 | upsert sets `created_by` and `updated_by` to BOOT | `ON CONFLICT` updates `updated_by` only; seed `created_by` stays NULL |
| S02-027 | Action SQL uses K0 (note: K2 after rotate) | After S02-023 the newest active key is the rotate-minted K3 |

**Harness gaps**

- `pg_temp.set_authenticated_session` injects only `sub` + `role`.
  `set_staff_active` needs `jwt_organization_id()`, so S02-007 overlays
  `organization_id` / `staff_member_id` after the helper (still a real RPC).
- Enroll/rotate require pgsodium (Register 5 #15) — local Supabase only.
- Local `schema_migrations` was behind the repo at runner 1 (`20260905120100`
  not applied). That is an environment gap, not a harness API gap.

## 6. Remaining failures

None.

## 7. Files touched (this stage)

Created:

- `backend/tests/catalog/stage-02-availability-and-enroll.sql`
- `backend/tests/catalog/stage-02-revoke-rotate-availability.sql`
- `backend/tests/catalog/reports/stage-02-failures.md`
- `backend/tests/catalog/reports/stage-02-conflicts.md`
- `backend/tests/catalog/reports/stage-02.md` (this file)

Not modified: `harness.sql`, `run.sh`, `harness-smoke.sql`,
`backend/supabase/migrations/**`, `ai-platform/**`, existing
`backend/tests/*.sql`.
