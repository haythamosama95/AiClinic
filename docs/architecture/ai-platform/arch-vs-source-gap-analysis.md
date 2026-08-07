# AI Platform — Architecture vs Source Gap Analysis

Comparison of `docs/architecture/ai-platform/01-ai-platform.md` against `ai-platform/` source only. No other documents were consulted.

**Verdict:** Most pipeline modules exist as libraries and are heavily unit-tested, but the Worker does **not** run an end-to-end inference path. `POST /v1/requests` always returns **503** (`event source required`). Client discovery and usage summary surfaces are absent as HTTP routes. Several control-plane functions (entitlement economics, kill switches, dashboards) are missing or incomplete.

---

## Table of Contents

1. [Scope and method](#1-scope-and-method)
2. [Missing modules to implement](#2-missing-modules-to-implement)
3. [Missing wirings for end-to-end operations](#3-missing-wirings-for-end-to-end-operations)
4. [Client → AI Platform request surface](#4-client--ai-platform-request-surface)
5. [Quick status matrix](#5-quick-status-matrix)

---

## 1. Scope and method

| Source | Role |
|--------|------|
| `docs/architecture/ai-platform/01-ai-platform.md` | Required design (modules, pipeline stages, API surfaces, control plane) |
| `ai-platform/src/**`, `migrations/`, `manifests/`, `prompts/`, `wrangler.toml`, `control/` artifacts | What exists in code |

Clinic-side seams (Flutter SDK, Supabase AAT mint, context RPCs, `record_ai_acceptance`) are architecture-required but **outside** `ai-platform/`; they are noted only where they affect platform E2E, not as Worker module gaps.

---

## 2. Missing modules to implement

Items below are either **absent**, **schema/control writers absent**, or **so incomplete they cannot satisfy the architecture**. Modules that exist as libraries but are only unwired are listed briefly here and detailed in [§3](#3-missing-wirings-for-end-to-end-operations).

### 2.1 Absent or incomplete relative to architecture

| Module (architecture) | Gap in `ai-platform` | Notes |
|-----------------------|----------------------|-------|
| **Worker pipeline compositor / production event source** | No production factory that connects adapter → guard → router → providers → stream brokers | `pipeline/index.ts` explicitly says “no Worker wiring”; `settleHappyPath` uses `FakeAdapter` only |
| **Telemetry emitter** (§4.3.12) | No dedicated telemetry/span emitter module | Guard-rejection tallies flush to `platform_counter` via rate-limit; no per-stage span emitter as described |
| **Entitlement management control plane** (§4.5) | No control routes to assign plan economics | Enroll inserts a `pending`/zeroed entitlement; no mutation to set quota, budget, allowed capabilities, period bounds, soft threshold, or move to `active` |
| **Kill switches** (§4.5, A8) | No D1 table; no control-plane writers | `config-cache` documents: *“No durable kill_switch table… miss ⇒ inactive”*. Entitlement/router **read** kill-switch keys, but nothing can persist them |
| **Usage summary client surface** (§5.5) | No HTTP handler/route | Rollup/credit/Quota DO exist; client cannot query “current period consumption + entitlement” |
| **Capability discovery HTTP surface** (§5.5) | `discover()` / `buildDiscoveryResponse()` exist; **no Worker route** | Architecture requires cacheable discovery for Context Resolver |
| **Operational dashboards exposure** (§4.5) | `dashboards/index.ts` query helpers exist; **no HTTP/control route** | Operator cannot consume health / taxonomy / latency / cost / quota dashboards via the control plane |
| **Production secret store for provider keys** | Adapters expect injectable `SecretStorePort`; `wrangler.toml` declares **no** `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` bindings | Without a Worker-injected secret store, live provider calls cannot authenticate |
| **Kill-switch / entitlement schema completeness** | Migrations have `entitlement`, `capability_grant`, etc., but **no `kill_switch` table** | Blocks durable kill-switch semantics |

### 2.2 Catalog / artifact thinness (modules exist; content incomplete for full product surface)

| Area | Architecture expectation | Source reality |
|------|--------------------------|----------------|
| **Capability registry** | Versioned manifests for AI features | Only `clinic.visit_summary@1.0.0` published under `manifests/published/` |
| **Prompt registry** | Bundled artifacts per capability | Only `prompts/clinic.visit_summary/*` |
| **Context Contract vocabulary** (§5.2) | Published shapes for declared keys | Fully published shape: `visit.chief_complaint@v1`; other §5.2 example keys are named, not fully shaped |
| **Conversational capability** (§6.7 / §8.10) | Same submit surface; context negotiation | Stream/context-request code paths exist in libraries/tests; **no published conversational capability** in `manifests/published/` |

### 2.3 Explicitly deferred in architecture (not current gaps)

Do **not** treat these as missing for “now”:

- OIDC/JWKS token verifier strategy (Tier 3 / reserved)
- Out-of-band cancel / Session Durable Object
- Health-based provider routing
- Workers KV hot config cache (rejected)
- Cloudflare AI Gateway as optional egress hop
- Background/batch inference, embeddings, agentic multi-step tools
- Runtime prompt activation pointer (bundled pins are the current model)

### 2.4 Implemented as libraries (not “missing modules”)

These match architecture stage names and are largely complete as code; the gap is wiring (§3), not greenfield implementation:

Protocol adapter, identity/enrolled-key verifier, entitlement evaluation, rate limiting, capability resolve, context validator, cost preflight, Quota DO admission/credit/release, journal writer, prompt composer/registry, provider router, DeepSeek + Gemini adapters, response validate/repair, prose + structured stream brokers, config cache, support lookup, retention, usage rollup, installation lifecycle / routing policy / token contract / capability deprecate-retire-cohort control handlers.

---

## 3. Missing wirings for end-to-end operations

### 3.1 Critical: inference path is not live

**Architecture happy path** (§7.2 / §6.1): Client submit → guard (1–10) → provider invoke (11) → stream (12–14) → journal/credit/R2 (15–16).

**Source today** (`src/worker.ts`):

```
POST /v1/requests
  → handleAdapterRequest(request)   // options.eventSource omitted
      → parse/size/headers
      → 503 "event source required"
```

Required wiring (not present on Worker):

1. Inject `eventSource` into `handleAdapterRequest` from `worker.ts`.
2. Inside that source: run `runGuard` (stages 1–10) with real bindings:
   - `TokenVerifier` (enrolled key) + `ConfigCache` + D1 reader
   - rate-limit bindings from `env`
   - Quota DO stub (`env.DO`) for admission
   - `composeRequest` from prompt registry
   - journal `createRequestRow`
3. On guard success: emit SSE `accepted`, then invoke production path:
   - `selectCandidateChain` / routing policy preload
   - `createProviderAdapter` for DeepSeek/Gemini with secret store
   - `runInvocation` (retry/fallback)
   - `createStreamBroker` or `createStructuredStreamBroker` by output mode
4. On stream end / cancel: terminal event, `recordTerminalState`, `creditUsage`, R2 envelope (`writePostResponseDetail`).
5. Replace `settleHappyPath`’s `FakeAdapter` with the real invocation chain for production (Fake remains for tests/load).

Until this compositor exists, **no clinic client can complete an AI request** against the Worker, regardless of how complete individual modules are.

### 3.2 Client HTTP surfaces missing or incomplete

| Architecture surface (§5.5) | Source wiring |
|-----------------------------|---------------|
| Capability discovery | Library only — **no route** on `worker.ts` |
| Submit request (SSE) | Route exists; **fails closed** without `eventSource` |
| Cancel (close SSE) | Adapter supports disconnect semantics **once** event source is wired |
| Get request | **Wired**: `GET /v1/requests/{reference}` + AAT auth |
| Usage summary | **Missing route** |

### 3.3 Control-plane wirings incomplete

| Architecture function (§4.5) | Source status |
|------------------------------|---------------|
| Installation lifecycle | Wired (`/control/installations/...`) |
| Entitlement management | **Missing** — enroll only seeds empty/pending row |
| Kill switches | **Missing** — no table, no routes |
| Capability availability | Partially wired (deprecate/retire/activate/promote); grant/gate economics still tied to entitlement gap |
| Token contract rotation | Wired |
| Routing policy publish/canary/promote/rollback | Wired |
| Support lookup | Wired |
| Operational dashboards | Library only — **not exposed** |

### 3.4 Storage / binding wirings

| Dependency | Architecture | Source |
|------------|--------------|--------|
| D1 | Required | Bound (`DB`); schema present except kill switches |
| R2 | Required | Bound (`R2`); used by journal envelopes, routing policy, support, purge |
| Quota Durable Object | Required | `GatewayObject` wired for admission/credit/release RPCs |
| Rate Limiting bindings | Required | Declared in `wrangler.toml`; used by guard library (not yet on live POST) |
| Provider secrets | Required | **Not declared** in `wrangler.toml`; adapters only work when tests inject `secretStore` |
| Workers KV | Rejected by architecture | Correctly absent |

### 3.5 End-to-end clinic flow blockers (platform + external)

Even after Worker wiring, full product E2E still needs (outside this repo folder, but architecture-required):

1. Clinic Supabase: `issue_ai_token`, installation public key, AI-enabled flag.
2. Client: resolve context keys under RLS before submit.
3. Operator: enroll installation, **then** entitlement management to activate economics.
4. Human accept → clinic `record_ai_acceptance` (not a platform call).

Platform-only E2E (operator + direct HTTPS) still needs: entitlement activation + kill-switch persistence (if testing those paths) + secret bindings + the §3.1 compositor.

### 3.6 Scheduled jobs (already wired)

Retention purge and usage rollup/reconciliation run from Worker `scheduled`; rejection-counter flush and grace reconcile run each cron tick. These are **not** the gap for client inference.

---

## 4. Client → AI Platform request surface

This section inventories every **client-facing** operation the architecture defines, plus the concrete paths the source already uses where they exist. Use this as the contract checklist for a future webservice / API gateway that triggers the same operations.

Architecture states surfaces by **purpose and fields**, not always by URL. Source has encoded some paths under `/v1/...`.

### 4.1 Capability discovery

| Field | Value |
|-------|--------|
| **Purpose** | Fetch active capability manifests for this installation/plan; drive Context Resolver; announce deprecation/retirement |
| **Auth** | Installation-scoped (AAT implied) |
| **Transport** | HTTPS; cacheable; revalidate by version/etag |
| **Request** | Not field-detailed in architecture beyond “fetch active manifests”; etag/conditional GET expected by `buildDiscoveryResponse` |
| **Response** | Active manifests (Identity: id, version, title, lifecycle, successor; Context requirements; Interaction/Output modes; etc.) |
| **Source today** | `capability.discover` / `buildDiscoveryResponse` — **no Worker route** |
| **Suggested future webservice op** | `DiscoverCapabilities` → e.g. `GET /v1/capabilities` (path not fixed by architecture) |

### 4.2 Submit request (primary inference)

| Field | Value |
|-------|--------|
| **Purpose** | Create AI request for a capability; stream provisional output; one terminal outcome |
| **Auth** | Bearer **AAT** (EdDSA JWS; claims §5.6: `iss`, `aud=ai-platform`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`/`exp`, `ver`) |
| **Transport** | HTTPS upstream → **SSE** downstream |
| **Headers (source)** | Required: `x-idempotency-key`, `x-capability-version`; optional: `x-trace-id` |
| **Body (architecture + source)** | Capability id (+ version pin via header); `intent` / `user_intent`; `context`; idempotency key. **Conversational only:** `conversation_id`, `turn_ordinal`, `transcript` |
| **Must not send** | Provider/model/routing hints; `routing_tier` / `degraded` / `degraded_notice`; prompt fragments; capability scopes in body |
| **SSE events** | Always starts with `accepted` `{request_reference}` (optional `degraded_notice`). Content: `text_delta` \| `partial_structured` \| heartbeats. Mid-fallback: `regenerating`. Exactly one terminal: `completed` \| `failed` \| `cancelled` \| `context_requested` (conversational only) |
| **Source today** | `POST /v1/requests` → **503** until event source wired |
| **Suggested future webservice op** | `SubmitCapabilityRequest` → `POST /v1/requests` (SSE) |

### 4.3 Cancel in-flight request

| Field | Value |
|-------|--------|
| **Purpose** | Abort provider fetch; journal `cancelled`; credit partial usage |
| **Mechanism** | **Close the SSE connection** — architecture forbids a separate cancel endpoint |
| **Auth** | Same open authenticated stream |
| **Source today** | Adapter disconnect hooks exist; effective only after event source + invocation abort are wired |
| **Suggested future webservice op** | Not a REST call — `AbortController` / stream close on the submit connection |

### 4.4 Get request

| Field | Value |
|-------|--------|
| **Purpose** | Recover terminal state / validated result after the stream is gone |
| **Auth** | Bearer AAT |
| **Transport** | HTTPS (architecture does not name method; source uses GET) |
| **Request** | Request reference |
| **Response** | Terminal state; result if completed; taxonomy/error fields when failed; awaiting_context / cancelled variants |
| **Source today** | **Implemented:** `GET /v1/requests/{reference}` |
| **Suggested future webservice op** | `GetRequest` → `GET /v1/requests/{reference}` |

### 4.5 Usage summary

| Field | Value |
|-------|--------|
| **Purpose** | Current period consumption and entitlement (in-app quota / future billing UI) |
| **Auth** | Installation-scoped AAT |
| **Transport** | HTTPS |
| **Response** | Live counters (Quota DO) + history (`usage_rollup`) per architecture §7.6 |
| **Source today** | **No client route** (rollup/credit exist internally) |
| **Suggested future webservice op** | `GetUsageSummary` → e.g. `GET /v1/usage` (path not fixed by architecture) |

### 4.6 Not client → AI Platform (do not expose as clinic webservice ops)

| Operation | Owner |
|-----------|--------|
| Support lookup by request reference | Control plane (operator) |
| Enroll / rotate / revoke / suspend / resume / delete / purge | Control plane |
| Entitlement economics assignment | Control plane (**missing**) |
| Kill switches | Control plane (**missing**) |
| Capability deprecate / retire / cohort activate / promote | Control plane |
| Routing policy publish / canary / promote / rollback | Control plane |
| Token contract begin-rotation / retire | Control plane |
| Dashboards | Control plane (**library only**) |
| `issue_ai_token`, context RPCs, `record_ai_acceptance` | **Supabase / clinic**, not AI Platform |
| Health check | Ops (`GET /health` in source) — not a clinic AI capability |

### 4.7 Error taxonomy clients must branch on (§5.4)

Every error carries request reference, trace id, and whether retry is safe. Codes:

`unauthenticated`, `installation_suspended`, `forbidden_capability`, `rate_limited`, `quota_exhausted`, `request_too_large`, `context_required`, `context_invalid`, `conversation_budget_exhausted`, `capability_unknown` / `capability_retired`, `capability_disabled`, `provider_unavailable`, `provider_rejected`, `validation_failed`, `cancelled`, `timeout`, `internal_error`.

Note: `context_requested` is a **terminal SSE event kind**, not an error code.

### 4.8 Future webservice operation checklist (clinic-facing)

Minimal set a clinic-facing webservice would need to trigger:

1. **DiscoverCapabilities**
2. **SubmitCapabilityRequest** (SSE; includes conversational turns on the same op)
3. **CancelByDisconnect** (no HTTP verb — document as stream abort)
4. **GetRequest**
5. **GetUsageSummary**

That is the full client→platform surface defined by the architecture.

---

## 5. Quick status matrix

| Area | Architecture | Source library | Worker / HTTP wiring |
|------|--------------|----------------|----------------------|
| Guard stages 1–10 | Required | Yes (`pipeline`, stages) | Not on POST |
| Provider invoke + fallback | Required | Yes (`invocation`, adapters) | Not on POST |
| Stream brokers | Required | Yes (`stream/*`) | Not on POST |
| Journal + R2 envelope | Required | Yes | GET yes; POST create path unwired |
| Quota DO | Required | Yes | DO RPC yes; POST admission unwired |
| Discovery | Required | Yes | **No** |
| Submit SSE | Required | Adapter yes | **503** |
| Get request | Required | Yes | **Yes** |
| Usage summary | Required | Partial (rollup/QDO) | **No** |
| Entitlement control | Required | Read path yes | **Writer missing** |
| Kill switches | Required | Read stubs | **Persist + control missing** |
| Dashboards | Required | Yes | **No** |
| Installation / routing / token / support control | Required | Yes | **Yes** |
| Telemetry emitter | Required | Tallies only | Partial |
| Provider secrets | Required | Test injection | **Not in wrangler** |

### 5.1 Highest-priority work to unlock E2E

1. Wire `eventSource` on `POST /v1/requests` to guard + real providers + stream brokers + journal/credit.
2. Bind and inject provider secrets.
3. Add entitlement-management control mutation(s) so enrolled installations can become `active` with budgets.
4. Expose discovery and usage-summary HTTP routes.
5. Add kill-switch D1 persistence + control writers (if operational kill is needed before go-live).
