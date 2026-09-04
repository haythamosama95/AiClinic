# AI Platform Data Journey — Stage 10 — Accept, route, invoke, stream

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [Boundary with Stage 9 (the guard)](#3-boundary-with-stage-9-the-guard)
4. [HTTP response shape](#4-http-response-shape)
  - [4.1 SSE response contract (consolidated)](#41-sse-response-contract-consolidated)
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
19. [Behavioral verification](#19-behavioral-verification)
   - [19.1 Setup](#191-setup)
   - [19.2 Coverage](#192-coverage)
   - [19.3 Ordered probes](#193-ordered-probes)
     - [19.3.1 Prerequisites and a reusable invoke](#1931-prerequisites-and-a-reusable-invoke)
     - [19.3.2 Missing routing policy after accepted](#1932-missing-routing-policy-after-accepted)
     - [19.3.3 Guard boundary without SSE](#1933-guard-boundary-without-sse)
     - [19.3.4 Publish and promote a fake-provider policy](#1934-publish-and-promote-a-fake-provider-policy)
     - [19.3.5 Happy fresh path end to end](#1935-happy-fresh-path-end-to-end)
     - [19.3.6 Canonical request, routing decision, and settlement](#1936-canonical-request-routing-decision-and-settlement)
     - [19.3.7 Two trace identifiers and ignored injection keys](#1937-two-trace-identifiers-and-ignored-injection-keys)
     - [19.3.8 Idempotent replay of completed](#1938-idempotent-replay-of-completed)
     - [19.3.9 Default provider chain without API keys](#1939-default-provider-chain-without-api-keys)
     - [19.3.10 Retry, fallback, and chain exhaustion](#19310-retry-fallback-and-chain-exhaustion)
     - [19.3.11 Empty chain, fail-closed filters, and kill-switch failover](#19311-empty-chain-fail-closed-filters-and-kill-switch-failover)
     - [19.3.12 Client disconnect and cancelled replay](#19312-client-disconnect-and-cancelled-replay)
     - [19.3.13 Idempotent replay of failed](#19313-idempotent-replay-of-failed)
     - [19.3.14 Degraded notice and canary preference](#19314-degraded-notice-and-canary-preference)
     - [19.3.15 What this stage does not do](#19315-what-this-stage-does-not-do)

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
| `routing_decision` on journal row | `NULL` until Stage 10 Phase C | Unchanged from prior job |


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

### 4.1 SSE response contract (consolidated)

Wire encoding: `event: <type>` then `data: <json>` (`encodeSseEvent` in `src/adapter.ts`). Terminal kinds are defined in `TERMINAL_EVENT_KINDS` — after one terminal event, no further frames are sent on that connection.


| `event` | Terminal? | `data` shape (JSON keys) | Notes |
| ------- | --------- | ------------------------ | ----- |
| `accepted` | no | `request_reference` (Crockford `XXXX-XXXX`), `trace_id`, optional `degraded_notice` (boolean `true`) | First frame; emitted before routing/provider I/O ([§6](#6-phase-a-sse-accepted)) |
| `heartbeat` | no | `trace_id` | Every **15 s** without `text_delta` / `regenerating` ([§11.2](#112-heartbeat)) |
| `regenerating` | no | `trace_id` | Client discards provisional `text_delta` since last `regenerating` or `accepted` ([§11.3](#113-regenerating)) |
| `text_delta` | no | `text` (string), `sequence` (number, monotonic per leg), `provisional` (always `true`) | **Platform today:** `data` often omits `trace_id` — wrapper carries it but `encodeSseEvent` serializes only `event.data` ([§19.3.5](#1935-happy-fresh-path-end-to-end)) |
| `completed` | **yes** | `result.finalContent.text` (string), `result.finalContent.authoritative` (always `true`), `trace_id` | Authoritative prose; replaces all provisional deltas ([§11.5](#115-completed)) |
| `failed` | **yes** | `code` (taxonomy string), `request_reference`, `trace_id`, `retry_safe` (boolean) | Same JSON shape as pre-accept HTTP error bodies ([§11.6](#116-failed)) |
| `cancelled` | **yes** | `trace_id` only | Client disconnect / abort ([§11.7](#117-cancelled)) |
| `context_requested` | **yes** | `context_request` (array of `{ key, arguments }` per `platform.context_request@v1`), `trace_id` | **Conversational capabilities only** — `pushTerminalEvent` throws for `single_shot` ([§11.8](#118-context_requested)) |


**`context_request` entry shape** (`src/context/context-request.ts`): each element is `{ "key": "<context key>", "arguments": { … } }` — plain object arguments; validated by `validateContextRequest` before emit.

**Verification:** [§19.3.5](#1935-happy-fresh-path-end-to-end) exercises `accepted` → `text_delta` → `completed` field-by-field on the fake provider path. [§19.3.12](#19312-client-disconnect-and-cancelled-replay) replays `cancelled`. [§19.3.8](#1938-idempotent-replay-of-completed) and [§19.3.13](#19313-idempotent-replay-of-failed) cover terminal replay shapes. `context_requested` is unprobeable on visit summary — see [§19.3.15](#19315-what-this-stage-does-not-do).

## 5. Runtime flow — fresh path

```
POST /v1/requests (guard 1–10 complete)     ← Stages 8–9
  ├─ SSE accepted emitted                     ← Phase A
  └─ background invoke pipeline               ← Phases B–E
       ├─ D1 routing_policy index + R2 policy document
       ├─ routing decision → provider chain; D1 UPDATE routing_decision   ← Phase C
       ├─ provider invoke (sequential chain; SSE relay concurrent) ← Phase D
       ├─ SSE text_delta / regenerating / heartbeat ← Phase E
       ├─ terminal SSE (completed | failed | cancelled)
       └─ every terminal credits the Quota DO; completed also writes D1/R2 (Stage 11)
```

**Concurrency rationale:** provider invocation and SSE relay run in parallel so the clinic client sees `text_delta` while the model is still generating, instead of waiting for the full provider response.

**Client disconnect:** closing the POST or SSE connection aborts the in-flight provider request and drives terminal `cancelled` (unless a terminal event was already sent).

## 6. Phase A — SSE `accepted`

Emitted as the **first SSE frame**, immediately when the stream opens, **after** the guard succeeds and **before** routing or provider I/O.


| Aspect | Detail |
| ------ | ------ |
| When | First bytes on the wire |
| Meaning | “Your job is admitted; keep this connection open for progress.” |
| Payload | `request_reference`, `trace_id`; optional `degraded_notice: true` when `routing_tier` is `degraded` |
| D1 at this point | Fresh path: `ai_request.state = Accepted`, `routing_tier` already set on INSERT; `routing_decision` still `NULL` |

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

1. **D1** `routing_policy` — active policy index (id, version, R2 pointer). Config-cache prefers a `status='canary'` row whose `canary_installation_ids` contains this installation, else `status='active'`. Both reads use `ORDER BY active_from DESC, rowid DESC` so same-second timestamps pick the later-inserted row (TEXT `version` is not sorted lexically).
2. **R2** `control/routing-policy/{policy_id}/{version}.json` — full policy document.

The first matching rule yields a **routing decision**:


| Input | Visit summary source | Purpose |
| ----- | -------------------- | ------- |
| `capabilityId` | manifest `Identity.capabilityId` | Rule `match.capability_ids` |
| `installationId` | AAT `iss` → Principal | Installation overrides / exclusions |
| `routingTier` | D1 `ai_request.routing_tier` via `routingTierFromAdmission` (soft threshold or grace) | Rule `match.tiers` (`standard` vs `degraded`) |
| `structured_output_required` | `Output.mode !== "prose"` | Target feature gate |
| `min_context_window` | `Routing.requiredProviderFeatures.contextWindow` | Drop undersized models (`context_window_too_small`); missing/non-numeric advertisement → `feature_unsupported` |
| `languages` | `[requiredProviderFeatures.language]` | Language filter (`language_unsupported`); missing/non-array advertisement → `feature_unsupported` (does not throw) |
| `latency_class` | `Routing.latencyClass` | Latency class filter (exact `!==` → `feature_unsupported`) |
| Cost class floor / ceiling | manifest + entitlement | Effective cost class for target filtering; known class above ceiling → `cost_class_excluded`; missing/unknown → `feature_unsupported` |


**Output — routing decision (conceptual):**


| Field | Meaning |
| ----- | ------- |
| `policy_id`, `policy_version` | Which published policy matched |
| `rule_id` | First matching rule in document order |
| `effective_cost_class` | Minimum of manifest, entitlement cap, installation override |
| `cost_class_source` | Which of those three inputs bound the class (`manifest` / `entitlement_cap` / `installation_override`) |
| `routing_tier` | Tier used for rule matching |
| `chain[]` | Ordered targets: `provider_id`, `model_id`, `max_attempts`, `timeout_ms` |
| `excluded[]` | Dropped targets with `reason_code` (kill switch, feature, installation override, cost class) |


Immediately after `selectCandidateChain`, Stage 10 **persists that object** as JSON on the existing `ai_request` row (`persistRoutingDecision` — one `UPDATE … SET routing_decision = ?`). No new tables. The write happens **before** provider invoke so the ledger already answers "why model X?" even if the chain later fails. `max_parallel_attempts` is not a decision field and is not persisted; invocation walks `chain[]` sequentially.


Target feature filters are **fail closed**. A missing or unknown `min_context_window`, `cost_class`, or `languages` advertisement excludes that target with `reason_code: feature_unsupported`. `languages` is `Array.isArray`-guarded so a malformed document excludes rather than throwing `TypeError` (which the worker would map to `internal_error`). Declared-but-insufficient values keep `context_window_too_small`, `language_unsupported`, and `cost_class_excluded`. Latency mismatch remains exact equality → `feature_unsupported`. If every target is excluded, the stream ends `failed` / `provider_unavailable`.

Guard stage 5 collects active `provider:<id>` kill switches (from the same routing-policy targets it already loaded) and returns them as `killedProviderIds` on the resolve / `GuardFreshSuccess` result. Invoke `selectCandidateChain` receives that set on `RouterContext` and also `consult`s `kill_switches` on the **same isolate-scoped ConfigCache** the guard just warmed — `mergeKilledProviderIds` unions both sources. Killed providers are dropped with `reason_code: kill_switch`; remaining targets stay in order, so traffic fails over (DeepSeek killed → Gemini first). Killing one provider does not 503 the capability.

**Rationale:** routing is **stateless** — each invoke re-evaluates policy against manifest requirements; there is no “remember last failure” routing memory.

Full policy field reference: [Stage 5 — Routing policy](07-stage-5-routing-policy.md).

## 9. Phase D — Provider invocation

The platform walks `chain[]` **sequentially** (one target at a time). For each entry, up to `max_attempts` tries against the same `provider_id` / `model_id`. There is no parallel racing of targets — a policy document may still carry `max_parallel_attempts` as a schema-retained key, but invocation never reads it.


| Step | Wire / storage effect |
| ---- | --------------------- |
| Per attempt | HTTPS to provider API with `stream: true` (DeepSeek) or `:streamGenerateContent?alt=sse` (Gemini). Production `createFetchTransport` passes `Response.body` through as a `ReadableStream` — adapters parse SSE incrementally (a reader over the body, one `data:` event at a time) and emit `text_delta` on the invocation sink as each event arrives, concurrently with the rest of the provider call. |
| Partial stream before retry | SSE `regenerating`; client discards provisional `text_delta` |
| Cross-provider fallback | After target exhausted, if prior target streamed text → `regenerating`, then next chain entry |
| Backoff between retries | Production wires `wallClockSleeper` (`setTimeout`). Delay is `max(jittered exponential backoff, provider retryAfterMs)`, cap 10s; `sleepWithinDeadline` truncates against the remaining request deadline. Tests inject no-op/recording sleepers. |
| Success | Provider usage counters → eventual DO credit and D1 `ai_attempt` |
| Truncation (`finish_reason = length`, or stream without a finish reason) | Attempt journaled as outcome `truncation` — **not** `ok: true` / authoritative `completed`. Because `validation_failed` is retryable, the loop may retry or fall back. If the chain ends on truncation, SSE `failed` `validation_failed` (not `provider_unavailable`). Failed-terminal credit is the existing path (Stage 11 §9). |
| Chain exhausted | SSE `failed` `provider_unavailable` |
| Client abort | SSE `cancelled`; Quota DO `credit` with `partial: true` even at zero usage (§17) |


Each attempt becomes one D1 `ai_attempt` row at settlement ([Stage 11](13-stage-11-terminal-settlement.md)).

## 10. Phase E — Stream relay and output guards

Visit summary uses **prose relay** (structured JSON capabilities use a separate relay path not covered here).


| Responsibility | Detail |
| -------------- | ------ |
| Relay | Provider text fragments → SSE `text_delta` with monotonic `sequence`. Deltas are pushed on the invocation-event channel **as SSE events arrive** from the provider (`onStreamChunk` → `InvocationSink.emitStreamText`); `relayTextDeltas` does not wait for `port.invoke` to resolve. Adapters that do not live-emit still fall back to post-invoke relay of the returned chunk list. |
| Heartbeat | Every **15s** without content → SSE `heartbeat` |
| Incremental guards | Max assembled length, stop sequences, system-prompt leak, refusal prefixes (start-of-text), injection-echo needle on cumulative text |
| Completion guards | Reject empty output; reject provider truncation (`finish_reason = length`) via `chunkSource.wasTruncated()`; same safety markers as incremental |
| Terminal | Exactly one of `completed`, `failed`, `cancelled` per connection |
| D1 on terminal | `ai_request.state` → `Completed`, `Failed`, or `Cancelled` |
| Quota DO on cancel | `credit` with `partial: true` (zero usage allowed) so `inFlight` is released |


**Prose guard thresholds (visit summary production):** max assembled length 128_000 characters; stop sequence `<|end|>`; system-prompt leak needles derived per request from distinctive 48-character slices of the composed system instruction — opening, interior, and ending (not a test placeholder, and not only the prompt's start); refusal prefixes `I'm sorry, I can't help with that` and `I'm sorry, I can't assist` matched at the start of assembled text (mid-sentence quotes do not fire); injection-echo needle `Ignore previous instructions` (substring). Matches of leak, refusal, or injection-echo take the existing guard-failure path: SSE `failed` / `validation_failed`. These markers live on the prose broker (`src/stream/prose-guards.ts` wired from `src/worker.ts`); they are not structured-broker-only.

The production chunk-source adapter `createChunkSourceFromInvocationEvents` implements `wasTruncated()`: it tracks `{ kind: "truncation" }` events relayed from `InvocationSink.emitTruncation()` when the adapter returns `kind: "truncation"`. A subsequent `regenerating` event clears the flag (discarded truncated prose). After the stream ends, the broker (and the structured safety phase, which reads the same sensor) fails with `validation_failed` rather than emitting authoritative `completed`.

**Provider failure before relay completes:** SSE `failed` with taxonomy code; D1 `Failed` with `terminal_error_code`; Quota DO `credit` with taxonomy-derived `partial` and idempotency `failed`; broker cancel path must not double-settle quota.

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
| `degraded_notice` | Present when D1 `ai_request.routing_tier = degraded` (soft threshold or grace). Per-request from preAccept — not a static adapter option. |


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
| Quota DO | Always receives `credit` with `partial: true` (accrued usage or zeros) |
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
6. Staff `user_intent` (`user` role), after the same `neutralizeText` escaping used for context blocks (`</` → `\u003c/`)

### 12.1 Top-level fields


| Field | Visit summary source | Meaning |
| ----- | -------------------- | ------- |
| `parts[]` | Composed list (§12.2) | Full prompt as role-tagged segments |
| `formatDirective.mode` | manifest `Output.mode` (`prose`) | Output shape; drives provider JSON mode when not prose |
| `formatDirective.outputSchemaRef` | manifest `Output.outputSchemaRef` | Schema ref for structured capabilities; `null` for visit summary |
| `samplingConstraints.allowedLanguages` | manifest `Input.allowedLanguages` | Declared language allow-list |
| `samplingConstraints.temperature` | Not populated for visit summary today | Optional; forwarded to provider when set |
| `maxOutputTokens` | manifest `Economics.maxOutputTokens` | Completion token cap (visit summary: 1024) |
| `stopConditions` | A4 §5.1 declares no stop-sequences field → always `[]` | Stop sequences; **always empty under A4** (the composer forwards absence via `stopConditionsFromManifest`, never an invented threshold). They do not flow from the manifest even if a future field were imagined — A4 has none. |
| `toolDeclarations` | `[]` | Tool calling not enabled |
| `stream` | Guard stage 10 passes `streamFlag: true` for live SSE capabilities | Provider HTTPS streaming flag — DeepSeek `stream` + `stream_options.include_usage`; Gemini `:streamGenerateContent?alt=sse` |
| `deadline` | Guard stage 10 forwards `GuardInput.deadline` when set; otherwise `null` (unbounded) | Shared wall clock across chain entries and retries |
| `correlationIds.request_reference` | Gateway-generated | Links provider logs to client ticket |
| `correlationIds.trace_id` | AAT `jti` | **Not** the SSE / D1 `trace_id` |


### 12.2 `parts[]`


| Field | Values | Meaning |
| ----- | ------ | ------- |
| `role` | `system`, `user`, `assistant`, `data` | Segment type — remapped on the wire (§13). DeepSeek: `data` → `user`; `system` / `user` / `assistant` passthrough. Gemini: §13.2 |
| `content` | string | UTF-8 text; `</` neutralized to `\u003c/` in context JSON, transcript turns, and the final `userIntent` part |


| Role | Visit summary content |
| ---- | --------------------- |
| `system` | Instruction, rules, output format |
| `data` | Rendered context keys (`<key name="…">…</key>`); JSON values neutralized |
| `user` | `user_intent` from POST body after `neutralizeText` (`</` → `\u003c/`) |
| `assistant` | Conversational history only (`context_requested` payloads already allowlisted at stage 6) |


## 13. Provider wire transformation

The platform maps `CanonicalRequest` → provider HTTPS JSON → `CanonicalResult` (usage, finish reason, provider request id).

### 13.1 DeepSeek (`deepseek-v4-flash`)

**Role mapping:**


| Canonical role | DeepSeek wire |
| -------------- | ------------- |
| `system` | `messages[]` role `system` |
| `user` | `messages[]` role `user` |
| `assistant` | `messages[]` role `assistant` |
| `data` | `messages[]` role `user` |


DeepSeek's OpenAI-compatible chat-completions API accepts only `system` / `user` / `assistant` / `tool`. Canonical `data` is translated in the adapter; it is never sent on the wire. `system` is **not** folded into `user`.

**Request mapping:**


| Canonical | DeepSeek wire |
| --------- | ------------- |
| `parts[]` | `messages[]` (roles remapped per the table above) |
| `maxOutputTokens` | `max_tokens` |
| `stopConditions` | `stop` — omitted when empty, which is **always** under A4 |
| `samplingConstraints.temperature` | `temperature` |
| `stream: true` | `stream` + `stream_options.include_usage` (always set for visit summary; compose passes `streamFlag: true`) |
| JSON output mode | `response_format.type = json_object` |


**Response mapping:**


| DeepSeek wire | Canonical / platform |
| ------------- | -------------------- |
| `usage.prompt_tokens` | input tokens → DO credit, D1 `ai_attempt.tokens_in`; post-response `priceUsage` input side |
| `usage.completion_tokens` | output tokens → `ai_attempt.tokens_out`; post-response `priceUsage` output side |
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
| `stopConditions` | `generationConfig.stopSequences` — omitted when empty, which is **always** under A4 |
| JSON output mode | `responseMimeType: application/json` (+ schema when set) |
| `stream: true` | `:streamGenerateContent?alt=sse` (always set for visit summary; compose passes `streamFlag: true`) |


**Response mapping:**


| Gemini wire | Canonical / platform |
| ----------- | -------------------- |
| `usageMetadata.promptTokenCount` | input tokens → post-response `priceUsage` input side |
| `usageMetadata.candidatesTokenCount` | output tokens → post-response `priceUsage` output side |
| `responseId` | `provider_request_id` |


## 14. Invocation retry and fallback logic


| Outcome class | Taxonomy examples | Next action |
| ------------- | ----------------- | ----------- |
| Retryable | `timeout`, `rate_limited`, `internal_error` | Backoff; retry same chain entry up to `max_attempts` |
| Terminal | `provider_rejected` | SSE `failed` with code (no further attempts on that error class) |
| Truncation | Output length limit | Attempt recorded as `truncation`; retry/fallback allowed; chain-end terminal is `validation_failed` (never authoritative `completed`) |
| Chain exhausted | All targets failed | SSE `failed` `provider_unavailable` |
| Caller cancelled | — | SSE `cancelled` |


**D1 `ai_attempt.selection_reason`:** `primary`, `fallback_after_retryable_error`, `fallback_after_timeout`.

**D1 `ai_attempt.cost`:** priced from that attempt's provider-reported tokens via the shared helper (`src/pricing`); cancel without reported usage uses `estimateUsageFromStreamedChars` (chars as output tokens through the same rates). See [Stage 11](13-stage-11-terminal-settlement.md).

**Backoff:** base 100ms × 2^retryIndex, plus up to 50% jitter, maximum 10_000ms between attempts on the same target. The delay actually slept is `max(that jittered value, provider retryAfterMs)` when the adapter parsed a Retry-After hint. Production invokes `wallClockSleeper` (`ms => new Promise((r) => setTimeout(r, ms))`) through `sleepWithinDeadline`, which shortens the sleep to the remaining request deadline (and skips it if the deadline has already elapsed). Invocation unit tests inject no-op or recording sleepers so CI does not wait on wall-clock. Retry-After is honored in wall-clock in production, not only computed.

## 15. Idempotent replay path (no provider call)

When guard stage 8 admission returns `idempotent` (same installation + `x-idempotency-key` while DO retains prior state):

```
SSE accepted
  → read Quota DO idempotency prior state
  → emit terminal from prior state (no routing, no provider, no new D1 INSERT, no R2 write)
```


| DO prior state | Terminal emitted |
| -------------- | ---------------- |
| `completed`, `admitted` (still in-flight, not yet swept) | SSE `completed` with placeholder text `"Prior request completed."` |
| `failed` | SSE `failed` `internal_error` — includes abandoned admissions swept after the 2h horizon (not the completed placeholder) |
| `cancelled` | SSE `cancelled` |


Quota DO idempotency states are `admitted` \| `completed` \| `failed` \| `cancelled` only. D1 conversational `awaiting_context` is a journal `ai_request` status, not a DO idempotency state.

**Rationale:** protects quota and journal integrity on client retry without a second provider charge. Full result replay from R2 is not performed today (see §18).

## 16. Failure paths after `accepted`


| Failure | SSE `code` | D1 `ai_request` |
| ------- | ---------- | --------------- |
| Missing guard handoff | `internal_error` | unchanged or Failed depending on timing |
| Empty routing chain | `provider_unavailable` | `Failed` — includes every target excluded (kill switch, installation override, feature mismatch, **or** malformed `min_context_window` / `cost_class` / `languages` fail-closed as `feature_unsupported`) |
| All providers exhausted | `provider_unavailable` | `Failed` |
| Output guard (length, stop, leak, refusal, injection-echo) / truncation | `validation_failed` | `Failed` |
| Unexpected platform error | `internal_error` | `Failed` |
| Client disconnect | — (terminal `cancelled`) | `Cancelled` |


Guard failures never reach this stage — they return HTTP JSON without SSE ([Stage 8](10-stage-8-request-ingress.md)).

## 17. Settlement handoff (Stage 11)

On SSE terminal (`completed`, `failed`, or `cancelled`) after the request was journaled:


| Action | Storage |
| ------ | ------- |
| Quota DO `credit` | `tokensUsed`, `costUsed`, `requestsUsed`; idempotency → `completed` |
| D1 `ai_request` UPDATE | `state = Completed`, `completed_at` |
| D1 `ai_attempt` INSERT | One row per provider attempt |
| D1 `usage_event` INSERT | Billing ledger row |
| R2 PUT | `request/{request_id}/envelope` diagnostic package |
| D1 `ai_request.payload_pointer` | Set to R2 envelope key |


See [Stage 11 — Terminal settlement](13-stage-11-terminal-settlement.md) for every RPC field, column, and R2 envelope key.

**Failed / cancelled:** Quota DO `credit` still runs (zero usage allowed) so `inFlight` is released and idempotency becomes `failed` or `cancelled` rather than staying `admitted`. `partial` follows §5.4 `consumesQuota`. D1 terminal state is `Failed` / `Cancelled`. Settlement then reuses the same Stage 11 writers as completed: `ai_attempt` (collected attempts; Failed always has at least one row), `usage_event` (period from admission `period_start`), and exactly one R2 envelope.

## 18. Spec vs platform behavior today

These items are part of the **intended** data journey but behave differently on the live path today. They are listed here so readers do not confuse specification with observed wire/storage behavior.


| Topic | Spec / schema says | Platform behavior today |
| ----- | ------------------ | ----------------------- |
| **`degraded_notice` on `accepted`** | Present when D1 `ai_request.routing_tier = degraded` (soft threshold or grace admission) | Wired: preAccept returns per-request `degradedNotice` from `degradedNoticeFromAdmission`; the SSE `accepted` frame includes `degraded_notice: true` |
| **Invoke-time routing tier** | Routing rule `match.tiers` should use the same tier as D1 `ai_request.routing_tier` | Wired: `runFreshEventSource` passes `routingTierFromAdmission(...)` into `selectCandidateChain`, so journaled tier and actual routing agree |
| **Idempotent replay result** | Client receives the prior terminal outcome | Terminal `completed` uses **placeholder prose** `"Prior request completed."` — not the original result text from R2 |
| **Kill switches → routing** | Guard stage 5 collects `provider:<id>` kills as `killedProviderIds`; the router excludes those targets (`kill_switch`) and fails over | Wired: `runFreshEventSource` passes `guard.killedProviderIds` into `selectCandidateChain`. Capability-level kills (manifest flag, D1 `global` / `capability:` / `installation:`) still 503 before SSE |
| **Entitlement cost ceiling at invoke** | Effective cost class from D1 entitlement | Invoke path may use a **fixed premium ceiling** rather than reading the installation entitlement row |

When any row above is fixed, update this table and the affected sections (§6, §8, §11.1, §12.1, §15).

Provider HTTPS streaming is live on the visit-summary path: compose sets `stream: true`, adapters parse SSE incrementally from the response body stream, and invocation relays `text_delta` to the broker while the provider call is still open. See §9–§10 and §12.1.

## 19. Behavioral verification

Live probes against a local Worker (`npm run dev` on `http://127.0.0.1:8787`) and a throwaway enrolled clinic. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§19.3](#193-ordered-probes) top to bottom**. If every probe matches, this stage is working.

**Fake provider.** Local happy-path invokes use `provider_id: "fake"` / model `fake-v1`. The Worker constructs `new FakeAdapter(["success"])` for that id (`src/worker.ts` `resolveProviderPort`) so you do **not** need `DEEPSEEK_API_KEY` or `GEMINI_API_KEY`. The checked-in playbook `control/routing-policy/platform-default/1.json` targets DeepSeek then Gemini; without secrets those adapters fail **before** HTTPS with `provider_rejected` and do **not** fall through ([§19.3.9](#1939-default-provider-chain-without-api-keys)). Unknown `provider_id` values get `FakeAdapter(["terminal:provider_unavailable"])` — taxonomy `provider_unavailable` is retryable, which is how [§19.3.10](#19310-retry-fallback-and-chain-exhaustion) forces retry/fallback without API keys.

The isolate `ConfigCache` TTL is 30 s. After every D1/R2 policy, kill-switch, or entitlement write in these probes, **restart** `npm run dev` so the next POST is not served from a stale isolate.

### 19.1 Setup

- Local Worker with D1 migrations applied (`npx wrangler d1 migrations apply ai-platform-development --local --env development`), `OPERATOR_BEARER_TOKEN` set, and `GET /health` returning 200.
- Clinic already through Stages 2–4 and 6: installation enrolled on this Worker, entitlement **active** with grant `clinic.visit_summary@1.0.0`, and a staff AAT from `public.issue_ai_token()`. Decode the JWS:
  - Payload `iss` = this installation
  - `aud` = `ai-platform`
  - `scopes` includes `ai.visit_summary`
  - `role` is `clinician` or `nurse` (visit-summary `Access.allowedStaffRoles`). A clinic `doctor` role is a **Stage 9** `forbidden_capability` — HTTP JSON, no SSE ([§19.3.3](#1933-guard-boundary-without-sse)).
- SQL as `postgres` only for clinic AAT minting. Platform inspection is Wrangler local D1/R2.
- No DeepSeek/Gemini keys required except the negative in [§19.3.9](#1939-default-provider-chain-without-api-keys) (keys must be **absent** there).

Export once:

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export AAT='…'                    # compact JWS from issue_ai_token
export INSTALLATION_ID='…'        # AAT iss
```

Visit-summary body (org/branch must match the AAT):

```bash
export VISIT_BODY='{
  "capability_id": "clinic.visit_summary",
  "user_intent": "Summarize today'\''s visit for the chart.",
  "context": {
    "org": "<AAT org>",
    "branch": "<AAT branch>",
    "visit.chief_complaint@v1": "Patient reports headache for 3 days."
  }
}'
```

Reusable SSE invoke (`curl -N` keeps the stream open). Headers go to `/tmp/sse-headers.txt`, frames to `/tmp/sse-body.txt`:

```bash
invoke_sse() {
  local idem="$1"
  local trace="${2:-verify-$(date +%s%N)}"
  curl -N -sS -D /tmp/sse-headers.txt -o /tmp/sse-body.txt \
    -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $AAT" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $idem" \
    -H "x-capability-version: 1.0.0" \
    -H "x-trace-id: $trace" \
    -d "$VISIT_BODY"
  echo "HTTP $(head -n1 /tmp/sse-headers.txt)"
  cat /tmp/sse-body.txt
}
```

Inspect D1 / R2 after the stream ends. Settlement R2 PUT runs on `waitUntil` — wait ~2 s:

```bash
cd ai-platform
sleep 2
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, request_reference, state, routing_tier, routing_decision, payload_pointer, terminal_error_code, trace_id
   FROM ai_request ORDER BY created_at DESC LIMIT 5"
```

```bash
npx wrangler r2 object get ai-platform-development \
  "request/<request_id>/envelope" --file /tmp/envelope.json --local --env development
```

### 19.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Guard finishes before SSE; guard failures are HTTP JSON, never `accepted` ([§3](#3-boundary-with-stage-9-the-guard), [§16](#16-failure-paths-after-accepted)) | [§19.3.3](#1933-guard-boundary-without-sse) |
| Fresh path has `request_id`, `request_reference`, composed CanonicalRequest, D1 `ai_request` `Accepted` then terminal; `routing_decision` filled in Phase C ([§3](#3-boundary-with-stage-9-the-guard), [§6](#6-phase-a--sse-accepted), [§8](#8-phase-c--routing-d1--r2)) | [§19.3.5](#1935-happy-fresh-path-end-to-end), [§19.3.6](#1936-canonical-request-routing-decision-and-settlement) |
| Idempotent replay skips journal INSERT, compose, routing, and provider ([§3](#3-boundary-with-stage-9-the-guard), [§7](#7-phase-b--dispatch-fresh-vs-idempotent), [§15](#15-idempotent-replay-path-no-provider-call)) | [§19.3.8](#1938-idempotent-replay-of-completed) |
| Two different trace ids: SSE/D1 `x-trace-id` vs CanonicalRequest `correlationIds.trace_id` = AAT `jti` ([§3](#3-boundary-with-stage-9-the-guard), [§12.1](#121-top-level-fields)) | [§19.3.7](#1937-two-trace-identifiers-and-ignored-injection-keys) |
| HTTP 200, `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `Connection: keep-alive`; frames are `event:` + `data:` JSON ([§4](#4-http-response-shape)) | [§19.3.5](#1935-happy-fresh-path-end-to-end) |
| Consolidated SSE contract — event types and `data` shapes ([§4.1](#41-sse-response-contract-consolidated)) | [§19.3.5](#1935-happy-fresh-path-end-to-end), [§19.3.8](#1938-idempotent-replay-of-completed), [§19.3.12](#19312-client-disconnect-and-cancelled-replay), [§19.3.13](#19313-idempotent-replay-of-failed) |
| `accepted` is first frame; fields `request_reference`, `trace_id`; optional `degraded_notice` ([§6](#6-phase-a--sse-accepted), [§11.1](#111-accepted), [§18](#18-spec-vs-platform-behavior-today)) | [§19.3.5](#1935-happy-fresh-path-end-to-end), [§19.3.14](#19314-degraded-notice-and-canary-preference) |
| Fresh path: `text_delta` then exactly one terminal `completed` ([§5](#5-runtime-flow--fresh-path), [§10](#10-phase-e--stream-relay-and-output-guards), [§11.4](#114-text_delta), [§11.5](#115-completed)) | [§19.3.5](#1935-happy-fresh-path-end-to-end) |
| `text_delta` fields `text`, `sequence` (monotonic from 0), `provisional: true`; `completed.result.finalContent.{text,authoritative}` ([§11.4](#114-text_delta), [§11.5](#115-completed)) | [§19.3.5](#1935-happy-fresh-path-end-to-end) |
| Visit summary never emits `context_requested` ([§11.8](#118-context_requested)) | [§19.3.5](#1935-happy-fresh-path-end-to-end), [§19.3.15](#19315-what-this-stage-does-not-do) |
| `heartbeat` only after 15 s silence; fake success is sub-second so the event is absent ([§11.2](#112-heartbeat)) | [§19.3.5](#1935-happy-fresh-path-end-to-end) |
| Body keys `routing_tier` / `degraded` / `degraded_notice` do not set the notice ([§3](#3-boundary-with-stage-9-the-guard) via Stage 8) | [§19.3.7](#1937-two-trace-identifiers-and-ignored-injection-keys) |
| Missing active/canary policy → SSE `failed` `internal_error` after `accepted` ([§7](#7-phase-b--dispatch-fresh-vs-idempotent) unexpected error, Stage 5 §8) | [§19.3.2](#1932-missing-routing-policy-after-accepted) |
| Routing decision JSON persisted on `ai_request` before invoke; `max_parallel_attempts` not a decision field ([§8](#8-phase-c--routing-d1--r2)) | [§19.3.6](#1936-canonical-request-routing-decision-and-settlement) |
| Canary row for this installation beats `active` ([§8](#8-phase-c--routing-d1--r2)) | [§19.3.14](#19314-degraded-notice-and-canary-preference) |
| Fail-closed malformed `languages` / undersized window / latency mismatch / cost class; empty chain → `provider_unavailable` ([§8](#8-phase-c--routing-d1--r2), [§16](#16-failure-paths-after-accepted)) | [§19.3.11](#19311-empty-chain-fail-closed-filters-and-kill-switch-failover) |
| `provider:<id>` kill switch excludes with `kill_switch` and fails over; capability-level kills 503 before SSE ([§8](#8-phase-c--routing-d1--r2), [§18](#18-spec-vs-platform-behavior-today)) | [§19.3.11](#19311-empty-chain-fail-closed-filters-and-kill-switch-failover), [§19.3.3](#1933-guard-boundary-without-sse) |
| Sequential chain; unknown provider retries then falls back; DeepSeek missing key is terminal `provider_rejected` with no Gemini attempt ([§9](#9-phase-d--provider-invocation), [§14](#14-invocation-retry-and-fallback-logic)) | [§19.3.9](#1939-default-provider-chain-without-api-keys), [§19.3.10](#19310-retry-fallback-and-chain-exhaustion) |
| Chain exhausted → `failed` `provider_unavailable`; `retry_safe: true` ([§9](#9-phase-d--provider-invocation), [§11.6](#116-failed), [§16](#16-failure-paths-after-accepted)) | [§19.3.10](#19310-retry-fallback-and-chain-exhaustion) |
| Wall-clock backoff between same-target retries ([§14](#14-invocation-retry-and-fallback-logic)) | [§19.3.10](#19310-retry-fallback-and-chain-exhaustion) |
| `ai_attempt.selection_reason` claimed in [§14](#14-invocation-retry-and-fallback-logic) — **not a D1 column today** (invocation-only; dashboard uses provider-switch heuristic) | [§19.3.10](#19310-retry-fallback-and-chain-exhaustion) |
| CanonicalRequest every field in R2 `envelope.prompt`; never on the SSE ([§12](#12-canonicalrequest--every-field)) | [§19.3.6](#1936-canonical-request-routing-decision-and-settlement) |
| Fake adapter raw body in `envelope.attempts[]`; DeepSeek/Gemini wire map needs API keys | [§19.3.6](#1936-canonical-request-routing-decision-and-settlement), [§19.3.15](#19315-what-this-stage-does-not-do) |
| Idempotent `completed` / `admitted` replay uses placeholder `"Prior request completed."` ([§15](#15-idempotent-replay-path-no-provider-call), [§18](#18-spec-vs-platform-behavior-today)) | [§19.3.8](#1938-idempotent-replay-of-completed) |
| Idempotent `failed` → SSE `failed` `internal_error`; `cancelled` → SSE `cancelled` ([§15](#15-idempotent-replay-path-no-provider-call)) | [§19.3.12](#19312-client-disconnect-and-cancelled-replay), [§19.3.13](#19313-idempotent-replay-of-failed) |
| Client disconnect: D1 `Cancelled`, Quota DO `credit` `partial: true`; original connection may not deliver `event: cancelled` ([§5](#5-runtime-flow--fresh-path), [§11.7](#117-cancelled), [§16](#16-failure-paths-after-accepted)) | [§19.3.12](#19312-client-disconnect-and-cancelled-replay) |
| Completed settlement handoff: DO credit, D1 `Completed`, `ai_attempt`, `usage_event`, R2 envelope, `payload_pointer` ([§17](#17-settlement-handoff-stage-11)) | [§19.3.6](#1936-canonical-request-routing-decision-and-settlement) |
| Failed/cancelled still credit and write the same Stage 11 writers; Failed always has ≥1 `ai_attempt`; Cancelled always has `usage_event` ([§17](#17-settlement-handoff-stage-11)) | [§19.3.10](#19310-retry-fallback-and-chain-exhaustion), [§19.3.12](#19312-client-disconnect-and-cancelled-replay) |
| Invoke-time cost ceiling is hardcoded `premium` / manifest `standard`, not the entitlement row ([§18](#18-spec-vs-platform-behavior-today)) | [§19.3.11](#19311-empty-chain-fail-closed-filters-and-kill-switch-failover) |
| `text_delta` `data` JSON omits `trace_id` today (wrapper field is not serialized); other events include it in `data` ([§4](#4-http-response-shape), [§11.4](#114-text_delta)) | [§19.3.5](#1935-happy-fresh-path-end-to-end) |
| Missing guard handoff; `regenerating`; truncation; live output-guard trips; DeepSeek/Gemini HTTPS bodies | [§19.3.15](#19315-what-this-stage-does-not-do) (unprobeable on this fake path) |
| What this stage does not do (guard matrix, lookup, entitle, conversational `context_requested`) | [§19.3.15](#19315-what-this-stage-does-not-do) |


### 19.3 Ordered probes

#### 19.3.1 Prerequisites and a reusable invoke

**Do:** `curl -s "$GATEWAY/health"`. Confirm `issue_ai_token` yields a JWS and decode header/payload (`alg=EdDSA`, `kid`, `iss`, `jti`, `role` ∈ {`clinician`,`nurse`}, `ai.visit_summary` in `scopes`).

**Expect:** Worker 200. AAT is usable for `POST /v1/requests`. Save `jti` as **JTI0**.

**Do:** as operator, list routing policies:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT policy_id, version, status, canary_installation_ids FROM routing_policy"
```

**Expect:** on a throwaway local D1 this is often empty. If an `active` row already exists, skip [§19.3.2](#1932-missing-routing-policy-after-accepted) (you cannot observe “no policy” without deleting ops data). If entitlement is still `pending`, entitle first ([Stage 4 example payload](06-stage-4-entitlement-and-capability-grants.md#6-example-entitle-payload-visit-summary)) — that is Stage 4, not this stage.

#### 19.3.2 Missing routing policy after accepted

Skip if `routing_policy` already has `status='active'` or a canary for this installation.

**Do:** `invoke_sse "idem-no-policy-1" "trace-no-policy-1"`

**Expect:** HTTP 200, `content-type: text/event-stream`. First frame `event: accepted` with `request_reference` (Crockford `XXXX-XXXX`) and `trace_id: "trace-no-policy-1"`. Then `event: failed` whose `data` is the taxonomy body: `code: "internal_error"`, same `request_reference`, `trace_id`, `retry_safe: true`. No `text_delta`. Guard passed (you saw `accepted`); routing/provider never ran. D1 `ai_request.state` becomes `Failed`, `terminal_error_code = internal_error`. This is [§16](#16-failure-paths-after-accepted) unexpected platform error — not a guard failure.

#### 19.3.3 Guard boundary without SSE

Do **not** re-run the Stage 9 matrix. Only the boundary this document asserts.

**Do:** `POST /v1/requests` with a clearly bad Bearer (`Authorization: Bearer not-a-jws`) and otherwise valid headers/body.

**Expect:** HTTP JSON `unauthenticated` (typically 401). **No** `Content-Type: text/event-stream`, **no** `event: accepted`. Failures before the guard completes never open this stage.

**Do:** if you have a second AAT whose `role` is `doctor` (not in `allowedStaffRoles`), POST the visit-summary body with that token.

**Expect:** HTTP JSON `forbidden_capability`. Still no SSE. Capability-level / entitlement kills (`global`, `capability:clinic.visit_summary`, `installation:<id>`, or `provider:fake` — the entitlement check hardcodes `providerId: "fake"`) likewise 503 `capability_disabled` **before** SSE. Provider kill switches on DeepSeek/Gemini are the ones that survive to Stage 10 ([§19.3.11](#19311-empty-chain-fail-closed-filters-and-kill-switch-failover)).

#### 19.3.4 Publish and promote a fake-provider policy

Manifest `Routing.routingPolicyRef` is `routing/standard@v1`. Config-cache strips `@v1` and serves the **active** (or matching **canary**) row for `policy_id = standard`, so a later version is fine.

**Do:** publish version `91` (or any unused version), then promote. `max_parallel_attempts: 99` is deliberate — invocation must ignore it.

```bash
curl -s -X POST "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "schema_version": 1,
      "policy_id": "standard",
      "policy_version": 91,
      "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
      "rules": [{
        "rule_id": "verify-fake",
        "match": {},
        "requires": { "structured_output": false, "min_context_window": 0, "languages": [] },
        "targets": [{
          "provider_id": "fake",
          "model_id": "fake-v1",
          "features": {
            "structured_output": true,
            "min_context_window": 128000,
            "languages": ["en"],
            "latency_class": "standard",
            "cost_class": "standard"
          },
          "max_attempts": 1,
          "timeout_ms": 30000
        }],
        "max_parallel_attempts": 99
      }],
      "overrides": []
    }
  }'

curl -s -X POST "$GATEWAY/control/routing-policies/standard/versions/91/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

Restart the Worker.

**Expect:** publish 200, promote 200. D1 row `policy_id=standard`, `version=91`, `status=active`, `content_pointer=control/routing-policy/standard/91.json`. R2 object exists at that key.

#### 19.3.5 Happy fresh path end to end

**Do:**

```bash
invoke_sse "idem-happy-1" "trace-happy-1"
```

Inspect headers and frames. Save `request_reference` from `accepted` as **REF0**.

**Expect — HTTP ([§4](#4-http-response-shape)):** status 200. Headers include `content-type: text/event-stream`, `cache-control: no-cache`, `connection: keep-alive`.

**Expect — SSE order and fields:**

1. `event: accepted` first. `data` has `request_reference` (`XXXX-XXXX`), `trace_id: "trace-happy-1"`, and **no** `degraded_notice` (first credits are below a default 0.8 soft threshold).
2. `event: text_delta`. `data.text` is `"Fake adapter summary."` (the fake adapter’s fixed prose). `data.sequence` is `0`. `data.provisional` is `true`. **Platform today:** `data` does **not** include `trace_id` — the broker puts `trace_id` on the event wrapper, and `encodeSseEvent` serializes only `event.data`. [§4](#4-http-response-shape) / [§11.4](#114-text_delta) say every `data` object includes `trace_id`; Expect the wire (omit), and treat that as the same class of gap [§18](#18-spec-vs-platform-behavior-today) lists for other topics.
3. `event: completed`. `data.result.finalContent.text` equals the assembled deltas (`"Fake adapter summary."`). `data.result.finalContent.authoritative` is `true`. `data.trace_id` is `"trace-happy-1"`.
4. **No** further events after that terminal. **No** `heartbeat` (invoke finished in milliseconds; the 15 s silence timer never fires). **No** `regenerating`. **No** `context_requested` (visit summary is `single_shot`). **No** second terminal.

Exactly one `completed`. Fake path does not wait for a real model — you still see `accepted` → `text_delta` → `completed`, which is this stage’s happy path.

#### 19.3.6 Canonical request, routing decision, and settlement

**Do:** after [§19.3.5](#1935-happy-fresh-path-end-to-end), wait ~2 s, then D1:

```sql
SELECT request_id, state, routing_tier, routing_decision, payload_pointer, trace_id, terminal_error_code
FROM ai_request WHERE request_reference = '<REF0>';
```

Fetch the envelope at `payload_pointer`. Count `ai_attempt` and `usage_event` for that `request_id`.

**Expect — journal (fresh path, [§3](#3-boundary-with-stage-9-the-guard) / [§8](#8-phase-c--routing-d1--r2) / [§17](#17-settlement-handoff-stage-11)):**

- Exactly **one** new `ai_request` row (this HTTP connection). `trace_id = trace-happy-1`. `routing_tier = standard`. `state = Completed`, `completed_at` set, `terminal_error_code` null.
- `routing_decision` is JSON (not NULL). It includes `policy_id: "standard"`, `policy_version: 91`, `rule_id: "verify-fake"`, `effective_cost_class`, `cost_class_source` (`manifest` on this path), `routing_tier: "standard"`, `chain[]` with one entry `{ provider_id: "fake", model_id: "fake-v1", max_attempts: 1, timeout_ms: 30000 }`, `excluded: []`. It does **not** contain `max_parallel_attempts` (the document’s `99` was dropped).
- `payload_pointer = request/<request_id>/envelope`.

**Expect — CanonicalRequest in `envelope.prompt` ([§12](#12-canonicalrequest--every-field)) — every field.** The object is **not** in any SSE frame.

| Field | Expect |
| ----- | ------ |
| `parts[]` | Visit-summary order: `system` (instruction), `system` (business rules), `system` (output-format instruction), `data` (rendered `<key name="visit.chief_complaint@v1">…`), `user` (`user_intent` after `neutralizeText`) |
| `parts[].role` / `content` | Roles as above; user/data strings have `</` as `\u003c/` if you put that substring in intent/context |
| `formatDirective.mode` | `"prose"` |
| `formatDirective.outputSchemaRef` | `null` |
| `samplingConstraints.allowedLanguages` | `["en"]` |
| `samplingConstraints.temperature` | omitted (not populated for visit summary) |
| `maxOutputTokens` | `1024` |
| `stopConditions` | `[]` |
| `toolDeclarations` | `[]` |
| `stream` | `true` |
| `deadline` | `null` (unbounded unless the guard forwarded one) |
| `correlationIds.request_reference` | **REF0** |
| `correlationIds.trace_id` | **JTI0** (AAT `jti`), **not** `trace-happy-1` |

**Expect — envelope attempts / result:** `attempts[0].payload` includes `{ "fake": true, "outcome": "success" }` (fake adapter raw body, not a DeepSeek messages array). `result` carries fake usage (`input: 10`, `output: 20`), `providerModel.provider = "fake"`, `model = "fake-v1"`, `finishReason = "stop"`, `providerRequestId = "fake-req-001"`.

**Expect — Stage 10 → 11 handoff (positives this doc asserts; column-level R2 keys live in Stage 11):** one `ai_attempt` (`provider=fake`, `model=fake-v1`, `outcome=success`, `tokens_in=10`, `tokens_out=20`, `provider_request_id=fake-req-001`). One `usage_event` for this `request_id` with `quota_weight=1` and tokens = 30. Quota DO `inFlight` released (a second **new** idempotency key still admits). Stage 10 emitted the terminal SSE and then reused Stage 11 writers; it does not implement lookup ([§19.3.15](#19315-what-this-stage-does-not-do)).

#### 19.3.7 Two trace identifiers and ignored injection keys

**Do:** POST with `x-trace-id: client-trace-7` and a body that **also** includes `"routing_tier":"degraded","degraded":true,"degraded_notice":true` plus the visit-summary fields. New idempotency key.

**Expect:** `accepted.data.trace_id` and D1 `ai_request.trace_id` are `client-trace-7`. Envelope `prompt.correlationIds.trace_id` is still **JTI0** (or the new AAT’s `jti` if you reminted) — not `client-trace-7`. `accepted` has **no** `degraded_notice`. Ingress ignores those body keys; degraded comes only from admission ([§18](#18-spec-vs-platform-behavior-today) invoke-time tier).

#### 19.3.8 Idempotent replay of completed

**Do:** `invoke_sse "idem-happy-1" "trace-replay-1"` — **same** `x-idempotency-key` as [§19.3.5](#1935-happy-fresh-path-end-to-end), new trace.

Count D1 `ai_request` rows and `ai_attempt` rows before vs after. Note `routing_decision` on **REF0**.

**Expect:** HTTP 200 SSE. `event: accepted` then `event: completed` with `result.finalContent.text = "Prior request completed."` and `authoritative: true` — **not** `"Fake adapter summary."` and **not** an R2 replay ([§15](#15-idempotent-replay-path-no-provider-call), [§18](#18-spec-vs-platform-behavior-today)). No `text_delta` (no provider). No new `ai_request` INSERT (still one row for **REF0**). `routing_decision` unchanged. `ai_attempt` count unchanged. Envelope object not rewritten (same `payload_pointer`). DO prior state `completed` (or `admitted` if you raced an in-flight job) maps to this placeholder; you are not charged a second provider call.

#### 19.3.9 Default provider chain without API keys

**Do:** publish+promote version `92` whose `targets` copy `ai-platform/control/routing-policy/platform-default/1.json` (DeepSeek `deepseek-v4-flash` `max_attempts: 2`, then Gemini `gemini-3.5-flash`). Restart. Confirm Worker env has **no** `DEEPSEEK_API_KEY` / `GEMINI_API_KEY`. `invoke_sse "idem-ds-1" "trace-ds-1"`. Then promote `91` again (or continue with later versions in the next probes) and restart so later probes use fake.

**Expect:** `accepted`, then `failed` with `code: "provider_rejected"`, `retry_safe: false` (taxonomy `retryable: "No"`). **No** Gemini `ai_attempt` row — missing DeepSeek secret is a **terminal** class ([§14](#14-invocation-retry-and-fallback-logic)); the loop does not walk the rest of the chain. D1 `state=Failed`, `terminal_error_code=provider_rejected`. At least one `ai_attempt` (`provider=deepseek`, outcome `terminal_failure`). Quota DO still `credit`s (failed path). This is why local happy-path probes must pin `fake`.

#### 19.3.10 Retry, fallback, and chain exhaustion

**Do:** publish+promote version `93`: catch-all with two targets that both advertise visit-summary features (`en`, `standard` latency, window ≥ 32000). First: `provider_id: "bogus-primary"`, `model_id: "bogus-v1"`, `max_attempts: 2`. Second: `fake` / `fake-v1`, `max_attempts: 1`. Restart. Time a successful invoke:

```bash
time invoke_sse "idem-fb-1" "trace-fb-1"
```

**Expect:** `accepted`, then `text_delta` from fake (`"Fake adapter summary."`), then `completed`. **No** `regenerating` — bogus failures do not stream text, so there is no partial to discard. Wall-clock `time` is **≥ ~100 ms** (jittered 100 ms × 2^0 backoff between the two bogus attempts; production uses `wallClockSleeper`). D1 `routing_decision.chain` lists bogus then fake. `ai_attempt`: two rows `provider=bogus-primary` `outcome=retryable_failure` `error_code=provider_unavailable`, then one `provider=fake` `outcome=success`. **Platform today:** there is **no** `ai_attempt.selection_reason` column ([§14](#14-invocation-retry-and-fallback-logic) names `primary` / `fallback_after_retryable_error` / `fallback_after_timeout` on the in-memory `AttemptRecord` only). Expect the second provider to differ from the first — that is the live fallback signal.

**Do:** publish+promote version `94`: **only** `bogus-primary` with `max_attempts: 2` (no fake). Restart. `invoke_sse "idem-ex-1" "trace-ex-1"`.

**Expect:** `accepted`, then `failed` `code: "provider_unavailable"`, `retry_safe: true`, same `request_reference` as this connection’s `accepted`. D1 `Failed`. `ai_attempt` count ≥ 1 (exhausted retries). Envelope exists. This is [§16](#16-failure-paths-after-accepted) “all providers exhausted”.

#### 19.3.11 Empty chain, fail-closed filters, and kill-switch failover

Restore a usable fake chain after each promote (version `95+`) or the later cancel probes will fail.

**Empty chain / undersized window.** **Do:** publish+promote a catch-all whose only target has `features.min_context_window: 1000` (visit summary needs 32000) and `provider_id: "fake"`. Restart. Invoke.

**Expect:** `accepted`, then `failed` `provider_unavailable`. `routing_decision.chain` is `[]`. `excluded[]` has `reason_code: "context_window_too_small"`. Failed settlement still writes ≥1 diagnostic `ai_attempt` and one R2 envelope (`payload` may include `reason: "no_provider_attempt"`).

**Fail-closed malformed `languages`.** **Do:** two targets: first `fake` with `"languages": "en"` (string, not array); second `fake` / `fake-v1` with a proper `languages: ["en"]` array (use `provider_id: "bogus-malformed"` on the first so you can tell them apart). Restart. Invoke.

**Expect:** completed via the well-formed fake target. `excluded[]` includes `reason_code: "feature_unsupported"` for the malformed advertisement — not `internal_error`, and the Worker does not throw.

**Latency / cost class.** **Do:** a lone target with `latency_class: "interactive"` (manifest is `"standard"`) → `feature_unsupported` → empty chain → `provider_unavailable`. A lone target with `cost_class: "premium"` while effective class is `standard` (hardcoded manifest `"standard"` in `worker.ts`) → `cost_class_excluded`. Changing D1 entitlement does **not** raise the ceiling: `entitlementMaxCostClass` is hardcoded `"premium"` ([§18](#18-spec-vs-platform-behavior-today)); the effective min is still `standard` from the manifest constant. An `overrides[].force_cost_class: "economy"` **does** bind (`cost_class_source: "installation_override"`) — that is the live third source.

**Kill-switch failover.** **Do:** publish+promote chain `[deepseek, fake]` (both feature-valid). Insert a provider kill (not a capability kill):

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT OR REPLACE INTO kill_switch (scope, target, active, changed_at, changed_by)
   VALUES ('provider', 'deepseek', 1, datetime('now'), 'verify-stage-10')"
```

Restart. Invoke. Then set `active=0` (or delete the row) and restart so later probes are clean.

**Expect:** `accepted` then fake `completed` — **not** HTTP 503. `routing_decision.excluded` contains `{ provider_id: "deepseek", reason_code: "kill_switch" }`. `chain[0].provider_id` is `fake`. Killing `provider:fake` is **Stage 9** (entitlement `providerId: "fake"`) and never reaches `accepted` ([§19.3.3](#1933-guard-boundary-without-sse)).

**Installation override.** **Do:** `overrides: [{ "installation_id": "<I0>", "exclude_providers": ["fake"] }]` on a fake-only rule.

**Expect:** empty chain, `excluded[].reason_code = "installation_excluded"`, SSE `provider_unavailable`.

#### 19.3.12 Client disconnect and cancelled replay

Need a window longer than a successful fake invoke. Use the version `93` retry chain (bogus `max_attempts: 2` then fake) so the Worker sleeps ~100–150 ms before fake runs.

**Do:**

```bash
curl -N -sS -D /tmp/cancel-headers.txt -o /tmp/cancel-body.txt \
  --max-time 0.08 \
  -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: idem-cancel-1" \
  -H "x-capability-version: 1.0.0" \
  -H "x-trace-id: trace-cancel-1" \
  -d "$VISIT_BODY" || true
sleep 2
```

**Expect:** curl exits on timeout (connection drop). `/tmp/cancel-body.txt` may contain `accepted` and **no** terminal — the adapter’s `cancel()` path does not enqueue `event: cancelled` because the client is already gone. D1 `ai_request.state = Cancelled` for this `request_reference`. One `usage_event` (zero tokens allowed). `ai_attempt` may be empty if abort happened before the first provider call, or may list the bogus attempt(s) if abort was mid-retry — both match [§17](#17-settlement-handoff-stage-11) (Cancelled always has `usage_event`; attempts only when invocation recorded them). Quota DO credited `partial: true` (next probe proves the idempotency state).

**Do — observe SSE `cancelled` via replay ([§11.7](#117-cancelled), [§15](#15-idempotent-replay-path-no-provider-call)):**

```bash
invoke_sse "idem-cancel-1" "trace-cancel-replay"
```

**Expect:** `accepted`, then `event: cancelled` with `data: { "trace_id": "trace-cancel-replay" }` only (no `code`, no `request_reference` on this event). No provider `text_delta`. No new journal row. This is how you read the cancelled terminal on the wire after a drop.

#### 19.3.13 Idempotent replay of failed

**Do:** reuse `idem-ex-1` from the exhausted-chain failure ([§19.3.10](#19310-retry-fallback-and-chain-exhaustion)):

```bash
invoke_sse "idem-ex-1" "trace-fail-replay"
```

**Expect:** `accepted`, then `failed` `code: "internal_error"` — **not** `provider_unavailable` again. [§15](#15-idempotent-replay-path-no-provider-call) maps DO `failed` to placeholder `internal_error`. No new `ai_attempt`. `retry_safe: true` on that taxonomy body.

#### 19.3.14 Degraded notice and canary preference

**Degraded `accepted`.** **Do:** lower the soft threshold on the already-entitled row (entitle is one-shot; this is a throwaway D1 UPDATE), restart, then a **new** idempotency key:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE entitlement SET soft_threshold = 0.001 WHERE installation_id = '$INSTALLATION_ID'"
```

Restart. `invoke_sse "idem-deg-1" "trace-deg-1"`.

**Expect:** `accepted.data.degraded_notice === true` (boolean present, not a body-injected flag). D1 `routing_tier = degraded`. `routing_decision.routing_tier = "degraded"` — journaled tier and invoke-time `match.tiers` agree ([§18](#18-spec-vs-platform-behavior-today)). If you add a rule `match.tiers: ["degraded"]` with a distinctive `rule_id`, that rule is the one persisted.

**Canary.** **Do:** publish version `96` with `rule_id: "verify-canary-fake"` (fake target). Canary **only** this installation; leave `91`/`95` as `active` for everyone else:

```bash
curl -s -X POST "$GATEWAY/control/routing-policies/standard/versions/96/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\": [\"$INSTALLATION_ID\"]}"
```

Restart. Invoke with a new key.

**Expect:** `routing_decision.policy_version = 96` and `rule_id = "verify-canary-fake"` for this installation. Config-cache prefers `status='canary'` whose `canary_installation_ids` contains this id, else `active`, both `ORDER BY active_from DESC, rowid DESC`.

#### 19.3.15 What this stage does not do

**Do:** `GET $GATEWAY/v1/requests/<REF0>` with the AAT (Stage 12 lookup). Confirm it returns the completed result from the envelope. Then confirm none of the following happened *as this stage’s job*.

**Expect:**

- This stage does **not** run the guard (identity, entitlement, quota admit, journal INSERT, compose). Those are Stages 8–9; this stage starts at SSE `accepted`.
- This stage does **not** mint AATs, enroll, or entitle.
- This stage does **not** implement support lookup, retention, or dashboards (Stage 12 / crons). It only hands a terminal to Stage 11 writers.
- Visit summary does **not** emit `context_requested`; that terminal is conversational-only. The `context_request` schema is therefore not exercised here.
- CanonicalRequest is **not** sent to the clinic client.
- Routing is **stateless**: a failed bogus provider on one request does not change the next request’s `chain[]` unless you change policy, kills, or overrides.

**Unprobeable on the local fake path (do not fake a pass):**

| Claim | Why it cannot be probed here |
| ----- | ---------------------------- |
| Missing guard handoff → SSE `failed` `internal_error` ([§7](#7-phase-b--dispatch-fresh-vs-idempotent), [§16](#16-failure-paths-after-accepted)) | `acceptContexts` is request-scoped; there is no client header that drops it |
| Live `heartbeat` frame ([§11.2](#112-heartbeat)) | FakeAdapter returns in milliseconds; 15 s silence never happens. Absence on [§19.3.5](#1935-happy-fresh-path-end-to-end) is the live check of the interval rule |
| `regenerating` after partial stream ([§11.3](#113-regenerating), [§9](#9-phase-d--provider-invocation)) | Production fake always `success`; unknown-provider errors emit no `text_delta` first |
| Truncation → `validation_failed` rather than authoritative `completed` ([§9](#9-phase-d--provider-invocation), [§10](#10-phase-e--stream-relay-and-output-guards)) | Production `FakeAdapter(["success"])` uses `finishReason: "stop"`, not `length` |
| Output-guard trips: 128_000 chars, stop sequence from [§10](#10-phase-e--stream-relay-and-output-guards), 48-char system-instruction leak needles, refusal prefixes, injection-echo needle | Fake prose is `"Fake adapter summary."` — none of those markers. Happy path only proves they do **not** false-positive on that string |
| DeepSeek `messages[]` role map / Gemini `systemInstruction` / `stream_options.include_usage` / `:streamGenerateContent?alt=sse` ([§13](#13-provider-wire-transformation)) | Missing secrets fail before fetch ([§19.3.9](#1939-default-provider-chain-without-api-keys)). Inspect CanonicalRequest in R2 instead |
| Retry-After honored as `max(jittered, retryAfterMs)` against a real 429 | Needs a live adapter that parses Retry-After |
| Catching `routing_decision IS NULL` in the instant after `accepted` ([§6](#6-phase-a--sse-accepted)) | Phase C runs in-process before you can query D1; after the stream ends it is always populated on the fresh path |

---

*Cross-references: [Stage 8 — Request ingress](10-stage-8-request-ingress.md), [Stage 9 — The guard](11-stage-9-the-guard.md), [Stage 5 — Routing policy](07-stage-5-routing-policy.md), [Stage 11 — Terminal settlement](13-stage-11-terminal-settlement.md).*
