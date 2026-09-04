# AI Platform Behavioral Journey

- Purpose: Walk through the AI platform as it actually behaves in `ai-platform/` today — from first configuration through an installation becoming usable, then through a live request until a terminal response.
- Read this when: you are learning the platform, operating it for the first time, debugging a request, or comparing architecture intent with runtime behavior.
- Canonical for: nothing. This is a **behavioral tour of the current implementation**. Architecture decisions remain in `01-ai-platform.md`. Operator recipes remain in `04-ai-platform-operator-runbook.md`.
- Source of truth for this document: `ai-platform/src/**`, `ai-platform/migrations/**`, `ai-platform/manifests/**`, `ai-platform/wrangler.toml`, and `ai-platform/test/**`. Architecture was used to name intended behavior and to call out where code diverges.
- Not used as structure: `03-ai-platform-delivery-plan.md` (a build-order document, not a runtime story).

---

## Table of Contents

1. [End-to-end behavioral map](#1-end-to-end-behavioral-map)
2. [How to read this tour](#2-how-to-read-this-tour)
3. [The platform comes online](#3-the-platform-comes-online)
4. [Operator authentication](#4-operator-authentication)
5. [Token-contract baseline](#5-token-contract-baseline)
6. [Enroll an installation](#6-enroll-an-installation)
7. [Entitle the installation](#7-entitle-the-installation)
8. [Make routing live](#8-make-routing-live)
9. [Clinic-side trust: minting an AAT](#9-clinic-side-trust-minting-an-aat)
10. [Discovery](#10-discovery)
11. [A request arrives](#11-a-request-arrives)
12. [The guard](#12-the-guard)
13. [Accept, route, invoke, and stream](#13-accept-route-invoke-and-stream)
14. [Terminal emit and settlement](#14-terminal-emit-and-settlement)
15. [Looking a request up later](#15-looking-a-request-up-later)
16. [Housekeeping crons](#16-housekeeping-crons)
17. [Control-plane alternative journeys](#17-control-plane-alternative-journeys)
18. [Conversational and context-negotiation paths](#18-conversational-and-context-negotiation-paths)
19. [Architecture vs implementation](#19-architecture-vs-implementation)

---

## 1. End-to-end behavioral map

Read this once. The rest of the document is this picture, unpacked.

The platform does **not** start at “a Flutter button was pressed.” A request cannot be admitted until several earlier journeys have succeeded. The real starting point is a Worker process with bindings, a migrated D1, and bundled capability artifacts.

```
 CONFIGURE
   wrangler env + secrets + D1/R2/DO/rate-limit bindings
   module boot: load clinic.visit_summary@1.0.0 into the in-memory registry
   D1 migrations: schema + token_contract ver='1' seed
        |
        v
 OPERATE (operator bearer)
   POST /control/installations/{id}/enroll
        → installation(status=active) + installation_key + entitlement(status=pending, quotas=0)
   POST /control/installations/{id}/entitle
        → entitlement(status=active, budgets, allowed_capabilities) + capability_grant rows
   POST /control/routing-policies/publish
        → R2 policy document + routing_policy(status=published); identity from document.policy_id/policy_version
   POST .../canary  and/or  POST .../promote
        → routing_policy(status=canary|active)
          [invoke preload requires this; missing policy → accepted then failed/internal_error]
          [stage 5 may load the same policy only to evaluate provider kill switches]
        |
        v
 CLINIC TRUST (outside the Worker)
   Clinic Postgres mints a short-lived AAT signed with the enrolled private key
        |
        v
 DISCOVER (optional but real)
   GET /v1/capabilities  + Bearer AAT
        → granted active/deprecated manifests (kill switches are NOT applied here)
        |
        v
 INVOKE
   POST /v1/requests
        adapter: size → JSON → required headers
        preAccept = runGuard stages 1–10   ← HTTP JSON error if this fails (no SSE)
        200 text/event-stream
        event: accepted { request_reference, trace_id }
             |
             +-- idempotent replay → stub terminal (does not read R2)
             |
             +-- fresh → preload routing policy → select candidate chain
                       → runInvocation + prose stream broker (concurrent)
                       → provider HTTP (DeepSeek / Gemini) or FakeAdapter
                       → one terminal SSE event
                       → credit Quota DO + write D1 attempts/usage + R2 envelope
```

Two facts that surprise people who come from the architecture document first:

1. **The guard finishes before the client sees `accepted`.** Composition, admission, and the D1 journal insert all happen in `preAccept`. A rejected caller never gets an SSE stream.
2. **Routing is not a guard check.** A request can pass the guard, receive `accepted`, then fail with `internal_error` because no active/canary routing policy exists.

---

## 2. How to read this tour

Each later section is one stage in the journey above. For every stage you should leave knowing:

- what the stage is responsible for
- what enters it, and from where
- what leaves it, and who consumes that
- the happy path and the meaningful invalid / alternative paths
- which `ai-platform/` files implement it
- how to verify it

Error codes named below are the closed taxonomy in `ai-platform/src/errors.ts` unless a control-plane `{ "error": "..." }` body is specified.

The existing gap analysis `arch-vs-source-gap-analysis.md` is **stale**. It claims `POST /v1/requests` always returns 503. The Worker now wires `preAccept` + `eventSource` and runs a live orchestrator. This document supersedes that claim.

---

## 3. The platform comes online

### 3.1 What is happening

Before any clinic exists, the Worker must be a runnable process with Cloudflare bindings, a migrated D1, bundled manifests/prompts, and an in-memory capability registry. This is the actual first step.

The Worker is a **single deployable unit** (`ai-platform-gateway`). There is no second service for inference, journaling, or control. A small stateful sidecar — one Durable Object class, `GatewayObject`, one instance per installation name — holds quota, jti replay, and idempotency.

### 3.2 Inputs

- `ai-platform/wrangler.toml`: named environments `development` / `staging` / `production`, D1 `DB`, R2 `R2`, Durable Object `DO` → `GatewayObject`, three Rate Limiting bindings, crons `0 3 * * *` and `0 4 * * *`.
- Secrets / `.dev.vars` (not declared as wrangler `vars`): `OPERATOR_BEARER_TOKEN`. Live providers also need `DEEPSEEK_API_KEY` / `GEMINI_API_KEY`.
- Plain vars: `BUILD_SHA`, `ENVIRONMENT`, `LOG_VERBOSITY` (`0`/`1`/`2`), `OPERATOR_ID`.
- Migrations under `ai-platform/migrations/`.
- Bundled artifacts: `manifests/published/clinic.visit_summary@1.0.0.json` and `prompts/clinic.visit_summary/*`.

### 3.3 Outputs / state

At module load (`src/worker.ts`):

- `assertRequiredBindings` throws if `DB`, `R2`, or `DO` is missing. The isolate does not serve traffic.
- `setCapabilityRegistry(createCapabilityRegistry([load(visitSummaryPublished)]))` installs the only published product capability. Tests may replace this registry first.
- Prompt artifacts are **not** loaded here. `composeRequest` is dynamically imported on the first live submit.

After D1 migrations (applied by Wrangler/ops, **not** by the Worker at boot):

- Full platform schema (`installation`, `installation_key`, `entitlement`, `capability_grant`, `routing_policy`, `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit`, plus later tables `token_contract`, `kill_switch`, routing canary/status columns, grant lifecycle columns).
- `token_contract` row `ver='1'` is **seeded**. You do not enroll a clinic to create it.
- Empty D1 (migrations not applied) makes every AAT fail identity with `unauthenticated`.

### 3.4 Thorough explanation

Think of boot as creating an empty airport that already knows one flight type (`clinic.visit_summary`) and already has a passport standard (`token_contract.ver=1`), but has no airlines (installations), no tickets (entitlements), and no runway assignment (routing policy).

HTTP routing in `fetch` is a straight if-chain, in this order:

| Method | Path | What happens |
| --- | --- | --- |
| any | `/health` | JSON `{ build, environment }`. No auth. |
| GET | `/v1/capabilities` | Discovery (AAT). |
| POST | `/v1/requests` | Live inference orchestrator. |
| POST | `/control/...` (see §4) | Control plane. |
| GET | `/v1/requests/{reference}` | Journal lookup (AAT). |
| other | anything else | `404 Not Found`. |

`GatewayObject.fetch` is a private RPC surface, not a public URL. The Worker talks to it with `stub.fetch("https://quota-do.internal/rpc")` and `kind` of `admission` | `credit` | `release`.

Scheduled handler (every cron tick): flush in-isolate guard-rejection tallies to `platform_counter`, then reconcile grace admissions. At `0 3 * * *` run retention purge; at `0 4 * * *` run usage rollup + reconciliation.

Logging is human-readable (`[file.ts] [Status] message`), verbosity from `LOG_VERBOSITY`. `trace.ts` also has a JSON-line `createStructuredLogger` used in tests; the live Worker uses `logger.ts`. There is no per-stage span emitter. `BUILD_SHA` in `wrangler.toml` is `"local"` for all named envs until a deploy overwrites it.

### 3.5 Paths / branches

```
Worker isolate starts
  ├─ missing DB/R2/DO  → throw; isolate dead
  ├─ capability JSON invalid → catch; tests may have installed a registry
  ├─ GET /health → 200 {build, environment}
  ├─ known routes → later stages
  └─ unknown → 404
```

Unknown Durable Object `kind` → 400 `{ error: "unknown_kind" }`. Invalid JSON to the DO → 400 `{ error: "invalid_json" }`. Argument validation failures stay 400 so admission maps them to `client_error` rather than grace.

### 3.7 Source files

- `ai-platform/src/worker.ts` — boot, `fetch`, `scheduled`, `GatewayObject`
- `ai-platform/wrangler.toml`
- `ai-platform/src/capability/index.ts` — registry
- `ai-platform/src/manifest/index.ts` — `load()`
- `ai-platform/migrations/20260731120000_platform_schema.sql` and later additive migrations
- `ai-platform/src/logger.ts`

### 3.8 How to test / verify

- `ai-platform/test/health.test.ts`
- `ai-platform/test/worker-entry.test.ts`
- `ai-platform/test/env-deploys.test.ts`
- `ai-platform/test/migrations.test.ts`
- `ai-platform/test/manifest-registry-gate.test.ts` / `prompt-registry-gate.test.ts`
- Manual: Health entity, or `curl http://127.0.0.1:8787/health`

---

## 4. Operator authentication

### 4.1 What is happening

Every control mutation is operator-authenticated. There is no clinic AAT on these routes. The Worker compares `Authorization: Bearer …` to the secret `OPERATOR_BEARER_TOKEN` in constant time and, on match, attributes the action to `OPERATOR_ID` (never to the token string).

### 4.2 Inputs

From stage 3: the secret and `OPERATOR_ID` in the isolate env. From the caller: `Authorization` header.

### 4.3 Outputs

An `OperatorPrincipal { operatorId }` consumed by every `handle*` in `src/control/`. That id is written to `control_audit.operator_id` and to grant `changed_by`.

### 4.4 Thorough explanation

`createSecretOperatorAuth` returns `null` (which becomes HTTP 401 `{ "error": "unauthorized" }`) when:

- the secret or operator id is empty (misconfigured isolate)
- the header is missing, not `Bearer`, or the token is empty
- the token does not match (timing-safe compare)

Control JSON errors are **not** taxonomy bodies. They are `{ "error": "<code>" }` with an HTTP status chosen by the handler (`reject()` in `control/http.ts`).

### 4.5 Paths / branches

```
POST /control/...
  ├─ not a control route pattern → Worker 404
  ├─ auth fail → 401 { error: unauthorized }
  └─ auth ok → dispatch by path
```

### 4.7 Source files

- `ai-platform/src/control/auth.ts`
- `ai-platform/src/control/http.ts` (`requireOperator`)
- `ai-platform/src/control/index.ts` (`isControlRoute`, `dispatchControlRequest`)

### 4.8 How to test / verify

- `ai-platform/test/control.test.ts` (unauthorized / authorized dispatch)
- Manual: any Control entity with a wrong bearer should return 401

---

## 5. Token-contract baseline

### 5.1 What is happening

When an AAT is verified, the platform checks `payload.ver` against the global `token_contract` table. Fresh D1 already contains `ver='1'`. This stage usually requires **no operator action**.

### 5.2 Inputs

Migration seed. Optional later operator calls:

- `POST /control/token-contract/begin-rotation` `{ ver }`
- `POST /control/token-contract/retire` `{ ver }`

### 5.3 Outputs

Accepted `ver` values. Identity verification (stage 12.2 / identity) loads `token_contracts:{ver}`. A retired or missing `ver` is `unauthenticated`.

### 5.4 Thorough explanation

Rotation is an overlap window: begin-rotation inserts a second accepted `ver`. At most **two** non-retired versions may exist (`409 rotation_already_open` if a rotation is already open). Clinics must mint the new `ver` before the old one is retired. Retiring the last remaining accepted version is refused (`409`).

You can enroll and entitle without touching this table. You cannot verify an AAT whose `ver` is not in it.

### 5.5 Paths / branches

```
Identity verify payload.ver
  ├─ row missing → unauthenticated
  ├─ retired_at set → unauthenticated
  └─ accepted → continue
Operator retire
  ├─ last remaining ver → 409
  └─ otherwise → retired_at stamped
```

### 5.7 Source files

- `ai-platform/migrations/20260803120000_token_contract.sql`
- `ai-platform/src/control/token-contract.ts`
- `ai-platform/src/identity/index.ts` (contract row check)
- `ai-platform/src/config-cache/index.ts` (`token_contracts` reader)

### 5.8 How to test / verify

- `ai-platform/test/token-contract-control.test.ts`
- `ai-platform/test/token-contract-rotation.test.ts`
- `ai-platform/test/identity.test.ts`

---

## 6. Enroll an installation

### 6.1 What is happening

Enrollment is the trust bootstrap. The platform records “this clinic exists, and this public key is how we will verify its tokens.” It does **not** grant the right to spend AI.

Architecture §8.1 matches this split: enroll creates trust; a later entitlement mutation creates spend rights. The implementation follows that.

### 6.2 Inputs

- Operator principal (stage 4)
- Path: `POST /control/installations/{installation_id}/enroll`
- Body: `org_id`, `display_name`, `region`, `plan`, `public_key`, `algorithm`, `kid`

The public key is typically Ed25519 raw bytes, base64url-encoded (identity can also import a JWK `{ kty: OKP, crv: Ed25519, x }`). The private key **never** enters the platform; it stays in clinic Postgres (pgsodium / `enroll_installation_keypair`).

### 6.3 Outputs / state consumed later

One D1 batch:

| Table | What is written |
| --- | --- |
| `installation` | `status='active'`, org, display name, region, `enrolled_at` |
| `installation_key` | `kid`, public key, algorithm, `valid_from=now`, `valid_until=NULL`, `revoked_at=NULL` |
| `entitlement` | `status='pending'`, `request_quota=0`, `token_budget=0`, `cost_budget=0`, `allowed_capabilities='[]'`, `soft_threshold=0` (sentinel: never degrades), period start/end = enroll timestamp |
| `control_audit` | `action='enroll'` |

Success body: `{ platform_base_url: <Worker origin> }`.

Identity (later) consumes `installation` + `installation_key`. Entitlement evaluation consumes the entitlement row and will **reject** `pending`. Stage 7 (`entitle`) is therefore mandatory before a useful request.

### 6.4 Thorough explanation

The installation is immediately `active` as a **lifecycle** status. “Active installation” and “AI-enabled entitlement” are different columns. Suspend/delete later change `installation.status`; identity fails closed unless it is exactly `active`.

`soft_threshold=0` at enroll is intentional: a pending row must not degrade-route. Real thresholds arrive in entitle (`0..1`).

The clinic still cannot call the platform: it has no spend rights, no grants, and (usually) no AAT until the clinic DB has stored the keypair and platform URL.

### 6.5 Paths / branches

```
enroll
  ├─ invalid/missing fields → 400 invalid_payload
  ├─ installation_id or org_id already present → 409 already_enrolled
  ├─ duplicate kid (unique) → 409 duplicate_kid
  ├─ D1 error → 500 storage_error
  └─ ok → 200 { platform_base_url }
```

### 6.7 Source files

- `ai-platform/src/control/lifecycle.ts` (`handleEnroll`)
- `ai-platform/src/control/types.ts` (`EnrollPayload`)

### 6.8 How to test / verify

- `ai-platform/test/control.test.ts`
- D1: `SELECT * FROM installation; SELECT * FROM entitlement;`
- Manual: enroll form, then a submit should still fail entitlement (`forbidden_capability`) until stage 7

---

## 7. Entitle the installation

### 7.1 What is happening

This is the mutation that turns “we trust this clinic” into “this clinic may spend AI on these capabilities.” It is a **one-shot** transition: `pending` → `active`. Re-running entitle returns `409 not_pending`.

### 7.2 Inputs

- Enrolled installation + pending entitlement (stage 6)
- `POST /control/installations/{id}/entitle`
- Body: `period_start`, `period_end`, `request_quota` (int ≥ 0), `token_budget` (int ≥ 0), `cost_budget` (finite ≥ 0), `soft_threshold` in `[0,1]`, `allowed_capabilities` (string array), `grants` (non-empty array of `{ capability_id, capability_version, scope?: "installation"|"plan" }`)

### 7.3 Outputs / state consumed later

- `entitlement` updated in place: budgets, period, `allowed_capabilities` JSON, `soft_threshold`, `status='active'`
- One `capability_grant` insert per grant (`scope` is `installation:{id}` or `plan:{plan}`)
- `control_audit` `action='entitle'`

Guard stage 3 (entitlement) and stage 5 (capability resolve) both read `allowed_capabilities` **and** a matching unrevoked grant at installation or plan scope. Discovery uses the same pair. Admission copies the entitlement snapshot into the Quota DO.

### 7.4 Thorough explanation

Three independent gates must all pass at request time:

1. Entitlement row `status === 'active'` (else `forbidden_capability`, path `ai_disabled`)
2. `allowed_capabilities` contains the capability id
3. A grant exists for that id+version at `installation:{id}` or, if missing, `plan:{plan}`

Plan tier is also checked. Worker preAccept currently passes `minimumPlanTier: "standard"` into stage 3, **hardcoded**, while stage 5 also reads `manifest.Access.minimumPlanTier`. The published visit-summary manifest’s minimum is `standard`, so a `starter` plan fails even if entitled. Ops setup seeds `plan: enterprise` to stay above that floor.

Grants without a matching `allowed_capabilities` entry still fail. An allowed capability without a grant still fails. Entitle’s payload must keep them aligned.

Cohort activate/promote (stage 17) can add or move grants later without re-entitling. Entitle itself cannot be used as a “change the budget” API after activation — there is no second entitle.

### 7.5 Paths / branches

```
entitle
  ├─ installation missing → 404 installation_not_found
  ├─ entitlement row missing → 404 entitlement_not_found
  ├─ status !== pending → 409 not_pending
  ├─ invalid numbers / empty grants / bad scope → 400 invalid_payload
  ├─ D1 batch error → 500 storage_error
  └─ ok → 200 { installation_id, status: "active" }
```

Entitle does **not** change `entitlement.plan` (that stays from enroll) and does **not** check installation lifecycle — a deleted installation can still be entitled if the rows exist. Architecture §8.1 said a pending entitlement should look like quota exhaustion; the live path returns **`forbidden_capability`** (`path: ai_disabled`) at stage 3 instead.

### 7.7 Source files

- `ai-platform/src/control/entitle.ts`
- `ai-platform/src/entitlement/index.ts` (runtime evaluation)
- `ai-platform/src/capability/index.ts` (`assertPlanAllowance`, `discover`)

### 7.8 How to test / verify

- `ai-platform/test/entitle-grant.test.ts`
- `ai-platform/test/entitlement.test.ts`
- Manual: entitle once, entitle again → 409; discovery should now list visit summary

---

## 8. Make routing live

### 8.1 What is happening

Inference needs an **active or canary** routing policy document. The visit-summary manifest points at `routing/standard@v1`. Publish writes the document; it is not used until canary (installation-scoped) or promote (global `status='active'`).

Missing routing does **not** fail the guard. After `accepted`, `preloadRoutingPolicyForInstallation` throws and the stream ends `failed` / `internal_error`. Stage 5 *does* try to load the same policy so it can evaluate **provider kill switches**; if the policy is missing that load is a miss (empty provider list), not a rejection. Promote has **no status pre-check** — publish → promote without canary is allowed.

### 8.2 Inputs

- Entitled installation (so a request can reach this far)
- `POST /control/routing-policies/publish` with `{ document }`
- Then `.../canary` with `{ installation_ids: [...] }` and/or `.../promote`

The JSON document must include `schema_version: 1`, well-formed `policy_id` / `policy_version` (they define the published identity — R2 key and D1 PK derive from them), a catch-all rule, and `targets[]` with `provider_id`, `model_id`, `features`, `max_attempts`, `timeout_ms`.

Wired provider ids in code: `deepseek`, `gemini`. `fake` is resolved in the Worker without being in `createProviderAdapter`. Unknown ids become a FakeAdapter that immediately returns `provider_unavailable`.

### 8.3 Outputs / state consumed later

- R2 object `control/routing-policy/{policyId}/{version}.json`
- `routing_policy` row: `published` → `canary` (with `canary_installation_ids`) → `active`
- `selectCandidateChain` in the live event source

Config-cache reader `active_routing_policy`:

1. If an installation id is in the cache key, prefer a `status='canary'` row whose `canary_installation_ids` contains that installation
2. Else the latest `status='active'` row for that `policy_id`
3. Miss → `ConfigCacheMissError`

### 8.4 Thorough explanation

A first-time operator who enrolls + entitles + submits will see:

1. HTTP 200, SSE `accepted` (guard does not require a routing policy; a miss at stage 5 is fail-open for kill-switch lookup)
2. SSE `failed` with `internal_error` (invoke-time preload throws, caught in `createProductionEventSource`)

That is why Setup inserts routing **before** “clinic closeout & play.”

Target filtering drops providers for feature mismatch, context window, language, cost class, installation override, or kill-switch (see §19 for the kill-switch caveat). An empty chain becomes `provider_unavailable` inside `runInvocation`.

### 8.5 Paths / branches

```
publish
  ├─ missing R2 binding → 500 missing_r2_binding
  ├─ missing document → 400 missing_document
  └─ ok → status=published (not yet selectable)

canary
  ├─ listed installation does not exist → 404 installation_not_found
  └─ ok → that installation’s preload hits this version

promote
  └─ this version becomes the global active policy

rollback
  └─ previous active restored (dangerous)

live preload miss → accepted then failed/internal_error
empty chain after filters → invocation provider_unavailable
unknown provider_id → FakeAdapter terminal provider_unavailable
```

### 8.7 Source files

- `ai-platform/src/control/routing-policy.ts`
- `ai-platform/src/router/index.ts`
- `ai-platform/src/config-cache/index.ts` (`active_routing_policy`)
- `ai-platform/src/provider/wiring.ts`

### 8.8 How to test / verify

- `ai-platform/test/routing-policy-canary.test.ts`
- `ai-platform/test/router.test.ts`
- `ai-platform/test/second-provider-policy.test.ts`
- Manual: submit without promote → `accepted` + `failed`/`internal_error`; promote then submit again

---

## 9. Clinic-side trust: minting an AAT

### 9.1 What is happening

The platform never sees a Supabase session JWT. The clinic database mints an **AI Access Token** (EdDSA JWS) with the enrolled private key. This step lives in clinic Postgres + Flutter / ops bootstrap, not in `ai-platform/src`. It is still a required predecessor of discovery and submit.

### 9.2 Inputs

- Enrolled public key on the platform (stage 6)
- Matching private key in clinic DB
- A clinic user session that the `SECURITY DEFINER` RPC `issue_ai_token` is willing to sign for

### 9.3 Outputs consumed later

A compact JWS. Identity expects:

- Header: `alg=EdDSA`, `kid` matching `installation_key.key_id`
- Payload strings: `iss` (installation id), `aud` (`ai-platform`), `sub` (actor), `org`, `branch`, `role`, `jti`, `ver` (token-contract version, usually `"1"`)
- `scopes`: string array (parsed onto `Principal`, **not currently used as a gate** — see §19)
- `iat`, `exp`: NumericDate seconds

### 9.4 Thorough explanation

The Worker verifies the signature against the enrolled public key, then trusts the claims. Context in the request body is never trusted as identity. `iss` must own the `kid`. Installation status must be `active` (suspended is a distinct 403).

Clinic minting is implemented outside this package (`public.issue_ai_token` in Supabase; Flutter `supabase_aat_mint_port.dart` / `ai_client_sdk.dart`).

Ops bootstrap tries to mint via `public.issue_ai_token` as `admin`/`admin` against local Supabase. If clinic org/branch/keypair are missing, bootstrap records an error and you paste an AAT by hand.

### 9.5 Paths / branches

Outside the Worker: mint RPC can refuse by RBAC. Inside the Worker, every malformed/expired/wrong-aud/wrong-kid token is `unauthenticated` (401). Suspended installation is `installation_suspended` (403).

### 9.7 Source files

- `ai-platform/src/identity/index.ts` (`EnrolledKeyVerifier`)
- Clinic Supabase RPCs (outside this package)

### 9.8 How to test / verify

- `ai-platform/test/identity.test.ts`
- Manual: Decode AAT, then Health vs Discovery (discovery requires a valid signature)

---

## 10. Discovery

### 10.1 What is happening

`GET /v1/capabilities` tells the client which capabilities this installation may invoke, with the public contract (context keys, output mode, acceptance mode) and **without** prompt text or provider names.

### 10.2 Inputs

- Bearer AAT (stage 9)
- Optional `If-None-Match` for 304
- Registry + entitlement + grants (stages 3, 6, 7)

### 10.3 Outputs

HTTP 200 with an ETag and a filtered manifest list, or 304, or taxonomy 401/403. An entitled-but-empty allow-list yields `[]`, not an error.

Kill switches are **intentionally not applied** in discovery: advertising a killed capability is considered correct so the client can show “temporarily unavailable” rather than pretend the feature does not exist. Invoke-time stage 3/5 still reject it.

### 10.4 Thorough explanation

Handler: verify AAT → `discover(principal)` → `buildDiscoveryResponse`.

`discover` returns no manifests when entitlement is missing or not `active`, plan is invalid, the capability is not in `allowed_capabilities`, plan tier is too low, grant is missing/revoked/version-mismatched, or lifecycle overlay is `retired`. Deprecated capabilities can still appear (with successor metadata) so clients can migrate.

### 10.5 Paths / branches

```
GET /v1/capabilities
  ├─ no/empty Bearer → 401 unauthenticated
  ├─ verify fail → 401 or 403 installation_suspended
  ├─ If-None-Match matches → 304
  └─ 200 manifests + ETag
```

### 10.7 Source files

- `ai-platform/src/discovery/index.ts`
- `ai-platform/src/capability/index.ts` (`discover`, `buildDiscoveryResponse`)

### 10.8 How to test / verify

- `ai-platform/test/discovery-http.test.ts`
- `ai-platform/test/capability.test.ts`
- Manual: Discovery before entitle → `[]`; after entitle → visit summary

---

## 11. A request arrives

### 11.1 What is happening

`POST /v1/requests` is the only inference ingress. `handleLivePostRequest` injects production `preAccept` (the guard) and `eventSource` (invoke + stream). The protocol adapter owns transport: size, JSON, headers, SSE framing, disconnect.

### 11.2 Inputs

Headers (all required except trace):

| Header | Role |
| --- | --- |
| `Authorization: Bearer <AAT>` | extracted for the guard; adapter itself does not verify |
| `x-idempotency-key` | admission + replay |
| `x-capability-version` | registry key together with body capability id |
| `x-trace-id` | optional; empty string is invalid; absent → Worker generates a ULID |

Body (JSON object), typical wire fields:

- `capability_id` or `capability` — **required** in production preAccept; missing → `internal_error`
- `user_intent` or `intent`
- `context` object
- optional `conversation_id` / `conversationId`, `turn_ordinal` / `turnOrdinal`, `transcript`

Body size cap: **1 MiB** (`INGRESS_BODY_SIZE_LIMIT`). `Content-Length` over the cap is rejected without reading; otherwise the stream is aborted at the first overflowing chunk.

The client **cannot** set routing tier. `ADAPTER_ROUTING_BODY_FIELDS` is empty; `routing_tier` / `degraded` / `degraded_notice` on the body are ignored (and must not be trusted).

### 11.3 Outputs

- Before accept: HTTP JSON taxonomy error (no SSE)
- After accept: `200 text/event-stream` starting with `event: accepted`
- `request_reference` is generated here (`XXXX-XXXX` Crockford base32). The client does not supply it.

### 11.4 Thorough explanation

Adapter order:

1. Read body within 1 MiB → `request_too_large` (413) or bare 422 on read error
2. Parse JSON object → bare 422 (not a taxonomy body; architecture §5.4 has no “bad json” code)
3. Required headers → bare 422
4. `preAccept` (full guard) → taxonomy JSON at `liveHttpStatusForCode`
5. Open SSE, enqueue `accepted`, start `eventSource`
6. Client abort → notify broker `disconnect('client_close')`; no `cancelled` event if the client is already gone

`accepted.data` may include `degraded_notice: true`, but production `handleLivePostRequest` **never passes** `degradedNotice` into the adapter. Soft-threshold degraded admission is journaled on the request row, not signalled on the wire today.

### 11.5 Paths / branches

```
POST /v1/requests
  ├─ body > 1 MiB → 413 request_too_large (empty reference/trace by design)
  ├─ not JSON object / bad headers / empty x-trace-id → 422 empty body
  ├─ preAccept fail → HTTP JSON taxonomy (401/403/404/413/422/429/503/500)
  ├─ no eventSource (library-only call) → 503 "event source required"
  └─ 200 SSE accepted → stage 13
```

### 11.7 Source files

- `ai-platform/src/adapter.ts`
- `ai-platform/src/worker.ts` (`handleLivePostRequest`, extractors)
- `ai-platform/src/reference.ts`, `src/trace.ts`, `src/errors.ts`

### 11.8 How to test / verify

- `ai-platform/test/adapter.test.ts`
- `ai-platform/test/error-body.test.ts`
- `ai-platform/test/worker-request-orchestrator.test.ts`
- Manual: Submit with missing `x-idempotency-key` → 422; oversized body → 413

---

## 12. The guard

This is architecture §6.1 stages 1–10, implemented as `runGuard` in `src/pipeline/index.ts`, called from `createProductionPreAccept`. **Cheapest rejection first.** On failure the client never sees SSE.

Production always supplies a token + `EnrolledKeyVerifier` (no harness principal skip).

Hardcoded in the Worker (behavioral, not a comment):

```
entitlement: {
  capabilityId,              // from body
  capabilityVersion,         // from x-capability-version
  minimumPlanTier: "standard",
  providerId: "fake",        // kill-switch provider key is therefore "fake"
}
```

Prompt artifact byte length is omitted (`0`), so stage 7 prices context+intent (+transcript) only.

```
preAccept
  ├─ no capability_id → internal_error
  └─ runGuard
        1 ingress
        2 identity
        3 entitlement
        4 rate limit
        5 capability resolve
        6 context validate
        7 cost pre-flight
        8 admission (Quota DO)
           ├─ idempotent → skip 9–10, stash priorState
           ├─ admitted | grace_admitted → 9 journal, 10 compose
           └─ fail
        9 journal insert (state=Accepted)
       10 compose canonical request
```

---

### 12.1 Stage 1 — Ingress shape

**Responsibility.** Bound size and require a JSON object. The adapter already did this; the pipeline repeats it so `runGuard` is testable without HTTP.

**Inputs.** Raw `bodyText`. **Outputs.** Parsed body, or fail.

| Cause | Code | Journal? | Quota? |
| --- | --- | --- | --- |
| UTF-8 bytes > 1 MiB | `request_too_large` | no | no |
| not a JSON object | `internal_error` | no | no |

Wire intent/context/conversation fields are extracted here for later stages.

**Files:** `pipeline/index.ts`, `adapter.ts` `parseAdapterRequestBody`. **Tests:** `pipeline.test.ts`, `adapter.test.ts`.

---

### 12.2 Stage 2 — Identity

**Responsibility.** Prove the AAT is a signed, unexpired, audience-correct token for an **active** installation, using an enrolled key and an accepted token-contract version.

**Inputs.** Bearer token; `ConfigCache` + D1 reader (installations, keys, token_contracts). **Outputs.** Frozen `Principal`, or fail.

Verification order (cheap claims before D1):

1. Three JWS segments, `alg=EdDSA`, non-empty `kid`
2. Required payload fields present
3. `aud === "ai-platform"` (default)
4. `iat`/`exp` within 60s skew
5. Load installation `iss`; miss → `unauthenticated`
6. Load key `kid`; revoked, outside `valid_from`/`valid_until`, or `installation_id !== iss` → `unauthenticated`
7. Ed25519 verify over `header.payload`
8. `installation.status === "suspended"` → `installation_suspended`; any other non-`active` (including `deleted`) → `unauthenticated`
9. Token contract `ver` accepted and not retired

Failures before signature verification tally as installation `"unverified"` in guard-rejection counters.

**Files:** `identity/index.ts`, `config-cache/index.ts`. **Tests:** `identity.test.ts`. **Ops:** wrong AAT on Submit or Discovery.

---

### 12.3 Stage 3 — Entitlement

**Responsibility.** Is this installation AI-enabled for this capability, this version, this plan tier? Are kill switches off?

**Inputs.** Principal; Worker entitlement context; D1 entitlements/grants/`kill_switch`. **Outputs.** Pass, or `forbidden_capability` / `capability_disabled`.

Evaluation:

1. Entitlement status must be `active` (pending from enroll fails here)
2. Plan must meet `minimumPlanTier` (`starter < standard < professional < enterprise`; unknown plan fails closed)
3. `allowed_capabilities` must include the capability id
4. Grant at `installation:{id}/{capabilityId}` or `plan:{plan}/{capabilityId}`, matching version, not revoked
5. Kill switches: `global`, `capability:{id}`, `installation:{id}`, `provider:{providerId}` — miss means inactive (fail-open). Explicit `{ active: true }` fails closed as `capability_disabled`

There is **no control-plane HTTP writer** for `kill_switch`. The table and readers exist; operators must insert D1 rows directly.

Provider kill switches at **this** stage use the hardcoded `providerId: "fake"`. A `provider:deepseek` row does **not** trip stage 3. Stage 5 (`isCapabilityDisabled`) loads the live routing policy and checks `provider:{id}` for every target in that document — so a DeepSeek kill switch can still reject **before** SSE if a policy is already active.

Architecture listed `installation_suspended` at stage 3; the code only emits it at stage 2.

**Files:** `entitlement/index.ts`, `migrations/20260807120000_kill_switch.sql`. **Tests:** `entitlement.test.ts`. **Ops:** submit after enroll but before entitle → 403 `forbidden_capability`.

---

### 12.4 Stage 4 — Rate limit

**Responsibility.** Burst control on three Cloudflare Rate Limiting keys. First failure wins.

| Binding | Key | Dev/staging/prod default |
| --- | --- | --- |
| `RATE_LIMITER_INSTALLATION` | `installationId` | 600 / 60s |
| `RATE_LIMITER_INSTALLATION_ACTOR` | `installationId:actorId` | 120 / 60s |
| `RATE_LIMITER_INSTALLATION_CAPABILITY` | `installationId:capabilityId` | 300 / 60s |

Missing bindings fall back to allow-all. Failure: `rate_limited` (429). Internally `retryAfter` is a constant 60s. `errors.ts` can attach `retry_after` via `supplementaryFieldsForCode`, but **`preAcceptFailureResponse` does not call it** — the live HTTP JSON body has only the core taxonomy fields.

Rejections are tallied in-isolate and flushed to `platform_counter` on cron (and some test paths).

**Files:** `rate-limit/index.ts`. **Tests:** `rate-limit.test.ts`.

---

### 12.5 Stage 5 — Capability resolve

**Responsibility.** Bind the request to an immutable bundled manifest, overlay D1 lifecycle (deprecate/retire), re-check plan allowance, apply capability kill-switch flag.

**Inputs.** `capabilityId` + `x-capability-version`; in-memory registry; grant overlay `global/{id}/{version}`. **Outputs.** `Manifest`, or:

| Cause | Code |
| --- | --- |
| not in registry | `capability_unknown` (404) |
| effective lifecycle `retired` | `capability_retired` (404) |
| plan/allow-list/grant fail | `forbidden_capability` (403) |
| capability kill / manifest flag | `capability_disabled` (503) |

Only `clinic.visit_summary@1.0.0` is published. A conversational capability exists in eval fixtures, not in `manifests/published/`.

Token `scopes` / `requiredCapabilityScope` are **not consulted**. A token without `ai.visit_summary` still passes if entitlement+grant say so.

`isCapabilityDisabled` also loads `active_routing_policy` (canary then global) and treats an active kill switch on any listed provider as `capability_disabled`. Policy miss → no provider keys checked (fail-open for this sub-check). That load uses the **preAccept** `ConfigCache`; `runFreshEventSource` later creates a **new** cache, so stage-5 loads are not reused at invoke.

**Files:** `capability/index.ts`, `manifest/index.ts`. **Tests:** `capability.test.ts`, `capability-deprecation.test.ts`. **Ops:** wrong capability id → 404; retire then submit → 404 `capability_retired`.

---

### 12.6 Stage 6 — Context validate

**Responsibility.** Treat body `context` as untrusted. Keep only keys the manifest declared; require required keys; check published shapes and size; freeze the filtered object.

For `interactionMode === "conversational"` **and** a numeric `turn_ordinal`, extra transcript rules apply. Visit summary is `single_shot`, so production traffic takes the single-shot path.

Single-shot:

- Missing required key → `context_required` (422 HTTP JSON, **not** SSE `context_requested`). `buildContextRequiredResponse` can add `missing_keys`, `shapes`, `manifest_version`, `manifest_capability_id`, but the live adapter uses `buildErrorBody` only — the client does **not** receive those extra fields on POST.
- Bad shape/size/tenant → `context_invalid`
- Undeclared keys are **dropped**, not rejected
- Platform vocabulary defects (malformed/unknown key in the manifest itself) → `internal_error`

Conversational (library; no published cap): omitted transcript → `context_invalid`; budgets exceeded → `conversation_budget_exhausted`; permitted-key allowlist drop.

**Files:** `context/validator.ts`, `context/index.ts`, `context/context-request.ts`; shape artifact `context/shapes/published/visit.chief_complaint@v1.json`. **Tests:** `context.test.ts`, `context-validator.test.ts`, `transcript-validation.test.ts`. **Ops:** Submit visit summary without `visit.chief_complaint@v1` → 422 `context_required`.

---

### 12.7 Stage 7 — Cost pre-flight

**Responsibility.** Refuse oversized prompts before a paid call. Byte estimate: `ceil(utf8(context+intent[+transcript] + promptArtifactBytes) / 4) * 1.15`. Production passes `promptArtifactByteLength = 0`.

Reject `request_too_large` when estimated input > `maxInputTokens`, or estimated input + `maxOutputTokens` > `perRequestCostCeiling`. Non-numeric Economics fail closed.

Visit summary ceilings: 8000 input, 1024 output, 9024 combined.

**Files:** `context/preflight.ts`. **Tests:** pipeline / context tests covering preflight. **Ops:** enormous `user_intent` / context → 413.

---

### 12.8 Stage 8 — Admission (Quota Durable Object)

**Responsibility.** One serialized round trip per installation answering four questions: jti freshness, idempotency, remaining budget, concurrency headroom (`CONCURRENCY_LIMIT = 16`). Also evaluates soft-threshold.

**Inputs.** Principal (`jti`, `exp`, installation), idempotency key, request reference, entitlement snapshot from D1. **Outputs.**

| Outcome | Next |
| --- | --- |
| `admitted` | new `requestId`; optional `degraded: true` if usage ≥ `soft_threshold` of any budget |
| `grace_admitted` | Quota DO unreachable; in-isolate cap 5 per installation; Worker-local UUID; journal `routing_tier=degraded` |
| `idempotent` | skip stages 9–10; replay from `priorState` |
| fail `unauthenticated` | expired token (defensive recheck) or **jti replay** |
| fail `quota_exhausted` | over request/token/cost budget **or** concurrency exhausted (mapped onto the same code) **or** grace cap exceeded **or** entitlement row missing |
| fail `internal_error` | DO 4xx / unexpected body |

Jti replay is returned as `unauthenticated`, not a dedicated code. The client is told to re-mint.

Idempotency prior states: `admitted` | `in_progress` | `completed` | `failed` | `cancelled` | `awaiting_context`. Ephemeral horizon: 2 hours.

Grace admissions are queued in **isolate memory** and reconciled on cron via `reconcileGraceUsage`. They are not durable across isolate eviction.

`quota_exhausted` can carry `period_reset` from the entitlement snapshot, but like `retry_after` it is **omitted** from the live preAccept JSON body.

**Files:** `admission/index.ts`, `quota-do/index.ts`, `soft-threshold/index.ts`, `worker.ts` `GatewayObject`. **Tests:** `admission-credit.test.ts`, `quota-do.test.ts`, `soft-threshold-routing.test.ts`.

---

### 12.9 Stage 9 — Journal the request

**Responsibility.** Insert `ai_request` with `state='Accepted'` **before** any provider work. This is the durability point: a user-visible request cannot vanish.

Columns include capability, actor, branch, idempotency key, trace, `routing_tier` (`standard` or `degraded` from admission/grace), conversation grouping.

Single-shot **forces** `conversation_id` and `turn_ordinal` to NULL. Conversational requires both or returns `context_invalid` (after admission!). On that failure, and on D1 insert failure, the Worker **releases** the Quota DO reservation.

Success consumers: stage 13 (requestId, manifest, composed request, principal) and GET/support lookup.

**Files:** `journal/index.ts` `createRequestRow`. **Tests:** `journal.test.ts`, `conversational-journaling.test.ts`.

---

### 12.10 Stage 10 — Prompt composition

**Responsibility.** Build a provider-independent `CanonicalRequest` from bundled prompt artifacts + filtered context + intent (+ transcript). No model names, no provider field names (`assertNoProviderShapedFieldNames`).

Loads `prompt/composer` dynamically. Failure: `internal_error`. Unlike stage 9, compose failure **records terminal `Failed`** and does **not** call release — in-flight quota can remain until the DO ephemeral sweep.

**Files:** `prompt/composer.ts`, `prompt/registry.ts`. **Tests:** `prompt-composer.test.ts`, `prompt-registry.test.ts`, `prompt-journal-seam.test.ts`. **Ops:** `debug.compose` runs composer locally without HTTP.

---

### 12.11 Guard failure vs success — what the client sees

Guard failure → adapter `preAcceptFailureResponse`: JSON taxonomy body (`code`, `request_reference`, `trace_id`, `retry_safe`), HTTP status from the table in `errors.ts`. No `accepted` event. No `retry_after` / `period_reset` / `missing_keys`. No journal row except the stage-9/10 cases above. `cancelled` has no HTTP mapping (`liveHttpStatusForCode` returns null); it is SSE-only after accept.

Guard success → `acceptContexts` map (request-scoped, not global) keyed by `request_reference`, then SSE `accepted`.

**Ops:** `clinic.submit` shows either JSON error status or an SSE dump. **Tests:** `pipeline.test.ts` covers stage-by-stage codes; `worker-request-orchestrator.test.ts` covers live composition.

---

## 13. Accept, route, invoke, and stream

### 13.1 What is happening

After `accepted`, `createProductionEventSource` runs. Fresh and idempotent paths diverge immediately.

Architecture stages 11–14 live here. Production **always** uses the **prose** stream broker (`createStreamBroker`), not `createStructuredStreamBroker`, even though structured validation/repair exist as libraries. That matches the only published capability (`Output.mode: "prose"`).

### 13.2 Inputs

From the guard: `GuardFreshSuccess` (principal, manifest, filtered context, composed canonical request, requestId, …) or `GuardIdempotentSuccess` (priorState). From control plane: routing policy document. From env: provider secrets.

### 13.3 Outputs

SSE events after `accepted`, then exactly one terminal event: `completed` | `failed` | `cancelled` | (`context_requested` exists in the adapter but is not emitted by the production broker).

### 13.4 Thorough explanation

#### 13.4.1 Idempotent replay

`replayIdempotentTerminal` does **not** load the R2 envelope.

| priorState | Wire result |
| --- | --- |
| `completed` / `admitted` / `in_progress` | `completed` with stub text `"Prior request completed."` |
| `failed` | `failed` / `internal_error` |
| `cancelled` | `cancelled` |
| other | `failed` / `internal_error` |

A client retrying with the same idempotency key therefore does **not** receive the original validated payload on the live stream. `GET /v1/requests/{reference}` is the path that can return the stored result once stage 16 has written R2.

#### 13.4.2 Fresh path

`runFreshEventSource` is scheduled with `executionCtx.waitUntil` so the Worker can keep working after headers are sent.

1. **Preload** `routing/standard@v1/{installationId}` (canary then active). Throw → `failed`/`internal_error`.
2. **Select chain** with **hardcoded** `routingTier: "standard"` (admission’s degraded flag is ignored here), `entitlementMaxCostClass: "premium"`, `manifestCostClass: "standard"`.
3. Start prose broker and `runInvocation` concurrently. Invocation pushes `text` / `regenerating` events into a pushable iterable the broker reads.
4. Heartbeats every 15s of silence (`heartbeat` SSE).
5. Each content chunk is SSE `text_delta` with `{ text, sequence, provisional: true }`. A `regenerating` event resets the assembled buffer on retry/fallback after a partial stream.
6. Incremental prose guards: max length 128_000, stop sequence `<|end|>`, system-prompt leak needle `SYSTEM_PROMPT_LEAK_TEST_NEEDLE`. Violation → `failed`/`validation_failed`. Empty assembled text also fails validation.
7. The broker will fail truncated streams if `chunkSource.wasTruncated()` is true; the production chunk-source adapter **does not implement** `wasTruncated`, so that branch is unreachable on the live path.
8. Client abort → broker `cancelled`; partial usage credited if known. If the client already dropped the connection, no `cancelled` event is written on the wire.

`runInvocation`:

- Empty chain → `provider_unavailable`
- For each target, up to `max_attempts`, each raced against `timeout_ms` and caller abort
- Retryable taxonomy (`provider_unavailable`, `timeout`, …) → jittered backoff then retry; after target exhausted, fallback to next chain entry (`regenerating` if the previous target streamed)
- Terminal taxonomy (`provider_rejected`, `validation_failed`, …) → stop, no fallback
- Production `sleeper` is `async () => {}` — **retries happen with zero delay**

`resolveProviderPort`:

| `provider_id` | Adapter |
| --- | --- |
| `fake` | `FakeAdapter(["success"])` → text `"Fake adapter summary."` |
| `deepseek` | `DeepSeekAdapter` → `POST https://api.deepseek.com/chat/completions` |
| `gemini` | `GeminiAdapter` → `https://generativelanguage.googleapis.com/v1beta/models/...` |
| other | `FakeAdapter(["terminal:provider_unavailable"])` |

Missing `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` → `provider_rejected` (`missing_api_key`), which is **terminal** (no fallback to the other provider).

Canonical messages are mapped to OpenAI-style chat (DeepSeek) or Gemini `contents` + `systemInstruction`. Streaming chunks become `text_delta`; the prose broker assembles text and the `completed` event carries `{ finalContent: { text, authoritative: true } }`. Stage 16’s R2 envelope stores the full `CanonicalResult` from `runInvocation`. GET therefore can return a richer `result` object than the SSE terminal. Clients must still treat the SSE terminal payload as authoritative for the live stream, not the deltas.

### 13.5 Paths / branches

```
eventSource
  ├─ missing accept context → failed/internal_error
  ├─ idempotent → stub terminal (table above)
  └─ fresh
        ├─ routing preload miss → failed/internal_error
        ├─ empty chain → failed/provider_unavailable
        ├─ missing provider key → failed/provider_rejected (no fallback)
        ├─ retryable errors → retry same target, then fallback
        ├─ timeout → timeout error; fallback if chain remains
        ├─ caller abort → cancelled (+ partial credit)
        ├─ prose guard trip → failed/validation_failed
        ├─ FakeAdapter success → completed "Fake adapter summary."
        └─ live provider success → completed assembled text
```

External services contacted: DeepSeek and/or Gemini only when those ids appear in the selected chain **and** secrets exist. FakeAdapter contacts nobody. D1 and the Quota DO are platform-internal.

### 13.7 Source files

- `ai-platform/src/worker.ts` (`createProductionEventSource`, `runFreshEventSource`, `resolveProviderPort`)
- `ai-platform/src/invocation/index.ts`
- `ai-platform/src/router/index.ts`
- `ai-platform/src/stream/index.ts`, `stream/prose-guards.ts`, `stream/structured.ts` (unwired in Worker)
- `ai-platform/src/provider/{port,wiring,fake,deepseek,gemini,classify}.ts`
- `ai-platform/src/contracts/canonical.ts`

### 13.8 How to test / verify

- `invocation.test.ts`, `router.test.ts`, `provider-port.test.ts`
- `deepseek-adapter.test.ts`, `gemini-adapter.test.ts`
- `stream-broker.test.ts`, `structured-modes.test.ts`
- `soft-threshold-routing.test.ts` (library; production routing tier still hardcoded)
- `test/eval/live-smoke.test.ts`, `golden.test.ts`
- Manual: point routing at `fake` for a no-network completed event; point at `deepseek` without a key → `provider_rejected`

---

## 14. Terminal emit and settlement

### 14.1 What is happening

Architecture stages 15–16: record terminal journal state, credit the Quota DO, persist attempt rows + usage ledger + one R2 envelope. Settlement must not take away a terminal event the client already received.

### 14.2 Inputs

Invocation result and attempt records; broker terminal (`completed`/`cancelled`/`failed`); partial usage accessor.

### 14.3 Outputs / state

- `ai_request.state` updated to `Completed` | `Failed` | `Cancelled` with `completed_at` (and `terminal_error_code` on Failed)
- Quota DO: `credit` decrements in-flight, adds tokens/cost/requests; `release` on some cancel/fail paths
- `ai_attempt` rows, `usage_event` row, R2 `request/{requestId}/envelope`, `payload_pointer` on the request

Production settlement cost is hardcoded `0.001` on the completed path (`settleCompletedRequest`), not a real price table. Invocation attempt `cost` is `0`.

### 14.4 Thorough explanation

The prose broker’s `journalTerminalSink` writes Completed/Cancelled/Failed as soon as it emits a terminal SSE event. The Worker then:

- **Invocation cancelled:** if the broker already journaled, stop; else partial credit + `Cancelled`
- **Invocation failed:** set `ignoreBrokerSettlement` so a disconnect-induced broker `cancelled` is not forwarded; push `failed` with the taxonomy code; journal `Failed`. This path does **not** call `creditUsage` or `releaseRPC`, so the Quota DO `inFlight` slot can remain until the 2-hour ephemeral sweep.
- **Invocation ok and broker `completed`:** `creditUsage` (full) + `writePostResponseDetail` (waitUntil; failures are logged, not raised to the client)
- **Broker non-completed** after successful invoke (guard trip, cancel): return without `settleCompletedRequest`

Stage 16 is defined to never fail the request. `writePostResponseDetail` swallows errors. A Completed GET can therefore return `resultMissing: true` if R2/D1 detail never landed.

`pipeline.settleHappyPath` is a **load-test helper** that invokes FakeAdapter itself. Production does not use it.

### 14.5 Paths / branches

```
terminal
  ├─ completed → credit full + R2 envelope (best-effort)
  ├─ cancelled → partial credit if usage known
  ├─ failed → journal Failed; in-flight quota slot may leak until DO sweep
  └─ stage-16 error → log only; SSE already closed
```

### 14.7 Source files

- `ai-platform/src/journal/index.ts` (`recordTerminalState`, `writePostResponseDetail`)
- `ai-platform/src/credit/index.ts`
- `ai-platform/src/quota-do/index.ts` (`creditRPC`, `releaseRPC`)

### 14.8 How to test / verify

- `journal.test.ts`, `admission-credit.test.ts`
- `load/happy-path.ts` (FakeAdapter settle)
- Manual: GET the reference; D1 `SELECT state, payload_pointer FROM ai_request`

---

## 15. Looking a request up later

### 15.1 What is happening

Two read paths exist: clinic GET (AAT, own installation only) and operator support lookup (bearer, any installation).

### 15.2 Inputs

- `GET /v1/requests/{reference}` + AAT
- `POST /control/support/lookup?reference=` + operator bearer

References are normalized (uppercase, I/L→1, O→0) to Crockford `XXXX-XXXX`.

### 15.3 Outputs

Clinic GET:

| Journal state | Body |
| --- | --- |
| `Completed` + envelope | `{ state, result }` |
| `Completed` without envelope | `{ state: "Completed" }` (result omitted) |
| `Failed` | `{ state, terminal_error_code }` |
| `AwaitingContext` | `{ state: "AwaitingContext" }` |
| `Cancelled` | `{ state: "Cancelled" }` |
| other (Accepted, …) | `{ state, pending: true }` |
| missing or other installation | `404` empty |

Wrong/missing AAT: 401, or 403 for suspended. Empty path after `/v1/requests/` → 404.

Support lookup: `{ request, attempts, envelope }` or 404 `not_found`. Missing R2 binding → 500.

### 15.4 Thorough explanation

GET is scoped by `auth.principal.installationId`. During flight the row stays `Accepted`, so GET returns `{ state: "Accepted", pending: true }` until a terminal write. Support lookup is the operator audit trace (architecture §8.9) and may include payload bytes from R2 when still inside the capability’s diagnostic retention horizon.

Dashboards (`src/dashboards/index.ts`) are query helpers with **no HTTP route**. There is no `/v1/usage` summary for the client.

### 15.6 Source files / tests

- `journal/index.ts` (`getRequest`, `authenticateGetRequest`)
- `support/index.ts`, `control/support-purge.ts`
- Tests: `journal.test.ts`, `support-lookup.test.ts`, `journal-dashboards.test.ts`

---

## 16. Housekeeping crons

### 16.1 What is happening

Every scheduled tick: flush rejection counters; reconcile grace admissions.

- `0 3 * * *` — retention purge (D1 rows + R2 envelopes by capability `retentionClass`, e.g. visit summary `diagnostic_30d`; journal horizon 90d; ledger 2555d)
- `0 4 * * *` — usage rollup + reconciliation report (missing attempts / missing credits)

### 16.2 Inputs / outputs

D1/R2/DO as above. Operators can also `POST /control/installations/{id}/purge` (dangerous) to purge one installation immediately.

### 16.4 Source files

- `worker.ts` `scheduled`
- `retention/index.ts`, `rollup/index.ts`, `credit/index.ts` (`reconcileGraceUsage`)

---

## 17. Control-plane alternative journeys

These are not on the happy enroll→entitle→submit path. Each is a real branch that changes later request behavior.

### 17.1 Key rotation and revocation

- `POST .../rotate` — insert a new `installation_key` (new `kid`). Old key remains valid until revoked/expired. Duplicate kid → 409. Deleted installation → 409 `illegal_lifecycle_transition`.
- `POST .../revoke-key` `{ kid }` — stamps `revoked_at`. Subsequent AATs with that kid → `unauthenticated`.

Ops: `control.rotate`, `control.revoke-key` (dangerous). Tests: `control.test.ts`.

### 17.2 Suspend / resume / delete

- Suspend: `installation.status='suspended'` → identity `installation_suspended` (403). AI denied; clinic login unaffected.
- Resume: back to `active`.
- Delete: status `deleted` → identity `unauthenticated` (not a distinct “deleted” taxonomy). Illegal transitions from deleted → 409.

Ops: `control.suspend|resume|delete`. Files: `control/lifecycle.ts`.

### 17.3 Capability deprecate / retire

- `POST /control/capabilities/{id}/versions/{v}/deprecate` `{ successor_id }`
- `.../retire`

Writes a global grant-scoped lifecycle overlay (`scope='global'`, `revoked_at=changed_at` so entitlement readers never treat it as a live grant). Same successor on an already-deprecated version is idempotent `200`. Retire requires the overlay to already be `deprecated` **and** `OVERLAP_WINDOW_MS` (90 days) to have elapsed (`409`/`400 overlap_window_active` otherwise). Resolve: deprecated still runs; retired → `capability_retired`. Discovery still lists deprecated.

Ops: `control.deprecate`, `control.retire`. Tests: `capability-deprecation.test.ts`.

### 17.4 Cohort activate / promote

Staged grant rollout without a new entitle. Activate writes grants for listed installations; promote lifts version across live grants (dangerous).

Ops: `control.cohort-activate`, `control.cohort-promote`. Tests: `cohort-activate-promote.test.ts`.

### 17.5 Routing canary / promote / rollback

Covered in §8. Rollback is dangerous. Highest-leverage misconfig: publish without canary/promote.

### 17.6 Token-contract rotation

Covered in §5.

### 17.7 Kill switches

Readable, not writable via control HTTP. Direct D1 insert into `kill_switch (scope, target, active, ...)`. Stage 3 checks `provider:fake`; stage 5 checks providers listed in the loaded routing policy; the live router’s `collectKilledProviderIds` only consults the (usually empty) invoke-time cache.

---

## 18. Conversational and context-negotiation paths

Architecture §6.7 / §8.10 describe a second interaction mode: a turn is a new HTTP request (new idempotency key) linked by `conversation_id`. A valid model “I need more data” becomes terminal `AwaitingContext` + SSE `context_requested`. The next leg carries a transcript.

**What is implemented as libraries:**

- Manifest `interactionMode: "conversational"`
- Transcript validation, budgets, permitted-key allowlist
- Composer rendering of transcript turns
- Adapter `pushTerminalEvent('context_requested')` (throws if used on single_shot)
- Journal `AwaitingContext` (conversational-only assertion)
- Eval fixture `test/eval/clinic.chat_assistant/`

**What production does today:**

- Registry contains only `clinic.visit_summary` (`single_shot`, prose)
- Worker always starts the **prose** broker
- Worker never calls `validateAndRepair` / structured broker
- Worker never writes `AwaitingContext` on the live path
- `context_required` at the guard is an HTTP 422 for missing single-shot keys, which is a different mechanism from SSE `context_requested`

So a first-time operator cannot walk a context-negotiation conversation against the live Worker without publishing a conversational capability and wiring the structured/conversational broker. The code for those branches is real and tested; it is not on the production event source.

**Self-healing (architecture §8.4):** missing required context is rejected at stage 6. The platform does not call the clinic back. The client is expected to fetch keys and resubmit (new or same request depending on client policy). There is no in-place mutation of an existing request.

**Tests:** `conversational-*.ts`, `awaiting-context.test.ts`, `context-request.test.ts`, `context-requested-terminal.test.ts`, `eval/conversation.test.ts`. **Ops:** `e2e.conversation-suite` (eval subprocess, not live Worker).

---

## 19. Architecture vs implementation

Grouped by journey stage. “Deferred” items from architecture §12.5 are omitted as gaps.

### 19.1 Implemented as designed (behavioral)

- Single Worker + Quota DO; no queues
- Enroll vs entitle split (trust vs spend)
- Guard order 1–10; cheapest rejection first; journal after admission
- AAT enrolled-key verification; no Supabase JWT on the platform
- Context keys as vocabulary; undeclared keys dropped
- SSE `accepted` then chunks then one terminal event
- Connection-scoped cancel
- Taxonomy codes and HTTP mapping for guard failures
- Discovery HTTP + ETag
- Control: lifecycle, entitle, grants, routing canary, token contract, support lookup, purge, deprecate/retire, cohort
- DeepSeek + Gemini adapters behind `ProviderPort`
- D1 journal + R2 envelope; GET scoped by installation
- Crons for retention and rollup

### 19.2 Implemented but different (operator-visible)

| Topic | Architecture | Actual behavior |
| --- | --- | --- |
| Request state machine | Accepted → Composing → Invoking → Streaming → Validating → terminal | Journal writes `Accepted`, then jumps to `Completed`/`Failed`/`Cancelled`. Intermediate states exist as types/`journalTransition` but the live Worker does not walk them. |
| Degraded routing | Admission `degraded` → routing tier + `degraded_notice` on `accepted` | `routing_tier` may be stored on the row; live `selectCandidateChain` hardcodes `"standard"`; adapter `degradedNotice` is never set. |
| Idempotent replay | Return original result | Stub `completed` text; use GET for the real envelope. |
| Retry backoff | Jittered sleep | Production `sleeper` is a no-op. |
| Provider kill switch | Per routed provider | Stage 3 uses `providerId: "fake"`. Stage 5 can reject real providers if a routing policy is already loadable. Live router kill-switch filter uses `cache.consult` on a fresh cache, so it rarely sees those rows. |
| Token scopes | AAT scopes gate capabilities | Scopes are parsed onto `Principal` and ignored; grants + allow-list gate. |
| Pending entitlement | §8.1 quota-exhaustion path | `forbidden_capability` / `ai_disabled` at stage 3. |
| `context_required` body | missing keys + shapes | Live POST uses core `buildErrorBody` only. |
| SSE vs GET payload | Same validated result | SSE `completed` is assembled prose `{ text, authoritative }`; GET `result` is the R2 `CanonicalResult`. |
| Cost | Price table | Completed path credits `cost: 0.001`; attempts store `0`. |
| Compose / invoke failure | Release reservation | Stage 10 and post-accept provider failure journal `Failed` without `releaseRPC`. |
| Structured / repair | Mode from manifest | Libraries exist; Worker always uses prose broker. |
| Telemetry | Per-stage spans | Human logger + `platform_counter` rejection tallies only. |
| `settleHappyPath` | — | FakeAdapter helper for load tests; not the live path. |

### 19.3 Missing / unwired

- Control HTTP to write `kill_switch` rows
- Client usage-summary HTTP
- Dashboard HTTP
- Published conversational capability
- Production wiring of structured broker, `validateAndRepair`, `context_requested` terminal, and `chunkSource.wasTruncated`
- Provider secret bindings in `wrangler.toml` (must be secrets / `.dev.vars`)
- `retry_after` / `period_reset` on live preAccept error bodies (`supplementaryFieldsForCode` unused there)
- Clinic Flutter live invoke may still be incomplete relative to this Worker (outside `ai-platform/`; runbook still warns). AAT mint and HTTPS submit ports exist in `frontend/lib/core/ai/`.

### 19.4 Stale companion docs

- `arch-vs-source-gap-analysis.md` still describes an unwired `POST /v1/requests` 503 path.
- `04-ai-platform-operator-runbook.md` still says discovery has no HTTP route and inference is library-only. Both are wired.
t; retire the capability.

---

That is the platform as a journey: configure the Worker, enroll trust, entitle spend, publish a route, mint a token, pass the guard, then carry one request until a single terminal event — with every meaningful off-ramp taken from the code that actually runs.