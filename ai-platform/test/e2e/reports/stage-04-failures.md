# Stage 04 failure report

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-04-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-04-entitlement-capability-grants.md`
Exit code: 0

## Counts

- Passing: 104
- Skipped: 0
- Failing: 0

Zero failures. The suite is clean: failing=0, skipped=0. No assertion failures or exceptions were recorded. Catalog classification was not required.

## Vitest summary

```
 Test Files  5 passed (5)
      Tests  104 passed (104)
   Start at  12:01:42
   Duration  7.48s (transform 600ms, setup 325ms, collect 4.07s, tests 19.56s, environment 0ms, prepare 1.54s)
```

Per-file:

```
 ✓ test/e2e/stage-04-deprecate-retire-auth.test.ts (19 tests) 3356ms
 ✓ test/e2e/stage-04-entitle-quota-grants-validation.test.ts (20 tests) 3467ms
 ✓ test/e2e/stage-04-entitle-auth-period.test.ts (20 tests) 4130ms
 ✓ test/e2e/stage-04-cohort-promote-deprecate.test.ts (20 tests) 4151ms
 ✓ test/e2e/stage-04-entitle-happy-cohort-activate.test.ts (25 tests) 4452ms
```

## Failures

None. failing=0.

No scenario IDs failed. No structured failure entries.

## Skipped tests

None. skipped=0.
