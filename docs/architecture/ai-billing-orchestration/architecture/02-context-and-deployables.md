# AI Billing Orchestration — Context and Deployables

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.
**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [1. Context and decisions already made](#1-context-and-decisions-already-made)
- [2. System context and deployables](#2-system-context-and-deployables)
  - [2.1 One new deployable](#21-one-new-deployable)
  - [2.2 Repository layout](#22-repository-layout)
  - [2.3 What the AI Billing Orchestrator never does](#23-what-the-ai-billing-orchestrator-never-does)
  - [2.4 Configuration and secrets inventory](#24-configuration-and-secrets-inventory)

---

## 1. Context and decisions already made

This document turns the agreed proposal ([`../01-proposal.md`](../01-proposal.md)) into a buildable architecture. The
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
[§14](11-governance.md#14-deviations-from-the-proposal).

## 2. System context and deployables



### 2.1 One new deployable

One new Cloudflare Worker, vendor-operated, in the same Cloudflare account as `ai-platform`
(separate account deferred — [§13](11-governance.md#13-proposal-open-items-resolutions) item 4). Same stack,
same workflow, same conventions: forward-only D1 migrations, three environments
(development/staging/production), secrets via `wrangler secret`, Cron Triggers for scheduled
work, and a Cloudflare Queue (`outbox-events` + `outbox-dlq` dead-letter) for purchase→
orchestrator handoff delivery (§4.1.5, §11.1). **Separate Worker, separate D1, separate secrets** — CI credentials and secret access for
one service cannot read the other's keys.

```
AI Billing Orchestrator (`ai-billing-orchestrator`)
├─ purchase module        (secrets: BILLING_PURCHASE_PROOF_PRIVATE_KEY, PAYMOB_*)
│   ├─ provider adapter   — thin, swappable (Paymob first, §7)
│   ├─ order state machine — provider-agnostic (§6.1)
│   └─ webhook endpoint   — provider signature verification, idempotent event table (§5.5)
└─ orchestrator module    (secret: ORCHESTRATOR_CAT_PRIVATE_KEY)
    ├─ consumes paid/refund events as a Cloudflare Queue consumer (outbox rows are the ledger)
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
│  ├─ worker.ts            — fetch + scheduled + queue entry points
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



