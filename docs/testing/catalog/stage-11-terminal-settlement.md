# Stage 11 — Terminal settlement (credit, journal, envelope, acceptance recording)

Source files read: `ai-platform/src/worker.ts` (settleTerminal, settleCompletedRequest, writeSettlementJournal, buildPostResponseInput, attemptsForFailedSettlement, placeholderTerminalResult, periodFromIso, runFreshEventSource brokerTerminal branches), `ai-platform/src/journal/index.ts` (writePostResponseDetail, persistPostResponseDetail, recordTerminalState, persistRoutingDecision, buildEnvelope, envelopeKey, TERMINAL_IMMUTABLE_WHERE), `ai-platform/src/credit/index.ts` (creditUsage, invokeCreditRpc, reconcileGraceUsage shape), `ai-platform/src/quota-do/index.ts` (creditRPC, markIdempotencyOnCredit, maybeResetPeriod, sweepEphemeral, inspectRPC), `ai-platform/src/pricing/index.ts` (ledgerUsageFromProvider, priceUsage, roundLedgerCost, estimateUsageFromStreamedChars, ratesForModel), `ai-platform/control/pricing/platform-default/1.json`, `ai-platform/src/provider/raw-body.ts` (captureRawProviderBody, ENVELOPE_RAW_BODY_BYTE_LIMIT), `ai-platform/src/contracts/canonical.ts` (CanonicalResult / CanonicalRequest field manifests), `ai-platform/src/invocation/index.ts` (processInvokeResult, readPartialUsage, noteUsageFromResult, terminal error factories, chain-exhaustion returns), `ai-platform/src/stream/index.ts` (handleCancel / handleFailed / handleCompleted, creditSink / journalTerminalSink), `ai-platform/src/errors.ts` (taxonomy consumesQuota table), `ai-platform/src/provider/fake.ts` + `ai-platform/src/provider/classify.ts` (FakeAdapter seam, terminal vs retryable classification), `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql` (record_ai_acceptance, invoke_acceptance_domain_rpc, ai_accepted_output), `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql` (save_visit_documentation domain shape), `ai-platform/migrations/20260731120000_platform_schema.sql` + `20260805180000_h3_conversation_index.sql`, `ai-platform/test/system/harness.ts` + `settlement-integrity.system.test.ts` (automation seams), orientation doc `docs/architecture/ai-platform/data-journey/13-stage-11-terminal-settlement.md`.

Shared fixture vocabulary (from `test/system/harness.ts`, reused by every scenario unless overridden): capability `clinic.visit_summary@1.0.0` (single_shot, `Economics.quotaWeight: 1`, `Output.mode: prose`, repairPolicy disabled); entitlement `period_start: "2026-07-01T00:00:00.000Z"`, `period_end: "2026-09-01T00:00:00.000Z"`, `request_quota: 1000`, `token_budget: 500000`, `cost_budget: 50.0`, `soft_threshold: 0.8`; routing policy `standard@1` with one target `{ provider_id: "fake", model_id: "fake-v1", max_attempts: 1, timeout_ms: 30000 }`; FakeAdapter success result `{ usage: { input: 10, output: 20, cached: 0 }, providerModel: { provider: "fake", model: "fake-v1" }, finishReason: "stop", providerRequestId: "fake-req-001", timing: { queue_ms: 1, provider_ms: 5, total_ms: 6 } }` with body `visitSummaryInvokeBody(scenario)` (`user_intent: "Summarize the visit."`, context key `visit.chief_complaint@v1`). Platform pricing (`control/pricing/platform-default/1.json`): `fake-v1` 0.1/0.2, `deepseek-v4-flash` 0.14/0.28, `gemini-3.5-flash` 0.075/0.3 per 1K input/output tokens, `default` 0.1/0.2; costs rounded to 6 decimals. The FakeAdapter success therefore prices at `(10/1000)*0.1 + (20/1000)*0.2 = 0.005` with `tokens = 30`. DO state is observed via `kind: "inspect"` RPC on the installation's GatewayObject stub.

## Scenario S11-001 — Completed settlement writes the full ledger (request, attempt, usage, envelope, DO credit)

| Field | Content |
|-------|---------|
| ID | S11-001 |
| Journey setup | Fresh scenario: enroll + entitle (Stage 3–6 equivalents via `/control/installations/{id}/enroll` and `/entitle` with the shared payload), publish + promote policy `standard@1` (Stage 7). No prior requests for this installation. |
| Action | `POST /v1/requests` with a minted AAT (scopes `ai.visit_summary`, `ai.access`), `x-idempotency-key: s11-001-<uuid>`, `x-capability-version: 1.0.0`, shared visit-summary body. Read the SSE stream to its end, then drain background work. |
| Expected outcome | SSE: `accepted` (Stage 10) then terminal `completed` whose `data.result.finalContent.text` is the assembled stream text `"Fake adapter summary."` with `authoritative: true` (broker-assembled, not the envelope result). Persisted state: `ai_request` row `state = 'Completed'`, `completed_at` ISO non-NULL, `terminal_error_code` NULL, `payload_pointer = 'request/<request_id>/envelope'`, `routing_decision` JSON non-NULL (written pre-invocation by `persistRoutingDecision`), `conversation_id`/`turn_ordinal` NULL (single_shot). Exactly one `ai_attempt`: `attempt_no 1`, `provider 'fake'`, `model 'fake-v1'`, `outcome 'success'`, `latency_ms 6`, `tokens_in 10`, `tokens_out 20`, `cost 0.005`, `provider_request_id 'fake-req-001'`, `error_code` NULL. Exactly one `usage_event`: `installation_id` = scenario installation, `period = '2026-07'` (`periodFromIso("2026-07-01T00:00:00.000Z")` — admission-time entitlement, not wall-clock September), `request_id` = request_id, `quota_weight 1`, `tokens 30`, `cost 0.005`, `recorded_at` ISO. R2 object `request/<request_id>/envelope` exists (key has no `.json` suffix) with exactly top-level keys `context`, `prompt`, `attempts`, `result`: `context` = filtered context (contains `visit.chief_complaint@v1`); `prompt` = CanonicalRequest with keys `parts`, `formatDirective`, `samplingConstraints`, `maxOutputTokens`, `stopConditions`, `toolDeclarations`, `stream`, `deadline`, `correlationIds`; `attempts` = one entry `{ payload: { fake: true, outcome: "success" }, truncated: false }`; `result` = the canonical provider result (`finishReason "stop"`, `usage { input: 10, output: 20, cached: 0 }`). DO (inspect): `periodCounters = { requestsUsed: 1, tokensUsed: 30, costUsed: 0.005, inFlight: 0 }`, `admittedRequests` empty, `creditedRequests[requestId]` present, idempotency entry for `s11-001-<uuid>` in state `completed` with `expiresAt` slid to credit-time + 7 200 000 ms. `GET /v1/requests/{ref}` with the AAT returns `{ state: "Completed", result: <envelope.result> }`. |
| Side effects | MUST: one DO `kind: credit` with `partial: false`, no `idempotencyState` (DO maps to `completed`), entitlement snapshot attached; D1 batch INSERT `ai_attempt` + `usage_event`; R2 `put` of the envelope; D1 UPDATE `ai_request.payload_pointer` (write order: batch → R2 → pointer). MUST NOT: no second `usage_event`, no second R2 object (no `envelope-2` / `envelope-failed` sibling), no `terminal_error_code` write, no `grace_admission_queue` row touched, no preflight `usage_event` (row exists only after the terminal). |
| Code reference | ai-platform/src/worker.ts:1019-1024 — runFreshEventSource completed branch → settleCompletedRequest; ai-platform/src/worker.ts:545-590 — settleCompletedRequest; ai-platform/src/journal/index.ts:378-434 — persistPostResponseDetail; ai-platform/src/journal/index.ts:179-191 — envelopeKey/buildEnvelope; ai-platform/src/stream/index.ts:329-357 — handleCompleted; ai-platform/src/quota-do/index.ts:463-541 — creditRPC |

