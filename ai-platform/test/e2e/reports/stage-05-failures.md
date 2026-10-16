# Stage 05 failure report

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-05-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-05-routing-policy.md`
Exit code: 0

## Counts

- Passing: 81
- Skipped: 4
- Failing: 0

**Zero failures.** 81 passed, 4 skipped, 0 failed (85 total).

Expected skips (Register 5 #26), all observed:

- S05-060 — `test/e2e/stage-05-rollback-serving.test.ts` (`it.skip`; frozen harness barrel does not export `createD1ConfigReader` / `selectCandidateChain`)
- S05-061 — `test/e2e/stage-05-rollback-serving.test.ts` (`it.skip`; `selectCandidateChain` not on frozen harness barrel)
- S05-078 — `test/e2e/stage-05-filters-kill-switch.test.ts` (`it.skip`; multi-language match clause; Register 5 #26 router-seam)
- S05-082 — `test/e2e/stage-05-filters-kill-switch.test.ts` (`it.skip`; non-hardwired cost sources; Register 5 #26 router-seam)

## Vitest summary

```
 Test Files  4 passed (4)
      Tests  81 passed | 4 skipped (85)
   Start at  12:24:23
   Duration  22.97s (transform 524ms, setup 237ms, collect 3.27s, tests 41.13s, environment 2ms, prepare 1.24s)
```

Per-file:

```
 ✓ test/e2e/stage-05-publish.test.ts (20 tests) 3066ms
 ✓ test/e2e/stage-05-canary-promote.test.ts (21 tests) 4228ms
 ✓ test/e2e/stage-05-rollback-serving.test.ts (21 tests | 2 skipped) 13791ms
 ✓ test/e2e/stage-05-filters-kill-switch.test.ts (23 tests | 2 skipped) 20043ms
```

## Failures

None. No assertion or exception failures. Skips listed above are expected and are not failures.
