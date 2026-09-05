# AI Platform — Request Lifecycle (Brief)

Source of truth: `ai-platform/src/`. Supplementary: [09-ai-platform-request-response-flow.md](09-ai-platform-request-response-flow.md), [data-journey/10-stage-8-request-ingress.md](data-journey/10-stage-8-request-ingress.md), [data-journey/12-stage-10-accept-route-invoke-stream.md](data-journey/12-stage-10-accept-route-invoke-stream.md).

**Route:** `POST /v1/requests` → `worker.ts` → `handleLivePostRequest()` → `handleAdapterRequest()` with guard (`createProductionPreAccept`) and event source (`createProductionEventSource`).

---

## Table of Contents

1. [Wrangler bindings](#1-wrangler-bindings)
2. [Verification — adapter gate](#2-verification--adapter-gate)
3. [Verification — guard stages 1–10](#3-verification--guard-stages-110)
4. [On pass — happy path](#4-on-pass--happy-path)
5. [Cost and remaining quota](#5-cost-and-remaining-quota)
6. [Storage reads and writes](#6-storage-reads-and-writes)
7. [Failures](#7-failures)

---

## 1. Wrangler bindings

| Binding | Type | Role in request lifecycle |
|---------|------|---------------------------|
| `DB` | D1 | Installations, keys, entitlements, grants, kill switches, routing policy metadata, `ai_request` journal, `usage_event` ledger, grace queue |
| `R2` | R2 | Routing policy document bodies; response envelope after settlement |
| `DO` | Durable Object (`GatewayObject`) | Per-installation quota admission, credit, release |
| `RATE_LIMITER_INSTALLATION` | CF Rate Limit | Stage 4 — per installation |
| `RATE_LIMITER_INSTALLATION_ACTOR` | CF Rate Limit | Stage 4 — per installation + actor |
| `RATE_LIMITER_INSTALLATION_CAPABILITY` | CF Rate Limit | Stage 4 — per installation + capability |
| `DEEPSEEK_API_KEY`, `GEMINI_API_KEY` | Worker secrets | Provider HTTP auth (not in wrangler.toml) |
| `CONFIG_CACHE_TTL_MS`, `LOG_VERBOSITY`, `BUILD_SHA`, `ENVIRONMENT` | Vars | Isolate config cache TTL, logging |

**Not used at invoke:** KV. Manifests and prompt artifacts are bundled in memory at worker boot (`manifest/load()`, `prompt/registry.ts`).

---

## 2. Verification — adapter gate

Runs in `adapter.ts` → `handleAdapterRequest()` **before** the guard. No D1/R2/DO I/O.

| Check | Fail |
|-------|------|
| Body ≤ 1 MiB (`INGRESS_BODY_SIZE_LIMIT`) | **413** `request_too_large` (taxonomy JSON) |
| Valid JSON, top-level plain object | **422** empty body |
| `x-idempotency-key` non-empty | **422** |
| `x-capability-version` non-empty | **422** |
| `x-trace-id` if present, non-empty | **422** |
| `eventSource` configured | **503** plain text |

Required headers for production: `Authorization: Bearer <AAT>`, `x-idempotency-key`, `x-capability-version`. Body must include `capability_id` (or `capability`).

---

## 3. Verification — guard stages 1–10

Orchestrated by `pipeline/index.ts` → `runGuard()`, invoked from `worker.ts` → `createProductionPreAccept()`. Failures return taxonomy JSON (no SSE stream).

### 3.1 Stage 1 — Size and JSON shape

Re-checks body bytes; parses adapter body fields (`user_intent`, `context`, `conversation_id`, `turn_ordinal`, `transcript`).

| Fail | HTTP |
|------|------|
| `request_too_large` | 413 |
| `internal_error` | 500 |

**Reads:** none.

### 3.2 Stage 2 — AAT / JWT identity

`identity/index.ts` → `EnrolledKeyVerifier.verify()`:

1. JWT structure, `alg === EdDSA`, `kid` present
2. Claims: `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`
3. `aud === "ai-platform"`, clock skew ±60s, lifetime ≤ 600s
4. **D1 (via isolate config cache):** `installation` (by `iss`), `installation_key` (by `kid`)
5. Ed25519 signature verify; key not revoked; installation `active` (not `suspended`)
6. **D1:** `token_contract` (by `ver`, not retired)

| Fail | HTTP |
|------|------|
| `unauthenticated` | 401 |
| `installation_suspended` | 403 |

### 3.3 Stage 3 — Entitlement

`entitlement/index.ts` → `evaluateEntitlement()`:

- **D1:** `entitlement` (status `active`), `capability_grant`, `kill_switch`
- Plan tier, `allowed_capabilities`, grant scope/version, kill switches (`global`, `capability:{id}`, `installation:{id}`, `provider:{id}`)

| Fail | HTTP |
|------|------|
| `forbidden_capability` | 403 |
| `capability_disabled` | 503 |

### 3.4 Stage 4 — Rate limit

`rate-limit/index.ts` → `checkRateLimit()` against three CF Rate Limit bindings (installation, installation+actor, installation+capability).

| Fail | HTTP |
|------|------|
| `rate_limited` + `retry_after` | 429 |

Rejection tallies buffered in isolate; flushed to D1 `platform_counter` on cron.

### 3.5 Stage 5 — Capability / manifest resolve

`capability/index.ts` → `resolve()`:

- **Memory:** frozen manifest registry (`{capability_id}@{x-capability-version}`)
- **D1:** `capability_grant` (lifecycle overlay), `entitlement`, `kill_switch`, `routing_policy` (metadata)
- **R2:** routing policy document (via `content_pointer`) — for provider kill-switch enumeration only

| Fail | HTTP |
|------|------|
| `capability_unknown`, `capability_retired` | 404 |
| `forbidden_capability` | 403 |
| `capability_disabled` | 503 |

### 3.6 Stage 6 — Context validation

`context/validator.ts` → `validateContext()` — manifest-driven required keys, org/branch match principal, A5 shapes, transcript budgets. No storage I/O.

| Fail | HTTP |
|------|------|
| `context_required`, `context_invalid` | 422 |
| `conversation_budget_exhausted` | 409 |

### 3.7 Stage 7 — Cost preflight (token ceiling only)

`context/preflight.ts` → `runCostPreflight()` — estimates input tokens (UTF-8 bytes / 4 × 1.15 + prompt artifact bytes). Compares against manifest `Economics` (`maxInputTokens`, `maxOutputTokens`, `perRequestTokenCeiling`). **No dollar cost, no quota decrement.**

| Fail | HTTP |
|------|------|
| `request_too_large` | 413 |

### 3.8 Stage 8 — Quota admission

`admission/index.ts` → `runAdmission()` → **DO RPC** `admissionRPC()` on `DO.idFromName(installationId)`:

1. **D1:** `entitlement` → budget limits (`request_quota`, `token_budget`, `cost_budget`, `soft_threshold`, period bounds)
2. **DO checks:** JTI replay, idempotency key, `periodCounters` vs entitlement limits, `inFlight < 16`
3. On admit: `inFlight++`, record `admittedRequests[requestId]`; optional `degraded` if soft threshold crossed
4. **Does not** increment `requestsUsed`, `tokensUsed`, or `costUsed`

**DO unavailable (5xx):** grace path → D1 `grace_admission_queue` (cap 5 pending/installation); ledger pre-check on `ai_request` + `usage_event`.

| Fail | HTTP |
|------|------|
| `unauthenticated` (replay/expired) | 401 |
| `quota_exhausted` (budget or concurrency) | 429 |
| `rate_limited` (grace queue full) | 429 + `retry_after` |
| `internal_error` | 500 |

**Idempotent hit:** short-circuits stages 9–10; SSE replays prior terminal state.

### 3.9 Stage 9 — Journal INSERT

`journal/index.ts` → `createRequestRow()` — **D1 INSERT** `ai_request` with `state = Accepted`.

On D1 failure: **DO RPC** `releaseRPC()` rolls back admission slot.

| Fail | HTTP |
|------|------|
| `context_invalid` (missing conversational fields) | 422 |
| `internal_error` | 500 |

### 3.10 Stage 10 — Prompt composition

`prompt/composer.ts` → `composeRequest()` — resolves bundled prompt artifacts, renders template, builds `CanonicalRequest`. On failure: **D1 UPDATE** `ai_request` → `Failed` (admission slot not released).

| Fail | HTTP |
|------|------|
| `internal_error` | 500 |

---

## 4. On pass — happy path

### 4.1 SSE accepted

Guard returns `ok: true` → adapter emits `event: accepted` (HTTP **200** `text/event-stream`), optionally `degraded_notice`. Background work via `executionCtx.waitUntil` → `runFreshEventSource()`.

### 4.2 Routing

`router/index.ts`:

1. `preloadRoutingPolicyForInstallation()` — **D1** `routing_policy` row + **R2** policy JSON (via `content_pointer`)
2. `selectCandidateChain()` — ordered provider chain from policy, capability requirements, admission routing tier, killed providers from stage 5
3. `persistRoutingDecision()` — **D1 UPDATE** `ai_request.routing_decision`

### 4.3 Provider invocation

`invocation/index.ts` → `runInvocation()`:

1. Walk `routingDecision.chain` sequentially
2. `resolveProviderPort()` → `DeepSeekAdapter` / `GeminiAdapter` / `FakeAdapter` via `provider/wiring.ts`
3. `mapCanonicalToWire()` transforms `CanonicalRequest` to provider wire format
4. `createFetchTransport()` POSTs to provider API with secret from env
5. SSE parsed incrementally; `onStreamChunk` pushes `text_delta` events
6. Per-target retries with exponential backoff + jitter (cap 10s); fallback to next chain entry on retryable errors
7. Concurrent with `createStreamBroker()` — prose guards, heartbeats every 15s

### 4.4 Settlement (success)

`worker.ts` → `settleCompletedRequest()`:

1. `ledgerUsageFromProvider()` — cost from provider token counts × pricing table
2. `creditUsage()` → **DO RPC** `creditRPC()` — increment `tokensUsed`, `costUsed`, `requestsUsed`; decrement `inFlight`
3. `writePostResponseDetail()` (via `waitUntil`) — **D1** `ai_attempt`, `usage_event`, `ai_request` terminal state + **R2** envelope at `request/{requestId}/envelope`

---

## 5. Cost and remaining quota

### 5.1 Cost calculation (post-provider only)

`pricing/index.ts` → `priceUsage()`:

```
cost = round6((inputTokens/1000) × input_per_1k + (outputTokens/1000) × output_per_1k)
```

Rates from `control/pricing/platform-default/1.json` per model (fallback: `default`). Partial/cancel: `estimateUsageFromStreamedChars()` prices streamed character count as output tokens.

`quotaWeight` from manifest is stored on `usage_event` for reporting — **does not** affect DO counters (always +1 request per credit).

### 5.2 Remaining quota (not exposed to clinic client)

Budget **limits** live in D1 `entitlement`. **Counters** live in Quota DO `periodCounters`. Remaining is not returned to the clinic client on `POST /v1/requests`, but operators can read a live snapshot via `GET /control/installations/{installation_id}/quota` ([Operator runbook §6.4](04-ai-platform-operator-runbook.md#64-durable-objects-quota--admission)):

| Dimension | Remaining |
|-----------|-----------|
| Requests | `request_quota - requestsUsed` |
| Tokens | `token_budget - tokensUsed` |
| Cost (USD) | `cost_budget - costUsed` |

Admission checks counters **before** provider call; credit increments them **after**. Budget of `0` blocks immediately. Period rollover resets counters when entitlement `period_start`/`period_end` change (preserves `inFlight`).

---

## 6. Storage reads and writes

### 6.1 D1 tables — reads (full request)

| Table | When |
|-------|------|
| `installation`, `installation_key`, `token_contract` | Stage 2 (identity) |
| `entitlement`, `capability_grant`, `kill_switch` | Stages 3, 5, 8 |
| `routing_policy` | Stage 5 (kill switches), post-accept routing |
| `ai_request`, `usage_event` | Grace fallback ledger check (stage 8) |

All config reads go through isolate config cache (`CONFIG_CACHE_TTL_MS`, default 30s).

### 6.2 D1 tables — writes

| Table | When | What |
|-------|------|------|
| `ai_request` | Stage 9 | INSERT `Accepted` |
| `ai_request` | Stage 10 fail | UPDATE `Failed` |
| `ai_request` | Post-accept | UPDATE `routing_decision`, terminal `state`/`completed_at`/`terminal_error_code`, `payload_pointer` |
| `ai_attempt` | Settlement | INSERT per provider attempt |
| `usage_event` | Settlement | INSERT tokens, cost, quota_weight |
| `grace_admission_queue` | DO down + grace admit | INSERT; UPDATE usage before reconcile |
| `platform_counter` | Guard rejections | Tally (cron flush) |

### 6.3 R2

| Operation | Key | When |
|-----------|-----|------|
| **Read** | `routing_policy.content_pointer` | Routing policy resolution |
| **Write** | `request/{requestId}/envelope` | Settlement — `{ context, prompt, attempts[], result }` |

### 6.4 Quota DO (`GatewayObject`, one per installation)

| RPC | When | State change |
|-----|------|--------------|
| `admission` | Stage 8 | `jtiReplay`, `idempotency`, `inFlight++`, `admittedRequests` |
| `release` | Stage 9 journal fail | Roll back admission |
| `credit` | Settlement | `tokensUsed/costUsed/requestsUsed++`, `inFlight--`, `creditedRequests`, idempotency terminal |
| `inspect` | Operator GET `/control/installations/{id}/quota` | None (read-only; ephemeral sweep applied in memory, not persisted) |

DO ephemeral keys swept after 2h (`EPHEMERAL_HORIZON_MS`).

---

## 7. Failures

### 7.1 Pre-accept failures (stages 1–8, adapter gate)

| Store | Written? |
|-------|----------|
| D1 `ai_request` | **No** |
| D1 `ai_attempt`, `usage_event` | **No** |
| R2 | **No** |
| DO | Refused: nothing. Stage 9 fail: `release`. |
| D1 `grace_admission_queue` | Only if DO unavailable + grace admitted |
| D1 `platform_counter` | Rejection tallies |

Response: HTTP JSON `{ code, request_reference, trace_id, retry_safe [, retry_after] }`. Status from `errors.ts` → `liveHttpStatusForCode()`.

**Note:** `period_reset` on `quota_exhausted` and `missing_keys` on `context_required` are computed in code but **not** forwarded on live HTTP responses.

### 7.2 Stage 10 compose failure (pre-SSE)

| Store | Written? |
|-------|----------|
| D1 `ai_request` | Yes → `Failed` |
| DO | Admission slot held until ephemeral sweep (no `releaseRPC`) |

### 7.3 Post-accept failures (after `event: accepted`)

Provider/validation failures arrive as SSE `event: failed` or `cancelled`, not HTTP errors.

| Condition | SSE | Settlement |
|-----------|-----|------------|
| Provider terminal error (`provider_rejected`) | `failed` | `settleTerminal` — credits full usage if `consumesQuota` |
| Retryable exhausted (`provider_unavailable`, `timeout`) | `failed` | Partial credit (`partial=true`) |
| Prose guard violation, truncation | `failed` `validation_failed` | Full credit |
| Client disconnect | `cancelled` (may not enqueue on wire) | Partial credit |
| Success | `completed` | Full credit |

**Post-accept writes (all terminal outcomes):**

| Store | Written? |
|-------|----------|
| D1 `ai_request` | Terminal state |
| D1 `ai_attempt` | ≥1 row |
| D1 `usage_event` | Yes (partial or full) |
| DO `credit` | Decrement `inFlight`, update counters |
| R2 envelope | Yes (includes attempts; placeholder result on failure) |

### 7.4 Failure code quick reference

| Layer | Codes | HTTP / SSE |
|-------|-------|------------|
| Adapter | parse/header/body size | 422 plain, 413 taxonomy |
| Identity | `unauthenticated`, `installation_suspended` | 401, 403 |
| Entitlement | `forbidden_capability`, `capability_disabled` | 403, 503 |
| Rate limit | `rate_limited` | 429 |
| Capability | `capability_unknown`, `capability_retired`, `capability_disabled` | 404, 503 |
| Context | `context_required`, `context_invalid`, `conversation_budget_exhausted` | 422, 409 |
| Preflight | `request_too_large` | 413 |
| Admission | `quota_exhausted`, `rate_limited` (grace) | 429 |
| Provider (post-accept) | `provider_rejected`, `provider_unavailable`, `timeout`, `validation_failed` | SSE `failed` |
| Cancel | `cancelled` | SSE only |

### 7.5 Idempotent replay

Same `(installationId, idempotencyKey)` while prior request is in-flight or terminal → admission returns `idempotent`; guard skips stages 9–10; SSE opens with `accepted` then replays prior terminal (`completed`/`failed`/`cancelled`). No new journal row, no provider call, no settlement.

---

## Key source files

| Concern | Path |
|---------|------|
| HTTP ingress + SSE | `ai-platform/src/adapter.ts` |
| Orchestration | `ai-platform/src/worker.ts` |
| Guard pipeline | `ai-platform/src/pipeline/index.ts` |
| Quota DO | `ai-platform/src/quota-do/index.ts` |
| Routing | `ai-platform/src/router/index.ts` |
| Invocation | `ai-platform/src/invocation/index.ts` |
| Stream broker | `ai-platform/src/stream/index.ts` |
| Pricing | `ai-platform/src/pricing/index.ts` |
| Journal + R2 | `ai-platform/src/journal/index.ts` |
| Config cache | `ai-platform/src/config-cache/index.ts` |
| Taxonomy | `ai-platform/src/errors.ts` |