## Scenario S11-002 — Ledger cost computed from the platform pricing table per model, rounded to 6 decimals

| Field | Content |
|-------|---------|
| ID | S11-002 |
| Journey setup | Same as S11-001 (three independent fresh scenarios, one per model case, so DO counters are isolated). FakeAdapter seam: `vi.spyOn(fakeMod, "FakeAdapter")` returning success results whose `providerModel.model` and `usage` are scripted per case (the seam used by SYS-7.3 in `test/system/settlement-integrity.system.test.ts`). |
| Action | Three completed `POST /v1/requests` journeys: (a) result `providerModel { provider: "fake", model: "deepseek-v4-flash" }`, `usage { input: 1000, output: 500, cached: 0 }`; (b) model `gemini-3.5-flash`, `usage { input: 2000, output: 100, cached: 0 }`; (c) model `unknown-model-x` (not in the pricing table), `usage { input: 10, output: 20, cached: 0 }`. |
| Expected outcome | All three SSE-terminal `completed`. (a) `ai_attempt.cost = usage_event.cost = 0.28` (`1*0.14 + 0.5*0.28`), `usage_event.tokens = 1500`; (b) cost `= 0.18` (`2*0.075 + 0.1*0.3`), tokens 2100; (c) falls back to `default` rates 0.1/0.2 → cost `= 0.005`, tokens 30. All costs exact at 6 decimal places (`roundLedgerCost`). Envelope `result.providerModel.model` matches the scripted model in each case. |
| Side effects | MUST: `ai_attempt.cost`, `usage_event.cost`, and the DO `costUsed` delta agree per request (one shared `priceUsage` helper). MUST NOT: no cost written anywhere before the terminal (preflight stays token-only); no pricing read from D1/R2 at runtime (table is bundled from `control/pricing/platform-default/1.json`). |
| Code reference | ai-platform/src/pricing/index.ts:111-134 — priceUsage/ledgerUsageFromProvider; ai-platform/src/pricing/index.ts:92-99 — ratesForModel/roundLedgerCost; ai-platform/control/pricing/platform-default/1.json:1-24; ai-platform/src/invocation/index.ts:197-211 — usageFieldsFromResult |

## Scenario S11-003 — Failed settlement: provider_unavailable with an empty chain writes a synthetic diagnostic attempt

| Field | Content |
|-------|---------|
| ID | S11-003 |
| Journey setup | Fresh scenario as in S11-001, then publish + promote policy `standard@2` with an installation override `exclude_providers: ["fake"]` so Stage 10 routing resolves an empty chain with `excluded = [{ provider_id: "fake", model_id: "fake-v1", ... }]`. |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-003-<uuid>`, shared body; read SSE to end; drain background work. |
| Expected outcome | SSE: `accepted` then `failed` with `data.code = "provider_unavailable"`, `data.request_reference` = ref, `retry_safe: true` (worker-pushed, since the broker's terminal is suppressed). `ai_request`: `state 'Failed'`, `completed_at` set, `terminal_error_code = 'provider_unavailable'`. Exactly one `ai_attempt` — the synthetic row: `attempt_no 1`, `provider 'fake'`, `model 'fake-v1'` (hint from `routing.excluded[0]`), `outcome 'terminal_failure'`, `latency_ms 0`, `tokens_in 0`, `tokens_out 0`, `cost 0`, `provider_request_id` NULL, `error_code 'provider_unavailable'`. Exactly one `usage_event` with `tokens 0`, `cost 0`, `period '2026-07'`, `quota_weight 1` — zero-usage failure is still journaled. R2 envelope at the same key shape; `attempts[0] = { payload: { reason: "no_provider_attempt", excluded: [...] }, truncated: false }`; `result.finishReason = "provider_unavailable"` (placeholder). DO: credit applied with `partial: true` (`consumesQuota "Partially, recorded"`), `idempotencyState "failed"`; counters `{ requestsUsed: 1, tokensUsed: 0, costUsed: 0, inFlight: 0 }`; idempotency entry state `failed`. `GET /v1/requests/{ref}` → `{ state: "Failed", terminal_error_code: "provider_unavailable" }`. |
| Side effects | MUST: exactly one credit and one `usage_event` despite the broker disconnect racing the failure (`ignoreBrokerSettlement` is set before `pushable.end()`). MUST NOT: no real provider call (no transport traffic); no `Completed` write; broker's `cancelled`/`failed` sink events, credit, and journal are all dropped. |
| Code reference | ai-platform/src/worker.ts:958-988 — failed branch of runFreshEventSource; ai-platform/src/worker.ts:382-411 — attemptsForFailedSettlement; ai-platform/src/worker.ts:898-904 — ignoreBrokerSettlement guard; ai-platform/src/invocation/index.ts:452-457 — empty-chain provider_unavailable; ai-platform/src/errors.ts:102-107 — provider_unavailable consumesQuota |

## Scenario S11-004 — Failed settlement: attempt timeouts exhaust the chain and settle as provider_unavailable

| Field | Content |
|-------|---------|
| ID | S11-004 |
| Journey setup | Fresh scenario; policy `standard@2` with one target `{ provider_id: "fake", model_id: "fake-v1", max_attempts: 2, timeout_ms: 50 }`. FakeAdapter seam: `invoke` never resolves inside 50 ms (5 s timer, abort-aware as in SYS-7.3). |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-004-<uuid>`; read SSE to end; drain background work. |
| Expected outcome | SSE terminal `failed` with `code = "provider_unavailable"` — per-attempt timeouts are retryable-classified, and chain exhaustion always returns the `createProviderUnavailableError()` terminal. Two `ai_attempt` rows: `attempt_no 1` and `2`, both `outcome 'timeout'`, `error_code 'timeout'`, `tokens_in 0`, `tokens_out 0`, `cost 0`, `latency_ms 0` (no result → `?? 0` defaults in buildAttemptInput). `ai_request.terminal_error_code = 'provider_unavailable'` (NOT `'timeout'` — see Doc-drift). One `usage_event` `{ tokens: 0, cost: 0 }`. DO credit `partial: true`, `idempotencyState "failed"`. Envelope `attempts` has two raw-body entries; `result.finishReason = "provider_unavailable"`. |
| Side effects | MUST: attempt rows preserve per-attempt `error_code 'timeout'` even though the request-level code is `provider_unavailable`; inter-attempt backoff sleeps occur (jittered, capped 10 000 ms — keep `timeout_ms` tiny so the test is fast). MUST NOT: no terminal `timeout` state anywhere; no partial token accrual (nothing streamed). |
| Code reference | ai-platform/src/invocation/index.ts:353-359 — invokeWithTimeout timer/createTimeoutError; ai-platform/src/invocation/index.ts:330-337 — timeout outcome mapping; ai-platform/src/invocation/index.ts:755-761 — exhaustion returns provider_unavailable; ai-platform/src/worker.ts:958-988 — failed branch |

## Scenario S11-005 — Failed settlement: provider_rejected consumes full quota after a retryable first attempt

