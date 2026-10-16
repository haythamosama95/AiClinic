# Stage X failures

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-X-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-X-cron-and-failure-journeys.md`

Exit code: 0. Duration wall-clock ~14.7s. Stdout and stderr were captured from the vitest process (including `[mf:warn]` compatibility-date fallbacks and expected worker `stderr` on error-path scenarios SX-019, SX-020, SX-058, SX-059). No tests were stopped early.

## Exact vitest summary

```
 Test Files  4 passed (4)
      Tests  62 passed | 1 skipped (63)
   Start at  16:32:17
   Duration  13.98s (transform 716ms, setup 303ms, collect 3.66s, tests 38.60s, environment 0ms, prepare 1.06s)
```

## Counts

- Passing: **62**
- Skipped: **1**
- Failing: **0**
- Test files: 4 passed (4)
- Total: 63

**ZERO failures.** 62 passed, 1 skipped, 0 failed (63 total). All four Stage X files passed.

## Per-file pass/fail/skip

Verbatim from the run:

```
 ✓ test/e2e/stage-X-ledger-reconciliation-sweep.test.ts (16 tests) 6752ms
 ✓ test/e2e/stage-X-credit-inspect-do-rpc.test.ts (15 tests | 1 skipped) 9877ms
 ✓ test/e2e/stage-X-cron-flush-reconcile.test.ts (16 tests) 10935ms
 ✓ test/e2e/stage-X-grace-retention.test.ts (16 tests) 11040ms
```

| File | Pass | Fail | Skip |
|------|------|------|------|
| `test/e2e/stage-X-ledger-reconciliation-sweep.test.ts` | 16 | 0 | 0 |
| `test/e2e/stage-X-credit-inspect-do-rpc.test.ts` | 14 | 0 | 1 |
| `test/e2e/stage-X-cron-flush-reconcile.test.ts` | 16 | 0 | 0 |
| `test/e2e/stage-X-grace-retention.test.ts` | 16 | 0 | 0 |

## Skipped tests

Expected skip (present; not flagged as unexpected):

- `SX-063 — Register 5 #45: in-pool GatewayObject cannot take injected storage; wrapDoStorage only reaches admissionRPC/creditRPC`
  File: `test/e2e/stage-X-credit-inspect-do-rpc.test.ts` (`it.skip`). Catalog SX-063 is a storage-fault seam that the in-pool GatewayObject cannot inject.

No other skips. No unexpected skips.

## Failures

None. Zero failing tests; no structured failure entries.
