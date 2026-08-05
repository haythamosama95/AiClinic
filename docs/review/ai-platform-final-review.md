# AI Platform — Final Cross-Slice Review

| Field | Value |
| --- | --- |
| Branch reviewed | `ai/master` (post-merge of all slice review fixes, HEAD `97253fe0`) |
| Architecture source of truth | [`docs/architecture/17-ai-platform.md`](../architecture/17-ai-platform.md) |
| Delivery plan | [`docs/architecture/17b-ai-platform-delivery-plan.md`](../architecture/17b-ai-platform-delivery-plan.md) |
| Prior per-slice reviews | [`docs/review/ai-platform-slices/`](ai-platform-slices/README.md) — all comments addressed and merged |
| Review type | Static, whole-directory (cross-slice seams prioritized) |
| Date | 2026-08-05 |

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Critical Issues](#2-critical-issues)
3. [Bugs](#3-bugs)
4. [Architectural Deviations](#4-architectural-deviations)
5. [Missing or Weak Tests](#5-missing-or-weak-tests)
6. [Recommended Improvements](#6-recommended-improvements)

---

## 1. Executive Summary

This is the final whole-directory review of `ai-platform/` after every per-slice review comment (slices A1–J4) was addressed and merged back to `ai/master`. Five parallel review passes covered: request-pipeline core, provider/invocation/streaming resilience, control plane & security, journaling/retention/schema, and test coverage. Prior slice fixes were spot-verified and are genuinely closed (B2 operator auth, B4 quota-DO concurrency, J4 atomic token-contract rotation, J3 routing-policy status model, A6 adapter ingress gating, F5 load-harness realism, H1/H2 conversational validation).

The slice fixes hold up. What the per-slice reviews could not see — and what this review found — is a class of **cross-module seam defects**: individually well-built slices whose interfaces don't meet in the middle. The findings concentrate on the `src/pipeline/index.ts` guard orchestrator, which is the only production composition of the §6.1 ten-stage guard and currently has no wired production caller and almost no failure-path test coverage.

**Totals: 5 Critical, 25 Medium, 0 Low reported (by design).**

Critical themes:

1. **The idempotency replay path is broken end-to-end.** A duplicate request with a reused idempotency key — the exact case the mechanism exists for — is mapped to a retryable `internal_error` (§2.1).
2. **Conversational requests lose their transcript.** The H2-validated transcript is dropped inside the guard pipeline before cost pre-flight and prompt composition, so conversational legs compose with no history and evade transcript pricing (§2.2).
3. **The cancellation chain is severed at two seams.** Client disconnect cannot reach the stream broker, and no abort signal can reach the in-flight provider fetch — cancelled requests run and bill to completion and are journaled `completed` (§2.3, §2.4).
4. **A latent clock-unit mismatch will reject 100% of admissions** the moment the guard pipeline is wired to production traffic (§2.5).

Medium findings cluster around: retry/fallback correctness (text splicing, `Retry-After` ignored, deadline not enforced on attempts), journaling seams (stuck `Accepted` rows, unpopulated `routing_tier`), control-plane safety (routing-policy transitions that can take serving down, non-atomic audit writes, unclosable key-rotation overlap), retention/privacy gaps (unbounded `platform_counter`, orphaned R2 envelopes, incomplete installation purge), and resilience limits (unbounded provider response bodies). Test coverage is strong at the module level but weak exactly where the Criticals live: the pipeline composition glue and worker entry seams.

**Bottom line:** the platform is in good shape at the unit level and the slice-review campaign was effective, but the guard pipeline should not be wired to production traffic until the five Criticals are fixed and pipeline-level failure-path tests exist.

## 2. Critical Issues

### 2.1 Idempotent replay is mapped to `internal_error` instead of returning the original request

- **Severity**: Critical · **Category**: Bug
- **Location**: `ai-platform/src/pipeline/index.ts:321-326` (seam with `ai-platform/src/admission/index.ts:62`)

`runAdmission` has a first-class success outcome `{ ok: true, outcome: "idempotent", priorState }` — exactly the "or returns the original request" branch of §6.1 stage 8. `runGuard` treats any outcome other than `"admitted"`/`"grace_admitted"` as failure: `return fail(8, "internal_error", started)`. Traced path: client retries POST with the same `x-idempotency-key` → stage 8 admission → Quota DO recognizes the key → `outcome: "idempotent"` → guard emits `internal_error`.

**Impact**: every transport retry with a reused idempotency key receives a 500-class `internal_error`, which the taxonomy marks `retry_safe: true` (`errors.ts:131-136`), so a compliant client retries and fails forever; the original result can never be recovered through the guard. It also compounds with §3.7 (burned keys from stage-9 failures loop here).

**Recommendation**: handle `outcome === "idempotent"` explicitly in `runGuard`: short-circuit stages 9–10 and return a success variant carrying `priorState` so the adapter can replay the original terminal response (or surface current state via the `getRequest` shape). Add a pipeline-level duplicate-key test.

### 2.2 Conversational transcript is validated at stage 6, then silently dropped before pre-flight and composition

- **Severity**: Critical · **Category**: Bug (cross-module seam: H2 validator/preflight ↔ H3 pipeline ↔ composer)
- **Location**: `ai-platform/src/pipeline/index.ts:33-44, 280-306, 348-353`; contrast `ai-platform/src/prompt/composer.ts:275-279` and `ai-platform/src/context/preflight.ts:38-59`

Two defects, one root cause. (a) `validateContext` parses, orders, budget-checks, and returns `validatedTranscript` (`context/validator.ts:391-396`), and `composeRequest` renders prior turns only when `input.transcript` is supplied (`composer.ts:275-279`) — but `runGuard` narrows the stage-6 result to `filteredContext`, defines the injected `ComposeRequestFn` without a `transcript` parameter, and calls it with no transcript. (b) Stage 7 hand-serializes `JSON.stringify({ filteredContext, userIntent })` instead of calling `serializePreflightInput`, whose own contract states "conversational legs MUST include the validated transcript so growth is priced by the existing estimator (H2)". H2 deferred this seam to the composition layer; it was never closed. The only conversational pipeline test stubs composition, so nothing catches it.

**Impact**: every conversational leg reaches the provider with zero prior-turn history — context-free answers journaled as normal conversational turns. Simultaneously, stage-7 cost pre-flight undercounts by up to `transcriptSizeLimit` bytes, so the per-request cost ceiling and max-input-window predicates admit requests whose real composed prompt blows both at the paid provider call.

**Recommendation**: thread the transcript through: add `transcript?: Transcript` to `ComposeRequestFn` input and `GuardSuccess`, populate from `contextResult.validatedTranscript`, use `serializePreflightInput({ filteredContext, userIntent, transcript })` at stage 7, and pass it into the stage-10 compose call. Add a pipeline test asserting composed requests contain rendered prior turns and that oversized transcripts fail stage 7 with `request_too_large`.

### 2.3 Client disconnect is invisible to the event source — broker `disconnect()` is uncallable from the production seam

- **Severity**: Critical · **Category**: Concurrency
- **Location**: `ai-platform/src/adapter.ts:47-51, 366-408`

A6-R1 fixed dead-socket writes by making `cancel()` and the abort listener only set `terminalEmitted` — but nothing replaced it as a *notification* to the event source. `AdapterEventSourceFactory` is `(sink, context) => unknown`: `AdapterStreamContext` carries no `AbortSignal`, and the factory's return value is discarded. Traced path: client closes stream → `ReadableStream.cancel()` → `markCancelledWithoutEnqueue()` → later `sink.push` calls silently dropped. The D4 brokers expose `disconnect(reason)` precisely for this event, but the adapter's contract gives the wiring no way to call it.

**Impact**: every documented cancellation guarantee (§5.5 rule 5, §6.5, §8.7) silently fails on the real path: the broker never aborts, keeps relaying into a dead sink, and on provider completion journals `completed` for a request the client cancelled — no partial usage credited, provider fetch bills to completion.

**Recommendation**: extend the seam so disconnect reaches the event source: type the factory return as `{ disconnect?(reason): void }` and invoke it from both `cancel()` and the abort listener, and/or add an `AbortSignal` to `AdapterStreamContext`. Test: `reader.cancel()` mid-stream → broker `disconnect` called exactly once → terminal `cancelled`, partial credit, journal `cancelled`.

### 2.4 `runInvocation` accepts no external cancellation signal — a client abort can never reach the in-flight provider fetch

- **Severity**: Critical · **Category**: Concurrency
- **Location**: `ai-platform/src/invocation/index.ts:49-59, 270-301, 394-399`

Even with §2.3 fixed, the abort chain stops at the broker. `InvocationInput` has no `signal` input; `invokeWithTimeout` constructs its own `AbortController` whose signal is the only one ever passed to `port.invoke`. There is also no live-partial-usage surface, so `ChunkSource.getPartialUsage` ("must reflect tokens actually generated before the cancel point") has no honest producer.

**Impact**: §8.7's "GW→PRV: abort in-flight fetch via abort signal" is unimplementable with the current interfaces. A cancelled request's provider call continues until the adapter deadline (up to 30s+), fully billed — and §6.5's "cancellation credits partial usage … free cancellation would be a quota-evasion vector" is inverted: cancellation is always free.

**Recommendation**: add `signal?: AbortSignal` to `InvocationInput`; chain it into the attempt controller in `invokeWithTimeout` (abort on either entry timeout or caller signal) and classify caller-abort as terminal `cancelled`, not `timeout`. Expose a per-run partial-usage accessor so `getPartialUsage` has a real source. Together with §2.3 this closes the full client→broker→invocation→provider abort chain.

### 2.5 Stage-8 admission clock compares milliseconds against second-based `exp` — rejects every request once wired

- **Severity**: Critical (latent) · **Category**: Bug
- **Location**: `ai-platform/src/admission/index.ts:303-313` (seam with `ai-platform/src/pipeline/index.ts:228-231, 309-320`)

`runAdmission` computes `const now = ctx?.now ?? Date.now()` then applies `if (now > principal.exp + ADMISSION_CLOCK_SKEW_SECONDS)`. `principal.exp` is a JWT NumericDate in **seconds** (verified elsewhere against `Math.floor(Date.now()/1000)`), but stage 8 is invoked with raw `input.now`, which is `undefined` on the default path — so `runAdmission` falls back to `Date.now()` in **milliseconds** (~1.77e12 vs `exp` ~1.77e9). The comparison is unconditionally true and every admission returns `{ ok: false, code: "unauthenticated" }`. Latent today only because `runGuard` has no production caller.

**Impact**: total outage of the request path the moment stage 8 is wired, with a misleading error code (clients see auth failure, not a platform defect) and polluted `unauthenticated` guard counters.

**Recommendation**: normalize units at the `runAdmission` boundary (`ctx?.now ?? Math.floor(Date.now()/1000)`), have the pipeline pass its already-computed seconds fallback to stage 8, and add a test calling `runAdmission` with no `ctx.now` against a principal minted with a real second-based `exp`.

## 3. Bugs

All Medium severity, grouped by subsystem.

### 3.1 Pipeline, journaling & control plane

#### 3.1.1 Provider-scoped kill switch can never fire

`ai-platform/src/capability/index.ts:280-319` — `isCapabilityDisabled` checks a `provider:<id>` kill-switch key only when `resolveProviderId` returns a value, but that function reads `policy.provider_id` off the routing-policy row/document, a field that exists in **neither** the D1 `routing_policy` table nor the R2 `RoutingPolicyDocument` (providers live only inside `rules[].targets[]`). In production it always returns `undefined`; the C1 test passed because fixtures fabricate the field. Relatedly, `RouterContext.killedProviderIds` (`router/index.ts:37`) has no producer. **Impact**: the emergency provider-outage lever silently disables nothing; requests keep routing to a provider operations believes is off. **Fix**: derive the provider set from the resolved routing decision's chain post-`selectCandidateChain` and feed matches into `killedProviderIds`, or enforce the provider scope solely in the router; fix the C1 test to use the real policy shape.

#### 3.1.2 Stage-10 composition failure leaves the journaled row in `Accepted` forever

`ai-platform/src/pipeline/index.ts:343-345, 355-357` — stage 9 creates the `ai_request` row; on stage-10 failure `runGuard` returns `fail(10, ...)` with no `recordTerminalState` call. Stage 10 is the only post-journal guard stage, so every composition failure freezes a row in `Accepted`: `getRequest` reports `pending: true` indefinitely (`journal/index.ts:488-491`), reconciliation never flags it (terminal-states only), and only the 90-day purge cleans it up. **Impact**: clients poll a dead reference forever; support lookup shows a request that "never finished"; violates §6.3's terminal-state guarantee. **Fix**: call `recordTerminalState(requestId, "Failed", composed.code, …)` on every post-stage-9 failure path; pin with a test.

#### 3.1.3 `routing_tier` is never populated by the only stage-9 writer

`ai-platform/src/pipeline/index.ts:323-341` vs `ai-platform/src/journal/index.ts:254`, `ai-platform/src/soft-threshold/index.ts:32-52` — `runGuard` holds the admission outcome (`admitted`/`grace_admitted`) but calls `createRequestRow` without `routingTier`, so the column is NULL for 100% of journaled requests, including every degraded-tier grace admission. F4 explicitly recommended this wiring when the orchestrator landed; `routingTierFromAdmission` is referenced only by tests. **Impact**: degraded-routing analytics, per-tier dashboards, and tier auditability are silently empty. **Fix**: derive the tier at stage 9 via `routingTierFromAdmission` (or `grace_admitted → "degraded"`) and pass it into `createRequestRow`; pin with a grace-admission pipeline test.

#### 3.1.4 `journalTransition`'s terminal branch writes `Failed` with no `terminal_error_code` — C3-R3 enforced in only one of two writers

`ai-platform/src/journal/index.ts:282-291` vs the guarded `recordTerminalState` at `:313-325` — the C3-R3 invariant "Failed requires a terminal error code" throws in `recordTerminalState` but `journalTransition` accepts any terminal state with no code. A `Failed` row written this way surfaces through `getRequest` as an `"internal_error"` fallback, masking the violation exactly as C3 Bug 6 described. Latent only because `journalTransition` currently has no caller. **Fix**: reject `Failed` in `journalTransition` (terminal writes must go through `recordTerminalState`) or give it the same parameter and throw; add symmetric tests.

#### 3.1.5 Routing-policy canary/rollback allow transition into a zero-active state that fails all non-cohort traffic

`ai-platform/src/control/routing-policy.ts:146-198, 329-357` — the J3 status column was added, but handlers never validate current status before transitioning. (a) `handleRoutingPolicyCanary` unconditionally sets `status='canary'` — including on the sole `active` row, leaving no active version; the request-path reader then returns `miss` for every non-cohort installation and the router throws `ConfigCacheMissError`. (b) `handleRoutingPolicyRollback` on the sole `active` version with no `superseded` prior produces the same outage with a 200. **Impact**: one operator typo takes the policy down for all non-cohort installations — a self-inflicted serving outage on what §4.5 calls the highest-leverage actions in the system. **Fix**: reject `canary` unless current status is `published`/`canary` (409 `illegal_policy_transition`); reject `rollback` of an `active` version with no superseded prior; test the invariant "exactly one `active` row per policy after every mutation".

#### 3.1.6 Grace reconciliation can wedge an entry forever and can settle the wrong request

`ai-platform/src/credit/index.ts:168-204` with `ai-platform/src/quota-do/index.ts:320-337, 408-414` — `reconcileGraceUsage` re-presents queued grace admissions with their original `jti`/key; both failure shapes requeue, and the queue has **no TTL, no max attempts, no drop path**. Common collision: DO down at T0 → grace-admitted; client retries at T1 after DO recovery → retry legitimately admitted and credited; next cron tick re-presents the grace entry → `idempotent` with the retry's `requestId` → credit returns `unknown_request` → requeued forever, every tick, for the isolate's lifetime. Worse, if cron lands between the retry's admission and its stage-15 credit, the grace entry's stale usage settles the retry's `requestId` first and the real credit is dropped — actual usage silently uncounted. **Fix**: on `idempotent`/`replay` outcomes and `unknown_request` credits, treat the entry as settled-by-another-path and drop it (journaled); add entry expiry/max-attempts; never credit a DO-issued `requestId` that didn't come from this entry's `admitted` outcome.

#### 3.1.7 `GatewayObject.fetch` collapses all internal RPC failures to `400 bad_request` and logs nothing

`ai-platform/src/worker.ts:75-96` — the `try/catch` around `admissionRPC`/`creditRPC` returns 400 for *any* thrown error, including DO storage failures, with no logging. Since the admission caller maps non-2xx DO responses into the grace path, internal faults are indistinguishable from client wire bugs: they burn grace admissions and leave no diagnostic trail. **Fix**: return 400 only for known arg-validation failures; 500 with a logged structured error (trace/installation context) for everything else.

#### 3.1.8 Stage-9 journal failure leaks the stage-8 admission — no compensation path

`ai-platform/src/pipeline/index.ts:310-345`; `ai-platform/src/quota-do/index.ts:76-100` — once stage 8 admits, the DO has recorded the idempotency key, `jti`, and quota/concurrency reservation. If stage 9's `createRequestRow` fails, the guard returns `internal_error` with no compensating action — the DO RPC surface has no release/rollback. The admission is orphaned: quota and concurrency headroom consumed against a request row that doesn't exist, and the idempotency key is burned so the client's natural retry lands in the §2.1 path. **Fix**: add a `release` RPC to the Quota DO invoked on stage-9 failure, or fold row creation into the admission round trip; at minimum record a guard-rejection tally so the leak is observable.

### 3.2 Provider, invocation & streaming

#### 3.2.1 Same-target retry after a partial stream splices text with no `regenerating` event

`ai-platform/src/invocation/index.ts:371-375, 386-436`; consumer `ai-platform/src/stream/index.ts:322-331` — `emitRegenerating()` fires only at chain-target boundaries, but the port explicitly permits partial chunks on failure (`provider/port.ts:42-45`). If a multi-attempt target fails retryably after emitting partial chunks, the same-target retry's text is relayed with no `regenerating`; the brokers reset assembly only on regenerating, so two attempts' text is concatenated and emitted as `finalContent` with `authoritative: true`. **Impact**: violates §8.6 "never splice output" — clients can be served fused mid-sentence text as the validated answer. Latent today only because no current adapter attaches error chunks; the contract invites it. **Fix**: emit `regenerating` before the first emission of any attempt following partial-stream emission on the same target; add the partial→retry→regenerating test.

#### 3.2.2 Prose broker cannot detect truncation — truncated prose is emitted as authoritative `completed`

`ai-platform/src/stream/index.ts:24-31, 265-288`; producer `ai-platform/src/invocation/index.ts:223-232` — D6-R3 added `wasTruncated()` to the *structured* broker only. The prose `ChunkSource` has no truncation input and `runFullGuardSet` doesn't check it, while `processInvokeResult` maps `truncation` to success — so a `finishReason: "length"` result flows to a `completed` event with `authoritative: true` partial text and no truncation marker anywhere. **Impact**: §4.3.9's "empty or truncated output" guard is dead on the prose path; a length-cut clinical summary is delivered as a complete answer. **Fix**: mirror the structured fix — add `wasTruncated?()` to the prose `ChunkSource`, populate from the truncation outcome, fail terminally (`validation_failed`) or mark non-authoritative.

#### 3.2.3 Gemini stream-frame classifier substring-matches `"rate"` — misclassifies "generate"/"accurate" messages

`ai-platform/src/provider/gemini.ts:344-353` — `classifyProviderErrorFrame` checks `message.includes("rate") || includes("quota")` *before* the `INTERNAL`/`UNAVAILABLE` branch. `"rate"` is a substring of "generate", "accurate", "moderate", "operate" — all plausible in vendor error prose. A terminal `INVALID_ARGUMENT` frame ("…is not accurate…") classifies as retryable `rate_limited`; a 500 INTERNAL frame ("…failed to generate…") is journaled as `rate_limited`. DeepSeek's equivalent correctly uses the structured token. **Impact**: terminal errors retried and fallback-triggered (wasted spend on already-billed partial streams); corrupted per-attempt diagnostics. **Fix**: classify on structured signals only (`status === "RESOURCE_EXHAUSTED"`, explicit tokens), drop bare message substrings, order the server-side branch first.

#### 3.2.4 Provider `Retry-After` is dropped — 429 retries fire after ~100ms and burn the attempt budget

`ai-platform/src/provider/gemini.ts:678-694`, `ai-platform/src/provider/deepseek.ts:580-596`, `ai-platform/src/invocation/index.ts:108-116, 423-431` — both transports receive response headers but discard `retry-after` on 429; the invocation sleeps ~100–150ms of jittered backoff and re-hits the still-limited provider. Provider cooldowns are typically seconds, so a 429 exhausts `max_attempts` and forces fallback (or `provider_unavailable`) when simply waiting would have succeeded. **Fix**: parse `Retry-After` (seconds + HTTP-date) in both adapters, carry it on `CanonicalError`, and sleep `max(jitteredBackoff, retryAfterMs)` clamped by the request deadline.

#### 3.2.5 Request `deadline` clamps inter-retry sleeps but never the attempts themselves

`ai-platform/src/invocation/index.ts:303-330` vs `:394-399` — D3-R3 added deadline-aware sleep truncation, but the attempt race still uses unclamped `entry.timeout_ms`, and the *stale original* `request.deadline` is handed to every invoke. A request with `deadline: 5_000` and two `timeout_ms: 30_000` targets can run ~60s+; only sleeps shrink. **Impact**: systematic budget violation on multi-attempt walks — exactly the provider-outage walks where the budget matters most. **Fix**: compute remaining deadline before each attempt and use `min(entry.timeout_ms, remainingMs)` in `invokeWithTimeout`, skipping targets whose budget is exhausted; propagate remaining-ms, not the original.

#### 3.2.6 `abortableAsyncIterate` can hang forever in its `finally` on the exact hung-source case it guards against

`ai-platform/src/stream/index.ts:137-175`, `ai-platform/src/stream/structured.ts:113-152` — the helper exists "so a signal-ignoring source cannot hang the broker", but its `finally` does `await iterator.return(undefined)`. For an async-generator source with a pending `next()`, `return()` queues behind the pending `next()` per spec and never settles. The client is saved (disconnect emits terminal synchronously), but `run()` never resolves and the heartbeat ticker is never cancelled. **Impact**: leaked per-request promise and live heartbeat in the isolate for every disconnect-during-hung-source; if wiring awaits `run()` via `ctx.waitUntil`, request lifetime is held indefinitely. **Fix**: fire `iterator.return()` without awaiting (or race a short timer); guarantee `heartbeatHandle.cancel()` via the terminal-emission path.

## 4. Architectural Deviations

All Medium severity.

### 4.1 Broker `failed` events bypass the adapter's frozen error body

`ai-platform/src/stream/index.ts:249-256`, `ai-platform/src/stream/structured.ts:241-246` vs `ai-platform/src/adapter.ts:108-121` — two producers emit terminal `failed` SSE events with different payloads. The adapter builds the full body via `buildErrorBody` (`code`, `request_reference`, `trace_id`, `retry_safe`); both brokers push `{ type: "failed", data: { code } }` directly. §5.4: "Every error response carries the request reference, the trace id, and whether a retry is safe." On the broker path — the only path real failures will take once wired — `request_reference` and `retry_safe` are absent. **Fix**: route broker terminal failures through `buildErrorBody` (pass `requestReference` into broker options), or make `pushTerminalEvent` the single terminal-event producer.

### 4.2 `platform_counter` has no retention purge — unbounded growth contra §7.7

`ai-platform/src/retention/index.ts:100-214` never touches `platform_counter`; buckets are minute-granular (`rate-limit/index.ts:46-49`), so the table accumulates one row per dimension-set per minute forever. §7.7 assigns it a "Months" horizon and §7.3 calls it "Bounded, low cardinality". This also corrupts a metric: the quota-rejection-rate numerator (`SUM` over all counter rows, `dashboards/index.ts:132-148`) accumulates forever while the denominator (`ai_request` count) is truncated to 90 days by the journal purge — from day ~90 the rate drifts monotonically upward and can exceed 1.0 on an incident dashboard. **Fix**: add a `DELETE FROM platform_counter WHERE time_bucket < ?` at a months-class cutoff to `runRetentionPurge`; bound the dashboard numerator to the same window as the denominator.

### 4.3 Diagnostic-horizon bounds unenforced — late purge of short classes, permanent R2 orphans for long classes

`ai-platform/src/retention/index.ts:119-133, 42-48, 174-178`; `ai-platform/src/manifest/index.ts:74` — nothing constrains `diagnostic_Nd` to the §7.7 "days to weeks" band. (a) The diagnostic scan prefilters at the hardcoded 7-day baseline, so a `diagnostic_3d` manifest retains PII envelopes 4 extra days. (b) A horizon longer than the 90-day journal horizon (e.g. `diagnostic_365d`) orphans the envelope permanently: the journal purge deletes the referencing row at day 90, after which neither the diagnostic scan nor `purgeByInstallationId` (both iterate `ai_request`) can ever find the PII-bearing R2 object. **Fix**: validate `retentionClass` at manifest load/publish against an enforced band (1–90 days); make the prefilter `min(diagnostic horizons)`; and/or have the journal purge delete the R2 envelope (when present) before deleting an expired row regardless of class horizon.

### 4.4 `purgeByInstallationId` is incomplete — NULL-pointer envelopes and installation-scoped rows survive

`ai-platform/src/retention/index.ts:230-263`; enabling state at `ai-platform/src/journal/index.ts:387-395` — (a) the R2 loop deletes only `if (row.payload_pointer)`, but stage 16 writes the envelope *before* the pointer, so a mid-sequence failure leaves an object at the derivable key `request/{id}/envelope` with NULL pointer — full prompt/context/result PII surviving an installation purge. (b) The D1 batch omits installation-scoped `capability_grant` rows (written by cohort activation), and nothing ever removes `installation`, `installation_key`, or `entitlement` rows — "purge by installation id" leaves the installation's identity and commercial footprint intact while the purge audit row falsely implies completeness. **Fix**: delete R2 objects by derived key unconditionally; add scope-matched `capability_grant` deletion; decide explicitly in the retention contract whether purge also removes/anonymizes `installation`/`installation_key`/`entitlement`, and wire it.

### 4.5 Key rotation never closes the overlap — no revoke path, and `valid_from`/`valid_until` are dead columns

`ai-platform/src/control/lifecycle.ts:210-284`; `ai-platform/src/identity/index.ts:280-320` — `handleRotate` only INSERTs a new key; no control-plane action can retire a key, so after every rotation the old key verifies indefinitely. Even hand-editing D1 wouldn't help: the verifier checks only `revoked_at` and ignores `valid_from`/`valid_until` entirely. §8.1 describes dual-acceptance "during the overlap" — an overlap the code can never end short of suspending the whole installation. **Impact**: a compromised clinic signing key remains usable forever; rotation provides availability but zero compromise recovery. **Fix**: add a control-plane `revoke-key` action stamping `revoked_at` (batch-audited like siblings); enforce `valid_from <= now < COALESCE(valid_until, +inf)` in `EnrolledKeyVerifier`; optionally stamp `valid_until` on superseded keys at rotate time.

### 4.6 Token-contract rotation and installation purge commit the mutation before a separate, non-atomic audit write

`ai-platform/src/control/token-contract.ts:40-60, 88-118`; same shape in `ai-platform/src/control/support-purge.ts:76-83` → `ai-platform/src/retention/index.ts:216-266` — every other control handler writes mutation + `control_audit` in one atomic `DB.batch`; these two write the mutation first, then audit separately. If the audit insert fails, the rotation/retirement (or a partial purge) is committed with no audit row, and the operator's retry gets `409 ver_already_exists`, obscuring that the change went through. §4.5: "Every control-plane mutation is journaled with the operator identity." **Fix**: single `DB.batch` for both token-contract handlers; for purge, write the intent-to-purge audit row first or batch the D1 deletes with the audit insert.

### 4.7 Unauthenticated callers can inject arbitrary `installation_id` cardinality into `platform_counter`

`ai-platform/src/identity/index.ts:57-63, 251-260`; flush at `ai-platform/src/rate-limit/index.ts:139-163` — the identity stage tallies guard rejections under `payload.iss` taken from the **unverified** token payload for audience/expiry failures, which run before signature verification. `recordGuardRejection` buckets by `installation_id`, and the flush upserts one permanent D1 row per distinct dimension set per minute. An attacker minting forged tokens with random `iss` forces unbounded row growth and pollutes all §4.3.12 guard metrics — with no rate limiter in front (identity is stage 2; rate limiting is stage 4). **Fix**: tally pre-verification failures under a constant `"unverified"` bucket; attribute `installation_id` only after signature verification; optionally cap distinct ids per flush window.

### 4.8 No size bound on provider response bodies — unbounded isolate memory

`ai-platform/src/provider/gemini.ts:26-30`, `ai-platform/src/provider/deepseek.ts:24-28`; contrast the 1 MiB ingress cap at `ai-platform/src/adapter.ts:11` — the buffered transport materializes the entire provider response as one string with no byte cap, then SSE parsing builds an events array plus an assembled string of comparable size. A malfunctioning or hostile endpoint can return an arbitrarily large 200 body. **Impact**: one oversized response can exhaust the isolate's 128 MB, killing every in-flight request in it — a resilience/DoS surface with no equivalent of the ingress gate. **Fix**: enforce a documented provider-body cap in the transport with a byte-counting reader mirroring `readBodyWithinLimit`; abort and classify when exceeded.

## 5. Missing or Weak Tests

Module-level coverage is genuinely strong (behavioral, negative-path, and concurrency tests against real Miniflare D1/R2/DO — see the per-module coverage map in the appendix of the test review). The gaps sit exactly where the Criticals live: the composition glue.

### 5.1 Pipeline guard composition has zero failure-path coverage — Medium

`src/pipeline/index.ts` (`runGuard` stages 1–10 `fail()` branches, `settleHappyPath` error branches) is exercised only by `test/load/happy-path.ts` and `test/conversational-journaling.test.ts` — both success-only. No test forces a single stage failure: stage ordering/short-circuiting, per-stage taxonomy mapping, the `idempotent` outcome handling (§2.1), transcript threading (§2.2), or `guardLatencyMs` on failure. A stage reorder or wrong code mapping ships undetected while the load suite stays green. **Add** a workers-pool `pipeline.test.ts` forcing each stage to fail (oversized body, bad token, suspended installation, rate-limit deny, unknown capability, invalid context, over-ceiling preflight, quota-exhausted admission, duplicate idempotency key, D1 insert failure, failing compose) asserting `{ ok: false, stage, code }` and that later stages' sinks were untouched (no DO fetch when failing at stage ≤7, no `ai_request` row when failing at stage ≤8).

### 5.2 Worker entry seams uncrossed — Medium

Four seams have no behavioral test through the worker boundary (`src/worker.ts`): (1) `POST /v1/requests` with no event source → the 503 fail-fast is pinned by nothing, so accidental wiring or route deletion fails no test; (2) `GET /v1/requests/:ref` response shaping (Completed ±result, pending, Failed, AwaitingContext, Cancelled, 404, 401) — covered at `getRequest` level but never through the worker's branch mapping; (3) `scheduled()` cron dispatch (retention `0 3 * * *`, rollup `0 4 * * *`, plus `flushRejectionCounters`/`reconcileGraceUsage` ordering) — the only assertion is a source-text grep that passes even if the call is never reached; (4) `GatewayObject.fetch` negatives (non-POST 405, invalid JSON, `unknown_kind`, and the catch-all from §3.1.7). **Add** `SELF.fetch` tests for the 503 and the GET reference matrix, invoke `scheduled` with cron values against spy D1/DO, and hit the DO stub with malformed inputs.

### 5.3 `handleInstallationPurge` — destructive control endpoint with zero tests — Medium

`src/control/support-purge.ts:55-83` (dispatch `src/control/index.ts:63,164-165`) — the operator-gated purge has no HTTP-layer test at all: no 401 non-operator case, no `invalid_route` case, no `missing_r2_binding` 500 case, no proof the `case "purge"` wiring reaches the handler. Every sibling mutation (enroll/rotate/suspend/resume/delete) has exactly these tests. Given §4.4's incompleteness findings, this endpoint needs both wiring and coverage. **Add** the sibling-mirrored matrix plus a happy-path test asserting target-only deletion and the audit row's `operator_id`.

### 5.4 Log-redaction test cannot see the actual logging paths — Medium

`test/log-redaction.test.ts:80-127` spies only `console.log`, but both failure-path log sites in `src/` use `console.error` (`journal/index.ts:405`, `prompt/composer.ts:329` — the latter passing the raw caught error object). The exercised request paths trigger no `src/` logging, so the "some logs captured" assertion is satisfied by wrangler's own dev-server output; there is no canary proving a worker log was captured. A regression logging prompt text or bearer material via `console.error` passes CI. **Fix**: spy `console.error`/`warn`/`info`, drive a path that provably logs (e.g. forced stage-16 persistence failure), and assert a canary line was captured before asserting absence of sensitive markers.

### 5.5 Golden eval gate: one case, and output-side assertions are constant under the fixture transport — Medium

`test/eval/` — the golden gate for the only production capability runs exactly one case (`visit_summary.happy_path`), and `output_must_contain`/`output_min_length` are evaluated against a *recorded fixture* provider response — a constant that can never fail in the golden run regardless of prompt regressions. The gate's entire discriminating power is five system-instruction needles plus the request-system golden; live-smoke asserts only `min_length: 1`. **Add** at least one negative golden case (insufficient-context input expecting a "what is missing" response), a harness-level control proving `output_must_contain` participates in golden failure (deliberately-regressed fixture response variant), and a stronger live-smoke expectation.

### 5.6 `env-deploys` startup-failure tests assert on a 3-second hang — Medium

`test/env-deploys.test.ts:111-137` — "fails at startup when a binding is missing" is proven by `Promise.race` against a 3s timeout asserting `outcome.kind === "timeout"`: wall-clock-dependent on loaded CI runners (the file spawns up to 7 `unstable_dev` instances), conflates "startup failed" with "fetch hangs", and would produce a hard test error rather than a clean assertion failure if wrangler goes fail-fast. **Fix**: assert the startup failure directly (rejects or 5xx, per current wrangler behavior), keeping the timeout only as a generous hang guard.

## 6. Recommended Improvements

Ordered by leverage. Items 1–2 are prerequisites for wiring the guard pipeline to production; item 3 before enabling real streaming traffic.

1. **Close the pipeline's broken seams before wiring it (Criticals §2.1, §2.2, §2.5).** Handle the `idempotent` admission outcome, thread the validated transcript through pre-flight and composition, and normalize the stage-8 clock to seconds. Land the pipeline failure-path test suite (§5.1) in the same change — each fix should ship with the test that would have caught it.
2. **Build the full cancellation chain (Criticals §2.3, §2.4).** Adapter → broker (`disconnect()`/`AbortSignal` on the event-source context), broker → invocation (`signal` on `InvocationInput`), invocation → provider fetch (chained abort, caller-abort classified `cancelled`), plus a real partial-usage source so cancelled requests credit honestly. Verify end-to-end with the mid-stream `reader.cancel()` test.
3. **Harden retry/fallback against real provider behavior (§3.2.1–§3.2.5).** `regenerating` on same-target partial retries, prose truncation detection, structured-only Gemini classification, `Retry-After` honoring, and remaining-budget attempt clamping. These five are cheap, independent, and jointly determine whether outages degrade gracefully or amplify cost.
4. **Make the control plane fail-safe for operators (§3.1.5, §4.5, §4.6).** Routing-policy transition guards with the one-active-row invariant, a key-revoke action with enforced validity windows, and atomic mutation+audit batches on token-contract and purge.
5. **Close the retention/privacy gaps (§4.2–§4.4).** `platform_counter` purge with dashboard-window alignment, enforced diagnostic-horizon bands, derived-key R2 deletion, and an explicit contract decision on installation identity rows — then the purge endpoint tests in §5.3.
6. **Strengthen the two guards that only look green (§5.4, §5.5).** Redaction canary on the `console.error` paths and golden-eval output-side negative controls.
7. **Standing practice going forward.** The pattern across all five Criticals is identical: a slice's contract points at a seam "to be wired later," and nothing tracked the deferred half. Consider a lightweight integration checklist in the delivery plan — every slice that introduces an injectable seam (event source, compose fn, disconnect hook, routing tier) must either wire it or file the follow-up in the same PR — plus a pipeline-level contract test that runs the ten-stage guard against real D1/DO on every change.

---

*Review method: five parallel static passes over `ai-platform/` (pipeline core; provider/invocation/streaming; control plane & security; journaling/retention/schema; tests), each verifying candidate findings by tracing full call paths. Prior per-slice review fixes were spot-verified as correctly implemented and were not re-reported.*
