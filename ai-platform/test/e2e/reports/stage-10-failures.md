# Stage 10 failure report

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-10-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-10-accept-route-invoke-stream.md`
Exit code: 0
Wall-clock: 41051 ms (process). S10-033 passed in 16854 ms.

Miniflare compatibility-date warnings (`requested "2026-05-03"`, falling back to `"2025-09-06"`) are not test failures. Two isolated worker runtimes started (one per test file).

**Zero failures.** 34 passed, 0 skipped, 0 failed (34 total). Both test files passed.

## 1. Counts

- Passing: 34
- Skipped: 0
- Failing: 0
- Total tests: 34

Test files: 2 (2 passed, 0 failed)

| File | Result |
| --- | --- |
| `test/e2e/stage-10-route-retry-idempotency.test.ts` | 17 passed, 0 failed (S10-001…S10-017) |
| `test/e2e/stage-10-prose-guard-stream.test.ts` | 17 passed, 0 failed (S10-018…S10-034) |

Failed IDs by file: none.

## 2. Vitest summary

Copied verbatim:

```
 Test Files  2 passed (2)
      Tests  34 passed (34)
   Start at  14:54:39
    Duration  40.42s (transform 471ms, setup 116ms, collect 1.54s, tests 62.16s, environment 1ms, prepare 391ms)
```

Per-file:

```
 ✓ test/e2e/stage-10-route-retry-idempotency.test.ts (17 tests) 24040ms
 ✓ test/e2e/stage-10-prose-guard-stream.test.ts (17 tests) 38123ms
```

## 3. Failures

None. Zero failures (34 passed, 0 skipped, 0 failed).

## 4. Skipped IDs

None.
