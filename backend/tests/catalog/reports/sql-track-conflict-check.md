# SQL-track conflict check (Phase 15 analog)

Branch: `ai/e2e-sql-track-conflict-check`  
HEAD = `ai/master` = `adbf1a9e` at start (working tree clean).  
This report is the only file added. No tests, Worker harness, Worker sources, catalog SQL, or old trust-suite files were modified. Failures were not “fixed” by editing tests.

**Final verdict: CONFLICT-FREE.**

Local Postgres at `127.0.0.1:54322` was accepting connections (`pg_isready`). This was not a “DB down” miss.

Two passes:

1. **First pass** recorded catalog SQL green, file-ownership CLEAN, trust-suite FK failure on leftover issuer-doctor rows, and Worker 702/21/8.
2. **Second pass** deleted leftover trust-suite fixture rows operationally (no test edits), then re-ran the trust suite and Worker E2E. Both went green. First-pass Worker failures did not reproduce.

## 1. Catalog SQL

Command: `bash /home/haytham/Desktop/AiClinic/backend/tests/catalog/run.sh`

```
catalog SQL harness: 8 passed, 0 failed.
```

Exit code: **0**.

| File | Result |
| --- | --- |
| `harness-smoke.sql` | PASS |
| `stage-02-availability-and-enroll.sql` | PASS |
| `stage-02-revoke-rotate-availability.sql` | PASS |
| `stage-06-happy-path-and-lifecycle.sql` | PASS |
| `stage-06-issuer-guards.sql` | PASS |
| `stage-06-verify-and-handoff.sql` | PASS |
| `stage-08-context-provider-rpc.sql` | PASS |
| `stage-11-record-ai-acceptance.sql` | PASS |

Catalog SQL stays green. Files `BEGIN`/`ROLLBACK` and do not use `c1000000` / `c2000000`. Not re-run in pass 2 (no catalog SQL edits).

## 2. Old AI-platform trust suite

Command: `bash /home/haytham/Desktop/AiClinic/backend/tests/run_ai_platform_trust_tests.sh`  
(existing runner; not invented)

### Pass 1 (FAIL)

| File | Result |
| --- | --- |
| `backend/tests/ai_keystore_rls.sql` | started (script continued) |
| `backend/tests/ai_token_issuer.sql` | **FAIL** — script stopped (`set -e`) |
| `backend/tests/ai_token_contract_rotation.sql` | not run |
| `backend/tests/context_provider_rpc.sql` | not run |
| `backend/tests/ai_acceptance_recording.sql` | not run |

Error (fixture setup, reported at end of the first `DO` block):

```
psql:backend/tests/ai_token_issuer.sql:162: ERROR:  update or delete on table "users" violates foreign key constraint "staff_members_auth_user_id_fkey" on table "staff_members"
DETAIL:  Key (id)=(c1000000-0000-4000-8000-000000000001) is still referenced from table "staff_members".
CONTEXT:  SQL statement "DELETE FROM auth.users WHERE id = v_doctor_user"
```

After the abort, committed leftover rows were still present:

- `staff_members` `c2000000-0000-4000-8000-000000000001` / `AI Issuer Doctor` → `auth.users` `c1000000-0000-4000-8000-000000000001`
- Seed bootstrap admin `b0000000-…` / `Clinic Administrator` (expected local seed)

Catalog SQL does **not** use those `c1000000` / `c2000000` UUIDs (ripgrep over `backend/tests/catalog/`). Catalog stage files have no `COMMIT` (each file `BEGIN` … `ROLLBACK`). The leftover doctor is the old trust suite’s own fixture name/IDs from a prior **committed** session, not a row the SQL track persisted.

`auth_internal.delete_clinic_test_fixtures(ARRAY[bootstrap_staff, doctor_staff])` **preserves** those staff ids (`p_preserve_staff_ids`), so a leftover `AI Issuer Doctor` row survives the helper and then `DELETE FROM auth.users` hits the FK. That is pre-existing fixture dirt plus the trust file’s cleanup order — not a catalog-SQL edit of `backend/tests/*.sql`.

