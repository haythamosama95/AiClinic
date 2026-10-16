# Stage 11 failures (runner pass 2)

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-11-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## Counts

- Passing: 21
- Skipped: 0
- Failing: 0
- Test files: 2 passed (2)

Per-file:

- `test/e2e/stage-11-completed-failed-cancelled.test.ts` (11 tests) 13162ms — all passed
- `test/e2e/stage-11-replay-envelope-grace.test.ts` (10 tests) 14568ms — all passed

## Exact vitest summary

```
 Test Files  2 passed (2)
      Tests  21 passed (21)
   Start at  15:35:47
   Duration  16.77s (transform 492ms, setup 128ms, collect 1.54s, tests 27.73s, environment 0ms, prepare 380ms)
```

Per-file:

```
 ✓ test/e2e/stage-11-completed-failed-cancelled.test.ts (11 tests) 13162ms
 ✓ test/e2e/stage-11-replay-envelope-grace.test.ts (10 tests) 14568ms
```

## Failures

Zero failures.

Independent re-run of the full stage glob (`test/e2e/stage-11-*`, both files together) exited 0. Previously failing IDs from runner pass 1 (S11-008, S11-009, S11-010, S11-011, S11-016, S11-018) all passed in this run. No catalog classification needed.
