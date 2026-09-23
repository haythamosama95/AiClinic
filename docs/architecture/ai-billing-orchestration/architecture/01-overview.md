# AI Billing Orchestration — Architecture (Overview)

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.
**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [Overview](#overview)
  - [Layers and deployables](#layers-and-deployables)
  - [AI Billing Orchestrator modules](#ai-billing-orchestrator-modules)
  - [Three-key trust chain](#three-key-trust-chain)
  - [Happy-path purchase flow](#happy-path-purchase-flow)
  - [How the rest of this document is organized](#how-the-rest-of-this-document-is-organized)

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
│  │ Flutter desktop app  │─────▶│ Clinic Supabase (PostgreSQL)             │ │
│  │ purchase + activate  │ RPC  │ receipt-verified ai.availability flag    │ │
│  └──────────┬───────────┘      └──────────────────────────────────────────┘ │
│             │ AAT + receipt pull                                            │
└─────────────┼───────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  PLATFORM LAYER — ai-platform Worker (existing, refactored)                         │
│  /v1/*  guard + invoke + status/receipt minting                                     │
│  /control/v1/*  enroll, entitle, renew, suspend — CAT auth, purchase-proof-gated    │
└─────────────▲───────────────────────────────────────────────────────────────────────┘
              │ CAT + purchase proof
              │
┌─────────────┴───────────────────────────────────────────────────────────────┐
│  BILLING LAYER — AI Billing Orchestrator Worker (new)                       │
│  purchase module ◄──webhook── Payment provider (Paymob first)               │
│  orchestrator module ──▶ platform /control/v1/*                             │
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
   ├─ outbox consumer      Cloudflare Queue consumer; rows in D1 are the ledger
   └─ platform client      enroll → entitle / renew / entitlement-suspend
```

The purchase module cannot sign a CAT; the orchestrator cannot sign a purchase proof. A full
compromise of either module alone cannot grant service.

**Handoff.** Payment or comp order → purchase updates order + mints purchase proof → writes an
`outbox` row → sends a Cloudflare Queue message (`outbox_id`) → the orchestrator, as queue
consumer, loads the row (queue-managed retries, DLQ on exhaustion) → signs CAT per call → hits
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
        └──── verified by ai-platform ─────────────────┘
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
     │─────────────────────────▶│ POST /v1/orders         │                     │
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
     │ 3. poll GET /v1/orders   │                         │                     │
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


| Section | What you will find there |
| ------- | ------------------------ |
| §1–§2   | [Context and deployables](02-context-and-deployables.md) |
| §3      | [Trust model and keys](03-trust-and-keys.md) |
| §4      | [Data model](04-data-model.md) |
| §5      | [Wire contracts](05-wire-contracts.md) |
| §6      | [Lifecycle and dunning policy](06-lifecycle-and-policy.md) |
| §7, §11 | [Billing Worker ops (adapter + cron)](07-billing-worker-ops.md) |
| §8      | [Platform-side changes](08-platform-changes.md) |
| §9      | [Clinic-side changes](09-clinic-changes.md) |
| §10     | [Flutter flows](10-flutter-flows.md) |
| §12–§15 | [Governance and compliance](11-governance.md) |

Full § index: [master TOC](00-index.md).