### Pass 2 operational cleanup

As `postgres` on `127.0.0.1:54322`, targeted deletes only (bootstrap admin `a0000000-…` / `b0000000-…` left in place; no unrelated clinic truncate):

1. `staff_branch_assignments` for staff `c2000000-0000-4000-8000-000000000001` (1 row).
2. `staff_members` `c2000000-…` / `AI Issuer Doctor` (1 row).
3. `auth.users` `c1000000-…` / `ai-issuer-doctor` (1 row).
4. After issuer-doctor rows were gone, a first trust re-run reached enroll and failed with `ALREADY_ENROLLED`. One leftover committed `ai_internal.installation_keys` row (`kid=8301fb59-…`, `installation_id=80c28a07-…`, created 2026-09-05 by bootstrap admin, `revoked_at` NULL) was deleted. Catalog SQL rolls back enrollment; this row was prior-session dirt, not SQL-track persistence.

Post-cleanup: only bootstrap `Clinic Administrator` staff + `admin` auth user remained (plus unrelated `ai-rotation-doctor` auth user with no staff row).

### Pass 2 trust re-run (GREEN)

```
== AI platform trust suite: ai_keystore_rls.sql ==
== AI platform trust suite: ai_token_issuer.sql ==
== AI platform trust suite: ai_token_contract_rotation.sql ==
== AI platform trust suite: context_provider_rpc.sql ==
== AI platform trust suite: ai_acceptance_recording.sql ==
AI platform trust suite: all checks passed.
```

Exit code: **0**. Duration ~0.84s. No test files edited.

## 3. Worker E2E vs Phase 15 baseline

Command (from `ai-platform/`):

```
npx vitest run --config vitest.e2e.config.ts
```

SQL track did not touch Worker sources, harness, or e2e tests. Isolated re-run of first-pass failing files was **not** needed: the full suite matched baseline on pass 2.

| | Phase 15 baseline | Pass 1 | Pass 2 |
| --- | --- | --- | --- |
| Passing | **710** | 702 | **710** |
| Skipped | **21** | 21 | **21** |
| Failing | **0** | 8 | **0** |
| Test files | 40 passed (40) | 6 failed \| 34 passed (40) | **40 passed (40)** |
| Total | 731 | 731 | 731 |
| Duration | 61.55s | 85.74s | 65.63s |
| Exit | 0 | 1 | **0** |

### Pass 1 failures (did not reproduce on pass 2)

Exact vitest summary (pass 1):

```
 Test Files  6 failed | 34 passed (40)
      Tests  8 failed | 702 passed | 21 skipped (731)
   Start at  19:19:54
   Duration  85.74s (transform 5.82s, setup 4.70s, collect 131.69s, tests 1647.82s, environment 7ms, prepare 45.37s)
```

| ID | File | Error |
| --- | --- | --- |
| S05-050 | `stage-05-rollback-serving.test.ts` | `Network connection lost.` (`WorkersTestRunner.updateStackedStorage`) |
| S05-051 | `stage-05-rollback-serving.test.ts` | `timed out waiting for ai_request 3VKV-X810 (state=Failed, routing_decision=null)` |
| S10-004 | `stage-10-route-retry-idempotency.test.ts` | `Network connection lost.` |
| S10-020 | `stage-10-prose-guard-stream.test.ts` | `expected [] to have a length of 1 but got +0` (`getAttempts`) |
| S11-001 | `stage-11-completed-failed-cancelled.test.ts` | `payload_pointer` expected `request/<id>/envelope`, received `null` |
| S11-005 | `stage-11-completed-failed-cancelled.test.ts` | `expected 'Accepted' to be 'Failed'` |
| SX-001 | `stage-X-cron-flush-reconcile.test.ts` | `Network connection lost.` |
| SX-024 | `stage-X-grace-retention.test.ts` | `expected 'Failed' to be 'Completed'` |

