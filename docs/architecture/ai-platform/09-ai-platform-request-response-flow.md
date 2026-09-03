# AI Platform Request/Response Flow

- Purpose: The **single source of truth** for every production request, RPC, and internal call that makes up the AI Platform — who initiates it, what it calls next, what it reads and writes, and how happy and unhappy paths branch.
- Read this when: you need to understand the complete call hierarchy without assembling the per-stage data-journey documents.
- Canonical for: request/response flow, caller identity, and the production call tree. Field-level D1/R2/DO column dictionaries remain in [data-journey/](data-journey/01-introduction-and-storage-layers.md). Architecture decisions remain in [01-ai-platform.md](01-ai-platform.md).
- Related docs: [06-ai-platform-behavioral-journey.md](06-ai-platform-behavioral-journey.md) (stage intent), [08-ai-platform-data-journey.md](08-ai-platform-data-journey.md) (field companion), [07-ai-platform-d1-r2-storage.md](07-ai-platform-d1-r2-storage.md) (storage).
- Out of scope: the AI Platform viewer. Viewer HTTP calls are not callers and are not documented here.

This document describes **implemented production behavior** (`ai-platform/src/`, `frontend/lib/`, `backend/supabase/migrations/`). Where older data-journey prose disagrees with source, **source wins**; those resolutions are listed in §1.6.

---

## Table of Contents

