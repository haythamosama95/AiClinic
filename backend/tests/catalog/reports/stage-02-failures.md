# Stage 02 catalog SQL — failure report

Branch: `ai/e2e-stage-02-clinic-keypair-pgtap`  
Command: `bash backend/tests/catalog/run.sh`  
Local DB: `127.0.0.1:54322` (user `postgres`)  
Runner iteration: 2 (after fixer pass on `stage-02-revoke-rotate-availability.sql`)

## Counts

| Scope | Passed | Skipped | Failed | Missing |
| --- | ---: | ---: | ---: | ---: |
| Files (`run.sh`) | 3 | 0 | 0 | 0 |
| S02-001 … S02-027 | 27 | 0 | 0 | 0 |
| Harness smoke (HARNESS-001 … 003) | 3 | 0 | 0 | 0 |

S02 passed: **S02-001 … S02-027** (27).  
S02 failed: **none**.  
S02 skipped: **0** (no skip path in these files).  
S02 missing: **0**.

`run.sh` summary: `catalog SQL harness: 3 passed, 0 failed.`

## File outcomes

| File | Outcome |
| --- | --- |
| `harness-smoke.sql` | **Passed** (3/3 recorded `t`; `fail_if_any` did not raise; ROLLBACK). |
| `stage-02-availability-and-enroll.sql` | **Passed** (14/14 recorded `t`; `fail_if_any` did not raise; ROLLBACK). |
| `stage-02-revoke-rotate-availability.sql` | **Passed** (13/13 recorded `t`; `fail_if_any` did not raise; ROLLBACK). No abort. |

## Failures

Zero failures. No `fail_if_any` RAISE. No `ON_ERROR_STOP` abort.

## Traceability (`pg_temp.record` ids)

Every recorded S02 id used the prefix `S02-NNN — `.

| ID | Result |
| --- | --- |
| S02-001 … S02-014 | pass (`stage-02-availability-and-enroll.sql`) |
| S02-015 … S02-027 | pass (`stage-02-revoke-rotate-availability.sql`) |
| HARNESS-001 … HARNESS-003 | pass (`harness-smoke.sql`) |
