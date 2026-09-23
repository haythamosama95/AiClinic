# AI Billing Orchestration — Billing Worker Ops

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.
**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [7. Payment provider adapter](#7-payment-provider-adapter)
  - [7.1 The port](#71-the-port)
  - [7.2 Paymob adapter (first implementation)](#72-paymob-adapter-first-implementation)
  - [7.3 What a provider swap touches](#73-what-a-provider-swap-touches)
- [11. Scheduled work and billing reconciliation](#11-scheduled-work-and-billing-reconciliation)
  - [11.1 Scheduled work and the outbox queue (AI Billing Orchestrator)](#111-scheduled-work-and-the-outbox-queue-ai-billing-orchestrator)
  - [11.2 Ops endpoints (AI Billing Orchestrator)](#112-ops-endpoints-ai-billing-orchestrator)
  - [11.3 Billing reconciliation job](#113-billing-reconciliation-job)

---

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


## 11. Scheduled work and billing reconciliation



### 11.1 Scheduled work and the outbox queue (AI Billing Orchestrator)

Two cron triggers, matching the ai-platform scheduled-handler pattern (`worker.ts` `scheduled`,
dispatched by cron expression). Outbox work is **not** cron-driven: producers send a Cloudflare
Queue message (`{ outbox_id }`) after committing the outbox row, and the orchestrator module runs
as the queue consumer — no polling, no idle ticks, retries managed by the queue.

**Queue configuration.** One queue `outbox-events` with the ABO Worker as both producer
(`OUTBOX_QUEUE` binding) and consumer. Consumer settings: `max_retries = 10` with exponential
`retry_delay` (queue-managed backoff), and a dead-letter queue `outbox-dlq`. The consumer loads
the row named by the message, flips it `pending → processing`, mirrors `message.attempts` into
`attempts`, and drives the platform call. On the final attempt it marks the row `failed` with
`last_error` and emits an alert log before the message dead-letters. Idempotent-replay mapping:
`409 already_enrolled`, `409 not_pending`, and `409 purchase_proof_replayed` mark the row `done`,
not `failed` — they mean a prior attempt committed and its response was lost; the consumer
confirms with a `quota-inspect` read before closing the row. DLQ contents are redriven by ops
after the underlying fault is fixed; the daily reconciliation (§11.3) alerts on any `paid` order
whose outbox row is not `done` past the retry window.

| Schedule     | Job              | Work                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------ | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `10 * * * *` | Order clock      | Issue renewal checkouts (`period_end − grace_days`, read from the cached catalogue fetch, §4.1.6) **only when** `orders.plan` is sellable (§6.6) and the order's key material still matches the platform (§5.4); otherwise skip checkout and log `renewal_checkout_skipped_plan_retired` / `renewal_checkout_skipped_key_rotated`. Flip `past_due` at `period_end`, fire `entitlement_suspend` outbox rows at `grace_until` (each followed by a queue message), flip `expired` at the tail, cancel expired checkouts                                                                                                                                                                                                                                                                                                                                                         |
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