| Field | Content |
|-------|---------|
| ID | S11-005 |
| Journey setup | Fresh scenario; policy target `max_attempts: 2, timeout_ms: 30000`. FakeAdapter seam scripted `["retryable:rate_limited", "terminal:provider_rejected"]`. |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-005-<uuid>`; read SSE to end; drain background work. |
| Expected outcome | SSE terminal `failed` with `code = "provider_rejected"`, `retry_safe: false`. Two `ai_attempt` rows: #1 `outcome 'retryable_failure'`, `error_code 'rate_limited'`; #2 `outcome 'terminal_failure'`, `error_code 'provider_rejected'`; both `tokens 0`, `cost 0`. `ai_request` `state 'Failed'`, `terminal_error_code 'provider_rejected'`. One `usage_event` `{ tokens: 0, cost: 0 }` — journaled even though nothing billable happened. DO credit with `partial: false` (`provider_rejected` consumesQuota `"Yes"` → full consume), `idempotencyState "failed"`; counters `requestsUsed 1, tokensUsed 0, costUsed 0, inFlight 0`. Envelope `result.finishReason = "provider_rejected"`; `attempts` entries carry the FakeAdapter raw bodies `{ payload: { fake: true, outcome: "retryable:rate_limited" | "terminal:provider_rejected" }, truncated: false }`. |
| Side effects | MUST: `partial` flag derived from `getTaxonomyEntry(code).consumesQuota !== "Yes"` in settleTerminal — `false` here vs `true` in S11-003/004; both attempt raw bodies land in the envelope in attempt order. MUST NOT: no retry after the terminal-classified error (classification `terminal` stops the chain); no success-path credit. |
| Code reference | ai-platform/src/worker.ts:493-543 — settleTerminal (partial derivation at L520); ai-platform/src/invocation/index.ts:320-329 — terminal classification via classifyFailure; ai-platform/src/provider/classify.ts:10-14 — classifyFailure; ai-platform/src/errors.ts:108-113 — provider_rejected consumesQuota "Yes" |

## Scenario S11-006 — Failed settlement: truncation exhaustion settles validation_failed under the ignoreBrokerSettlement single-credit guard

| Field | Content |
|-------|---------|
| ID | S11-006 |
| Journey setup | Fresh scenario; policy target `max_attempts: 1`. FakeAdapter seam scripted `["truncation"]` (result `usage { input: 10, output: 20 }`, `finishReason "length"`, text `"Partial output…"`). |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-006-<uuid>`; read SSE to end; drain background work. |
| Expected outcome | SSE terminal `failed` with `code = "validation_failed"` pushed by the worker (`pushFailedTerminal`) — the broker's own `handleFailed("validation_failed")` (wasTruncated) fires after `ignoreBrokerSettlement = true`, so its event/credit/journal are dropped. `ai_request` `state 'Failed'`, `terminal_error_code 'validation_failed'` (written by the worker's `recordTerminalState`, since the broker journal sink was suppressed). One `ai_attempt`: `outcome 'truncation'`, `tokens_in 10`, `tokens_out 20`, `cost 0.005`, `error_code` NULL (truncation records usage but no error code). One `usage_event` `{ tokens: 30, cost: 0.005 }` — accrued partial usage from the truncated result. DO: exactly one credit, from the worker, `partial: false` (`validation_failed` consumesQuota `"Yes"`), `idempotencyState "failed"`, usage `{ tokens: 30, cost: 0.005 }`. Envelope `result.finishReason = "validation_failed"`. |
| Side effects | MUST (double-credit guard): exactly one `usage_event` row and exactly one DO credit for the request even though both the broker (wasTruncated) and the worker (invokeResult not ok) reached a failing terminal; `creditedRequests[requestId]` written once. MUST NOT: broker's dropped credit must not appear (DO `tokensUsed` delta is exactly 30, not 60); no `completed` event ever emitted. |
| Code reference | ai-platform/src/worker.ts:898-904 — ignoreBrokerSettlement set before pushable.end; ai-platform/src/worker.ts:800-812 — brokerSink drop; ai-platform/src/worker.ts:826-857 — creditSink/journalTerminalSink drop; ai-platform/src/invocation/index.ts:749-754 — exhaustedViaTruncation → validation_failed; ai-platform/src/stream/index.ts:441-444 — wasTruncated guard |

## Scenario S11-007 — Failed settlement: broker prose guard fails a completed invocation (broker-credited, worker journals with skipCredit)

| Field | Content |
|-------|---------|
| ID | S11-007 |
| Journey setup | Fresh scenario; standard policy. FakeAdapter seam: success result with `usage { input: 10, output: 20 }` but empty relayed text (`finalContent.text ""`, no `text_delta` chunks), so the broker assembles `""` and `runFullGuardSet` returns `empty_output`. |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-007-<uuid>`; read SSE to end; drain background work. |
| Expected outcome | SSE terminal `failed` with `code = "validation_failed"` emitted by the broker (not the worker). Invocation itself succeeded (`invokeResult.ok`), so the worker takes the `brokerTerminal !== "completed"` branch with `skipCredit: true`: the broker's `handleFailed` already credited `partial: false`, `idempotencyState "failed"`, usage `{ tokens: 30, cost: 0.005 }` (accrued from the processed success before `pushable.end()`). `ai_request` `state 'Failed'`, `terminal_error_code 'validation_failed'` written by the broker's journalTerminalSink → `recordTerminalState`. One `ai_attempt` with `outcome 'success'`, `tokens 10/20`, `cost 0.005`, `error_code` NULL — a `success` attempt row under a `Failed` request is the correct profile here. One `usage_event` `{ tokens: 30, cost: 0.005 }`. Envelope `result` is the placeholder (`finishReason "validation_failed"`), not the provider result. |
| Side effects | MUST: exactly one credit (broker) and one `usage_event` (worker journal with `skipCredit: true`); `recordTerminalState` called exactly once (broker sink) — the worker does not rewrite state in this branch. MUST NOT: no second DO credit from the worker; no `completed` SSE event. |
| Code reference | ai-platform/src/worker.ts:992-1017 — broker-non-completed branch; ai-platform/src/stream/index.ts:289-327 — handleFailed; ai-platform/src/stream/index.ts:446-450 — runFullGuardSet at stream end; ai-platform/src/stream/prose-guards.ts:94-107 — empty_output; ai-platform/src/journal/index.ts:341-375 — recordTerminalState |

## Scenario S11-008 — Cancelled settlement: client disconnect during the provider invoke (zero usage)

| Field | Content |
|-------|---------|
| ID | S11-008 |
| Journey setup | Fresh scenario; standard policy. FakeAdapter seam: `invoke` waits on a 5 s timer and rejects `AbortError` on signal abort (SYS-7.3 shape). |
| Action | `POST /v1/requests` with `x-idempotency-key: s11-008-<uuid>` and an `AbortController` signal on the fetch; wait until the fake invoke is entered, then `controller.abort()`; drain background work. |
| Expected outcome | The SSE stream dies with the disconnect (broker emits terminal `cancelled` with `data.trace_id` synchronously on disconnect). `ai_request` `state 'Cancelled'`, `completed_at` set, `terminal_error_code` NULL (Cancelled never stamps a taxonomy code). One `ai_attempt` row: the in-flight invoke resolves to a caller-abort error which `processInvokeResult` terminal-classifies (`cancelled` retryable `"—"` → not retry-safe), so `outcome 'terminal_failure'`, `error_code 'cancelled'`, `tokens 0`, `cost 0`. Exactly one `usage_event` `{ tokens: 0, cost: 0 }` — cancelled requests always journal usage. DO: one credit from the broker's `handleCancel` with `partial: true` (`cancelled` consumesQuota `"Partially, recorded"`), `idempotencyState "cancelled"`, usage `{ tokens: 0, cost: 0 }` (no accrued usage, no streamed chars); idempotency entry state `cancelled`; `inFlight` back to 0. The worker's cancelled branch sees `brokerTerminal === "cancelled"` and re-journals with `skipCredit: true`. Envelope exists at the standard key; `result.finishReason = "cancelled"`. |
| Side effects | MUST: exactly one `usage_event` and one DO credit (broker); worker writes D1/R2 only. MUST NOT: `terminal_error_code` stays NULL; no `failed` event; no second credit when the worker's settleTerminal runs. |
| Code reference | ai-platform/src/worker.ts:925-957 — cancelled branch (skipCredit when brokerTerminal set); ai-platform/src/stream/index.ts:258-287 — handleCancel; ai-platform/src/invocation/index.ts:117-128 — createCancelledError; ai-platform/src/invocation/index.ts:320-329 — cancelled terminal-classified attempt record |

## Scenario S11-009 — Cancelled settlement: disconnect before the first provider attempt writes a zero-attempt journal

| Field | Content |
|-------|---------|
| ID | S11-009 |
| Journey setup | Fresh scenario; standard policy; unmodified FakeAdapter (the abort lands before the adapter is entered). |
| Action | `POST /v1/requests` with `x-idempotency-key: s11-009-<uuid>`; call `controller.abort()` immediately after dispatching the fetch (signal already aborted when the event source starts, so `onAbort` fires before/around invocation start); drain background work. |
| Expected outcome | `ai_request` `state 'Cancelled'`, `completed_at` set, `terminal_error_code` NULL. ZERO `ai_attempt` rows — `runInvocation` returns `createCancelledError()` at the pre-attempt `callerSignal?.aborted` check before any `recordAttempt`. Exactly one `usage_event` `{ tokens: 0, cost: 0 }` (reconciliation expects usage for Cancelled but not attempts). DO credit `partial: true`, `idempotencyState "cancelled"`, zero usage. Envelope exists with `attempts: []` and placeholder result `finishReason "cancelled"`. |
| Side effects | MUST: `usage_event` written even with no attempts; envelope still written (every terminal that reaches settlement gets exactly one object). MUST NOT: no `ai_attempt` insert; no provider traffic. Note: the abort-vs-invoke-entry timing is the determinant; if the abort lands after invoke entry the row profile of S11-008 results instead. |
| Code reference | ai-platform/src/invocation/index.ts:527-533 — pre-attempt abort check; ai-platform/src/worker.ts:870-877 — onAbort → broker.disconnect; ai-platform/src/worker.ts:931-945 — cancelled branch; ai-platform/src/journal/index.ts:378-434 — persistPostResponseDetail (zero-length attempts batch) |

## Scenario S11-010 — Cancelled settlement with accrued partial usage from a prior truncation

| Field | Content |
|-------|---------|
| ID | S11-010 |
| Journey setup | Fresh scenario; policy `standard@2` with TWO targets: target 1 `{ provider_id: "fake", model_id: "fake-v1", max_attempts: 1, timeout_ms: 30000 }`, target 2 same shape. FakeAdapter seam: first invoke returns `truncation` (usage 10/20, cost 0.005 accrued via `noteUsageFromResult`); second invoke hangs abort-aware (SYS-7.3 shape). |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-010-<uuid>`; wait until the second invoke is entered (fallback after target-1 truncation + `regenerating` emission), then abort; drain background work. |
| Expected outcome | `ai_request` `state 'Cancelled'`, `terminal_error_code` NULL. Two `ai_attempt` rows: #1 `outcome 'truncation'`, `tokens 10/20`, `cost 0.005`, `error_code` NULL; #2 `outcome 'terminal_failure'`, `error_code 'cancelled'`, zeros. One `usage_event` `{ tokens: 30, cost: 0.005 }` — partial credit uses the ACCRUED usage (`hasAccruedUsage` true), not the char estimate. DO credit from broker `handleCancel`: `partial: true`, `idempotencyState "cancelled"`, usage `{ tokens: 30, cost: 0.005 }`. Envelope `attempts` length 2; placeholder result `usage { input: 30, output: 0, cached: 0 }` (placeholder puts total tokens in `input`). |
| Side effects | MUST: `readPartialUsage` prefers accrued provider-reported usage over `estimateUsageFromStreamedChars`; SSE shows a `regenerating` event before the stream dies (fallback after partial stream). MUST NOT: no full (`partial: false`) credit; no validation_failed settlement despite the truncation (cancel wins because the abort precedes chain exhaustion). |
| Code reference | ai-platform/src/invocation/index.ts:480-499 — readPartialUsage/noteUsageFromResult; ai-platform/src/invocation/index.ts:658-661 — truncation accrues usage; ai-platform/src/worker.ts:931-957 — cancelled branch with partialUsage; ai-platform/src/stream/index.ts:274-281 — handleCancel credit input |

