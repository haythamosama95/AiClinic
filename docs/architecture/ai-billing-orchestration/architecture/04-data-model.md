# AI Billing Orchestration — Data Model

**Status:** Architecture — decided

**Date:** 2026-09-11

**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.

**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.

**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [4. Data model](#4-data-model)
  - [4.1 Billing D1 schema](#41-billing-d1-schema)
    - [4.1.1 Overview](#411-overview)
    - [4.1.2 orders](#412-orders)
    - [4.1.3 provider_refs](#413-provider_refs)
    - [4.1.4 webhook_events](#414-webhook_events)
    - [4.1.5 outbox](#415-outbox)
    - [4.1.6 No local plan table — the platform catalogue is the single source](#416-no-local-plan-table-the-platform-catalogue-is-the-single-source)
    - [4.1.7 reconciliation_alert](#417-reconciliation_alert)
    - [4.1.8 ops_operator and ops_jti](#418-ops_operator-and-ops_jti)
  - [4.2 Platform D1 additions](#42-platform-d1-additions)
    - [`control_operator`](#control_operator)
    - [`control_cat_jti`](#control_cat_jti)
    - [`purchase_proof`](#purchase_proof)
    - [`entitlement` (column additions)](#entitlement-column-additions)
    - [`control_audit` (column addition)](#control_audit-column-addition)
    - [`plan` and `invoice` (column additions, A17)](#plan-and-invoice-column-additions-a17)

---

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
| Module bridge | `outbox` | Handoff ledger from the **purchase** module to the **orchestrator** module (same Worker): the row carries the minted proof JWS and tracks delivery state, while a Cloudflare Queue message (`outbox_id`) schedules and retries the work (§4.1.5) |
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
│  ┌─ purchase module  ┐    ┌─ orchestrator module ──┐  │
│  │ orders,           │    │ queue consumer: reads  │  │
│  │ provider_refs     │───►│ outbox row, calls      │  │
│  │ webhook_events    │Q+  │ ai-platform /control/v1│  │
│  │ ops_operator      │out │                        │  │
│  └───────────────────┘box └────────────────────────┘  │
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
                           ▼  │             ┌──────────────────────┐
                          outbox            │ reconciliation_alert |
                       (FK order_id;        │ (detail JSON cites   |
                        handoff to          │  order_id; no FK)    |
                        orchestrator;       └──────────────────────┘
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

 4  producer ──queue message──► orchestrator module ──► ai-platform /control/v1/*
                                      outbox (done), orders (provisioned_at)
                                      (Cloudflare Queue retries failures; DLQ + recon alert)

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
| [4] Payment provider → purchase module · HTTP `POST /v1/webhooks/{provider}` | Authoritatively record payment outcome (success, failure, refund); transition order state; mint purchase proof; enqueue platform provisioning by writing the outbox row and sending a queue message carrying its `outbox_id`. | **R** `provider_refs` — map provider id → `order_id`<br>**R** `webhook_events` — idempotency on `(provider, provider_event_id)`<br>**W** `webhook_events` — log authenticated event + payload hash<br>**W** `orders` — status transition, period bounds, `paid_at`, latest `purchase_proof_id` on success<br>**W** `outbox` — enqueue `provision` (or refund-driven) job with the freshly minted proof JWS embedded in `payload` |
| [5] orchestrator module → ai-platform · queue consumer + HTTPS `/control/v1/*` | Invoked by the Cloudflare Queue consumer with the `outbox_id`; load the row, drive platform `enroll` → `entitle` (or `renew` / `entitlement-suspend`) using CAT + purchase proof. A thrown error retries the message with queue-managed backoff; exhausted retries dead-letter and mark the row `failed`. | **R** `outbox` — the row named by the message (`payload` carries the exact JWS to present, on first attempt and every retry)<br>**R** `orders` — order context for the control call<br>**W** `outbox` — `done` / `attempts` / `failed`<br>**W** `orders` — `provisioned_at` when provision completes |
| [6] Order clock cron → purchase module · cron (§11.1) | Time-driven dunning: renewal checkout windows, `past_due` flips, suspend enqueue, terminal expiry. | **R** `orders` — rows crossing `period_end`, `grace_until`, expiry thresholds<br>**W** `orders` — status, `grace_until`, renewal checkout fields<br>**W** `outbox` — `entitlement_suspend` rows when grace expires unpaid, each followed by a queue message |
| [7] Billing reconciliation cron → ops · cron (§11.3) | Detect billing ↔ platform ↔ payout drift; persist findings for operator review. | **R** `orders` — `paid` / `provisioned` / `past_due` cohort<br>**R** `webhook_events` — payout cross-check<br>**R** platform (via `quota-inspect` / audit reads — not billing D1)<br>**W** `reconciliation_alert` — drift kind + JSON `detail` (order id, installation id, amounts) |
| [—] Vendor ops → purchase module · HTTP `POST /v1/ops/comp-orders` | Issue complimentary access (trial/goodwill) without payment — same grant path as a paid order (§6.5). | **R** `ops_operator` — per-operator key verification (§4.1.8)<br>**R** platform `plan` catalogue — cached fetch: plan exists<br>**W** `orders` — comp order through `paid` state (`comp_operator_id` attribution)<br>**W** `ops_jti` — token replay guard, same batch<br>**W** `outbox` — enqueue `provision` with the minted proof JWS in `payload`, then send the queue message |

Step [4]→[5] is the critical internal handoff: the **purchase** module mints the purchase proof,
writes the `outbox` row with the JWS embedded in `payload`, and sends a Cloudflare Queue message
carrying the `outbox_id`; the **orchestrator** module (same Worker) runs as the queue consumer.
No HTTP between the two modules — the row is the payload ledger and the queue is the scheduler:
delivery is at-least-once with queue-managed exponential backoff, and a message that exhausts its
retries lands in a dead-letter queue. The consumer loads the row by id, marks it `processing`,
and on success marks it `done`; platform-side idempotency (409 mappings, §11.1) is the backstop
for duplicate deliveries.

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

**What it is.** The billing case file for one clinic installation's AI subscription: one long-lived
row tracks checkout, payment, the current period, dunning, and whether platform provisioning has
completed. Everything else in billing D1 hangs off `order_id`.

**Responsibilities.** Hold payment-side state (§6.1); snapshot clinic identity and signing key
material at purchase time; expose a provider-agnostic status surface for Flutter polling (§5.4);
enforce at most one live order per installation.

**Who touches it.**

| Actor | Read | Write |
| ----- | ---- | ----- |
| Flutter (poll token) | `GET /v1/orders/{id}` — status, period, checkout fields | — |
| Purchase module | Live-order guard, renewal eligibility, webhook transitions | Create on `POST /v1/orders`; update on webhooks, renewal checkout, order-clock cron, comp orders |
| Orchestrator module | Order context for control calls | `provisioned_at` when grant succeeds |
| Reconciliation cron (§11.3) | Paid / provisioned / past_due cohorts | — |

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

**What it is.** A side index that maps payment-provider ids (checkout intention, transaction,
settlement, …) to an `order_id`, so provider-specific strings never appear on `orders`, purchase
proofs, or audit rows.

**Responsibilities.** Isolate adapter identifiers (§7.2); let webhooks resolve “which order is
this payment about?” via `UNIQUE (provider, kind, provider_ref)` lookup.

**Who touches it.**

| Actor | Read | Write |
| ----- | ---- | ----- |
| Purchase module | — | Insert when opening initial or renewal hosted checkout |
| Webhook handler | Resolve `provider_ref` → `order_id` before updating `orders` | — |

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

**What it is.** An append-only log of payment-provider callbacks the Worker has accepted after
signature verification — one row per provider event id, even when processing fails later.

**Responsibilities.** Idempotency on webhook redelivery (`UNIQUE (provider, provider_event_id)` →
conflict means “already seen”, respond `200` without re-running side effects, §5.5); tamper-evidence
via `payload_hash`; support payout cross-checks in reconciliation (§11.3).

**Who touches it.**

| Actor | Read | Write |
| ----- | ---- | ----- |
| Webhook handler | Idempotency check before work | Insert at start of handling; update `status` / `processed_at` |
| Reconciliation cron | Compare payouts vs recorded events | — |

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

**What it is.** The durable handoff ledger between the **purchase** module (which mints the
proof) and the **orchestrator** module (which calls `/control/v1/*`): one row per “grant or
suspend entitlement on ai-platform using this purchase proof.” Scheduling and retries are
delegated to a **Cloudflare Queue** — the producer sends a message carrying the `outbox_id`
after its D1 batch commits, and the orchestrator runs as the queue consumer.

**Responsibilities.** Carry the exact purchase-proof JWS in `payload` on every attempt; record
delivery state (`pending` → `processing` → `done` / `failed`) so reconciliation and ops can audit
what happened; act as the billing-side minting ledger (rows are never purged). Retry timing,
backoff, and dead-lettering are the queue's job, not the row's. Platform replay protection lives
separately in §4.2 `purchase_proof`.

**Who touches it.**

| Actor | Read | Write |
| ----- | ---- | ----- |
| Purchase module | — | Enqueue `provision` after payment or comp; enqueue `entitlement_suspend` from order clock; send the queue message |
| Orchestrator module (queue consumer) | Load the row named by the message | `processing` → `done` / `failed`; drives platform calls |
| Reconciliation / ops | Audit what was minted and presented | — |

The handoff from purchase module to orchestrator (proposal §3): each producer that inserts a row
sends a queue message (`{ outbox_id }`) after its D1 batch commits — the payment webhook handler,
the comp-order ops endpoint, and the order-clock cron (for `entitlement_suspend` rows) all use
the same `OUTBOX_QUEUE` binding. The queue delivers to the consumer in seconds and retries a
thrown handler with managed exponential backoff; a message that exhausts `max_retries` lands in
the `outbox-dlq` dead-letter queue. The consumer loads the row by id, flips it `pending →
processing`, mirrors `message.attempts` into `attempts`, and on the final attempt (per the
queue's `max_retries`) marks the row `failed` with `last_error` and emits an alert log before
letting the message dead-letter. Delivery is at-least-once, so the consumer is idempotent:
platform-side 409 mappings (`already_enrolled`, `not_pending`, `purchase_proof_replayed`,
§11.1) confirm with a `quota-inspect` read and close the row `done`, and the platform
`purchase_proof` replay guard (§4.2) makes a duplicate grant impossible. The daily
reconciliation job (§11.3) is the liveness floor: a `paid` order whose outbox row is not `done`
past the retry window raises a `payment_without_entitlement` alert, and DLQ contents are
redriven by ops (`wrangler queues` or the consumer's redrive path) after the underlying fault is
fixed.


| Column                        | Type                     | Meaning                                                     |
| ----------------------------- | ------------------------ | ----------------------------------------------------------- |
| `outbox_id`                   | TEXT PK                  | UUID                                                        |
| `kind`                        | TEXT NOT NULL            | `provision` \| `entitlement_suspend`                         |
| `order_id`                    | TEXT NOT NULL → `orders` |                                                             |
| `payload`                     | TEXT NOT NULL            | JSON: purchase proof JWS plus the control-call parameters (enroll metadata is parsed from the order's stored `order_payload`, §4.1.2) |
| `status`                      | TEXT NOT NULL            | `pending` → `processing` → `done` or `failed`             |
| `attempts`                    | INTEGER NOT NULL         | Mirrored from the queue message's delivery attempts        |
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

**What it is (by design).** There is **no** `plan` table in billing D1. Sellable plans, prices,
display copy, and `grace_days` live only in ai-platform's `plan` catalogue (A17), fetched over
`GET /v1/plans` (§5.10).

**Responsibilities.** One catalogue for “what can be sold and for how much” so billing and platform
enforcement cannot disagree; bind the *paid* amount in the purchase proof (§5.7), not a stale
local price row.

**Who touches it.**

| Actor | Read | Write |
| ----- | ---- | ----- |
| Purchase module | Cached `GET /v1/plans` at order create, renewal checkout, comp validation | — |
| ai-platform | Serves catalogue; validates plan at enroll/entitle/renew | Platform migrations / ops (not ABO D1) |
| Flutter | `GET /v1/plans` for UI (not billing D1) | — |

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
purchase proof's `amount_cents` / `currency` claims (§5.7), so period-close invoices and reconciliation
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

**What it is.** An ops-facing inbox row when automated checks find billing state, platform
entitlement, or provider payout data out of alignment — not a workflow engine, just a persisted
finding plus optional acknowledgement.

**Responsibilities.** Record drift kind and JSON `detail` (order id, installation id, amounts) from
the daily reconciliation job (§11.3); give operators something to triage without mutating orders or
entitlements automatically.

**Who touches it.**

| Actor | Read | Write |
| ----- | ---- | ----- |
| Reconciliation cron | — | Insert new alerts when rules fire |
| Vendor ops | Review `/v1/ops/*` or D1 directly | Set `acknowledged_at` when reviewed |

Drift findings from the daily job (§11):


| Column            | Type          | Meaning                                           |
| ----------------- | ------------- | ------------------------------------------------- |
| `alert_id`        | TEXT PK       | UUID                                              |
| `kind`            | TEXT NOT NULL | `payment_without_entitlement` \| `entitlement_without_payment` \| `payout_mismatch` (§11.3) |
| `detail`          | TEXT NOT NULL | JSON context (order id, installation id, amounts) |
| `created_at`      | TEXT NOT NULL |                                                   |
| `acknowledged_at` | TEXT          | Operator review marker                            |

#### 4.1.8 ops_operator and ops_jti

**What they are.** The billing Worker's operator registry (`ops_operator`) plus a short-lived
replay store (`ops_jti`) for signed ops tokens — same idea as platform `control_operator` /
`control_cat_jti` (§4.2), but scoped to `/v1/ops/*` (e.g. comp orders). No shared ops bearer
(§11.2).

**Responsibilities.**

| Table | Job |
| ----- | --- |
| `ops_operator` | Map `kid` → public key, allowed actions, and `operator_id` for attribution on comp orders |
| `ops_jti` | Reject reused ops token `jti` within TTL; purged by order-clock cron |

**Who touches them.**

| Actor | Read | Write |
| ----- | ---- | ----- |
| Comp-order handler (`POST /v1/ops/comp-orders`) | Verify token against `ops_operator`; check `ops_jti` | Insert `ops_jti` in same batch as order/outbox writes |
| Bootstrap / rotation | — | `wrangler d1` under Cloudflare IAM (§3.7, §11.2) — not self-service HTTP |

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

These tables extend **ai-platform** D1 (not billing D1). They exist so grants are cryptographically
gated, attributable, and replay-safe at the enforcement boundary.

#### `control_operator`

**What it is.** Who may call `/control/v1/*` and which actions each key may perform — replaces a
single shared control bearer with per-caller Ed25519 keys and scopes.

**Readers / writers.** ai-platform control handlers **read** on every CAT-authenticated request;
vendor bootstrap **writes** via `wrangler d1` (rotation §3.4). The billing orchestrator module
uses a dedicated `operator_id` (e.g. `orchestrator`) row here.

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

#### `control_cat_jti`

**What it is.** “Have we already accepted this Control Action Token?” — one row per consumed CAT
`jti` until expiry.

**Readers / writers.** Control plane **reads** before grant mutations; **writes** `jti` in the
same D1 batch as the authorized action. Purged by the platform scheduled handler.

`control_cat_jti` — CAT replay store (§13 item 7 for the D1-vs-DO decision):

```sql
CREATE TABLE control_cat_jti (
  jti         TEXT PRIMARY KEY NOT NULL,
  operator_id TEXT NOT NULL,
  expires_at  TEXT NOT NULL                    -- CAT exp + skew; purged by the existing scheduled handler
);
```

#### `purchase_proof`

**What it is.** The platform's record that a specific purchase-proof JWS was consumed to authorize
a grant — the enforcement-side replay guard (§5.7). Billing D1 keeps mint history in `outbox`;
this table answers “has ai-platform already honored this `jti`?”

**Readers / writers.** Entitle / renew / enroll handlers **read** (conflict = replay); **insert**
in the **same batch** as the entitlement mutation so a replay rolls back the whole grant.

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

#### `entitlement` (column additions)

**What changes.** Links the live entitlement row to the billing order and the latest proof that
(re)granted it — so guards and support can trace "this installation's access" → "this payment".

**Readers / writers.** Quota / status paths **read**; grant and renew handlers **write**
`order_id` and `purchase_proof_id` with the entitlement state transition. Flutter and clinic
Supabase read derived status via ai-platform HTTP, not D1 directly.

`entitlement` **gains two columns** (proposal §4.4):

```sql
ALTER TABLE entitlement ADD COLUMN order_id TEXT;
ALTER TABLE entitlement ADD COLUMN purchase_proof_id TEXT;  -- latest purchase proof that (re)granted
CREATE UNIQUE INDEX idx_entitlement_order_id ON entitlement (order_id) WHERE order_id IS NOT NULL;
```

`order_id` UNIQUE makes one payment unable to entitle two installations; the partial index keeps
legacy rows (null `order_id`) untouched. `purchase_proof_id` on the row is informational (latest);
replay protection lives in the `purchase_proof` table, which retains **every** consumed id.

#### `control_audit` (column addition)

**What changes.** Optional `order_id` on audit rows so every grant action is traceable to a
billing order in forensics (proposal §4.7).

**Readers / writers.** Control handlers **write** audit on each action; ops / tooling **read**.
Non-grant actions and legacy rows keep `order_id` null.

`control_audit` **gains** `order_id TEXT` (nullable) — every grant traces to a payment
(proposal §4.7); null only for non-grant actions and pre-migration rows.

#### `plan` and `invoice` (column additions, A17)

**What changes.** `plan.grace_days` is the single timing source for dunning and receipt validity;
`invoice.purchase_proof_id` (or `order_id`) links commercial invoices to the proof that fixed the
paid price.

**Readers / writers.** `GET /v1/plans` and grant paths **read** `grace_days`; catalogue ops
**write** via platform migrations. Period-close invoicing **reads** consumed proof amounts;
**writes** invoice rows with the proof link.

Two further platform-side column additions land with the A17 catalogue amendment pass (they
are recorded here because this design depends on them):

- `plan` **gains** `grace_days INTEGER NOT NULL DEFAULT 7` — served by `GET /v1/plans`
  (§5.10) and the single source for dunning timing on both sides (§4.1.6, §6.3, §11.1).
- `invoice` **gains** `purchase_proof_id TEXT` (nullable; alternatively `order_id`) — so the
  chain invoice → proof → order is navigable in data, and period-close invoicing prices the invoice
  from the consumed proof's `amount_cents` / `currency`, never from a catalogue re-lookup
  (§5.7, §6.4).

