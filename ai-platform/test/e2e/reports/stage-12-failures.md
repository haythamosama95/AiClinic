# Stage 12 failures

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-12-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-12-lookup-and-support.md`

## Counts

- Passing: 72
- Skipped: 0
- Failing: 0
- Test files: 4 passed (4)

Per-file:

- `test/e2e/stage-12-support-lookup.test.ts` (15 tests) 13637ms — all passed
- `test/e2e/stage-12-quota-inspect-dashboard.test.ts` (17 tests) 16648ms — all passed
- `test/e2e/stage-12-get-auth.test.ts` (22 tests) 25845ms — all passed
- `test/e2e/stage-12-get-lookup.test.ts` (18 tests) 26476ms — all passed

Zero failures. Passing 72, skipped 0, failing 0.

## Exact vitest summary

```
 Test Files  4 passed (4)
      Tests  72 passed (72)
   Start at  15:51:22
   Duration  29.30s (transform 569ms, setup 240ms, collect 3.42s, tests 82.61s, environment 0ms, prepare 1.06s)
```

Per-file:

```
 ✓ test/e2e/stage-12-support-lookup.test.ts (15 tests) 13637ms
 ✓ test/e2e/stage-12-quota-inspect-dashboard.test.ts (17 tests) 16648ms
 ✓ test/e2e/stage-12-get-auth.test.ts (22 tests) 25845ms
 ✓ test/e2e/stage-12-get-lookup.test.ts (18 tests) 26476ms
```

S12-060 (`verbose maps truncate at 500; counts stay 501`) passed in 10940ms.

## Failures

Zero failures. No assertion failures or exceptions were recorded. No catalog classification needed.