## Scenario S11-011 — Cancelled settlement prices streamed characters via estimateUsageFromStreamedChars

| Field | Content |
|-------|---------|
| ID | S11-011 |
| Journey setup | Fresh scenario; standard policy. FakeAdapter seam: `invoke` calls `options.onStreamChunk` with one `text_delta` of exactly 250 characters (`"x".repeat(250)`), then hangs abort-aware (never returns a result). |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-011-<uuid>`; wait until the chunk is relayed (invoke entered + small delay), then abort; drain background work. |
| Expected outcome | `ai_request` `state 'Cancelled'`. One `usage_event` with `tokens 250`, `cost 0.05` — `estimateUsageFromStreamedChars(250, "fake-v1")` treats streamed chars as OUTPUT tokens through `priceUsage`: `(250/1000)*0.2 = 0.05` (6-decimal exact). DO credit `partial: true`, `idempotencyState "cancelled"`, same usage. `ai_attempt`: one row `outcome 'terminal_failure'`, `error_code 'cancelled'`, `tokens_in 0`, `tokens_out 0`, `cost 0` (no provider result was processed, so the attempt row itself carries no usage — only the credit/usage_event do). SSE relayed one `text_delta` (`provisional: true`) before the terminal `cancelled`. |
| Side effects | MUST: the estimate flows through the named `priceUsage` helper with the chain entry's model (`fake-v1`) — no anonymous 0.001 formula; `usage_event.cost` equals the DO `costUsed` delta. MUST NOT: no accrued-usage path (result never processed → `hasAccruedUsage` false); no `completed` event despite streamed text. |
| Code reference | ai-platform/src/invocation/index.ts:480-488 — readPartialUsage streamedChars branch; ai-platform/src/pricing/index.ts:138-155 — estimateUsageFromStreamedChars; ai-platform/src/invocation/index.ts:511-515 — observingSink.emitStreamText counts chars; ai-platform/src/stream/index.ts:274-281 — handleCancel |

## Scenario S11-012 — Quota DO creditRPC rejects double credit and unknown requestIds

| Field | Content |
|-------|---------|
| ID | S11-012 |
| Journey setup | Fresh scenario as in S11-001. DO access seam: fetch the installation's GatewayObject stub directly (`env.DO.idFromName(installationId)` → `https://quota-do.internal/rpc`), the same transport `invokeCreditRpc` uses; `now` is injectable on the RPC body. |
| Action | (1) Complete S11-001's request. (2) POST `{ kind: "credit", installationId, requestId, requestReference, usage: { tokens: 30, cost: 0.005 }, partial: false }` for the SAME requestId a second time. (3) POST a credit for a never-admitted requestId `crypto.randomUUID()`. (4) POST `{ kind: "inspect" }` after each step. |
| Expected outcome | Step 2: `{ kind: "credit", ok: false, code: "unknown_request" }` — `creditedRequests[requestId]` blocks the double credit; counters UNCHANGED (`requestsUsed 1, tokensUsed 30, costUsed 0.005, inFlight 0`); idempotency entry stays `completed`; no error thrown. Through the `creditUsage` wrapper this maps to `{ ok: false, code: "unknown_request" }`. Step 3: same `unknown_request` response (no `admittedRequests` entry). Step 4: inspect shows exactly one `creditedRequests` entry and the counters above. D1 is untouched by these direct calls — `usage_event` count for the request stays 1 (the DO never writes `usage_event`; see Doc-drift). |
| Side effects | MUST: second credit is a pure no-op on counters and idempotency (the DO still persists state via `storage.put`); `blockConcurrencyWhile` serializes the two credits. MUST NOT: no negative `inFlight` (`Math.max(0, …)`); no counter movement on rejection; no D1 write of any kind from the DO. |
| Code reference | ai-platform/src/quota-do/index.ts:489-499 — creditedRequests/unknown_request guard; ai-platform/src/quota-do/index.ts:507-524 — counter application + creditedRequests mark; ai-platform/src/quota-do/index.ts:340-356 — markIdempotencyOnCredit; ai-platform/src/credit/index.ts:190-197 — wire response mapping; ai-platform/src/credit/index.ts:231-243 — CreditResult mapping |

## Scenario S11-013 — Idempotent replay after Completed produces no new settlement

