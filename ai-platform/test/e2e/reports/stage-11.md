# Stage 11 — Terminal settlement E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  2 passed (2)
      Tests  21 passed (21)
   Start at  15:35:47
   Duration  16.77s (transform 492ms, setup 128ms, collect 1.54s, tests 27.73s, environment 0ms, prepare 380ms)
```

- Passing: **21**
- Skipped: **0** (zero unexpected skips; S11-021 implemented via documented `creditUsage` + `wrapDurableObjectNamespace` component seam, not skipped)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-11-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

Per-file: `stage-11-completed-failed-cancelled.test.ts` 11/11 (13162 ms); `stage-11-replay-envelope-grace.test.ts` 10/10 (14568 ms).

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts` | S11-001 … S11-011 | Writer 1 |
| `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts` | S11-012 … S11-021 | Writer 2 |

Assigned to writers: **21** IDs (S11-001…S11-021). S11-022…S11-029 were **not** assigned (hard rule 7).

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-11-completed-failed-cancelled.test.ts`

Implemented (real `it`): S11-001 … S11-011 (11).

Skipped: **none**.

Register 5 seams implemented rather than skipped:

- FakeAdapter constructor / subclass spy (catalog §1; not on the barrel — HARNESS-GAP)
- Local abort helpers: hangUntilAbort, waitFor, clinicFetch + AbortController (S11-008…011)
- `creditUsage` spy via `../../src/credit` for partial / idempotencyState / single-credit (not on the barrel — HARNESS-GAP)

### 2.2 Writer 2 — `stage-11-replay-envelope-grace.test.ts`

Implemented (real `it`): S11-012 … S11-021 (10).

Skipped: **none**.

S11-022…S11-029 were not written (not even `it.skip`).

Register 5 seams implemented rather than skipped:

- Direct GatewayObject RPC (`gatewayObjectRpc` / `gatewayObjectJson`) for S11-012 / S11-017(b)
- `setCapabilityRegistry({ replace: true })` for S11-016
- `wrapDurableObjectNamespace` + `creditUsage({ DO, DB })` for S11-021 (component path; Register 5 #28 does not apply because the catalog Action is not `SELF.fetch`)
- `[SEED]` `grace_admission_queue` row for S11-021

Replay / envelope prior state is rebuilt inside the same `it` (`beforeEach` `resetE2eState` isolates files).

## 3. Iteration count

**1 runner→fixer iteration** (2 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 15 passed, 0 skipped, **6 failed** | 2 files (`completed-failed-cancelled`, `replay-envelope-grace`) |
| Runner 2 | **21 passed, 0 skipped, 0 failed** | none — green |

Runner 1 failures: S11-008, S11-009, S11-010, S11-011, S11-016, S11-018.

## 4. Final counts (Runner 2)

| | Count |
|---|---|
| Passing | 21 |
| Skipped | 0 |
| Failing | 0 |
| Test files | 2 passed |
| Catalog IDs in this stage | 29 |
| Assigned to writers | 21 (S11-001…021) |
| Deferred (not tests, not skips) | 8 (S11-022…029) |

Skipped IDs: none.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-11-conflicts.md`. Tests follow code.

### 5.1 S11-009 — immediate abort never reaches admission

Catalog: unmodified FakeAdapter; `controller.abort()` immediately after dispatch so `onAbort` fires before/around invoke; zero `ai_attempt` rows.

Code: abort-at-dispatch cancels `SELF.fetch` before ingress (no `ai_request`). workerd throws if an already-aborted signal is passed into `Request` construction. Zero-attempt settlement is the pre-attempt `callerSignal?.aborted` check (`invocation/index.ts:526-533`) after admission and `persistRoutingDecision`. Test waits for `ai_request` then aborts in that window (60 ms hold after routing persist). Assertions unchanged (zero attempts, Cancelled, usage 0/0).

### 5.2 S11-010 / S11-011 — pending-fetch abort discards unread SSE

Catalog: abort after second invoke / 250-char `text_delta`; client observes `regenerating` or one provisional `text_delta` before the stream dies.

Code: abort must happen while the fetch promise is still pending or `hangUntilAbort` resolves as success (S11-011 settled Completed). After pending-fetch abort, workerd discards the unread body. SSE assertions read bytes already `enqueue`'d on the adapter sink (same frames). Settlement assertions unchanged.

### 5.3 S11-018 — 16 KiB cap does not re-clamp after UTF-8 decode

Catalog: truncated payload string at most 16 384 bytes.

Code: `captureRawProviderBody` slices then decodes with no re-clamp (`raw-body.ts:25-26`). Catalog ellipsis fixture (`U+2026`) splits a 3-byte character → U+FFFD → re-encoded 16386 bytes. Test requires `truncated === true`, string payload, and payload bytes matching the production helper.

### 5.4 Stage 08 / 09 / 10 alignments still in force

- Invoke SSE accept is HTTP **200**, not 202.
- Unique AAT `jti` per POST.
- Entitle window uses `period_start: 2026-07-01` with `period_end: 2027-01-01` (catalog `2026-09-01` end is expired as of 2026-09-05). `usage_event.period` is `'2026-07'` from admission `period_start`.
- Truncation-exhausted path (S11-006 / S11-020 recreation) may omit `text_delta` (stage-10 S10-028).
- Live providers often `provider_rejected` without FakeAdapter spy; these tests spy FakeAdapter.

## 6. Harness gaps (commented in tests; harness not extended)

| ID | Gap |
|---|---|
| S11-002, S11-004…011, S11-014, S11-015, S11-018…020 | FakeAdapter constructor / subclass spy is not on the barrel. Catalog §1 documents the seam. |
| S11-003, S11-005…011 | `creditUsage` spy is not on the barrel. |
| S11-008…011 | `postRequest` drains the whole SSE. Abort tests use `clinicFetch` + local wait/abort. |
| S11-018, S11-019 | `captureRawProviderBody` is not on the barrel. |
| S11-021 | `creditUsage` is not on the barrel (catalog Action calls it directly). `writeSettlementJournal` is not exported — test uses `createRequestRow` + `writePostResponseDetail` with a local draining `waitUntil` (`emptyExecutionContext.waitUntil` is a no-op). |

Register 5 #28 full-path DO outage at credit after a healthy admission remains non-automatable (catalog non-automatable note 1). S11-021 covers the same code at component level.

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**S11-022 … S11-029** — Supabase `record_ai_acceptance` contract scenarios (hard rule 7). Not assigned to writers. Not implemented as tests. Not `it.skip`. Deferred to the pgTAP / PostgREST track after Phase 15.

| ID | Title |
|---|---|
| S11-022 | `record_ai_acceptance` happy path writes acceptance, audit log, and merged rpc_success |
| S11-023 | rejects malformed request references |
| S11-024 | rejects unregistered acceptance targets |
| S11-025 | rejects duplicate acceptance before any domain write |
| S11-026 | requires organization context |
| S11-027 | passes through delegated domain failures unchanged |
| S11-028 | rolls back everything when the domain write returns no record id |
| S11-029 | wrapper gate and `ai_accepted_output` RLS visibility |

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts` (Writer 1, then Fixer)
- `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts` (Writer 2, then Fixer)
- `ai-platform/test/e2e/reports/stage-11-failures.md` (runners)
- `ai-platform/test/e2e/reports/stage-11-conflicts.md` (fixers)
- `ai-platform/test/e2e/reports/stage-11.md` (this report)

Harness, production `ai-platform/src/`, `backend/supabase/migrations/`, and other stages were not modified.
