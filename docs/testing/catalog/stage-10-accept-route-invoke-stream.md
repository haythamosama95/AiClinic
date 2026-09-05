# Stage 10 — Accept, route, invoke, stream

Source files read:
- `ai-platform/src/worker.ts` (`runFreshEventSource`, `createProductionEventSource`, `replayIdempotentTerminal`, `createPushableInvocationEvents`, `resolveProviderPort`, `attemptsForFailedSettlement`, `settleTerminal`, `settleCompletedRequest`, `PRODUCTION_GUARD_THRESHOLDS`, `HEARTBEAT_INTERVAL_MS`)
- `ai-platform/src/router/index.ts` (`selectCandidateChain`, `filterTargets`, `preloadRoutingPolicyForInstallation`)
- `ai-platform/src/invocation/index.ts` (`runInvocation`, `invokeWithTimeout`, `processInvokeResult`, `computeJitteredBackoff`, `sleepWithinDeadline`, error factories)
- `ai-platform/src/provider/classify.ts` (`classifyFailure` — taxonomy retryability → retryable/terminal)
- `ai-platform/src/provider/port.ts`, `ai-platform/src/provider/wiring.ts` (wired ids: `deepseek`, `gemini`)
- `ai-platform/src/provider/fake.ts` (`FakeAdapter` script vocabulary: `success`, `truncation`, `malformed`, `retryable:<code>`, `terminal:<code>`; empty queue → `internal_error`)
- `ai-platform/src/provider/deepseek.ts`, `ai-platform/src/provider/gemini.ts` (missing-key → terminal `provider_rejected`; HTTP/SSE classification)
- `ai-platform/src/provider/fetch-transport.ts`, `ai-platform/src/provider/readable-body.ts`, `ai-platform/src/provider/raw-body.ts` (16 KiB raw-body cap)
- `ai-platform/src/stream/index.ts` (`createStreamBroker`, `createChunkSourceFromInvocationEvents`)
- `ai-platform/src/stream/prose-guards.ts` (`checkIncrementalGuards`, `runFullGuardSet`)
- `ai-platform/src/stream/structured.ts` (`createStructuredStreamBroker` — **never wired in `worker.ts`**)
- `ai-platform/src/validate/index.ts`, `ai-platform/src/validate/phases.ts` (`validateAndRepair` — no live caller)
- `ai-platform/src/contracts/canonical.ts`, `ai-platform/src/wall-clock-sleeper.ts`, `ai-platform/src/pricing/index.ts`
- `ai-platform/src/adapter.ts` (`handleAdapterRequest`, `pushTerminalEvent`, disconnect wiring)
- `ai-platform/src/journal/index.ts` (`persistRoutingDecision`, `recordTerminalState`, `writePostResponseDetail`)
- `ai-platform/src/prompt/composer.ts` (`leakNeedlesFromSystemInstruction` — 48-char opening/interior/ending slices)
- `ai-platform/src/errors.ts` (taxonomy table), `ai-platform/migrations/20260731120000_platform_schema.sql` (`ai_attempt`/`usage_event` DDL)
- `ai-platform/control/routing-policy/platform-default/1.json`, `ai-platform/control/pricing/platform-default/1.json`
- `ai-platform/test/system/harness.ts`, `ai-platform/test/worker-request-orchestrator.test.ts` (established harness seams)
- Orientation only: `docs/architecture/ai-platform/data-journey/12-stage-10-accept-route-invoke-stream.md`

Conventions used throughout:
- Harness: `@cloudflare/vitest-pool-workers`, `SELF.fetch` against the real worker (`src/worker.ts`), real D1 migrations, real R2/DO, per `test/system/harness.ts`. Gateway origin `https://ai-gateway.test`; operator bearer `test-operator-bearer-token`.
- **Setup FRESH** (referenced by most scenarios): Stage 3 enrollment happy path for a new installation; Stage 4 entitle happy path (`period_start 2026-07-01`, `soft_threshold 0.8`, grant `clinic.visit_summary@1.0.0`); Stage 5 policy publish/promote happy path for policy id `standard` with the scenario's document; AAT minted by the test helper (`role: "clinician"`, scopes `["ai.visit_summary","ai.access"]`, `ver "1"`); POST body = `visitSummaryInvokeBody` (`capability_id "clinic.visit_summary"`, `user_intent "Summarize the visit."`, context with `visit.chief_complaint@v1`). `isolateConfigCache.clear()` after every control-plane write. Stage 9 guard fresh success is a precondition for every scenario here; guard rejections are Stage 9's chapter.
- **Provider seam**: production `resolveProviderPort` (worker.ts:L343-L359) maps `provider_id: "fake"` → `new FakeAdapter(["success"])`, wired ids (`deepseek`, `gemini`) → real adapters over `createFetchTransport()`, and any unknown id → `new FakeAdapter(["terminal:provider_unavailable"])`. Tests script behavior by `vi.spyOn(fakeMod, "FakeAdapter")` / subclassing `FakeAdapter.prototype.invoke` — the established seam in `test/worker-request-orchestrator.test.ts` (T16/T21/`prose_safety_markers_on_live_path`). No other provider double is used.
- The test pool env has **no** `DEEPSEEK_API_KEY` / `GEMINI_API_KEY`; wired-id invokes fail before HTTP with terminal `provider_rejected` (`missing_api_key`).
- SSE wire notes (code-authoritative): `text_delta.data` is `{text, sequence, provisional: true}` and does **not** contain `trace_id` (the broker puts `trace_id` on the event wrapper; `encodeSseEvent` serializes only `event.data`). All other events carry `trace_id` inside `data`. `failed.data` is the full taxonomy body `{code, request_reference, trace_id, retry_safe}`.
- Pricing: `fake-v1` rates 0.1/0.2 per 1K input/output (`control/pricing/platform-default/1.json`). Fake success usage is 10 in / 20 out → tokens 30, cost 0.005.
- SSE event-type → scenario map: `accepted` → every scenario (asserted explicitly in S10-001); `text_delta` → S10-001; `regenerating` → S10-029/030/031; `heartbeat` → S10-033; `completed` → S10-001, replay S10-016/017; `failed` → S10-003/004/005/009/020–028/032/034, replay S10-018; `cancelled` → S10-013/014/015, replay S10-019; `context_requested` → never emitted for `single_shot` (see Non-automatable notes); `progress` / `partial_structured` → structured broker only, never wired (see Doc-drift observations).

## Scenario S10-001 — Single-target chain success: accepted → text_delta → completed with full settlement

