# Stage 09 failure report (final runner pass — green gate)

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-09-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-09-the-guard.md`
Exit code: 0

**Zero failures.** This is the green-gate report.

Miniflare compatibility-date warnings (`requested "2026-05-03"`, falling back to `"2025-09-06"`) are not test failures. Four isolated worker runtimes started (one per test file).

## 1. Vitest summary

Copied verbatim:

```
 Test Files  4 passed (4)
      Tests  80 passed | 5 skipped (85)
   Start at  14:17:59
   Duration  26.29s (transform 533ms, setup 260ms, collect 3.30s, tests 88.60s, environment 1ms, prepare 985ms)
```

Per-file:

```
 ✓ test/e2e/stage-09-adapter-identity.test.ts (22 tests) 20535ms
 ✓ test/e2e/stage-09-entitlement-ratelimit.test.ts (21 tests) 21518ms
 ✓ test/e2e/stage-09-capability-context-preflight.test.ts (22 tests) 23067ms
 ✓ test/e2e/stage-09-admission-journal-compose.test.ts (20 tests | 5 skipped) 23479ms
```

No `FAIL` block. No `Failed Tests` section.

## 2. Counts

- Passing: 80
- Skipped: 5
- Failing: 0
- Total tests: 85

Test files: 4 (4 passed, 0 failed)

| File | Result |
| --- | --- |
| `test/e2e/stage-09-adapter-identity.test.ts` | 22 passed (S09-001…S09-022) |
| `test/e2e/stage-09-entitlement-ratelimit.test.ts` | 21 passed (S09-023…S09-043) |
| `test/e2e/stage-09-capability-context-preflight.test.ts` | 22 passed (S09-044…S09-065) |
| `test/e2e/stage-09-admission-journal-compose.test.ts` | 15 passed, 0 failed, 5 skipped (S09-066…S09-085) |

Failed IDs: none.

Pass-3 failure that did not reproduce as an assertion failure this run: S09-073 (`S09-073 — 16 in-flight then 17th is quota_exhausted` passed in 970ms). Catalog expected HTTP 429 `quota_exhausted` after 16 held in-flight POSTs; this run treated it as a passing `it(...)`.

## 3. Skipped IDs

Five `it.skip` names in `test/e2e/stage-09-admission-journal-compose.test.ts` (reasons from the skip titles):

- **S09-075** — DO outage admits under grace with degraded tier (Register 5 #28: in-pool env.DO frozen; wrapDurableObjectNamespace / installEnvOverrides do not reach SELF.fetch)
- **S09-076** — grace replay of pending row keeps queue count 1 (Register 5 #28: in-pool env.DO frozen; wrapDurableObjectNamespace / installEnvOverrides do not reach SELF.fetch)
- **S09-077** — sixth concurrent grace is rate_limited not quota_exhausted (Register 5 #28: in-pool env.DO frozen; wrapDurableObjectNamespace / installEnvOverrides do not reach SELF.fetch)
- **S09-079** — DO HTTP 400 bad_request is internal_error not grace (Register 5 #28: in-pool env.DO frozen; wrapDurableObjectNamespace / installEnvOverrides do not reach SELF.fetch)
- **S09-082** — journal INSERT failure releases reservation; retry same AAT (Register 5 #29: in-pool env.DB frozen; wrapD1 / prepare patch does not reach SELF.fetch)

These are Register 5 skips, not failures. Catalog scenarios S09-001 through S09-085 either passed or were these five skips.

## 4. Failures

**None.** Zero assertion failures and no uncaught test exceptions.

- Passing: 80
- Skipped: 5
- Failing: 0
- Total: 85

Verbatim vitest summary:

```
 Test Files  4 passed (4)
      Tests  80 passed | 5 skipped (85)
   Start at  14:17:59
   Duration  26.29s (transform 533ms, setup 260ms, collect 3.30s, tests 88.60s, environment 1ms, prepare 985ms)
```

## 5. Classification tally

| Cause | IDs |
| --- | --- |
| harness | (none this run) |
| test-logic | (none this run) |
| catalog-vs-code conflict | (none this run) |
