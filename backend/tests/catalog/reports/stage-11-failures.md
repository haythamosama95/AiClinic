# Stage 11 catalog SQL — leftover failure report (iteration 2)

Branch: `ai/e2e-stage-11-acceptance-pgtap` (`f61c8cc0` + untracked `stage-11-record-ai-acceptance.sql`)  
Command: `bash backend/tests/catalog/run.sh` (from repo root)  
Local DB: `127.0.0.1:54322` (user `postgres`; password from `backend/local/.env` `POSTGRES_PASSWORD`)  
`psql -v ON_ERROR_STOP=1` per file. No test/harness/migration/Worker files were modified. No commit. Worker vitest was not started.

Green is declared from this runner report only (not from the fixer).

## 1. Overall summary (`run.sh` per-file PASS/FAIL)

`run.sh` summary line: **`catalog SQL harness: 8 passed, 0 failed.`** Exit code **0**.

| File | Outcome |
| --- | --- |
| `harness-smoke.sql` | **PASS** |
| `stage-02-availability-and-enroll.sql` | **PASS** |
| `stage-02-revoke-rotate-availability.sql` | **PASS** |
| `stage-06-happy-path-and-lifecycle.sql` | **PASS** |
| `stage-06-issuer-guards.sql` | **PASS** |
| `stage-06-verify-and-handoff.sql` | **PASS** |
| `stage-08-context-provider-rpc.sql` | **PASS** |
| `stage-11-record-ai-acceptance.sql` | **PASS** |

Stage 02 still PASS? **yes** (both files; S02-001 … S02-027). Not a regression.  
Stage 06 still PASS? **yes** (all three files; S06-001 … S06-047). Not a regression.  
Stage 08 still PASS? **yes** (`stage-08-context-provider-rpc.sql`; S08-061 … S08-069). Not a regression.  
Harness smoke PASS? **yes** (HARNESS-001 … HARNESS-003).

Green: **yes** — zero failures. Every catalog SQL file PASS, including Stage 11.

## 2. Passing / skipped / failing counts (`catalog_results`)

Every file completed `SELECT test_name, passed, detail FROM catalog_results`. All recorded `passed=t`. No skip rows. No `passed=f` rows. `fail_if_any` did not raise on any file. Each file ended with `ROLLBACK`.

| File | Passed | Failed | Skipped | Outcome |
| --- | ---: | ---: | ---: | --- |
| `harness-smoke.sql` | 3 | 0 | 0 | **PASS** (HARNESS-001 … 003) |
| `stage-02-availability-and-enroll.sql` | 14 | 0 | 0 | **PASS** (S02-001 … S02-014) |
| `stage-02-revoke-rotate-availability.sql` | 13 | 0 | 0 | **PASS** (S02-015 … S02-027) |
| `stage-06-happy-path-and-lifecycle.sql` | 16 | 0 | 0 | **PASS** (S06-017 … S06-032; `fail_if_any` did not raise; ROLLBACK) |
| `stage-06-issuer-guards.sql` | 16 | 0 | 0 | **PASS** (S06-001 … S06-016) |
| `stage-06-verify-and-handoff.sql` | 15 | 0 | 0 | **PASS** (S06-033 … S06-047) |
| `stage-08-context-provider-rpc.sql` | 9 | 0 | 0 | **PASS** (S08-061 … S08-069) |
| `stage-11-record-ai-acceptance.sql` | 8 | 0 | 0 | **PASS** (S11-022 … S11-029) |
| **Totals** | **94** | **0** | **0** | 8 files PASS, 0 files FAIL |

## 3. Failures

Zero failures. No per-ID `fail_if_any` entries. No file-level abort.

### Stage 11 per-ID pass list (`catalog_results`, all `passed=t`)

- **S11-022** — record_ai_acceptance happy path writes acceptance, audit log, and merged rpc_success
- **S11-023** — record_ai_acceptance rejects malformed request references
- **S11-024** — record_ai_acceptance rejects unregistered acceptance targets
- **S11-025** — record_ai_acceptance rejects duplicate acceptance before any domain write
- **S11-026** — record_ai_acceptance requires organization context
- **S11-027** — record_ai_acceptance passes through delegated domain failures unchanged
- **S11-028** — record_ai_acceptance rolls back everything when the domain write returns no record id
- **S11-029** — record_ai_acceptance wrapper gate and ai_accepted_output RLS visibility
