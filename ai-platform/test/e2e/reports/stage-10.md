# Stage 10 — Accept, route, invoke, stream E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  2 passed (2)
      Tests  34 passed (34)
   Start at  14:54:39
    Duration  40.42s (transform 471ms, setup 116ms, collect 1.54s, tests 62.16s, environment 1ms, prepare 391ms)
```

- Passing: **34**
- Skipped: **0** (zero unexpected skips; Register 5 #23 S10-033 implemented at ~16 s wall clock; #35 S10-034 implemented via `Map.prototype.get` spy)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-10-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

S10-033 passed in 16854 ms. Per-file: `stage-10-route-retry-idempotency.test.ts` 17/17 (24040 ms); `stage-10-prose-guard-stream.test.ts` 17/17 (38123 ms).

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts` | S10-001 … S10-017 | Writer 1 |
| `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` | S10-018 … S10-034 | Writer 2 |

All 34 catalog IDs (S10-001…S10-034) were assigned. No Supabase-contract IDs in this stage (hard rule 7).

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-10-route-retry-idempotency.test.ts`

Implemented (real `it`): S10-001 … S10-017 (17).

Skipped: **none**.

Register 5 seams implemented rather than skipped:

- FakeAdapter constructor / `prototype.invoke` spy (catalog §1; not on the barrel — HARNESS-GAP)
- Local `readSseUntil` for in-flight abort / admitted replay (S10-013, S10-014, S10-017)
- Local `requestAbortedAtEntry` plus barrel `handleAdapterRequest` for S10-015 (Register 5 #39)

S10-009 is the missing-key `provider_rejected` path (automatable). Live DeepSeek/Gemini wire shaping is Register 5 #33 and was not assigned as an ID.

### 2.2 Writer 2 — `stage-10-prose-guard-stream.test.ts`

Implemented (real `it`): S10-018 … S10-034 (17).

Skipped: **none**.

Register 5 seams implemented rather than skipped:

- #23 S10-033 — heartbeat at wall-clock cost (~16 s); pool `testTimeout` is 120000
- #35 S10-034 — `Map.prototype.get` spy on the accept-context store
- S10-024 `[SEED]` via production `__setArtifactContentForTest` (catalog named `vi.mock`; e2e setup does not mock the registry)
- Replay prior state rebuilt in this file (S10-005-style failure for S10-018; S10-013-style cancel for S10-019)

## 3. Iteration count

**1 runner→fixer iteration** (2 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 25 passed, 0 skipped, **9 failed** | 2 files (`route-retry-idempotency`, `prose-guard-stream`) |
| Runner 2 | **34 passed, 0 skipped, 0 failed** | none — green |

Runner 1 failures: S10-005, S10-006, S10-007, S10-008, S10-013, S10-015, S10-019, S10-028, S10-034.

## 4. Final counts (Runner 2)

| | Count |
|---|---|
| Passing | 34 |
| Skipped | 0 |
| Failing | 0 |
| Test files | 2 passed |
| Catalog IDs in this stage | 34 |
| Assigned to writers | 34 (S10-001…034) |
| Deferred (not tests, not skips) | 0 |

Skipped IDs: none.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-10-conflicts.md`. Tests follow code.

### 5.1 S10-005 / S10-008 — per-attempt FakeAdapter construction

Catalog: one unknown-id adapter whose script queue exhausts → attempt 2 `internal_error`.

Code: `resolveProviderPort` constructs `new FakeAdapter(["retryable:provider_unavailable"])` on every attempt (`worker.ts:351-366`). Both bogus attempts are `provider_unavailable`. S10-006/S10-007 spies share script tokens across constructions so same-target retry can still succeed.

### 5.2 S10-015 — aborted signal does not cross SELF.fetch

Catalog: `SELF.fetch` with an already-aborted signal; D1 row stays `Accepted`.

