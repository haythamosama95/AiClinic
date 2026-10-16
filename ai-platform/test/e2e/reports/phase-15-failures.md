# Phase 15 full-suite failures

Command: `npx vitest run --config vitest.e2e.config.ts`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

Exit code: 0. Duration wall-clock ~62.3s (shell elapsed 62288ms). Stdout and stderr were captured from the vitest process (including `[mf:warn]` compatibility-date fallbacks, `[vpw:info]` isolated runtime startup, worker `stdout`/`stderr` on error-path scenarios, and `[vpw:debug] Shutting down runtimes...`). No tests were stopped early. One full-suite invocation; no per-file re-runs. Iteration 7 after the S10-002 and S12-059 fixers.

## Exact vitest summary

```
 Test Files  40 passed (40)
      Tests  710 passed | 21 skipped (731)
   Start at  17:34:36
   Duration  61.55s (transform 7.63s, setup 6.09s, collect 129.53s, tests 789.80s, environment 4ms, prepare 50.35s)
```

## Counts

- Passing: **710**
- Skipped: **21**
- Failing: **0**
- Test files: 40 passed (40)
- Total: 731

**ZERO failures.** 710 passed, 21 skipped, 0 failed (731 total). All 40 files passed.

## Per-file pass/fail/skip

Verbatim from the run:

```
 ✓ test/e2e/phase-00-exemplars.test.ts (3 tests) 2979ms
 ✓ test/e2e/stage-01-auth-validation.test.ts (16 tests) 7225ms
 ✓ test/e2e/stage-08-size-json-headers.test.ts (20 tests | 3 skipped) 7990ms
 ✓ test/e2e/stage-00-boot-bindings-routing.test.ts (19 tests | 7 skipped) 8161ms
 ✓ test/e2e/stage-05-publish.test.ts (20 tests) 8731ms
 ✓ test/e2e/stage-03-enroll-validation.test.ts (20 tests) 9215ms
 ✓ test/e2e/stage-03-auth-routing.test.ts (20 tests) 9327ms
 ✓ test/e2e/stage-04-deprecate-retire-auth.test.ts (19 tests) 10096ms
 ✓ test/e2e/stage-04-entitle-quota-grants-validation.test.ts (20 tests) 10420ms
 ✓ test/e2e/stage-01-rotation-retire.test.ts (15 tests) 10506ms
 ✓ test/e2e/stage-04-entitle-auth-period.test.ts (20 tests) 11212ms
 ✓ test/e2e/stage-04-cohort-promote-deprecate.test.ts (20 tests) 11919ms
 ✓ test/e2e/stage-03-lifecycle-rotate.test.ts (20 tests) 12139ms
 ✓ test/e2e/stage-08-trace-auth.test.ts (20 tests) 12642ms
 ✓ test/e2e/stage-05-canary-promote.test.ts (21 tests) 12647ms
 ✓ test/e2e/stage-00-auth-schema-cron-happy.test.ts (19 tests | 1 skipped) 12780ms
 ✓ test/e2e/stage-04-entitle-happy-cohort-activate.test.ts (25 tests) 13256ms
 ✓ test/e2e/stage-X-ledger-reconciliation-sweep.test.ts (16 tests) 16162ms
 ✓ test/e2e/stage-03-revoke-delete-purge.test.ts (23 tests) 16529ms
 ✓ test/e2e/stage-07-routing-identity.test.ts (18 tests) 18668ms
 ✓ test/e2e/stage-X-credit-inspect-do-rpc.test.ts (15 tests | 1 skipped) 19736ms
 ✓ test/e2e/stage-07-etag-cache.test.ts (15 tests) 21700ms
 ✓ test/e2e/stage-12-support-lookup.test.ts (15 tests) 22178ms
 ✓ test/e2e/stage-11-replay-envelope-grace.test.ts (10 tests) 22737ms
 ✓ test/e2e/stage-X-cron-flush-reconcile.test.ts (16 tests) 22925ms
 ✓ test/e2e/stage-07-entitlement-filters.test.ts (19 tests) 23665ms
 ✓ test/e2e/stage-X-grace-retention.test.ts (16 tests) 23841ms
 ✓ test/e2e/stage-05-rollback-serving.test.ts (21 tests | 2 skipped) 26197ms
 ✓ test/e2e/stage-11-completed-failed-cancelled.test.ts (11 tests) 26303ms
 ✓ test/e2e/stage-09-entitlement-ratelimit.test.ts (21 tests) 26711ms
 ✓ test/e2e/stage-09-adapter-identity.test.ts (22 tests) 26818ms
 ✓ test/e2e/stage-08-guard-sse-adapter.test.ts (20 tests) 27783ms
 ✓ test/e2e/stage-09-capability-context-preflight.test.ts (22 tests) 29449ms
 ✓ test/e2e/stage-12-get-auth.test.ts (22 tests) 31162ms
 ✓ test/e2e/stage-12-quota-inspect-dashboard.test.ts (17 tests) 31190ms
 ✓ test/e2e/stage-05-filters-kill-switch.test.ts (23 tests | 2 skipped) 31669ms
 ✓ test/e2e/stage-09-admission-journal-compose.test.ts (20 tests | 5 skipped) 32189ms
 ✓ test/e2e/stage-12-get-lookup.test.ts (18 tests) 35016ms
 ✓ test/e2e/stage-10-route-retry-idempotency.test.ts (17 tests) 36988ms
 ✓ test/e2e/stage-10-prose-guard-stream.test.ts (17 tests) 48936ms
```

