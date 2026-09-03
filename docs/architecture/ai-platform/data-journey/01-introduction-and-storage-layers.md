# AI Platform Data Journey

- Purpose: Trace **every field** of data as it moves through the AI platform — from first configuration through enrollment, entitlements, contracts, routing, live AI requests, and settlement in D1, R2, and the Quota Durable Object.
- Read this when: you are learning the platform and want to understand **what each value means, where it came from, and why a path succeeded or failed** — not just which HTTP endpoint to call.
- Canonical for: nothing. This is a **data-field companion** derived from `ai-platform/src/`**, `ai-platform/migrations/`**, `backend/supabase/migrations/**`, and `ai-platform/manifests/**`.
- Related docs: [09-ai-platform-request-response-flow.md](../09-ai-platform-request-response-flow.md) (canonical request/response call hierarchy), [06-ai-platform-behavioral-journey.md](../06-ai-platform-behavioral-journey.md) (stage behavior), [07-ai-platform-d1-r2-storage.md](../07-ai-platform-d1-r2-storage.md) (storage tables), [01-ai-platform.md](../01-ai-platform.md) (architecture decisions).

---

## Table of Contents

1. [How to read this document](#1-how-to-read-this-document)
  - [1.1 What you will find in each stage](#11-what-you-will-find-in-each-stage)
  - [1.2 Three meanings of "contract"](#12-three-meanings-of-contract)
  - [1.3 Field notation](#13-field-notation)
2. [The master data map](#2-the-master-data-map)
3. [Storage layers — filing cabinet, warehouse, and live ledger](#3-storage-layers-filing-cabinet-warehouse-and-live-ledger)
  - [3.1 D1 — the filing cabinet (`DB` binding)](#31-d1-the-filing-cabinet-db-binding)
  - [3.2 R2 — the warehouse (`R2` binding)](#32-r2-the-warehouse-r2-binding)
  - [3.3 Quota Durable Object — the live ledger (`DO` binding)](#33-quota-durable-object-the-live-ledger-do-binding)
  - [3.4 Bundled artifacts — the product catalog (neither D1 nor R2)](#34-bundled-artifacts-the-product-catalog-neither-d1-nor-r2)
  - [3.5 Config cache — 30-second reading glasses](#35-config-cache-30-second-reading-glasses)
4. [Behavioral verification](#4-behavioral-verification)
  - [4.1 Setup](#41-setup)
  - [4.2 Coverage](#42-coverage)
  - [4.3 Ordered probes](#43-ordered-probes)
    - [4.3.1 Reset local D1](#431-reset-local-d1)
    - [4.3.2 Bindings, vars, secrets, and Worker boot](#432-bindings-vars-secrets-and-worker-boot)
    - [4.3.3 D1 filing cabinet shape](#433-d1-filing-cabinet-shape)
    - [4.3.4 Bundled artifacts are not D1 or R2](#434-bundled-artifacts-are-not-d1-or-r2)
    - [4.3.5 Control bearer, enroll, and shared OPERATOR_ID](#435-control-bearer-enroll-and-shared-operator_id)
    - [4.3.6 Discovery reads D1, not R2](#436-discovery-reads-d1-not-r2)
    - [4.3.7 Guard finishes before accepted](#437-guard-finishes-before-accepted)
    - [4.3.8 Entitle, in-memory catalog, pricing not on the wire](#438-entitle-in-memory-catalog-pricing-not-on-the-wire)
    - [4.3.9 Routing is not a guard gate](#439-routing-is-not-a-guard-gate)
    - [4.3.10 Publish, canary, promote: R2 document, D1 pointer](#4310-publish-canary-promote-r2-document-d1-pointer)
    - [4.3.11 Terminal settlement: Quota DO, D1 ledger, R2 envelope](#4311-terminal-settlement-quota-do-d1-ledger-r2-envelope)
    - [4.3.12 JTI replay, idempotency, and GET journal](#4312-jti-replay-idempotency-and-get-journal)
    - [4.3.13 Config cache TTL, plan grant key, no flush API](#4313-config-cache-ttl-plan-grant-key-no-flush-api)
    - [4.3.14 Kill-switch cache keys](#4314-kill-switch-cache-keys)
    - [4.3.15 Token-contract cache key](#4315-token-contract-cache-key)

---

## 1. How to read this document



### 1.1 What you will find in each stage

Every stage section follows the same recipe:

1. **Plain language** — what we are doing and why, without jargon first.
2. **Metaphor** — a mental model (airport, passport office, filing cabinet).
3. **Data entering** — every field, where it came from.
4. **Data leaving** — every field produced, who consumes it next.
5. **Storage writes** — exact D1 rows, R2 keys, or DO keys touched.
6. **Happy path** — ASCII diagram of success.
7. **Other paths** — every branch, which **input field** caused it, and the **error code** returned.



### 1.2 Three meanings of “contract”

The word **contract** appears in three different places. Do not mix them up:


| Name                             | Where it lives                                      | What it governs                                                   |
| -------------------------------- | --------------------------------------------------- | ----------------------------------------------------------------- |
| **Token contract**               | D1 `token_contract`                                 | Which AAT `ver` claim values the platform accepts                 |
| **Capability manifest**          | Bundled JSON in the Worker (`manifests/published/`) | What a product feature (e.g. visit summary) requires and produces |
| **Canonical inference contract** | TypeScript types (`contracts/canonical.ts`)         | How the gateway talks to DeepSeek/Gemini internally               |




### 1.3 Field notation

- **Wire** = HTTP header or JSON body on the network.
- **D1** = SQLite row column in Cloudflare D1.
- **R2** = object key and JSON document in Cloudflare R2.
- **DO** = Durable Object in-memory + persisted state.
- **Principal** = verified identity extracted from a valid AAT.

---



## 2. The master data map

Read this once. The rest of the document unpacks every box.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ CONFIGURE (no clinic data yet)                                              │
│  wrangler.toml → bindings: DB, R2, DO, rate limiters, crons, vars, secrets  │
│  D1 migrations → 14 tables + seed token_contract ver='1'                    │
│  Worker boot → in-memory registry: clinic.visit_summary@1.0.0               │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ CLINIC TRUST (Supabase PostgreSQL)                                          │
│  enroll / rotate / revoke_installation_keypair → installation_keys          │
│  get_ai_availability → { enrolled, platform_base_url }                      │
│  get_visit_chief_complaint → context for visit.chief_complaint@v1           │
│  record_ai_acceptance → human accept + provenance row                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │ public_jwk.x, kid, installation_id
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ CONTROL PLANE — `/control/*` (Bearer OPERATOR_BEARER_TOKEN)                 │
│  Single shared bearer + OPERATOR_ID: control_audit cannot distinguish ops   │
│  POST …/enroll  → D1: installation, installation_key, entitlement(pending)  │
│  POST …/rotate / revoke-key / suspend / resume / delete / purge             │
│  POST …/entitle → D1: entitlement(active), capability_grant, control_audit  │
│  POST …/capabilities/…/activate / promote / deprecate / retire                │
│  POST …/routing-policies/…/publish / canary / promote / rollback            │
│  POST …/token-contract/begin-rotation / retire                              │
│  POST …/support/lookup                                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ CLINIC MINT (Supabase)                                                      │
│  issue_ai_token → signed JWS (AAT) + ai_token_issuance row per jti          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │ Authorization: Bearer <AAT>
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ RUNTIME /v1/*                                                               │
│  GET /v1/capabilities → reads D1 entitlement + grants (no R2)               │
│  POST /v1/requests:                                                         │
│    preAccept = guard 1–10 → D1 ai_request INSERT (fresh path)               │
│    SSE accepted → preload routing (D1 + R2) → invoke providers            │
│    terminal → credit Quota DO + D1 attempts/usage + R2 envelope             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Two facts that confuse newcomers:**

1. The **guard finishes before** `accepted`. A rejected caller never opens an SSE stream.
2. **Routing is not a guard gate**. A request can pass the guard, receive `accepted`, then fail at invoke because no active routing policy exists.

---



## 3. Storage layers — filing cabinet, warehouse, and live ledger



### 3.1 D1 — the filing cabinet (`DB` binding)

Structured rows you can query. Holds identity, entitlements, request journal summaries, billing ledger, audit log, and routing **indexes** (not full routing documents).

**Rule:** D1 stores **index cards**. Large JSON lives in R2; D1 holds a pointer column.

### 3.2 R2 — the warehouse (`R2` binding)

Large JSON blobs:


| Pattern                                             | Contents                                                           |
| --------------------------------------------------- | ------------------------------------------------------------------ |
| `control/routing-policy/{policy_id}/{version}.json` | Full routing policy document                                       |
| `request/{request_id}/envelope`                     | Per-request diagnostic package (context, prompt, attempts, result) |




### 3.3 Quota Durable Object — the live ledger (`DO` binding)

One `GatewayObject` instance per `installation_id` (addressed via `DO.idFromName(installationId)`).

Holds **ephemeral, high-churn** state that must be consistent per installation:

- Period counters (requests, tokens, cost used)
- In-flight concurrency count
- JTI replay map (AAT `jti` claim)
- Idempotency map (`x-idempotency-key` header)
- Admitted / credited request tracking

**Not in D1:** live quota enforcement happens here first; D1 `usage_event` is the durable ledger after completion.

### 3.4 Bundled artifacts — the product catalog (neither D1 nor R2)

Deployed with the Worker:


| Path                                                  | Role                                |
| ----------------------------------------------------- | ----------------------------------- |
| `manifests/published/clinic.visit_summary@1.0.0.json` | Capability manifest                 |
| `context/shapes/published/visit.chief_complaint@v1.json` | Context key shape (field names, types, cardinality, units — [01-ai-platform.md §5.2](../01-ai-platform.md#52-context-contract)); immutable per key version |
| `prompts/clinic.visit_summary/*.md`                   | System, rules, template prompt text |
| `control/pricing/platform-default/1.json`             | Post-response model price table (input/output per 1K tokens). Bundled, never client-visible. Money is applied only at settlement from provider-reported tokens (§13.6.2). |




### 3.5 Config cache — 30-second reading glasses

Before most D1 reads, `config-cache` may return a cached copy (TTL `30_000` ms). Production uses
**one `ConfigCache` instance per Worker isolate** (`isolateConfigCache`) — isolate-local memory,
not a store. `createProductionPreAccept` (`POST /v1/requests`), `authenticateGetRequest`
(`GET /v1/requests/{ref}`), invoke-path routing, and discovery share that instance, so the TTL
dedupes installation, key, entitlement, grant, kill-switch, token-contract, and policy reads
**across requests** in a warm isolate. Tests inject `new ConfigCache()` so they stay isolated.
D1 updates become visible after TTL expiry (≤30 s); there is no flush API. Cache keys:



| Kind                    | Key pattern                                                          | D1 table              |
| ----------------------- | -------------------------------------------------------------------- | --------------------- |
| `installations`         | `{installation_id}`                                                  | `installation`        |
| `keys`                  | `{key_id}`                                                           | `installation_key`    |
| `entitlements`          | `{installation_id}`                                                  | `entitlement`         |
| `grants`                | `{installation_id}/{capability_id}` or `plan:{plan}/{capability_id}` | `capability_grant`    |
| `kill_switches`         | `global` or `{scope}:{target}`                                       | `kill_switch`         |
| `token_contracts`       | `{ver}`                                                              | `token_contract`      |
| `active_routing_policy` | `{policyRef}` or `{policyRef}/{installationId}`                      | `routing_policy` + R2; canary-then-active, `ORDER BY active_from DESC, rowid DESC` |


---

## 4. Behavioral verification

Live probes against a throwaway local Worker (and local clinic Supabase from [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id) onward). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§4.3](#43-ordered-probes) top to bottom**. If every probe matches, this document’s storage-layer claims are working.

Wording in this file vs the wire:

- Control-plane auth failure is JSON `{ "error": "unauthorized" }` (HTTP 401), not a taxonomy `code`.
- Pending entitlement is path `ai_disabled` in Worker logs; the client sees taxonomy **`forbidden_capability`**.
- JTI replay is Quota DO outcome `replay`, mapped to **`unauthenticated`**.
- Missing active/canary routing after `accepted` throws `ConfigCacheMissError` on preload; the SSE terminal is **`failed` / `internal_error`** (not a dedicated routing code).
- Enroll `plan` must be a known tier (`starter` / `standard` / `professional` / `enterprise`); unknown values are rejected at enroll with `400 invalid_payload`. Visit summary’s `minimumPlanTier` is `standard` — use **`standard`**, not an invented plan id.
- `OPERATOR_ID` in `wrangler.toml` is `platform-operator`. D1 grant `scope` is `installation:{id}` or `plan:{plan}`; the cache key for an installation grant is `{installation_id}/{capability_id}`.

### 4.1 Setup

- Throwaway local Worker. Prefer a D1 you can wipe. Keep **`npm run dev` running** for the whole of [§4.3](#43-ordered-probes) (the config-cache probes need a warm isolate). Do not restart the Worker during [§4.3.13](#4313-config-cache-ttl-plan-grant-key-no-flush-api)–[§4.3.15](#4315-token-contract-cache-key).
- From `ai-platform/`:

```bash
nvm use
cd ai-platform
npm install
npx wrangler d1 migrations apply ai-platform-development --local --env development
# OPERATOR_BEARER_TOKEN lives in `.dev.vars` / `.dev.vars.development` (not wrangler.toml)
npm run dev
# → http://127.0.0.1:8787
```

- In a second shell:

```bash
cd ai-platform
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'   # same value as `.dev.vars`; do not commit it

d1() {
  npx wrangler d1 execute ai-platform-development --local --env development --command "$1"
}
```

- Local clinic Supabase with AI migrations applied (keypair RPC + `issue_ai_token`). You will wipe `ai_internal.installation_keys` / `ai_token_issuance`. Owner or administrator session to enroll the keypair; a staff session with at least one `ai.*` RBAC permission to mint AATs.
- Clinic `organizations.id` for the enroll body. Visit-summary POSTs need `context.org` / `context.branch` equal to the AAT `org` / `branch` claims.
- No provider API keys are required: [§4.3.10](#4310-publish-canary-promote-r2-document-d1-pointer) publishes a `fake` / `fake-v1` routing policy so invoke stays on the Worker.
- Wrangler has no first-class “dump Quota DO storage” command. Live quota is observed through HTTP + D1 `usage_event`, not by reading Durable Object SQLite.

### 4.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Token contract lives in D1 `token_contract` | [§4.3.3](#433-d1-filing-cabinet-shape), [§4.3.15](#4315-token-contract-cache-key) |
| Capability manifest is bundled JSON (`manifests/published/`), not D1/R2 | [§4.3.2](#432-bindings-vars-secrets-and-worker-boot), [§4.3.4](#434-bundled-artifacts-are-not-d1-or-r2), [§4.3.8](#438-entitle-in-memory-catalog-pricing-not-on-the-wire) |
| Context key shapes are bundled JSON (`context/shapes/published/`); shape schema and validation frozen in `src/context/index.ts` | [§4.3.2](#432-bindings-vars-secrets-and-worker-boot), [§4.3.4](#434-bundled-artifacts-are-not-d1-or-r2) |
| Canonical inference contract is TypeScript `contracts/canonical.ts` | [§4.3.2](#432-bindings-vars-secrets-and-worker-boot) |
| `wrangler.toml` bindings: `DB`, `R2`, `DO`, rate limiters, crons, vars | [§4.3.2](#432-bindings-vars-secrets-and-worker-boot) |
| Secrets are not in `wrangler.toml` (`OPERATOR_BEARER_TOKEN` via `.dev.vars`) | [§4.3.2](#432-bindings-vars-secrets-and-worker-boot), [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id) |
| D1 migrations: 14 application tables + seed `token_contract ver='1'` | [§4.3.3](#433-d1-filing-cabinet-shape) |
| Worker boot registry `clinic.visit_summary@1.0.0` | [§4.3.2](#432-bindings-vars-secrets-and-worker-boot), [§4.3.8](#438-entitle-in-memory-catalog-pricing-not-on-the-wire) |
| Clinic keypair is minted in Supabase; platform enroll copies `public_jwk.x` + `kid` | [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id) |
| Clinic `ai.availability` is not written by platform enroll | [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id) |
| Control plane: Bearer `OPERATOR_BEARER_TOKEN`; missing/wrong token → 401 | [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id) |
| Single shared bearer + `OPERATOR_ID`: `control_audit` cannot distinguish operators | [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id), [§4.3.8](#438-entitle-in-memory-catalog-pricing-not-on-the-wire) |
| `POST …/enroll` → D1 `installation`, `installation_key`, `entitlement(pending)` | [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id) |
| `POST …/entitle` → D1 `entitlement(active)`, `capability_grant`, `control_audit` | [§4.3.8](#438-entitle-in-memory-catalog-pricing-not-on-the-wire) |
| `POST …/routing-policies/…/publish` → R2 policy JSON + D1 `routing_policy` index | [§4.3.10](#4310-publish-canary-promote-r2-document-d1-pointer) |
| `POST …/canary` / `promote` → D1 `routing_policy` status transitions | [§4.3.10](#4310-publish-canary-promote-r2-document-d1-pointer) |
| Clinic mint: `issue_ai_token` → JWS + `ai_token_issuance` row | [§4.3.6](#436-discovery-reads-d1-not-r2) |
| `GET /v1/capabilities` reads D1 entitlement + grants (no R2) | [§4.3.6](#436-discovery-reads-d1-not-r2), [§4.3.8](#438-entitle-in-memory-catalog-pricing-not-on-the-wire) |
| Guard finishes **before** `accepted`; rejected caller never opens SSE | [§4.3.7](#437-guard-finishes-before-accepted) |
| Fresh `POST /v1/requests` inserts D1 `ai_request` on the success path | [§4.3.9](#439-routing-is-not-a-guard-gate) |
| Routing is **not** a guard gate: `accepted` then fail with no active/canary policy | [§4.3.9](#439-routing-is-not-a-guard-gate) |
| D1 holds identity, entitlements, journal summaries, billing ledger, audit, routing **indexes** | [§4.3.3](#433-d1-filing-cabinet-shape), [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id), [§4.3.8](#438-entitle-in-memory-catalog-pricing-not-on-the-wire), [§4.3.10](#4310-publish-canary-promote-r2-document-d1-pointer), [§4.3.11](#4311-terminal-settlement-quota-do-d1-ledger-r2-envelope) |
| D1 stores **index cards**; large JSON lives in R2; D1 holds a pointer | [§4.3.10](#4310-publish-canary-promote-r2-document-d1-pointer), [§4.3.11](#4311-terminal-settlement-quota-do-d1-ledger-r2-envelope) |
| R2 `control/routing-policy/{policy_id}/{version}.json` | [§4.3.10](#4310-publish-canary-promote-r2-document-d1-pointer) |
| R2 `request/{request_id}/envelope` (context, prompt, attempts, result) | [§4.3.11](#4311-terminal-settlement-quota-do-d1-ledger-r2-envelope) |
| One `GatewayObject` per `installation_id` (`DO` binding, `class_name = GatewayObject`) | [§4.3.2](#432-bindings-vars-secrets-and-worker-boot), [§4.3.12](#4312-jti-replay-idempotency-and-get-journal) |
| Quota DO: period counters, JTI map, idempotency map, admitted/credited tracking | [§4.3.11](#4311-terminal-settlement-quota-do-d1-ledger-r2-envelope), [§4.3.12](#4312-jti-replay-idempotency-and-get-journal), [§4.3.14](#4314-kill-switch-cache-keys) |
| Live quota is **not** a D1 table; `usage_event` is the durable ledger after completion | [§4.3.3](#433-d1-filing-cabinet-shape), [§4.3.11](#4311-terminal-settlement-quota-do-d1-ledger-r2-envelope) |
| Prompts `prompts/clinic.visit_summary/*.md` bundled, not D1/R2 | [§4.3.2](#432-bindings-vars-secrets-and-worker-boot), [§4.3.4](#434-bundled-artifacts-are-not-d1-or-r2) |
| Pricing table bundled, never client-visible; money from provider-reported tokens at settlement | [§4.3.4](#434-bundled-artifacts-are-not-d1-or-r2), [§4.3.8](#438-entitle-in-memory-catalog-pricing-not-on-the-wire), [§4.3.11](#4311-terminal-settlement-quota-do-d1-ledger-r2-envelope) |
| Config cache TTL `30_000` ms; one isolate instance; no flush API | [§4.3.13](#4313-config-cache-ttl-plan-grant-key-no-flush-api) |
| `POST /v1/requests`, `GET /v1/requests/{ref}`, invoke routing, and discovery share that cache | [§4.3.13](#4313-config-cache-ttl-plan-grant-key-no-flush-api), [§4.3.12](#4312-jti-replay-idempotency-and-get-journal) |
| Cache kind `installations` / `keys` | [§4.3.6](#436-discovery-reads-d1-not-r2), [§4.3.13](#4313-config-cache-ttl-plan-grant-key-no-flush-api) |
| Cache kind `entitlements` | [§4.3.6](#436-discovery-reads-d1-not-r2), [§4.3.13](#4313-config-cache-ttl-plan-grant-key-no-flush-api) |
| Cache kind `grants` (`{installation_id}/{capability_id}` and `plan:{plan}/{capability_id}`) | [§4.3.8](#438-entitle-in-memory-catalog-pricing-not-on-the-wire), [§4.3.13](#4313-config-cache-ttl-plan-grant-key-no-flush-api) |
| Cache kind `kill_switches` (`global` or `{scope}:{target}`) | [§4.3.14](#4314-kill-switch-cache-keys) |
| Cache kind `token_contracts` (`{ver}`) | [§4.3.15](#4315-token-contract-cache-key) |
| Cache kind `active_routing_policy` (`{policyRef}` or `{policyRef}/{installationId}`); canary-then-active; `ORDER BY active_from DESC, rowid DESC` | [§4.3.10](#4310-publish-canary-promote-r2-document-d1-pointer) |
| Field notation (Wire / D1 / R2 / DO / Principal) and the per-stage recipe in [§1.1](#11-what-you-will-find-in-each-stage) | Documentation convention — no runtime probe |
| Tests inject `new ConfigCache()` | Not an operator HTTP path; production is `isolateConfigCache` ([§4.3.13](#4313-config-cache-ttl-plan-grant-key-no-flush-api) observes the shared isolate) |
| In-flight concurrency count (DO limit 16) | Not exercised: `FakeAdapter` completes immediately, so 16 overlapping admissions are not observable here. D1 has no `in_flight` column ([§4.3.3](#433-d1-filing-cabinet-shape)) |
| `DO.idFromName(installationId)` addressing | No Wrangler dump of DO ids. Proved indirectly: JTI/idempotency state is per this installation ([§4.3.12](#4312-jti-replay-idempotency-and-get-journal)) and `wrangler.toml` binds `DO` → `GatewayObject` ([§4.3.2](#432-bindings-vars-secrets-and-worker-boot)) |


### 4.3 Ordered probes

#### 4.3.1 Reset local D1

**Do:** with the Worker already migrated, as the D1 command helper from [§4.1](#41-setup):

```bash
d1 "DELETE FROM ai_attempt;"
d1 "DELETE FROM usage_event;"
d1 "DELETE FROM grace_admission_queue;"
d1 "DELETE FROM ai_request;"
d1 "DELETE FROM capability_grant;"
d1 "DELETE FROM control_audit;"
d1 "DELETE FROM entitlement;"
d1 "DELETE FROM installation_key;"
d1 "DELETE FROM kill_switch;"
d1 "DELETE FROM platform_counter;"
d1 "DELETE FROM routing_policy;"
d1 "DELETE FROM usage_rollup;"
d1 "DELETE FROM installation;"
d1 "DELETE FROM token_contract;"
d1 "INSERT INTO token_contract (ver, added_at, retired_at, changed_by) VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed');"
```

On the throwaway clinic, as `postgres`:

```sql
DELETE FROM ai_internal.ai_token_issuance;
DELETE FROM ai_internal.installation_keys;
```

**Expect:** D1 clinic tables empty except the seeded `token_contract` row (next probe). Clinic keystore empty. Leftover local R2 objects from older runs may still exist; later probes use new `request_id`s and will overwrite a republished policy key.

#### 4.3.2 Bindings, vars, secrets, and Worker boot

**Do:**

```bash
curl -sS "$GATEWAY/health"
grep -nE 'binding = "DB"|binding = "R2"|name = "DO"|class_name = "GatewayObject"|RATE_LIMITER_|crons|OPERATOR_ID|OPERATOR_BEARER_TOKEN|BUILD_SHA|ENVIRONMENT' wrangler.toml
test -f manifests/published/clinic.visit_summary@1.0.0.json \
  && test -f prompts/clinic.visit_summary/system.md \
  && test -f prompts/clinic.visit_summary/rules-visit-summary.md \
  && test -f prompts/clinic.visit_summary/template-visit-summary.md \
  && test -f control/pricing/platform-default/1.json \
  && test -f src/contracts/canonical.ts \
  && echo artifacts_ok
```

**Expect:** `/health` is HTTP 200 `{ "build": "local", "environment": "development" }` (`BUILD_SHA` / `ENVIRONMENT` from `[env.development.vars]`). `wrangler.toml` declares `DB`, `R2`, `DO` with `class_name = "GatewayObject"`, the three `RATE_LIMITER_*` bindings, `crons = ["0 3 * * *", "0 4 * * *"]`, and `OPERATOR_ID = "platform-operator"`. `OPERATOR_BEARER_TOKEN` does **not** appear in `wrangler.toml`. All six `test -f` paths exist (`artifacts_ok`). The canonical contract is the TypeScript module providers import; it is not a D1/R2 document.

**Do:** `curl -sS -o /dev/null -w '%{http_code}\n' "$GATEWAY/v1/capabilities"`

**Expect:** HTTP 401 (no Bearer). The Worker is serving; the in-memory registry is not a public unauthenticated catalog.

#### 4.3.3 D1 filing cabinet shape

**Do:**

```bash
d1 "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' AND name != 'd1_migrations' ORDER BY name;"
d1 "SELECT ver, added_at, retired_at, changed_by FROM token_contract;"
d1 "SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE '%jti%' OR name LIKE '%quota%' OR name LIKE '%idempotenc%' OR name LIKE '%in_flight%' OR name LIKE '%inflight%');"
d1 "SELECT sql FROM sqlite_master WHERE name IN ('routing_policy','ai_request');"
```

**Expect:** exactly these **14** application tables (plus Wrangler’s `d1_migrations` bookkeeping, which this query excludes): `ai_attempt`, `ai_request`, `capability_grant`, `control_audit`, `entitlement`, `grace_admission_queue`, `installation`, `installation_key`, `kill_switch`, `platform_counter`, `routing_policy`, `token_contract`, `usage_event`, `usage_rollup`.

Seed row: `ver = '1'`, `added_at = '2026-08-03T00:00:00.000Z'`, `retired_at` NULL, `changed_by = 'seed'`.

No table named for JTI, live quota, idempotency, or in-flight concurrency — those live in the Quota DO. `routing_policy` has `content_pointer`; `ai_request` has `payload_pointer`. Those are index-card columns, not the JSON blobs.

#### 4.3.4 Bundled artifacts are not D1 or R2

**Do:**

```bash
d1 "SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE '%manifest%' OR name LIKE '%prompt%' OR name LIKE '%pricing%');"
npx wrangler r2 object get ai-platform-development \
  "manifests/published/clinic.visit_summary@1.0.0.json" --file /tmp/vs-manifest.json --local
npx wrangler r2 object get ai-platform-development \
  "control/pricing/platform-default/1.json" --file /tmp/pricing.json --local
npx wrangler r2 object get ai-platform-development \
  "prompts/clinic.visit_summary/system.md" --file /tmp/system.md --local
```

**Expect:** no D1 tables for manifest / prompt / pricing. Each `r2 object get` **fails** (object not found). The product catalog and price table are Worker-bundled; they are not warehouse objects.

#### 4.3.5 Control bearer, enroll, and shared OPERATOR_ID

**Do:** as clinic **owner or administrator**:

```sql
SELECT public.enroll_installation_keypair();
```

Save `installation_id` as **I0**, `kid` as **K0**, `public_jwk.x` as **X0**. Look up clinic `organizations.id` as **ORG**.

**Do:** export `INSTALLATION_ID` / `ORG_ID` / `X0` / `K0` from the RPC, then:

```bash
curl -sS -D - -o /tmp/enroll-noauth.json -X POST \
  "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H 'Content-Type: application/json' \
  -d '{"org_id":"x"}'

curl -sS -D - -o /tmp/enroll-bad.json -X POST \
  "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer not-the-operator-token" \
  -H 'Content-Type: application/json' \
  -d '{"org_id":"x","display_name":"x","region":"x","plan":"standard","public_key":"x","algorithm":"EdDSA","kid":"x"}'
```

**Expect:** both HTTP **401**, body `{ "error": "unauthorized" }`. No D1 `installation` row.

**Do:** (set `INSTALLATION_ID` to **I0**)

```bash
curl -sS -D - -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{
    \"org_id\": \"$ORG_ID\",
    \"display_name\": \"Storage probe clinic\",
    \"region\": \"local\",
    \"plan\": \"standard\",
    \"public_key\": \"$X0\",
    \"algorithm\": \"EdDSA\",
    \"kid\": \"$K0\"
  }"
```

**Expect:** HTTP 200 `{ "platform_base_url": "http://127.0.0.1:8787" }` (the origin you posted to).

**Do:** as any authenticated clinic staff, `SELECT public.get_ai_availability();`

**Expect:** still `{ "enrolled": false, "platform_base_url": null }` (or whatever you had before). Platform enroll does **not** write clinic `ai.availability`.

**Do:**

```bash
d1 "SELECT installation_id, org_id, status FROM installation;"
d1 "SELECT key_id, installation_id, public_key, algorithm, revoked_at FROM installation_key;"
d1 "SELECT installation_id, plan, status, request_quota, token_budget, cost_budget, allowed_capabilities FROM entitlement;"
d1 "SELECT operator_id, action, target FROM control_audit;"
npx wrangler r2 object get ai-platform-development \
  "control/routing-policy/standard/1.json" --file /tmp/rp-before.json --local
```

**Expect:** one `installation` row (`installation_id = I0`, `status = active`). One `installation_key` (`key_id = K0`, `public_key = X0`, `algorithm = EdDSA`, `revoked_at` NULL). One `entitlement` (`plan = standard`, `status = pending`, quotas `0`, `allowed_capabilities = []`). `control_audit` has `action = enroll`, `operator_id = platform-operator` (the var, not the bearer secret). R2 still has **no** routing-policy object — enroll writes D1 only.

#### 4.3.6 Discovery reads D1, not R2

**Do:** as staff with `ai.*`, `SELECT public.issue_ai_token();`

**Expect:** a compact JWS (three `.`-separated segments). Clinic `ai_internal.ai_token_issuance` has a new row for that `jti`. Decode header/payload (base64url): header `kid = K0`, payload `iss = I0`, `aud = ai-platform`, `ver = "1"`, `org` and `branch` present. Save the token as **AAT0**. Save `org` / `branch` as **ORG_CLAIM** / **BRANCH_CLAIM**.

**Do:**

```bash
curl -sS -D - "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT0"
```

**Expect:** HTTP 200 `{ "manifests": [] }`. Entitlement is still `pending`, so discovery returns no catalog. This call must succeed with R2 empty of routing objects ([§4.3.4](#434-bundled-artifacts-are-not-d1-or-r2) / [§4.3.5](#435-control-bearer-enroll-and-shared-operator_id)) — discovery is D1 entitlement + grants (+ identity), not the warehouse.

**Do:** `curl -sS -D - "$GATEWAY/v1/capabilities"` (no Authorization).

**Expect:** HTTP **401**, JSON taxonomy `{ "code": "unauthenticated", "request_reference": "…", "trace_id": "…", "retry_safe": true }`.

#### 4.3.7 Guard finishes before accepted

**Do:**

```bash
curl -sS -D - -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT0" \
  -H 'Content-Type: application/json' \
  -H 'x-idempotency-key: probe-guard-pending' \
  -H 'x-capability-version: 1.0.0' \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"$ORG_CLAIM\",
      \"branch\": \"$BRANCH_CLAIM\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
```

**Expect:** HTTP **403**, `Content-Type: application/json` (not `text/event-stream`). Body `code = forbidden_capability` (pending entitlement / `ai_disabled`). **No** `event: accepted` line. The guard finished before SSE.

**Do:** `d1 "SELECT COUNT(*) AS n FROM ai_request;"`

**Expect:** `n = 0`. Fresh-path journal INSERT happens only after the guard admits.

#### 4.3.8 Entitle, in-memory catalog, pricing not on the wire

**Do:**

```bash
curl -sS -D - -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "period_start": "2026-08-01T00:00:00.000Z",
    "period_end": "2026-12-01T00:00:00.000Z",
    "request_quota": 5,
    "token_budget": 100000,
    "cost_budget": 100,
    "soft_threshold": 0.8,
    "allowed_capabilities": ["clinic.visit_summary"],
    "grants": [
      {
        "capability_id": "clinic.visit_summary",
        "capability_version": "1.0.0",
        "scope": "installation"
      },
      {
        "capability_id": "clinic.visit_summary",
        "capability_version": "1.0.0",
        "scope": "plan"
      }
    ]
  }'
```

**Expect:** HTTP 200 `{ "installation_id": "<I0>", "status": "active" }`. Wait **31 seconds** so the isolate drops the `pending` entitlement cached in [§4.3.6](#436-discovery-reads-d1-not-r2).

**Do:**

```bash
d1 "SELECT status, request_quota, allowed_capabilities FROM entitlement WHERE installation_id = '$INSTALLATION_ID';"
d1 "SELECT scope, capability_id, capability_version, revoked_at FROM capability_grant ORDER BY scope;"
d1 "SELECT operator_id, action FROM control_audit ORDER BY recorded_at;"
curl -sS "$GATEWAY/v1/capabilities" -H "Authorization: Bearer $AAT0" | tee /tmp/capabilities.json
python3 - <<'PY'
import json
doc=json.load(open("/tmp/capabilities.json"))
text=json.dumps(doc)
assert "input_per_1k" not in text and "pricing_id" not in text
m=doc["manifests"]
assert len(m)==1
ident=m[0]["Identity"]
assert ident["capabilityId"]=="clinic.visit_summary" and ident["version"]=="1.0.0"
print("catalog_ok")
PY
```

**Expect:** entitlement `status = active`, `request_quota = 5`, `allowed_capabilities` includes `clinic.visit_summary`. Two grant rows: `scope = installation:<I0>` and `scope = plan:standard`, both `clinic.visit_summary` / `1.0.0`, `revoked_at` NULL. `control_audit` has both `enroll` and `entitle` with the **same** `operator_id = platform-operator`. Discovery JSON has exactly one manifest, `Identity.capabilityId = clinic.visit_summary`, `version = 1.0.0` (the boot registry). The body must **not** contain `input_per_1k` or `pricing_id` — the price table is not client-visible. `catalog_ok`.

That manifest was not inserted into D1; D1 only has grant/entitlement index cards.

#### 4.3.9 Routing is not a guard gate

Do **not** publish a routing policy yet.

**Do:**

```bash
curl -sS -N -D - -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT0" \
  -H 'Content-Type: application/json' \
  -H 'x-idempotency-key: probe-no-routing' \
  -H 'x-capability-version: 1.0.0' \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"$ORG_CLAIM\",
      \"branch\": \"$BRANCH_CLAIM\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
```

**Expect:** HTTP **200**, `Content-Type: text/event-stream`. First event:

```
event: accepted
data: {"request_reference":"XXXX-XXXX","trace_id":"…"}
```

Then a terminal:

```
event: failed
data: {… "code":"internal_error" …}
```

(`preloadRoutingPolicyForInstallation` misses D1+R2 and the event-source catch maps that to `internal_error`.) The guard **did** pass — you received `accepted` — then invoke-path routing failed. Save `request_reference` as **REF_MISS**.

**Do:**

```bash
d1 "SELECT request_reference, state, payload_pointer, terminal_error_code FROM ai_request;"
```

**Expect:** one row, `request_reference = REF_MISS`, `payload_pointer` NULL (no R2 envelope on this miss path), journal INSERT happened on the fresh path **before** routing. `d1 "SELECT COUNT(*) FROM routing_policy;"` is still 0.

#### 4.3.10 Publish, canary, promote: R2 document, D1 pointer

**Do:** publish a catch-all policy that pins the in-Worker `fake` adapter (no DeepSeek/Gemini keys):

```bash
curl -sS -D - -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "document": {
      "schema_version": 1,
      "policy_id": "standard",
      "policy_version": 1,
      "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
      "rules": [
        {
          "rule_id": "probe-fake-catch-all",
          "match": {},
          "requires": {
            "structured_output": false,
            "min_context_window": 0,
            "languages": []
          },
          "targets": [
            {
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
            }
          ]
        }
      ],
      "overrides": []
    }
  }'
```

**Expect:** HTTP 200 `{}` (or `{ "warnings": … }` only if latency classes were wrong — they should match).

**Do:**

```bash
d1 "SELECT policy_id, version, content_pointer, status, canary_installation_ids FROM routing_policy;"
npx wrangler r2 object get ai-platform-development \
  "control/routing-policy/standard/1.json" --file /tmp/rp.json --local
python3 - <<'PY'
import json
doc=json.load(open("/tmp/rp.json"))
assert doc["policy_id"]=="standard" and doc["policy_version"]==1
assert doc["rules"][0]["rule_id"]=="probe-fake-catch-all"
print("r2_document_ok")
PY
```

**Expect:** D1 row `policy_id = standard`, `version = 1`, `status = published`, `canary_installation_ids` NULL, `content_pointer = control/routing-policy/standard/1.json`. The D1 row does **not** contain `rules`. The R2 object is the full document (`r2_document_ok`). Index card vs warehouse.

**Do:** canary to this installation, then confirm D1, then promote:

```bash
curl -sS -D - -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"installation_ids\": [\"$INSTALLATION_ID\"]}"

d1 "SELECT status, canary_installation_ids FROM routing_policy WHERE policy_id='standard' AND version='1';"

curl -sS -D - -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

**Expect:** canary HTTP 200. D1 `status = canary` and `canary_installation_ids` JSON includes **I0**. Promote HTTP 200. Then:

```bash
d1 "SELECT version, status, canary_installation_ids FROM routing_policy ORDER BY active_from DESC, rowid DESC;"
```

**Expect:** `version = 1`, `status = active`, `canary_installation_ids` NULL. Preload uses cache key `{policyRef}/{installationId}` (`routing/standard@v1/<I0>`): canary-then-active.

**Do:** publish version 2, then promote it:

```bash
curl -sS -D - -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "document": {
      "schema_version": 1,
      "policy_id": "standard",
      "policy_version": 2,
      "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
      "rules": [
        {
          "rule_id": "probe-fake-v2",
          "match": {},
          "requires": {
            "structured_output": false,
            "min_context_window": 0,
            "languages": []
          },
          "targets": [
            {
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
            }
          ]
        }
      ],
      "overrides": []
    }
  }'

curl -sS -D - -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

**Expect:** both HTTP 200. Then:

```bash
d1 "SELECT version, status FROM routing_policy ORDER BY active_from DESC, rowid DESC;"
```

**Expect:** version `2` is `active` first; version `1` is `superseded`. The reader’s `ORDER BY active_from DESC, rowid DESC` on `status = 'active'` therefore selects v2. Repeat `…/versions/1/publish` → HTTP **409** `{ "error": "already_published" }`.

#### 4.3.11 Terminal settlement: Quota DO, D1 ledger, R2 envelope

**Do:** mint a **new** AAT (**AAT1**) so JTI is unused (`SELECT public.issue_ai_token();`). Then:

```bash
curl -sS -N -D - -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT1" \
  -H 'Content-Type: application/json' \
  -H 'x-idempotency-key: probe-happy-1' \
  -H 'x-capability-version: 1.0.0' \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"$ORG_CLAIM\",
      \"branch\": \"$BRANCH_CLAIM\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
```

**Expect:** HTTP 200 SSE. `event: accepted`, then `event: completed` (fake adapter). Save `request_reference` as **REF1**. Sleep 2 seconds so `waitUntil` settlement can finish.

**Do:**

```bash
d1 "SELECT request_id, request_reference, state, payload_pointer FROM ai_request WHERE request_reference = 'REF1';"
# substitute REF1
d1 "SELECT provider, model, outcome, tokens_in, tokens_out, cost FROM ai_attempt;"
d1 "SELECT tokens, cost, request_id IS NOT NULL AS has_request FROM usage_event;"
```

Save `request_id` as **RID1** and `payload_pointer`.

**Expect:** `state = Completed`. `payload_pointer = request/<RID1>/envelope`. One `ai_attempt`: `provider = fake`, `model = fake-v1`, `outcome = success`, `tokens_in = 10`, `tokens_out = 20`, **`cost = 0.005`**. One `usage_event` with the same tokens/cost and `has_request = 1`. `SELECT routing_decision FROM ai_request WHERE request_id = '<RID1>'` contains `rule_id` **`probe-fake-v2`** (latest active row, not superseded v1).

Cost check: bundled `fake-v1` rates are `input_per_1k = 0.1`, `output_per_1k = 0.2`; `(10/1000)*0.1 + (20/1000)*0.2 = 0.005`. Money is applied at settlement from provider-reported tokens, not from a client-supplied price.

**Do:**

```bash
npx wrangler r2 object get ai-platform-development \
  "request/RID1/envelope" --file /tmp/envelope.json --local
python3 - <<'PY'
import json
env=json.load(open("/tmp/envelope.json"))
assert set(env)=={"context","prompt","attempts","result"}
assert "visit.chief_complaint@v1" in json.dumps(env["context"])
assert "pricing_id" not in json.dumps(env)
print("envelope_ok")
PY
```

**Expect:** R2 object exists (`envelope_ok`). Diagnostic package has context, prompt, attempts, result. The **price table** is still absent from the envelope. D1 stored only the pointer.

Live quota lived in the DO during admission/credit; D1 `usage_event` is the durable ledger **after** completion. Before this probe, `usage_event` was empty even though the installation existed.

#### 4.3.12 JTI replay, idempotency, and GET journal

**Do:** reuse **AAT1** (same `jti`) with a **new** idempotency key:

```bash
curl -sS -D - -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT1" \
  -H 'Content-Type: application/json' \
  -H 'x-idempotency-key: probe-jti-replay' \
  -H 'x-capability-version: 1.0.0' \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"$ORG_CLAIM\",
      \"branch\": \"$BRANCH_CLAIM\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
```

**Expect:** HTTP **401** JSON, `code = unauthenticated`, **not** SSE. Quota DO JTI map rejected the token. `d1 "SELECT COUNT(*) FROM ai_request;"` is unchanged (still the miss-path row + **RID1** only). D1 has no `jti` table.

**Do:** mint **AAT2**. Replay the **same** `x-idempotency-key: probe-happy-1`:

```bash
curl -sS -N -D - -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT2" \
  -H 'Content-Type: application/json' \
  -H 'x-idempotency-key: probe-happy-1' \
  -H 'x-capability-version: 1.0.0' \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"$ORG_CLAIM\",
      \"branch\": \"$BRANCH_CLAIM\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
```

**Expect:** HTTP 200 SSE `accepted` then the **prior** terminal (`completed`) without a second provider settlement. `d1 "SELECT COUNT(*) FROM ai_request WHERE payload_pointer IS NOT NULL;"` stays **1**. `d1 "SELECT COUNT(*) FROM usage_event;"` stays **1**. The idempotency map is in the DO (`x-idempotency-key`), not a D1 table. Admitted/credited tracking is what makes the replay a no-op credit.

**Do:**

```bash
curl -sS -D - "$GATEWAY/v1/requests/$REF1" \
  -H "Authorization: Bearer $AAT2"
```

**Expect:** HTTP 200 `{ "state": "Completed", "result": … }`. `authenticateGetRequest` uses the same isolate `ConfigCache` as discovery and POST (identity `installations` / `keys` / `token_contracts`).

#### 4.3.13 Config cache TTL, plan grant key, no flush API

Keep the **same** `npm run dev` process (warm isolate).

**Do:** `curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$GATEWAY/control/config-cache/flush" -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"`

**Expect:** HTTP **404** `Not Found`. There is no flush API. (`ConfigCache.clear()` is tests-only.)

**Do:** warm the cache with `GET /v1/capabilities` (AAT2), then revoke **only** the installation-scoped grant:

```bash
d1 "UPDATE capability_grant SET revoked_at = '2026-08-21T00:00:00.000Z'
    WHERE scope = 'installation:$INSTALLATION_ID'
      AND capability_id = 'clinic.visit_summary';"
curl -sS "$GATEWAY/v1/capabilities" -H "Authorization: Bearer $AAT2" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["manifests"]))'
```

**Expect:** immediate discovery still reports **1** manifest (installation grant is cached under `{installation_id}/{capability_id}`).

**Do:** wait **31 seconds**, then the same `GET /v1/capabilities`.

**Expect:** still **1** manifest. Installation grant is revoked in D1; discovery now loads `plan:standard/clinic.visit_summary`. That is the `plan:{plan}/{capability_id}` cache key.

**Do:** prove TTL on entitlement **and** that POST / GET / discovery share the isolate. Mint a **new** AAT (**AAT3**) — do not reuse AAT2; that `jti` is already in the Quota DO map. Warm with GET, then:

```bash
d1 "UPDATE entitlement SET status = 'pending' WHERE installation_id = '$INSTALLATION_ID';"
curl -sS "$GATEWAY/v1/capabilities" -H "Authorization: Bearer $AAT2" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["manifests"]))'
# immediate POST must still pass the guard (cached active entitlement)
curl -sS -D /tmp/hdr-cached-post.txt -o /tmp/body-cached-post.txt -N -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT3" \
  -H 'Content-Type: application/json' \
  -H 'x-idempotency-key: probe-cache-still-active' \
  -H 'x-capability-version: 1.0.0' \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"$ORG_CLAIM\",
      \"branch\": \"$BRANCH_CLAIM\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
head -n 5 /tmp/hdr-cached-post.txt
```

**Expect:** immediate discovery still **1** manifest. Immediate POST is `HTTP/1.1 200` and `content-type: text/event-stream` (`event: accepted` in the body). Cached `entitlements` / `installations` / `keys` are shared across discovery and `createProductionPreAccept`. Sleep 2 seconds so settlement can write a second `usage_event`.

**Do:** mint **AAT4**. Wait **31 seconds**. Repeat GET capabilities (AAT2 is fine — discovery does not consult the JTI map) and POST with AAT4 (`x-idempotency-key: probe-cache-expired`).

**Expect:** GET `{ "manifests": [] }` (pending entitlement now visible). POST HTTP **403** JSON `forbidden_capability`, not SSE. D1 updates become visible after TTL expiry (≤30 s).

**Do:** restore for the remaining probes:

```bash
d1 "UPDATE entitlement SET status = 'active' WHERE installation_id = '$INSTALLATION_ID';"
d1 "UPDATE capability_grant SET revoked_at = NULL
    WHERE scope = 'installation:$INSTALLATION_ID'
      AND capability_id = 'clinic.visit_summary';"
```

Wait **31 seconds**. Confirm `GET /v1/capabilities` returns one manifest again before continuing.

#### 4.3.14 Kill-switch cache keys

**Do:** mint **AAT6** (fresh `jti`). Then:

```bash
d1 "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
    VALUES ('global', 'global', 1, '2026-08-21T00:00:00.000Z', 'probe');"
curl -sS -D - -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT6" \
  -H 'Content-Type: application/json' \
  -H 'x-idempotency-key: probe-kill-global' \
  -H 'x-capability-version: 1.0.0' \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"$ORG_CLAIM\",
      \"branch\": \"$BRANCH_CLAIM\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
```

**Expect:** HTTP **503** JSON, `code = capability_disabled`. Guard, no SSE. Cache key `kill_switches` / `global`. (A missing kill-switch row is fail-open and is **not** remembered, so this insert is visible on the next load.)

**Do:**

```bash
d1 "DELETE FROM kill_switch WHERE scope='global' AND target='global';"
d1 "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
    VALUES ('capability', 'clinic.visit_summary', 1, '2026-08-21T00:00:00.000Z', 'probe');"
```

Mint **AAT7**. Wait **31 seconds** if the previous `global` row was cached `active: true`, then POST with AAT7 and `x-idempotency-key: probe-kill-capability`.

**Expect:** again HTTP **503** `capability_disabled`. Key pattern `{scope}:{target}` = `capability:clinic.visit_summary`.

**Do:** `d1 "DELETE FROM kill_switch;"` then wait **31 seconds** so the next probe is not stuck on a cached active switch.

**Do:** pin period quota to what the DO already credited:

```bash
d1 "UPDATE entitlement SET request_quota = (SELECT COUNT(*) FROM usage_event)
    WHERE installation_id = '$INSTALLATION_ID';"
```

Wait **31 seconds**. Mint **AAT8** and POST (`x-idempotency-key: probe-quota-exhausted`) with the visit-summary body.

**Expect:** HTTP **429** JSON, `code = quota_exhausted`, `period_reset` equal to entitlement `period_end` (`2026-12-01T00:00:00.000Z`). Period counters live in the Quota DO; D1 `usage_event` already has the completed rows and does not by itself refuse the next call — the DO does. No new SSE stream.

#### 4.3.15 Token-contract cache key

**Do:** confirm discovery still works, then retire the seeded version in D1 (do not use a control-plane retire unless you also want its audit row):

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT2"
d1 "UPDATE token_contract SET retired_at = '2026-08-21T00:00:00.000Z', changed_by = 'probe' WHERE ver = '1';"
curl -sS -o /dev/null -w '%{http_code}\n' "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT2"
```

**Expect:** both GETs HTTP **200** immediately after the UPDATE — `token_contracts` / `1` is cached.

**Do:** wait **31 seconds**, then `GET /v1/capabilities` with AAT2 again.

**Expect:** HTTP **401** `unauthenticated`. Identity loads `token_contracts` by `{ver}` (`payload.ver = "1"`). After TTL, `retired_at` is visible and the AAT is rejected. Restore if you will keep using this D1:

```bash
d1 "UPDATE token_contract SET retired_at = NULL, changed_by = 'seed' WHERE ver = '1';"
```