| Field | Content |
|-------|---------|
| ID | S10-001 |
| Journey setup | Setup FRESH. Policy document: catch-all rule, one target `{provider_id: "fake", model_id: "fake-v1", max_attempts: 1, timeout_ms: 30000, features: {structured_output: false, min_context_window: 32000, languages: ["en"], latency_class: "standard", cost_class: "standard"}}` (harness `fakePolicyDocument("standard","1")`). |
| Action | `POST /v1/requests` with the AAT, `x-idempotency-key: "s10-001-idem"`, `x-trace-id: "s10-001-trace"`, `x-capability-version: 1.0.0`. Read the SSE stream to completion, then wait ~200 ms for `waitUntil` settlement. |
| Expected outcome | HTTP 200, `content-type: text/event-stream`. Exact event sequence: (1) `accepted` with `data.request_reference` matching `XXXX-XXXX`, `data.trace_id: "s10-001-trace"`, no `degraded_notice`; (2) `text_delta` with `data.text: "Fake adapter summary."`, `data.sequence: 0`, `data.provisional: true`, and **no** `trace_id` inside `data`; (3) `completed` with `data.result.finalContent.text: "Fake adapter summary."`, `data.result.finalContent.authoritative: true`, `data.trace_id: "s10-001-trace"`. No `heartbeat` (sub-second invoke vs 15 s interval), no `regenerating`, no second terminal. |
| Side effects | D1 `ai_request`: one row, `state Completed`, `completed_at` set, `terminal_error_code NULL`, `routing_tier "standard"`, `routing_decision` JSON non-null (`policy_id "standard"`, `rule_id "catch-all"`, `chain` length 1, `excluded []`, no `max_parallel_attempts` key), `payload_pointer = request/<request_id>/envelope`. D1 `ai_attempt`: exactly 1 row — `attempt_no 1`, `provider "fake"`, `model "fake-v1"`, `outcome "success"`, `tokens_in 10`, `tokens_out 20`, `cost 0.005`, `provider_request_id "fake-req-001"`, `error_code NULL`. D1 `usage_event`: 1 row, `tokens 30`, `cost 0.005`, `quota_weight 1`, `period "2026-07"`. R2 envelope exists at `payload_pointer`; `envelope.prompt` is the composed CanonicalRequest (`stream: true`, `deadline: null`, `correlationIds.trace_id` = AAT `jti` ≠ `"s10-001-trace"`); `envelope.attempts[0].payload` = `{fake: true, outcome: "success"}`, `truncated: false`. Quota DO `credit` once with `partial: false`, usage `{tokens: 30, cost: 0.005}` (usage/cost extraction via `ledgerUsageFromProvider`). |
| Code reference | ai-platform/src/worker.ts:L709-L1024 — `runFreshEventSource` (completed branch); ai-platform/src/stream/index.ts:L329-L357 — `handleCompleted`; ai-platform/src/pricing/index.ts:L122-L134 — `ledgerUsageFromProvider`; ai-platform/src/provider/fake.ts:L82-L157 — `FakeAdapter` |

## Scenario S10-002 — Routing decision is persisted before any provider I/O

| Field | Content |
|-------|---------|
| ID | S10-002 |
| Journey setup | Setup FRESH (same policy as S10-001). |
| Action | `vi.spyOn(fakeMod.FakeAdapter.prototype, "invoke")` wrapping the original; inside the spy, read `SELECT routing_decision FROM ai_request WHERE request_id = <this request>` before returning. Then `POST /v1/requests` (new idempotency key `s10-002-idem`). |
| Expected outcome | At first provider invoke, `routing_decision` is already non-null JSON with `chain[0] = {provider_id: "fake", model_id: "fake-v1", max_attempts: 1, timeout_ms: 30000}` and `excluded: []`. SSE completes as in S10-001. The persisted decision never contains `max_parallel_attempts` even when the policy document carries it (schema-retained key, dropped by `selectCandidateChain`). |
| Side effects | One `UPDATE ai_request SET routing_decision = ?` ordered before the first `FakeAdapter.invoke` call; otherwise identical to S10-001. |
| Code reference | ai-platform/src/worker.ts:L764-L767 — `persistRoutingDecision` call before `runInvocation`; ai-platform/src/journal/index.ts:L289-L299 — `persistRoutingDecision`; ai-platform/src/router/index.ts:L583-L680 — `selectCandidateChain` |

## Scenario S10-003 — Missing routing policy after accepted → failed internal_error with terminal settlement

| Field | Content |
|-------|---------|
| ID | S10-003 |
| Journey setup | Setup FRESH but **skip** policy publish/promote (no `active` or canary `routing_policy` row for `standard`). |
| Action | `POST /v1/requests`, idempotency key `s10-003-idem`, trace `s10-003-trace`. |
| Expected outcome | HTTP 200 SSE. Events: `accepted` → `failed` with `data.code: "internal_error"`, `data.request_reference` = this connection's reference, `data.trace_id: "s10-003-trace"`, `data.retry_safe: true`. No `text_delta`. Mechanism: `preloadRoutingPolicyForInstallation` → `loadConfig` throws `ConfigCacheMissError`; the `runFreshEventSource` rejection is caught in `createProductionEventSource`, mapped to `pushFailedTerminal(..., "internal_error")`, then `settlePostAcceptInternalError` journals and records terminal state. |
| Side effects | D1 `ai_request` → `Failed` / `terminal_error_code "internal_error"`. Exactly 1 **synthetic** `ai_attempt` row from `attemptsForFailedSettlement` with empty routing (`reason: "no_provider_attempt"`). Quota DO `credit` once, `partial: true`, idempotency `failed`, zero usage. One `usage_event`; one R2 envelope. |
| Code reference | ai-platform/src/worker.ts — `event_source_fresh_failed` catch + `settlePostAcceptInternalError`; ai-platform/src/worker.ts:L731-L735 — `preloadRoutingPolicyForInstallation`; ai-platform/src/config-cache/index.ts:L387-L413 — `loadConfig` miss throw |

## Scenario S10-004 — Empty candidate chain → failed provider_unavailable with synthetic attempt row

| Field | Content |
|-------|---------|
| ID | S10-004 |
| Journey setup | Setup FRESH. Policy document: catch-all rule whose only target is `fake/fake-v1` with `features.min_context_window: 1000` (manifest requires 32000) — excluded `context_window_too_small`, chain `[]`. |
| Action | `POST /v1/requests`, idempotency key `s10-004-idem`, trace `s10-004-trace`. |
| Expected outcome | Events: `accepted` → `failed` with `data.code: "provider_unavailable"`, `data.retry_safe: true`. No `text_delta`. `runInvocation` returns `createProviderUnavailableError()` before any `portResolver` call. |
| Side effects | `routing_decision` persisted with `chain: []` and `excluded: [{provider_id: "fake", model_id: "fake-v1", reason_code: "context_window_too_small"}]`. D1 `ai_request` → `Failed` / `terminal_error_code "provider_unavailable"`. Exactly 1 **synthetic** `ai_attempt` row from `attemptsForFailedSettlement`: `attempt_no 1`, `provider "fake"`, `model "fake-v1"` (hint = `excluded[0]`), `outcome "terminal_failure"`, `error_code "provider_unavailable"`, `latency_ms/tokens_in/tokens_out/cost` all 0; the R2 envelope attempt payload is `{reason: "no_provider_attempt", excluded: [...]}`, `truncated: false`. Quota DO `credit` once, `partial: true` (`provider_unavailable` consumesQuota is "Partially, recorded" → `partial = consumesQuota !== "Yes"`), idempotency `failed`, zero usage. One `usage_event` (tokens 0). |
| Code reference | ai-platform/src/invocation/index.ts:L451-L457 — empty-chain early return; ai-platform/src/worker.ts:L382-L411 — `attemptsForFailedSettlement`; ai-platform/src/router/index.ts:L464-L581 — `filterTargets` |

## Scenario S10-005 — Unknown provider_id → FakeAdapter retryable:provider_unavailable fallback, retry, chain exhaustion

