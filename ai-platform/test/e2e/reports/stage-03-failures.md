# Stage 03 failure report

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-03-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-03-installation-enrollment.md`
Pass: runner pass 2 after fixers

## Counts

- Passing: 83
- Skipped: 0
- Failing: 0

The suite is clean: failing=0. No assertion failures or exceptions were recorded.

## Vitest summary

```
 Test Files  4 passed (4)
      Tests  83 passed (83)
   Start at  11:46:42
   Duration  7.95s (transform 536ms, setup 267ms, collect 3.34s, tests 15.38s, environment 0ms, prepare 911ms)
```

Per-file:

```
 ✓ test/e2e/stage-03-auth-routing.test.ts (20 tests) 3098ms
 ✓ test/e2e/stage-03-enroll-validation.test.ts (20 tests) 3126ms
 ✓ test/e2e/stage-03-lifecycle-rotate.test.ts (20 tests) 4001ms
 ✓ test/e2e/stage-03-revoke-delete-purge.test.ts (23 tests) 5151ms
```

## Failures

None. failing=0.

No scenario IDs failed. Catalog classification was not required.

## Skipped tests

None. skipped=0.

No unexpected skips. No skip titles cited a Register 5 reason because no tests were skipped. The four Stage 03 files contain no `it.skip` / `describe.skip` / `test.skip` / `.todo` entries.