| File | Pass | Fail | Skip |
|------|------|------|------|
| `test/e2e/phase-00-exemplars.test.ts` | 3 | 0 | 0 |
| `test/e2e/stage-01-auth-validation.test.ts` | 16 | 0 | 0 |
| `test/e2e/stage-08-size-json-headers.test.ts` | 17 | 0 | 3 |
| `test/e2e/stage-00-boot-bindings-routing.test.ts` | 12 | 0 | 7 |
| `test/e2e/stage-05-publish.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-03-enroll-validation.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-03-auth-routing.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-04-deprecate-retire-auth.test.ts` | 19 | 0 | 0 |
| `test/e2e/stage-04-entitle-quota-grants-validation.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-01-rotation-retire.test.ts` | 15 | 0 | 0 |
| `test/e2e/stage-04-entitle-auth-period.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-04-cohort-promote-deprecate.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-03-lifecycle-rotate.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-08-trace-auth.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-05-canary-promote.test.ts` | 21 | 0 | 0 |
| `test/e2e/stage-00-auth-schema-cron-happy.test.ts` | 18 | 0 | 1 |
| `test/e2e/stage-04-entitle-happy-cohort-activate.test.ts` | 25 | 0 | 0 |
| `test/e2e/stage-X-ledger-reconciliation-sweep.test.ts` | 16 | 0 | 0 |
| `test/e2e/stage-03-revoke-delete-purge.test.ts` | 23 | 0 | 0 |
| `test/e2e/stage-07-routing-identity.test.ts` | 18 | 0 | 0 |
| `test/e2e/stage-X-credit-inspect-do-rpc.test.ts` | 14 | 0 | 1 |
| `test/e2e/stage-07-etag-cache.test.ts` | 15 | 0 | 0 |
| `test/e2e/stage-12-support-lookup.test.ts` | 15 | 0 | 0 |
| `test/e2e/stage-11-replay-envelope-grace.test.ts` | 10 | 0 | 0 |
| `test/e2e/stage-X-cron-flush-reconcile.test.ts` | 16 | 0 | 0 |
| `test/e2e/stage-07-entitlement-filters.test.ts` | 19 | 0 | 0 |
| `test/e2e/stage-X-grace-retention.test.ts` | 16 | 0 | 0 |
| `test/e2e/stage-05-rollback-serving.test.ts` | 19 | 0 | 2 |
| `test/e2e/stage-11-completed-failed-cancelled.test.ts` | 11 | 0 | 0 |
| `test/e2e/stage-09-entitlement-ratelimit.test.ts` | 21 | 0 | 0 |
| `test/e2e/stage-09-adapter-identity.test.ts` | 22 | 0 | 0 |
| `test/e2e/stage-08-guard-sse-adapter.test.ts` | 20 | 0 | 0 |
| `test/e2e/stage-09-capability-context-preflight.test.ts` | 22 | 0 | 0 |
| `test/e2e/stage-12-get-auth.test.ts` | 22 | 0 | 0 |
| `test/e2e/stage-12-quota-inspect-dashboard.test.ts` | 17 | 0 | 0 |
| `test/e2e/stage-05-filters-kill-switch.test.ts` | 21 | 0 | 2 |
| `test/e2e/stage-09-admission-journal-compose.test.ts` | 15 | 0 | 5 |
| `test/e2e/stage-12-get-lookup.test.ts` | 18 | 0 | 0 |
| `test/e2e/stage-10-route-retry-idempotency.test.ts` | 17 | 0 | 0 |
| `test/e2e/stage-10-prose-guard-stream.test.ts` | 17 | 0 | 0 |

Iteration-6 failures that passed this run:

- `S10-002 — routing decision is persisted before provider I/O` — `test/e2e/stage-10-route-retry-idempotency.test.ts` (1897ms)
- `S12-059 — verbose=true includes maps; other verbose values omit them` — `test/e2e/stage-12-quota-inspect-dashboard.test.ts` (2526ms)

## Skipped tests

All 21 skips are `it.skip` with documented harness/catalog gaps. None flagged as unexpected. This run did not print vitest `↓` rows in the captured output; skip counts appear in the per-file summaries.

- `S00-001 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test`
  File: `test/e2e/stage-00-boot-bindings-routing.test.ts` (`it.skip`). Catalog non-automatable: pool always supplies DB/R2/DO.
- `S00-002 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test`
  File: `test/e2e/stage-00-boot-bindings-routing.test.ts` (`it.skip`). Same reason as S00-001.