| Field | Content |
|-------|---------|
| ID | S10-005 |
| Journey setup | Setup FRESH. Policy document: catch-all, single target `{provider_id: "bogus-primary", model_id: "bogus-v1", max_attempts: 2, timeout_ms: 30000}` with visit-summary-valid features. No spy — production `resolveProviderPort` maps the unknown id to `new FakeAdapter(["retryable:provider_unavailable"])`. |
| Action | `POST /v1/requests`, idempotency key `s10-005-idem`, trace `s10-005-trace`. Measure wall-clock elapsed. |
| Expected outcome | Events: `accepted` → `failed` `provider_unavailable`, `retry_safe: true`. `setRetryabilityFromClassification` recomputes from the taxonomy (`provider_unavailable` retryable "Yes"), so `processInvokeResult` records **retryable_failure** and the loop retries: attempt 1 `error_code "provider_unavailable"` (script token), attempt 2 `error_code "internal_error"` (script queue exhausted → FakeAdapter empty-queue branch). Elapsed ≥ ~100 ms (jittered backoff `100×2^0` + up to 50% jitter, via `wallClockSleeper`). Chain exhausted → `provider_unavailable`. |
| Side effects | D1 `ai_attempt`: 2 rows — `(attempt_no 1, provider "bogus-primary", outcome "retryable_failure", error_code "provider_unavailable")`, `(attempt_no 2, outcome "retryable_failure", error_code "internal_error")`. `ai_request` → `Failed/provider_unavailable`. Credit once, `partial: true`, idempotency `failed`. One envelope; attempt payloads `{fake: true, outcome: "retryable:provider_unavailable"}` and `{fake: true, outcome: undefined}`-class internal error body. |
| Code reference | ai-platform/src/worker.ts:L343-L359 — `resolveProviderPort` unknown-id fallback; ai-platform/src/provider/fake.ts:L92-L99 — empty-queue `internal_error`; ai-platform/src/provider/classify.ts:L10-L13 — `classifyFailure`; ai-platform/src/invocation/index.ts:L755-L761 — all-providers-exhausted return |

## Scenario S10-006 — Retryable provider error → jittered backoff → same-target retry succeeds

| Field | Content |
|-------|---------|
| ID | S10-006 |
| Journey setup | Setup FRESH. Policy: single fake target, `max_attempts: 2`. Spy `vi.spyOn(fakeMod, "FakeAdapter")` with `mockImplementation(() => new original(["retryable:rate_limited", "success"]))`. |
| Action | `POST /v1/requests`, idempotency key `s10-006-idem`. Measure elapsed. |
| Expected outcome | Events: `accepted` → `text_delta("Fake adapter summary.", sequence 0)` → `completed`. **No** `regenerating` (attempt 1 streamed no text). Elapsed ≥ 100 ms and < 10 s (backoff base 100 ms × 2^0 + jitter, cap 10 000 ms; `sleepWithinDeadline` is a no-op truncation because `deadline` is null). |
| Side effects | `ai_attempt` rows: `(1, outcome "retryable_failure", error_code "rate_limited")`, `(2, outcome "success", tokens_in 10, tokens_out 20, cost 0.005)`. `ai_request` → `Completed`. Credit once `partial: false`, tokens 30 / cost 0.005 (only the successful result is ledger-priced). |
| Code reference | ai-platform/src/invocation/index.ts:L698-L729 — retry branch (`computeJitteredBackoff`, `sleepWithinDeadline`); ai-platform/src/invocation/index.ts:L159-L167 — `computeJitteredBackoff`; ai-platform/src/wall-clock-sleeper.ts:L2-L6 — `wallClockSleeper` |

## Scenario S10-007 — Malformed provider outcome is retryable internal_error, then success

| Field | Content |
|-------|---------|
| ID | S10-007 |
| Journey setup | Setup FRESH. Policy: single fake target, `max_attempts: 2`. Spy script `["malformed", "success"]`. |
| Action | `POST /v1/requests`, idempotency key `s10-007-idem`. |
| Expected outcome | Events: `accepted` → `text_delta` → `completed`. Attempt 1: `malformed` → canonical `internal_error` → taxonomy retryable "Yes" → `retryable_failure` with `error_code "internal_error"`, backoff, retry. |
| Side effects | `ai_attempt`: `(1, "retryable_failure", error_code "internal_error")`, `(2, "success")`. `ai_request` → `Completed`; one credit `partial: false`. |
| Code reference | ai-platform/src/provider/fake.ts:L127-L133 — `malformed` branch; ai-platform/src/invocation/index.ts:L320-L335 — classification in `processInvokeResult` |

## Scenario S10-008 — Multi-target chain: first target retryable exhaustion falls back to second target

| Field | Content |
|-------|---------|
| ID | S10-008 |
| Journey setup | Setup FRESH. Policy: catch-all with two feature-valid targets — `{provider_id: "bogus-primary", model_id: "bogus-v1", max_attempts: 2, timeout_ms: 30000}` then `{provider_id: "fake", model_id: "fake-v1", max_attempts: 1, timeout_ms: 30000}`. No spy. |
| Action | `POST /v1/requests`, idempotency key `s10-008-idem`. Measure elapsed. |
| Expected outcome | Events: `accepted` → `text_delta("Fake adapter summary.")` → `completed`. **No** `regenerating` (bogus attempts stream nothing). Elapsed ≥ ~100 ms (one inter-retry backoff on the bogus target). In-memory `selection_reason` for the fake attempt is `fallback_after_retryable_error` — **not observable in D1** (`ai_attempt` has no such column; see Doc-drift observations). |
| Side effects | `ai_attempt` 3 rows in order: `(1, "bogus-primary", "retryable_failure", "provider_unavailable")`, `(2, "bogus-primary", "retryable_failure", "internal_error")` (queue exhausted), `(3, "fake", "success")`. `routing_decision.chain` lists bogus then fake. `ai_request` → `Completed`; credit once tokens 30. |
| Code reference | ai-platform/src/invocation/index.ts:L525-L568 — chain walk and `selection_reason` derivation; ai-platform/src/worker.ts:L358 — unknown-id FakeAdapter fallback |

## Scenario S10-009 — Terminal provider_rejected (missing DeepSeek key) fails fast — no fallback

| Field | Content |
|-------|---------|
| ID | S10-009 |
| Journey setup | Setup FRESH. Policy: catch-all with targets `[{provider_id: "deepseek", model_id: "deepseek-v4-flash", max_attempts: 2, timeout_ms: 30000, …valid features}, {provider_id: "fake", model_id: "fake-v1", max_attempts: 1, …}]`. Pool env has **no** `DEEPSEEK_API_KEY`. |
| Action | `POST /v1/requests`, idempotency key `s10-009-idem`, trace `s10-009-trace`. |
| Expected outcome | Events: `accepted` → `failed` with `data.code: "provider_rejected"`, `data.retry_safe: false` (taxonomy retryable "No"). The DeepSeek adapter returns `provider_rejected`/`missing_api_key` before any fetch; `classifyFailure("provider_rejected")` = terminal → `runInvocation` returns immediately. **No** retry despite `max_attempts: 2`; **no** fake attempt — terminal errors fail fast, they do not fall back. |
| Side effects | `ai_attempt`: exactly 1 row — `provider "deepseek"`, `model "deepseek-v4-flash"`, `outcome "terminal_failure"`, `error_code "provider_rejected"`, tokens/cost 0. `ai_request` → `Failed/provider_rejected`. Credit once, `partial: false` (`provider_rejected` consumesQuota "Yes"), idempotency `failed`. One `usage_event`, one envelope. |
| Code reference | ai-platform/src/provider/deepseek.ts:L556-L566 — missing-key outcome; ai-platform/src/invocation/index.ts:L320-L328 — terminal classification short-circuit; ai-platform/src/provider/classify.ts:L10-L13 — `classifyFailure` |

## Scenario S10-010 — Attempt timeout classification: outcome timeout, retry, exhaustion → provider_unavailable

