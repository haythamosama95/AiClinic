# Stage 12 — Lookup and support E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  4 passed (4)
      Tests  72 passed (72)
   Start at  15:51:22
   Duration  29.30s (transform 569ms, setup 240ms, collect 3.42s, tests 82.61s, environment 0ms, prepare 1.06s)
```

- Passing: **72**
- Skipped: **0** (zero unexpected skips; Register 5 #7 S12-039/040, #10 S12-009, and #43 S12-060 implemented, not skipped)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-12-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

Per-file: `stage-12-support-lookup.test.ts` 15/15 (13637 ms); `stage-12-quota-inspect-dashboard.test.ts` 17/17 (16648 ms); `stage-12-get-auth.test.ts` 22/22 (25845 ms); `stage-12-get-lookup.test.ts` 18/18 (26476 ms). S12-060 passed in 10940 ms.

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-12-get-lookup.test.ts` | S12-001 … S12-018 | Writer 1 |
| `ai-platform/test/e2e/stage-12-get-auth.test.ts` | S12-019 … S12-040 | Writer 2 |
| `ai-platform/test/e2e/stage-12-support-lookup.test.ts` | S12-041 … S12-055 | Writer 3 |
| `ai-platform/test/e2e/stage-12-quota-inspect-dashboard.test.ts` | S12-056 … S12-072 | Writer 4 |

All 72 catalog IDs (S12-001…S12-072) were assigned. No Supabase-contract IDs in this stage (hard rule 7).

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-12-get-lookup.test.ts`

Implemented (real `it`): S12-001 … S12-018 (18).

Skipped: **none**.

Register 5 seams implemented rather than skipped:

- #10 S12-009 — live POST → `accepted` → GET while FakeAdapter hangs; labeled `[SEED] state='Invoking'` fallback if that GET already settled

### 2.2 Writer 2 — `stage-12-get-auth.test.ts`

Implemented (real `it`): S12-019 … S12-040 (22).

Skipped: **none**. S12-039/040 not skipped: isolate TTL + `isolateConfigCache.setTtlMs` (Register 5 #7).

### 2.3 Writer 3 — `stage-12-support-lookup.test.ts`

Implemented (real `it`): S12-041 … S12-055 (15).

Skipped: **none**.

`500 missing_r2_binding` has no S12 catalog ID (Register 5 #2 / non-automatable note 1). Not invented as an extra ID.

### 2.4 Writer 4 — `stage-12-quota-inspect-dashboard.test.ts`

Implemented (real `it`): S12-056 … S12-072 (17).

Skipped: **none**. S12-060 implemented (501 admit+credit RPCs), not skipped for slowness.

## 3. Iteration count

**0 runner→fixer iterations** (1 runner pass).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | **72 passed, 0 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 1)

| | Count |
|---|---|
| Passing | 72 |
| Skipped | 0 |
| Failing | 0 |
| Test files | 4 passed |
| Catalog IDs in this stage | 72 |
| Assigned to writers | 72 (S12-001…072) |
| Deferred (not tests, not skips) | 0 |

Skipped IDs: none.

## 5. Catalog-vs-code conflicts

No `stage-12-conflicts.md` (no fixer pass). Writer notes that follow code, recorded here:

### 5.1 S12-029 / S12-030 — unknown `iss` / `kid` are UUIDs

Catalog examples `inst-ghost-999` / `key-ghost-999`. Tests use UUID-shaped unknowns (Stage 07 S07-016 style). Assertions unchanged (401 `unauthenticated`).

### 5.2 Token contract `ver` is `"1"`

Catalog I0 text uses `v1`. Harness / D1 seed is `TOKEN_CONTRACT_VER = "1"`. S12-037 still uses `'v99'` as cataloged. S12-038 retires `ver='1'`.

### 5.3 S12-060 — concurrency cap of 16

Catalog: 501 direct `admission` RPCs. Code: Quota DO `inFlight >= 16` refuses further admits. Test credits after each admission so 501 distinct keys exist; verbose maps still truncate at 500; non-verbose `idempotency_keys`=501.

### 5.4 Phase 0 / prior-stage alignments still in force

- Empty GET `/v1/requests/` is null-body 404; catch-all is plain-text `Not Found` (S12-013 vs S12-014/S12-018; Stage 00 S00-017).
- Control 401 is `{ "error": "unauthorized" }` (S12-043/044/063).
- AAT claim is `role`, not `roles`.
- `CONFIG_CACHE_TTL_MS="0"` is unsafe; harness `"100"` plus `isolateConfigCache.setTtlMs` / `clearConfigCache()`.
- Unique AAT `jti` per POST.
- `visit.chief_complaint@v1` is the object from `visitSummaryInvokeBody`, not the catalog string.
- Invoke SSE accept is HTTP **200**, not 202.
- No Supabase IDs; `newScenario()` UUIDs, not catalog `inst-aaa-001`.

## 6. Harness gaps (commented in tests; harness not extended)

| ID | Gap |
|---|---|
| S12-007, S12-009 | FakeAdapter constructor spy is not on the barrel. Local SSE pump / abort helpers — `postRequest` drains the whole stream. |
| S12-019…021 | `getRequestByRef` always sends `Bearer`; tests use `clinicFetch` with custom/missing `Authorization`. |
| S12-039/040 | Injectable `new ConfigCache` is not on the barrel. Tests use `isolateConfigCache.setTtlMs`. |
| S12-051 | No R2 `get` spy on the barrel. Test asserts `envelope: null` with the object left in place. |
| S12-066…072 | Dashboard exports are not on the barrel. Tests import `../../src/dashboards` (catalog Action is the SQL-contract call). |

Register 5 #2 `500 missing_r2_binding` (support lookup) and `503 quota_do_unavailable` remain non-automatable via `SELF.fetch`; no S12 IDs assigned. Register 5 #21 `400 invalid_route` is unreachable via HTTP.

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**None.** Stage 12 has no Supabase contract IDs. All 72 catalog IDs are real `it` tests.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-12-get-lookup.test.ts` (Writer 1)
- `ai-platform/test/e2e/stage-12-get-auth.test.ts` (Writer 2)
- `ai-platform/test/e2e/stage-12-support-lookup.test.ts` (Writer 3)
- `ai-platform/test/e2e/stage-12-quota-inspect-dashboard.test.ts` (Writer 4)
- `ai-platform/test/e2e/reports/stage-12-failures.md` (runner)
- `ai-platform/test/e2e/reports/stage-12.md` (this report)

Harness, production `ai-platform/src/`, and `backend/supabase/migrations/` were not modified.