- `S00-003 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test`
  File: `test/e2e/stage-00-boot-bindings-routing.test.ts` (`it.skip`). Same reason as S00-001.
- `S00-007 throwing-load arm — The manifest is a static JSON import baked at build time; cannot become malformed in a running isolate`
  File: `test/e2e/stage-00-boot-bindings-routing.test.ts` (`it.skip`). Catalog: throwing-`load()` arm is build-time; the runnable S00-007 uses the empty-registry seam.
- `S00-012 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate`
  File: `test/e2e/stage-00-boot-bindings-routing.test.ts` (`it.skip`). Catalog non-automatable: log verbosity.
- `S00-013 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate`
  File: `test/e2e/stage-00-boot-bindings-routing.test.ts` (`it.skip`). Same as S00-012.
- `S00-014 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate`
  File: `test/e2e/stage-00-boot-bindings-routing.test.ts` (`it.skip`). Same as S00-012.
- `S00-028 — The pool applies migrations once per test database; d1_migrations tracking is platform behavior, not worker code`
  File: `test/e2e/stage-00-auth-schema-cron-happy.test.ts` (`it.skip`). Catalog non-automatable.
- `S08-003 — Content-Length one byte over 1 MiB (Register 5 #37: workerd may strip Content-Length on constructed Request; no in-pool seam)`
  File: `test/e2e/stage-08-size-json-headers.test.ts` (`it.skip`).
- `S08-005 — Under-declared Content-Length smuggle (Register 5 #37: workerd may strip Content-Length on constructed Request; no in-pool seam)`
  File: `test/e2e/stage-08-size-json-headers.test.ts` (`it.skip`).
- `S08-009 — Non-numeric Content-Length (Register 5 #37: workerd may strip Content-Length on constructed Request; no in-pool seam)`
  File: `test/e2e/stage-08-size-json-headers.test.ts` (`it.skip`).
- `S05-060 — Register 5 #26: createD1ConfigReader/selectCandidateChain are not exported by the frozen harness barrel; README does not document calling them from tests`
  File: `test/e2e/stage-05-rollback-serving.test.ts` (`it.skip`).
- `S05-061 — Register 5 #26: selectCandidateChain is not exported by the frozen harness barrel; visit-summary Output.mode is prose so structured_output_required cannot be driven on POST /v1/requests`
  File: `test/e2e/stage-05-rollback-serving.test.ts` (`it.skip`).
- `S05-078 — Inputs the bundled manifest set cannot produce (multi-language match clause; Register 5 #26 router-seam; selectCandidateChain is not on the frozen harness barrel)`
  File: `test/e2e/stage-05-filters-kill-switch.test.ts` (`it.skip`).
- `S05-082 — Inputs the bundled manifest set cannot produce (non-hardwired cost sources; Register 5 #26 router-seam; selectCandidateChain is not on the frozen harness barrel)`
  File: `test/e2e/stage-05-filters-kill-switch.test.ts` (`it.skip`).
- `S09-075 — DO outage admits under grace with degraded tier (Register 5 #28: in-pool env.DO frozen; wrapDurableObjectNamespace / installEnvOverrides do not reach SELF.fetch)`
  File: `test/e2e/stage-09-admission-journal-compose.test.ts` (`it.skip`).
- `S09-076 — grace replay of pending row keeps queue count 1 (Register 5 #28: in-pool env.DO frozen; wrapDurableObjectNamespace / installEnvOverrides do not reach SELF.fetch)`
  File: `test/e2e/stage-09-admission-journal-compose.test.ts` (`it.skip`).
- `S09-077 — sixth concurrent grace is rate_limited not quota_exhausted (Register 5 #28: in-pool env.DO frozen; wrapDurableObjectNamespace / installEnvOverrides do not reach SELF.fetch)`
  File: `test/e2e/stage-09-admission-journal-compose.test.ts` (`it.skip`).
- `S09-079 — DO HTTP 400 bad_request is internal_error not grace (Register 5 #28: in-pool env.DO frozen; wrapDurableObjectNamespace / installEnvOverrides do not reach SELF.fetch)`
  File: `test/e2e/stage-09-admission-journal-compose.test.ts` (`it.skip`).
- `S09-082 — journal INSERT failure releases reservation; retry same AAT (Register 5 #29: in-pool env.DB frozen; wrapD1 / prepare patch does not reach SELF.fetch)`
  File: `test/e2e/stage-09-admission-journal-compose.test.ts` (`it.skip`).
- `SX-063 — Register 5 #45: in-pool GatewayObject cannot take injected storage; wrapDoStorage only reaches admissionRPC/creditRPC`
  File: `test/e2e/stage-X-credit-inspect-do-rpc.test.ts` (`it.skip`). Catalog SX-063 is a storage-fault seam that the in-pool GatewayObject cannot inject.

No other skips. No unexpected skips.

## Failures

None. Zero failing tests; no structured failure entries.