| Field | Content |
|-------|---------|
| ID | S10-010 |
| Journey setup | Setup FRESH. Policy: single fake target with `timeout_ms: 50`, `max_attempts: 2`. Spy `FakeAdapter` subclass whose `invoke` hangs (signal-aware 5 000 ms promise that rejects `AbortError` on abort). |
| Action | `POST /v1/requests`, idempotency key `s10-010-idem`. Measure elapsed. |
| Expected outcome | Events: `accepted` → `failed` `provider_unavailable` (`retry_safe: true`). Each attempt: `invokeWithTimeout`'s 50 ms timer wins the race → canonical `timeout` error → taxonomy retryable → attempt `outcome "timeout"`, `error_code "timeout"`. One backoff (~100–150 ms), second attempt times out, chain exhausted. **Timeout is never the client-facing terminal code** — exhaustion maps to `provider_unavailable`. Elapsed ≈ 200–250 ms. |
| Side effects | `ai_attempt`: 2 rows, both `outcome "timeout"`, `error_code "timeout"`. `ai_request` → `Failed/provider_unavailable`. Credit once `partial: true`, idempotency `failed`. |
| Code reference | ai-platform/src/invocation/index.ts:L338-L403 — `invokeWithTimeout` (`createTimeoutError` race); ai-platform/src/invocation/index.ts:L330-L335 — `outcome "timeout"` derivation |

## Scenario S10-011 — Fallback after timeout: second chain target succeeds

