# Stage 00 failure report

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-00-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-00-platform-boot.md`

## Counts

- Passing: 30
- Skipped: 8
- Failing: 0

The suite is clean: failing=0. No assertion failures or exceptions were recorded.

## Vitest summary

```
 Test Files  2 passed (2)
      Tests  30 passed | 8 skipped (38)
   Start at  11:10:38
   Duration  7.07s (transform 463ms, setup 110ms, collect 1.50s, tests 9.50s, environment 0ms, prepare 404ms)
```

## Failures

None. failing=0.

## Skipped tests

Vitest reported `test/e2e/stage-00-auth-schema-cron-happy.test.ts (19 tests | 1 skipped)` and `test/e2e/stage-00-boot-bindings-routing.test.ts (19 tests | 7 skipped)` without printing skipped titles. The `it.skip` titles in those files are:

### `test/e2e/stage-00-boot-bindings-routing.test.ts`

- `S00-001 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test`
- `S00-002 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test`
- `S00-003 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test`
- `S00-007 throwing-load arm — The manifest is a static JSON import baked at build time; cannot become malformed in a running isolate`
- `S00-012 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate`
- `S00-013 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate`
- `S00-014 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate`

### `test/e2e/stage-00-auth-schema-cron-happy.test.ts`

- `S00-028 — The pool applies migrations once per test database; d1_migrations tracking is platform behavior, not worker code`

Skipped scenario IDs: S00-001, S00-002, S00-003, S00-007 (throwing-load arm only; the empty-registry-seam S00-007 test passed), S00-012, S00-013, S00-014, S00-028.
