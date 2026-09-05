# Stage 04 — Entitlement and capability grants E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  5 passed (5)
      Tests  104 passed (104)
   Start at  12:01:42
   Duration  7.48s (transform 600ms, setup 325ms, collect 4.07s, tests 19.56s, environment 0ms, prepare 1.54s)
```

- Passing: **104**
- Skipped: **0** (Register 5 seams implemented, not skipped; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-04-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-04-entitle-auth-period.test.ts` | S04-001 … S04-020 | Writer 1 |
| `ai-platform/test/e2e/stage-04-entitle-quota-grants-validation.test.ts` | S04-021 … S04-040 | Writer 2 |
| `ai-platform/test/e2e/stage-04-entitle-happy-cohort-activate.test.ts` | S04-041 … S04-065 | Writer 3 |
| `ai-platform/test/e2e/stage-04-cohort-promote-deprecate.test.ts` | S04-066 … S04-085 | Writer 4 |
| `ai-platform/test/e2e/stage-04-deprecate-retire-auth.test.ts` | S04-086 … S04-104 | Writer 5 |

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-04-entitle-auth-period.test.ts`

Implemented (real `it`): S04-001 … S04-020 (20).

Skipped: **none**.

S04-005 uses `dispatchControl` + `createSecretOperatorAuth({ bearerToken: "" })` (unconfigured operator secret). Pool `SELF.fetch` cannot unset `OPERATOR_BEARER_TOKEN`.

### 2.2 Writer 2 — `stage-04-entitle-quota-grants-validation.test.ts`

Implemented (real `it`): S04-021 … S04-040 (20).

Skipped: **none**. Register 5 #24 (`cost_budget` NaN/Infinity unreachable over HTTP) is not an ID in this range; S04-026 is the string `"50.0"` case.

### 2.3 Writer 3 — `stage-04-entitle-happy-cohort-activate.test.ts`

Implemented (real `it`): S04-041 … S04-065 (25).

Skipped: **none**. S04-057 implemented via `wrapD1` `{ batchThrow: diskIoError() }` + `dispatchControl` (Register 5 #19). `[SEED]` only on S04-048, S04-049, S04-054; S04-056 is a direct D1 UNIQUE probe.

### 2.4 Writer 4 — `stage-04-cohort-promote-deprecate.test.ts`

Implemented (real `it`): S04-066 … S04-085 (20).

Skipped: **none**. S04-066 / S04-069 / S04-074 use `[REGISTRY]` two-version seam. `[SEED]` only on S04-078.

### 2.5 Writer 5 — `stage-04-deprecate-retire-auth.test.ts`

Implemented (real `it`): S04-086 … S04-104 (19).

Skipped: **none**. S04-091 is a real `it` asserting HTTP 400 `{"error":"invalid_payload"}` (code `requireNonEmptyString` guard; Register 5 #8 TypeError skip not used because the handler returns a Response). Overlap-window S04-095…S04-097 / S04-098 / S04-100 use real deprecate plus `[SEED] retire_after` where labeled.

## 3. Iteration count

**0 runner→fixer iterations** (1 runner pass).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | **104 passed, 0 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 1)

| | Count |
|---|---|
| Passing | 104 |
| Skipped | 0 |
| Failing | 0 |
| Test files | 5 passed |

Skipped IDs: none.

## 5. Catalog-vs-code conflicts

No fixer pass; `stage-04-conflicts.md` was not created. Writers already followed known Stage 00/03 / Phase 0 alignments:

### 5.1 S04-091 — non-string `successor_id` returns a Response

Register 5 #8 / Register 4 #21 still describe an uncaught TypeError. Code (`capability-lifecycle.ts`) now type-guards via `requireNonEmptyString` and returns HTTP 400 `{"error":"invalid_payload"}`, matching the catalog scenario. Test asserts the Response, not a fetch rejection.

### 5.2 Operator bearer and enroll origin (Phase 0 / Stage 03)

Harness `OPERATOR_BEARER` is `test-operator-bearer-token` (not catalog `test-operator-token`). Enroll/control origin is `GATEWAY_ORIGIN` (`https://ai-gateway.test`). Tests use `controlFetch` auth variants.

### 5.3 Catalog example keys / entitle one-shot

Enroll uses `generateTestKeypair()` (32-byte Ed25519). Entitle is one-shot (`409 not_pending` on re-entitle); each test rebuilds pending state after `resetE2eState()`.

### 5.4 Phase 0 conflicts still in force

- Control 401 is `{"error":"unauthorized"}` (not taxonomy).
- AAT claim is `role`, not `roles` (S04-003 mints via harness `mintAat`).
- `CONFIG_CACHE_TTL_MS="0"` is unsafe; harness `"100"` (not exercised as a Stage 04 assertion).
- Default harness entitle window is 2026-01-01…2027-01-01; Stage 04 entitle tests use catalog REF-BODY periods where specified (entitle does not require wall-clock-in-period).

## 6. Harness gaps (commented in tests; harness not extended)

None. No `HARNESS-GAP` comments in Stage 04 files.

Register 5 items noted but not skipped (automatable seams used):

- #8 S04-091 — code returns 400 `invalid_payload`; implemented, not skipped.
- #9 timing-safe compare — functional 401 coverage only (S04-001…S04-005, S04-058, S04-072, S04-080, S04-092, S04-101…S04-104).
- #19 `storage_error` — S04-057 implemented via `wrapD1` + `dispatchControl`.
- #23 90-day overlap wait — `[SEED] retire_after` for S04-096/097/098/100; S04-095 uses a just-written deprecate overlay.
- #24 `cost_budget` NaN/Infinity — not an ID; documented only.

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**Supabase contract scenarios: none in Stage 04.** All 104 catalog IDs are platform-worker control-plane. None deferred.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-04-entitle-auth-period.test.ts` (Writer 1)
- `ai-platform/test/e2e/stage-04-entitle-quota-grants-validation.test.ts` (Writer 2)
- `ai-platform/test/e2e/stage-04-entitle-happy-cohort-activate.test.ts` (Writer 3)
- `ai-platform/test/e2e/stage-04-cohort-promote-deprecate.test.ts` (Writer 4)
- `ai-platform/test/e2e/stage-04-deprecate-retire-auth.test.ts` (Writer 5)
- `ai-platform/test/e2e/reports/stage-04-failures.md` (Runner 1)
- `ai-platform/test/e2e/reports/stage-04.md` (this report)

Harness, production `ai-platform/src/`, `backend/supabase/migrations/`, Stage 00–03 tests, and exemplars were not modified.
