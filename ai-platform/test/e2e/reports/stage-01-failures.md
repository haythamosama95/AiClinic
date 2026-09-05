# Stage 01 failure report

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-01-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-01-token-contract.md`

## Counts

- Passing: 31
- Skipped: 0
- Failing: 0

The suite is clean: failing=0. No assertion failures or exceptions were recorded.

## Vitest summary

```
 Test Files  2 passed (2)
      Tests  31 passed (31)
   Start at  11:24:04
   Duration  7.84s (transform 427ms, setup 119ms, collect 1.44s, tests 9.43s, environment 0ms, prepare 372ms)
```

Per-file:

```
 ✓ test/e2e/stage-01-auth-validation.test.ts (16 tests) 3693ms
 ✓ test/e2e/stage-01-rotation-retire.test.ts (15 tests) 5735ms
```

## Failures

None. failing=0.

No scenario IDs failed. Catalog classification was not required.

## Coverage note

All catalog scenarios S01-001…S01-031 ran and passed:

- `test/e2e/stage-01-auth-validation.test.ts` — S01-001…S01-016 (16 passed)
- `test/e2e/stage-01-rotation-retire.test.ts` — S01-017…S01-031 (15 passed)
