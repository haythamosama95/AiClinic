# AI Platform Data Journey

- Purpose: Trace **every field** of data as it moves through the AI platform — from first configuration through enrollment, entitlements, contracts, routing, live AI requests, and settlement in D1, R2, and the Quota Durable Object.
- Read this when: you are learning the platform and want to understand **what each value means, where it came from, and why a path succeeded or failed** — not just which HTTP endpoint to call.
- Canonical for: nothing. This is a **data-field companion** derived from `ai-platform/src/`**, `ai-platform/migrations/`**, `backend/supabase/migrations/**`, and `ai-platform/manifests/**`.
- Related docs: [06-ai-platform-behavioral-journey.md](../06-ai-platform-behavioral-journey.md) (stage behavior), [07-ai-platform-d1-r2-storage.md](../07-ai-platform-d1-r2-storage.md) (storage tables), [01-ai-platform.md](../01-ai-platform.md) (architecture decisions).

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
│  enroll_installation_keypair → installation_keys (secret + public, kid)     │
│  app_settings ai.availability → { enrolled, platform_base_url }             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │ public_jwk.x, kid, installation_id
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ CONTROL PLANE — `/control/*` (Bearer OPERATOR_BEARER_TOKEN)                 │
│  POST …/enroll  → D1: installation, installation_key, entitlement(pending)  │
│  POST …/entitle → D1: entitlement(active), capability_grant, control_audit  │
│  POST …/routing-policies/…/publish → R2: policy JSON + D1: routing_policy    │
│  POST …/canary / promote → D1: routing_policy status transitions            │
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
| `prompts/clinic.visit_summary/*.md`                   | System, rules, template prompt text |




### 3.5 Config cache — 30-second reading glasses

Before most D1 reads, `config-cache` may return a cached copy (TTL `30_000` ms). Cache keys:


| Kind                    | Key pattern                                                          | D1 table              |
| ----------------------- | -------------------------------------------------------------------- | --------------------- |
| `installations`         | `{installation_id}`                                                  | `installation`        |
| `keys`                  | `{key_id}`                                                           | `installation_key`    |
| `entitlements`          | `{installation_id}`                                                  | `entitlement`         |
| `grants`                | `{installation_id}/{capability_id}` or `plan:{plan}/{capability_id}` | `capability_grant`    |
| `kill_switches`         | `global` or `{scope}:{target}`                                       | `kill_switch`         |
| `token_contracts`       | `{ver}`                                                              | `token_contract`      |
| `active_routing_policy` | `{policyRef}` or `{policyRef}/{installationId}`                      | `routing_policy` + R2 |


---



