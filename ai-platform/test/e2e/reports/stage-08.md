# Stage 08 — Request ingress E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  3 passed (3)
      Tests  57 passed | 3 skipped (60)
   Start at  13:21:09
   Duration  19.27s (transform 467ms, setup 182ms, collect 2.30s, tests 26.17s, environment 1ms, prepare 737ms)
```

- Passing: **57**
- Skipped: **3** (Register 5 #37 Content-Length only: S08-003, S08-005, S08-009; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-08-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-08-size-json-headers.test.ts` | S08-001 … S08-020 | Writer 1 |
| `ai-platform/test/e2e/stage-08-trace-auth.test.ts` | S08-021 … S08-040 | Writer 2 |
| `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts` | S08-041 … S08-060 | Writer 3 |

S08-061 … S08-069 were **not** assigned to writers (hard rule 7: Supabase context-provider RPC, deferred to pgTAP).

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-08-size-json-headers.test.ts`

Implemented (real `it`): S08-001, S08-002, S08-004, S08-006, S08-007, S08-008, S08-010 … S08-020 (17).

Skipped (`it.skip`, Register 5 #37): S08-003, S08-005, S08-009 — workerd may strip `Content-Length` on constructed `Request`; no in-pool seam. Stream-path size coverage is S08-004 / S08-006 / S08-007 / S08-008.

### 2.2 Writer 2 — `stage-08-trace-auth.test.ts`

Implemented (real `it`): S08-021 … S08-040 (20).

Skipped: **none**.

### 2.3 Writer 3 — `stage-08-guard-sse-adapter.test.ts`

Implemented (real `it`): S08-041 … S08-060 (20).

Skipped: **none**. Register 5 seams implemented rather than skipped:

- #31 S08-044 — live `RATE_LIMITER_*` `.limit` host-object patch (`installEnvOverrides` swap does not reach `SELF.fetch`)
- #38 S08-056 / S08-057 — steady-state stream closed / no `cancelled` frame (S08-057 via `handleAdapterRequest` after injecting aborted `.signal`)
- #39 S08-058 / S08-060 — barrel `handleAdapterRequest`
- #40 S08-049 — assert `content-type` / `cache-control` in-pool; do not require `connection`

## 3. Iteration count

**2 runner→fixer iterations** (3 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 47 passed, 3 skipped, **10 failed** | 2 fixers (`trace-auth`, `guard-sse-adapter`) |
| Runner 2 | 56 passed, 3 skipped, **1 failed** (S08-057) | 1 fixer (`guard-sse-adapter`) |
| Runner 3 | **57 passed, 3 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 3)

| | Count |
|---|---|
| Passing | 57 |
| Skipped | 3 |
| Failing | 0 |
| Test files | 3 passed |
| Catalog IDs in this stage | 69 |
| Assigned to writers | 60 (S08-001…060) |
| Deferred (not tests, not skips) | 9 (S08-061…069) |

Skipped IDs (expected Register 5 #37): S08-003, S08-005, S08-009.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-08-conflicts.md`. Tests follow code.

### 5.1 S08-034 / S08-042 / S08-043 — entitlement stage 3 before registry stage 5

Catalog: unknown `capability_id` / unpublished `x-capability-version` → HTTP 404 `capability_unknown`.

Code: guard stage 3 (`evaluateEntitlement` → `capability_not_granted`) runs before stage 5 registry resolve → HTTP 403 `forbidden_capability` (`retry_safe: false`). Same order as Stage 00 S00-008. Precedence of `capability_id` over alias still holds (the unknown primary key is what stage 3 evaluates).

### 5.2 S08-045 — `quota_exhausted` carries `period_reset`

Catalog: no `retry_after` and no `period_reset` on the live body.

Code: no `retry_after` is correct. Admission sets `periodReset` from entitle `period_end`; `createProductionPreAccept` forwards it; the adapter emits `period_reset` when non-empty. Live body includes `period_reset: "2027-01-01T00:00:00.000Z"`.

### 5.3 S08-053 — `authoritative` nested under `result.finalContent`

Catalog: replay `completed` with canned `"Prior request completed."` and `authoritative: true` on the event data root.

Code: canned text matches; `authoritative: true` lives on `data.result.finalContent`, not `completed.data.authoritative`.

### 5.4 Multi-POST journeys need a unique AAT `jti`

Catalog assumed one minted AAT could be reused. Quota DO treats a reused `jti` as admission replay → 401 `unauthenticated` before idempotency/quota. Tests mint a fresh AAT per POST (S08-045, S08-051…054). Assertions otherwise follow catalog wire outcomes.

### 5.5 Phase 0 / Stage 05 alignments still in force

- Invoke SSE accept is HTTP **200**, not 202.
- AAT claim is `role`, not `roles`.
- `CONFIG_CACHE_TTL_MS="0"` is unsafe; harness `"100"`.
- `visit.chief_complaint@v1` uses the object shape from `visitSummaryInvokeBody` (code), not the catalog string.

## 6. Harness gaps (commented in tests; harness not extended)

| ID | Gap |
|---|---|
| S08-010 | `postRequest` always serializes a body; empty-body ingress uses `clinicFetch` with no body |
| S08-037 | `postRequest` always prefixes `Bearer`; Basic scheme uses `clinicFetch` |
| S08-044 | `installEnvOverrides` swapping `RATE_LIMITER_*` does not reach `limit()` on `SELF.fetch`. Test patches `.limit` on the live host objects instead |
| S08-056 | `notifyDisconnect` is not on the barrel; assert stream closed / no `cancelled` frame |
| S08-057 | workerd throws `AbortError` on `new Request(..., { signal: AbortSignal.abort() })`. Scenario driven via barrel `handleAdapterRequest` after injecting aborted `.signal` post-construction (same family as S08-058/060) |

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**S08-061 … S08-069 — deferred to pgTAP / PostgREST** (hard rule 7; Register 5 #41). Context-provider RPC `get_visit_chief_complaint` against clinic Supabase; not the workers pool. They are **not** `it.skip` (deferred-to-pgTAP, not Register 5 in-pool skips).

| ID | Catalog title (short) |
|---|---|
| S08-061 | RPC happy path supplies `visit.chief_complaint@v1` |
| S08-062 | RPC with no clinical note; client omits key → `context_required` |
| S08-063 | RPC note with NULL complaint omits only complaint key |
| S08-064 | RPC ignores soft-deleted notes |
| S08-065 | Unknown visit UUID → `NOT_FOUND` |
| S08-066 | Out-of-scope visit → `NOT_FOUND` (not `FORBIDDEN`) |
| S08-067 | No clinical read permission → `FORBIDDEN` |
| S08-068 | Out-of-scope + no permission → `NOT_FOUND` (scope precedes permission) |
| S08-069 | Anon cannot call the RPC |

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-08-size-json-headers.test.ts` (Writer 1)
- `ai-platform/test/e2e/stage-08-trace-auth.test.ts` (Writer 2, then Fixer 1)
- `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts` (Writer 3, then Fixers 2–3)
- `ai-platform/test/e2e/reports/stage-08-failures.md` (runners)
- `ai-platform/test/e2e/reports/stage-08-conflicts.md` (fixers)
- `ai-platform/test/e2e/reports/stage-08.md` (this report)

Harness, production `ai-platform/src/`, `backend/supabase/migrations/`, and other stages were not modified.