Code: workerd rejects `new Request({ signal: aborted })`, and a Proxy on `Request.signal` is invisible inside the worker isolate. Barrel `handleAdapterRequest` (Register 5 #39) observes `abortedAtEntry`: `eventSource` never runs, SSE is `accepted` only, stub `preAccept` does not INSERT, so there is no `ai_request` row.

### 5.3 S10-028 — truncation-exhausted path emits no text_delta

Catalog: `accepted` → `text_delta("Partial output…")` → `failed` `validation_failed`.

Code: with `max_attempts: 1`, the worker `pushFailedTerminal` path closes the stream before the broker emits the truncation chunk. Actual SSE: `accepted` → `failed`. Credit-once, attempt `outcome "truncation"`, usage 30 / 0.005 unchanged. S10-029 still emits `text_delta` because retry keeps the broker open.

### 5.4 S10-034 — missing-handoff settlement skips synthetic attempt

Catalog: synthetic `ai_attempt`, partial credit, `usage_event`, R2 envelope via `settleMissingHandoffInternalError`.

Code: settlement rebuilds `Principal` with empty `scopes` / `role` → `resolveCapability` `forbidden_capability` → `missing_handoff_settle_capability_unresolved` → `recordTerminalState(Failed, internal_error)` only. SSE `accepted` → `failed` `internal_error` still holds.

### 5.5 Stage 08 / 09 alignments still in force

- Invoke SSE accept is HTTP **200**, not 202.
- Unique AAT `jti` per POST.
- Entitle window is harness `DEFAULT_ENTITLE_PAYLOAD` (2026-01-01 … 2027-01-01), not catalog `period_start` 2026-07-01.
- `usage_event.period` follows wall-clock / entitle period (`YYYY-MM`), not catalog `2026-07`.
- Envelope `correlationIds.trace_id` is the AAT `jti`, not `x-trace-id`.
- `selection_reason` is in-memory only (no D1 column).

## 6. Harness gaps (commented in tests; harness not extended)

| ID | Gap |
|---|---|
| S10-002, S10-006…011, S10-013, S10-014, S10-017, S10-019…032 | FakeAdapter constructor / `prototype.invoke` spy is not on the barrel. Catalog §1 documents the seam. |
| S10-013, S10-014, S10-017, S10-019 | `postRequest` drains the whole SSE. Tests use `clinicFetch` / `SELF.fetch` plus a local `readSseUntil`. |
| S10-015 | `SELF.fetch` cannot inject aborted-at-entry. Tests use barrel `handleAdapterRequest`. |
| S10-024 | Catalog `[SEED]` named `vi.mock("../../src/prompt/registry")`. E2E setup does not mock the registry; tests use production `__setArtifactContentForTest`. |
| S10-023 | Leak needles from the real bundled `system.md` via `leakNeedlesFromSystemInstruction`, not the 43-char system-test mock. |
| S10-028, S10-032 | `creditUsage` spy is not on the barrel. |
| S10-034 | `Map.prototype.get` spy is not on the barrel; catalog describes the seam. |

Register 5 #33 live DeepSeek/Gemini fetch-stub wire behavior was not implemented (no catalog ID in this stage besides missing-key S10-009). Register 5 #34 deadline-driven invocation branches have no POST-level seam.

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**None.** Stage 10 has no Supabase contract IDs. All 34 catalog IDs are real `it` tests.

Live provider HTTP shaping / Retry-After / 16 KiB raw-body cap (Register 5 #33, catalog non-automatable notes 1–3) remain out of this stage until a fetch-stub + API-key binding seam is used. Missing-key S10-009 is covered.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts` (Writer 1, then Fixer)
- `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` (Writer 2, then Fixer)
- `ai-platform/test/e2e/reports/stage-10-failures.md` (runners)
- `ai-platform/test/e2e/reports/stage-10-conflicts.md` (fixers)
- `ai-platform/test/e2e/reports/stage-10.md` (this report)

Harness, production `ai-platform/src/`, `backend/supabase/migrations/`, and other stages were not modified.