| Field | Content |
|-------|---------|
| ID | S11-013 |
| Journey setup | S11-001 completed (ref REF0, request_id RID0, key `s11-001-<uuid>`). Snapshot `ai_attempt`/`usage_event` counts, envelope presence, and the `ai_request` row (`state`, `completed_at`, `updated_at`, `payload_pointer`). |
| Action | `POST /v1/requests` again with the SAME `x-idempotency-key: s11-001-<uuid>` and a fresh AAT (new `jti`); read SSE to end; drain background work. |
| Expected outcome | Stage 9 guard returns idempotent (DO idempotency state `completed`); SSE terminal `completed` with placeholder `data.result.finalContent = { text: "Prior request completed.", authoritative: true }`. ZERO new settlement: `ai_attempt` count, `usage_event` count, envelope object, and the full `ai_request` row are byte-identical to the snapshot (the terminal-immutable `WHERE state NOT IN ('Completed','Failed','Cancelled','AwaitingContext')` would no-op any stray terminal UPDATE). DO counters unchanged; no second credit (`creditUsage` is never invoked on the replay path). |
| Side effects | MUST: replay short-circuits in `replayIdempotentTerminal` — no routing, no invocation, no journal, no credit. MUST NOT: no new `ai_request` row (unique `request_reference`/idempotency dedupe at Stage 9); no R2 `put`; no DO state mutation beyond the admission read. |
| Code reference | ai-platform/src/worker.ts:607-640 — replayIdempotentTerminal; ai-platform/src/worker.ts:665-673 — idempotent accept branch; ai-platform/src/journal/index.ts:136-137 — TERMINAL_IMMUTABLE_WHERE; ai-platform/src/quota-do/index.ts:384-400 — admission idempotent outcome |

## Scenario S11-014 — Idempotent replay after Failed replays failed (internal_error body) with no new settlement

| Field | Content |
|-------|---------|
| ID | S11-014 |
| Journey setup | S11-003 failed (provider_unavailable; key `s11-003-<uuid>`). Snapshot D1/R2/DO as in S11-013. |
| Action | Re-POST with the same idempotency key; read SSE; drain. |
| Expected outcome | SSE terminal `failed` whose `data.code` is `internal_error` — the replay path does NOT recover the original `provider_unavailable` (the DO stores only the idempotency STATE `failed`, not the code). `retry_safe: true` (internal_error retryable "Yes"). Zero new settlement: counts, envelope, and `ai_request` row unchanged; `terminal_error_code` still `provider_unavailable` on the original row. DO counters unchanged. |
| Side effects | MUST: no credit, no journal, no new rows. MUST NOT: the replay must not emit `"Prior request completed."` (that placeholder is only for `completed`/`admitted` prior states); no second `usage_event` for RIDF. |
| Code reference | ai-platform/src/worker.ts:631-634 — replayIdempotentTerminal failed branch; ai-platform/src/quota-do/index.ts:340-356 — idempotency state failed persisted at credit; ai-platform/src/worker.ts:592-604 — pushFailedTerminal |

## Scenario S11-015 — Idempotent replay after Cancelled replays cancelled with no new settlement