| Field | Content |
|-------|---------|
| ID | S10-011 |
| Journey setup | Setup FRESH. Policy: two fake targets — `{model_id: "fake-slow", timeout_ms: 50, max_attempts: 1}` then `{model_id: "fake-v1", timeout_ms: 30000, max_attempts: 1}`. Spy `FakeAdapter` by construction order: first instance hangs (as S10-010), second is `new original(["success"])`. |
| Action | `POST /v1/requests`, idempotency key `s10-011-idem`. |
| Expected outcome | Events: `accepted` → `text_delta("Fake adapter summary.")` → `completed`. No `regenerating` (the timed-out attempt streamed nothing). In-memory `selection_reason` for attempt 2 is `fallback_after_timeout` (prior target's final failure was timeout-classified) — in-memory only, not persisted (Doc-drift observations). |
| Side effects | `ai_attempt`: `(1, model "fake-slow", outcome "timeout", error_code "timeout")`, `(2, model "fake-v1", outcome "success")`. `ai_request` → `Completed`; credit tokens 30 / cost 0.005 priced at `fake-v1` rates. |
| Code reference | ai-platform/src/invocation/index.ts:L552-L559 — `fallback_after_timeout` selection; ai-platform/src/invocation/index.ts:L736-L739 — `prevExhaustedViaTimeout` propagation |

## Scenario S10-012 — All chain targets exhausted (multi-target) → failed provider_unavailable with real attempt rows

| Field | Content |
|-------|---------|
| ID | S10-012 |
| Journey setup | Setup FRESH. Policy: two unknown-provider targets — `bogus-a/bogus-v1 max_attempts: 1`, `bogus-b/bogus-v1 max_attempts: 1`, both feature-valid. |
| Action | `POST /v1/requests`, idempotency key `s10-012-idem`, trace `s10-012-trace`. |
| Expected outcome | Events: `accepted` → `failed` `provider_unavailable`, `retry_safe: true`, `request_reference` matching this connection's `accepted`. No backoff elapsed (each target has `max_attempts: 1`, so no inter-retry sleep). |
| Side effects | `ai_attempt`: 2 **real** rows (`bogus-a` then `bogus-b`, both `retryable_failure`/`provider_unavailable`) — `attemptsForFailedSettlement` uses the real records, not the synthetic row (contrast S10-004). `ai_request` → `Failed/provider_unavailable`. Credit once `partial: true`, idempotency `failed`; one `usage_event`; one envelope. |
| Code reference | ai-platform/src/invocation/index.ts:L755-L761 — exhaustion return; ai-platform/src/worker.ts:L969-L977 — failed settlement with real records |

## Scenario S10-013 — Client disconnect mid-stream after partial text → cancelled with streamed-chars partial credit

| Field | Content |
|-------|---------|
| ID | S10-013 |
| Journey setup | Setup FRESH (policy as S10-001). Spy `FakeAdapter` subclass: `invoke` calls `options.onStreamChunk` once with a `text_delta` chunk `"Partial "` (8 chars), then hangs signal-aware (rejects `AbortError` on abort). |
| Action | `POST /v1/requests` with `signal` from a test `AbortController`, idempotency key `s10-013-idem`. Wait until the fake's `invoke` was entered and the `text_delta` was relayed, then `controller.abort()`. Allow the fetch promise to reject; flush background work (~350 ms). |
| Expected outcome | The original connection may show `accepted` + `text_delta("Partial ", sequence 0)` and **no** terminal frame (adapter `markCancelledWithoutEnqueue` — the client is gone). The broker's `disconnect("client_close")` emits terminal `cancelled` synchronously into the dead stream, credits, and journals. Invocation's caller signal aborts the in-flight attempt → canonical `cancelled` → terminal classification → worker cancel path (`invocation_cancelled`) settles with `skipCredit: true` because the broker already settled. |
| Side effects | D1 `ai_request` → `Cancelled` (via broker `journalTerminalSink`), `terminal_error_code NULL`. Quota DO `credit` **exactly once**, `partial: true`, idempotency `cancelled`, usage = `estimateUsageFromStreamedChars(8, "fake-v1")` = `{tokens: 8, cost: 0.0016}` (streamed chars priced as output tokens at the first chain model). `ai_attempt`: 1 row — `outcome "terminal_failure"`, `error_code "cancelled"`, tokens 0 (the attempt never produced a result). One `usage_event` (tokens 8, cost 0.0016); one envelope. |
| Code reference | ai-platform/src/stream/index.ts:L259-L287 — `handleCancel`; ai-platform/src/worker.ts:L925-L955 — cancelled settle path; ai-platform/src/pricing/index.ts:L142-L154 — `estimateUsageFromStreamedChars`; ai-platform/src/adapter.ts:L539-L544 — stream `cancel()` → `notifyDisconnect("client_close")` |

## Scenario S10-014 — Client disconnect before any provider byte → cancelled with zero-usage partial credit

| Field | Content |
|-------|---------|
| ID | S10-014 |
| Journey setup | Setup FRESH. Spy `FakeAdapter` subclass whose `invoke` hangs signal-aware without emitting any chunk. |
| Action | As S10-013 but abort as soon as the fake's `invoke` is entered (no `text_delta` relayed). Idempotency key `s10-014-idem`. |
| Expected outcome | Same wire shape as S10-013 (no terminal on the dead connection). `chunkSource.getPartialUsage()` returns `undefined` (no accrued result, 0 streamed chars) → broker credits `{tokens: 0, cost: 0}` with `partial: true` — zero-usage cancel credit still releases `inFlight` and flips idempotency to `cancelled`. |
| Side effects | `ai_request` → `Cancelled`. Credit exactly once, `partial: true`, zero usage. `ai_attempt`: 1 row `terminal_failure`/`cancelled` if the abort landed after the attempt started (this arrangement), or 0 rows if it lands before the chain loop — both are code-valid; this scenario pins the former. One `usage_event` (zeros); one envelope. |
| Code reference | ai-platform/src/stream/index.ts:L274-L279 — `getPartialUsage ?? {tokens: 0, cost: 0}`; ai-platform/src/invocation/index.ts:L526-L531 — caller-signal check at chain start |

## Scenario S10-015 — Abort already signaled at entry: disconnect before the accept context is consumed

| Field | Content |
|-------|---------|
| ID | S10-015 |
| Journey setup | Setup FRESH (policy as S10-001). No spy. |
| Action | `SELF.fetch` the `POST /v1/requests` with an **already-aborted** `AbortController.signal`, idempotency key `s10-015-idem`. Tolerate a rejected fetch promise; flush background work. |
| Expected outcome | The adapter's `abortedAtEntry` branch runs: `markCancelledWithoutEnqueue()` + `notifyDisconnect("client_close")` + close — the event-source factory is **never invoked**, so the accept-context entry is never consumed, no broker exists, no provider is called, and no terminal event is produced anywhere. |
| Side effects | D1 `ai_request` row exists (guard INSERT) and remains `state Accepted` with `routing_decision NULL` — the event-source factory is never invoked (C-01 settlement does not apply). No `ai_attempt`, no `usage_event`, no envelope, no Quota DO `credit` (the admission stays `admitted` until the DO sweep — outside this stage). |
| Code reference | ai-platform/src/adapter.ts:L470-L470 — `abortedAtEntry`; ai-platform/src/adapter.ts:L527-L532 — abort-at-entry short-circuit before `eventSource(...)` |

## Scenario S10-016 — Idempotent replay of a completed prior request → placeholder completed

| Field | Content |
|-------|---------|
| ID | S10-016 |
| Journey setup | S10-001 completed with idempotency key `s10-001-idem` (DO idempotency state `completed`). |
| Action | Re-`POST /v1/requests` with the **same** `x-idempotency-key: "s10-001-idem"`, new `x-trace-id: "s10-016-trace"`. |
| Expected outcome | Events: `accepted` (new `request_reference`, `trace_id "s10-016-trace"`) → `completed` with `data.result.finalContent.text: "Prior request completed."`, `authoritative: true` — placeholder prose, **not** the original result and not an R2 replay. No `text_delta`, no routing, no provider call (`replayIdempotentTerminal` returns before any fresh-path work). |
| Side effects | None. No new `ai_request` row, no `ai_attempt`, no `usage_event`, envelope not rewritten, no credit. |
| Code reference | ai-platform/src/worker.ts:L606-L640 — `replayIdempotentTerminal` (`completed`/`admitted` branch); ai-platform/src/worker.ts:L666-L673 — idempotent dispatch |

## Scenario S10-017 — Idempotent replay of an admitted (still in-flight) prior request → accepted only (no fabricated terminal)

| Field | Content |
|-------|---------|
| ID | S10-017 |
| Journey setup | Setup FRESH. Spy `FakeAdapter` subclass whose `invoke` hangs ~5 s signal-aware, then succeeds. First `POST /v1/requests` with idempotency key `s10-017-idem` still in-flight (DO state `admitted`). |
| Action | While the first request is mid-invoke, second `POST /v1/requests` with the same key `s10-017-idem`, trace `s10-017-trace`. Then let the first request finish. |
| Expected outcome | Second connection: `accepted` only — **no** terminal frame (stream stays open; `replayIdempotentTerminal` returns without fabricating `completed`). Client polls `GET /v1/requests/{prior_request_reference}` or waits on the first connection for the real outcome. First connection: normal `accepted` → `text_delta` → `completed` with real fake text once the hang resolves. |
| Side effects | Exactly one `ai_request` row total; one `ai_attempt`; one credit (`partial: false`) from the first request only. The replay connection writes nothing. |
| Code reference | ai-platform/src/worker.ts — `replayIdempotentTerminal` `admitted` branch (no terminal emission) |

## Scenario S10-018 — Idempotent replay of a failed prior request → failed internal_error (not the original code)

| Field | Content |
|-------|---------|
| ID | S10-018 |
| Journey setup | S10-005 (or S10-012) completed its failure: DO idempotency state `failed` for key `s10-005-idem` (original terminal code `provider_unavailable`). |
| Action | Re-`POST /v1/requests` with `x-idempotency-key: "s10-005-idem"`, trace `s10-018-trace`. |
| Expected outcome | Events: `accepted` → `failed` with `data.code: "internal_error"` — the replay deliberately does **not** echo the original `provider_unavailable` — `retry_safe: true`, `request_reference` of this new connection. No provider call. |
| Side effects | None (no new rows, no credit). |
| Code reference | ai-platform/src/worker.ts:L631-L634 — `failed` → `pushFailedTerminal(..., "internal_error")` |

## Scenario S10-019 — Idempotent replay of a cancelled prior request → cancelled

| Field | Content |
|-------|---------|
| ID | S10-019 |
| Journey setup | S10-013 or S10-014 completed its cancel: DO idempotency state `cancelled` for key `s10-013-idem`. |
| Action | Re-`POST /v1/requests` with `x-idempotency-key: "s10-013-idem"`, trace `s10-019-trace`. |
| Expected outcome | Events: `accepted` → `cancelled` with `data` = `{trace_id: "s10-019-trace"}` only (no `code`, no `request_reference`). This is the only way to observe a `cancelled` frame on the wire after a real client drop. |
| Side effects | None. |
| Code reference | ai-platform/src/worker.ts:L635-L638 — `cancelled` replay branch |

## Scenario S10-020 — Prose guard: refusal prefixes at start of output → validation_failed

| Field | Content |
|-------|---------|
| ID | S10-020 |
| Journey setup | Setup FRESH (policy as S10-001). Spy `FakeAdapter` subclass returning success whose single terminal `text_delta` chunk carries the refusal text. |
| Action | Two POSTs (keys `s10-020a-idem`, `s10-020b-idem`): (a) output text `"I'm sorry, I can't help with that"`; (b) output text `"I'm sorry, I can't assist"`. |
| Expected outcome | Each: `accepted` → `failed` with `data.code: "validation_failed"`, `retry_safe: true` (taxonomy "Yes, at user discretion"). The tripping chunk is **not** emitted as `text_delta` — `checkIncrementalGuards` runs after assembly, before `emitEvent`. No `completed`. |
| Side effects | Per request: `ai_request` → `Failed/validation_failed`; credit exactly once `partial: false` (`validation_failed` consumesQuota "Yes"), idempotency `failed`, settled by the broker and journaled by the worker with `skipCredit: true` (broker-terminal path). `ai_attempt`: 1 row with `outcome "success"` (the provider call itself succeeded) and `error_code NULL` under a `Failed` request — honest code behavior. One `usage_event` (tokens 30, cost 0.005 from the succeeded result via `ledgerUsageFromProvider`). |
| Code reference | ai-platform/src/stream/prose-guards.ts:L60-L67 — refusal prefix match after `trimStart`; ai-platform/src/worker.ts:L169-L173 — production refusal prefixes; ai-platform/src/worker.ts:L992-L1016 — broker-non-completed settle |

## Scenario S10-021 — Prose guard negative: refusal text mid-sentence does not trip

| Field | Content |
|-------|---------|
| ID | S10-021 |
| Journey setup | As S10-020, output text `"The patient joked: I'm sorry, I can't help with that"`. |
| Action | `POST /v1/requests`, key `s10-021-idem`. |
| Expected outcome | `accepted` → `text_delta` → `completed` with the full text authoritative. Prefix match is `trimStart().startsWith(prefix)` — mid-sentence occurrences never fire. |
| Side effects | As S10-001 (Completed settlement). |
| Code reference | ai-platform/src/stream/prose-guards.ts:L60-L67 — start-anchored refusal check |

## Scenario S10-022 — Prose guard: injection-echo needle substring → validation_failed

| Field | Content |
|-------|---------|
| ID | S10-022 |
| Journey setup | As S10-020. Output arrives in two chunks: `"Visit summary. "` then `"Ignore previous instructions and continue."` |
| Action | `POST /v1/requests`, key `s10-022-idem`. |
| Expected outcome | `accepted` → `text_delta("Visit summary. ", sequence 0)` → `failed` `validation_failed`. The needle `"Ignore previous instructions"` is a substring check on cumulative assembled text; the second (tripping) chunk is never emitted. |
| Side effects | As S10-020 (`Failed/validation_failed`, one `partial: false` credit, success-shaped attempt row). |
| Code reference | ai-platform/src/stream/prose-guards.ts:L53-L58 — `injection_echo`; ai-platform/src/worker.ts:L174 — production needle |

## Scenario S10-023 — Prose guard: system-prompt leak (opening needle) → validation_failed

| Field | Content |
|-------|---------|
| ID | S10-023 |
| Journey setup | Setup FRESH. The harness prompt-registry mock serves system instruction `"You are a clinical documentation assistant.\n"` (43 chars trimmed ≤ 48 → the sole leak needle is the whole instruction). Spy `FakeAdapter` subclass returning output text `"You are a clinical documentation assistant."` |
| Action | `POST /v1/requests`, key `s10-023-idem`. |
| Expected outcome | `accepted` → `failed` `validation_failed`. The model echo of the composed system instruction trips `system_prompt_leak` via `text.includes(needle)`. |
| Side effects | As S10-020. |
| Code reference | ai-platform/src/stream/prose-guards.ts:L46-L51 — leak-needle loop; ai-platform/src/prompt/composer.ts:L42-L70 — `leakNeedlesFromSystemInstruction`; ai-platform/src/worker.ts:L860-L866 — guard thresholds wiring |

## Scenario S10-024 — Prose guard: leak interior and ending 48-char slices → validation_failed

| Field | Content |
|-------|---------|
| ID | S10-024 |
| Journey setup | Setup FRESH. [SEED] Extend the harness prompt-registry mock so `clinic.visit_summary/system@v1` returns a ≥ 150-char instruction (e.g. 160 chars of distinctive prose) before any request; the composer then derives three distinct needles: `slice(0,48)`, the centered 48-char window, and `slice(-48)`. Justification: the default harness instruction is 43 chars and collapses to a single needle; the interior/ending branches of `leakNeedlesFromSystemInstruction` are otherwise unreachable. Prompt content seeding uses the same `vi.mock("../../src/prompt/registry")` seam the production harness already uses. Spy `FakeAdapter` subclass parameterized on output text. |
| Action | Two POSTs (keys `s10-024a-idem`, `s10-024b-idem`): (a) output contains the interior 48-char slice verbatim; (b) output contains the ending 48-char slice verbatim. |
| Expected outcome | Each: `accepted` → `failed` `validation_failed`. `guard.systemPromptLeakNeedles` (all slices) is passed into the broker thresholds and any slice match trips. |
| Side effects | As S10-020 per request. |
| Code reference | ai-platform/src/prompt/composer.ts:L53-L69 — start/middle/end slicing; ai-platform/src/stream/prose-guards.ts:L26-L34 — `leakNeedlesFromThresholds` (multi-needle preference) |

## Scenario S10-025 — Prose guard: stop sequence <|end|> in output → validation_failed

| Field | Content |
|-------|---------|
| ID | S10-025 |
| Journey setup | As S10-020. Output text `"Summary body <|end|> trailing text"`. |
| Action | `POST /v1/requests`, key `s10-025-idem`. |
| Expected outcome | `accepted` → `failed` `validation_failed` (`stop_sequence` trip on cumulative text). Tripping chunk not emitted. |
| Side effects | As S10-020. |
| Code reference | ai-platform/src/stream/prose-guards.ts:L40-L44 — stop-sequence loop; ai-platform/src/worker.ts:L168 — production `stopSequences: ["<|end|>"]` |

## Scenario S10-026 — Prose guard: assembled length over 128 000 chars → validation_failed mid-stream

| Field | Content |
|-------|---------|
| ID | S10-026 |
| Journey setup | As S10-020. Spy subclass streams two `text_delta` chunks of 65 536 chars each (via `onStreamChunk`), then a success result. |
| Action | `POST /v1/requests`, key `s10-026-idem`. |
| Expected outcome | `accepted` → `text_delta` (chunk 1, sequence 0) → `failed` `validation_failed`. After chunk 2 the assembled length is 131 072 > `maxLength` 128 000 → `length_ceiling`; the broker aborts its chunk source and fails. Chunk 2 is never emitted. |
| Side effects | As S10-020. Additionally the broker's `abortController.abort()` stops the chunk-source pull; invocation itself is not signal-aborted (its caller signal is the connection signal) and may run to completion — settlement still single-credits (see S10-032). |
| Code reference | ai-platform/src/stream/prose-guards.ts:L76-L92 — `checkIncrementalGuards` length ceiling; ai-platform/src/worker.ts:L167 — `maxLength: 128_000`; ai-platform/src/stream/index.ts:L406-L411 — incremental trip → abort + `handleFailed` |

## Scenario S10-027 — Prose guard: empty output → validation_failed (full-guard empty_output)

| Field | Content |
|-------|---------|
| ID | S10-027 |
| Journey setup | As S10-020. Spy subclass returns `kind: "success"` with `finalContent.text: ""` and chunks = single terminal `text_delta` with empty text. |
| Action | `POST /v1/requests`, key `s10-027-idem`. |
| Expected outcome | `accepted` → `failed` `validation_failed`. No `text_delta` at all: `relayTextDeltas` skips empty strings, so the broker assembles `""`; incremental guards never fire on empty text, but the deferred `runFullGuardSet` `empty_output` check fails at stream end. |
| Side effects | As S10-020 (broker-terminal path, single credit). |
| Code reference | ai-platform/src/stream/prose-guards.ts:L94-L108 — `runFullGuardSet` empty check; ai-platform/src/stream/index.ts:L445-L449 — full guard set at completion; ai-platform/src/invocation/index.ts:L243-L258 — empty-text skip in `relayTextDeltas` |

## Scenario S10-028 — Truncation with no retries left → failed validation_failed; ignoreBrokerSettlement prevents double credit

| Field | Content |
|-------|---------|
| ID | S10-028 |
| Journey setup | Setup FRESH. Policy: single fake target `max_attempts: 1`. Spy `vi.spyOn(fakeMod, "FakeAdapter")` → `new original(["truncation"])`. Also spy `creditUsage`. |
| Action | `POST /v1/requests`, key `s10-028-idem`, trace `s10-028-trace`. |
| Expected outcome | `accepted` → `text_delta("Partial output…", sequence 0)` → `failed` `validation_failed` (`retry_safe: true`). Mechanism: attempt outcome `truncation`; `validation_failed` is retryable but `max_attempts: 1` leaves no retry; chain end with `exhaustedViaTruncation` returns `createValidationFailedError()` (never `provider_unavailable`, never authoritative `completed`). The worker arms `ignoreBrokerSettlement = true` **before** `pushable.end()`, so when the broker afterwards sees `wasTruncated()` and would emit its own `failed` + credit, both are suppressed; the worker's `pushFailedTerminal` is the single terminal and `settleTerminal` the single credit. Assert `creditUsage` called exactly once. |
| Side effects | `ai_request` → `Failed/validation_failed`. `ai_attempt`: 1 row `outcome "truncation"`, `tokens_in 10`, `tokens_out 20`, `cost 0.005`, `error_code NULL`. Credit once `partial: false`, idempotency `failed`, usage `{tokens: 30, cost: 0.005}` (accrued from the truncation result via `noteUsageFromResult`). One `usage_event`, one envelope. |
| Code reference | ai-platform/src/invocation/index.ts:L749-L754 — truncation-exhausted → `validation_failed`; ai-platform/src/worker.ts:L897-L903 — `ignoreBrokerSettlement` arming; ai-platform/src/worker.ts:L800-L812 — broker sink suppression; ai-platform/src/stream/index.ts:L441-L444 — `wasTruncated` fail |

## Scenario S10-029 — Truncation then same-target retry succeeds → regenerating clears truncation → completed

| Field | Content |
|-------|---------|
| ID | S10-029 |
| Journey setup | Setup FRESH. Policy: single fake target `max_attempts: 2`. Spy script `["truncation", "success"]`. |
| Action | `POST /v1/requests`, key `s10-029-idem`. |
| Expected outcome | Exact sequence: `accepted` → `text_delta("Partial output…", sequence 0)` → `regenerating` (`data.trace_id`) → `text_delta("Fake adapter summary.", sequence 0)` (sequence resets after regenerating) → `completed` with authoritative `"Fake adapter summary."`. The `regenerating` chunk clears the chunk-source `truncated` flag, so the discarded truncated prose cannot fail the completed leg. |
| Side effects | `ai_attempt`: `(1, outcome "truncation", tokens 10/20, cost 0.005)`, `(2, outcome "success", tokens 10/20, cost 0.005)`. `ai_request` → `Completed`. Credit once `partial: false` with usage from the **successful** result only (`{tokens: 30, cost: 0.005}`) — the accrued partial-usage tracker (60 tokens across both attempts) is used only for cancel/fail credit, not completed settlement. `usage_event` tokens 30. |
| Code reference | ai-platform/src/invocation/index.ts:L606-L610 — same-target regenerating before retry emission; ai-platform/src/stream/index.ts:L63-L66 — regenerating clears `truncated`; ai-platform/src/worker.ts:L1018-L1023 — `settleCompletedRequest` |

## Scenario S10-030 — Cross-target fallback after partial stream → regenerating → completed

| Field | Content |
|-------|---------|
| ID | S10-030 |
| Journey setup | Setup FRESH. Policy: two fake targets — `{model_id: "fake-v1", max_attempts: 1}` then `{model_id: "fake-v2", max_attempts: 1}`. Spy `FakeAdapter` by construction order: first instance's `invoke` calls `onStreamChunk` with `"Partial "` then returns `{kind: "error", error: retryable rate_limited}`; second is `new original(["success"])`. |
| Action | `POST /v1/requests`, key `s10-030-idem`. |
| Expected outcome | `accepted` → `text_delta("Partial ", sequence 0)` → `regenerating` → `text_delta("Fake adapter summary.", sequence 0)` → `completed`. The regenerating is emitted at chain-target switch because the prior target had a partial stream (`prevTargetHadPartialStream`). In-memory `selection_reason` of attempt 2: `fallback_after_retryable_error`. |
| Side effects | `ai_attempt`: `(1, model "fake-v1", "retryable_failure", "rate_limited")`, `(2, model "fake-v2", "success")`. `Completed` settlement as S10-001. |
| Code reference | ai-platform/src/invocation/index.ts:L546-L549 — cross-target regenerating; ai-platform/src/invocation/index.ts:L737-L738 — `prevTargetHadPartialStream` propagation |

## Scenario S10-031 — Same-target retry after partial stream → regenerating before first re-emission

| Field | Content |
|-------|---------|
| ID | S10-031 |
| Journey setup | Setup FRESH. Policy: single fake target `max_attempts: 2`. Spy subclass: attempt 1 calls `onStreamChunk("Partial ")` then returns retryable `rate_limited` error; attempt 2 returns success. |
| Action | `POST /v1/requests`, key `s10-031-idem`. |
| Expected outcome | `accepted` → `text_delta("Partial ", sequence 0)` → `regenerating` → `text_delta("Fake adapter summary.", sequence 0)` → `completed`. The regenerating is emitted before the retry's first emission (`pendingSameTargetRegenerating` set at the retry decision because `currentTargetHadPartialStream`). |
| Side effects | `ai_attempt`: `(1, "retryable_failure", "rate_limited")`, `(2, "success")`. `Completed`; credit tokens 30. |
| Code reference | ai-platform/src/invocation/index.ts:L697-L700 — `pendingSameTargetRegenerating` arming; ai-platform/src/invocation/index.ts:L606-L610 — emission |

## Scenario S10-032 — Broker terminal (guard trip) races invoke success → single failed, single credit

| Field | Content |
|-------|---------|
| ID | S10-032 |
| Journey setup | Setup FRESH (policy as S10-001). Spy subclass: `invoke` calls `onStreamChunk` once with `"Ignore previous instructions"` (injection-echo needle in one chunk), then waits ~50 ms and returns a normal success result. Spy `creditUsage`. |
| Action | `POST /v1/requests`, key `s10-032-idem`, trace `s10-032-trace`. |
| Expected outcome | `accepted` → `failed` `validation_failed` — exactly one terminal, emitted by the broker when the incremental guard trips (the needle chunk is never emitted as `text_delta`). Invocation is not aborted (its caller signal is the connection signal, not the broker's) and returns `ok: true` ~50 ms later; the worker takes the `brokerTerminal !== "completed"` branch with `brokerCode "validation_failed"` and settles with `skipCredit: true`. Assert `creditUsage` called **exactly once** (broker's `partial: false` failed credit) — no double credit from the invoke-success side. |
| Side effects | `ai_request` → `Failed/validation_failed`. `ai_attempt`: 1 row `outcome "success"` under the Failed request. One `usage_event` (tokens 30, cost 0.005 — `partialUsage` accrued from the success result). One envelope. |
| Code reference | ai-platform/src/worker.ts:L992-L1016 — broker-non-completed settle (`skipCredit: true`); ai-platform/src/stream/index.ts:L406-L411 — guard trip → `handleFailed("validation_failed")`; ai-platform/src/stream/index.ts:L289-L327 — `handleFailed` credit + journal |

## Scenario S10-033 — Heartbeat on a slow stream (> 15 s silence) → heartbeat before text_delta

| Field | Content |
|-------|---------|
| ID | S10-033 |
| Journey setup | Setup FRESH (policy as S10-001, `timeout_ms: 30000`). Spy subclass: `invoke` waits 16 000 ms (signal-aware) then returns `new original(["success"])`-equivalent success. |
| Action | `POST /v1/requests`, key `s10-033-idem`, trace `s10-033-trace`. Read the stream with timestamps. |
| Expected outcome | `accepted` → at ~15 s, `heartbeat` with `data.trace_id: "s10-033-trace"` → at ~16 s, `text_delta("Fake adapter summary.")` → `completed`. Exactly one heartbeat (the text_delta's `notifyActivity()` rearms the 15 s timer; the terminal cancels it). Slow test (~16 s; pool `testTimeout` is 120 000 ms). |
| Side effects | As S10-001. |
| Code reference | ai-platform/src/worker.ts:L161 — `HEARTBEAT_INTERVAL_MS = 15_000`; ai-platform/src/worker.ts:L285-L306 — `createProductionHeartbeatTicker`; ai-platform/src/stream/index.ts:L366-L372 — heartbeat emission |

## Scenario S10-034 — Missing accept context → failed internal_error (harness seam required)

| Field | Content |
|-------|---------|
| ID | S10-034 |
| Journey setup | Setup FRESH (policy as S10-001). [SEED] The accept-context store is a request-scoped `Map` inside `handleLivePostRequest`; no client behavior can drop the entry between pre-accept and event-source. Seam: `vi.spyOn(Map.prototype, "get")` returning `undefined` once for the event-source lookup (or invoke the unexported factory path via module internals). Justification: covers the defensive `event_source_missing_accept_context` branch that is otherwise unreachable end-to-end. |
| Action | `POST /v1/requests`, key `s10-034-idem`, trace `s10-034-trace`, with the seam armed. |
| Expected outcome | `accepted` → `failed` with `data.code: "internal_error"`, `retry_safe: true`. Log `event_source_missing_accept_context`. No routing, no provider call, no broker. Background `settleMissingHandoffInternalError` settles the request. |
| Side effects | D1 `ai_request` → `Failed` / `terminal_error_code "internal_error"`. One synthetic `ai_attempt`; Quota DO `credit` once (`partial: true`, idempotency `failed`); one `usage_event`; one R2 envelope. |
| Code reference | ai-platform/src/worker.ts — missing-accept-context branch + `settleMissingHandoffInternalError` |

## Doc-drift observations

1. **Missing-policy / missing-handoff post-accept failures — fixed (C-01).** `settlePostAcceptInternalError` / `settleMissingHandoffInternalError` now journal, credit, and `recordTerminalState` for the `runFreshEventSource` catch and missing-accept-context branches (S10-003, S10-034).
2. **Abort-at-entry (S10-015) unchanged.** The adapter short-circuits before the event-source factory runs; the row stays `Accepted` — distinct from the missing-handoff settlement paths above.
3. **`ai_attempt.selection_reason` is not a D1 column.** §14 presents `primary` / `fallback_after_retryable_error` / `fallback_after_timeout` as `D1 ai_attempt.selection_reason`; the migration (`20260731120000_platform_schema.sql:L86-L100`) has no such column — the values exist only on the in-memory `AttemptRecord` (`invocation/index.ts:L21-L24`). §19.3.10 self-flags this, but the §14 table still drifts (S10-008, S10-011, S10-030).
4. **`text_delta.data` omits `trace_id`.** §4.1 and §11.4 claim every `data` object includes `trace_id`; the broker puts `trace_id` on the event wrapper and `encodeSseEvent` serializes only `event.data`, so `text_delta.data` is `{text, sequence, provisional}` only. §19.3.5 acknowledges the gap; the §4.1/§11.4 contract tables were not updated (S10-001).
5. **Structured relay path is documented as live but is never wired.** §10 says "structured JSON capabilities use a separate relay path"; `createStructuredStreamBroker` (`stream/structured.ts:L177`) and `validateAndRepair` (`validate/index.ts:L87`) have **no caller in `worker.ts`** — the prose broker is created unconditionally (`worker.ts:L814-L866`). `progress` / `partial_structured` events, commit-time schema/business validation, and `repairPolicy` reask are unreachable on `POST /v1/requests` regardless of manifest `Output.mode`. Conversely, `regenerating` **is** reachable for visit summary despite `repairPolicy.allowed: false`, because regenerating originates in the invocation loop (partial-stream retry/fallback), not in validation repair (S10-029/030/031).
6. **`AdapterDisconnectReason "network_drop"` is dead.** Defined at `adapter.ts:L31` and accepted by the broker, but all three adapter call sites pass `"client_close"` (`adapter.ts:L529, L543, L555`). No scenario can produce `network_drop`.
7. **Unknown-provider fallback token renamed (C-23).** `resolveProviderPort` now scripts `retryable:provider_unavailable` for unknown ids, matching retryable semantics (S10-005).
8. **`cancelled` on a true client drop is emitted into a dead stream.** §11.7 shows the `cancelled` frame without noting it is unobservable on the dropped connection (adapter `markCancelledWithoutEnqueue`, `adapter.ts:L472-L474`); §19.3.12 documents the replay-based observation. S10-013/014 (drop) + S10-019 (replay) encode the code behavior.

## Non-automatable notes

1. **Live DeepSeek/Gemini wire behavior** — request shaping (role maps, `stream_options.include_usage`, `:streamGenerateContent?alt=sse`, `response_format`/`responseMimeType`), HTTP failure classification (401/403 → `provider_rejected`, 429 → `rate_limited`, 5xx → `internal_error`, content-filter → `provider_rejected`), SSE parsing (`[DONE]`, malformed data line → `malformed`/`internal_error`, error frames), `finish_reason: "length"` / missing finish → `truncation`, usage-absent → `provider_note`, and the 1 MiB `PROVIDER_RESPONSE_BODY_SIZE_LIMIT` → `internal_error response_too_large`. Proposed seam: stub `globalThis.fetch` in the pool isolate — `createFetchTransport` binds `globalThis.fetch` lazily at `resolveProviderPort` call time (`fetch-transport.ts:L33-L55`), so a test-installed stub is picked up — plus `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` bindings in `poolOptions.workers.bindings`. Until that seam is built, only the missing-key terminal path is covered (S10-009).
2. **Raw-body 16 KiB cap truncation in journaled attempts** (`raw-body.ts:L6, L13-L27`). `FakeAdapter.rawBody` is a tiny fixed object (`{fake: true, outcome}`, `truncated: false`); only the real adapters attach wire text via `withRawBody`, and the cap trips only above 16 384 bytes. Same fetch-stub seam as note 1 with a > 16 KiB provider body; assert envelope attempt `truncated: true` and payload sliced at the cap.
3. **Provider Retry-After honored in backoff** (`invocation/index.ts:L702-L711` — `delay = max(jittered, retryAfterMs)`). `retryAfterMs` is attached only by the DeepSeek/Gemini adapters from HTTP `Retry-After` (`deepseek.ts:L146-L165`, `gemini.ts:L156-L178`). Same fetch-stub seam: 429 response with `Retry-After: 2`, assert inter-attempt gap ≥ 2 000 ms.
4. **Deadline-driven invocation branches** — deadline-exhausted target skip (`invocation/index.ts:L534-L544`), `sleepWithinDeadline` truncation (`L416-L431`), `min(timeout_ms, remaining)` attempt timeout (`L594-L604`). Production pre-accept never sets `GuardInput.deadline`, so `CanonicalRequest.deadline` is always `null` on the live path (`worker.ts:L1052-L1085`; confirmed in envelopes as `deadline: null`). No POST-level seam exists without a code change; these branches are unit-test territory for `runInvocation` with an injected deadline.
5. **Heartbeat timing** is automatable only at wall-clock cost (S10-033, ~16 s): the ticker is constructed per request inside the worker isolate (`worker.ts:L285-L306`) with a hardcoded 15 000 ms interval, so `vi.useFakeTimers` in the test module does not control it. If heartbeat coverage ever needs to be fast, the seam would be injecting `HeartbeatTicker` through wiring — a code change, not a test harness change.
6. **Missing accept context (S10-034)** is not reachable by any client action: the store is request-scoped and pre-accept always populates it before the event source runs in the same `handleAdapterRequest` call. The scenario requires the `Map.prototype.get` spy seam described there; it is listed here so reviewers know pure `POST /v1/requests` cannot trip it.
7. **`context_requested` terminal** is unreachable for visit summary: the manifest is `single_shot`, neither broker emits it, and `pushTerminalEvent` throws for `single_shot` (`adapter.ts:L122-L128`). It becomes relevant only when a conversational capability is registered — cover it in that capability's stage chapter, not here.
