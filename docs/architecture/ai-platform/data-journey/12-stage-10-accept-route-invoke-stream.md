# AI Platform Data Journey — Stage 10 — Accept, route, invoke, stream

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [Boundary with Stage 9 (the guard)](#3-boundary-with-stage-9-the-guard)
4. [HTTP response shape](#4-http-response-shape)
5. [Runtime flow — fresh path](#5-runtime-flow-fresh-path)
6. [Phase A — SSE `accepted`](#6-phase-a-sse-accepted)
7. [Phase B — Dispatch (fresh vs idempotent)](#7-phase-b-dispatch-fresh-vs-idempotent)
8. [Phase C — Routing (D1 + R2)](#8-phase-c-routing-d1--r2)
9. [Phase D — Provider invocation](#9-phase-d-provider-invocation)
10. [Phase E — Stream relay and output guards](#10-phase-e-stream-relay-and-output-guards)
11. [SSE events — every field](#11-sse-events-every-field)
    - [`accepted`](#111-accepted)
    - [`heartbeat`](#112-heartbeat)
    - [`regenerating`](#113-regenerating)
    - [`text_delta`](#114-text_delta)
    - [`completed`](#115-completed)
    - [`failed`](#116-failed)
    - [`cancelled`](#117-cancelled)
    - [`context_requested`](#118-context_requested)
12. [CanonicalRequest — every field](#12-canonicalrequest-every-field)
    - [Top-level fields](#121-top-level-fields)
    - [`parts[]`](#122-parts)
13. [Provider wire transformation](#13-provider-wire-transformation)
    - [DeepSeek (`deepseek-v4-flash`)](#131-deepseek-deepseek-v4-flash)
    - [Gemini (`gemini-3.5-flash`)](#132-gemini-gemini-35-flash)
14. [Invocation retry and fallback logic](#14-invocation-retry-and-fallback-logic)
15. [Idempotent replay path (no provider call)](#15-idempotent-replay-path-no-provider-call)
16. [Failure paths after `accepted`](#16-failure-paths-after-accepted)
17. [Settlement handoff (Stage 11)](#17-settlement-handoff-stage-11)
18. [Spec vs platform behavior today](#18-spec-vs-platform-behavior-today)

---




## 1. Plain language

If the guard passed, the HTTP response opens as **Server-Sent Events (SSE)**. The first event is `accepted` — proof the job is admitted and the stream is live. What follows depends on the path:

- **Fresh path:** the platform loads a routing policy from D1 + R2, walks a provider chain (DeepSeek, then Gemini fallback), relays partial text as `text_delta`, runs output safety checks, emits one terminal event, then settles quota and storage ([Stage 11](13-stage-11-terminal-settlement.md)).
- **Idempotent replay:** the client retried with the same `x-idempotency-key` while Quota DO still knows the prior job — no routing, no provider call; the platform replays a terminal outcome from DO idempotency state.

This stage is where **latency and cost** happen. Everything before `accepted` was cheap validation; everything after is I/O to external models.

## 2. Metaphor

**Boarding and takeoff** — the guard was ten checkpoints from parking to the gate. `accepted` is the boarding call. Routing picks the runway and aircraft type; invocation is the flight; `text_delta` events are live position reports; the terminal event is landing (completed, diverted/failed, or cancelled mid-air).

## 3. Boundary with Stage 9 (the guard)

The guard ([Stage 9](11-stage-9-the-guard.md)) finishes **before** the SSE body starts. By the time the client sees `accepted`, the platform already has:


| Artifact | Fresh path | Idempotent replay |
| -------- | ---------- | ----------------- |
| `request_id` | Quota DO admission (or grace UUID) | Prior `request_id` from DO |
| `request_reference` | Gateway-generated `XXXX-XXXX` | Same on this HTTP connection |
| `CanonicalRequest` | Composed at guard stage 10 | **Not recomposed** |
| D1 `ai_request` row | INSERT with `state = Accepted` | **Skipped** |
| `routing_tier` on journal row | From admission / soft threshold | Unchanged from prior job |


**What the guard deliberately does *not* do:** pick a live provider, call DeepSeek/Gemini, or stream tokens. Routing runs **after** `accepted`. A request can pass the guard, receive `accepted`, and still fail with `provider_unavailable` if every chain entry is excluded or exhausted.

**Two different “trace” identifiers:**


| Name | Source | Used for |
| ---- | ------ | -------- |
| SSE / D1 `trace_id` | Header `x-trace-id` or server ULID | Every SSE event, HTTP error bodies, support lookup |
| `CanonicalRequest.correlationIds.trace_id` | AAT claim `jti` | Provider-side correlation inside the canonical contract only |


Do not assume they are the same value.

## 4. HTTP response shape


| Item | Value |
| ---- | ----- |
| Status | `200` (guard failures never open SSE — they return HTTP JSON from [Stage 8](10-stage-8-request-ingress.md)) |
| `Content-Type` | `text/event-stream` |
| `Cache-Control` | `no-cache` |
| `Connection` | `keep-alive` |
| Body | Sequence of SSE frames until one terminal event |

Each SSE frame:

```
event: <type>
data: <json object>

```

Every `data` object includes `trace_id` (same value as header `x-trace-id` when the client supplied one, otherwise the server ULID from ingress).

## 5. Runtime flow — fresh path

```
POST /v1/requests (guard 1–10 complete)     ← Stages 8–9
  ├─ SSE accepted emitted                     ← Phase A
  └─ background invoke pipeline               ← Phases B–E
       ├─ D1 routing_policy index + R2 policy document
       ├─ routing decision → provider chain   ← Phase C
       ├─ provider invoke (parallel with relay) ← Phase D
       ├─ SSE text_delta / regenerating / heartbeat ← Phase E
       ├─ terminal SSE (completed | failed | cancelled)
       └─ on completed → Stage 11 settlement (DO credit, D1, R2)
```

**Concurrency rationale:** provider invocation and SSE relay run in parallel so the clinic client sees `text_delta` while the model is still generating, instead of waiting for the full provider response.

**Client disconnect:** closing the POST or SSE connection aborts the in-flight provider request and drives terminal `cancelled` (unless a terminal event was already sent).

## 6. Phase A — SSE `accepted`

Emitted as the **first SSE frame**, immediately when the stream opens, **after** the guard succeeds and **before** routing or provider I/O.


| Aspect | Detail |
| ------ | ------ |
| When | First bytes on the wire |
| Meaning | “Your job is admitted; keep this connection open for progress.” |
| Payload | `request_reference`, `trace_id`; optional `degraded_notice` (see §18) |
| D1 at this point | Fresh path: `ai_request.state = Accepted`, `routing_tier` already set on INSERT |

See [§11.1 `accepted`](#111-accepted) for field-level detail.

## 7. Phase B — Dispatch (fresh vs idempotent)

After `accepted`, the gateway looks up the guard outcome keyed by `request_reference` (one-shot handoff from pre-accept).


| Branch | Trigger | Behavior |
| ------ | ------- | -------- |
| Missing handoff | No stored guard outcome | SSE `failed` `internal_error` |
| Idempotent | Quota DO returned `idempotent` at guard stage 8 | Replay terminal from DO prior state — no routing, no provider, no new D1/R2 writes |
| Fresh | Normal admission | Load routing policy, invoke providers, relay SSE until terminal |

## 8. Phase C — Routing (D1 + R2)

After `accepted` on the fresh path, the platform resolves the manifest’s `Routing.routingPolicyRef`:

1. **D1** `routing_policy` — active policy index (id, version, R2 pointer).
2. **R2** `control/routing-policy/{policy_id}/{version}.json` — full policy document.

The first matching rule yields a **routing decision**:


| Input | Visit summary source | Purpose |
| ----- | -------------------- | ------- |
| `capabilityId` | manifest `Identity.capabilityId` | Rule `match.capability_ids` |
| `installationId` | AAT `iss` → Principal | Installation overrides / exclusions |
| `routingTier` | Should be D1 `ai_request.routing_tier` | Rule `match.tiers` (`standard` vs `degraded`) — see §18 |
| `structured_output_required` | `Output.mode !== "prose"` | Target feature gate |
| `min_context_window` | `Routing.requiredProviderFeatures.contextWindow` | Drop undersized models |
| `languages` | `[requiredProviderFeatures.language]` | Language filter |
| `latency_class` | `Routing.latencyClass` | Latency class filter |
| Cost class floor / ceiling | manifest + entitlement | Effective cost class for target filtering |


**Output — routing decision (conceptual):**


| Field | Meaning |
| ----- | ------- |
| `policy_id`, `policy_version` | Which published policy matched |
| `rule_id` | First matching rule in document order |
| `effective_cost_class` | Minimum of manifest, entitlement cap, installation override |
| `routing_tier` | Tier used for rule matching |
| `chain[]` | Ordered targets: `provider_id`, `model_id`, `max_attempts`, `timeout_ms` |
| `excluded[]` | Dropped targets with `reason_code` |


**Rationale:** routing is **stateless** — each invoke re-evaluates policy against manifest requirements; there is no “remember last failure” routing memory.

Full policy field reference: [Stage 5 — Routing policy](07-stage-5-routing-policy.md).

## 9. Phase D — Provider invocation

The platform walks `chain[]` in order. For each entry, up to `max_attempts` tries against the same `provider_id` / `model_id`.


| Step | Wire / storage effect |
| ---- | --------------------- |
| Per attempt | HTTPS to provider API; `CanonicalRequest` mapped to provider JSON (§13) |
| Partial stream before retry | SSE `regenerating`; client discards provisional `text_delta` |
| Cross-provider fallback | After target exhausted, if prior target streamed text → `regenerating`, then next chain entry |
| Backoff between retries | Exponential + jitter, cap 10s; may honor provider Retry-After |
| Success | Provider usage counters → eventual DO credit and D1 `ai_attempt` |
| Chain exhausted | SSE `failed` `provider_unavailable` |
| Client abort | SSE `cancelled`; partial DO credit if tokens accrued (§17) |


Each attempt becomes one D1 `ai_attempt` row at settlement ([Stage 11](13-stage-11-terminal-settlement.md)).

## 10. Phase E — Stream relay and output guards

Visit summary uses **prose relay** (structured JSON capabilities use a separate relay path not covered here).


| Responsibility | Detail |
| -------------- | ------ |
| Relay | Provider text fragments → SSE `text_delta` with monotonic `sequence` |
| Heartbeat | Every **15s** without content → SSE `heartbeat` |
| Incremental guards | Max assembled length, stop sequences, system-prompt leak check on cumulative text |
| Completion guards | Reject empty output; reject provider truncation (`finish_reason = length`) |
| Terminal | Exactly one of `completed`, `failed`, `cancelled` per connection |
| D1 on terminal | `ai_request.state` → `Completed`, `Failed`, or `Cancelled` |
| Quota DO on cancel | `credit` with `partial: true` when usage accrued before abort |


**Prose guard thresholds (visit summary production):** max assembled length 128_000 characters; stop sequence `<|end|>`; system-prompt leak sentinel string.

**Provider failure before relay completes:** SSE `failed` with taxonomy code; D1 `Failed` with `terminal_error_code`; broker cancel path must not double-settle quota.

## 11. SSE events — every field

Terminal kinds: `completed`, `failed`, `cancelled`, `context_requested` — after one terminal, no further events are sent.

### 11.1 `accepted`

```json
{
  "request_reference": "ABCD-EFGH",
  "trace_id": "<ulid-or-client-supplied>"
}
```

When degraded routing applies (spec):

```json
{
  "request_reference": "ABCD-EFGH",
  "trace_id": "<ulid>",
  "degraded_notice": true
}
```


| Field | Meaning |
| ----- | ------- |
| `request_reference` | Client-facing ticket for this connection; repeated on terminal `failed` |
| `trace_id` | Correlation id for all subsequent SSE events and support lookup |
| `degraded_notice` | Optional hint that D1 `routing_tier = degraded` — see §18 for whether it appears on the wire today |


### 11.2 `heartbeat`

```json
{ "trace_id": "<ulid>" }
```


| Aspect | Detail |
| ------ | ------ |
| Interval | 15 seconds of silence (no `text_delta` or `regenerating`) |
| Purpose | Keep proxies and clients from closing idle connections during model latency |
| Reset | Any content event resets the timer |


### 11.3 `regenerating`

```json
{ "trace_id": "<ulid>" }
```


| Aspect | Detail |
| ------ | ------ |
| When | Same-provider retry after partial stream, or fallback to next chain entry after partial stream |
| Client action | **Discard** all provisional `text_delta` since the last `regenerating` (or since `accepted`) |
| Rationale | A retry may produce different clinical text; stale partial output must not be shown as draft |


### 11.4 `text_delta`

```json
{
  "text": "<chunk>",
  "sequence": 0,
  "provisional": true,
  "trace_id": "<ulid>"
}
```


| Field | Meaning |
| ----- | ------- |
| `text` | Incremental UTF-8 fragment from the provider |
| `sequence` | Monotonic within one generation leg — resets after `regenerating` |
| `provisional` | Always `true` — only `completed.result.finalContent` is authoritative |
| `trace_id` | Same as `accepted` |


### 11.5 `completed`

```json
{
  "result": {
    "finalContent": {
      "text": "<full assembled prose>",
      "authoritative": true
    }
  },
  "trace_id": "<ulid>"
}
```


| Field | Meaning |
| ----- | ------- |
| `result.finalContent.text` | Full prose after assembly and output guards |
| `result.finalContent.authoritative` | Always `true` — replaces all provisional deltas |
| Emitted when | Output guards pass and provider did not hit output length limit |


### 11.6 `failed`

```json
{
  "code": "<taxonomy code>",
  "request_reference": "ABCD-EFGH",
  "trace_id": "<ulid>",
  "retry_safe": true
}
```


| Field | Meaning |
| ----- | ------- |
| `code` | Platform taxonomy code (`provider_unavailable`, `validation_failed`, `internal_error`, …) |
| `request_reference` | Same ticket as `accepted` |
| `trace_id` | Correlation id |
| `retry_safe` | Whether retry with a **new** `x-idempotency-key` is reasonable (from taxonomy retryability) |


Same JSON shape as pre-accept HTTP error bodies ([Stage 19 — Taxonomy](19-taxonomy-codes-and-http-mapping.md)).

### 11.7 `cancelled`

```json
{ "trace_id": "<ulid>" }
```


| Aspect | Detail |
| ------ | ------ |
| When | Client closes the SSE connection or aborts the POST |
| Quota DO | May receive `credit` with `partial: true` if tokens accrued before abort |
| D1 | `ai_request.state = Cancelled` |


### 11.8 `context_requested`

Conversational capabilities only — not emitted for visit summary (`single_shot`).

```json
{
  "context_request": { "...": "platform context-request schema" },
  "trace_id": "<ulid>"
}
```


| Aspect | Detail |
| ------ | ------ |
| Meaning | Model requests additional context keys mid-thread |
| Client response | New POST leg with updated `context` / `transcript` (conversational flow) |


## 12. CanonicalRequest — every field

Built at guard stage 10, held in memory for invoke only — **never sent to the clinic client**. It is the platform-internal contract mapped to DeepSeek/Gemini HTTPS bodies (§13).

**Composition order in `parts[]` (visit summary):**

1. System instruction (manifest prompt artifact)
2. Business rule fragments
3. Output format instruction (from `Output.mode` / schema ref)
4. *(Conversational only)* prior transcript turns
5. Rendered context (`data` role) from `filteredContext`
6. Staff `user_intent` (`user` role)

### 12.1 Top-level fields


| Field | Visit summary source | Meaning |
| ----- | -------------------- | ------- |
| `parts[]` | Composed list (§12.2) | Full prompt as role-tagged segments |
| `formatDirective.mode` | manifest `Output.mode` (`prose`) | Output shape; drives provider JSON mode when not prose |
| `formatDirective.outputSchemaRef` | manifest `Output.outputSchemaRef` | Schema ref for structured capabilities; `null` for visit summary |
| `samplingConstraints.allowedLanguages` | manifest `Input.allowedLanguages` | Declared language allow-list |
| `samplingConstraints.temperature` | Not populated for visit summary today | Optional; forwarded to provider when set |
| `maxOutputTokens` | manifest `Economics.maxOutputTokens` | Completion token cap (visit summary: 1024) |
| `stopConditions` | manifest (none declared) → `[]` | Stop sequences; empty when manifest omits them |
| `toolDeclarations` | `[]` | Tool calling not enabled |
| `stream` | Default `false` for visit summary | Provider HTTPS streaming flag — see §18 |
| `deadline` | Optional ms budget; default unbounded | Shared wall clock across chain entries and retries |
| `correlationIds.request_reference` | Gateway-generated | Links provider logs to client ticket |
| `correlationIds.trace_id` | AAT `jti` | **Not** the SSE / D1 `trace_id` |


### 12.2 `parts[]`


| Field | Values | Meaning |
| ----- | ------ | ------- |
| `role` | `system`, `user`, `assistant`, `data` | Segment type — providers remap roles (§13) |
| `content` | string | UTF-8 text; context JSON neutralized in templates |


| Role | Visit summary content |
| ---- | --------------------- |
| `system` | Instruction, rules, output format |
| `data` | Rendered context keys (`<key name="…">…</key>`) |
| `user` | `user_intent` from POST body |
| `assistant` | Conversational history only |


## 13. Provider wire transformation

The platform maps `CanonicalRequest` → provider HTTPS JSON → `CanonicalResult` (usage, finish reason, provider request id).

### 13.1 DeepSeek (`deepseek-v4-flash`)

**Request mapping:**


| Canonical | DeepSeek wire |
| --------- | ------------- |
| `parts[]` | `messages[]` (roles passed through, including `data`) |
| `maxOutputTokens` | `max_tokens` |
| `stopConditions` | `stop` (omitted when empty) |
| `samplingConstraints.temperature` | `temperature` |
| `stream: true` | `stream` + `stream_options.include_usage` |
| JSON output mode | `response_format.type = json_object` |


**Response mapping:**


| DeepSeek wire | Canonical / platform |
| ------------- | -------------------- |
| `usage.prompt_tokens` | input tokens → DO credit, D1 `ai_attempt.tokens_in` |
| `usage.completion_tokens` | output tokens |
| `usage.prompt_cache_hit_tokens` | cached token count |
| `id` | `provider_request_id` on attempt row |
| message content / stream deltas | SSE `text_delta` → assembled prose |
| `finish_reason = length` | No authoritative `completed` — SSE `failed` `validation_failed` |


### 13.2 Gemini (`gemini-3.5-flash`)

**Role mapping:**


| Canonical role | Gemini wire |
| -------------- | ----------- |
| `system` | `systemInstruction` (merged) |
| `assistant` | `contents[]` role `model` |
| `user`, `data` | `contents[]` role `user` |


**Request mapping:**


| Canonical | Gemini wire |
| --------- | ----------- |
| `maxOutputTokens` | `generationConfig.maxOutputTokens` |
| `stopConditions` | `generationConfig.stopSequences` |
| JSON output mode | `responseMimeType: application/json` (+ schema when set) |
| `stream: true` | `:streamGenerateContent?alt=sse` |


**Response mapping:**


| Gemini wire | Canonical / platform |
| ----------- | -------------------- |
| `usageMetadata.promptTokenCount` | input tokens |
| `usageMetadata.candidatesTokenCount` | output tokens |
| `responseId` | `provider_request_id` |


## 14. Invocation retry and fallback logic


| Outcome class | Taxonomy examples | Next action |
| ------------- | ----------------- | ----------- |
| Retryable | `timeout`, `rate_limited`, `internal_error` | Backoff; retry same chain entry up to `max_attempts` |
| Terminal | `provider_rejected` | SSE `failed` with code (no further attempts on that error class) |
| Truncation | Output length limit | Attempt recorded; no authoritative `completed` |
| Chain exhausted | All targets failed | SSE `failed` `provider_unavailable` |
| Caller cancelled | — | SSE `cancelled` |


**D1 `ai_attempt.selection_reason`:** `primary`, `fallback_after_retryable_error`, `fallback_after_timeout`.

**Backoff:** base 100ms × 2^retryIndex, plus up to 50% jitter, maximum 10_000ms between attempts on the same target.

## 15. Idempotent replay path (no provider call)

When guard stage 8 admission returns `idempotent` (same installation + `x-idempotency-key` while DO retains prior state):

```
SSE accepted
  → read Quota DO idempotency prior state
  → emit terminal from prior state (no routing, no provider, no new D1 INSERT, no R2 write)
```


| DO prior state | Terminal emitted |
| -------------- | ---------------- |
| `completed`, `admitted`, `in_progress` | SSE `completed` with placeholder text `"Prior request completed."` |
| `failed` | SSE `failed` `internal_error` |
| `cancelled` | SSE `cancelled` |
| other | SSE `failed` `internal_error` |


**Rationale:** protects quota and journal integrity on client retry without a second provider charge. Full result replay from R2 is not performed today (see §18).

## 16. Failure paths after `accepted`


| Failure | SSE `code` | D1 `ai_request` |
| ------- | ---------- | --------------- |
| Missing guard handoff | `internal_error` | unchanged or Failed depending on timing |
| Empty routing chain | `provider_unavailable` | `Failed` |
| All providers exhausted | `provider_unavailable` | `Failed` |
| Output guard / truncation | `validation_failed` | `Failed` |
| Unexpected platform error | `internal_error` | `Failed` |
| Client disconnect | — (terminal `cancelled`) | `Cancelled` |


Guard failures never reach this stage — they return HTTP JSON without SSE ([Stage 8](10-stage-8-request-ingress.md)).

## 17. Settlement handoff (Stage 11)

On SSE terminal `completed` after successful provider invoke:


| Action | Storage |
| ------ | ------- |
| Quota DO `credit` | `tokensUsed`, `costUsed`, `requestsUsed`; idempotency → `completed` |
| D1 `ai_request` UPDATE | `state = Completed`, `completed_at` |
| D1 `ai_attempt` INSERT | One row per provider attempt |
| D1 `usage_event` INSERT | Billing ledger row |
| R2 PUT | `request/{request_id}/envelope` diagnostic package |
| D1 `ai_request.payload_pointer` | Set to R2 envelope key |


See [Stage 11 — Terminal settlement](13-stage-11-terminal-settlement.md) for every RPC field, column, and R2 envelope key.

**Partial cancel:** Quota DO `credit` with `partial: true`; D1 `Cancelled`; no full R2 envelope on happy-path settlement.

## 18. Spec vs platform behavior today

These items are part of the **intended** data journey but behave differently on the live path today. They are listed here so readers do not confuse specification with observed wire/storage behavior.


| Topic | Spec / schema says | Platform behavior today |
| ----- | ------------------ | ----------------------- |
| **`degraded_notice` on `accepted`** | Present when D1 `ai_request.routing_tier = degraded` (soft threshold or grace admission) | `routing_tier` is written correctly on journal INSERT, but **`degraded_notice` is not emitted** on the SSE `accepted` frame |
| **Invoke-time routing tier** | Routing rule `match.tiers` should use the same tier as D1 `ai_request.routing_tier` | Invoke preload passes **`routingTier = standard` always**, so degraded policy rules may not match even when the journal row says `degraded` |
| **Idempotent replay result** | Client receives the prior terminal outcome | Terminal `completed` uses **placeholder prose** `"Prior request completed."` — not the original result text from R2 |
| **Provider HTTP streaming** | `CanonicalRequest.stream` may request token streaming | Visit summary compose leaves **`stream = false`** — providers use non-streaming HTTPS; the client often receives **one** `text_delta` burst rather than many incremental frames |
| **Kill switches → routing** | Guard stage 5 may exclude providers | Invoke routing may not receive the full kill-switch exclusion list — policy document exclusions still apply |
| **Entitlement cost ceiling at invoke** | Effective cost class from D1 entitlement | Invoke path may use a **fixed premium ceiling** rather than reading the installation entitlement row |

When any row above is fixed, update this table and the affected sections (§6, §8, §11.1, §12.1, §15).

---

*Cross-references: [Stage 8 — Request ingress](10-stage-8-request-ingress.md), [Stage 9 — The guard](11-stage-9-the-guard.md), [Stage 5 — Routing policy](07-stage-5-routing-policy.md), [Stage 11 — Terminal settlement](13-stage-11-terminal-settlement.md).*
