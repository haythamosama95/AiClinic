# Stage 07 failure report (iteration 3)

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-07-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-07-discovery.md`
Exit code: 0

Stdout and stderr were captured together from the vitest process (no separate stderr channel). stderr also contained Miniflare compatibility-date warnings (`requested "2026-05-03"`, falling back to `"2025-09-06"`). Those warnings are not test failures.

## Counts

- Passing: 52
- Skipped: 0
- Failing: 0

**Zero failures.** 52 passed, 0 skipped, 0 failed (52 total).

Test files: 3 (3 passed, 0 failed)

| File | Result |
| --- | --- |
| `test/e2e/stage-07-routing-identity.test.ts` | 18 passed (S07-001…S07-018) |
| `test/e2e/stage-07-entitlement-filters.test.ts` | 19 passed (S07-019…S07-037) |
| `test/e2e/stage-07-etag-cache.test.ts` | 15 passed (S07-038…S07-052), including S07-051 |

## Vitest summary

```
 Test Files  3 passed (3)
      Tests  52 passed (52)
   Start at  12:48:47
   Duration  25.48s (transform 480ms, setup 203ms, collect 2.43s, tests 59.22s, environment 0ms, prepare 770ms)
```

Per-file:

```
 ✓ test/e2e/stage-07-routing-identity.test.ts (18 tests) 17839ms
 ✓ test/e2e/stage-07-etag-cache.test.ts (15 tests) 18728ms
 ✓ test/e2e/stage-07-entitlement-filters.test.ts (19 tests) 22657ms
```

S07-051 compact line (previously failing in iteration 2):

```
   ✓ Stage 07 — discovery ETag, cache, lifecycle overlay (S07-038…S07-052) > S07-051 — Revoked grant stays listed while isolate cache is warm  1113ms
```

## Failures

None. Catalog `docs/testing/catalog/stage-07-discovery.md` scenarios S07-001 through S07-052 all passed. The iteration-2 failure (S07-051 — post-revoke GET returning `manifests: []` because isolate TTL expired) did not reproduce; `isolateConfigCache.setTtlMs(30_000)` kept the warmed grant listed until `cache.clear()`.