| Field | Content |
|-------|---------|
| ID | S11-015 |
| Journey setup | S11-008 cancelled (key `s11-008-<uuid>`). Snapshot D1/R2/DO. |
| Action | Re-POST with the same idempotency key (no abort this time); read SSE; drain. |
| Expected outcome | SSE terminal `cancelled` (`data.trace_id` only) via `pushTerminalEvent(sink, …, "cancelled", "single_shot")`. Zero new settlement: `usage_event` count stays 1, `ai_attempt` count unchanged, envelope unchanged, `ai_request` still `Cancelled` with NULL `terminal_error_code`. DO idempotency entry remains `cancelled`; counters unchanged. |
| Side effects | MUST: replay does not re-run the broker or invocation (no provider traffic with the unmodified FakeAdapter queue). MUST NOT: no credit (a second credit would hit S11-012's `unknown_request` guard anyway); no state transition out of `Cancelled`. |
| Code reference | ai-platform/src/worker.ts:635-638 — replayIdempotentTerminal cancelled branch; ai-platform/src/adapter.ts:157-164 — pushTerminalEvent cancelled; ai-platform/src/quota-do/index.ts:384-400 — admission idempotent outcome |

## Scenario S11-016 — usage_event quota_weight sourced from manifest Economics.quotaWeight with fallback to 1

| Field | Content |
|-------|---------|
| ID | S11-016 |
| Journey setup | Registry seam (`setCapabilityRegistry(…, { replace: true })`, as the harness does): register two variant manifests cloned from `clinic.visit_summary@1.0.0` — (a) `clinic.visit_summary_heavy@1.0.0` with `Economics.quotaWeight: 3`; (b) `clinic.visit_summary_zero@1.0.0` with `Economics.quotaWeight: 0`. Both keep `Access.requiredCapabilityScope: "ai.visit_summary"` so the standard AAT passes Stage 9. Entitle the scenario with `allowed_capabilities` + grants for both variant ids. |
| Action | Two completed `POST /v1/requests` journeys, bodies with `capability_id` = each variant in turn (fresh idempotency keys). |
| Expected outcome | Both SSE-terminal `completed`. (a) `usage_event.quota_weight = 3`; (b) `quota_weight = 1` — `Number(0) || 1` fallback in buildPostResponseInput. All other columns match the S11-001 profile (`tokens 30`, `cost 0.005`, `period '2026-07'`). DO counters are weight-agnostic (`requestsUsed` increments by 1 per credit regardless of weight). |
| Side effects | MUST: `quota_weight` comes from the manifest at settlement time, not from entitlement or policy. MUST NOT: weight never propagates into DO counters or `ai_attempt`. |
| Code reference | ai-platform/src/worker.ts:439-451 — buildPostResponseInput (`Number(manifest.Economics.quotaWeight) || 1`); ai-platform/src/journal/index.ts:406-425 — usage_event insert; ai-platform/manifests/published/clinic.visit_summary@1.0.0.json:67-72 — Economics.quotaWeight 1 |

## Scenario S11-017 — usage_event period derived from admission-time entitlement period_start; DO period reset on credit

| Field | Content |
|-------|---------|
| ID | S11-017 |
| Journey setup | (a) Fresh scenario entitled with `period_start: "2026-07-01T00:00:00.000Z"` while wall clock is September 2026. (b) DO RPC seam as in S11-012 with injectable `now`. |
| Action | (a) Complete one request; inspect `usage_event.period`. (b) Direct DO journey: admission with entitlement period A (`2026-07-01`/`2026-08-01`), then a credit for that requestId carrying an entitlement snapshot whose `period_bounds` are period B (`2026-08-01`/`2026-09-01`) — the period-boundary-between-admit-and-credit case; inspect after each call. |
| Expected outcome | (a) `usage_event.period = '2026-07'` — `periodFromIso(period_start)` slices `YYYY-MM` from the ADMISSION snapshot, never wall-clock at credit. (b) `maybeResetPeriod` fires inside creditRPC because bounds differ: `periodBounds` becomes period B, `requestsUsed`/`tokensUsed`/`costUsed` reset to 0 BEFORE the credit's usage is applied (post-credit counters exactly the credited usage), and `inFlight` is preserved across the reset (1 → decremented to 0 by the credit itself). Credit returns `ok: true`. |
| Side effects | MUST: worker always sends the admission entitlement snapshot with the credit (production path keeps DO and D1 in the same period); the reset preserves `inFlight` only. MUST NOT: D1 `usage_event.period` must not follow the DO reset — it is fixed at admission; no period string longer than 7 chars. |
| Code reference | ai-platform/src/worker.ts:280-282 — periodFromIso; ai-platform/src/worker.ts:912-921 — periodStart from guard.entitlementSnapshot; ai-platform/src/quota-do/index.ts:257-274 — maybeResetPeriod; ai-platform/src/quota-do/index.ts:500-505 — entitlement resolution + reset on credit |

## Scenario S11-018 — Envelope attempts[] raw body capped at 16 KB with truncated flag

| Field | Content |
|-------|---------|
| ID | S11-018 |
| Journey setup | Fresh scenario; standard policy. FakeAdapter seam: success result plus `rawBody = captureRawProviderBody("".padStart(40_000, "…"))` — i.e. route a > 16 KiB provider body through the real `captureRawProviderBody` (the production adapter path via `withRawBody`). |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-018-<uuid>`; read SSE to `completed`; drain; fetch `request/<request_id>/envelope` from R2. |
| Expected outcome | Settlement identical to S11-001 except `envelope.attempts[0].truncated === true` and `attempts[0].payload` is a STRING of at most 16 384 bytes (first 16 KiB of the body, decoded after the byte slice — not parsed JSON). The envelope itself remains valid JSON with the four canonical top-level keys; `ai_attempt` row is unaffected (cap applies to the R2 diagnostic copy only). |
| Side effects | MUST: cap is per-attempt raw body (`ENVELOPE_RAW_BODY_BYTE_LIMIT = 16 * 1024`), applied at capture time; `truncated: false` exactly when `byteLength <= 16384`. MUST NOT: no second envelope object for the overflow; the cap never changes `ai_attempt` columns or credit usage. |
| Code reference | ai-platform/src/provider/raw-body.ts:6-27 — ENVELOPE_RAW_BODY_BYTE_LIMIT/captureRawProviderBody; ai-platform/src/journal/index.ts:183-191 — buildEnvelope (attempts map to rawBody); ai-platform/src/worker.ts:362-375 — buildAttemptInput rawBody passthrough |

## Scenario S11-019 — Envelope stores a non-JSON provider raw body as a string payload

| Field | Content |
|-------|---------|
| ID | S11-019 |
| Journey setup | Fresh scenario; standard policy. FakeAdapter seam: success result with `rawBody = captureRawProviderBody("502 Bad Gateway\nupstream connect error")` — a sub-16-KiB body that is not JSON. |
| Action | `POST /v1/requests`, `x-idempotency-key: s11-019-<uuid>`; read to `completed`; drain; fetch the envelope. |
| Expected outcome | `envelope.attempts[0] = { payload: "502 Bad Gateway\nupstream connect error", truncated: false }` — the JSON.parse failure branch stores the raw text verbatim. All S11-001 D1/DO assertions still hold (parse failure is envelope-only). |
| Side effects | MUST: `truncated` stays `false` for parse failures (truncation is byte-cap-only); payload type is string, not object. MUST NOT: no throw from capture (parse errors are swallowed into the string form); no settlement failure from an unparseable body. |
| Code reference | ai-platform/src/provider/raw-body.ts:18-23 — parse-or-string branch; ai-platform/src/journal/index.ts:183-191 — buildEnvelope |

## Scenario S11-020 — Failed and cancelled envelopes carry the placeholder canonical result

| Field | Content |
|-------|---------|
| ID | S11-020 |
| Journey setup | Reuse the settled requests from S11-003 (failed, zero usage), S11-006 (failed, accrued 30/0.005), and S11-008 (cancelled, zero usage). |
| Action | Fetch `request/<request_id>/envelope` for each of the three request ids from R2; diff `result` against the canonical field manifest. |
| Expected outcome | Each envelope has exactly the keys `context`, `prompt`, `attempts`, `result` — one object per request, written on EVERY terminal, never a sibling key. `result` is the placeholder: `finalContent { type: "text", text: "" }`, `usage { input: <totalTokens>, output: 0, cached: 0 }` (0 for S11-003/008; 30 for S11-006 — total tokens land in `input`), `providerModel { provider: "", model: "" }`, `finishReason` = the taxonomy code (`"provider_unavailable"` / `"validation_failed"` / `"cancelled"`), `providerRequestId ""`, `timing { queue_ms: 0, provider_ms: 0, total_ms: 0 }`. All six canonical result keys present, no extras. `GET /v1/requests/{ref}` for the failed refs returns `{ state: "Failed", terminal_error_code }` WITHOUT the envelope; cancelled returns `{ state: "Cancelled" }`. |
| Side effects | MUST: identical envelope key shape across terminals; `payload_pointer` set on all three rows. MUST NOT: provider result never leaks into a failed/cancelled envelope; no `envelope-failed` sidecar object. |
| Code reference | ai-platform/src/worker.ts:413-425 — placeholderTerminalResult; ai-platform/src/worker.ts:530-541 — settleTerminal journal input; ai-platform/src/contracts/canonical.ts:22-29 — result field manifest; ai-platform/src/journal/index.ts:179-191 — envelopeKey/buildEnvelope |

## Scenario S11-021 — Grace-admitted settlement attaches usage to the pending grace queue row and journals despite DO outage

| Field | Content |
|-------|---------|
| ID | S11-021 |
| Journey setup | [SEED] Insert a pending `grace_admission_queue` row (`status 'pending'`, `grace_request_id` = GRID, `request_reference` = REF, `idempotency_key`, `jti`, `entitlement_json`) — the Stage 8 grace-admission path that created it belongs to the admission stage's chapter; seeding isolates Stage 11. DO seam: a stub `DurableObjectNamespace` whose stub `fetch` throws (DO down), per the `test/admission-credit.test.ts` pattern. |
| Action | Call `creditUsage({ installationId, requestId: GRID, requestReference: REF, usage: { tokens: 30, cost: 0.005 }, partial: false, entitlement: <snapshot> }, { DO: stubDown, DB: env.DB })`; then run the S11-001 journal path (`writeSettlementJournal` via a settleTerminal-equivalent call) for the same request. |
| Expected outcome | `grace_admission_queue` row updated: `usage_tokens 30`, `usage_cost 0.005`, `partial 0` (matched by `grace_request_id`; the fallback match by `request_reference` is exercised by a second call keyed on REF when the id match misses). `creditUsage` resolves `{ ok: false, code: "unavailable" }` — and settlement CONTINUES: `settleTerminal`/`settleCompletedRequest` never inspect the credit result, so `ai_attempt` + `usage_event` + envelope + `payload_pointer` are all written exactly as in S11-001. The DO-side credit is deferred to cron `reconcileGraceUsage` (Stage X / cron chapter), which later credits the re-admitted requestId with the attached usage. |
| Side effects | MUST: attach runs BEFORE the DO RPC; journal writes proceed on credit failure; exactly one `usage_event`. MUST NOT: no exception propagation from a down DO; no DO counter change while down; no second attach when both id and reference miss (result `false` ignored). |
| Code reference | ai-platform/src/credit/index.ts:200-243 — creditUsage (attach then RPC); ai-platform/src/admission/index.ts:382-404 — attachGraceUsage; ai-platform/src/worker.ts:513-543 — settleTerminal ignoring CreditResult; ai-platform/src/credit/index.ts:255-343 — reconcileGraceUsage (consumer of the attach) |

## Scenario S11-022 — record_ai_acceptance happy path writes acceptance, audit log, and merged rpc_success

| Field | Content |
|-------|---------|
| ID | S11-022 |
| Journey setup | Local Supabase with all migrations. Seeded clinic: organization ORG, branch BR, visit V (`is_deleted = false`, `updated_at` = T0), user U in ORG with `visits.edit_soap` permission and branch scope covering BR. Registry row present from the migration: `('visit_clinical_notes', 'save_visit_documentation', 'visit_clinical_notes')`. A completed AI request reference from the platform side in the valid format, e.g. `'7K2M-9XQD'`. Authenticated JWT for U with org claim ORG. |
| Action | `select public.record_ai_acceptance('7K2M-9XQD', 'visit_clinical_notes', '{"p_visit_id": "<V>", "p_expected_updated_at": "<T0>", "p_plan": "Rest and hydration. AI-drafted summary accepted."}'::jsonb)` (via PostgREST RPC as U). |
| Expected outcome | `rpc_result.success = true`; `data` = the domain payload (`visit_id`, `updated_at`) merged with `acceptance_id` (uuid), `table_name 'visit_clinical_notes'`, `record_id` = V's uuid (extracted from domain `data->>'visit_id'`), `audit_log_id`. Persisted: one `public.visit_clinical_notes` row for V with `plan` set (delegated domain write); one `public.audit_log` row `action 'ai.acceptance_record'`, `table_name 'visit_clinical_notes'`, `record_id` = V, `new_data_json = {"ai_request_reference": "7K2M-9XQD", "acceptance_id": <same uuid>}`, `user_id` = U, `organization_id` = ORG; one `public.ai_accepted_output` row `id` = acceptance_id, `organization_id` ORG, `branch_id` = BR (looked up from `public.visits`), `table_name 'visit_clinical_notes'`, `record_id` = V, `ai_request_reference '7K2M-9XQD'`, `accepted_by` = U, `audit_log_id` = the audit row. Note the provenance records the VISIT id under `table_name 'visit_clinical_notes'` (domain returns `visit_id`, not the note id). |
| Side effects | MUST: single transaction — domain write, audit insert, acceptance insert commit or roll back together; `accepted_at` defaults to `now()`. MUST NOT: no write to any platform (D1) table; no second domain invocation; registry table never written by the RPC. |
| Code reference | backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:144-274 — auth_internal.record_ai_acceptance; backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:209-217 — record_id extraction; backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:229-263 — audit + acceptance inserts; backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql:425 — domain success payload |

## Scenario S11-023 — record_ai_acceptance rejects malformed request references

| Field | Content |
|-------|---------|
| ID | S11-023 |
| Journey setup | Same seeded clinic as S11-022; no other setup needed (the check runs before any lookup). |
| Action | Three calls as U: (a) `record_ai_acceptance(NULL, 'visit_clinical_notes', '{}')`; (b) reference `'7k2m-9xqd'` (lowercase — outside Crockford base32 alphabet); (c) reference `'7K2M9XQD'` (missing hyphen). |
| Expected outcome | All three return `success = false`, `error_code = 'INVALID_INPUT'`, `error_message = 'Request reference must use the standard format.'` The format gate is `~ '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$'`. Zero writes: no domain invocation, no `audit_log`, no `ai_accepted_output` (verify by counts before/after). |
| Side effects | MUST: pure validation failure, evaluated first (before registry, duplicate, and org checks). MUST NOT: no delegated domain call — `visit_clinical_notes` unchanged. |
| Code reference | backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:164-167 — reference format check |

## Scenario S11-024 — record_ai_acceptance rejects unregistered acceptance targets

| Field | Content |
|-------|---------|
| ID | S11-024 |
| Journey setup | Same seeded clinic as S11-022. |
| Action | `record_ai_acceptance('7K2M-9XQD', 'billing_invoices', '{"p_visit_id": "<V>", "p_expected_updated_at": "<T0>"}')` — `billing_invoices` is not in `ai_internal.acceptance_targets`. |
| Expected outcome | `success = false`, `error_code 'INVALID_INPUT'`, `error_message 'Acceptance target is not registered.'` Zero writes anywhere (registry `SELECT … INTO v_target` finds nothing and returns before the duplicate check, org check, and domain dispatch). |
| Side effects | MUST: the registry is the ONLY source of invocable domain functions — even a real public function name cannot be reached without a registry row (defense in depth with the wrapper-gate revokes). MUST NOT: no dynamic SQL executed. |
| Code reference | backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:169-176 — registry lookup; backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:14-17 — seeded registry row |

## Scenario S11-025 — record_ai_acceptance rejects duplicate acceptance before any domain write

| Field | Content |
|-------|---------|
| ID | S11-025 |
| Journey setup | S11-022 completed (acceptance exists for `('7K2M-9XQD', 'visit_clinical_notes')`). A SECOND visit V2 in the same branch exists. |
| Action | (a) Repeat S11-022's exact call (same reference, same visit). (b) Same reference `'7K2M-9XQD'` and target, but `p_visit_id` = V2 — a DIFFERENT record of the same table. |
| Expected outcome | Both return `success = false`, `error_code 'INVALID_INPUT'`, `error_message 'This AI output was already accepted for this record.'` Case (b) is rejected by the pre-check even though the `ai_accepted_output_unique_domain_reference` UNIQUE constraint is on `(table_name, record_id, ai_request_reference)` and would have allowed it — the foreseeable-duplicate guard is `(ai_request_reference, table_name)` only (see Doc-drift). Zero new rows in both cases; the domain function is never invoked (no `STALE_DOCUMENTATION` risk, no note mutation). |
| Side effects | MUST: duplicate check runs BEFORE the org-context check and before `invoke_acceptance_domain_rpc`; exactly one `ai_accepted_output` and one `audit_log` row for the reference after both calls. MUST NOT: no partial second acceptance; no exception from the UNIQUE constraint (the pre-check fires first). |
| Code reference | backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:178-190 — duplicate pre-check; backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:36-38 — unique constraint |

## Scenario S11-026 — record_ai_acceptance requires organization context

| Field | Content |
|-------|---------|
| ID | S11-026 |
| Journey setup | Seeded clinic as S11-022, but the caller's JWT carries NO organization claim (`public.jwt_organization_id()` returns NULL) — e.g. a service-key-shaped or malformed session for user U. |
| Action | `record_ai_acceptance('8N3P-QWRA', 'visit_clinical_notes', '{"p_visit_id": "<V>", "p_expected_updated_at": "<T0>", "p_plan": "x"}')`. |
| Expected outcome | `success = false`, `error_code 'FORBIDDEN'`, `error_message 'Organization context is required.'` The check sits AFTER the duplicate check and BEFORE the domain dispatch, so no domain write can commit without provenance. Zero writes: `visit_clinical_notes`, `audit_log`, `ai_accepted_output` all unchanged. |
| Side effects | MUST: fail before `invoke_acceptance_domain_rpc`; the domain function's own FORBIDDEN path is never reached. MUST NOT: no audit row without org (audit insert requires `v_org_id`). |
| Code reference | backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:192-197 — org-context gate |

## Scenario S11-027 — record_ai_acceptance passes through delegated domain failures unchanged

| Field | Content |
|-------|---------|
| ID | S11-027 |
| Journey setup | Seeded clinic as S11-022; visit V's `updated_at` has advanced to T1 (someone edited the visit after the client read T0). Fresh reference `'9P4R-SXTC'`. |
| Action | (a) `record_ai_acceptance('9P4R-SXTC', 'visit_clinical_notes', '{"p_visit_id": "<V>", "p_expected_updated_at": "<T0>", "p_plan": "stale edit"}')`. (b) Same shape with `p_visit_id` = a random uuid that matches no visit. |
| Expected outcome | (a) `success = false`, `error_code 'STALE_DOCUMENTATION'` with the domain's exact message — the `rpc_result` from `save_visit_documentation` is returned VERBATIM (no re-wrapping, no acceptance-specific code). (b) `success = false`, `error_code 'NOT_FOUND'`. In both cases: zero `ai_accepted_output` / `audit_log` rows for the reference; the domain function itself made no mutation (its own guards fired first). |
| Side effects | MUST: pass-through preserves the domain `error_code`/`error_message`/`data` triple; the acceptance layer adds nothing on failure. MUST NOT: no `acceptance_id` generated-or-persisted on failure (gen_random_uuid is only called after domain success). |
| Code reference | backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:199-205 — domain dispatch + failure return; backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql:388-390 — STALE_DOCUMENTATION; backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql:362-364 — NOT_FOUND |

## Scenario S11-028 — record_ai_acceptance rolls back everything when the domain write returns no record id

| Field | Content |
|-------|---------|
| ID | S11-028 |
| Journey setup | [SEED] Register a test target: insert `('test_no_record_id', 'test_domain_no_id', 'visit_clinical_notes')` into `ai_internal.acceptance_targets` and create `public.test_domain_no_id() returns rpc_result` as a function that performs a real write (e.g. inserts an audit_log row) then returns `rpc_success('{}'::jsonb)` — no `record_id`/`visit_id`/`id` key. Justification: every shipped domain function returns an id, so the no-id branch is unreachable with the production registry alone. |
| Action | `record_ai_acceptance('ABCD-EFGH', 'test_no_record_id', '{}')` inside a transaction; capture the raised error; then count rows. |
| Expected outcome | The call raises `Domain write did not return a record id.` (RAISE EXCEPTION — NOT an `rpc_error` return) so the PostgREST transaction aborts: the domain function's own write, and any acceptance/audit rows, ALL roll back. Post-rollback counts: zero `ai_accepted_output` for `'ABCD-EFGH'`, zero `audit_log` rows from either the domain stub or the acceptance layer. |
| Side effects | MUST: exception (not rpc_error) so the delegated write cannot commit orphaned; comment in code requires propagation. MUST NOT: no partial provenance; no `rpc_result` returned to the client on this path (HTTP 400 from PostgREST with the exception payload). |
| Code reference | backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:209-217 — record_id extraction + raise; backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:227-228 — propagation comment |

## Scenario S11-029 — record_ai_acceptance wrapper gate and ai_accepted_output RLS visibility

| Field | Content |
|-------|---------|
| ID | S11-029 |
| Journey setup | S11-022 completed (acceptance row exists in ORG/BR). A second organization ORG2 with user U2 (no branch overlap). |
| Action | (a) As authenticated U: `select auth_internal.record_ai_acceptance('7K2M-9XQD', 'visit_clinical_notes', '{}')` and `select auth_internal.invoke_acceptance_domain_rpc('save_visit_documentation', '{}')` directly. (b) As U2 (org claim ORG2): `select * from public.ai_accepted_output where ai_request_reference = '7K2M-9XQD'`. (c) As U: same SELECT. (d) As U with a JWT whose branch ids exclude BR: same SELECT against a row whose `branch_id` is BR. |
| Expected outcome | (a) Both fail with `permission denied for function …` — EXECUTE revoked from PUBLIC/authenticated/anon on both `auth_internal` functions; only `public.record_ai_acceptance` is executable by authenticated. (b) Zero rows (RLS: `organization_id = jwt_organization_id()` fails). (c) One row. (d) Zero rows (branch clause: `branch_id IS NULL OR branch_id = ANY (jwt_branch_ids())`). |
| Side effects | MUST: the registry table `ai_internal.acceptance_targets` is also unreadable by authenticated (SELECT granted to postgres only). MUST NOT: no authenticated path to the dynamic dispatcher; no cross-org visibility of acceptance provenance. |
| Code reference | backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:294-299 — wrapper-gate revokes/grants; backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:46-58 — RLS policy + grant; backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:11-13 — registry grants |

## Doc-drift observations

1. **Credit RPC fields (doc self-contradiction).** `13-stage-11-terminal-settlement.md` §3 lists `jti` and `idempotencyKey` as fields of the `kind: credit` RPC; `CreditRequest` in `src/quota-do/index.ts` has neither (they exist only on `AdmissionRequest`). The doc's own §10.3.6 later states the correct behavior ("`jti` was consumed at admit; credit finds the reservation by `requestId`"). Follow the code.
2. **Terminal `timeout` is unreachable.** The orientation doc §9 table and the chapter briefing list `timeout` as a failed-settlement taxonomy with `partial: true`. In code, `timeout` is retryable-classified (`classifyFailure`), so it only ever appears as an `ai_attempt.outcome = 'timeout'` / `error_code = 'timeout'`; chain exhaustion always settles the request as `provider_unavailable` (`runInvocation` L755-761). `ai_request.terminal_error_code = 'timeout'` cannot be produced by the current invocation path (worker would honor it via `isTaxonomyCode` if it ever arose). Covered as S11-004.
3. **Cancelled-during-invoke writes an attempt row.** Doc §9 says cancelled requests have `ai_attempt` "only when invocation recorded attempts (abort before the first provider call is expected to have none)". Code terminal-classifies the caller-abort error (`cancelled` retryable `"—"` → not retry-safe), so an abort DURING an in-flight invoke records `outcome 'terminal_failure', error_code 'cancelled'` (S11-008). Only a pre-attempt abort yields zero rows (S11-009).
4. **usage_event is never written by the Quota DO.** The chapter briefing grouped "usage_event insertion" under `quota-do`; in code `usage_event` is written only by `persistPostResponseDetail` (journal, D1). The DO mutates only its own storage; `creditUsage`'s only D1 touch is the grace-queue attach. Scenarios S11-001/S11-012 assert this split.
5. **Replay of a failed request loses the original code.** `replayIdempotentTerminal` emits `failed` with `internal_error` for any prior `failed` state (worker.ts L631-634); the DO idempotency entry stores the state, not the taxonomy code. The doc's "typically `internal_error` on the replay frame" is exact, and S11-014 pins it.
6. **Duplicate pre-check is broader than the UNIQUE constraint.** `record_ai_acceptance` rejects on `(ai_request_reference, table_name)` alone, while `ai_accepted_output_unique_domain_reference` is `(table_name, record_id, ai_request_reference)` — the same AI output cannot be accepted into two different records of the same table even though the constraint would allow it (S11-025 case b). Not documented in the migration comment beyond "foreseeable duplicate".
7. **Provenance records the visit id under `table_name 'visit_clinical_notes'`.** `record_id` comes from domain `data->>'visit_id'` (the visit uuid), not the clinical-note row id; `branch_id` is then resolved from `public.visits`. Anyone joining `ai_accepted_output.record_id` to `visit_clinical_notes.id` will miss (S11-022).
8. **Worker cancelled branch's non-skipCredit sub-path is defensive.** `brokerTerminal === undefined` after a cancel is effectively unreachable via client disconnect because `broker.disconnect()` synchronously runs `handleCancel` → `journalTerminalSink`, which sets `brokerTerminal` before the worker checks it (worker.ts L931-945, stream/index.ts L472-488). No scenario can reach the credit-without-skipCredit cancelled path through `POST /v1/requests` without fault injection inside the broker sinks.
9. **`repair` attempt outcome unreachable for `clinic.visit_summary`.** The doc §5 lists `repair` among legal outcomes; the published manifest sets `repairPolicy.allowed: false, maxAttempts: 0`, and repair orchestration is a Stage 10 concern. No Stage 11 settlement scenario can produce a `repair` row with the published capability.
10. **Doc §3 credit-field table otherwise matches code** (`partial` derivation, `idempotencyState` default `partial ? "cancelled" : "completed"`, entitlement snapshot always sent, period sharing) — verified by S11-001/005/017.

## Non-automatable notes

1. **DO outage at credit time after a healthy (non-grace) admission.** `creditUsage` returns `{ ok: false, code: "unavailable" }` and settlement journaling proceeds, leaking `inFlight` until the 2 h abandoned-admission sweep flips the idempotency entry to `failed`. A full `POST /v1/requests` journey cannot force this: `@cloudflare/vitest-pool-workers` gives one `env.DO` binding per suite, and taking it down mid-request requires fault injection inside the DO fetch path. S11-021 covers the same code at component level with a stubbed namespace; the end-to-end variant stays manual.
2. **Ephemeral-horizon sweeps (2 h).** `creditedRequests`/`idempotency` expiry and the abandoned-admission sweep (`sweepAbandonedAdmissions` → idempotency `failed`) are wall-clock. The DO RPC accepts an injectable `now`, so sweep behavior is exercisable via direct `GatewayObject` RPCs with `now + 7_200_000` offsets (as in S11-012's seam), but never through the public HTTP journey.
3. **Journal write failure is log-only.** `writePostResponseDetail` catches and logs `stage16_post_response_detail_failed`; a D1 batch or R2 put failure leaves the request terminal with missing rows (later flagged by cron reconciliation) and does not change the SSE outcome. Forcing a D1/R2 fault mid-settlement is not available in the pool; verify by fault injection in a manual run if needed.
4. **R2/D1 write-order interleaving.** The order batch → R2 put → `payload_pointer` UPDATE is asserted by S11-001's final state, but a crash between steps (e.g. pointer set without object, or object without pointer → `GET` returns `Completed` with `resultMissing`) requires process-kill fault injection.
5. **Real-provider settlement (deepseek / gemini).** All journeys use the FakeAdapter seam; live HTTP transport settlement against real providers belongs to `test/eval/live-smoke.test.ts` and manual verification, not this catalog.
6. **Supabase exception-path HTTP shape.** S11-028's raised exception surfaces through PostgREST as an HTTP error rather than an `rpc_result`; the exact status/body mapping is a PostgREST behavior verified manually against local Supabase, not asserted in the migration.