1. [How to read this document](#1-how-to-read-this-document)
   - [1.1 Actors](#11-actors)
   - [1.2 Planes](#12-planes)
   - [1.3 Storage layers](#13-storage-layers)
   - [1.4 Diagram conventions](#14-diagram-conventions)
   - [1.5 Two facts that structure every live request](#15-two-facts-that-structure-every-live-request)
   - [1.6 Resolved contradictions](#16-resolved-contradictions)
2. [Complete call hierarchy](#2-complete-call-hierarchy)
   - [2.1 Master tree — every initiator](#21-master-tree--every-initiator)
   - [2.2 Worker HTTP dispatch](#22-worker-http-dispatch)
   - [2.3 Clinic trust RPCs (Supabase)](#23-clinic-trust-rpcs-supabase)
   - [2.4 Control plane](#24-control-plane)
     - [2.4.1 Token contract](#241-token-contract)
     - [2.4.2 Installation enroll and lifecycle](#242-installation-enroll-and-lifecycle)
     - [2.4.3 Entitle and capability cohort / lifecycle](#243-entitle-and-capability-cohort--lifecycle)
     - [2.4.4 Routing policy](#244-routing-policy)
     - [2.4.5 Support lookup](#245-support-lookup)
   - [2.5 Clinic staff runtime](#25-clinic-staff-runtime)
   - [2.6 `POST /v1/requests` — ingress, guard, invoke, settle](#26-post-v1requests--ingress-guard-invoke-settle)
   - [2.7 Lookup and support](#27-lookup-and-support)
   - [2.8 Scheduled work](#28-scheduled-work)
   - [2.9 Quota Durable Object RPCs](#29-quota-durable-object-rpcs)
3. [Step-by-step flow](#3-step-by-step-flow)
   - [3.1 Platform boot](#31-platform-boot)
   - [3.2 Token-contract baseline](#32-token-contract-baseline)
   - [3.3 Clinic keypair enrollment](#33-clinic-keypair-enrollment)
   - [3.4 Platform installation enrollment](#34-platform-installation-enrollment)
   - [3.5 Installation lifecycle](#35-installation-lifecycle)
   - [3.6 Entitlement and capability grants](#36-entitlement-and-capability-grants)
   - [3.7 Routing policy](#37-routing-policy)
   - [3.8 Clinic availability flag](#38-clinic-availability-flag)
   - [3.9 Staff session bootstrap](#39-staff-session-bootstrap)
   - [3.10 Minting an AAT](#310-minting-an-aat)
   - [3.11 Discovery](#311-discovery)
   - [3.12 Visit context resolution](#312-visit-context-resolution)
   - [3.13 Request ingress](#313-request-ingress)
   - [3.14 Guard stages 1–10](#314-guard-stages-110)
     - [3.14.1 Stage 1 — Ingress size and JSON](#3141-stage-1--ingress-size-and-json)
     - [3.14.2 Stage 2 — Identity](#3142-stage-2--identity)
     - [3.14.3 Stage 3 — Entitlement and kill switches](#3143-stage-3--entitlement-and-kill-switches)
     - [3.14.4 Stage 4 — Rate limit](#3144-stage-4--rate-limit)
     - [3.14.5 Stage 5 — Capability resolve](#3145-stage-5--capability-resolve)
     - [3.14.6 Stage 6 — Context validate](#3146-stage-6--context-validate)
     - [3.14.7 Stage 7 — Cost pre-flight](#3147-stage-7--cost-pre-flight)
     - [3.14.8 Stage 8 — Admission (Quota DO)](#3148-stage-8--admission-quota-do)
     - [3.14.9 Stage 9 — Journal INSERT](#3149-stage-9--journal-insert)
     - [3.14.10 Stage 10 — Prompt compose](#31410-stage-10--prompt-compose)
   - [3.15 Accept, route, invoke, stream](#315-accept-route-invoke-stream)
   - [3.16 Terminal settlement](#316-terminal-settlement)
   - [3.17 Lookup, support, and clinical acceptance](#317-lookup-support-and-clinical-acceptance)
     - [3.17.1 `GET /v1/requests/{request_reference}`](#3171-get-v1requestsrequest_reference)
     - [3.17.2 `POST /control/support/lookup?reference=`](#3172-post-controlsupportlookupreference)
     - [3.17.3 `public.record_ai_acceptance`](#3173-publicrecord_ai_acceptance)
   - [3.18 Cron](#318-cron)
4. [Unused and orphaned implementations](#4-unused-and-orphaned-implementations)
   - [4.1 Implemented HTTP with no production client](#41-implemented-http-with-no-production-client)
   - [4.2 Implemented clinic RPCs with no Flutter caller](#42-implemented-clinic-rpcs-with-no-flutter-caller)
   - [4.3 Worker modules with no HTTP or runtime caller](#43-worker-modules-with-no-http-or-runtime-caller)
   - [4.4 Flutter modules with no production mount](#44-flutter-modules-with-no-production-mount)
   - [4.5 Storage with no control-plane writer](#45-storage-with-no-control-plane-writer)
   - [4.6 Wired but policy-gated (not orphaned)](#46-wired-but-policy-gated-not-orphaned)
5. [Compact maps](#5-compact-maps)
   - [5.1 HTTP surface](#51-http-surface)
   - [5.2 Clinic Supabase RPCs](#52-clinic-supabase-rpcs)
   - [5.3 Taxonomy to HTTP](#53-taxonomy-to-http)

---

## 1. How to read this document

### 1.1 Actors

Every call in this document names an initiator. There are six:

| Actor | What it is | How it authenticates |
| ----- | ---------- | -------------------- |
| **Clinic staff (Flutter)** | Desktop app used by doctors, nurses, and other staff with `ai.*` permission | Clinic Supabase session for RPCs; AAT Bearer for `/v1/*` |
| **Clinic owner/admin** | Intended caller of keypair RPCs | Clinic Supabase session + `assert_owner_or_administrator()` |
| **Operator** | Human or script holding the platform bearer | `Authorization: Bearer <OPERATOR_BEARER_TOKEN>` on `/control/*` |
| **Cloudflare Worker isolate** | `ai-platform` Worker `fetch` / `scheduled` | Bindings; not an HTTP client of itself |
| **Quota Durable Object** | One `GatewayObject` per `installation_id` | Worker → DO RPC only (`idFromName(installationId)`). Public URL returns 404 |
| **Cloudflare cron** | Wrangler cron triggers | Runtime `scheduled()` handler |

**Vendor SQL / curl** is how owner/admin and operator actions are performed today when Flutter has no UI. That does not change the *intended* actor.

The platform Worker **never** calls clinic Postgres. Clinic **never** writes D1, R2, or the Quota DO except by sending HTTP to the Worker.

### 1.2 Planes

| Plane | Base | Auth | Initiators |
| ----- | ---- | ---- | ---------- |
| Clinic trust | PostgREST RPCs on the clinic Supabase project | Authenticated clinic JWT | Flutter staff / owner-admin |
| Control | `POST /control/*` | Operator bearer | Operator |
| Data (runtime) | `GET /health`, `GET /v1/*`, `POST /v1/requests` | None (`/health`); AAT (`/v1/*`) | Flutter staff; probes |
| Internal | Worker → Quota DO `POST https://quota-do.internal/rpc` | Not public | Worker isolate |
| Scheduled | `scheduled()` | Cron | Cloudflare |

Control-plane errors use `{ "error": "<code>" }`. Runtime errors use `{ "code", "request_reference", "trace_id", "retry_safe" }` (plus optional `retry_after`). Do not mix the two shapes.

### 1.3 Storage layers

| Layer | Binding | Role in the flow |
| ----- | ------- | ---------------- |
| D1 | `env.DB` | Filing cabinet: installation, keys, entitlement, grants, journal, audit, kill switches, routing index |
| R2 | `env.R2` | Warehouse: routing-policy documents; per-request envelopes |
| Quota DO | `env.DO` | Live ledger: period counters, concurrency, JTI replay, idempotency |
| Config cache | isolate memory | 30 s TTL over D1 (+ preloaded R2 policy documents). No flush HTTP API |
| Bundled artifacts | Worker bundle | Capability manifests, prompt files, pricing table — not D1/R2 |
| Clinic Postgres | Supabase | Keypair, AAT issuance, availability flag, visit context, acceptance |

### 1.4 Diagram conventions

All diagrams in §2 are **vertical trees**.

- The root of each tree is the **initiator**.
- Each child is a call the parent makes. HTTP calls show method + path. RPCs show `public.name()`. Internal functions show the TypeScript symbol.
- `[happy]` is the success continuation. `[error]` is a terminal unhappy branch (HTTP status + code, or SSE event).
- A call that does not continue (no further calls) is a leaf.
- Indentation is the **call stack**, not time across unrelated requests.

### 1.5 Two facts that structure every live request

1. **The guard finishes before SSE `accepted`.** A rejected `POST /v1/requests` never opens a stream. The client receives taxonomy JSON.
2. **Routing is not a guard gate.** A request can pass the guard, receive `accepted`, then fail at invoke because no active routing policy exists, the R2 document is missing, or every target is excluded.

### 1.6 Resolved contradictions

These conflicts appear across the data-journey set. This document uses **source** as authority:

| Topic | Rejected claim | Authoritative behavior |
| ----- | -------------- | ---------------------- |
| Platform key rotate | Some stage docs say `POST …/rotate` stamps `revoked_at` on prior keys in the same batch | `handleRotate` **inserts** a new `installation_key` row and leaves prior rows untouched. Dual-key overlap until `POST …/revoke-key` |
| Adapter vs guard on bad JSON | Guard stage 1 would return 500 `internal_error` | Live `handleAdapterRequest` returns **422** empty `text/plain` **before** `runGuard` |
| Kill-switch control API | Implied operator HTTP | **No** `/control/*` route writes `kill_switch`. Operators insert D1 rows (SQL). Guard and router **read** those rows |
| Config-cache flush | `POST /control/config-cache/flush` | **Does not exist** (404). Wait ≤30 s or restart the isolate |
| `GET /v1/requests/{ref}` | Documented as the clinic poll path | Implemented on the Worker; **Flutter production `lib/` never calls it**. SSE is the clinic result path |
| Rotate in alternative-journey prose | Stage 15 tree said rotate revokes prior keys | Same as rotate row above: additive |

---

## 2. Complete call hierarchy

### 2.1 Master tree — every initiator

```
Cloudflare Worker module load
└─ assertRequiredBindings()
   └─ setCapabilityRegistry()          [in-memory catalog; clinic.visit_summary@1.0.0]
      └─ price table load              [bundled control/pricing/…]

Cloudflare cron  (scheduled(); also every tick: flush + grace reconcile)
├─ every tick
│  ├─ flushRejectionCounters()         [Worker isolate → D1 platform_counter]
│  └─ reconcileGraceUsage()            [Worker isolate → D1 grace_admission_queue + Quota DO]
├─ 0 3 * * *
│  └─ runRetentionPurge()              [D1 journal + R2 envelopes]
└─ 0 4 * * *
   └─ runRollupAndReconciliation()     [D1 usage_rollup + join audit]

Operator  (Authorization: Bearer OPERATOR_BEARER_TOKEN)
├─ POST /control/token-contract/begin-rotation
├─ POST /control/token-contract/retire
├─ POST /control/installations/{installation_id}/enroll
├─ POST /control/installations/{installation_id}/rotate
├─ POST /control/installations/{installation_id}/revoke-key
├─ POST /control/installations/{installation_id}/suspend
├─ POST /control/installations/{installation_id}/resume
├─ POST /control/installations/{installation_id}/delete
├─ POST /control/installations/{installation_id}/purge
├─ POST /control/installations/{installation_id}/entitle
├─ POST /control/capabilities/{id}/versions/{ver}/activate
├─ POST /control/capabilities/{id}/versions/{ver}/promote
├─ POST /control/capabilities/{id}/versions/{ver}/deprecate
├─ POST /control/capabilities/{id}/versions/{ver}/retire
├─ POST /control/routing-policies/{policyId}/versions/{ver}/publish
├─ POST /control/routing-policies/{policyId}/versions/{ver}/canary
├─ POST /control/routing-policies/{policyId}/versions/{ver}/promote
├─ POST /control/routing-policies/{policyId}/versions/{ver}/rollback
└─ POST /control/support/lookup?reference={REF}

Clinic owner/admin  (Supabase session; no Flutter UI today — vendor SQL / PostgREST)
├─ public.enroll_installation_keypair()
├─ public.rotate_installation_key()
└─ public.revoke_installation_key(p_kid)

Clinic staff (Flutter)
├─ public.get_ai_availability()                         [AiFeatureHostPage bootstrap]
├─ GET /health                                          [HttpPlatformReachabilityPort]
├─ public.issue_ai_token()                              [SupabaseAatMintPort via AiClientSdk]
├─ GET /v1/capabilities                                 [DiscoveryClient / ManifestRefreshPort]
├─ public.get_visit_chief_complaint(p_visit_id)         [SupabaseContextProviderPort]
└─ POST /v1/requests                                    [PlatformHttpsSubmitPort via AiClientSdk.invoke]
   └─ (SSE) accepted → text_delta/heartbeat/regenerating → completed|failed|cancelled

Worker isolate  (not an HTTP initiator; called from fetch/scheduled)
├─ GatewayObject RPC kind=admission                     [runAdmission, guard stage 8]
├─ GatewayObject RPC kind=credit                        [creditUsage, terminal settlement]
└─ GatewayObject RPC kind=release                       [releaseAdmissionReservation, journal INSERT fail]

Anyone / probe
└─ GET /health                                          [also called by Flutter when enrolled]
```

Expanded subtrees follow. Each names the caller on every request.

### 2.2 Worker HTTP dispatch

Caller: **Cloudflare** invokes `worker.ts` `fetch` for every inbound HTTP request.

```
Cloudflare edge
└─ worker.fetch(request)
   ├─ GET  /health
   │  └─ [happy] 200 { build, environment }
   │
   ├─ GET  /v1/capabilities
   │  └─ handleDiscoveryRequest()                  [caller of this function: worker.fetch]
   │     └─ (see §2.5 discovery subtree)
   │
   ├─ POST /v1/requests
   │  └─ handleLivePostRequest()                   [caller: worker.fetch]
   │     └─ handleAdapterRequest()                 [caller: handleLivePostRequest]
   │        └─ (see §2.6)
   │
   ├─ POST /control/…  when isControlRoute(pathname)
   │  └─ dispatchControlRequest()                  [caller: worker.fetch]
   │     └─ requireOperator() then specific handle* [caller: dispatchControlRequest]
   │        └─ (see §2.4)
   │
   ├─ GET  /v1/requests/{request_reference}
   │  └─ authenticateGetRequest()                  [caller: worker.fetch]
   │     └─ getRequest()                           [caller: worker.fetch after auth]
   │        └─ (see §2.7)
   │
   └─ anything else
      └─ [error] 404 "Not Found"
```

`GatewayObject.fetch` is a **separate** isolate entry (Durable Object), not this tree. Public clients cannot reach it; see §2.9.

### 2.3 Clinic trust RPCs (Supabase)

The Worker is **not** in these trees. PostgREST is the HTTP front; the RPC is the call.

```
Clinic owner/admin  (Flutter intended; vendor SQL today)
│
├─ public.enroll_installation_keypair()
│  ├─ [happy] { kid, installation_id, public_jwk }     [secret_key never on the wire]
│  ├─ [error] FORBIDDEN
│  ├─ [error] ALREADY_ENROLLED
│  └─ [error] SINGLE_INSTALLATION_VIOLATION            [trigger]
│
├─ public.rotate_installation_key()
│  ├─ [happy] same shape as enroll (new kid, same installation_id)
│  ├─ [error] FORBIDDEN
│  └─ [error] INSTALLATION_NOT_ENROLLED
│
└─ public.revoke_installation_key(p_kid)
   ├─ [happy] { kid, revoked_at }                      [idempotent if already revoked]
   ├─ [error] FORBIDDEN
   ├─ [error] INVALID_INPUT
   ├─ [error] KEY_NOT_FOUND
   └─ [error] CANNOT_REVOKE_LAST_ACTIVE_KEY

Clinic staff (Flutter)
│
├─ public.get_ai_availability()                        [caller: SupabaseAiAvailabilityReader.read]
│  └─ [happy] { enrolled, platform_base_url }          [read-only]
│
├─ public.issue_ai_token()                             [caller: SupabaseAatMintPort.mint ← AiClientSdk._acquireAat]
│  ├─ [happy] compact JWS text
│  ├─ [error] INSTALLATION_NOT_ENROLLED
│  ├─ [error] AI_ACCESS_DENIED
│  ├─ [error] BRANCH_NOT_FOUND
│  └─ [error] RATE_LIMITED
│
├─ public.get_visit_chief_complaint(p_visit_id)        [caller: SupabaseContextProviderPort]
│  ├─ [happy] { visit_id, complaint?, recorded_at? }
│  ├─ [error] NOT_FOUND
│  └─ [error] FORBIDDEN
│
└─ public.record_ai_acceptance(...)                    [implemented; no Flutter page calls it — see §4]
   ├─ [happy] acceptance_id + domain write
   ├─ [error] INVALID_INPUT | FORBIDDEN | INTERNAL_ERROR
   └─ [error] delegated domain errors
```

Handoff after keypair enroll: owner/admin (or vendor) takes `installation_id`, `kid`, `public_jwk.x` to the operator enroll call in §2.4. The platform never pulls these from Postgres.

### 2.4 Control plane

Caller of every HTTP request in this tree: **Operator**.
Caller of `dispatchControlRequest`: `worker.fetch`.
Caller of each `handle*`: `dispatchControlRequest`.

Shared unhappy prefix (every route):

```
Operator
└─ POST /control/…
   └─ dispatchControlRequest()
      ├─ [error] 401 unauthorized          [missing/wrong OPERATOR_BEARER_TOKEN]
      ├─ [error] 400 invalid_json
      └─ [error] 400 invalid_route         [malformed path]
```

#### 2.4.1 Token contract

```
Operator
├─ POST /control/token-contract/begin-rotation
│  └─ handleTokenContractBeginRotation()
│     ├─ [happy] 200 { ver }
│     ├─ [error] 400 invalid_ver
│     ├─ [error] 409 ver_already_exists
│     └─ [error] 409 rotation_already_open
│
└─ POST /control/token-contract/retire
   └─ handleTokenContractRetire()
      ├─ [happy] 200 { ver, retired_at }
      ├─ [error] 404 ver_not_found
      ├─ [error] 409 ver_already_retired
      └─ [error] 409 no_rotation_open
```

#### 2.4.2 Installation enroll and lifecycle

```
Operator
│
├─ POST /control/installations/{installation_id}/enroll
│  └─ handleEnroll()
│     ├─ [happy] 200 { platform_base_url }
│     ├─ [error] 400 invalid_payload
│     ├─ [error] 409 already_enrolled          [installation_id or org_id]
│     ├─ [error] 409 duplicate_kid
│     └─ [error] 500 storage_error
│
├─ POST /control/installations/{installation_id}/rotate
│  └─ handleRotate()                           [ADDITIVE — does not revoke prior kids]
│     ├─ [happy] 200 {}
│     ├─ [error] 400 invalid_payload
│     ├─ [error] 404 installation_not_found
│     ├─ [error] 409 illegal_lifecycle_transition   [status=deleted]
│     ├─ [error] 409 duplicate_kid
│     └─ [error] 500 storage_error
│
├─ POST /control/installations/{installation_id}/revoke-key
│  └─ handleRevokeKey()
│     ├─ [happy] 200 {}
│     ├─ [error] 404 installation_not_found | key_not_found
│     ├─ [error] 409 illegal_lifecycle_transition
│     ├─ [error] 409 key_already_revoked
│     └─ [error] 409 cannot_revoke_last_active_key
│
├─ POST /control/installations/{installation_id}/suspend
│  └─ handleSuspend()
│     ├─ [happy] 200 {}
│     └─ [error] 409 illegal_lifecycle_transition   [already suspended/deleted]
│
├─ POST /control/installations/{installation_id}/resume
│  └─ handleResume()
│     ├─ [happy] 200 {}
│     └─ [error] 409 illegal_lifecycle_transition   [not suspended]
│
├─ POST /control/installations/{installation_id}/delete
│  └─ handleDelete()
│     ├─ [happy] 200 {}                        [status=deleted; rows remain]
│     └─ [error] 409 illegal_lifecycle_transition
│
└─ POST /control/installations/{installation_id}/purge
   └─ handleInstallationPurge()
      ├─ [happy] 200 {}                        [R2 envelopes + D1 cascade delete]
      ├─ [error] 500 missing_r2_binding
      └─ [error] 500 storage_error
```

#### 2.4.3 Entitle and capability cohort / lifecycle

```
Operator
│
├─ POST /control/installations/{installation_id}/entitle
│  └─ handleEntitle()
│     ├─ [happy] 200 { installation_id, status: "active" }
│     ├─ [error] 404 installation_not_found | entitlement_not_found
│     ├─ [error] 409 not_pending
│     ├─ [error] 400 invalid_payload
│     └─ [error] 500 storage_error
│
├─ POST /control/capabilities/{id}/versions/{ver}/activate
│  └─ handleCohortActivate()
│     ├─ [happy] 200 {}
│     ├─ [error] 400 missing_installation_ids
│     ├─ [error] 404 capability_not_found | installation_not_found
│     └─ [error] 500 storage_error
│
├─ POST /control/capabilities/{id}/versions/{ver}/promote
│  └─ handleCohortPromote()
│     ├─ [happy] 200 {}
│     ├─ [error] 404 capability_not_found
│     └─ [error] 500 storage_error
│
├─ POST /control/capabilities/{id}/versions/{ver}/deprecate
│  └─ handleDeprecate()
│     ├─ [happy] 200 {}                        [idempotent if same successor]
│     ├─ [error] 400 missing_successor_id | unknown_successor
│     ├─ [error] 404 capability_not_found
│     └─ [error] 409 already_retired | already_deprecated
│
└─ POST /control/capabilities/{id}/versions/{ver}/retire
   └─ handleRetire()
      ├─ [happy] 200 {}
      ├─ [error] 400 not_deprecated | overlap_window_active
      ├─ [error] 404 capability_not_found
      └─ [error] 409 already_retired
```

#### 2.4.4 Routing policy

```
Operator
│
├─ POST /control/routing-policies/{policyId}/versions/{ver}/publish
│  └─ handleRoutingPolicyPublish()
│     ├─ [happy] 200 {} | 200 { warnings: ["latency_class_mismatch"] }
│     ├─ [error] 400 policy_identity_mismatch
│     ├─ [error] 409 already_published
│     └─ [error] 500 storage_error
│
├─ POST /control/routing-policies/{policyId}/versions/{ver}/canary
│  └─ handleRoutingPolicyCanary()
│     ├─ [happy] 200 {}
│     ├─ [error] 400 missing_installation_ids
│     ├─ [error] 404 installation_not_found
│     └─ [error] 409 illegal_policy_transition
│
├─ POST /control/routing-policies/{policyId}/versions/{ver}/promote
│  └─ handleRoutingPolicyPromote()
│     ├─ [happy] 200 {}
│     └─ [error] 409 illegal_policy_transition
│
└─ POST /control/routing-policies/{policyId}/versions/{ver}/rollback
   └─ handleRoutingPolicyRollback()
      ├─ [happy] 200 {}
      └─ [error] 409 illegal_policy_transition
```

`published` is **not served** until canary or promote. Runtime routing happens later, inside §2.6 after `accepted`.

#### 2.4.5 Support lookup

```
Operator
└─ POST /control/support/lookup?reference={REF}
   └─ handleSupportLookup() → supportLookup()
      ├─ [happy] 200 { request, attempts, envelope }
      ├─ [error] 400 missing_reference | invalid_reference
      ├─ [error] 404 not_found
      └─ [error] 500 missing_r2_binding
```

### 2.5 Clinic staff runtime

Caller of every HTTP request in this tree: **Clinic staff, via Flutter**.
Bootstrap lives in `AiFeatureHostPage`; invoke lives in `AiClientSdk` + `FirstAiFeatureSurface`.

```
Clinic staff (Flutter) opens the AI surface
│
├─ AiFeatureHostPage._bootstrap()
│  ├─ SupabaseAiAvailabilityReader.read()
│  │  └─ public.get_ai_availability()                  [caller: Flutter reader]
│  │     ├─ enrolled=false
│  │     │  └─ [stop] degraded nonEnrolled             [no platform HTTP]
│  │     └─ enrolled=true + platform_base_url
│  │        └─ HttpPlatformReachabilityPort.isReachable()
│  │           └─ GET /health                          [caller: Flutter reachability port]
│  │              ├─ [happy] 2xx → mode ready
│  │              └─ [error] timeout/non-2xx → degraded unreachable
│  │
│  └─ [ready] ContextResolver constructed
│
├─ (optional, on invoke / self-heal) DiscoveryClient.fetchCapabilities()
│  └─ GET /v1/capabilities                             [caller: Flutter DiscoveryClient]
│     └─ handleDiscoveryRequest()                      [caller: worker.fetch]
│        ├─ EnrolledKeyVerifier.verify(AAT)
│        │  ├─ [error] 401 unauthenticated
│        │  └─ [happy]
│        │     └─ discover() → buildDiscoveryResponse()
│        │        ├─ [happy] 200 { manifests }
│        │        ├─ [happy] 304                          [If-None-Match matches ETag]
│        │        └─ [happy] 200 { manifests: [] }        [pending entitlement / no grants]
│        └─ POST /v1/capabilities
│           └─ [error] 404                                 [route not registered]
│
├─ SupabaseContextProviderPort.fetchVisitChiefComplaint()
│  └─ public.get_visit_chief_complaint(p_visit_id)     [caller: Flutter; never the Worker]
│
└─ AiClientSdk.invoke()
   ├─ [retry] PlatformHttpException unauthenticated
   │  └─ remint once via issue_ai_token() then retry submit
   ├─ [retry] TransportFailure up to 3 attempts
   ├─ [error] TransportRetryExhausted
   └─ [happy path]
      ├─ AiClientSdk._acquireAat()
      │  └─ SupabaseAatMintPort.mint()
      │     └─ public.issue_ai_token()                 [caller: Flutter mint port]
      └─ PlatformHttpsSubmitPort.submit()
         └─ POST /v1/requests                          [caller: Flutter submit port]
            └─ (see §2.6)
```

`GET /v1/requests/{ref}` is **not** in this Flutter tree. The clinic result path is the SSE stream from `POST /v1/requests`.

### 2.6 `POST /v1/requests` — ingress, guard, invoke, settle

Caller of the HTTP request: **Clinic staff (Flutter `PlatformHttpsSubmitPort.submit`)**.
Caller of `handleLivePostRequest`: `worker.fetch`.
Caller of `handleAdapterRequest`: `handleLivePostRequest`.

```
POST /v1/requests
└─ handleLivePostRequest()
   └─ handleAdapterRequest()
      │
      ├─ readBodyWithinLimit()
      │  └─ [error] 413 request_too_large              [request_reference "", trace_id ""]
      ├─ parseRequestBody()
      │  └─ [error] 422 empty text/plain               [never reaches guard]
      ├─ parseRequiredHeaders()                        [x-idempotency-key, x-capability-version; x-trace-id if present]
      │  └─ [error] 422 empty text/plain
      │
      └─ createProductionPreAccept()                   [caller: handleAdapterRequest]
         ├─ generateRequestReference()                 [Crockford XXXX-XXXX]
         ├─ extract capability_id from body
         │  └─ [error] 500 internal_error              [missing/non-string; guard not run]
         └─ runGuard()                                 [caller: createProductionPreAccept]
            │
            ├─ stage 1  parseAdapterRequestBody()
            │  └─ [error] 413 request_too_large | 500 internal_error
            ├─ stage 2  EnrolledKeyVerifier.verify()
            │  ├─ [error] 401 unauthenticated
            │  └─ [error] 403 installation_suspended
            ├─ stage 3  evaluateEntitlement()
            │  ├─ [error] 403 forbidden_capability
            │  └─ [error] 503 capability_disabled      [kill_switch]
            ├─ stage 4  checkRateLimit()               [3 Cloudflare Rate Limit bindings]
            │  └─ [error] 429 rate_limited             [+ retry_after]
            ├─ stage 5  resolve()                      [in-memory capability registry]
            │  ├─ [error] 404 capability_unknown | capability_retired
            │  ├─ [error] 403 forbidden_capability     [plan / grant / scope / allowedStaffRoles]
            │  └─ [error] 503 capability_disabled
            ├─ stage 6  validateContext()
            │  ├─ [error] 422 context_required | context_invalid
            │  └─ [error] 409 conversation_budget_exhausted
            ├─ stage 7  runCostPreflight()
            │  └─ [error] 413 request_too_large
            ├─ stage 8  runAdmission()                 [caller: runGuard]
            │  ├─ Quota DO RPC kind=admission          [caller: runAdmission]
            │  │  ├─ [error] 401 unauthenticated       [JTI replay]
            │  │  ├─ [error] 429 quota_exhausted       [period or concurrency=16]
            │  │  ├─ [happy] admitted
            │  │  └─ [happy] idempotent                [skip stages 9–10]
            │  └─ [DO down] admitUnderGrace()
            │     ├─ [error] 429 rate_limited          [grace cap 5 pending / installation]
            │     └─ [happy] grace_admitted            [routing_tier=degraded]
            ├─ stage 9  createRequestRow()             [skipped on idempotent]
            │  ├─ [error] 500 internal_error
            │  │  └─ Quota DO RPC kind=release         [caller: runGuard]
            │  └─ [happy] D1 ai_request INSERT state=Accepted
            └─ stage 10 composeRequest()               [skipped on idempotent]
               └─ [error] 500 internal_error           [D1 state=Failed]
            │
            └─ [guard fail any stage]
               └─ [error] taxonomy JSON                [NO SSE, no accepted]
            │
            └─ [guard pass]
               └─ handleAdapterRequest opens SSE 200 text/event-stream
                  └─ createProductionEventSource()     [caller: handleAdapterRequest]
                     │
                     ├─ [idempotent] replayIdempotentTerminal()
                     │  ├─ prior completed → SSE completed  ["Prior request completed."]
                     │  ├─ prior failed    → SSE failed internal_error
                     │  └─ prior cancelled → SSE cancelled
                     │     (no provider, no new D1 INSERT, no new R2 write)
                     │
                     └─ [fresh] runFreshEventSource()  [caller: createProductionEventSource]
                        ├─ SSE accepted
                        ├─ preloadRoutingPolicyForInstallation()
                        │  ├─ ConfigCache / D1 routing_policy
                        │  └─ R2 GET control/routing-policy/{id}/{ver}.json
                        ├─ selectCandidateChain()
                        │  ├─ [error] SSE failed internal_error
                        │  │     [no active/canary policy, missing R2, identity mismatch]
                        │  ├─ [error] SSE failed no_matching_rule
                        │  └─ [error] SSE failed provider_unavailable
                        │        [empty chain / all targets excluded]
                        ├─ persistRoutingDecision()    [D1 ai_request.routing_decision]
                        ├─ createStreamBroker()        [caller: runFreshEventSource]
                        ├─ runInvocation()             [caller: runFreshEventSource]
                        │  └─ resolveProviderPort() → HTTPS
                        │     ├─ DeepSeek | Gemini | FakeAdapter
                        │     ├─ retry same target → SSE regenerating (if partial stream)
                        │     ├─ fallback next target in chain
                        │     ├─ [error] SSE failed provider_unavailable  [chain exhausted]
                        │     ├─ [error] SSE failed provider_rejected     [missing API key]
                        │     ├─ [error] SSE failed timeout
                        │     └─ [happy] chunks → InvocationSink.emitStreamText
                        │           └─ SSE text_delta
                        ├─ silence → SSE heartbeat (15 s)
                        ├─ client abort
                        │  └─ SSE cancelled → settle cancelled
                        ├─ prose output guards fail
                        │  └─ SSE failed validation_failed
                        └─ terminal
                           └─ settleCompletedRequest() | settleTerminal()
                              └─ (see settlement subtree below)
```

Settlement (called from the broker / `runFreshEventSource`, **not** from Flutter):

```
runFreshEventSource / createStreamBroker
└─ terminal (completed | failed | cancelled)
   ├─ creditUsage()                                    [caller: broker creditSink / settle*]
   │  └─ Quota DO RPC kind=credit                      [caller: creditUsage]
   ├─ recordTerminalState()                            [D1 ai_request state]
   └─ writePostResponseDetail()
      ├─ D1 INSERT ai_attempt (per provider attempt; ≥1 on Failed)
      ├─ D1 INSERT usage_event                         [always, including cancel at zero]
      ├─ R2 PUT request/{request_id}/envelope
      └─ D1 UPDATE ai_request.payload_pointer
```

### 2.7 Lookup and support

```
Clinic staff (Flutter)                                 [NO production caller today]
└─ GET /v1/requests/{request_reference}
   └─ worker.fetch
      ├─ authenticateGetRequest()                      [EnrolledKeyVerifier; caller: worker.fetch]
      │  ├─ [error] 401 unauthenticated
      │  └─ [error] 403 installation_suspended
      └─ getRequest()                                  [caller: worker.fetch]
         ├─ [error] 404 empty body                     [missing, or other installation]
         ├─ [happy] 200 { state: Completed, result? }
         ├─ [happy] 200 { state: Failed, terminal_error_code }
         ├─ [happy] 200 { state: Cancelled }
         ├─ [happy] 200 { state: AwaitingContext }
         └─ [happy] 200 { state, pending: true }       [in-flight]

Operator
└─ POST /control/support/lookup?reference={REF}        [already in §2.4.5]
```

### 2.8 Scheduled work

Caller: **Cloudflare cron** → `worker.scheduled()`.

Local-dev only, Cloudflare also exposes `GET /cdn-cgi/handler/scheduled` so an operator can fire the handler; that is a wrangler test hook, not a platform API.

```
Cloudflare cron
└─ worker.scheduled(controller)
   ├─ flushRejectionCounters()                         [every tick]
   ├─ reconcileGraceUsage()                            [every tick]
   │  └─ Quota DO RPC kind=admission + kind=credit     [caller: reconcileGraceUsage]
   ├─ [cron == 0 3 * * *] runRetentionPurge()
   └─ [cron == 0 4 * * *] runRollupAndReconciliation()
```

### 2.9 Quota Durable Object RPCs

Caller of every RPC: **Worker isolate** (`runAdmission`, `creditUsage`, `releaseAdmissionReservation`, `reconcileGraceUsage`).
Not reachable as public HTTP.

```
Worker isolate
└─ env.DO.idFromName(installationId) → GatewayObject.fetch
   └─ POST https://quota-do.internal/rpc
      ├─ kind=admission → admissionRPC()
      ├─ kind=credit    → creditRPC()
      └─ kind=release   → releaseRPC()
```

---

## 3. Step-by-step flow

Read §2 for *who calls what*. This section explains *what each step does*, *what it touches*, and *how it connects*.

Cloudflare columns below cover D1, R2, Quota DO, isolate ConfigCache, rate-limit bindings, env/secrets, and outbound provider HTTPS. A cell that says **none** means that side is not in the call.

### 3.1 Platform boot

**Does.** Brings a Worker isolate to a state where it can serve HTTP. Wrangler injects bindings from `ai-platform/wrangler.toml`. At module load, `assertRequiredBindings` requires `DB`, `R2`, and `DO`. `setCapabilityRegistry` loads the bundled capability catalog (today `clinic.visit_summary@1.0.0`). The pricing table is loaded from the bundled artifact `control/pricing/platform-default/1.json`. Prompt markdown is **not** loaded at boot; `composeRequest` imports it lazily on first guard stage 10.

**Caller.** Cloudflare runtime (isolate start). Flutter and the operator do not call boot.

**Cloudflare.** Reads env `BUILD_SHA`, `ENVIRONMENT`, `LOG_VERBOSITY`, `OPERATOR_ID`; secrets `OPERATOR_BEARER_TOKEN`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`. Bindings: D1, R2, DO, three rate limiters (`RATE_LIMITER_INSTALLATION` 600/60s, `RATE_LIMITER_INSTALLATION_ACTOR` 120/60s, `RATE_LIMITER_INSTALLATION_CAPABILITY` 300/60s). Writes nothing. Missing `DB`/`R2`/`DO` throws and the isolate does not serve.

**Supabase.** None.

**Connects.** Precedes every other step. D1 schema itself is applied out-of-band by `wrangler d1 migrations apply`, which seeds `token_contract` `ver='1'`. After boot, the only unauthenticated runtime call is `GET /health`.

**`GET /health`.** Called by Flutter `HttpPlatformReachabilityPort.isReachable` after `get_ai_availability` reports enrolled, and by any probe. Reads `BUILD_SHA` and `ENVIRONMENT` only. Returns `200 { build, environment }`. Does not read D1. An isolate that booted without migrations still returns 200; AAT paths then fail later.

### 3.2 Token-contract baseline

**Does.** Declares which AAT `ver` claim values the platform will accept. Seed row `ver='1'` is created by D1 migration, not by HTTP.

**Caller of HTTP.** Operator → `POST /control/token-contract/begin-rotation` (`handleTokenContractBeginRotation`) and `POST /control/token-contract/retire` (`handleTokenContractRetire`). Runtime identity (guard stage 2 / discovery verifier) **reads** the table; it never writes it.

**Cloudflare.** Begin-rotation: D1 INSERT `token_contract` (at most two non-retired versions) + INSERT `control_audit` `action=token_contract_begin_rotation`. Retire: D1 UPDATE `token_contract.retired_at` + INSERT `control_audit` `action=token_contract_retire`. ConfigCache key `token_contracts:{ver}` (30 s TTL). R2/DO: none.

**Supabase.** None. Clinic mint reads `ai_internal.app_settings` key `ai.aat.ver` (default `"1"`) independently. The platform does not write that setting. If clinic `ver` and D1 `token_contract` diverge, mint still succeeds and platform identity returns `unauthenticated`.

**Connects.** After boot (§3.1). Before any AAT can pass identity (§3.10, §3.14 stage 2). Dual-accept window: both versions valid until retire. After retire, AATs with that `ver` fail `unauthenticated`.

**Unhappy.** `401 unauthorized`; `400 invalid_ver`; `409 ver_already_exists` / `rotation_already_open` / `ver_already_retired` / `no_rotation_open`; `404 ver_not_found`.

### 3.3 Clinic keypair enrollment

**Does.** Creates the clinic-side Ed25519 keypair that will sign AATs. The private key never leaves Postgres and is never sent to the platform.

**Caller.** Clinic owner/admin via `public.enroll_installation_keypair()`. Flutter `lib/` has **no** caller; today this is vendor SQL / PostgREST. Same actor for `rotate_installation_key()` and `revoke_installation_key(p_kid)`.

**Cloudflare.** None. The platform does not learn about this key until enroll (§3.4).

**Supabase.** Enroll INSERT `ai_internal.installation_keys` (`kid`, `installation_id`, `public_key`, `secret_key`, `algorithm=EdDSA`). Rotate INSERT a new row with the same `installation_id`. Revoke UPDATE `revoked_at`. Returns `kid`, `installation_id`, `public_jwk.{kty,crv,x,kid}` — never `secret_key`.

**Connects.** After a clinic exists. Next: operator takes `installation_id` + `kid` + `public_jwk.x` to §3.4. Staff mint (§3.10) signs with the latest active key (`valid_from DESC, kid DESC`). Revoking the last active key is refused (`CANNOT_REVOKE_LAST_ACTIVE_KEY`).

**Unhappy.** `FORBIDDEN`; `ALREADY_ENROLLED`; `SINGLE_INSTALLATION_VIOLATION`; rotate `INSTALLATION_NOT_ENROLLED`; revoke `KEY_NOT_FOUND` / `INVALID_INPUT`.

### 3.4 Platform installation enrollment

**Does.** Creates the platform’s record of the clinic installation: identity row, public key, and a **pending** entitlement (AI still disabled).

**Caller.** Operator → `POST /control/installations/{installation_id}/enroll` → `handleEnroll`. The path `{installation_id}` is the UUID returned by §3.3 — the platform does not generate it. Intended future caller is Flutter owner/admin after purchase; today it is operator curl. Body: `org_id`, `display_name`, `region`, `plan` (`starter`/`standard`/`professional`/`enterprise`), `public_key` (base64url 32-byte Ed25519), `algorithm=EdDSA`, `kid`.

**Cloudflare.** Atomic D1 batch:

- INSERT `installation` (`status=active`, `enrolled_at=now`)
- INSERT `installation_key` (`key_id=kid`, `valid_until=valid_from+365d`, `revoked_at=NULL`)
- INSERT `entitlement` (`status=pending`, quotas 0, `allowed_capabilities=[]`, `soft_threshold=0`)
- INSERT `control_audit` `action=enroll`

R2/DO: none. Success `200 { platform_base_url }` echoing the request origin.

**Supabase.** None. Enroll does **not** flip `ai.availability`. That is a separate clinic write (§3.8).

**Connects.** After §3.3. After this step, a well-signed AAT can pass identity, but guard stage 3 still returns `403 forbidden_capability` (`ai_disabled`) because entitlement is pending. Discovery returns `{ manifests: [] }`. Next required spend-path step is entitle (§3.6) plus a served routing policy (§3.7).

**Unhappy.** `401 unauthorized`; `400 invalid_json` / `invalid_payload`; `409 already_enrolled` (same `installation_id` **or** `org_id`); `409 duplicate_kid`; `500 storage_error`. `org_id` uniqueness is clinic-local in Postgres and globally unique in D1 — two independent clinics that reuse an org UUID collide here.

### 3.5 Installation lifecycle

**Does.** Changes the enrolled installation after §3.4 without returning to enroll (except after purge). Every action is operator `POST`, writes `control_audit`, and is gated by `requireOperator`.

**Caller.** Operator. Clinic key rotate/revoke RPCs (§3.3) are the **clinic-side** counterparts; they do not call these endpoints. Someone must copy the new `kid` + `public_key` into the platform rotate body.

| HTTP | Handler | Cloudflare write | Runtime effect on next `POST /v1/requests` |
| ---- | ------- | ---------------- | ------------------------------------------ |
| `…/rotate` | `handleRotate` | INSERT new `installation_key` only | Dual-key overlap; old `kid` still verifies until revoke-key |
| `…/revoke-key` | `handleRevokeKey` | UPDATE `installation_key.revoked_at` | AAT with that `kid` → `401 unauthenticated` |
| `…/suspend` | `handleSuspend` | `installation.status=suspended` | Guard stage 2 → `403 installation_suspended` |
| `…/resume` | `handleResume` | `status=active` from `suspended` only | Restores invoke |
| `…/delete` | `handleDelete` | `status=deleted` (rows remain) | AAT → `401 unauthenticated` |
| `…/purge` | `handleInstallationPurge` | Audit intent → R2 DELETE `request/{id}/envelope` → D1 cascade delete (attempts, usage_event, ai_request, grants, keys, entitlement, installation) → audit complete | Installation gone. Does **not** clear `grace_admission_queue`. Does **not** touch clinic Postgres |

**Supabase.** None of these endpoints write clinic data. After platform revoke-key, clinic `verify_aat` / mint still uses clinic `installation_keys` until the clinic RPC revoke is also performed.

**Connects.** Rotate follows clinic `rotate_installation_key()`. Suspend/resume/delete are operator operational controls on the runtime path (§3.14). Purge is the terminal cleanup after delete (or instead of keeping deleted rows).

### 3.6 Entitlement and capability grants

**Does.** Opens spend: flips entitlement from `pending` to `active`, writes budgets, and inserts capability grants that discovery and the guard will honor.

**Caller.** Operator → `POST /control/installations/{id}/entitle` → `handleEntitle`. Cohort/lifecycle:

- `POST /control/capabilities/{id}/versions/{ver}/activate` → `handleCohortActivate`
- `…/promote` → `handleCohortPromote` (cohort, not routing-policy promote)
- `…/deprecate` → `handleDeprecate`
- `…/retire` → `handleRetire`

**Cloudflare.** Entitle: UPDATE `entitlement` (`status=active`, period bounds, `request_quota`, `token_budget`, `cost_budget`, `soft_threshold`, `allowed_capabilities`); INSERT `capability_grant` per grant (`scope` default `installation:{id}`, or `plan:{plan}`); INSERT `control_audit` `action=entitle`. Does **not** change `entitlement.plan` or `installation.status`. Activate/promote UPDATE/INSERT grants. Deprecate INSERT global overlay grant `lifecycle_state=deprecated`, `retire_after=deprecated_at+90d`. Retire INSERT overlay `lifecycle_state=retired` after the overlap window.

ConfigCache: `entitlements/{installationId}`, `grants/{installationId}/{capabilityId}` or `plan:{plan}/{capabilityId}` — stale up to 30 s.

**Supabase.** None.

**Connects.** After enroll (§3.4). Unlocks discovery manifests (§3.11) and guard stage 3 (§3.14). Does **not** publish routing; a request can now pass the guard and still fail post-`accepted` if §3.7 is missing. Zero quotas with `status=active` fail at guard stage 8 (`429 quota_exhausted`), not as `forbidden_capability`.

**Unhappy (entitle).** `404 installation_not_found` / `entitlement_not_found`; `409 not_pending`; `400 invalid_payload`; `500 storage_error`.

### 3.7 Routing policy

**Does.** Puts the document the post-accept router will use: full JSON in R2, index row in D1. Serving requires canary or promote; `published` alone is not served.

**Caller.** Operator:

- `POST /control/routing-policies/{policyId}/versions/{ver}/publish` → `handleRoutingPolicyPublish` (R2 PUT then D1 INSERT `status=published`)
- `…/canary` → `handleRoutingPolicyCanary` (D1 `status=canary` + `canary_installation_ids`)
- `…/promote` → `handleRoutingPolicyPromote` (supersede other active/canary; target `active`)
- `…/rollback` → `handleRoutingPolicyRollback`

**Cloudflare.** Publish writes R2 `control/routing-policy/{policyId}/{version}.json` and D1 `routing_policy` (`content_pointer`, version, status) + `control_audit` `action=routing_policy_publish`. Canary/promote/rollback update D1 only. Runtime **reads** (not in this step): ConfigCache `active_routing_policy` then the preloaded R2 document inside `runFreshEventSource` (§3.15).

**Supabase.** None.

**Connects.** Can be done before or after entitle; both are required for a completed invoke. Manifest `routingPolicyRef` (bundled) selects which policy id to load. Failure is **after** `accepted`: SSE `failed` `internal_error` (missing policy/R2) or `provider_unavailable` (empty chain).

### 3.8 Clinic availability flag

**Does.** Tells Flutter whether to show the AI surface and which platform base URL to use. This is the clinic-side switch; enroll/entitle do not flip it.

**Caller of the read.** Clinic staff Flutter → `SupabaseAiAvailabilityReader.read` → `public.get_ai_availability()`.

**Caller of the write.** **No write RPC exists.** Migration seeds `{ enrolled: false, platform_base_url: null }`. Intended production: Flutter owner/admin after a successful platform enroll. Today: vendor `UPDATE ai_internal.app_settings` key `ai.availability`.

**Cloudflare.** None.

**Supabase.** Read `ai_internal.app_settings`. Write (manual) the same key.

**Connects.** After §3.4 (so `platform_base_url` from enroll can be copied in). Before staff bootstrap (§3.9). Flutter **never** probes the platform to discover enrollment (FR-009); it only calls `GET /health` after this flag says enrolled.

### 3.9 Staff session bootstrap

**Does.** Decides whether the AI surface is ready, unreachable, or hidden.

**Caller.** Clinic staff Flutter → `AiFeatureHostPage._bootstrap`.

Sequence:

1. `get_ai_availability()` (§3.8). If `enrolled=false`, stop — **no** platform HTTP.
2. `GET /health` against `platform_base_url` (`HttpPlatformReachabilityPort`).
3. `resolveDegradedMode` → `ready` constructs `ContextResolver`.

**Cloudflare.** `GET /health` reads env only.

**Supabase.** Availability read only.

**Connects.** After §3.8. Ready mode precedes context fetch (§3.12) and invoke (§3.10–§3.16). Unreachable mode renders degraded UI and does not mint or POST.

### 3.10 Minting an AAT

**Does.** Issues a short-lived clinic-signed JWS (AAT) that the platform will treat as the staff principal. The platform never receives the private key and is not called during mint.

**Caller.** Clinic staff Flutter → `AiClientSdk._acquireAat` → `SupabaseAatMintPort.mint` → `public.issue_ai_token()`. Cached on the SDK instance; reminted once if `POST /v1/requests` returns `unauthenticated`.

**Cloudflare.** None at mint time.

**Supabase.** Reads latest active `installation_keys`, staff member, primary branch, RBAC `ai.*` permissions, `ai.aat.*` settings (`audience` default `ai-platform`, `ver` default `"1"`, `lifetime_minutes` seed 15). Writes `ai_internal.ai_token_issuance` one row per `jti`. Returns compact JWS (`alg=EdDSA`, `kid` in header). Claims: `iss=installation_id`, `aud`, `sub=staff id`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`. No patient ids, quotas, or provider hints.

**Connects.** After §3.3 (clinic key exists). Platform identity also needs §3.4 (D1 key) and §3.2 (token contract). Used as `Authorization: Bearer` on discovery (§3.11) and invoke (§3.13). Platform rejects `exp − iat > 600` even if the clinic minted a 15-minute token — that mismatch is real: clinic seed is 15 minutes, platform max lifetime is 10 minutes.

**Unhappy.** `INSTALLATION_NOT_ENROLLED`; `AI_ACCESS_DENIED`; `BRANCH_NOT_FOUND`; `RATE_LIMITED`.

### 3.11 Discovery

**Does.** Returns the capability manifests this installation may invoke, filtered by entitlement and grants. Kill switches are **not** applied here (`killSwitchFlag` on a manifest is informational).

**Caller.** Clinic staff Flutter → `DiscoveryClient.fetchCapabilities` (hub composition and `DiscoveryManifestRefreshPort` during context self-heal) → `GET /v1/capabilities` → `handleDiscoveryRequest`.

**Cloudflare.** Reads D1 via ConfigCache: `installation`, `entitlement`, `capability_grant`. Verifies AAT with `EnrolledKeyVerifier` (same crypto as guard stage 2: `installation_key`, `token_contract`). Writes nothing. Headers: `Cache-Control: private, must-revalidate`, `ETag`. `If-None-Match` match → 304.

**Supabase.** None (AAT already minted).

**Connects.** After mint (§3.10) and enroll (§3.4). Empty `manifests` is a **200**, not an error — typical when entitlement is still pending. Flutter uses `Identity.capabilityId` as body `capability_id` and `Identity.version` as `x-capability-version` on the subsequent POST.

**Unhappy.** `401 unauthenticated` (missing/invalid AAT, including operator bearer). `POST /v1/capabilities` is not registered → 404.

### 3.12 Visit context resolution

**Does.** Loads the clinic visit field that becomes `visit.chief_complaint@v1` on the invoke body. Required by the visit-summary manifest (max 4096 bytes on the wire).

**Caller.** Clinic staff Flutter → `SupabaseContextProviderPort.fetchVisitChiefComplaint` → `public.get_visit_chief_complaint(p_visit_id)`. The Worker never calls this RPC.

**Cloudflare.** None.

**Supabase.** Reads the visit the staff is allowed to see. Unhappy: `NOT_FOUND`, `FORBIDDEN`.

**Connects.** After bootstrap ready (§3.9). Output is placed in `POST /v1/requests` `context` before submit. Guard stage 6 validates it. Body keys `routing_tier`, `degraded`, `degraded_notice` are ignored if the client sends them (`ADAPTER_ROUTING_BODY_FIELDS = []`); the server sets routing tier from Quota DO admission.

### 3.13 Request ingress

**Does.** Turns an HTTPS POST into either a taxonomy JSON error (no stream) or a handoff into `runGuard`. Size, JSON shape, and required headers are enforced **here**, before the guard.

**Caller.** Clinic staff Flutter → `AiClientSdk.invoke` → `PlatformHttpsSubmitPort.submit` → `POST /v1/requests` with `Authorization: Bearer <AAT>`, `x-idempotency-key`, `x-capability-version`, optional `x-trace-id`. Worker `fetch` → `handleLivePostRequest` → `handleAdapterRequest`.

**Cloudflare.** Reads the HTTP request only. Writes nothing at this step. `generateRequestReference()` allocates Crockford `XXXX-XXXX` once pre-accept starts. `resolveTraceId()` uses `x-trace-id` or a server ULID.

**Supabase.** None.

**Connects.** After mint (§3.10), discovery (§3.11), and context (§3.12). Next is the guard (§3.14). Adapter failures never open SSE:

| Failure | HTTP | Body |
| ------- | ---- | ---- |
| Body or `Content-Length` > 1 MiB | 413 | taxonomy `request_too_large`; `request_reference` and `trace_id` empty |
| Non-object JSON | 422 | empty `text/plain` |
| Missing/empty `x-idempotency-key` or `x-capability-version`; empty `x-trace-id` if present | 422 | empty `text/plain` |
| Missing/non-string `capability_id` (after headers parsed) | 500 | `internal_error` (guard not run) |

Flutter retries: one remint on `unauthenticated`; up to three attempts on `TransportFailure`.

### 3.14 Guard stages 1–10

**Does.** Ten sequential checks. Any failure returns taxonomy JSON and **never** emits `accepted`. Caller of `runGuard` is `createProductionPreAccept`, itself called from `handleAdapterRequest`.

On success the isolate stores `AcceptContext` (fresh vs idempotent) in a **request-scoped** map for the event source. That map is not D1 and not a module global.

#### 3.14.1 Stage 1 — Ingress size and JSON

Re-checks UTF-8 byte length and object shape (`parseAdapterRequestBody`). Extracts `userIntent`, `suppliedContext`, `conversationId`, `turnOrdinal`, `transcript`. Unhappy: `413 request_too_large` / `500 internal_error`. On the live POST path, malformed JSON is already a 422 from §3.13, so stage 1 `internal_error` is not reachable for that case.

**Cloudflare / Supabase.** None beyond the in-memory body.

#### 3.14.2 Stage 2 — Identity

`EnrolledKeyVerifier.verify`. Requires compact JWS, `alg=EdDSA`, `kid`, all claims, `aud=ai-platform`, clock skew ±60 s, `exp − iat ≤ 600`. Loads D1 `installation` by `iss`, `installation_key` by `kid` (not revoked, in validity window, bound to installation), verifies Ed25519 signature, then `token_contract` for `ver`.

| Installation / key state | Result |
| ------------------------ | ------ |
| Missing installation, missing/revoked/wrong key, bad signature, retired/missing token contract, deleted installation | `401 unauthenticated` |
| `installation.status=suspended` | `403 installation_suspended` |
| Active + valid key + accepted `ver` | Principal produced |

**Cloudflare.** ConfigCache reads `installations`, `keys`, `token_contracts`. Writes none.

**Supabase.** None (signature already exists).

Produces: `installationId`, `organizationId`, `branchId`, `actorId`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`.

#### 3.14.3 Stage 3 — Entitlement and kill switches

`evaluateEntitlement`. Uses body `capability_id`. Provider kill-switch dimension at this stage is hardcoded `providerId: "fake"`.

| Check | Failure |
| ----- | ------- |
| `entitlement.status !== active` | `403 forbidden_capability` (path `ai_disabled`) |
| Plan below `minimumPlanTier` (standard) | `403 forbidden_capability` (`plan_tier`) |
| Capability not in `allowed_capabilities` | `403 forbidden_capability` |
| Missing / revoked / version-mismatched grant | `403 forbidden_capability` |
| Active `kill_switch` global / capability / installation / `provider:fake` | `503 capability_disabled` |

**Cloudflare.** Reads `entitlement`, `capability_grant`, `kill_switch` via ConfigCache.

#### 3.14.4 Stage 4 — Rate limit

`checkRateLimit` against three bindings: installation, installation+actor, installation+capability. First dimension that trips returns `429 rate_limited` with `retry_after` (default 60 s).

Side effect: `recordGuardRejection` increments an **in-isolate** tally. Cron `flushRejectionCounters` later writes D1 `platform_counter` (lower bound, not exact).

#### 3.14.5 Stage 5 — Capability resolve

`resolve` looks up `{capability_id}@{x-capability-version}` in the in-memory registry (not D1). Checks lifecycle, plan, grants, `requiredCapabilityScope`, `allowedStaffRoles`, manifest `killSwitchFlag`, and D1 kill switches (global/capability/installation). Provider kill switches are collected as `killedProviderIds` for the router — they do **not** 503 here.

Unhappy: `404 capability_unknown` / `capability_retired`; `403 forbidden_capability`; `503 capability_disabled`.

Visit-summary `allowedStaffRoles` is `["clinician","nurse"]` while `issue_ai_token` mints `role=doctor`. That role mismatch fails this stage unless RBAC/manifest are aligned.

#### 3.14.6 Stage 6 — Context validate

`validateContext`. Required keys, `context.org` / `context.branch` must match AAT, per-key shape and `maxSize`. Extra keys are dropped, not rejected. Conversational mode also requires `turn_ordinal`, `transcript`, and a remaining budget.

Unhappy: `422 context_required` / `context_invalid`; `409 conversation_budget_exhausted`. Live HTTP does not currently attach `missing_keys` on `context_required` (`buildContextRequiredResponse` is unused on the Worker wire — see §4).

Output: `filteredContext`.

#### 3.14.7 Stage 7 — Cost pre-flight

`runCostPreflight`. Token estimate: `ceil((utf8(context+intent[+transcript]) + promptArtifactByteLength) / 4) * 1.15`. Fails `413 request_too_large` if estimated input exceeds `maxInputTokens` or input+`maxOutputTokens` exceeds `perRequestTokenCeiling`. Does **not** read a D1 price table.

#### 3.14.8 Stage 8 — Admission (Quota DO)

`runAdmission`. If `principal.exp` is already past: `401 unauthenticated`. Then Worker → Quota DO `kind=admission` with `jti`, `installationId`, `idempotencyKey`, `requestReference`, entitlement snapshot.

| DO outcome | Guard | Next |
| ---------- | ----- | ---- |
| `admitted` | ok + `requestId`; may set `degraded` if usage ≥ `soft_threshold` | stages 9–10; `routing_tier=standard` or `degraded` |
| `idempotent` | ok, prior state | **skip 9 and 10** |
| `replay` (same JTI, different idempotency key, within 2 h) | `401 unauthenticated` | stop |
| `quota_exhausted` | `429 quota_exhausted` | stop (period counters vs entitlement) |
| `concurrency_exhausted` | `429 quota_exhausted` | stop (in-flight cap 16) |

If the DO is down: `admitUnderGrace` inserts D1 `grace_admission_queue` (`routing_tier=degraded`). Cap **5** pending rows per installation → `429 rate_limited` (not `quota_exhausted`). Idempotent replay of a journaled row stays idempotent; a pending grace row reuses `graceRequestId`.

**Cloudflare.** DO read/write ephemeral state (`jti` map, idempotency map, in-flight, period counters). Possible D1 INSERT `grace_admission_queue`.

#### 3.14.9 Stage 9 — Journal INSERT

`createRequestRow`. Fresh path only. D1 INSERT `ai_request` (`state=Accepted`, `routing_decision=NULL`, identity/capability/idempotency/trace/routing_tier/conversation fields).

If INSERT fails: Quota DO `kind=release` (`releaseAdmissionReservation`) then `500 internal_error`. This is the only production caller of `release`.

#### 3.14.10 Stage 10 — Prompt compose

`composeRequest` (lazy prompt registry). Builds `CanonicalRequest` with `streamFlag: true`. Failure: D1 UPDATE `state=Failed` + `500 internal_error`.

Success object (`GuardFreshSuccess`) is what §3.15 consumes: `requestId`, principal, manifest, `filteredContext`, composed request, prompt version, `killedProviderIds`, `routingTier`, `degraded?`.

### 3.15 Accept, route, invoke, stream

**Does.** Opens SSE, loads routing, calls a provider, relays chunks, and hands the terminal outcome to settlement. Caller of `createProductionEventSource` is `handleAdapterRequest` after a passing guard. Caller of `runFreshEventSource` is that event source on the fresh path.

**Cloudflare reads.** D1 `routing_policy` + R2 policy document via `preloadRoutingPolicyForInstallation`; D1 `kill_switch` for providers via `selectCandidateChain` / `collectKilledProviderIds`. Outbound HTTPS to DeepSeek (`deepseek-v4-flash`, OpenAI-compatible `stream: true`), Gemini (`gemini-3.5-flash`, `:streamGenerateContent?alt=sse`), or in-process `FakeAdapter`.

**Cloudflare writes before terminal.** D1 UPDATE `ai_request.routing_decision` (`persistRoutingDecision`). SSE events to the client. No Supabase.

**SSE sequence (fresh).**

1. `accepted` — `request_reference`, `trace_id`, optional `degraded_notice`. HTTP status is already 200 `text/event-stream`.
2. `text_delta` — provisional tokens (`text`, `sequence`, `provisional: true`). Platform may omit `trace_id` on this event today.
3. `heartbeat` — every 15 s of silence.
4. `regenerating` — retry of the same target after a partial stream.
5. Terminal: `completed` | `failed` | `cancelled` | (conversational) `context_requested`.

Two trace identifiers: SSE/D1 `trace_id` is `x-trace-id` or server ULID; `CanonicalRequest.correlationIds.trace_id` is the AAT `jti` (provider correlation only).

**Idempotent path.** No provider, no new D1 INSERT, no new R2 write. Replay from Quota DO prior state: completed uses placeholder `"Prior request completed."` (not a full R2 replay); failed → `internal_error`; cancelled → `cancelled`.

**Post-accept failures (all after `accepted`).**

| Condition | SSE `failed` code |
| --------- | ----------------- |
| Missing guard handoff; missing/mismatched routing policy or R2 document | `internal_error` |
| No matching rule | `no_matching_rule` |
| Empty chain; all targets excluded; chain exhausted | `provider_unavailable` |
| Missing provider API key | `provider_rejected` |
| Output guards (length, stop, leak, refusal, injection-echo, empty, truncation) | `validation_failed` |
| Unexpected throw | `internal_error` |
| Client abort | `cancelled` (event may not reach an already-gone client) |

Invoke-time cost ceiling uses `entitlementMaxCostClass` hardcoded `"premium"` in `runFreshEventSource`; it does not re-read a live entitlement cost class on the wire.

**Connects.** After guard pass (§3.14). Terminal always continues to settlement (§3.16), including cancel at zero usage.

### 3.16 Terminal settlement

**Does.** Credits the Quota DO, journals attempts and money, and stores the envelope. Called from `createStreamBroker` sinks and from `settleCompletedRequest` / `settleTerminal` inside `runFreshEventSource`. Flutter does not call this.

**Cloudflare writes (order).**

1. Quota DO `kind=credit` (`creditUsage`) — `maybeResetPeriod`; add tokens/cost; `requestsUsed += 1`; `inFlight -= 1`; delete `admittedRequests[requestId]`; set `creditedRequests[requestId]` (expires +2 h); idempotency map → `completed` / `failed` / `cancelled`. `partial=true` for unavailable/timeout/cancelled.
2. D1 UPDATE `ai_request` (`state`, `completed_at`, `terminal_error_code`).
3. D1 INSERT `ai_attempt` (per provider attempt; ≥1 on Failed when attempts were recorded).
4. D1 INSERT `usage_event` (**always**, including cancel at `{tokens:0,cost:0}`).
5. R2 PUT `request/{request_id}/envelope` (`context`, `prompt`, `attempts` capped at 16 KiB each, `result`).
6. D1 UPDATE `ai_request.payload_pointer`.
7. Grace path only: attach usage on `grace_admission_queue`.

Pricing: `priceUsage()` from bundled `control/pricing/platform-default/1.json`. Cancel without provider usage estimates from streamed chars through the same helper.

**Supabase.** None.

**Connects.** After every terminal in §3.15. Feeds lookup (§3.17) and cron rollup/retention (§3.18). Idempotent replay of the same `x-idempotency-key` returns the stored terminal without a second credit.

### 3.17 Lookup, support, and clinical acceptance

#### 3.17.1 `GET /v1/requests/{request_reference}`

**Does.** Installation-scoped journal read, plus R2 `result` when completed.

**Caller of HTTP.** Any AAT holder in theory. **Flutter production `lib/` does not call this.** The clinic UX uses the SSE stream. The route is still a live Worker path (`authenticateGetRequest` → `getRequest`).

**Cloudflare.** Reads D1 `ai_request` by reference; R2 envelope only if `state=Completed` and `payload_pointer` set. Writes none. Other-installation hits return **404 empty** (no leak). Auth failures: `401 unauthenticated`, `403 installation_suspended`. Trailing slash `GET /v1/requests/` is 404 before auth.

#### 3.17.2 `POST /control/support/lookup?reference=`

**Does.** Cross-installation operator trace: request row, attempts, full envelope (or `null` if purged).

**Caller.** Operator → `handleSupportLookup` → `supportLookup`. Does **not** write `control_audit`.

**Cloudflare.** Reads D1 `ai_request`, `ai_attempt`; R2 envelope. Writes none.

#### 3.17.3 `public.record_ai_acceptance`

**Does.** Clinic-side human accept + provenance into the chart (registry key `visit_clinical_notes` → `save_visit_documentation`).

**Caller.** Intended: Flutter after SSE `completed`. Implemented: `ClinicalAcceptanceClient` / `ClinicalAcceptController` under `frontend/lib/features/ai/acceptance/`. **No presentation page imports them** (widget test asserts the live surface does not call the RPC).

**Cloudflare.** None. **Supabase.** INSERT acceptance/provenance + domain write.

**Connects.** After `completed`. Independent of D1; losing the platform journal does not undo a recorded acceptance, and recording acceptance does not settle the platform.

### 3.18 Cron

**Does.** Housekeeping the live path does not do inline. Caller: Cloudflare → `worker.scheduled`.

| When | Function | Cloudflare effect | Supabase |
| ---- | -------- | ----------------- | -------- |
| Every tick | `flushRejectionCounters` | Isolate tallies → D1 `platform_counter` (lower bound) | none |
| Every tick | `reconcileGraceUsage` | Drain `grace_admission_queue`: DO re-admit + credit attached usage; TTL/max-attempt → `status=dropped` (dropped rows no longer count toward the cap 5) | none |
| `0 3 * * *` | `runRetentionPurge` | `UPDATE usage_event SET request_id=NULL`; DELETE aged `ai_request` / `ai_attempt`; DELETE R2 envelopes (90-day journal horizon) | none |
| `0 4 * * *` | `runRollupAndReconciliation` | UPSERT `usage_rollup`; request-centric JOIN audit | none |

After retention, `GET /v1/requests/{ref}` and support lookup return 404. `usage_event` money rows remain but are unjoinable.

Local wrangler: `GET /cdn-cgi/handler/scheduled` fires this handler. That URL is not part of the platform contract.

---

## 4. Unused and orphaned implementations

These exist in source but have **no production caller** in the trees in §2. Tests, load harnesses, and wrangler hooks do not count as callers. Operator `/control/*` routes **are** used (operator is the caller) and are not listed here.

### 4.1 Implemented HTTP with no production client

| Surface | Status |
| ------- | ------ |
| `GET /v1/requests/{request_reference}` | Worker route is live. Flutter never calls it. Clinic results travel on the POST SSE stream |
| `POST /control/config-cache/flush` | **Not implemented.** Clients that probe it get 404 |

### 4.2 Implemented clinic RPCs with no Flutter caller

| RPC | Status |
| --- | ------ |
| `public.enroll_installation_keypair()` | Intended owner/admin; no Dart reference in `frontend/lib`. Vendor SQL today |
| `public.rotate_installation_key()` | Same |
| `public.revoke_installation_key(p_kid)` | Same |
| `public.record_ai_acceptance(...)` | `ClinicalAcceptanceClient` + `ClinicalAcceptController` exist; no page mounts them |
| Write path for `ai.availability` | **No RPC.** Flag is seeded and updated by SQL / intended future UI |
| `public.dev_reset_clinic_installation()` | Dev/test clinic wipe, not an AI-platform flow |

### 4.3 Worker modules with no HTTP or runtime caller

| Symbol | Module | Why orphaned |
| ------ | ------ | ------------ |
| `runAllDashboardQueries`, `dashboardAvgAttemptLatencyByProvider`, other `dashboard*` helpers | `src/dashboards/index.ts` | No route under `worker.fetch`. Tests only |
| `settleHappyPath` | `src/pipeline/index.ts` | Load-test shortcut. Production uses `runFreshEventSource` |
| `buildContextRequiredResponse` | `src/context/validator.ts` | Tests only; live `context_required` body omits `missing_keys` |
| `createStructuredStreamBroker` | `src/stream/structured.ts` | Structured-output capabilities are not in the published catalog (`clinic.visit_summary` is prose) |
| `validateAndRepair` | `src/validate/index.ts` | Called from the structured broker / tests, not the prose path |
| `listConversationLegs` | `src/journal/index.ts` | No HTTP exposure |
| `leakNeedleFromSystemInstruction` (singular) | `src/prompt/composer.ts` | Superseded by `leakNeedlesFromSystemInstruction`; tests only |
| `drainPendingGraceAdmissions`, `peekPendingGraceAdmissions` (sync drains) | `src/admission/index.ts` | Test/diagnostic. Production uses D1-backed list/mark helpers from cron |
| `drainDroppedGraceJournal`, `peekDroppedGraceJournal` | `src/credit/index.ts` | Test/diagnostic |
| `resetGraceAdmissionCounter` | `src/admission/index.ts` | No-op |

### 4.4 Flutter modules with no production mount

| Symbol | Status |
| ------ | ------ |
| `ConversationLoop` | `frontend/lib/core/ai/conversation_loop.dart` — unit tests only; visit summary is single-shot |
| `ClinicalAcceptanceClient` / `ClinicalAcceptController` | Implemented, unmounted (see §4.2) |

### 4.5 Storage with no control-plane writer

| Resource | Readers | Writer |
| -------- | ------- | ------ |
| D1 `kill_switch` | Guard stages 3 and 5; router `collectKilledProviderIds` | **No `/control/*` API.** Operators `INSERT` via SQL / `wrangler d1 execute` |

Absence of a writer does not make the **reads** unused: an inserted row is honored on the next invoke (after ConfigCache TTL).

### 4.6 Wired but policy-gated (not orphaned)

DeepSeek and Gemini adapters (`src/provider/deepseek.ts`, `gemini.ts`) are selected by `resolveProviderPort` when `selectCandidateChain` names those `provider_id`s. Local routing that targets `fake` never calls them. They are part of the §2.6 tree whenever a served policy says so.

---

## 5. Compact maps

### 5.1 HTTP surface

| Method | Path | Caller | Auth | Handler |
| ------ | ---- | ------ | ---- | ------- |
| GET | `/health` | Flutter reachability; probes | none | `worker.fetch` |
| GET | `/v1/capabilities` | Flutter `DiscoveryClient` | AAT | `handleDiscoveryRequest` |
| POST | `/v1/requests` | Flutter `PlatformHttpsSubmitPort` | AAT | `handleLivePostRequest` → `handleAdapterRequest` |
| GET | `/v1/requests/{ref}` | **none in Flutter** | AAT | `authenticateGetRequest` → `getRequest` |
| POST | `/control/installations/{id}/enroll` | Operator | operator bearer | `handleEnroll` |
| POST | `/control/installations/{id}/rotate` | Operator | operator bearer | `handleRotate` |
| POST | `/control/installations/{id}/revoke-key` | Operator | operator bearer | `handleRevokeKey` |
| POST | `/control/installations/{id}/suspend` | Operator | operator bearer | `handleSuspend` |
| POST | `/control/installations/{id}/resume` | Operator | operator bearer | `handleResume` |
| POST | `/control/installations/{id}/delete` | Operator | operator bearer | `handleDelete` |
| POST | `/control/installations/{id}/purge` | Operator | operator bearer | `handleInstallationPurge` |
| POST | `/control/installations/{id}/entitle` | Operator | operator bearer | `handleEntitle` |
| POST | `/control/capabilities/{id}/versions/{v}/activate` | Operator | operator bearer | `handleCohortActivate` |
| POST | `/control/capabilities/{id}/versions/{v}/promote` | Operator | operator bearer | `handleCohortPromote` |
| POST | `/control/capabilities/{id}/versions/{v}/deprecate` | Operator | operator bearer | `handleDeprecate` |
| POST | `/control/capabilities/{id}/versions/{v}/retire` | Operator | operator bearer | `handleRetire` |
| POST | `/control/routing-policies/{id}/versions/{v}/publish` | Operator | operator bearer | `handleRoutingPolicyPublish` |
| POST | `/control/routing-policies/{id}/versions/{v}/canary` | Operator | operator bearer | `handleRoutingPolicyCanary` |
| POST | `/control/routing-policies/{id}/versions/{v}/promote` | Operator | operator bearer | `handleRoutingPolicyPromote` |
| POST | `/control/routing-policies/{id}/versions/{v}/rollback` | Operator | operator bearer | `handleRoutingPolicyRollback` |
| POST | `/control/token-contract/begin-rotation` | Operator | operator bearer | `handleTokenContractBeginRotation` |
| POST | `/control/token-contract/retire` | Operator | operator bearer | `handleTokenContractRetire` |
| POST | `/control/support/lookup` | Operator | operator bearer | `handleSupportLookup` |

Anything else: `404 Not Found`. Control routes require POST; GET on `/control/*` is 404.

### 5.2 Clinic Supabase RPCs

| RPC | Caller | Platform involvement |
| --- | ------ | -------------------- |
| `enroll_installation_keypair()` | Owner/admin (no Flutter UI) | None; output copied into enroll HTTP |
| `rotate_installation_key()` | Owner/admin (no Flutter UI) | None; output copied into rotate HTTP |
| `revoke_installation_key(p_kid)` | Owner/admin (no Flutter UI) | None; pair with platform revoke-key |
| `get_ai_availability()` | Flutter `SupabaseAiAvailabilityReader` | None |
| `issue_ai_token()` | Flutter `SupabaseAatMintPort` | None at mint; AAT consumed on `/v1/*` |
| `get_visit_chief_complaint(p_visit_id)` | Flutter `SupabaseContextProviderPort` | None; value placed in POST body |
| `record_ai_acceptance(...)` | Unmounted Flutter client | None |

The Worker has **zero** outbound calls to Supabase.

### 5.3 Taxonomy to HTTP

Pre-SSE (guard / adapter) failures use HTTP status + JSON. Post-`accepted` failures use SSE `failed` with HTTP still 200.

| Code | When | HTTP (pre-SSE) | After `accepted` |
| ---- | ---- | -------------- | ---------------- |
| `unauthenticated` | Bad/expired/replayed AAT; deleted installation; retired token contract | 401 | — |
| `installation_suspended` | `installation.status=suspended` | 403 | — |
| `forbidden_capability` | Pending entitlement, plan, grant, scope, role | 403 | — |
| `capability_disabled` | Kill switch or manifest flag | 503 | — |
| `capability_unknown` / `capability_retired` | Registry miss / retired | 404 | — |
| `rate_limited` | Rate-limit bindings or grace cap | 429 + `retry_after` | — |
| `quota_exhausted` | DO period or concurrency | 429 | — |
| `request_too_large` | 1 MiB body or token estimate | 413 | — |
| `context_required` / `context_invalid` | Stage 6 | 422 | — |
| `conversation_budget_exhausted` | Conversational budget | 409 | — |
| `internal_error` | Compose/journal/missing policy/unexpected | 500 | SSE `failed` |
| `provider_unavailable` | Empty or exhausted chain | — | SSE `failed` |
| `provider_rejected` | Missing API key / provider 4xx mapped | — | SSE `failed` |
| `no_matching_rule` | Policy loaded, no rule | — | SSE `failed` |
| `validation_failed` | Prose output guards | — | SSE `failed` |
| `timeout` | Provider deadline | — | SSE `failed` |
| `cancelled` | Client abort | — | SSE `cancelled` |

Control plane uses `{ "error": "<code>" }` (`unauthorized`, `already_enrolled`, `not_pending`, `illegal_lifecycle_transition`, …) and must not be parsed as taxonomy.

---

End of flow. Field dictionaries: [16 D1 columns](data-journey/16-complete-d1-column-reference.md), [17 R2 objects](data-journey/17-complete-r2-object-reference.md), [18 Quota DO state](data-journey/18-quota-durable-object-state-reference.md). Source index: [20](data-journey/20-source-file-index.md).
