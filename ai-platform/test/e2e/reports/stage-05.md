# Stage 05 — Routing policy E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  4 passed (4)
      Tests  81 passed | 4 skipped (85)
   Start at  12:24:23
   Duration  22.97s (transform 524ms, setup 237ms, collect 3.27s, tests 41.13s, environment 2ms, prepare 1.24s)
```

- Passing: **81**
- Skipped: **4** (Register 5 #26 router-seam only: S05-060, S05-061, S05-078, S05-082; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-05-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-05-publish.test.ts` | S05-001 … S05-020 | Writer 1 |
| `ai-platform/test/e2e/stage-05-canary-promote.test.ts` | S05-021 … S05-041 | Writer 2 |
| `ai-platform/test/e2e/stage-05-rollback-serving.test.ts` | S05-042 … S05-062 | Writer 3 |
| `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts` | S05-063 … S05-085 | Writer 4 |

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-05-publish.test.ts`

Implemented (real `it`): S05-001 … S05-020 (20).

Skipped: **none**.

- S05-016 uses `dispatchControlRequest` with `{ DB: env.DB }` only (Register 5 #2; same as S03-083). `dispatchControl` / `controlBindingsFromEnv` backfill pool R2.
- S05-020 uses documented `wrapD1({ batchUniqueThrow })` + `dispatchControl` (Register 5 #10 UNIQUE seam), not a `SELF.fetch` race.

### 2.2 Writer 2 — `stage-05-canary-promote.test.ts`

Implemented (real `it`): S05-021 … S05-041 (21).

Skipped: **none**.

`canaryPolicy` has no `cohort_name` argument. S05-023 uses `controlFetch` (`// HARNESS-GAP`).

### 2.3 Writer 3 — `stage-05-rollback-serving.test.ts`

Implemented (real `it`): S05-042 … S05-059, S05-062 (19).

Skipped (`it.skip`, Register 5 #26): S05-060, S05-061 — `createD1ConfigReader` / `selectCandidateChain` are not on the frozen barrel / README.

`[SEED]` only on S05-052 (malformed canary JSON), S05-053/054 (R2 delete), S05-055 (R2 identity overwrite). S05-059 uses pool TTL `"100"` plus raw `controlFetch` rollback and `clearConfigCache()` (not TTL `"0"`).

### 2.4 Writer 4 — `stage-05-filters-kill-switch.test.ts`

Implemented (real `it`): S05-063 … S05-077, S05-079 … S05-081, S05-083 … S05-085 (21).

Skipped (`it.skip`, Register 5 #26): S05-078, S05-082.

S05-069 / S05-070 follow code: `POST /control/kill-switches/arm` then `clearConfigCache()` (Register 5 #27 is stale; Phase 0 + README expose arm/disarm).

## 3. Iteration count

**1 runner→fixer iteration** (2 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 51 passed, 4 skipped, **30 failed** | 2 fixers (`rollback-serving`, `filters-kill-switch`) |
| Runner 2 | **81 passed, 4 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 2)

| | Count |
|---|---|
| Passing | 81 |
| Skipped | 4 |
| Failing | 0 |
| Test files | 4 passed |

Skipped IDs (expected Register 5 #26): S05-060, S05-061, S05-078, S05-082.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-05-conflicts.md`. Tests follow code.

### 5.1 Invoke accept is HTTP 200, not 202

Catalog Conventions / Stage 10 accepted-request behavior say HTTP 202. `openSseResponse` returns SSE `status: 200` (`adapter.ts:573-580`). Invoke tests assert 200 + `text/event-stream` + SSE `accepted`.

### 5.2 Non-empty chain does not reach SSE `completed` in this pool

Catalog serving journeys imply `completed`. Routing persists `routing_decision` then live DeepSeek/Gemini fail with `provider_rejected` (Register 5 #33). Stage 05 asserts D1 `routing_decision` (policy_version, rule_id, chain, excluded, cost class, routing_tier), not invocation success. Empty-chain IDs still require SSE `failed` / `provider_unavailable`.

### 5.3 S05-059 30 s cache window is not observable

Catalog default TTL is 30 s. Pool `CONFIG_CACHE_TTL_MS` is `"100"` (TTL `"0"` is unsafe). Full `postRequest` SSE drain exceeds 100 ms, so the warm v2 entry expires before the post-rollback invoke. Test asserts D1 v1 after rollback and after `clearConfigCache()`.

### 5.4 Phase 0 / Stage 03 alignments still in force

Harness `OPERATOR_BEARER` is `test-operator-bearer-token`. Enroll origin is `GATEWAY_ORIGIN` (`https://ai-gateway.test`). Enroll uses `generateTestKeypair()`. Control 401 is `{"error":"unauthorized"}`.

## 6. Harness gaps (commented in tests; harness not extended)

- S05-023: `canaryPolicy` has no `cohort_name`; test uses `controlFetch`.
- S05-053 / S05-054: isolate console is not captured; `routing_policy_r2_miss` log is not asserted.

Register 5 items implemented rather than skipped:

- #2 S05-016 — `dispatchControlRequest` with `{ DB }` only.
- #7 S05-059 — `clearConfigCache()` + TTL `"100"` (not `"0"`).
- #10 S05-020 — `wrapD1` UNIQUE + `dispatchControl`.
- #27 S05-069 / S05-070 — kill-switch control routes exist; tests arm via HTTP.

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**Supabase contract scenarios: none in Stage 05.** All 85 catalog IDs are platform-worker routing/control. None deferred.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-05-publish.test.ts` (Writer 1)
- `ai-platform/test/e2e/stage-05-canary-promote.test.ts` (Writer 2)
- `ai-platform/test/e2e/stage-05-rollback-serving.test.ts` (Writer 3 + Fixer 1)
- `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts` (Writer 4 + Fixer 2)
- `ai-platform/test/e2e/reports/stage-05-failures.md` (Runner 1, overwritten by Runner 2)
- `ai-platform/test/e2e/reports/stage-05-conflicts.md` (Fixers)
- `ai-platform/test/e2e/reports/stage-05.md` (this report)

Harness, production `ai-platform/src/`, `backend/supabase/migrations/`, Stage 00–04 tests, and exemplars were not modified.
