# AI Billing Orchestration — Architecture

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `01-proposal.md` (agreed decisions, verification findings, attack model),
`../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../ai-platform/03-ai-platform-delivery-plan.md` (Band G, Band L).

---

## Table of Contents

- [Overview](#overview)
  - [Layers and deployables](#layers-and-deployables)
  - [AI Billing Orchestrator modules](#ai-billing-orchestrator-modules)
  - [Three-key trust chain](#three-key-trust-chain)
  - [Happy-path purchase flow](#happy-path-purchase-flow)
  - [How the rest of this document is organized](#how-the-rest-of-this-document-is-organized)

1. [Context and decisions already made](#1-context-and-decisions-already-made)
2. [System context and deployables](#2-system-context-and-deployables)
3. [Trust model and key management](#3-trust-model-and-key-management)
4. [Data model](#4-data-model)
5. [Wire contracts](#5-wire-contracts)
6. [State machines and dunning policy](#6-state-machines-and-dunning-policy)
7. [Payment provider adapter](#7-payment-provider-adapter)
8. [Platform-side changes](#8-platform-side-changes)
9. [Clinic-side changes](#9-clinic-side-changes)
10. [Flutter flows](#10-flutter-flows)
11. [Scheduled work and reconciliation](#11-scheduled-work-and-reconciliation)
12. [Security traceability](#12-security-traceability)
13. [Proposal open items — resolutions](#13-proposal-open-items-resolutions)
14. [Deviations from the proposal](#14-deviations-from-the-proposal)
15. [Constitution compliance check](#15-constitution-compliance-check)

---



## Overview

This section is the map. Read it first; the numbered sections below fill in schemas, wire
formats, and edge cases.

**Problem.** Clinics need to buy AI self-service: pay a provider, get provisioned automatically,
with no operator in the loop and no way to skip payment.

**Core principle.** The ai-platform **guard** is the only enforcement point for AI access.
Everything else — billing, webhooks, clinic flags — is **provisioning**. Granting service
requires **two independent signatures** (purchase proof + orchestrator CAT), so no single
compromised secret or service can turn AI on.

### Layers and deployables

Four layers, two vendor Workers, one clinic stack:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CLINIC LAYER (per deployment)                                              │
│  ┌──────────────────────┐      ┌──────────────────────────────────────────┐ │
│  │ Flutter desktop app  │─────▶│ Clinic Supabase (PostgreSQL)           │ │
│  │ purchase + activate  │ RPC  │ receipt-verified ai.availability flag  │ │
│  └──────────┬───────────┘      └──────────────────────────────────────────┘ │
│             │ AAT + receipt pull                                              │
└─────────────┼───────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PLATFORM LAYER — ai-platform Worker (existing, refactored)                 │
│  /v1/*  guard + invoke + status/receipt minting                               │
│  /control/v1/*  enroll, entitle, renew, suspend — CAT auth, purchase-proof-gated   │
└─────────────▲───────────────────────────────────────────────────────────────┘
              │ CAT + purchase proof
              │
┌─────────────┴───────────────────────────────────────────────────────────────┐
│  BILLING LAYER — AI Billing Orchestrator Worker (new)                       │
│  purchase module ◄──webhook── Payment provider (Paymob first)               │
│  orchestrator module ──▶ platform /control/v1/*                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```


| Layer    | Deployable                            | Owns                                                  | Never does                                       |
| -------- | ------------------------------------- | ----------------------------------------------------- | ------------------------------------------------ |
| Clinic   | Flutter + Supabase                    | Clinic keys, signed order payloads, local AI flag     | Hold vendor credentials; call `/control/v1/*`       |
| Platform | `ai-platform` Worker + D1             | Entitlements, guard, provisioning receipts            | Take payment; write to clinic DB                 |
| Billing  | `ai-billing-orchestrator` Worker + D1 | Orders, payments, purchase proofs, provisioning drive | Write to clinic Supabase; call `/v1/*` data path |
| Payment  | Provider hosted checkout              | Card capture                                          | Touch clinic or platform business data           |


The billing and platform Workers share a Cloudflare account and conventions but have **separate
D1 databases and secrets** — a compromise of one cannot read the other's signing keys.

### AI Billing Orchestrator modules

One new Worker, two modules, **two keys** (key separation is load-bearing):

```
ai-billing-orchestrator/
├─ purchase module          secret: BILLING_PURCHASE_PROOF_PRIVATE_KEY, PAYMOB_*
│  ├─ orders/               POST /v1/orders, GET /v1/orders/{id}, renewal checkout
│  ├─ catalogue/            cached read of the platform's GET /v1/plans (§4.1.6)
│  ├─ webhooks/             POST /v1/webhooks/{provider} — signature verify, idempotency
│  ├─ providers/            adapter port (Paymob first); provider IDs quarantined
│  └─ purchase_proofs/         mint purchase proof after payment or comp order
│
└─ orchestrator module      secret: ORCHESTRATOR_CAT_PRIVATE_KEY
   ├─ outbox consumer      in-process handoff from purchase (no queue infra)
   └─ platform client      enroll → entitle / renew / entitlement-suspend
```

The purchase module cannot sign a CAT; the orchestrator cannot sign a purchase proof. A full
compromise of either module alone cannot grant service.

**Handoff.** Payment or comp order → purchase updates order + mints purchase proof → writes an
`outbox` row → producer triggers orchestrator immediately (`ctx.waitUntil` from webhook/comp;
order clock inline for suspends); `* * * * *` cron sweeps retries → signs CAT per call → hits
platform `/control/v1/*`.

### Three-key trust chain

Three Ed25519 signing keys, three jobs — read left to right as the purchase-to-activation chain:

```
  [Clinic pays]     [Orchestrator acts]      [Clinic turns AI on]
        │                    │                         │
        ▼                    ▼                         ▼
 Purchase            Control Action            Provisioning
 Proof                    Token                   Receipt
 (billing key)        (orchestrator CAT)      (platform key)
        │                    │                         │
        └──── verified by ai-platform ────────────────┘
                                    │
                                    └── receipt verified by clinic Supabase
```


| Key                        | Simple job                                                                                                    | Where detail lives |
| -------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------ |
| Purchase proof signing key | Proves this installation paid, or was granted complimentary access by support (`comp` order), for this period | §3.1, §5.7         |
| Orchestrator CAT           | Proves the caller may invoke a specific `/control/v1/*` action                                                   | §3.1, §5.6, §8.1   |
| Platform receipt           | Proves the platform has an active entitlement for this installation                                           | §3.1, §5.8, §9.2   |


A **comp** (complimentary) order is a zero-price order issued by vendor support — goodwill,
trials, or adjustments — with no checkout. It still mints a purchase proof and follows the same
grant path as a paid order (§6.5).

Human operators use **personal CAT keys** registered in `control_operator` for every
`/control/v1/*` call — there is no shared bearer anywhere on the control plane. The legacy
`OPERATOR_BEARER_TOKEN` is **removed entirely** (§8.1, §13 item 3); auth-system recovery is a
D1-level operation under Cloudflare account IAM, not a standing credential.

### Happy-path purchase flow

End-to-end, first purchase:

```
Owner (Flutter)                ABO                    Platform              Clinic DB
     │                          │                         │                     │
     │ 1. sign order payload    │                         │                     │
     │─────────────────────────▶│ POST /v1/orders            │                     │
     │◀ checkout_url + poll_token                         │                     │
     │                          │                         │                     │
     │ 2. pay in system browser │                         │                     │
     │───────────(provider)────▶│ webhook: paid           │                     │
     │                          │ mint purchase proof     │                     │
     │                          │ outbox: provision       │                     │
     │                          │────────────────────────▶│ CAT + purchase proof│
     │                          │                         │ enroll → entitle    │
     │                          │◀ provisioned ───────────│                     │
     │                          │                         │                     │
     │ 3. poll GET /v1/orders      │                         │                     │
     │◀ status: provisioned ──  │                         │                     │
     │                          │                         │                     │
     │ 4. GET /v1/installation/status (AAT)               │                     │
     │───────────────────────────────────────────────────▶│ mint receipt        │
     │◀ receipt ──────────────────────────────────────────│                     │
     │                          │                         │                     │
     │ 5. set_ai_availability(receipt)                    │                     │
     │─────────────────────────────────────────────────────────────────────────▶│
     │                          │                         │     AI flag = on    │
```

Renewals reuse the same chain: payer-initiated checkout → new purchase proof → `renew` → fresh
receipt → clinic flag extended. Dunning (grace, suspend, expiry) is time-driven cron on the
billing side plus receipt `valid_until` on the clinic side — see §6.

### How the rest of this document is organized


| Section | What you will find there                                                  |
| ------- | ------------------------------------------------------------------------- |
| §1      | Decisions already locked; what this doc adds vs the proposal              |
| §2      | Deployable boundaries, repo layout, what the billing Worker never does    |
| §3      | All three keys, rotation, operator identity, clinic key wrapping          |
| §4      | D1 schemas (billing + platform `control_operator`, purchase proof tables) |
| §5      | Wire contracts: order API, webhooks, CAT, purchase proof, receipt, status |
| §6      | Order and entitlement state machines; dunning/grace; plan retirement    |
| §7      | Payment provider adapter port and anti-lock-in rules                      |
| §8      | Platform code changes: CAT auth, purchase-proof-gated grants, new routes  |
| §9      | Clinic Supabase RPCs: receipt-verified activation, key seeding            |
| §10     | Flutter purchase, activation, renewal, and failure recovery               |
| §11     | Cron jobs (outbox, order clock, reconciliation)                           |
| §12     | Security traceability matrix (threat → mitigation)                        |
| §13–§15 | Open-item resolutions, proposal deviations, constitution check            |




## 1. Context and decisions already made

This document turns the agreed proposal (`01-proposal.md`) into a buildable architecture. The
proposal's decisions are **not** re-opened here: the three-key trust chain, the single AI Billing Orchestrator (ABO) with two modules, purchase-proof-gated grants, receipt-verified clinic activation, and the
replacement of `set_ai_availability` are settled. What this document adds is everything the
proposal deliberately left to the design phase: concrete schemas, wire contracts with exact
claims and verification order, key-rotation designs for all three trust roots (proposal §9
finding 5), the dunning/grace policy (proposal §12), and the provider adapter boundary.

Two product decisions were confirmed during this design phase and are load-bearing throughout:

1. **Renewals are payer-initiated.** No card-on-file, no merchant-initiated charges. Near period
  end the AI Billing Orchestrator issues a fresh checkout URL for the existing order; the clinic owner
   pays again through the provider's hosted page. This keeps the adapter at its simplest
   (a payment-intent create + webhook verify), stores no payment credentials anywhere, and
   matches the constitution's simplicity principle.
2. **Support/goodwill grants go through zero-price orders.** The platform's existing `override`
  endpoint becomes purchase-proof-gated like every other grant path: the AI Billing Orchestrator issues a `comp` order
   (amount 0, no checkout), signs a purchase proof, and the orchestrator presents it. The rule
   "every entitlement traces to an order" therefore has no exceptions, and reconciliation needs
   no special cases.

Every contract below was verified against the code as of 2026-09-11. Where the code contradicts
something the proposal assumed, the code wins and the deviation is listed in
[§14](#14-deviations-from-the-proposal).

## 2. System context and deployables



### 2.1 One new deployable

One new Cloudflare Worker, vendor-operated, in the same Cloudflare account as `ai-platform`
(separate account deferred — [§13](#13-proposal-open-items-resolutions) item 4). Same stack,
same workflow, same conventions: forward-only D1 migrations, three environments
(development/staging/production), secrets via `wrangler secret`, Cron Triggers for scheduled
work. **Separate Worker, separate D1, separate secrets** — CI credentials and secret access for
one service cannot read the other's keys.

```
AI Billing Orchestrator (`ai-billing-orchestrator`)
├─ purchase module        (secrets: BILLING_PURCHASE_PROOF_PRIVATE_KEY, PAYMOB_*)
│   ├─ provider adapter   — thin, swappable (Paymob first, §7)
│   ├─ order state machine — provider-agnostic (§6.1)
│   └─ webhook endpoint   — provider signature verification, idempotent event table (§5.5)
└─ orchestrator module    (secret: ORCHESTRATOR_CAT_PRIVATE_KEY)
    ├─ consumes paid/refund events via the outbox table (in-process handoff; no queue infra)
    └─ drives ai-platform /control/v1/* (enroll → entitle / renew / entitlement-suspend)
```

The two modules share a deployable and a D1 database but **not** keys: the purchase module cannot
sign a CAT, and the orchestrator cannot sign a purchase proof. This is the code-level expression of
the proposal's core principle — a full compromise of either module cannot grant service.

### 2.2 Repository layout

New top-level directory `ai-billing-orchestrator/`, mirroring `ai-platform/` conventions:

```
ai-billing-orchestrator/
├─ src/
│  ├─ worker.ts            — fetch + scheduled entry points
│  ├─ orders/              — order state machine, POST /v1/orders, GET /v1/orders/{id}
│  ├─ catalogue/           — cached server-side read of the platform's GET /v1/plans (§5.10)
│  ├─ webhooks/            — provider webhook endpoint, event idempotency
│  ├─ providers/
│  │  ├─ types.ts          — the adapter port (§7.1)
│  │  └─ paymob/           — first adapter
│  ├─ purchase_proofs/        — purchase proof minting (Ed25519 JWS)
│  ├─ orchestrator/        — outbox consumer, CAT minter, platform control client
│  └─ reconcile/           — daily billing reconciliation job
├─ migrations/             — forward-only, YYYYMMDDHHMMSS_snake_case.sql
├─ wrangler.toml
└─ test/
```

`AGENTS.md` gains an `ai-billing-orchestrator/` line in its repo-layout quick reference.

**Shared crypto package.** Ed25519 compact-JWS sign/verify (EdDSA-pinned), the base64url codec,
and timing-safe string compare live in one workspace package — `packages/ed25519-jws/` —
consumed by both `ai-platform/` (AAT verifier internals, CAT `OperatorAuth`) and
`ai-billing-orchestrator/` (PoP verification, purchase proof minting, poll-token compare). Three
near-identical JWS verifiers in one repository is a defect, not a pattern. The clinic side is
exempt: pgsodium is a different runtime.

### 2.3 What the AI Billing Orchestrator never does

- Never writes to any clinic Supabase (it has no inbound path and holds no clinic credentials —
clinic activation is pull-based, §10.2).
- Never learns provider card data (hosted checkout only; no provider SDK in any client).
- Never calls the ai-platform `/v1/*` data path — only `/control/v1/*`, and only with a CAT.
- Never stores provider identifiers outside `provider_refs` (§7.2).

### 2.4 Configuration and secrets inventory

Secrets (per environment, via `wrangler secret`): `BILLING_PURCHASE_PROOF_PRIVATE_KEY` (§3.1),
`ORCHESTRATOR_CAT_PRIVATE_KEY` (§3.1), `PAYMOB_SECRET_KEY` / `PAYMOB_PUBLIC_KEY` /
`PAYMOB_HMAC_SECRET` (§7.2). Vars: the active purchase-proof `kid` (`bill-<n>`, §3.3), the
orchestrator CAT key id (§3.4), `PAYMOB_INTEGRATION_ID` (§7.2), and:


| Var                    | Purpose                                                                                                  |
| ---------------------- | -------------------------------------------------------------------------------------------------------- |
| `AI_PLATFORM_BASE_URL` | Platform origin for the orchestrator module's control client (`/control/v1/*` calls) and the purchase module's catalogue fetch (`GET /v1/plans`, §4.1.6) |
| `BILLING_PUBLIC_ORIGIN` | This Worker's own public origin — used to build the Paymob `notification_url` (§7.2)                    |

**Catalogue cache mechanism.** The server-side `GET /v1/plans` fetch is cached **per isolate,
in memory**, with a 300 s max-age (the endpoint's `Cache-Control`, §5.10) — no Cache API, no D1
mirror; a cold isolate simply fetches. The staleness analysis in §4.1.6 applies unchanged.



## 3. Trust model and key management



### 3.1 The three signing keys


| Key                            | Held by                                      | Signs                                             | Verified by                           | Storage                                                                                                          |
| ------------------------------ | -------------------------------------------- | ------------------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Purchase proof signing key** | AI Billing Orchestrator, purchase module     | Purchase Proof (§5.7)                             | ai-platform control plane             | Worker secret `BILLING_PURCHASE_PROOF_PRIVATE_KEY` (PKCS#8, base64)                                              |
| **Orchestrator CAT key**       | AI Billing Orchestrator, orchestrator module | Control Action Token per `/control/v1/`* call (§5.6) | ai-platform control plane             | Worker secret `ORCHESTRATOR_CAT_PRIVATE_KEY` (PKCS#8, base64)                                                    |
| **Platform receipt key**       | ai-platform Worker                           | Provisioning Receipt (§5.8)                       | clinic Supabase `set_ai_availability` | Worker secret `PLATFORM_RECEIPT_PRIVATE_KEY` (PKCS#8, base64); public half in var `PLATFORM_RECEIPT_PUBLIC_KEYS` |


- **Purchase proof signing key** — proves a clinic actually paid (or received a comp order). The purchase module signs a short-lived token after money moves; the platform checks it before granting or renewing an entitlement.
- **Orchestrator CAT key** — proves the orchestrator is allowed to call platform control APIs. Every `/control/v1/`* request carries a token signed with this key so the platform knows the caller is the billing orchestrator, not a random client.
- **Platform receipt key** — proves the platform has an active entitlement for a clinic installation. The platform signs a receipt the Flutter app delivers to the clinic database, which accepts it as the only way to turn AI on locally.

Private key = signs. Public key = verifies. Each artifact's JWS header carries a `kid` so the
verifier picks the right public key from its store.

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│  KEY 1 — Purchase proof (payment → platform grant)                                         │
├────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                            │
│  ABO purchase module                         ai-platform Worker                            │
│  ┌────────────────────────────┐              ┌─────────────────────────────────────────┐   │
│  │ PRIVATE (secret)           │   signs      │ PUBLIC (Worker var)                     │   │
│  │ BILLING_PURCHASE_PROOF_    │ ──────────▶  │ BILLING_PURCHASE_PROOF_PUBLIC_KEYS      │   │
│  │   PRIVATE_KEY              │  Purchase    │   [{ kid: "bill-1", public_key, … },    │   │
│  │ kid: bill-1 (active)       │    Proof     │    { kid: "bill-2", … }]  (key set)     │   │
│  └────────────────────────────┘              └──────────────────▲──────────────────────┘   │
│           │ only purchase module                                │ verify on enroll /       │
│           │ can sign                                            │ entitle / renew /        │
│           │                                                     │ override (§5.7)          │
│  Key set in Worker var; rotation overlap up to 72 h (§3.3).                                │
└───────────┼─────────────────────────────────────────────────────┼──────────────────────────┘
            │                                                     │
┌───────────┼─────────────────────────────────────────────────────┼──────────────────────────┐
│  KEY 2 — Orchestrator CAT (who may call /control/v1/*)             │                          │
├───────────┼─────────────────────────────────────────────────────┼──────────────────────────┤
│           │                                                     │                          │
│  ABO orchestrator module                     ai-platform Worker                            │
│  ┌────────────────────────────┐              ┌───────────────────────────────────────────┐ │
│  │ PRIVATE (secret)           │   signs      │ PUBLIC (D1 table — many rows, not one key)│ |
│  │ ORCHESTRATOR_CAT_          │ ──────────▶  │ control_operator                          │ │
│  │   PRIVATE_KEY              │  CAT per     │   one row per key: { key_id,              │ │
│  │ kid: UUID = key_id         │  /control/v1/*  │     operator_id, public_key,              │ │
│  │ (one active private secret │              │     allowed_actions, revoked_at }         │ │
│  │  on ABO at a time)         │              │   rotation: INSERT new row, revoke old    │ │
│  └────────────────────────────┘              └──────────────────▲────────────────────────┘ │
│           │ only orchestrator module                            │ verify before any        │
│           │ can sign with orchestrator key                      │ control handler (§5.6)   │
│           │                                                     │                          │
│  Human operators (incident response / ops) same table ────────┘                            │
│  ┌────────────────────────────┐   signs CAT  each operator: own row, own allowed_actions;  │
│  │ PRIVATE on operator's      │ ──────────▶   private key never on server (§4.2)           │
│  │   laptop only              │                                                            │
│  └────────────────────────────┘                                                            │
│  Rotation overlap ≈ 2 min (CAT max lifetime 120 s, §5.6) — see §3.4.                       │
└────────────────────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────────────────────┐
│  KEY 3 — Provisioning receipt (platform → clinic AI flag)                                  │
├────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                            │
│  ai-platform Worker                          clinic Supabase                               │
│  ┌────────────────────────────┐              ┌─────────────────────────────────────────┐   │
│  │ PRIVATE (secret)           │   signs      │ PUBLIC (app_settings JSON array)        │   │
│  │ PLATFORM_RECEIPT_          │ ──────────▶  │ ai.platform_receipt_keys                │   │
│  │   PRIVATE_KEY              │  Provisioning│   [{ kid: "rcpt-1", public_key, … }]    │   │
│  │ kid: rcpt-1 (active)       │    Receipt   │ seeded via GET /v1/platform-keys (§3.5) │   │
│  └────────────────────────────┘              └──────────────────▲──────────────────────┘   │
│           │ minted in GET /v1/installation/status               │ verify in                │
│           │                                                     │ set_ai_availability      │
│           │ Public keys also in Worker var                      │ (§5.8, §9.2)             │
│           │ PLATFORM_RECEIPT_PUBLIC_KEYS (for Flutter fetch)    │                          │
│           │                                                     │                          │
│           └──── receipt carried by Flutter (short-lived; ───────┘                          │
│                 not a stored clinic credential)                                            │
└────────────────────────────────────────────────────────────────────────────────────────────┘

Grant path (two signatures on the platform):  Purchase Proof ──┐
                                                               ├──▶ ai-platform /control/v1/*
Orchestrator CAT ──────────────────────────────────────────────┘
Clinic activation (separate step):  Provisioning Receipt ──▶ clinic DB
```

**Why KEY 1 and KEY 2 store public keys differently:** both allow multiple public keys during
rotation. Purchase proof uses a Worker var key set because there is one billing issuer and proofs
live up to 72 h. CAT uses a `control_operator` table because many callers (orchestrator +
humans) each have their own key, scopes, and fast revocation — and CATs expire in 120 s, so
rotation overlap is minutes, not days (§3.3 vs §3.4).

All three are Ed25519. Signing uses `crypto.subtle.sign`/`verify` with `Ed25519` — the same
primitive `EnrolledKeyVerifier` already uses in production (`ai-platform/src/identity/index.ts`).
Private keys are imported from PKCS#8 (`crypto.subtle.importKey("pkcs8", …, "Ed25519", …)`);
public keys travel as base64url raw 32-byte strings or JWK `{kty:"OKP", crv:"Ed25519", x}`,
matching the existing clinic-key conventions.

Human operators hold **personal** Ed25519 keypairs (generated locally, private key never leaves
their machine) and sign CATs with them; their public keys are registered in `control_operator`
(§4.2). The shared `OPERATOR_BEARER_TOKEN` is **removed entirely** (§8.1, §13 item 3) — a
shared, unattributed credential is the exact anti-pattern per-operator keys exist to
eliminate.

### 3.2 Key identifiers

Every signed object carries a `kid` in its JWS header. Key ids are namespaced so a `kid` from one
trust domain can never be resolved in another:


| Domain                           | `kid` format                           | Example  |
| -------------------------------- | -------------------------------------- | -------- |
| Clinic installation keys         | UUID (existing convention)             | `8f3c…`  |
| Purchase proof signing keys      | `bill-<n>`                             | `bill-1` |
| Orchestrator / operator CAT keys | UUID per key row in `control_operator` | `7a21…`  |
| Platform receipt keys            | `rcpt-<n>`                             | `rcpt-1` |




### 3.3 Rotation — purchase proof signing key

The platform verifies purchase proofs against a **key set**, not a single key:
`BILLING_PURCHASE_PROOF_PUBLIC_KEYS` is a Worker var holding a JSON array
`[{ "kid": "bill-1", "public_key": "<base64url>", "not_before": "…", "not_after": "…" }]`.
Verification selects the entry by header `kid` and rejects outside its validity window — the same
shape as `isKeyWithinValidityWindow` in `EnrolledKeyVerifier`.

Rotation procedure (zero-downtime, four steps) — executed by the single rotation
script/runbook of §3.7, which performs the platform-side and AI Billing Orchestrator-side steps
in one operation:

1. Generate `bill-(n+1)`; add its public half to `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` alongside
  `bill-n` (platform now accepts both).
2. Set the AI Billing Orchestrator's `BILLING_PURCHASE_PROOF_PRIVATE_KEY` secret to the new key and its
  active `kid` var to `bill-(n+1)`.
3. Wait one maximum purchase proof lifetime (72 h, §5.7) so every in-flight purchase proof signed by
  `bill-n` has expired or been consumed.
4. Remove `bill-n` from the platform key set (or stamp its `not_after`).

Emergency revocation is step 4 alone: at most 72 h of already-minted purchase proofs become
unusable, and every one of them is single-use anyway (§5.7 replay rule), so the real exposure
window is the set of *unconsumed* purchase proofs, which the orchestrator retries make small.

### 3.4 Rotation — orchestrator CAT key (and human operator keys)

CAT verification is backed by the `control_operator` **table** (§4.2), so rotation is data, not
deployment:

1. Insert a new row `(operator_id = "orchestrator", key_id = <new uuid>, public_key = …)`.
2. Update the AI Billing Orchestrator's `ORCHESTRATOR_CAT_PRIVATE_KEY` secret and key-id var.
3. Stamp `revoked_at` on the old key row.

CATs live at most 120 s (§5.6), so the overlap window is two minutes, not days. Human operator
rotation is identical. Revocation of a compromised operator is one `UPDATE` — this is the
mechanism behind the proposal's "orchestrator DoS is revocable" residual-risk mitigation.

### 3.5 Rotation — platform receipt key

The hard case (proposal §9 finding 5): the verifying party is **every clinic database**, so the
key set must be distributable and stored clinic-side.

- **Clinic storage:** `ai_internal.app_settings` key `ai.platform_receipt_keys` holds a JSON
array `[{ "kid": "rcpt-1", "public_key": "<base64url>", "added_at": "…", "revoked_at": null }]`.
The existing deny-all RLS policy on `app_settings` is unchanged; only SECURITY DEFINER RPCs
touch it (§9.3, §9.4).
- **Distribution:** the platform serves its own public keys at `GET /v1/platform-keys`
(unauthenticated — public keys are not secrets; §5.9). Flutter fetches this during activation
and seeds the clinic via `add_platform_receipt_key`. Trust anchor is the vendor's TLS origin —
the same anchor the clinic already trusts for `platform_base_url`.
- **Rotation procedure:**
  1. Generate `rcpt-(n+1)`; add to `PLATFORM_RECEIPT_PUBLIC_KEYS` (platform now *serves* both)
    and set the signing secret to the new key.
  2. Clinics pick up the new key on their next activation/status poll (Flutter re-fetches
    `GET /v1/platform-keys` whenever receipt verification fails with `unknown kid`, then retries
     once — self-healing, no operator action).
  3. After every clinic's stored receipts would have expired (receipts live 15 minutes;
    `valid_until` is a *consumption* bound, not a signature-validity bound), the old key can be
     retired from the served set. Clinics revoke it locally via `revoke_platform_receipt_key`
     (which refuses to revoke the last key, mirroring `CANNOT_REVOKE_LAST_ACTIVE_KEY`).
- **Emergency revocation:** remove the key from `PLATFORM_RECEIPT_PUBLIC_KEYS` and stop signing
with it. Clinics that still trust it accept receipts for at most 15 minutes (receipt `exp`),
and the guard re-checks entitlement on every request regardless — a forged or stale receipt
flips a UI flag, it does not grant service (§12).



### 3.6 Clinic installation private-key wrapping (proposal §9 finding 4)

Today `ai_internal.installation_keys.secret_key` is raw `bytea`. This design makes that key
**purchase-authorizing** (it signs order payloads, §5.2), so the architecture schedules hardening
as part of Band L rather than deferring it:

- A new migration adds `secret_key_wrapped bytea` and `wrap_key_id uuid`, populates them with
`pgsodium.crypto_aead_det_encrypt(secret_key, kid::bytea, key_id)` where `key_id` references a
pgsodium-managed key created via `pgsodium.create_key(name := 'ai_installation_key_wrap')`,
then drops the plaintext column. The key id is stored in `app_settings`
(`ai.key_wrap_id`); it is not itself secret.
- `issue_ai_token` and the new order-signing RPC decrypt with
`pgsodium.crypto_aead_det_decrypt` at point of use. No RPC signature changes.
- **Honest boundary:** this protects the key against SQL-level exfiltration (a dumped table or a
stolen backup without the pgsodium root key is not a signing key). It does not protect against
an attacker with live `postgres` access, who can call the decrypt function. The pgsodium root
key's custody is a Supabase environment property; clinics self-hosting PostgreSQL must set
`pgsodium.root_key` outside the database for the boundary to hold. This is documented in the
slice, not hand-waved.

Until the migration ships, the residual is exactly today's status quo; the order-signing RPC is
designed so wrapping is an internal change to two functions.

### 3.7 Rotation runbook and boot-time self-check

Every rotation above spans two deployables — a platform-side half and an AI Billing
Orchestrator-side half that must land together or the trust chain breaks half-rotated. Two
operability controls keep that from being a hand-coordinated dance:

- **One rotation script/runbook per key domain.** A single script (or runbook, while the
  operator count is one) performs **both sides** of a rotation in one operation: for the
  purchase-proof key, the §3.3 four-step procedure (platform key-set update, ABO secret + active
  `kid` var, overlap wait, old-key retirement); for the orchestrator CAT key, the §3.4
  table-backed procedure (`control_operator` insert, ABO secret + key-id var, old-row
  revocation); for the receipt key, the §3.5 procedure (platform secret + served key set,
  clinic-side self-healing refetch, old-key retirement). The script enforces the overlap waits
  between phases rather than relying on the operator's calendar.
- **ABO boot-time self-check.** At isolate init (cached for the isolate's lifetime), the AI
  Billing Orchestrator verifies its active purchase-proof `kid` and issuer
  (`BILLING_ISSUER`) against an **authenticated platform read** (orchestrator-scoped CAT,
  §5.6) and **fails fast** on mismatch — the Worker refuses to mint proofs or run the outbox
  processor and emits a structured alert. A misconfigured or half-rotated deploy surfaces at
  boot, not as a stream of failed `enroll` calls against paid orders.

## 4. Data model



### 4.1 Billing D1 schema

Seven tables in the AI Billing Orchestrator's D1 database. [§4.1.1](#411-overview) maps entities,
transactions, and relationships; [§4.1.2](#412-orders)–[§4.1.8](#418-ops_operator-and-ops_jti) give
per-table column detail.

Forward-only migrations under `ai-billing-orchestrator/migrations/`, named
`YYYYMMDDHHMMSS_snake_case.sql` per the ai-platform convention. All timestamps are ISO-8601 UTC
text, matching platform D1 practice.

#### 4.1.1 Overview

Not every table holds business state — some exist only to record or bridge a handoff between
actors:

| Role | Tables | Job |
| ---- | ------ | --- |
| State hub | `orders` | One row per purchase relationship; every other billing table hangs off it |
| Provider bridge | `provider_refs`, `webhook_events` | Isolate provider identifiers from the rest of the schema; idempotent webhook log |
| Module bridge | `outbox` | In-process handoff from the **purchase** module to the **orchestrator** module (same Worker, no queue); persisted `payload` rows double as the purchase-proof minting ledger (§4.1.5) |
| Ops drift | `reconciliation_alert` | Findings when billing state and platform state diverge |
| Ops identity | `ops_operator`, `ops_jti` | Per-operator authentication for `/v1/ops/*` — no shared bearer (§11.2) |

**Records vs transports.** Plan and period facts appear in several places, but only two are
*records*: `orders` is the payment record (what was sold, when it was paid) and the platform's
`entitlement` is the enforcement record (what the guard admits). The purchase proof and the
provisioning receipt are signed *transports* between the two — not copies of record, and each is
single-use or short-lived. When the two records disagree, that is drift, and §11.3 exists to
detect it.

**Who exists** — three layers; billing D1 sits entirely inside the ABO Worker:

```
┌──────────────────── CLINIC LAYER ──────────────────────┐
│  Flutter  ◄──RPC──►  Clinic Supabase  (not billing D1) │
└──────────────┬─────────────────────────────────────────┘
               │  HTTP: POST/GET /v1/orders, poll token
               ▼
┌──────────────────── BILLING LAYER ────────────────────┐
│            AI Billing Orchestrator Worker             │
│                                                       │
│  ┌─ purchase module  ─┐    ┌─ orchestrator module ─┐  │
│  │ orders,            │    │ reads outbox, calls   │  │
│  │ provider_refs      │───►│ ai-platform /control/v1 │  │
│  │ webhook_events     │out │                       │  │
│  │ ops_operator       │box │                       │  │
│  └────────────────────┘    └───────────────────────┘  │
│  reconciliation_alert (daily cron); ops_jti (§4.1.8)  │
└──────────────┬───────────────────────┬────────────────┘
               │ webhook               │ CAT + purchase proof
               ▼                       ▼
     Payment provider            ai-platform (§4.2 D1)
```

**Tables hang off `orders`** — every other billing table is a child row (there is no local plan
table; the platform's catalogue is the single source — §4.1.6):

```
  provider_refs ──────►  orders  ◄────── webhook_events
  (quarantine provider     │  ▲              (idempotent event log;
   ids; FK order_id)       │  │               resolves via provider_refs)
                           │  │
                           ▼  │            ┌────────────────────┐
                          outbox            │ reconciliation_alert
                       (FK order_id;        │ (detail JSON cites
                        handoff to          │  order_id; no FK)
                        orchestrator;       └────────────────────┘
                        payload embeds
                        the minted proof
                        JWS)
```

**Happy-path chain** — the flows that matter most, in order (tables **written**; full access in
the transaction table):

```
 0  Flutter ──GET /v1/plans──► ai-platform
                                      (config cache; not billing D1)

 1  Clinic Supabase ──sign──► Flutter
                                      (clinic tables only)

 2  Flutter ──POST /v1/orders──► purchase module
                                      orders, provider_refs

 3  Owner pays in browser ──webhook──► purchase module
                                      webhook_events → orders → outbox (proof JWS in payload)

 4  producer ──waitUntil/inline──► orchestrator module ──► ai-platform /control/v1/*
                                      outbox (done), orders (provisioned_at)
                                      (* * * * * cron sweeps retries/failures)

 5  Flutter polls GET /v1/orders ──► purchase module
                                      (read orders only)

 6  Flutter ──status + receipt──► ai-platform ──► Clinic Supabase
                                      (§4.2 + clinic tables; not billing D1)
```

**All transactions** — what each communication does and which billing tables it touches
conceptually (R = read, W = write):

| Edge | Purpose | Billing D1 access |
| ---- | ------- | ----------------- |
| [0] Flutter → ai-platform · HTTP `GET /v1/plans` | List sellable plans with current prices and display copy, so client UIs never hardcode the catalogue (A17). | *(none — platform config cache; not billing D1)* |
| [1] Clinic Supabase → Flutter · RPC | Clinic signs a purchase intent (installation key, plan, org metadata) so Flutter can open checkout without holding the private key. | *(none — clinic tables only)* |
| [2] Flutter → purchase module · HTTP `POST /v1/orders` | Verify proof-of-possession signature, confirm the plan is sellable and no live order exists, open provider hosted checkout. | **R** platform `plan` catalogue — cached `GET /v1/plans` fetch: plan exists, current price/currency (not billing D1)<br>**R** `orders` — live-order guard per `installation_id`<br>**W** `orders` — new `pending` row (clinic identity snapshot, signed payload bytes, poll-token hash)<br>**W** `provider_refs` — provider checkout intention/transaction ids from the adapter<br>**W** `orders` — `checkout_url` and `checkout_expires_at` |
| [3a] Flutter → purchase module · HTTP `GET /v1/orders/{id}` | Poll purchase/renewal progress for the UI; response is provider-agnostic (status, period, checkout link). | **R** `orders` — `status`, period bounds, grace, checkout fields (auth via poll-token hash) |
| [3b] Flutter → purchase module · HTTP `POST /v1/orders/{id}/renewal-checkout` | Issue a new hosted checkout for renewal or plan change while order is `provisioned` or `past_due`. | **R** platform `plan` catalogue — cached fetch: target plan exists, current price<br>**R** `orders` — confirm order state allows renewal<br>**W** `provider_refs` — new checkout refs for this payment attempt<br>**W** `orders` — replace `checkout_url` / `checkout_expires_at` |
| [4] Payment provider → purchase module · HTTP `POST /v1/webhooks/{provider}` | Authoritatively record payment outcome (success, failure, refund); transition order state; mint purchase proof; queue platform provisioning and trigger it immediately (`ctx.waitUntil` on the new outbox row). | **R** `provider_refs` — map provider id → `order_id`<br>**R** `webhook_events` — idempotency on `(provider, provider_event_id)`<br>**W** `webhook_events` — log authenticated event + payload hash<br>**W** `orders` — status transition, period bounds, `paid_at`, latest `purchase_proof_id` on success<br>**W** `outbox` — enqueue `provision` (or refund-driven) job with the freshly minted proof JWS embedded in `payload` |
| [5] orchestrator module → ai-platform · waitUntil + cron sweeper + HTTPS `/control/v1/*` | Triggered immediately by the producer on enqueue (`ctx.waitUntil` or order-clock inline); drive platform `enroll` → `entitle` (or `renew` / `entitlement-suspend`) using CAT + purchase proof. The `* * * * *` cron sweeps due `pending` rows on failure or backoff. | **R** `outbox` — due `pending` rows (`payload` carries the exact JWS to present, on first attempt and every retry)<br>**R** `orders` — order context for the control call<br>**W** `outbox` — `done` / retry backoff / `failed`<br>**W** `orders` — `provisioned_at` when provision completes |
| [6] Order clock cron → purchase module · cron (§11.1) | Time-driven dunning: renewal checkout windows, `past_due` flips, suspend enqueue, terminal expiry. | **R** `orders` — rows crossing `period_end`, `grace_until`, expiry thresholds<br>**W** `orders` — status, `grace_until`, renewal checkout fields<br>**W** `outbox` — `entitlement_suspend` rows when grace expires unpaid; clock `await`s processor inline for those rows |
| [7] Billing reconciliation cron → ops · cron (§11.3) | Detect billing ↔ platform ↔ payout drift; persist findings for operator review. | **R** `orders` — `paid` / `provisioned` / `past_due` cohort<br>**R** `webhook_events` — payout cross-check<br>**R** platform (via `quota-inspect` / audit reads — not billing D1)<br>**W** `reconciliation_alert` — drift kind + JSON `detail` (order id, installation id, amounts) |
| [—] Vendor ops → purchase module · HTTP `POST /v1/ops/comp-orders` | Issue complimentary access (trial/goodwill) without payment — same grant path as a paid order (§6.5). | **R** `ops_operator` — per-operator key verification (§4.1.8)<br>**R** platform `plan` catalogue — cached fetch: plan exists<br>**W** `orders` — comp order through `paid` state (`comp_operator_id` attribution)<br>**W** `ops_jti` — token replay guard, same batch<br>**W** `outbox` — enqueue `provision` with the minted proof JWS in `payload`, and trigger it immediately via `ctx.waitUntil` |

Step [4]→[5] is the critical internal handoff: the **purchase** module mints the purchase proof
and enqueues `outbox` with the JWS embedded in `payload`; the **orchestrator** module (same
Worker) is invoked immediately via `ctx.waitUntil`
from the purchase handlers (webhook, comp-order) and inline from the order clock,
with the `* * * * *` cron handler remaining as sweeper for retries and dropped attempts. No HTTP
between the two modules — the table is the handoff and the durability mechanism: `waitUntil` is
best-effort, so a dropped or failed immediate attempt leaves the row `pending` for the sweeper.

**Foreign keys and logical joins** (no enforced FK on `reconciliation_alert`):


| Child table | Key column | Parent | Notes |
| ----------- | ---------- | ------ | ----- |
| `orders` | `plan` | platform `plan` catalogue | Not a local join — validated via the cached `GET /v1/plans` fetch (§4.1.6) |
| `orders` | `purchase_proof_id` | — (proof `jti`) | Latest minted proof id only; the JWS bytes live in `outbox.payload` and, after consumption, in the platform `purchase_proof` log (§4.2) |
| `provider_refs` | `order_id` | `orders` | Provider ids quarantined here |
| `webhook_events` | `order_id` | `orders` | Resolved via `provider_refs`; null if unresolvable |
| `outbox` | `order_id` | `orders` | `payload` embeds the minted proof JWS for that job |
| `reconciliation_alert` | — | `orders` (in `detail` JSON) | No FK; ops-facing drift record |

#### 4.1.2 orders

One row per purchase relationship (an order is long-lived across renewal periods; proposal §7.2
keeps one `order_id` with a new purchase proof per period):


| Column                                                     | Type          | Meaning                                                                                            |
| ---------------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------------------- |
| `order_id`                                                 | TEXT PK       | UUID, minted by the AI Billing Orchestrator                                                        |
| `installation_id`                                          | TEXT NOT NULL | From the clinic-signed order payload (§5.2)                                                        |
| `kid`                                                      | TEXT NOT NULL | Clinic signing key id from the order payload                                                       |
| `public_key`                                               | TEXT NOT NULL | Clinic public key (base64url) from the order payload                                               |
| `plan`                                                     | TEXT NOT NULL | Plan name — validated against the platform's `plan` catalogue, the single catalogue (A17, §4.1.6) |
| `status`                                                   | TEXT NOT NULL | State machine of §6.1                                                                              |
| `period_start` / `period_end`                              | TEXT          | Current paid period (null until first payment)                                                     |
| `grace_until`                                              | TEXT          | `period_end + grace_days` while `past_due` (§6.3)                                                  |
| `order_payload`                                            | TEXT NOT NULL | Exact clinic-signed payload bytes, as received                                                     |
| `order_signature`                                          | TEXT NOT NULL | Base64url detached signature over `order_payload`                                                  |
| `poll_token_hash`                                          | TEXT NOT NULL | SHA-256 (hex) of the order poll token (§5.4)                                                       |
| `checkout_url` / `checkout_expires_at`                     | TEXT          | Current checkout URL (initial or renewal) and its expiry                                           |
| `purchase_proof_id`                                        | TEXT          | Latest purchase proof id minted for this order (the JWS `jti`; the proof bytes live in `outbox.payload`, §4.1.5) |
| `comp_operator_id`                                         | TEXT          | `ops_operator.operator_id` of the issuing operator — comp orders only (§6.5, §11.2)                |
| `created_at` / `paid_at` / `provisioned_at` / `updated_at` | TEXT          | Lifecycle timestamps                                                                               |

**The identity columns are an as-purchased snapshot, not a registry mirror.** `installation_id`,
`kid`, and `public_key` are copied from the clinic-signed payload at order creation and are
never re-synced from the platform: they bind the money to the key material the clinic held
*when it paid*, which is exactly what the purchase proof and platform enroll must commit to
(§5.2). Clinic-side key rotation or an org rename does not propagate — by design. The
`org_id` / `display_name` / `region` metadata is deliberately **not** stored as columns; it
already lives inside the stored `order_payload` bytes on the same row, and the orchestrator
parses it from there at orchestration time (enroll, §8.2) — one less drift point.
**Key-rotation rule:** if the clinic has rotated its installation key since the order was
created, the order's key material is stale and the order cannot be renewed — renewal-checkout
re-validates the key material against the platform and a rotated clinic must create a fresh
order (§5.4, §6.4).

One **live** order per installation, enforced by a partial unique index:
`CREATE UNIQUE INDEX idx_orders_live_installation ON orders (installation_id) WHERE status IN ('pending','paid','provisioned','past_due');`
A clinic whose order reached a terminal state (`expired`, `refunded`, `chargeback`,
`cancelled`) may purchase again — the platform-side reactivation path is `renew`, not `enroll`
(§6.2).

#### 4.1.3 provider_refs

The quarantine table. Every provider-assigned identifier lives here and nowhere else (§7.2):


| Column         | Type                     | Meaning                                                     |
| -------------- | ------------------------ | ----------------------------------------------------------- |
| `ref_id`       | TEXT PK                  | UUID                                                        |
| `order_id`     | TEXT NOT NULL → `orders` | Owning order                                                |
| `provider`     | TEXT NOT NULL            | Adapter id, e.g. `paymob`                                   |
| `kind`         | TEXT NOT NULL            | `checkout` \| `intention` \| `settlement`                    |
| `provider_ref` | TEXT NOT NULL            | The provider's identifier (intention id, transaction id, …) |
| `created_at`   | TEXT NOT NULL            |                                                             |


`UNIQUE (provider, kind, provider_ref)` lets a webhook resolve its order without the provider's
id ever appearing in `orders`, purchase proofs, or audit rows.

#### 4.1.4 webhook_events

Idempotent, provider-signature-verified event log:


| Column                         | Type          | Meaning                                                     |
| ------------------------------ | ------------- | ----------------------------------------------------------- |
| `event_id`                     | TEXT PK       | UUID                                                        |
| `provider`                     | TEXT NOT NULL | Adapter id                                                  |
| `provider_event_id`            | TEXT NOT NULL | Provider's unique event/transaction id                      |
| `canonical_event`              | TEXT NOT NULL | One of the §7.1 canonical events                            |
| `order_id`                     | TEXT          | Resolved via `provider_refs`; null if unresolvable          |
| `payload_hash`                 | TEXT NOT NULL | SHA-256 (hex) of the raw body — tamper-evidence for the log |
| `received_at` / `processed_at` | TEXT          |                                                             |
| `status`                       | TEXT NOT NULL | `processed` \| `failed` — failures after the idempotency insert are marked `failed` and recovered via the outbox, not the provider (§5.5) |


`UNIQUE (provider, provider_event_id)` is the idempotency key: a redelivered webhook is an
insert conflict → `200` with no re-processing.

#### 4.1.5 outbox

The in-process handoff from purchase module to orchestrator (proposal §3; a table, not a queue
— constitution-compliant): each producer that inserts a row triggers immediate processing after
its D1 batch commits — the payment webhook handler and the comp-order ops endpoint call
`ctx.waitUntil(processor(outbox_id))` (one attempt, best-effort); the order-clock cron
`await`s the same processor inline after enqueueing `entitlement_suspend` rows. The `* * * * *`
cron remains as a **sweeper**: it drains rows still `pending` and due when an immediate attempt
failed, backoff retries are due, or a `waitUntil` task was dropped (isolate eviction/crash).
`waitUntil` is a latency optimization only; the row is the durability mechanism and the sweeper
is the liveness floor. The shared processor claims a row atomically (`UPDATE … SET status =
'processing' … WHERE status = 'pending' AND next_attempt_at ≤ now`) so the immediate trigger
and the sweeper cannot double-process the same row; platform-side idempotency (409 mappings,
§11.1) is the backstop if a claim races anyway.


| Column                        | Type                     | Meaning                                                     |
| ----------------------------- | ------------------------ | ----------------------------------------------------------- |
| `outbox_id`                   | TEXT PK                  | UUID                                                        |
| `kind`                        | TEXT NOT NULL            | `provision` \| `entitlement_suspend`                         |
| `order_id`                    | TEXT NOT NULL → `orders` |                                                             |
| `payload`                     | TEXT NOT NULL            | JSON: purchase proof JWS plus the control-call parameters (enroll metadata is parsed from the order's stored `order_payload`, §4.1.2) |
| `status`                      | TEXT NOT NULL            | `pending` → `processing` → `done` or `failed`             |
| `attempts`                    | INTEGER NOT NULL         |                                                             |
| `next_attempt_at`             | TEXT NOT NULL            | Exponential backoff, cap 10 attempts → `failed` + alert log |
| `last_error`                  | TEXT                     |                                                             |
| `created_at` / `processed_at` | TEXT                     |                                                             |

**The outbox is also the minting ledger.** The minted purchase-proof JWS is embedded in
`payload` at enqueue time, and outbox rows are **never purged**: `done` rows persist as the
durable record of what was minted and presented, so retries re-present the identical token
(purchase proofs are single-use platform-side, §5.7) and billing reconciliation can audit
minting. An earlier draft of this design kept a separate `purchase_proofs` table for that
ledger role; it was dropped because the outbox `payload` already carries the JWS — the second
copy was redundant. The platform-side `purchase_proof` table (§4.2) **stays**: it is the
consumption log and replay guard, and the co-location rule (§5.1) requires it to live in the
enforcing store — a guard that lives in the caller's database is no guard at all.

#### 4.1.6 No local plan table — the platform catalogue is the single source

The AI Billing Orchestrator holds **no plan or price table**. Plan names, subscription prices, and
display copy live in exactly one place: the platform's `plan` catalogue, which carries
`price_cents` / `currency` / `display_name` / `description` alongside the economics (platform
amendment A17) **and `grace_days`** — the single source for the grace / renewal-lead / payable-tail
timing constants (§6.3). The AI Billing Orchestrator's order clock reads grace and renewal timing
from this same cached fetch, and the platform computes receipt `valid_until = period_end +
grace_days` from the same catalogue value (§5.8) — the two sides agree because both read one
catalogue, not because two deployables hardcode the same constant. The initial value is 7 days.
The purchase module reads the catalogue through a cached server-side fetch of
`GET /v1/plans` (§5.10) — at order creation, at renewal checkout, and at comp-order validation.

This deletes an entire drift class: there is no both-tables sellability rule, no CI drift check,
and no "paid order wedges at `enroll` because a name exists in only one store" failure mode. The
price used at checkout is the catalogue's *current* price; the price *paid* is bound into the
purchase proof's `amount_cents` / `currency` claims (§5.7), so invoices (G4) and reconciliation
never re-lookup a catalogue price.

**Cache behaviour.** The fetch is cached per isolate in memory for the endpoint's
`Cache-Control` max-age (300 s) — the mechanism named in §2.4. A
price change propagates to new checkouts within minutes; a paid order is never repriced, so
staleness can only delay a *new* price's visibility, never misquote an open period. A catalogue
fetch failure at order time fails the request with `502 catalogue_unavailable` — selling against
an unverifiable catalogue is worse than a retryable error.

**Contract test.** A contract test pins that `GET /v1/plans` serves **exactly** the
`status = 'active'` rows, each with price (`price_cents` / `currency`) and `grace_days` — so the
ABO-side "plan exists and is active" validation (against the cached fetch) and the
platform-side validation at enroll/entitle/renew (against the catalogue directly, §8.2) are
provably the same rule, not two implementations that can drift.

#### 4.1.7 reconciliation_alert

Drift findings from the daily job (§11):


| Column            | Type          | Meaning                                           |
| ----------------- | ------------- | ------------------------------------------------- |
| `alert_id`        | TEXT PK       | UUID                                              |
| `kind`            | TEXT NOT NULL | `payment_without_entitlement` \| `entitlement_without_payment` \| `payout_mismatch` (§11.3) |
| `detail`          | TEXT NOT NULL | JSON context (order id, installation id, amounts) |
| `created_at`      | TEXT NOT NULL |                                                   |
| `acknowledged_at` | TEXT          | Operator review marker                            |

#### 4.1.8 ops_operator and ops_jti

Per-operator authentication for `/v1/ops/*` — the same pattern as the platform's
`control_operator` (§4.2), applied to the AI Billing Orchestrator's own ops surface from day one. There is no
shared ops bearer (§11.2).

`ops_operator`:

| Column            | Type          | Meaning                                       |
| ----------------- | ------------- | --------------------------------------------- |
| `key_id`          | TEXT PK       | Token header `kid`                            |
| `operator_id`     | TEXT NOT NULL | Attribution — recorded on comp orders         |
| `public_key`      | TEXT NOT NULL | base64url raw 32-byte Ed25519                 |
| `allowed_actions` | TEXT NOT NULL | JSON array, e.g. `["comp-order"]`             |
| `revoked_at`      | TEXT          | Fast revocation                               |
| `created_at`      | TEXT NOT NULL |                                               |

`ops_jti`: `jti` PK, `operator_id`, `expires_at` — the replay store for ops tokens, purged by
the order-clock cron; insert-if-absent in the same batch as the comp-order write (co-location
rule, §5.1).

Bootstrap and rotation are `wrangler d1` statements under Cloudflare account IAM (per-person,
audited by Cloudflare) — ops scale does not justify a self-service key API.

**Dual-registry provisioning.** A human operator who both issues comp orders and performs
platform incident response needs their public key in **both** registries — `ops_operator` here
and `control_operator` on the platform (§4.2), which are schema-identical by design. One
provisioning script/runbook registers the operator into both atomically, so the two registries
cannot drift into divergent identity config (§11.2).




### 4.2 Platform D1 additions

One forward-only migration in `ai-platform/migrations/` (implementation-time timestamp), plus a
second for the audit column. All verified against
`20260731120000_platform_schema.sql` and `20260911120000_plan_catalogue.sql`.

`control_operator` — per-caller keys and scopes (replaces the single shared bearer as the
grant-path credential):

```sql
CREATE TABLE control_operator (
  key_id          TEXT PRIMARY KEY NOT NULL,   -- CAT header kid
  operator_id     TEXT NOT NULL,               -- attribution identity, e.g. "orchestrator", "haytham"
  public_key      TEXT NOT NULL,               -- base64url raw 32-byte Ed25519
  allowed_actions TEXT NOT NULL,               -- JSON array, e.g. ["enroll","entitle","renew","entitlement-suspend"]
  revoked_at      TEXT,
  created_at      TEXT NOT NULL
);
```

One operator may hold many keys (rotation, §3.4); `operator_id` is what lands in
`control_audit.operator_id`, replacing today's single `OPERATOR_ID` env attribution.

`control_cat_jti` — CAT replay store (§13 item 7 for the D1-vs-DO decision):

```sql
CREATE TABLE control_cat_jti (
  jti         TEXT PRIMARY KEY NOT NULL,
  operator_id TEXT NOT NULL,
  expires_at  TEXT NOT NULL                    -- CAT exp + skew; purged by the existing scheduled handler
);
```

`purchase_proof` — consumption log; the replay guard for grants:

```sql
CREATE TABLE purchase_proof (
  purchase_proof_id TEXT PRIMARY KEY NOT NULL,    -- purchase proof JWS jti
  order_id       TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  kind           TEXT NOT NULL,                -- purchase | renewal | comp
  period_start   TEXT NOT NULL,
  period_end     TEXT NOT NULL,
  amount_cents   INTEGER NOT NULL,             -- paid amount from the proof claims (§5.7)
  currency       TEXT NOT NULL,                -- ditto
  processed_at   TEXT NOT NULL
);
```

The `INSERT` into this table is part of the **same D1 batch** as the entitlement mutation it
authorizes, so a replay races to a PRIMARY KEY conflict and the whole grant rolls back.

`entitlement` **gains two columns** (proposal §4.4):

```sql
ALTER TABLE entitlement ADD COLUMN order_id TEXT;
ALTER TABLE entitlement ADD COLUMN purchase_proof_id TEXT;  -- latest purchase proof that (re)granted
CREATE UNIQUE INDEX idx_entitlement_order_id ON entitlement (order_id) WHERE order_id IS NOT NULL;
```

`order_id` UNIQUE makes one payment unable to entitle two installations; the partial index keeps
legacy rows (null `order_id`) untouched. `purchase_proof_id` on the row is informational (latest);
replay protection lives in the `purchase_proof` table, which retains **every** consumed id.

`control_audit` **gains** `order_id TEXT` (nullable) — every grant traces to a payment
(proposal §4.7); null only for non-grant actions and pre-migration rows.

Two further platform-side column additions land with the A17 catalogue amendment pass (they
are recorded here because this design depends on them):

- `plan` **gains** `grace_days INTEGER NOT NULL DEFAULT 7` — served by `GET /v1/plans`
  (§5.10) and the single source for dunning timing on both sides (§4.1.6, §6.3, §11.1).
- `invoice` **gains** `purchase_proof_id TEXT` (nullable; alternatively `order_id`) — so the
  chain invoice → proof → order is navigable in data, and period close (G4) prices the invoice
  from the consumed proof's `amount_cents` / `currency`, never from a catalogue re-lookup
  (§5.7, §6.4).

## 5. Wire contracts

All HTTP paths on both origins are versioned: client/ops endpoints under `/v1/…`, server-to-server control-plane endpoints under `/control/v1/…`. A breaking change increments the version prefix; unversioned paths are never served.

### 5.1 Canonicalization rules

**There is no JSON canonicalization anywhere in this design.** Every signature covers the exact
bytes transported:

- JWS compact serialization is self-canonicalizing: the signed input is the literal
`base64url(header) || "." || base64url(payload)` string. Verifiers recompute over the received
segments, never over a re-serialized parse — this is already how `EnrolledKeyVerifier` and
`auth_internal.verify_aat` work.
- The clinic-signed order payload (§5.2) is signed **as produced by the RPC** and transported
verbatim as a string field; the AI Billing Orchestrator verifies the signature over those exact bytes before
parsing. Field order, whitespace, and number formatting are therefore irrelevant.
- The CAT body hash (§5.6) is SHA-256 over the **raw request body bytes**; for routes that read
no body (existing body-ignoring routes such as `suspend`), it is the hash of the empty string.

This removes the entire class of canonicalization mismatches between Postgres, Workers, and
Flutter. The cost — payloads must be transported unmodified — is paid by making the payload an
opaque string in every envelope that carries it.

All three JWS types pin `alg: "EdDSA"` in the header and reject anything else, matching the
existing verifier (`header.alg !== "EdDSA"` → reject) so `none`/HMAC confusion is impossible.

**The replay-guard co-location rule.** Every single-use credential in this system is consumed in
the same store and the same atomic unit as the action it protects: the CAT `jti` inserts with the
control mutation, the purchase proof `jti` inserts in the grant's D1 batch, the webhook event id
inserts with event processing, the AAT `jti` lives in the Quota DO that admits the request. A
replay guard that lives outside the enforcing store — or commits in a separate transaction — is
a race window, not a guard. This is why each service keeps its own replay tables rather than
sharing one.

**Error style.** Two families, named once: clinic-facing data-path endpoints (platform `/v1/*`)
use the taxonomy envelope (`{ code, request_reference, trace_id, retry_safe, … }`);
control-plane-family endpoints — platform `/control/v1/*` and **all AI Billing Orchestrator endpoints** —
use the flat `{"error": "<snake_code>"}` body. Flutter maps ABO error codes to UI states; the
taxonomy machinery is not imported into the AI Billing Orchestrator.

### 5.2 Order payload and clinic proof of possession

The clinic's order-signing RPC (§9.1) returns two strings; Flutter transports them unmodified:

```json
{
  "order_payload": "{\"display_name\":\"…\",\"installation_id\":\"…\",…}",
  "signature": "<base64url Ed25519 detached signature over the UTF-8 bytes of order_payload>"
}
```

`order_payload` is a JSON object with **exactly** these fields (produced by
`jsonb_build_object`, which fixes key order alphabetically — a convenience, not a requirement,
since the bytes are signed as-is):


| Field             | Source                                     | Consumed by                                                   |
| ----------------- | ------------------------------------------ | ------------------------------------------------------------- |
| `installation_id` | `ai_internal.installation_keys` active row | ABO `orders`; platform enroll path equality check             |
| `kid`             | active key row                             | ABO `orders`; platform enroll                                 |
| `public_key`      | active key row, base64url                  | ABO PoP verification; platform enroll                         |
| `plan`            | RPC argument, validated non-empty          | ABO catalogue check (cached `GET /v1/plans`); platform enroll → `entitlement.plan` |
| `org_id`          | clinic `organizations.id`                  | enroll metadata                                               |
| `display_name`    | clinic org name                            | enroll metadata                                               |
| `region`          | app setting / RPC default                  | enroll metadata                                               |
| `nonce`           | `gen_random_uuid()`                        | single-use freshness at order creation                        |
| `issued_at`       | `clock_timestamp()`                        | the AI Billing Orchestrator rejects payloads older than 24 h  |


Billing verifies the signature with the `public_key` **inside the payload** — at order time the
platform does not know the clinic yet, so this is self-signed proof of possession, not
authentication against a registry. That is sufficient because of how the chain closes: the paid
order binds money to `(installation_id, kid, public_key)`; the purchase proof carries the same
triple; platform enroll registers exactly that key; and from then on every AAT must verify
against it. An attacker who substitutes their own keypair has bought AI service for an
installation only they can mint tokens for — payment redirection gains nothing.

### 5.3 `POST /v1/orders` (AI Billing Orchestrator)

Unauthenticated in the HTTP sense — the PoP signature **is** the authorization. Rate-limited per
source IP at the platform edge (Cloudflare rate-limiting rule, same mechanism family as the
ai-platform `[env.*.ratelimits]` bindings).

**Request:**

```json
{ "order_payload": "<string>", "signature": "<base64url>" }
```

**Verification order:** JSON parse → required fields → payload age (`issued_at` within 24 h) →
`public_key` decodes to 32 bytes → `crypto.subtle.verify` over exact payload bytes → plan exists
in the platform catalogue (cached `GET /v1/plans` fetch, §4.1.6) → no live order for
`installation_id` (partial unique index, §4.1).
 
**Then:** insert `orders` (`status = pending`; `installation_id` / `kid` / `public_key` stored as
the as-purchased identity snapshot, §4.1.2; poll token generated — 256-bit random, stored as
SHA-256 hex) → adapter `create_checkout(order, price)` with the catalogue's current price for the
plan → store returned refs in `provider_refs` → update `checkout_url`.

**Success** `201`**:**

```json
{
  "order_id": "<uuid>",
  "status": "pending",
  "checkout_url": "https://…",
  "checkout_expires_at": "<ISO>",
  "poll_token": "<256-bit random, base64url>"
}
```

`poll_token` is returned **once**, here, and never again (only its hash is stored).

**Errors:** `400 invalid_payload` (shape/age/key), `400 invalid_signature`,
`404 plan_not_found`, `409 order_exists` (a live order already exists for this installation —
the response includes that order's `order_id` so a restarted client can resume, but **not** a
new poll token), `502 provider_error`, `502 catalogue_unavailable` (the platform catalogue fetch
failed — retryable; §4.1.6).

### 5.4 `GET /v1/orders/{order_id}` (AI Billing Orchestrator)

Polled by Flutter during purchase and renewal. Auth: `Authorization: Bearer <poll_token>`,
compared as SHA-256 hex against `poll_token_hash` (timing-safe string compare, same helper
family as `timingSafeEqualString` in `control/auth.ts`). An unknown order **or** a wrong token
returns the same `404` — order existence is not enumerable.

**Success** `200`**:**

```json
{
  "order_id": "<uuid>",
  "status": "pending | paid | provisioned | past_due | refunded | chargeback | expired | cancelled",
  "plan": "standard",
  "period_start": "<ISO|null>",
  "period_end": "<ISO|null>",
  "grace_until": "<ISO|null>",
  "checkout_url": "<string|null>",
  "checkout_expires_at": "<ISO|null>"
}
```

`checkout_url` is non-null while payable: initially, and again from `period_end − grace_days`
until terminal state (the renewal checkout, §6.3). No provider identifiers, no amounts beyond what the
clinic already knows — the response is provider-agnostic by construction.

`POST /v1/orders/{order_id}/renewal-checkout` — the self-service plan-change and on-demand
renewal path. Auth: the same poll-token Bearer rule as the GET, with the same uniform `404`.
Body `{ "plan": "<plan name>" }`. Valid while the order is `provisioned` or `past_due`.
Validates the plan against the platform catalogue (cached `GET /v1/plans` fetch, §4.1.6), runs
the adapter `create_checkout` for that plan's
current catalogue price, stores the new refs in `provider_refs`, and replaces `checkout_url` /
`checkout_expires_at` on the order. The new plan takes effect when the renewal is paid and
`renew` applies it (§6.4).

**Key-rotation re-validation.** Before opening the checkout, the AI Billing Orchestrator
re-validates the order's key material against the platform through an authenticated read
(orchestrator-scoped `quota-inspect` / `support-lookup`, §5.6): the `kid` / `public_key` in the
order's as-purchased snapshot (§4.1.2) must still be the installation's active enrolled key. If
the clinic has rotated keys since the order was created, the order **must be re-created** — the
endpoint fails with `409 key_rotated` and the clinic starts a fresh order with a newly signed
payload (§5.3), because the purchase proof and enroll bind the as-purchased key material and a
renewal cannot re-bind them. The order clock's pre-issued renewal checkouts (§11.1) run the
same check before calling the adapter.

Errors: `400 invalid_payload`, `404 plan_not_found`,
`409 illegal_state` (terminal orders), `409 key_rotated` (clinic rotated keys — fresh order
required), `502 provider_error`, `502 catalogue_unavailable`.
When the order's current plan has been retired, this endpoint is the **only** renewal checkout
path — the order clock does not pre-issue a URL for non-sellable plans (§6.6).

### 5.5 `POST /v1/webhooks/{provider}` (AI Billing Orchestrator)

The only provider-shaped surface in the system, and it is owned entirely by the adapter.

**Verification order (Paymob):** extract `hmac` query parameter → parse body → recompute
HMAC-SHA512 over the documented 20-field concatenation of `body.obj` (booleans as literal
`true`/`false`, no separators) keyed by `PAYMOB_HMAC_SECRET` → timing-safe hex compare →
idempotency lookup on `(provider, provider_event_id)`: already present → return `200` with no
re-processing, regardless of the event's age → resolve order via `provider_refs`
(`obj.order.id` / transaction id) → insert `webhook_events` → map to canonical event →
transition the order (§6.1) → enqueue outbox rows.

The idempotency table is the authoritative replay guard; there is **no timestamp rejection
gate**. A replayed authentic payload is either already processed (duplicate → `200`) or a
legitimate event whose first delivery never completed — processing it is correct. A time-based
rejection would lose exactly those legitimate redeliveries, which arrive with the provider's
original timestamp long after the first attempt. `obj.created_at` is recorded on the
`webhook_events` row for observability only.

Failures before the idempotency insert return `400`; the provider retries. Failures after it are
retried by the outbox mechanism, not by the provider. The endpoint always responds `200`
to a well-formed, authentic duplicate.

After the D1 batch commits (order transition, purchase proof, outbox row), the handler calls
`ctx.waitUntil` to run the shared outbox processor for the new row immediately — provisioning
starts in seconds instead of waiting for the sweeper cron; the HTTP response to the provider is
still returned without awaiting the processor. If the `waitUntil` task is dropped or the attempt
fails, the row stays `pending` with backoff and the sweeper retries it.

The **redirect URL** (`redirection_url` on the intention) is UX only — its query parameters are
not trusted for order state (Paymob's own guidance: the callback is authoritative). Flutter
never sees it; the clinic owner simply closes the browser tab and the app's polling observes the
webhook's effect.

### 5.6 CAT — Control Action Token

Replaces the operator bearer on **every** control route — the bearer is removed, not scoped
(§8.1). Compact JWS, sent as
`Authorization: CAT <token>`.

**Header:** `{ "alg": "EdDSA", "kid": "<control_operator.key_id>" }`

**Claims:**


| Claim         | Value                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------- |
| `iss`         | `operator_id` (e.g. `orchestrator`, or a human's id)                                     |
| `aud`         | `"ai-platform-control"`                                                                  |
| `iat` / `exp` | Unix seconds; `exp − iat ≤ 120` enforced                                                 |
| `jti`         | UUID; single-use (§4.2 `control_cat_jti`)                                                |
| `act`         | The control action: `enroll`                                                             |
| `tgt`         | Target installation id for installation-scoped actions; `""` otherwise                   |
| `bh`          | Base64url SHA-256 of the raw request body bytes (empty-string hash for body-less routes) |


**Verification order** (new CAT `OperatorAuth` factory, §8.1): three-segment structure →
`alg` pin → `kid` → `control_operator` row (not revoked) → Ed25519 signature → `aud` →
`iat`/`exp` with 60 s skew and max-lifetime check (mirrors `MAX_AAT_LIFETIME_SECONDS`) →
`act` equals the route's action **and** is in the row's `allowed_actions` → `tgt` equals the
path installation id where applicable → `bh` equals SHA-256 of the raw body (the auth layer
reads `request.clone()` so handlers still parse the body normally) → `jti` insert-if-absent
(conflict → `401`). Any failure → `401 { "error": "unauthorized" }` — the control plane keeps
its no-403 convention.

The orchestrator's key holds exactly `["enroll","entitle","renew","entitlement-suspend","quota-inspect","support-lookup"]`.
Human keys hold their roles' subsets. **No key holds both a grant action and the purchase proof
signing key's job** — the two-signature rule is enforced by key custody, not by code
convention.

### 5.7 Purchase Proof

Minted by the AI Billing Orchestrator purchase module when money moves (or a comp order is issued); verified by the platform's `enroll` and
**consumed** only by `entitle` / `renew` / `override`. `enroll` never consumes the `jti`: it
grants nothing (the entitlement it creates stays `pending` with zero quotas), and its replay is
already blocked by `409 already_enrolled` and the purchase proof's installation binding — so the
provision flow can present the same purchase proof to `enroll` and then to `entitle`, which claims
the `jti`. Compact JWS, carried in the control request body as `{ "purchase_proof": "<token>" }`.

**Header:** `{ "alg": "EdDSA", "kid": "bill-<n>" }`

**Claims:**


| Claim                         | Value                                                                                    |
| ----------------------------- | ---------------------------------------------------------------------------------------- |
| `iss`                         | Billing issuer id (platform var `BILLING_ISSUER`, e.g. `"ai-billing-orchestrator"`)      |
| `aud`                         | `"ai-platform-control"`                                                                  |
| `jti`                         | `purchase_proof_id` (UUID) — replay key into the platform `purchase_proof` table         |
| `iat` / `exp`                 | `exp = iat + 72 h` — sized for outbox retry windows; single-use makes a long life safe   |
| `kind`                        | `purchase` \| `renewal` \| `comp`                                                        |
| `order_id`                    | Billing order UUID                                                                       |
| `installation_id`             | Bound installation                                                                       |
| `kid` / `public_key`          | Clinic key material from the order (enroll validates the body against these)             |
| `plan`                        | Plan name — resolved through the G1 catalogue by the handler, never trusted as economics |
| `period_start` / `period_end` | ISO-8601 instants; `period_start < period_end`                                           |
| `amount_cents` / `currency`   | The price actually paid for this period (`0` for comp orders) — stored on the platform `purchase_proof` row at consumption so period close (G4) prices the invoice from what was paid, never from a catalogue re-lookup (A17) |


**Platform verification (shared verifier module):** structure → `alg` pin → `kid` → public key
from `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` within its validity window → signature → `iss`/`aud` →
`exp`/`iat` with 60 s skew → `installation_id` equals the path id → action-specific checks:
`enroll` additionally requires body `kid`/`public_key`/`plan` equal to the claims; `entitle`
requires `kind ∈ {purchase, comp}` and entitlement `pending`; `renew` requires entitlement
`active` or `suspended`; `override` requires `kind = comp`. The `entitle` / `renew` / `override` batch then inserts
`purchase_proof` (jti …) — a conflict rolls the grant back with `409 purchase_proof_replayed`.

### 5.8 Provisioning Receipt

Minted by the platform inside `GET /v1/installation/status` when (and only when) the
installation and entitlement are both `active`. Compact JWS, transported by Flutter, verified by
the clinic's `set_ai_availability` RPC.

**Header:** `{ "alg": "EdDSA", "kid": "rcpt-<n>" }`

**Claims:**


| Claim               | Value                                                                            |
| ------------------- | -------------------------------------------------------------------------------- |
| `iss`               | `"ai-platform"`                                                                  |
| `aud`               | The `installation_id` — a receipt for clinic A cannot activate clinic B          |
| `iat` / `exp`       | `exp = iat + 15 min` — the receipt is a transport proof, not a stored credential |
| `status`            | `"active"` (receipts are never minted for any other state)                       |
| `plan`              | Current plan name (display only)                                                 |
| `period_end`        | Current paid period end                                                          |
| `valid_until`       | `period_end + grace_days` from the plan catalogue (§5.10) — the clinic-side self-expiry instant (§6.3) |
| `platform_base_url` | The Worker's origin — what the clinic stores and calls                           |


**Clinic verification** (`auth_internal.set_ai_availability`, §9.2): three segments → header
`alg = EdDSA` → `kid` found in `ai.platform_receipt_keys` and not revoked →
`pgsodium.crypto_sign_verify_detached` over the exact signing input (the
`verify_aat` pattern) → `iss` → `aud` equals the clinic's own `installation_id` →
`exp` not passed → `status = "active"`. Only then is `ai.availability` written.

### 5.9 Platform status and key endpoints

`GET /v1/installation/status` — AAT-authenticated, reusing `EnrolledKeyVerifier` exactly as
discovery and the journal GET do (`authenticateGetRequest` pattern, audience `"ai-platform"`,
60 s skew). Identity passes for an enrolled installation even while its entitlement is
`pending` or `suspended` — that is what makes pull-based activation and self-healing work.

Success `200`:

```json
{
  "installation_id": "<uuid>",
  "installation_status": "active",
  "entitlement_status": "pending | active | suspended",
  "plan": "standard",
  "period_end": "<ISO|null>",
  "receipt": "<compact JWS — present only when both statuses are active>"
}
```

Errors follow the taxonomy: `401 unauthenticated`, `403 installation_suspended`. Reads come
from the config cache (warm isolate: no D1 I/O, the A5 pattern); receipt signing is one
`crypto.subtle.sign` per call — no DO, no journal row.

`GET /v1/platform-keys` — unauthenticated, cacheable:

```json
{ "keys": [ { "kid": "rcpt-1", "kty": "OKP", "crv": "Ed25519", "x": "<base64url>", "valid_from": "<ISO>" } ] }
```

Served from the `PLATFORM_RECEIPT_PUBLIC_KEYS` var. Flutter fetches it during activation and
re-fetches once on `unknown kid` receipt-verification failure (§3.5).

### 5.10 `GET /v1/plans` (ai-platform)

The sellable-plan read path — served by the **platform**, not the AI Billing Orchestrator, because the
platform's `plan` catalogue is the single plan and pricing catalogue (platform amendment A17;
§4.1.6). Unauthenticated and cacheable, edge rate-limited; prices are not secrets — they are
displayed on the provider's hosted checkout page — so the endpoint needs no credential, mirroring
the `GET /v1/platform-keys` precedent (§5.9). Reads come from the config cache (warm isolate: no
D1 I/O, the A5 pattern).

**Success `200`:**

```json
{
  "plans": [
    {
      "plan": "standard",
      "display_name": "Standard",
      "description": "…",
      "price_cents": 150000,
      "currency": "EGP",
      "grace_days": 7
    }
  ]
}
```

- **Source:** `plan` rows with `status = 'active'`, served from the config cache — exactly the
  active rows, each with price and `grace_days` (pinned by the §4.1.6 contract test).
  `grace_days` is the single source for dunning timing on both sides: the ABO order clock
  (§11.1) reads it from this payload, and receipt minting computes
  `valid_until = period_end + grace_days` from the same value (§5.8).
- **Caching:** `Cache-Control: public, max-age=300`. A price change propagates to clients within
  minutes; open periods are never repriced (the paid amount is bound into the purchase proof,
  §5.7), so staleness can only delay a *new* price's visibility, never misquote an open period.
- The response is identical for every caller: no per-clinic data, no provider identifiers.

Two consumers: Flutter calls this when the purchase surface opens and when the renewal banner
renders plan selection (§10.1, §10.3) — plan names, prices, and display copy are never shipped in
the app; and the AI Billing Orchestrator purchase module fetches it server-side (cached, §4.1.6) to
validate and price `POST /v1/orders`, renewal checkouts, and comp orders.

## 6. State machines and dunning policy



### 6.1 Order state machine (AI Billing Orchestrator)

```
                 create_checkout
 POST /v1/orders ─────────────────► pending ──payment_succeeded──► paid ──outbox: provision──► provisioned
                                    │                            │                              │
                                    │ payment_failed /           │ refunded /                   │ period_end − grace_days:
                                    │ checkout expiry            │ chargeback                   │ renewal checkout issued
                                    ▼                            ▼                              ▼
                                cancelled ◄──────────────── (terminal states)            provisioned (renewal due)
                                                                                              │
                                              period_end, unpaid                              │ renewal_paid
                                                                                              ▼
                                                          past_due ──renewal_paid──► provisioned (new period)
                                                              │
                                                              │ grace_until passes, unpaid
                                                              ▼
                                              past_due (suspended) ── outbox: entitlement_suspend fired
                                                              │
                                                              │ period_end + grace_days + 30d, unpaid
                                                              ▼
                                                          expired (terminal)
```

Rules:

- `pending → paid` on the canonical `payment_succeeded` event only (webhook-verified, §5.5) or
a comp order issuance (§6.5), which transitions `pending → paid → provisioned` without any
provider interaction.
- `paid → provisioned` when the outbox `provision` job completes (triggered immediately on
enqueue via `ctx.waitUntil`; platform enroll + entitle succeeded). A failed provisioning leaves
the order `paid` and retries via the outbox sweeper — money received always eventually
provisions or alerts.
- `provisioned → past_due` is time-driven: the daily cron flips orders whose `period_end` has
passed without a renewal payment, setting `grace_until = period_end + grace_days` (catalogue
value, §6.3).
- `past_due → provisioned` on `renewal_paid` (new period bounds from the payment date, §6.4).
- `past_due → expired` at `period_end + grace_days + 30 days` (grace + 30-day payable tail).
- `refunded` / `chargeback` are reachable from `paid`, `provisioned`, or `past_due` and are
terminal. Both fire an outbox `entitlement_suspend` **immediately** — no grace when money was
clawed back.
- `cancelled` is reachable from `pending` only (abandoned or expired checkout, or adapter
`cancel`).



### 6.2 Entitlement state machine (platform)

```
 enroll (purchase proof: purchase|comp)          entitle (purchase proof: purchase|comp)
 ───────────────────────────────► pending ──────────────────────────────────► active
                                                                               │  ▲
                                          entitlement-suspend (CAT, no         │  │ renew (purchase proof:
                                          purchase proof — suspending grants      │  │ purchase|renewal|comp)
                                          nothing)                             ▼  │
                                                                           suspended
```

- `pending` is the enroll sentinel: zero quotas, closed empty period — unchanged from Band B/G.
- `active → suspended` only via the new `entitlement-suspend` control action (orchestrator CAT;
no purchase proof required — it grants nothing).
- `suspended → active` **only** via `renew` with a fresh purchase proof. There is no
entitlement-resume action, so restoring service after a non-payment suspension is always
two-key gated. This is deliberate: it is what makes "humans can stop abuse but can never
grant service" hold for the orchestration path too.
- The guard already rejects any `status ≠ active` with `forbidden_capability` / `ai_disabled`
(`src/entitlement/index.ts`) — no guard change is needed for the new status value.
- Installation-level `suspend`/`resume` (existing, installation.status) remain the **human**
incident-response tools and are untouched. The two suspension axes are independent: an
abuse-suspended installation stays rejected at identity even if a renewal payment arrives and
reactivates the entitlement — renew never touches `installation.status`.

**Code-verified correction:** the guard does **not** evaluate `period_end` (verified in
`src/entitlement/index.ts` and `src/quota-do/index.ts` — the DO resets counters when period
bounds change but never rejects on expiry). Non-payment is therefore enforced by two explicit
mechanisms, not by the calendar: the receipt's `valid_until` expires the clinic UI flag, and
the orchestrator's `entitlement-suspend` closes the guard. See §14, deviation 1.

### 6.3 Dunning and grace policy — decided

Proposal §12 item 1, resolved. All three timing constants (renewal lead, grace, receipt
self-expiry) derive from **`grace_days` on the plan catalogue row**, served by `GET /v1/plans`
(§5.10): the ABO order clock reads them from its cached catalogue fetch (§11.1), and the
platform's receipt minting uses the same catalogue value (§5.8) — the two enforcement
mechanisms agree because both read one catalogue, not because two deployables hardcode the
same constant. The initial value is **7 days**.


| Parameter                             | Value                                                      | Rationale                                                                                                                                                                                                                |
| ------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Renewal checkout issued               | `period_end − grace_days`                                  | A full grace-length window of in-app "Renew" CTA (§10.3) before service is at risk                                                                                                                                       |
| Grace (`past_due`, service continues) | **`grace_days`** after `period_end`                        | Constitution V: no hard-lock; clinics have intermittent connectivity and monthly cash cycles. AI is an add-on, so a bounded continuation is safe — the guard still meters every request against the old period's budgets |
| Suspension                            | At `grace_until`, orchestrator fires `entitlement-suspend` | Fail-closed after grace; reactivation only via paid renewal + purchase proof                                                                                                                                             |
| Payable tail                          | 30 further days (`period_end + grace_days + 30`)           | Late payers reactivate via `renew` without re-purchasing or re-enrolling                                                                                                                                                 |
| Terminal                              | `expired` at tail end                                      | New purchase required; platform side still needs only `renew` (entitlement row persists), so reactivation stays cheap                                                                                                    |
| Refund / chargeback                   | **Immediate** `entitlement-suspend`, no grace              | Money was clawed back; grace would be an abuse window                                                                                                                                                                    |
| Receipt `valid_until`                 | `period_end + grace_days` (same catalogue value)           | Clinic UI self-expires exactly when the platform suspends — the two enforcement mechanisms agree by construction                                                                                                         |


Dunning notification surface is **in-app only** (Flutter learns `past_due` / `grace_until` from
`GET /v1/orders/{id}` and from the status endpoint's `period_end`; §10.3). No email/SMS
infrastructure is introduced; the provider's own payment receipts remain the only external
messages. This is a documented simplification, revisited if support data shows missed renewals.

### 6.4 Renewal semantics

A renewal payment produces a new purchase proof with the **same** `order_id`, a new
`purchase_proof_id`, `kind = renewal`, and period bounds that never discard paid time: while the
entitlement is still `active` (a renewal inside the 7-day lead window), the new period starts
at the current `period_end`, not at `paid_at` — early payers keep their remaining days; when
reactivating from `past_due` / `suspended` / `expired`, the period is
`[paid_at, paid_at + 1 month]`. The
orchestrator calls `renew`, which: verifies the purchase proof, resolves `plan` through the G1
catalogue, updates the entitlement's plan/economics/period/`order_id`/`purchase_proof_id`, sets
`status = active`, and records `order_id` in `control_audit`. The Quota DO resets its period
counters automatically when the period bounds change (verified: `maybeResetPeriod` in
`src/quota-do/index.ts`), so no DO coordination is needed.

**Key rotation vs renewal.** A renewal proof re-carries the order's as-purchased key material
(§4.1.2), so renewal is only valid while that material is still the installation's active
enrolled key. Renewal-checkout re-validates the key material against the platform via an
authenticated read before taking payment (§5.4); if the clinic has rotated keys, the order
must be **re-created** — a fresh order with a freshly signed payload — rather than renewed.

**Plan changes** take effect at renewal only: the clinic requests a renewal checkout for a
different plan (`POST /v1/orders/{id}/renewal-checkout`, §5.4) and pays it; the purchase proof
carries the new plan, which `renew` applies. There is **no proration and no mid-period migration** — orchestration policy lives in the core
module, and "change at next period" is the simplest policy that cannot produce invoice
disputes. Mid-period upgrades are a comp-order + `override` (purchase-proof-gated, §6.5) if support
chooses. When a plan is retired from the sellable catalogue, renewal becomes a forced migration
onto a currently active plan — see §6.6.

Composition with Band G4 is as the proposal states: period close invoices the period that
ended; the paid renewal opens the next. The two systems share only the plan name and the
period bounds carried by the purchase proof. The platform `invoice` row gains a
`purchase_proof_id` (or `order_id`) reference in the A17 amendment pass (§4.2), so the chain
invoice → proof → order is navigable in data, and the invoice is priced from the consumed
proof's `amount_cents` / `currency` — what was actually paid — never from a catalogue
re-lookup (§5.7).

### 6.5 Comp orders

Support goodwill without breaking the traceability rule: an AI Billing Orchestrator ops endpoint
(`POST /v1/ops/comp-orders`, §11.2) creates an order directly in `paid` with `amount = 0`, no
checkout, and enqueues provisioning like any payment, triggering it immediately via
`ctx.waitUntil`. The calling operator is recorded on the
order (`comp_operator_id`, §4.1.2). The purchase proof's `kind = comp` is what
authorizes `override` (economics adjustment) or `renew` (period extension) platform-side. Every
comp order appears in reconciliation like any other order — with expected payout zero.

### 6.6 Plan retirement

When a vendor removes a plan from the sellable catalogue — by setting `plan.status` to anything
other than `active`, or by equivalent operator action — clinics on that plan are handled as
follows. Plans do **not** carry a capability-style deprecate → overlap → retire lifecycle; there
is no grandfathered renewal path at the old tier or price.

**During the current paid period.** Nothing changes. The platform entitlement keeps its existing
`plan` name and economics until `period_end`; the guard continues to admit against those
bounds. Retiring a plan from the catalogue does not suspend or reprice an open period.

**At renewal.** Every checkout — initial, cron-issued, or clinic-initiated — validates the
target plan against the platform's cached `GET /v1/plans` fetch, which serves only
`status = 'active'` rows (§5.10). A retired plan is not sellable:

- `POST /v1/orders` with a retired plan → `404 plan_not_found`.
- `POST /v1/orders/{id}/renewal-checkout` with a retired plan → `404 plan_not_found`.
- Platform `renew` resolves economics from the G1 catalogue; a purchase proof whose `plan`
  claim is absent from the catalogue fails with no writes (same rule as enroll's unknown-plan
  rejection, §8.2).

There is **no** self-service path to renew at a removed tier. The clinic must pick a currently
active plan from `GET /v1/plans`, call `renewal-checkout` with that plan, pay, and let `renew`
apply the new plan and catalogue economics on the **same** `order_id` (§6.4). The `orders.plan`
column is updated when the renewal payment succeeds.

**Order-clock behaviour** (`period_end − grace_days`, §11.1). The cron may attempt to pre-issue a
renewal checkout using `orders.plan` only when that plan is currently sellable (present in the
cached `GET /v1/plans` response). When `orders.plan` is no longer sellable:

1. **Do not** call the provider adapter — no `checkout_url` is written.
2. Leave the order `provisioned` (or `past_due` if already past `period_end`); dunning
   transitions (§6.3) proceed unchanged.
3. Emit a structured log line (`renewal_checkout_skipped_plan_retired`) naming `order_id` and
   the retired plan — ops visibility, not a clinic-facing error.

The clinic's renewal surface therefore shows the "Renew AI" banner but **no** one-tap checkout
until the owner selects an active plan and the app calls `renewal-checkout` (§10.3). This is
deliberate: a removed tier must not silently charge the old price.

**Vendor operations.** Before marking a plan non-`active`, confirm no clinic still depends on a
cron pre-issued checkout for that plan (unlikely in practice — pre-issued URLs expire with
`checkout_expires_at`). There is no subscriber-count gate on plan retirement in this design;
forced migration at renewal is the policy. Goodwill exceptions (e.g. honouring an old price for
one clinic) go through `comp` orders and `override` (§6.5), not catalogue grandfathering.

**Plan renames are discouraged.** The plan name is a shared key in five places — `orders.plan`,
the purchase-proof `plan` claim, `entitlement.plan`, `invoice.plan`, and
`capability_grant.scope = 'plan:{tier}'` — so a rename is not a catalogue edit but a migration
across `capability_grant` rows (and every record that carries the name). Retire the old plan
and create the new one under a new name instead; the forced-migration path above then applies
cleanly.

### 6.7 Order ↔ entitlement coherence matrix

The two state machines (§6.1, §6.2) are synchronized only through the outbox, the platform's
409-mappings (§11.1), and daily billing reconciliation (§11.3) — so the canonical statement of
which order-status × entitlement-status pairs are coherent is a **contract artifact**, not
prose. This subsection is that artifact: both sides' contract tests and the §11.3
reconciliation job consume this mapping, and a pair marked *drift* is exactly what
`reconciliation_alert` reports.


| `orders.status`              | `entitlement.status`      | Verdict    | Why                                                                                  |
| ---------------------------- | ------------------------- | ---------- | ------------------------------------------------------------------------------------ |
| `pending`                    | *(no entitlement row)*    | Coherent   | Pre-payment; the platform does not know the installation yet                         |
| `pending`                    | any                       | Drift      | An entitlement without a paid order is an unbilled grant                             |
| `paid`                       | `pending`                 | Transient  | Provisioning in flight; must resolve within the outbox retry window (§4.1.5)         |
| `paid`                       | `active` / `suspended` / *(none)* | Drift | Money received but the two records disagree on what was granted               |
| `provisioned`                | `active`                  | Coherent   | The happy path                                                                       |
| `provisioned`                | `suspended`               | Drift      | Paid and in-period, yet the guard is closed — investigate before the clinic notices  |
| `past_due`                   | `active`                  | Coherent   | In grace: `grace_until` has not passed, service continues by policy (§6.3)           |
| `past_due`                   | `suspended`               | Coherent   | Grace expired unpaid; the `entitlement_suspend` outbox row has landed                |
| `refunded` / `chargeback`    | `suspended`               | Coherent   | Money clawed back → immediate suspend, no grace (§6.1)                               |
| `expired`                    | `suspended`               | Coherent   | Terminal; reactivation is a new purchase + `renew`                                   |
| `cancelled`                  | *(no entitlement row)*    | Coherent   | Abandoned checkout; nothing was ever granted                                         |

Any pair not listed as coherent or transient is drift. The matrix is deliberately small: if a
real transition cannot be expressed here, the state machines — not the matrix — are wrong.

## 7. Payment provider adapter



### 7.1 The port

The system speaks only canonical domain language past this boundary (proposal §3.1). The
adapter interface (`ai-billing-orchestrator/src/providers/types.ts`):

**Commands** (core → adapter):


| Command                                                                | Returns                     | Notes                                 |
| ---------------------------------------------------------------------- | --------------------------- | ------------------------------------- |
| `create_checkout(order, price) → { checkout_url, expires_at, refs[] }` | Hosted-checkout launch data | `refs` go straight to `provider_refs` |
| `cancel(order) → void`                                                 |                             | Best-effort checkout invalidation     |
| `list_settlements(since) → Settlement[]`                               | Payout/transaction list     | Billing reconciliation input (§11)      |


**Events** (adapter → core), produced only inside the webhook handler after signature
verification:

`payment_succeeded` · `renewal_paid` · `payment_failed` · `refunded` · `chargeback`

First-payment vs renewal distinction is made by the **core** (current order status), not the
adapter: a `payment_succeeded` against a `pending` order is a purchase; against `provisioned`/
`past_due` it is recorded as `renewal_paid`. The adapter reports money movement; the core owns
meaning.

**Quarantine rules (enforced by review, pinned by contract test):**

1. Provider identifiers appear only in `provider_refs` rows — never in `orders` columns,
  purchase proofs, outbox payloads, audit rows, logs, or client responses.
2. Provider event names/enum values never cross the adapter boundary — the webhook handler maps
  to canonical events at the edge.
3. Billing **policy** (grace length, proration, payable tail) is decided in the core module; the
  adapter executes mechanics only.
4. A contract test greps `outbox` and `orders` serializers for adapter-module
  imports and fails on any.



### 7.2 Paymob adapter (first implementation)

Grounded against Paymob's current API (verified 2026-09-11):

- **Checkout:** `POST /v1/intention/` with the merchant **secret key**
(`Authorization: Token …`), `amount` in cents, `currency: "EGP"`,
`payment_methods: [<integration id>]`, `special_reference: <order_id>`,
`notification_url: <BILLING_PUBLIC_ORIGIN>/v1/webhooks/paymob` (§2.4), and a `redirection_url` that is used
for UX only. The response's `client_secret` plus the **public key** compose the Unified
Checkout URL (`/unifiedcheckout/?publicKey=…&clientSecret=…`) — that URL is the
`checkout_url` returned to Flutter. Intention id and Paymob order id are stored in
`provider_refs` (kinds `intention` and `checkout` respectively; settlement/inquiry flows use
`kind = settlement`, §4.1.3).
- **Webhook:** transaction callback POST to `notification_url` with an `hmac` query parameter.
Verification is HMAC-SHA512 over the documented 20-field concatenation of `body.obj`,
lowercased hex, timing-safe compared (§5.5). Event mapping: `obj.success = true` →
`payment_succeeded`; `obj.success = false` → `payment_failed`; `obj.is_refunded = true` →
`refunded`; `obj.is_voided = true` → ignored (a void is not a refund of captured money).
- **Chargeback — honest gap:** Paymob's transaction callback has no reliable distinct
chargeback signal. The canonical `chargeback` event exists in the port, but the Paymob
adapter never emits it; chargebacks surface through `list_settlements` reconciliation
(a payout reversal against a provisioned order → `reconciliation_alert` → ops reviews and
manually triggers the suspend path). This is recorded as a known limitation, not hidden.
- **Settlements:** transaction inquiry against the Paymob API by intention/order refs from
`provider_refs`; mapped to `Settlement[]` for the billing reconciliation job.
- **Secrets:** `PAYMOB_SECRET_KEY`, `PAYMOB_PUBLIC_KEY`, `PAYMOB_HMAC_SECRET` (three distinct
dashboard values), `PAYMOB_INTEGRATION_ID` (var).



### 7.3 What a provider swap touches

Exactly: (1) a new directory under `ai-billing-orchestrator/src/providers/` implementing the port, (2) the
`webhooks/{provider}` route registration, (3) new secrets/vars, (4) a data migration copying or
re-keying `provider_refs` rows for live orders. **Nothing else moves** — not the order machine,
not the purchase proof format, not the orchestrator, not the platform, not the clinic RPCs, not
Flutter (proposal §3.1 anti-lock-in, now contract-pinned by §7.1 rule 4).

## 8. Platform-side changes

These are recorded as **Amendment A16** in `01-ai-platform.md` (§2.10) and sliced in
`04-abo-delivery-plan.md` (bands M–U, superseding Band L); this section is the design summary. Sequenced after Band G completes, per
the proposal — the expected refactor collision point is `src/control/entitle.ts` (proposal §9
finding 1), and G1's plan-catalogue assignment logic is reused as-is.

### 8.1 CAT verification through the existing `OperatorAuth` port

The port (`src/control/types.ts`) is the designed injection point, and it is used. One
mechanical change is required and is a recorded deviation (§14, item 2): `resolve` is
synchronous today, but CAT verification needs `crypto.subtle` and a D1 `jti` insert, so the
port becomes:

```ts
export type OperatorAuth = {
  resolve(request: Request, action: string): Promise<OperatorPrincipal | null>;
};
```

`requireOperator(request, operatorAuth, action)` gains the action argument and an `await` at
each handler — the call sites' shape is otherwise unchanged, and dispatch
(`src/control/index.ts`) is untouched except for the two new routes. Exactly one factory
remains:

- `createCatOperatorAuth({ db, … })` — the only production path (§5.6 verification order).

The legacy `createSecretOperatorAuth` bearer factory and its break-glass action set are
**deleted, not demoted**: every `/control/v1/*` caller — orchestrator or human — authenticates
with a personal CAT key registered in `control_operator`, and there is no composite wiring in
`worker.ts`. A shared, non-attributed bearer is the exact anti-pattern §11.2 refuses for the
ABO's own ops surface; the platform does not keep it either. The one genuine residual the
bearer covered — auth-system failure (a corrupted `control_operator` table, or all operator
keys lost) — is answered at the D1 level: an operator with Cloudflare account IAM inserts a
new `control_operator` row via `wrangler d1`, the same bootstrap mechanism the ABO uses for
`ops_operator` (§4.1.8). No standing credential exists to leak.

Human operators sign CATs with a small local CLI delivered in Band L
(`ai-platform/scripts/cat-sign`, alongside the L8 key-generation recipe); the private key never
leaves the operator's machine, and the viewer may grow the same capability later.

`control_audit.operator_id` becomes the CAT `iss` — real per-caller attribution (proposal §4.7),
with `order_id` added on grant actions (§4.2).

### 8.2 Purchase-proof-gated grants

- `enroll` — body shrinks to `{ purchase_proof, org_id, display_name, region }`;
`kid`/`public_key`/`plan` come from the purchase proof claims (§5.7), and the orchestrator
reads `org_id` / `display_name` / `region` from the order's stored `order_payload` bytes at
orchestration time — they are not `orders` columns (§4.1.2). Dedup is tightened to
`installation_id` **only** (§13 item 2): the `org_id` OR-clause in `handleEnroll`'s
existence check is removed; `org_id` remains stored metadata. Plan validation changes from
the hardcoded `isKnownPlanTier` list to a `plan`-catalogue lookup (`status = 'active'`),
which is what G1 made possible.
- `entitle` — requires `{ purchase_proof }` with `kind ∈ {purchase, comp}`; economics still
resolve from the catalogue exactly as G1 wrote it; the batch gains the `purchase_proof` insert
and the entitlement `order_id`/`purchase_proof_id` writes.
- `renew` (new) — `POST /control/v1/installations/{id}/renew`, body `{ purchase_proof }`.
Mechanical extension of `CONTROL_ACTION_PATTERN` + dispatch switch + handler, per the
proposal. Requires entitlement `active` or `suspended` (404 `entitlement_not_found`,
409 `not_renewable` from `pending` — renew is never the first grant). Writes: entitlement
UPDATE (plan, all economics from the catalogue, period from the purchase proof,
`status = 'active'`, `order_id`, `purchase_proof_id`), `purchase_proof` INSERT, audit INSERT with
`order_id`. Response `{ installation_id, status: "active", period_end }`.
- `entitlement-suspend` (new) — `POST /control/v1/installations/{id}/entitlement-suspend`,
body-less. `active → suspended`, else `409 illegal_lifecycle_transition`. CAT-only (no
purchase proof — it grants nothing). Orchestrator scope; human operators use installation
`suspend`/`resume` with their own scoped CAT keys (§6.2).
- `override` — now requires `{ purchase_proof }` with `kind = comp` in addition to its existing
payload (§6.5). Its economics-merging logic is unchanged.



### 8.3 New read surfaces

`GET /v1/installation/status` and `GET /v1/platform-keys` (§5.9). The status endpoint is the
platform's first production **signing** path: the receipt key arrives as the
`PLATFORM_RECEIPT_PRIVATE_KEY` secret, imported as PKCS#8 Ed25519, used only here.

### 8.4 Untouched

Guard pipeline, Quota DO admission contract, Band G economics (G1–G4), `/v1/*` data path,
journal, R2 layout — proposal §4.8, confirmed against the code: nothing in the request path
reads `order_id`, purchase proofs, or receipts.

## 9. Clinic-side changes

All in one forward-only backend migration family, reusing the B1 patterns
(`20260801120000_ai_keystore_schema.sql`, `20260801120200_ai_token_issuer_rpc.sql`):
SECURITY DEFINER functions in `auth_internal`, thin `public` wrappers, `GRANT EXECUTE … TO authenticated`, deny-all RLS untouched.

### 9.1 Order-signing RPC — `public.create_ai_order(p_plan text)`

Owner/admin-gated (`auth_internal.assert_owner_or_administrator()` first, exactly as the
keystore RPCs). Selects the active installation key (same ordering as the issuer:
`valid_from DESC, kid DESC`, `revoked_at IS NULL`), builds the §5.2 payload with
`jsonb_build_object`, signs with `pgsodium.crypto_sign_detached` over the exact payload text
(the `issue_ai_token` pattern), and returns
`{ order_payload, signature, installation_id, kid, public_key }`. Errors: `FORBIDDEN`,
`INSTALLATION_NOT_ENROLLED`, `INVALID_INPUT` (blank plan). The RPC **records nothing** — order
state lives in the AI Billing Orchestrator; the clinic database stays ignorant of money, preserving the A15
boundary in the other direction.

### 9.2 `set_ai_availability` — replaced, not supplemented

The existing `public.set_ai_availability(boolean, text)` and its `auth_internal` twin
(`20260905120100_set_ai_availability_rpc.sql`) are **dropped** in the same migration that
creates the receipt-verifying variant — leaving both would keep a permanent bypass of the
activation ceremony (proposal §5.2, finding 3).

New signature: `public.set_ai_availability(p_receipt text)`.

- `p_receipt NULL` → deactivate: writes `{ enrolled: false, platform_base_url: null, valid_until: null }`. Always allowed for owner/admin — turning AI off needs no proof.
- Non-null → full §5.8 verification against `ai.platform_receipt_keys`; on success writes
`{ enrolled: true, platform_base_url, valid_until }` from the receipt claims.
- Errors: `FORBIDDEN`, `INVALID_RECEIPT` (any verification failure — one code, no oracle),
`RECEIPT_EXPIRED`.

`public.get_ai_availability()` keeps its signature and plain-`jsonb` shape, gains a
`valid_until` field, and becomes **self-expiring**: when `valid_until` is in the past it
returns `enrolled: false` (the stored row is left untouched; the next successful activation
overwrites it). Flutter's rule is unchanged — it reads this flag and never probes the platform
to discover enrollment.

### 9.3 Platform receipt key seed — `public.add_platform_receipt_key(p_kid text, p_public_key text)`

Owner/admin-gated. Validates `p_public_key` is base64url of exactly 32 bytes, then upserts the
`{ kid, public_key, added_at, revoked_at: null }` entry into the `ai.platform_receipt_keys`
app-settings array. `public.revoke_platform_receipt_key(p_kid text)` stamps `revoked_at` and
refuses the last unrevoked key (`CANNOT_REVOKE_LAST_PLATFORM_KEY`), mirroring the installation
keystore rule. Initial seed: Flutter fetches `GET /v1/platform-keys` during first activation
and calls the add RPC (§3.5); a clinic that has never activated has no keys and
`set_ai_availability(receipt)` fails closed with `INVALID_RECEIPT`.

### 9.4 Key wrapping

The `secret_key` wrapping migration of §3.6 ships in the same band. No RPC contract changes.

### 9.5 What is deliberately not stored in the clinic

No vendor credentials, no orchestrator identity, no order state, no provider anything. The
clinic's only new possessions are public keys and its own signed order payloads. There is no
credential honeypot to defend (proposal §5.3).

## 10. Flutter flows

Rules carried from the proposal and pinned here: no provider SDK, no card data in the app
process, provider swap = zero Flutter change, Flutter never calls `/control/v1/*` and never holds
control-plane credentials. The E1 architecture lint is extended with the AI Billing Orchestrator origin so
provider hostnames cannot leak into client code.

### 10.1 Purchase

1. Owner/admin opens the AI purchase surface (visible when `get_ai_availability().enrolled`
   is false — the existing hide-without-probing rule).
2. App ensures a Stage-2 keypair exists (`enroll_installation_keypair()` — already built).
3. App fetches `GET /v1/plans` (§5.10) from the **platform** origin and renders the plan picker
   from the response — plan names, prices, and display copy come from the platform's catalogue,
   never from the app binary. Fetch failure renders as a normal empty/retry state (the E4 rule),
   never an error dialog.
4. App calls `create_ai_order(plan)` → `{ order_payload, signature }`.
5. App `POST /v1/orders` to the **AI Billing Orchestrator** origin (a new, vendor-published constant alongside the
   platform origin) → `{ order_id, checkout_url, poll_token }`. The pair
   `(order_id, poll_token)` is persisted in the app's local secure storage so a restart resumes
   polling; it is not written to clinic Postgres.
6. `url_launcher` opens `checkout_url` in the **system browser** (hosted checkout).
7. App polls `GET /v1/orders/{order_id}` (Bearer poll token, 5 s interval with backoff, visible
   "waiting for payment" state, cancelable). Terminal `paid`/`provisioned` → activation (§10.2);
   `cancelled`/poll timeout → abandon and clear local state.



### 10.2 Activation (pull model)

1. On `paid`/`provisioned` (and on every app start while `enrolled` is false but a completed
  order exists in local storage): mint a staff AAT (`issue_ai_token` — identity passes once
   enrolled, even while `pending`).
2. First activation only: `GET /v1/platform-keys` → `add_platform_receipt_key` per key.
3. Poll `GET /v1/installation/status` (AAT) until `entitlement_status = active` and a `receipt`
  is present.
4. `set_ai_availability(receipt)` → AI chrome enabled for all staff on next flag read.
5. If receipt verification fails with an unknown `kid`: re-fetch `/v1/platform-keys`, seed, and
  retry once (rotation self-heal, §3.5).

**Receipt refresh while enrolled:** on every app start, and whenever `valid_until` is within
3 days, an already-enrolled installation also polls `GET /v1/installation/status` and re-runs
steps 3–4. This extends `valid_until` after a renewal paid from any device; without it the flag
would self-expire at the old instant and AI chrome would go dark until the first start after
expiry.

### 10.3 Renewal and dunning UX

- From `period_end − grace_days` (§6.3), the status endpoint's `period_end` drives a "Renew AI" banner.
When `orders.plan` is still sellable, the cron may have pre-issued a `checkout_url`; tapping
"Renew" can poll `GET /v1/orders/{id}` and open that URL directly. When the current plan has
been retired (§6.6), `checkout_url` is null until the owner picks a replacement — the banner
always offers plan selection from a cached `GET /v1/plans` (§5.10), calls
`POST /v1/orders/{id}/renewal-checkout` (§5.4) with the chosen plan, then opens the returned
checkout URL. Payment → webhook → `renew` → next status poll returns a fresh receipt →
`set_ai_availability(receipt)` extends `valid_until`. The banner disappears.
- In `past_due`, the banner becomes a warning naming `grace_until`. Service continues.
- After suspension, AI chrome hides on the next flag read (`valid_until` has passed — no
network needed), and the purchase surface shows "suspended — pay to reactivate" driven by the
order poll. Payment reactivates end-to-end with no vendor contact.



### 10.4 Self-healing and failure modes


| Situation                          | Behaviour                                                                                                                                                                                                                                                                                                                                                                                |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App reinstall / lost local storage | Owner re-runs purchase surface → `POST /v1/orders` returns `409 order_exists` with the live `order_id`… but no poll token. Recovery path: the surface instead offers "already purchased — reactivate", which skips the AI Billing Orchestrator checkout path and goes straight to §10.2 steps 2–4 (status + receipt need only an AAT). The poll token is a UX convenience, not a capability |
| Platform unreachable               | Existing E4 rule: renders as a normal state, never an error dialog; flag unchanged                                                                                                                                                                                                                                                                                                       |
| Receipt expired mid-session        | Flag self-expires at `valid_until`; AI chrome hides; no clinical workflow is blocked (constitution V)                                                                                                                                                                                                                                                                                    |
| Clinic clock skew                  | Receipt `exp` is 15 min and verified against clinic time; the activation poll retries, so transient skew self-resolves. `valid_until` is day-granular in practice (period + `grace_days`) and tolerant of hours of skew                                                                                                                                                                        |
| Current plan retired at renewal    | Cron leaves `checkout_url` null (§6.6); renewal banner requires plan selection from `GET /v1/plans` and an explicit `renewal-checkout` call before payment — no silent charge at the old tier                                                                                                                                                                                            |




## 11. Scheduled work and billing reconciliation



### 11.1 Cron Triggers (AI Billing Orchestrator)

Three triggers, matching the ai-platform scheduled-handler pattern (`worker.ts` `scheduled`,
dispatched by cron expression). Outbox rows are processed immediately by their producer
(`ctx.waitUntil` or inline `await` on the order clock); the `* * * * *` job is a sweeper, not
the primary driver:


| Schedule     | Job              | Work                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------ | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `* * * * *`  | Outbox sweeper   | Drain due `outbox` rows still `pending` (`next_attempt_at ≤ now`): retries with exponential backoff (cap 10, `failed` logs an alert) and recovery of rows whose immediate `ctx.waitUntil` attempt was dropped or failed. Same shared processor and idempotent-replay mapping as the producer trigger: `409 already_enrolled`, `409 not_pending`, and `409 purchase_proof_replayed` mark the row `done`, not `failed` — they mean a prior attempt committed and its response was lost; the processor confirms with a `quota-inspect` read before closing the row. Happy path is event-driven (seconds, via the producer's `waitUntil` trigger); the sweeper bounds recovery of failed or dropped attempts to ~1 minute |
| `10 * * * *` | Order clock      | Issue renewal checkouts (`period_end − grace_days`, read from the cached catalogue fetch, §4.1.6) **only when** `orders.plan` is sellable (§6.6) and the order's key material still matches the platform (§5.4); otherwise skip checkout and log `renewal_checkout_skipped_plan_retired` / `renewal_checkout_skipped_key_rotated`. Flip `past_due` at `period_end`, fire `entitlement_suspend` outbox rows at `grace_until`, flip `expired` at the tail, cancel expired checkouts                                                                                                                                                                                                                                                                                                                                                         |
| `0 5 * * *`  | Billing reconciliation | §11.3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |


The platform Worker's existing crons gain one job: purge `control_cat_jti` rows where
`expires_at < now` (rides the daily retention cron, `0 3 * * *`).

### 11.2 Ops endpoints (AI Billing Orchestrator)

`POST /v1/ops/comp-orders` (§6.5) is the only ops HTTP endpoint, and it is authenticated by
**per-operator Ed25519 keys from day one** — the same pattern as the platform's
`control_operator`, applied to the AI Billing Orchestrator's own surface (`ops_operator` /
`ops_jti`, §4.1.8). Tokens are CAT-structured (§5.6 claims) with `aud =
"ai-billing-orchestrator-ops"`, verified against `ops_operator` via the shared
`packages/ed25519-jws/` package, with `jti` replay-guarded in the same batch as the comp-order
write (co-location rule, §5.1). The verified `operator_id` is recorded on the order
(`comp_operator_id`) and every comp order is caught by the payout direction of billing
reconciliation (§11.3: an entitlement whose order never payouts). Key bootstrap, rotation, and
revocation are `wrangler d1` statements under Cloudflare account IAM (per-person, audited by
Cloudflare). Operators who also perform platform incident response are provisioned into both
registries (`ops_operator` here, `control_operator` on the platform) by one atomic provisioning
script/runbook (§4.1.8).

There is deliberately **no shared ops bearer** (no `BILLING_OPS_TOKEN`-style secret): a shared
bearer here would be *operationally grant-capable* — a comp order auto-provisions through the
Worker's own keys, so a leaked bearer could mint free service end-to-end with no attribution.
That is the same anti-pattern the platform removed `OPERATOR_BEARER_TOKEN` for (§8.1); the AI
Billing Orchestrator does not introduce it.

There is also **no `GET /v1/ops/reconciliation-alerts` HTTP endpoint**: billing reconciliation
alerts are read and acknowledged directly against D1 (`wrangler d1` / Cloudflare dashboard),
which is per-person IAM-authenticated and audited by Cloudflare — no app-level credential to
leak, and no read-path endpoint to maintain.

### 11.3 Billing reconciliation job

Named *billing* reconciliation to distinguish it from the platform's usage-side
`runRollupAndReconciliation` cron — a different job with a colliding name. This is the
after-the-fact control for collusion and insider tampering (proposal §3.3, §8):

1. **Payment → entitlement:** every ABO order in `paid`/`provisioned`/`past_due` has a
  platform entitlement whose `order_id` matches and whose status is coherent per the §6.7
   coherence matrix (queried per
   installation through `quota-inspect` with the orchestrator CAT — a read the orchestrator is
   already scoped for). Drift → `reconciliation_alert (payment_without_entitlement)`.
2. **Entitlement → payment:** the reverse direction needs a platform-side list the control
  plane does not currently expose. Rather than add a list endpoint, the platform's
   `control_audit` is the source: the job pages `support-lookup`-style audit reads (orchestrator
   scope) for `entitle`/`renew`/`override` actions and confirms each carries an `order_id` that
   exists and is coherent per the §6.7 matrix in the AI Billing Orchestrator. Drift → `entitlement_without_payment`. If audit paging
   proves insufficient at volume, a dedicated `GET /control/v1/entitlements` audit read is the
   named extension point — deferred until needed, per the constitution's simplicity rule.
3. **Provider payouts:** `list_settlements` vs `webhook_events`/`orders` — every payout traces
  to an order; every provisioned order traces to a payout (modulo the provider's settlement
   lag, which the job tolerates by only examining periods closed ≥ 3 days). Drift →
   `payout_mismatch`.

Every run and every alert is a structured log line; alerts persist in
`reconciliation_alert` until acknowledged directly against D1 (`wrangler d1` / Cloudflare
dashboard — there is deliberately no alerts HTTP endpoint, §11.2).

## 12. Security traceability

Every attack row in proposal §8, traced to the concrete mechanism in this design:


| Attack (proposal §8)                          | Mechanism here                                                                                                                                                                                                                                    |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Self-enroll keypair from the app              | Enroll now requires a Purchase Proof (§8.2) in addition to CAT; without payment there is no purchase proof. Guard still fails closed: `401 unauthenticated` without enroll, `403 ai_disabled` without entitle                                     |
| Forge payment webhook                         | HMAC-SHA512 verification with timing-safe compare + `webhook_events` idempotency as the authoritative replay guard (§5.5)                                                                                                                         |
| Call `/control/v1/*` directly                    | CAT requires a `control_operator` private key — server-side only, never shipped (§5.6); there is no bearer fallback — the shared bearer is removed entirely (§8.1)                                                                              |
| Orchestrator fully compromised                | Holds no purchase proof signing key → cannot grant (§2.1 key separation). Worst case: `entitlement-suspend` DoS — revocable via `control_operator.revoked_at` (§3.4), audited (`control_audit` with real `operator_id`), rate-limited at the edge |
| Billing fully compromised                     | Holds no CAT key → cannot write to the platform (§2.1). Forged purchase proofs need the purchase proof signing key, which lives in a different secret store from the CAT key                                                                      |
| Replay one payment for many clinics           | `entitlement.order_id` UNIQUE + `purchase_proof` table single-use + order bound to one installation by PoP (§4.2, §5.2, §5.7)                                                                                                                     |
| Redirect a paid order to another installation | Purchase proof binds `installation_id` + key material minted at order creation; enroll validates body against claims (§5.7)                                                                                                                       |
| Rogue human operator                          | Personal CAT keys with scoped `allowed_actions` — a suspend-scoped human key can stop abuse but can never grant; every action attributed in `control_audit` (§8.1). Operator key loss is recovered at the D1 level: a new `control_operator` row inserted via `wrangler d1` under Cloudflare account IAM (§13 item 3). The AI Billing Orchestrator's ops surface uses the same pattern from day one — per-operator keys (`ops_operator`), comp orders attributed via `comp_operator_id`, no shared ops bearer (§11.2) |
| Flip `ai.availability` in clinic DB           | Receipt-verified RPC is the only write path (old boolean RPC dropped, §9.2); even a flipped flag yields no AI access — the guard re-checks entitlement per request                                                                                |
| Insider tampers with platform D1              | Billing reconciliation (§11.3) + `control_audit.order_id` on every grant + platform `purchase_proof` consumption-log cross-check (§4.2)                                                                                                               |


**Residual risks (honest):** purchase-module + orchestrator-module key collusion (mitigated: separate secrets,
billing reconciliation, and the keys never co-locate in one module's code path); platform D1 insider
tampering (billing reconciliation + audit review; periodic signed audit export remains a named future
hardening, not built); orchestrator suspend-DoS (revocation + rate limits); clinic `postgres`
access can still call the signing RPCs' internals (§3.6 boundary). The Paymob chargeback
detection gap (§7.2) is a detection-latency risk, not a bypass: the money-side reversal is
caught by billing reconciliation and the suspend is then manual.

## 13. Proposal open items — resolutions

All seven items from proposal §12, decided:

1. **Dunning/grace policy** — §6.3: renewal lead and grace both equal to the catalogue's
  `grace_days` (initially 7 days) with service continuing through grace,
  entitlement-suspend at grace end, 30-day payable tail, immediate suspend on
   refund/chargeback, in-app dunning surface only.
2. **Enroll dedup** — tightened to `installation_id` only (§8.2). The `org_id` OR-clause is
  removed: `org_id` is unique only within one clinic deployment (Stage 3 documents the
   cross-deployment collision risk), and with PoP-bound orders the installation id is the trust
   anchor. Disaster-recovery re-enrollment of the same clinic under a new installation id is
   thereby unblocked, which the old clause prevented.
3. **Break-glass bearer** — RESOLVED: **removed entirely** (§8.1). All `/control/v1/*` callers,
  orchestrator and human, authenticate with personal CAT keys registered in `control_operator`;
   humans with suspend-scoped keys can stop abuse but can never grant, so the "humans can stop
   abuse but never grant" property holds without any shared credential. The residual concern —
   the orchestrator as single point of failure for incident response — was never real: human
   CAT keys cover every incident action, and the orchestrator is not on the human incident
   path. The one genuine residual, auth-system failure (corrupted `control_operator` table or
   all keys lost), is answered at the D1 level: an operator with Cloudflare account IAM inserts
   a new `control_operator` row via `wrangler d1` — the same bootstrap mechanism the ABO uses
   for `ops_operator` (§4.1.8).
4. **Separate Cloudflare account** — not now. Single vendor operator; separate Worker, D1, and
  secrets already prevent cross-service credential access within the account. Revisit when a
   second engineer gains production access; the design has no account-local coupling, so the
   move is a redeploy, not a redesign.
5. **Trust-root rotation** — designed in §3.3–§3.5: key-set verification with validity windows
  (purchase proof), table-backed rotation (CAT), clinic-side key set with self-healing refetch
   (receipt); operationalized by the single rotation script/runbook and the ABO boot-time
   self-check (§3.7).
6. **Clinic private-key wrapping** — designed in §3.6 (pgsodium AEAD with a named managed key),
  scheduled in Band L (slice L6), honest about the live-`postgres` residual.
7. **CAT** `jti` **replay store** — D1 table `control_cat_jti` (§4.2), insert-if-absent, cron purge.
  Control-plane volume is human-plus-cron (orders of magnitude below D1 write limits), D1
   writes are strongly consistent within the region, and a Durable Object would add the
   platform's second stateful component for a table that sees a few writes per hour. If volume
   ever argues otherwise, the migration is a port swap behind the same verifier interface.



## 14. Deviations from the proposal

1. `period_end` **is not guard-enforced.** Proposal §7.3 says "entitlement `period_end` bounds
  the abuse window." Code-verified false: neither the entitlement stage nor the Quota DO reads
   `period_end` for admission. The binding mechanisms are receipt `valid_until` (clinic UI) and
   orchestrator `entitlement-suspend` (guard) — §6.2. The alternative (guard rejects on period
   expiry) was considered and rejected: it would hard-stop service at midnight on period end
   with no grace, violating the dunning policy and constitution V.
2. `OperatorAuth.resolve` **becomes async and gains the action argument** (§8.1). The proposal
  said per-handler `requireOperator` calls are unchanged; they in fact gain `await` and the
   action string. Everything else about the injection point is as the proposal verified.
3. **Dunning suspension is entitlement-level, not installation-level** (§6.2). The proposal's
  "orchestrator calls `suspend`" would have made paid reactivation require a bare `resume` —
   a grant without purchase proof. The new `entitlement-suspend` action keeps every service-
   restoring path purchase-proof-gated.
4. `override` **requires a comp purchase proof** (§6.5) — stricter than the proposal's silence,
  per the confirmed product decision; "every entitlement traces to an order" has no exception.
5. **Renewals are payer-initiated** (confirmed product decision); the adapter has no
  card-on-file or merchant-initiated charge surface.
6. `GET /v1/orders/{id}` **auth** — the proposal did not specify one; the poll-token design (§5.4)
  is new.
7. `GET /v1/platform-keys` is new — the proposal named the clinic key-storage problem
  (finding 5) but not a distribution mechanism.
8. **Chargeback detection via reconciliation** for Paymob (§7.2) — the canonical event exists;
  the first adapter cannot emit it from webhooks.
9. **Enroll plan validation moves from the hardcoded tier list to the plan catalogue** (§8.2) —
  a consequence of G1 existing in code; the closed four-tier list would otherwise drift from
   the catalogue.
10. **Receipt carries** `valid_until` **and the clinic flag self-expires** (§5.8, §9.2) — the
    proposal implied expiry ("receipts expire with the period") without a mechanism; this is
    the mechanism, set to `period_end + grace_days` from the plan catalogue so the two
    enforcement paths agree by construction (§6.3).
11. **The plan and pricing catalogue lives only on the platform** (platform amendment A17;
    §4.1.6, §5.10) — the proposal's Flutter flows assume plan selection without defining where
    the plan list or prices come from, and the first draft of this document answered with an
    ABO-side `plan_price` table, a second catalogue that could drift from the platform's. There
    is now one catalogue (platform `plan`, with price and display copy), one public read
    (`GET /v1/plans`), and no plan table in the AI Billing Orchestrator; the purchase module validates and
    prices orders against a cached server-side fetch. The purchase proof carries the paid
    `amount_cents` / `currency` (§5.7) so invoices and reconciliation never re-lookup a price.
12. **Shared `packages/ed25519-jws/` package** (§2.2) — the proposal's "same primitives on both
    sides" implied per-service copies; with two Workers in one repository that would be three
    near-identical JWS verifiers (AAT, CAT, PoP/purchase-proof) plus a copied timing-safe
    compare. One workspace package is the rule; the clinic side is exempt (pgsodium is a
    different runtime).
13. **Error style families are named** (§5.1) — flat `{"error": "<snake_code>"}` for the
    control-plane family (platform `/control/v1/*` and all ABO endpoints), the taxonomy envelope
    reserved for the clinic-facing `/v1/*` data path. The proposal was silent; the first draft
    of this document invented a third style by accident.
14. **No shared ops bearer on the AI Billing Orchestrator** (§4.1.8, §11.2) — the proposal's
    "operator keys — done now, not later" principle is applied to the orchestrator's own ops
    surface: `POST /v1/ops/comp-orders` takes per-operator Ed25519 keys (`ops_operator` +
    CAT-structured tokens via the shared package) with `comp_operator_id` attribution, and a
    grant-capable shared bearer is never introduced. The read path
    (`GET /v1/ops/reconciliation-alerts`) is eliminated entirely — alerts are read/acknowledged
    via `wrangler d1` / Cloudflare dashboard under per-person account IAM.



## 15. Constitution compliance check

- **I. Product fit and simplicity** — one new vendor Worker; no queues (outbox table + Cron
Triggers); no microservice sprawl; payer-initiated renewal avoids stored-credential
machinery. The constitution amendment registering this deployable is in
`.specify/memory/constitution.md` (Operating Constraints) and lands before Band L code.
- **II. Replaceable layer boundaries** — Flutter orchestrates and transports; clinic Postgres
owns clinic-side integrity (RPCs, RLS); the provider adapter is a port with a contract test
pinning the seam (§7.1). No custom backend is added to the *clinic's* primary architecture.
- **III. Backend authority** — clinic-side writes (availability flag, key material) remain
RPC-enforced under deny-all RLS; the platform's grant path is constraint-enforced (UNIQUE
indexes, batch-atomic purchase proof consumption).
- **IV. Secure, human-gated operations** — every grant is two-signature gated and audited with
real operator identity and order id; human incident response runs on personal scoped CAT keys,
with D1-level recovery under Cloudflare account IAM (§8.1, §13 item 3).
- **V. Operational continuity** — nothing hard-locks: grace period before any suspension, AI
is an add-on whose loss never blocks clinical workflows, the clinic flag fails closed but the
app remains fully usable, and reactivation is self-service.