Three of eight were vitest-pool-workers / Miniflare `Network connection lost` during stacked-storage teardown. The others were settlement / routing races (`payload_pointer` null, `Accepted` vs terminal, empty `attempts`). SQL track cannot cause those (no Worker edits).

### Pass 2 full suite (GREEN)

Exact vitest summary (pass 2):

```
 Test Files  40 passed (40)
      Tests  710 passed | 21 skipped (731)
   Start at  19:26:37
   Duration  65.63s (transform 7.62s, setup 6.42s, collect 111.48s, tests 841.16s, environment 5ms, prepare 39.04s)
```

Matches Phase 15 baseline **710 / 21 / 0**. Worker tests were **not** edited. First-pass failures classified as pool / settlement flakes, not a SQL-track conflict.

## 4. File-ownership proof

SQL-track commits (`git log --oneline -- backend/tests/catalog/`):

| Commit | Subject | Paths |
| --- | --- | --- |
| `06033dd7` | catalog SQL harness | `backend/tests/catalog/` only (README, harness, smoke, `run.sh`, `reports/phase-00-sql-harness.md`) |
| `1a9a4564` | Stage 02 catalog SQL | `backend/tests/catalog/` only (`stage-02-*.sql` + reports) |
| `c8414f01` | Stage 06 catalog SQL | `backend/tests/catalog/` only (`stage-06-*.sql` + reports) |
| `9a51472b` | Stage 08 catalog SQL | `backend/tests/catalog/` only (`stage-08-*.sql` + reports) |
| `cbdd9914` | Stage 11 catalog SQL | `backend/tests/catalog/` only (`stage-11-*.sql` + reports) |

Per-commit scan of those five hashes against `ai-platform/test/e2e/**` and `ai-platform/src/**`: **no hits**.

`git log --oneline --name-status 06033dd7^..cbdd9914 -- ai-platform/test/e2e/ ai-platform/src/ ai-platform/vitest.e2e.config.ts backend/tests/*.sql backend/tests/run_ai_platform_trust_tests.sh` is **empty**.

Confirmations:

- No `ai-platform/test/e2e/stage-02-*.test.ts` or `stage-06-*.test.ts` exist.
- `ai-platform/test/e2e/harness/` last commit: `155a840a` (Phase 0 harness, 2026-09-05) — not a catalog commit.
- `vitest.e2e.config.ts` last commit: same `155a840a`.
- Existing `stage-*.test.ts` files were not in any catalog commit.
- Worker historical reports still declare deferred:
  - `ai-platform/test/e2e/reports/stage-02.md` — **Declaration: GREEN (deferred)** (`aadab6e5`)
  - `ai-platform/test/e2e/reports/stage-06.md` — **Declaration: GREEN (deferred)** (`525bad27`)
- New Stage 02/06/08/11 reports live under `backend/tests/catalog/reports/` (this file included).

Starting `git diff ai/master` was empty. After this report, the only added path is `backend/tests/catalog/reports/sql-track-conflict-check.md`.

## 5. Verdict

**CONFLICT-FREE** — catalog SQL green, file ownership CLEAN, trust suite green after leftover-fixture cleanup, Worker E2E matches 710/21/0.

| Gate | Pass 1 | Pass 2 (final) |
| --- | --- | --- |
| Catalog SQL | GREEN (8 passed, 0 failed) | GREEN (unchanged; not re-run) |
| File ownership (SQL track vs Worker / old trust files) | CLEAN | CLEAN |
| Worker historical deferred reports | Unchanged (GREEN deferred) | Unchanged |
| Old trust suite | FAIL (leftover `AI Issuer Doctor` FK) | **GREEN** (all five files passed after targeted fixture deletes) |
| Worker E2E vs 710/21/0 | FAIL (702 passed, 21 skipped, 8 failed) | **GREEN** (710 passed, 21 skipped, 0 failed) |

First-pass trust failure was leftover committed issuer-doctor / installation-key fixture dirt, not a catalog SQL code conflict. First-pass Worker failures were Miniflare pool / settlement flakes; they did not reproduce on a full re-run. No tests were weakened or edited to go green.
