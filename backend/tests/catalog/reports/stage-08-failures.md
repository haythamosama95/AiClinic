# Stage 08 catalog SQL — leftover context-provider RPC (iteration 2)

Branch: `ai/e2e-stage-08-context-provider-pgtap` (`9155499e`)  
Command: `bash backend/tests/catalog/run.sh` (from repo root)  
Local DB: `127.0.0.1:54322` (user `postgres`; password from `backend/local/.env` `POSTGRES_PASSWORD`)  
`psql -v ON_ERROR_STOP=1` per file. No test/harness/migration/Worker files were modified. No commit.

## Summary

`run.sh` summary line: **`catalog SQL harness: 7 passed, 0 failed.`**

Green: **yes** — zero failures. All seven files PASS, including `stage-08-context-provider-rpc.sql`. S08-069 is **not** a current failure.

Stage 02 still PASS? **yes** (both files; S02-001 … S02-027). Not a regression.  
Stage 06 still PASS? **yes** (all three files; S06-001 … S06-047). Not a regression.  
Harness smoke PASS? **yes** (HARNESS-001 … HARNESS-003).

## Counts per file

| File | Passed | Failed | Skipped | Outcome |
| --- | ---: | ---: | ---: | --- |
| `harness-smoke.sql` | 3 | 0 | 0 | **PASS** (HARNESS-001 … 003) |
| `stage-02-availability-and-enroll.sql` | 14 | 0 | 0 | **PASS** (S02-001 … S02-014). Regression: none. |
| `stage-02-revoke-rotate-availability.sql` | 13 | 0 | 0 | **PASS** (S02-015 … S02-027). Regression: none. |
| `stage-06-happy-path-and-lifecycle.sql` | 16 | 0 | 0 | **PASS** (S06-017 … S06-032). Regression: none. |
| `stage-06-issuer-guards.sql` | 16 | 0 | 0 | **PASS** (S06-001 … S06-016). Regression: none. |
| `stage-06-verify-and-handoff.sql` | 15 | 0 | 0 | **PASS** (S06-033 … S06-047). Regression: none. |
| `stage-08-context-provider-rpc.sql` | 9 | 0 | 0 | **PASS** (S08-061 … S08-069) |
| **Totals** | **86** | **0** | **0** | 7 files PASS, 0 files FAIL |

File run order: harness-smoke, Stage 02 files, Stage 06 files (happy-path, issuer-guards, verify-and-handoff), then `stage-08-context-provider-rpc.sql`.

## Stage 08 IDs (all passing)

S08-061, S08-062, S08-063, S08-064, S08-065, S08-066, S08-067, S08-068, S08-069 — all `passed=t`. `fail_if_any` did not raise; ROLLBACK.

S08-069 detail this run: `sqlstate=42501 msg=permission denied for schema auth_internal result_assigned=false; Register 5 #12 SQLSTATE 42501 (do not assert PostgREST HTTP 401/403)`.

No failing IDs. No file-level abort.
