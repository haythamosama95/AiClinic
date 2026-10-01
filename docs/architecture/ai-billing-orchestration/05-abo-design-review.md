# AI Billing Orchestration — Design Review

**Status:** Review — findings and recommended redesign, for decision before implementation
**Date:** 2026-09-30
**Scope:** The ABO architecture set (`architecture/00-index.md` … `11-governance.md`), the proposal
(`01-proposal.md`), the delivery plan (`04-abo-delivery-plan.md`), and the implemented `ai-platform/`
code it must drive.
**Ground rules:** Only critical and major findings are recorded. The project constitution was
deliberately **not** considered; every judgment is on engineering merit (correctness, security,
simplicity, operating cost, legal need). Nothing in the ABO is implemented, so every recommendation
assumes a free hand to redesign both the ABO and the platform's control surface.
**Related:** [`03-ap-abo-deduplication-analysis.md`](03-ap-abo-deduplication-analysis.md) — this review
disagrees with several of its verdicts (§9).

## Table of Contents

1. [Verdict](#1-verdict)
2. [Method](#2-method)
3. [Critical findings](#3-critical-findings)
4. [Major findings — ABO design](#4-major-findings--abo-design)
5. [Major findings — AI Platform rework](#5-major-findings--ai-platform-rework)
6. [Recommended target design](#6-recommended-target-design)
7. [What the redesign removes and adds](#7-what-the-redesign-removes-and-adds)
8. [Recommended sequencing](#8-recommended-sequencing)
9. [Disagreements with the prior deduplication analysis](#9-disagreements-with-the-prior-deduplication-analysis)
10. [Decisions needed from the product owner](#10-decisions-needed-from-the-product-owner)
11. [Non-findings and refuted concerns](#11-non-findings-and-refuted-concerns)

---

## 1. Verdict

The design is **overengineered in trust ceremony and underengineered in the payment domain.**

- **Where it is overengineered.** The design has three signing keys, a per-call Control Action Token
  (CAT) for machine-to-machine calls, two operator registries, a provisioning receipt chain with
  clinic-side key distribution, a cross-deploy rotation script with a 72-hour overlap, a boot-time
  self-check, an eight-state order machine plus a coherence matrix, and a Cloudflare Queue plus
  dead-letter queue. Most of this protects properties that do not actually hold. The headline claim,
  "two independent signatures", is false because both keys live in the same Worker (M1). The receipt
  protects a UI flag the clinic owner can already forge (M3).
- **Where it is underengineered.** There is no per-payment record. Refund callbacks can be read as
  successful payments. The amount and plan paid are never checked against what was sold. Duplicate
  and declined payments are undefined. Buying again after a lapse takes the money and grants nothing.
  There is no tax invoicing. Several failure paths leave a paid clinic unprovisioned with no automatic
  recovery, and nobody is alerted.
- **Where the platform needs rework.** Access never expires at the platform; enforcement depends on the
  ABO staying healthy. The quota period is the payment period, so every renewal resets the clinic's
  quota and shifts the usage ledger's month key. The control API is multi-step, not idempotent, and
  signals success with 409s.

The fixes simplify rather than grow the system. Payments become immutable rows, and what they buy
becomes dated **coverage** rows that the platform guard enforces on its own. The ABO holds one
signing key and calls the platform over a private service binding. The receipt chain, the order
state machine, the queue, the poll token and the ABO operator registry are all deleted (§7).

**Finding count:** 8 critical, 21 major.

| ID | Finding | Severity | Category |
|----|---------|----------|----------|
| C1 | Paymob refund/void callbacks misclassified — a refund can grant a free month | Critical | Incorrect |
| C2 | No per-payment record; plan and amount not bound to the checkout that was paid | Critical | Incorrect / Gap |
| C3 | Duplicate payments, declined attempts and pending callbacks undefined or wrong | Critical | Gap |
| C4 | "Money received always provisions" is false — five stall paths, no automatic recovery | Critical | Incorrect |
| C5 | Re-purchase, reinstall, deleted installation and key rotation dead-end; 409→done takes money silently | Critical | Incorrect |
| C6 | Access never expires at the platform; non-payment enforcement is fail-open | Critical | Weak point |
| C7 | Quota period coupled to the paid period — renewals reset quota, ledger and period close disagree | Critical | Incorrect |
| C8 | Egyptian tax invoicing (ETA e-invoice, VAT, credit notes) absent | Critical | Gap (legal) |
| M1 | "Two independent signatures" is not real; the ABO is one trust principal | Major | Incorrect / Overengineered |
| M2 | Per-call CAT on a public HTTP control plane for machine calls | Major | Overengineered |
| M3 | The provisioning receipt chain protects nothing | Major | Overengineered |
| M4 | Poll token is a single-desktop credential; multi-branch clinics cannot renew | Major | Gap |
| M5 | Unauthenticated order creation allows free squatting; enrolled installations not bound to their current key | Major | Gap |
| M6 | The order-as-subscription state machine is overbuilt, and comp orders contradict it | Major | Overengineered / Incorrect |
| M7 | Refund and chargeback policy is too blunt and has no recording path | Major | Incorrect |
| M8 | Price, interval and grace live in the wrong system; no term plans | Major | Gap / Overengineered |
| M9 | Order clock re-fires suspends, double-issues checkouts, breaks on retired plans | Major | Incorrect |
| M10 | No customer billing identity or contact channel (Paymob checkout creation will fail) | Major | Gap |
| M11 | Alerts are log lines and D1 rows that nobody receives | Major | Gap |
| M12 | Payment system of record has no history, raw evidence, export or durable backup | Major | Gap |
| M13 | Ops surface unworkable for one operator; duplicate operator registries | Major | Overengineered / Gap |
| M14 | Nothing sells until 9 bands land; bearer removal breaks existing tooling | Major | Overengineered |
| M15 | Time-driven flows cannot be tested end to end as planned | Major | Gap |
| M16 | Design and delivery plan contain wrong "code-verified" claims and self-contradictions | Major | Incorrect |
| P1 | Platform control API is multi-step, non-idempotent, and 409-as-success | Major | Weak point |
| P2 | Plan identity model broken (static tiers, side-effect plan grants, delete is a no-op) | Major | Incorrect |
| P3 | Plan features sold but not enforced (`max_cost_class`, token/cost budgets) | Major | Incorrect |
| P4 | Installation keys hard-expire at 365 days with operator-only rotation | Major | Gap |
| P5 | Platform invoice / `credit_price` / period close conflict with ABO billing | Major | Overengineered / Incorrect |

(P-prefixed findings are AI Platform rework items, §5. P6 and P7 there are smaller items folded into
the target contract.)

## 2. Method

- **Code discovery.** Two explorer passes mapped `ai-platform/`: the control plane, identity and config
  cache, plus metering, the Quota Durable Object (DO), pricing and period close. Load-bearing claims
  were re-checked by hand, for example `lifecycle.ts:30` (365-day key TTL), `worker.ts:984`
  (hard-coded `"premium"` cost class) and `platform-vocabulary.ts:2` (static plan tiers).
- **Analysis.** Four independent analyses covered the trust model, the payment domain (including
  Paymob API behaviour and Egyptian tax rules via web research), reliability and operations, and the
  platform contract. Each began from reviewer hypotheses it was asked to verify or refute. Refuted
  hypotheses are in §11. Where the analyses conflicted, the resolution is stated in §6.
- **Confidence.** Code facts are high confidence. Paymob callback shapes and Egyptian Tax Authority
  (ETA) rules are **medium to high** confidence from public documentation. Both must be confirmed in the
  Paymob sandbox and with a local accountant before implementation (§10).

---

## 3. Critical findings

### 3.1 C1 — Paymob refund and void callbacks are misclassified

**Evidence.**
- `architecture/07-billing-worker-ops.md` §7.2 maps `obj.success = true` to `payment_succeeded`,
  `obj.is_refunded = true` to `refunded`, and ignores `obj.is_voided`.
- §7.1 treats any `payment_succeeded` on a `provisioned`/`past_due` order as `renewal_paid`.
- `05-wire-contracts.md` §5.5 dedupes on `(provider, provider_event_id)` and resolves the order by
  `obj.order.id`.
- Paymob refunds create a **new child transaction** (new `id`, `success: true`, `is_refund: true`,
  `has_parent_transaction: true`, same `order.id`). A void cancels a captured payment before
  settlement, so the merchant never receives the funds.

**Impact.**
- A goodwill partial refund arrives as a new successful transaction on the same order and passes
  the id-based idempotency check. It becomes `renewal_paid`, then a renewal proof, then `renew`: the
  clinic gets a **free month because it was refunded**.
- A void (the natural way to reverse a mistaken charge) leaves service granted with no money
  received.
- If Paymob also re-notifies the parent with `is_refunded = true`, that callback has the same `obj.id`
  and is dropped as a duplicate.

**Fix.**
- **Classify on the full signed flag tuple, never on `success` alone.**
  - `has_parent_transaction` means a refund or void child. Confirm it through the Transaction
    Inquiry API and read `parent_transaction` and the amount from the authoritative record.
  - `pending` means no-op.
  - `is_voided` means a reversal.
  - Only `success ∧ ¬pending ∧ ¬is_voided ∧ ¬is_refunded ∧ ¬has_parent_transaction ∧ amount/currency
    match` is a payment.
- **Change the idempotency key** to `(provider, obj.id, hash(signed state flags))`.
- **Store the raw verified callback body.**
- **Before building:** record full refund, partial refund and void callbacks in the Paymob sandbox.

### 3.2 C2 — No per-payment record; plan and amount are not bound to what was paid

**Evidence.**
- `04-data-model.md` §4.1.2: `orders` is one long-lived row, with a single `plan`, period and
  `checkout_url`, and **no amount or currency column**.
- §4.1.3: `provider_refs` carries no plan, amount or expiry.
- `05` §5.4: `renewal-checkout` *replaces* `checkout_url` for a new plan. The chosen renewal plan is
  never persisted.
- `06` §6.6: "`orders.plan` is updated when the renewal payment succeeds".
- The paid amount lives only inside a JWS in `outbox.payload`, with an unspecified source.
- Paymob intentions cannot be cancelled once created (only updated before payment), so the port's
  `cancel(order)` has nothing to call. Old intentions stay payable until they expire.

**Impact.**
- **Wrong plan granted.** An owner holding a cron-issued Standard checkout picks Pro in the app, then
  pays the stale Standard tab. The webhook applies whatever `orders.plan` says, so the clinic gets
  Pro at the Standard price.
- **Price changes go unchecked.** A price change between checkout and payment is never compared
  against anything.
- **No trail.** A refund cannot be tied to a period. Support cannot answer "what did we pay for in
  March". Reconciliation has no expected amount.

**Fix.**
- **Add a `payment` row per checkout attempt** that snapshots the offer at creation: plan, interval,
  gross, VAT, currency, `expires_at` and key material.
- **Set `special_reference = payment_id`.** Create the intention when the owner clicks, with a
  30–60 minute expiry.
- **On callback,** require the signed `amount_cents`/`currency` to equal the payment row. On mismatch,
  record `amount_mismatch`, grant nothing and alert.
- **Coverage follows the payment row,** never the subscription's "current plan".
- **Removes:** order checkout fields, cron pre-issued checkouts, adapter `cancel`, and
  "replace checkout" semantics.

### 3.3 C3 — Duplicate payments, declined attempts and pending callbacks are undefined

**Evidence.**
- `06` §6.1 has no transition for `payment_succeeded` on `paid`/`cancelled`/`expired`, and none for
  `payment_failed` on `provisioned`/`past_due`.
- A single `payment_failed` moves `pending → cancelled`.
- `obj.success = false` includes intermediate `pending = true` callbacks (wallets, 3DS).
- A cron-issued URL plus an app-issued URL, or two browser tabs, give two payable intentions.

**Impact.**
- **Undefined outcome for duplicates.** Paying twice takes the money twice with no defined outcome:
  either an unintended stacked month or an unhandled transition.
- **One decline kills the order.** A single declined card on first purchase cancels the order. A retry
  that then succeeds lands on a `cancelled` order.
- **Pending is misread.** A pending wallet callback is treated as a failure.

**Fix** (falls out of the §6.2 model, with no state machine):
- Failures and pendings are logged against their `payment` row. The attempt stays `open` until it
  expires.
- Every verified success creates a coverage segment stacked from `max(covered_until, paid_at)`. Value
  is never lost.
- Two successes within 48 h raise `possible_duplicate`, and the owner is offered a refund, which
  revokes that segment.

### 3.4 C4 — "Money received always provisions" is false

**Evidence and stall paths.**
1. **Webhook not atomic.**
   - `05` §5.5 inserts `webhook_events` and then transitions the order and enqueues the outbox row,
     but nowhere requires one D1 batch.
   - `04` §4.1.4 keeps the event row "even when processing fails later".
   - If anything throws after the event insert, there is no outbox row. Paymob's redelivery is
     answered `200 duplicate`, and the payment is lost.
2. **Send after commit.** The queue message is sent after the D1 commit (`04` §4.1.5). If the isolate
   dies in between, the row stays `pending` forever.
3. **Stuck `processing`.** The consumer flips the row to `processing` and is evicted mid-call. The
   redelivery sees `processing` and skips it (delivery plan R1-V1).
4. **Dead-lettered.** An outage longer than the retry budget dead-letters the message. The DLQ keeps
   messages for 4 days by default, and redrive tooling is undefined.
5. **Expired proof.** The purchase proof is minted once with `exp = iat + 72 h` and replayed
   byte-identically (`05` §5.7, delivery plan R1-V8). Any blockage longer than 72 hours (a weekend
   outage, a bad `kid` deploy, the boot self-check refusing to run, a day-3 redrive) makes every retry
   fail permanently, and there is no re-mint path.

In every case the only detector is a **daily** reconciliation row that nobody is notified about (M11).
The payout direction of that reconciliation also skips the last 3 days.

**Fix.**
- **One D1 batch per webhook:** the `webhook_events` insert, a compare-and-set on the subscription or
  payment, the `payment` update, and an outbox row with `dedupe_key`. A batch failure returns `500`
  so Paymob retries.
- **Delete the Cloudflare Queue and DLQ.**
  - Use a D1-leased outbox (`pending`/`processing` with `lease_until`, `next_attempt_at`, `blocked`),
    a best-effort `ctx.waitUntil` attempt after commit, and a `* * * * *` sweeper.
  - Transient errors retry forever with capped backoff (a paid order has no terminal failure).
    Permanent errors go to `blocked` and alert.
- **Mint the proof per attempt** with a stable `jti` (the coverage-segment id) and `exp ≈ 10 min`.
  Store claims, not JWS bytes. The platform treats an already-applied `jti` with an identical claims
  hash as success regardless of `exp`.
- **Add a Paymob Inquiry fallback** in the sweeper for open payments older than about 10 minutes. It
  catches lost webhooks and HMAC drift within minutes.

### 3.5 C5 — Re-purchase, reinstall, deletion and key rotation dead-end; 409 means "done"

**Evidence.**
- `07` §11.1 maps `409 already_enrolled`, `409 not_pending` and `409 purchase_proof_replayed` to
  `done`.
- `ai-platform/src/control/entitle.ts:209-211` returns `409 not_pending` for any non-pending
  entitlement.
- `ai-platform/src/control/lifecycle.ts:232-240` dedupes enroll on
  `installation_id = ? OR org_id = ?`, which also matches *deleted* installations and *other*
  installations of the same org.
- `04` §4.1.2 says a terminal order may purchase again because "the platform-side reactivation path is
  `renew`", but the provision job only runs `enroll → entitle`.
- Delivery plan R-E9 expects that repurchase to succeed. The platform code cannot do that.
- **Key rotation deadlock.** `05` §5.4 returns `409 key_rotated` and says to "start a fresh order",
  while `05` §5.3 returns `409 order_exists` for as long as the old order is live. The way out is to
  wait `period_end + grace + 30 d`, and even then `enroll` says `already_enrolled`.

**Impact.**
- **Lapsed clinic pays for nothing.** It pays again, gets 409 on enroll and 409 on entitle, both
  marked `done`, and the order is marked `provisioned` while service stays off.
- **Reinstall pays for nothing.** A reinstalled clinic (new `installation_id`, same `org_id`) pays and
  gets `already_enrolled`, which is marked `done`.
- **Rotation locks out renewal.** A clinic that rotates keys cannot renew for 37+ days.

**Fix.**
- **One permanent `subscription` per installation** that can always accept a payment. There is no
  "re-purchase" concept.
- **One idempotent platform operation, `applyCoverage(proof)`** (§6.3), with **typed permanent
  errors** (`installation_deleted`, `plan_retired`, `org_has_live_installation`, …) routed to refund
  or alert, never to `done`.
- **Remove the `org_id` OR-clause.** If "one live installation per org" is a real rule, enforce it with
  `UNIQUE(org_id) WHERE status <> 'deleted'` and a typed error.
- **Remove key material from renewal proofs.** It appears only in a first-enrollment block.

### 3.6 C6 — Access never expires at the platform; non-payment enforcement is fail-open

**Evidence.**
- `ai-platform/src/entitlement/index.ts:181-184`: the guard checks only `status === "active"` and
  never reads `period_end`.
- `quota-do/index.ts:263-282` resets counters on a bound change but never rejects on expiry.
- The design accepts this and makes ABO-driven `entitlement-suspend` the only closing mechanism
  (`06` §6.2, `11` §14 deviation 1).
- A guard-side check was rejected only because it would "hard-stop at midnight with no grace". That
  objection disappears if the platform stores the grace instant itself.

**Impact.**
- **Unpaid clinics keep service.** If the ABO's cron, sweeper, D1 or platform call is down on the
  grace date, every unpaid clinic keeps full AI access with no upper bound, and the vendor pays the
  provider costs.
- **Clients that ignore the flag keep working.** The clinic UI flag self-expires, but any client that
  ignores it keeps working.

**Fix.** Store paid coverage as dated rows on the platform (`starts_at`, `ends_at`, `grace_until`) and
have the guard deny once `now ≥ grace_until` (§6.3).
- **Delete** non-payment `entitlement_suspend` entirely. Refunds and chargebacks use `voidCoverage`.
- **Side benefit:** a date compared against `now` expires on time even from a 30-second-stale config
  cache, whereas a status flip only takes effect when the cache refreshes.

### 3.7 C7 — The quota period is the paid period

**Evidence.**
- `quota-do/index.ts:263-282` (`maybeResetPeriod`) zeroes counters whenever **either** period bound
  differs from the stored bounds.
- `06` §6.4 applies an early renewal as `[old_end, old_end + 1 month)` immediately.
- `worker.ts:290-292, 619`: the ledger key is `periodFromIso(period_start)`, which is `YYYY-MM`.
- `period-close/index.ts:43-94`: closes the previous **calendar** month, covers `status = 'active'`
  rows only, skips zero usage, and uses `ON CONFLICT DO NOTHING`.
- `entitle.ts:391-396, 515`: `override` can move period bounds.

**Impact.**

| Scenario | What happens today / under the design |
|----------|----------------------------------------|
| Renew 5 days early | Quota resets immediately, giving a free second budget; the last 5 days of usage are tagged to next month |
| Anniversary period (e.g. starting the 15th) | Ledger key `2026-09` covers Sep 15 – Oct 15; the Oct 1 close bills two weeks, and `DO NOTHING` drops the rest permanently |
| Grace usage | Tagged to a month whose close may already have run, so it is never billed |
| Lapse and suspend | Suspended rows are skipped by period close, so the last month's usage disappears |
| Early renewal with a plan change | New plan economics apply before the paid period starts, contradicting "plan changes take effect at renewal only" |
| Any bound change | Isolates holding old and new bounds in cache alternate for up to 30 s; the DO resets on every flip and loses counted usage |

**Fix.** Separate **coverage** (what was paid) from the **quota cycle** (when counters reset).
- **Anchor the cycle.** It rolls monthly from `entitlement.cycle_anchor`. Payments never move the
  anchor; only a real lapse resets it.
- **Grace meters against the last paid cycle.**
- **The DO resets forward only** (`cycle_start > stored.cycle_start`). The cycle is carried from
  admission through settlement.
- **`usage_rollup` is keyed by cycle start.**
- **Early renewal becomes a no-op for metering.**

### 3.8 C8 — Egyptian tax invoicing is absent

**Evidence.**
- The design has no VAT treatment, no seller or buyer tax ids, no sequential numbering, no credit notes
  and no ETA submission. `06` §6.3 says Paymob receipts are the only external documents.
- The platform `invoice` is a usage artefact: credits × `credit_price`, calendar-month keyed, issued
  at period *end* for a *prepaid* service, and skipping zero-usage clinics.
- Egypt:
  - B2B e-invoicing through ETA is mandatory for VAT-registered sellers, and e-invoices are required
    to deduct costs.
  - VAT is 14% on digital services.
  - Invoices must be sequentially numbered and carry buyer and seller identity.
  - Refunds require numbered credit notes that reference the original invoice.
  - Records must be kept for 5 years.
  - Clinics' medical services are VAT-exempt, so the VAT is a real cost to them, but they still need
    the e-invoice to deduct the expense.

**Impact.** Selling without ETA documents is non-compliant for a VAT-registered vendor. Clinics cannot
deduct the expense, and refunds have no document to credit.

**Fix.**
- **Commercial invoicing lives in the ABO at payment time.** An `invoice` table holds a series and
  sequential number, `invoice` or `credit_note`, `payment_id`, a buyer snapshot, net/VAT/gross, and
  the ETA UUID and status. Outbox jobs `issue_invoice` and `issue_credit_note` drive it.
- **Submission goes through a certified e-invoicing provider,** because ETA signatures require a
  licensed CA token or HSM that a Worker cannot hold.
- **Prices are VAT-inclusive.**
- **Collect a billing profile once:** legal name, tax registration number (TRN) or national id,
  address, email and phone.
- **The platform becomes money-free** (P5).
- **Minimum before taking money:** VAT-inclusive offers, the billing profile, invoice and credit-note
  records with PDFs, the e-invoicing provider integration, and 5-year retention.

---

## 4. Major findings — ABO design

### 4.1 M1 — "Two independent signatures" is not real

**Evidence.**
- `01-overview.md` says "A full compromise of either module alone cannot grant service".
- `02` §2.1: one deployable and one D1 for both modules.
- `03-trust-and-keys.md` §3.1: both private keys are secrets of the same Worker.
- `11` §12 attack rows repeat the claim.
- `07` §11.2: a comp order "auto-provisions through the Worker's own keys", so one operator key
  already grants end to end.

**Impact.**
- **Shared custody.** Both keys sit in one `env`, one isolate, one deploy pipeline, one account and
  one operator. A malicious dependency (including the planned shared `packages/ed25519-jws/`), stolen
  `wrangler` credentials, or deploy rights obtain both.
- **Confused deputy.** Even if custody were split, the orchestrator verifies nothing independently. It
  co-signs whatever the purchase module writes to the outbox.
- **The complexity buys nothing.** The CAT key, its registry row, its rotation, the custody grep test
  (R1-V7) and two attack-matrix rows protect a property that does not exist.

**Fix.**
- **The ABO is one trust principal with one signing key** (the purchase proof).
- **State the threat model honestly:** no clinic, internet caller, or person without vendor
  infrastructure access can grant. Every grant carries a stored, verifiable ABO signature and is
  reconciled against Paymob payouts.
- **Keep two Workers,** but for the real reasons: payment secrets and the webhook surface stay out of
  the AI request path, deploys and faults are isolated, and a proof means something only if the
  platform does not sign it for itself.
- **Store the compact proof JWS on the platform** and self-audit that every coverage row links to a
  proof that verifies.

### 4.2 M2 — Per-call CAT on a public control plane for machine calls

**Evidence.**
- `05` §5.6: CAT with `jti` + body hash + 120 s, and a D1 `jti` insert per call.
- `08` §8.1: `OperatorAuth.resolve` becomes async.
- Both Workers are in one Cloudflare account (`02` §2.1; separate account deferred, `11` §13 item 4).

**Impact.** Given M1, the CAT adds no security for the machine path. What it does add is a
public HTTP grant surface, a key and its rotation, a replay table written on every call, and the
lost-response edge case (`purchase_proof_replayed`).

**Fix.**
- **The platform exposes a non-public `WorkerEntrypoint`** (not routed on `fetch`) with typed methods
  (§6.3).
- **The ABO reaches it through a service binding.** Only the ABO's `wrangler.toml` declares the
  binding, enforced by a CI lint.
- **The purchase proof is the only grant credential.**
- **Trade-off:** a later move to a separate Cloudflare account needs a signed HTTP path again. That is
  cheap to reintroduce, and with one operator a separate account protects nothing today.

### 4.3 M3 — The provisioning receipt chain protects nothing

**Evidence.**
- `09-clinic-changes.md` §9.3: `add_platform_receipt_key` is owner/admin-gated, the same gate as
  `set_ai_availability`.
- `03` §3.5: trust is anchored in a key fetched by Flutter, a client the owner controls.
- `11` §12 admits a forged receipt "flips a UI flag, it does not grant service".
- The same table's claim that the receipt RPC is "the only write path" is false, because the owner can
  seed their own key.

**Impact.** A third signing key, the platform's first production signing path, `GET /v1/platform-keys`,
a clinic key store, add and revoke RPCs, pgsodium JWS verification in Postgres, a self-heal refetch and
a rotation runbook all protect a flag the owner can forge and the guard ignores.

**Fix.**
- **Drop receipts.** The owner/admin desktop reads the platform status (§6.3) with the access token it
  already has and writes `set_ai_availability(enabled, platform_base_url, valid_until)` through a
  plain owner-gated RPC.
- **Keep `valid_until` self-expiry.** It equals the coverage's `grace_until`.
- **Staff clients still only read the flag.**
- Receipts would only be worth keeping if non-admin devices were allowed to refresh the flag (§10).

### 4.4 M4 — The poll token is a single-desktop credential

**Evidence.**
- `05` §5.3: the poll token is returned once. `409 order_exists` returns no new token.
- `05` §5.4: both `GET` and `renewal-checkout` require it.
- `10-flutter-flows.md` §10.1 stores it in one desktop's local secure storage.
- `10` §10.4 recovers *activation* after a reinstall, but not renewal or plan change.
- Comp orders are created by ops, so the clinic never receives a token at all.

**Impact.**
- **Other desktops cannot renew.** An owner on another branch's desktop, or after a reinstall, sees the
  Renew banner but cannot obtain a checkout, renew, or change plan. Service lapses. For multi-branch
  clinics this is the normal case.
- **Trials cannot convert.** A trial clinic (comp) can never pay.

**Fix.**
- **Clinic-signed requests.** A new owner/admin RPC,
  `sign_ai_billing_request(action, args)`, returns `{payload, signature}` signed with the installation
  key. That key lives in the clinic database, so every desktop can reach it.
- **Payload:** `{installation_id, kid, action, args, nonce, iat}`, valid for about 5 minutes. Actions:
  `status`, `checkout(offer)`, `history`, `update_billing_profile`.
- **The ABO verifies** through the platform's `verifyInstallationToken`/`getInstallation` RPC for
  enrolled installations, so there is one verifier and key-expiry rules cannot drift.
- **Self-signed proof of possession** is used only before the first enrollment.
- **Removes:** `poll_token_hash`, local token persistence, the "no new token" dead end,
  `409 key_rotated`, and the order-clock key check.

### 4.5 M5 — Unauthenticated order creation allows free squatting

**Evidence.**
- `05` §5.2–§5.3: order creation uses a self-signed proof of possession (the key is inside the payload).
- `04` §4.1.2: the live-order index includes `pending`, and there is no cancel.
- Installation ids appear in every clinic access token (AAT) `iss` claim and on staff devices.

**Impact.**
- **Free, repeatable squat.** Anyone who knows an `installation_id` can create a `pending` order with
  their own key and block the clinic with `409 order_exists`, repeating after each expiry. It costs
  nothing.
- **Billing hijack.** For an enrolled installation with no live order, an attacker can pay with their
  own key and take over the billing relationship. A later refund then suspends the victim.
- **Merchant account risk.** Unlimited Paymob intentions put the merchant account's reputation at risk.

**Fix.**
- **Pending attempts never block.** Uniqueness applies only to the subscription.
- **Bind enrolled installations to their current key.** After enrollment, every request must verify
  against the platform's current key (M4).
- **Create intentions lazily** on "go to checkout", with a per-installation cap on open attempts.

### 4.6 M6 — The order-as-subscription state machine is overbuilt; comp orders contradict it

**Evidence.**
- `06` §6.1: eight states, a 30-day payable tail, terminal `expired`, and a coherence matrix
  (§6.7) needed to keep it consistent with the three-state entitlement.
- `06` §6.5: comp orders are created in `paid`, but the live-order partial unique index (`04` §4.1.2)
  forbids a second live order. So "mid-period upgrade = comp + override" (§6.4) and goodwill
  extensions for paying clinics are impossible.
- A comp order for a never-enrolled installation has no source for the NOT NULL `order_payload`
  (clinic-signed key material), and §6.5 does not say where it comes from.

**Impact.** C3, C5, M4 and the refund blast radius (M7) all stem from folding payment attempts,
coverage and subscription into one mutable row.

**Fix.** Use the §6.2 model: `subscription` (no status column) + `payment` + `coverage_segment`.
Status is derived from coverage dates: active / grace / lapsed. **Comp** becomes a coverage segment
with `source = 'comp'`, an operator id and a reason. Extensions append, trials are `[now, +N]`, and
upgrades are plan B over `[now, covered_until]`. The coherence matrix shrinks to those three rows.

### 4.7 M7 — Refund and chargeback policy is too blunt and has no recording path

**Evidence.**
- `06` §6.1/§6.3: any refund means terminal `refunded` and immediate suspension.
- `07` §7.2: chargebacks go through "ops … manually triggers the suspend path", but the ABO's only ops
  endpoint is comp orders. Ops would therefore suspend through the platform, leaving the ABO at
  `provisioned`: permanent drift.

**Impact.** A 100 EGP goodwill refund, a refund of a duplicate, or a refund of an old period kills
current service and ends the relationship. Chargebacks cannot be recorded in billing at all.

**Fix.** Reversals act on a specific `payment`.
- **Full refund or void:** revoke that payment's segment. Delete it if not started, cut it to now if
  current, and leave it if past. Then call `voidCoverage` on the platform and issue a credit note.
- **Partial refund:** issue a credit note, with no coverage effect unless ops marks it as revoking.
- **Chargeback:** an ops "record reversal" action, which then follows the full-refund path.

### 4.8 M8 — Price, interval and grace live in the wrong system; no term plans

**Evidence.**
- `04` §4.1.6 / `05` §5.10 put price, display copy and `grace_days` on the **platform** plan and a new
  public `GET /v1/plans`. That endpoint does not exist in code today.
- The ABO's dunning reads `grace_days` from a platform cache at use time, so a catalogue edit changes
  grace for orders already in flight.
- The plan catalogue has no interval (`plan_catalogue.sql:1-9`).
- `06` §6.4: `paid_at + 1 month` with no rule for the 31st.
- Renewal is payer-initiated with no card on file, and dunning is in-app only.

**Impact.**
- **Cross-deploy coupling.** The ABO's dunning depends on the platform cache, and the platform becomes
  the price authority for money it should never touch.
- **Price history is lost** when a price is edited in place.
- **Churn.** Twelve manual payments a year with no reminders is a churn machine, and quarterly or
  annual prepay (the cheapest retention lever) cannot be expressed.

**Fix.**
- **An ABO `offer` table** with immutable price versions: `plan`, `interval_months`, `gross_price`,
  `vat_rate`, `currency`, `active_from`/`to`.
- **A public ABO `GET /v1/offers`** for Flutter.
- **Grace is ABO policy,** snapshotted as an absolute `grace_until` into each segment and proof.
- **The platform plan keeps economics only.**
- **Store an `anchor_day`** and clamp dates to month end.
- **Remove the platform `GET /v1/plans`, `plan.price_*` and `plan.grace_days`** from A17.

### 4.9 M9 — The hourly order clock is not idempotent

**Evidence.**
- `06` §6.1: after the suspend the "order stays `past_due`", and there is no marker that the suspend
  was requested.
- `08` §8.2: `entitlement-suspend` on a non-active entitlement returns `409 illegal_lifecycle_transition`,
  which the consumer does not map.
- `GET /v1/plans` serves only active plans, yet `06` §6.6 says dunning for retired plans "proceeds
  unchanged".
- Cron Triggers are at-least-once.

**Impact.**
- **Repeat suspends.** `past_due ∧ grace_until < now` stays true for 30 days, producing about 720
  failing suspend rows per unpaid clinic and drowning real alerts.
- **Double checkouts.** Duplicate cron runs double-issue checkouts, so an owner can pay twice (C3).
- **Retired plans have no grace** to compute from.

**Fix.** Most of this disappears under C6 and the §6.2 model: there are no suspends, no pre-issued
checkouts, and grace is stored. What remains (expiring attempts, dunning emails) uses level-triggered
predicates, compare-and-set claims, and `dedupe_key`, with a "run twice, assert no new side effects"
test.

### 4.10 M10 — No customer billing identity or contact channel

**Evidence.**
- Paymob intention creation requires `billing_data`, and a missing `phone_number` is rejected.
- The order payload (`05` §5.2) carries no name, email or phone.
- `06` §6.3 limits dunning to in-app banners.

**Impact.**
- **Checkout creation fails as written.**
- **Silent suspension.** A clinic owner who does not open the app during the renewal window loses AI
  with no warning.
- **Nowhere to send documents.** There is no channel for invoices or duplicate-payment notices.

**Fix.**
- **A clinic-signed billing profile on `subscription`,** the same data as C8.
- **Transactional email:** renewal due at T-7 and T-1, lapsed, receipt and invoice, and possible
  duplicate.

### 4.11 M11 — Alerts that nobody receives

**Evidence.**
- `07` §11.1/§11.3: failures are "alert log" lines and `reconciliation_alert` rows read via
  `wrangler d1`, and there is deliberately no endpoint.
- `ai-platform/wrangler.toml` has no `[observability]` block, and production uses `LOG_VERBOSITY = "0"`.
- `ai-platform/src/logger.ts` writes text lines, not JSON.
- `worker.ts` `scheduled` swallows job errors.

**Impact.** A paid order not provisioned, an HMAC mismatch after a Paymob field change (every payment
then gets `400`), stuck outbox rows and a stopped cron all make no noise. The operator learns about them
when a clinic calls. Without Workers Logs enabled, the lines are not even retained.

**Fix.**
- **A `notify(key, text)` function** that sends to a Telegram bot or Email Worker, deduplicated through
  a D1 `alert_state` table.
- **A daily digest.** Its absence means the crons have stopped.
- **`[observability] enabled = true` on both Workers,** with JSON error lines.
- **Alert keys:** `paid_not_provisioned > 15 min`, `outbox_blocked`, `webhook_hmac_fail`,
  `webhook_unresolved`, `payment_found_by_inquiry`, `platform_unreachable > 30 min`,
  `possible_duplicate`, `amount_mismatch`, `job_error`.

### 4.12 M12 — The payment system of record has no history, raw evidence, export or durable backup

**Evidence.**
- `orders` is overwritten on each renewal, and amounts exist only inside JWS strings.
- `webhook_events` keeps only a hash of a body that is never stored.
- D1 Time Travel covers 30 days, and a restore is destructive and in place.
- Egyptian law requires financial records and invoices to be kept for 5 years.

**Impact.**
- **Basic reports are hard.** "All Q1 payments with amounts" means parsing JWS strings.
- **Late-found errors are unrecoverable.** A bad migration discovered on day 31 cannot be undone.
- **Restores are destructive.** Restoring to fix one row rolls back every payment since.

**Fix.**
- **An append-only `payment` table (C2)** and raw webhook bodies.
- **A daily NDJSON export of changed rows to R2** with a retention lock of at least 6 years.
- **A written rebuild runbook** (orders from platform coverage + Paymob `special_reference`).

### 4.13 M13 — Ops surface unworkable for one operator; duplicate operator registries

**Evidence.**
- `07` §11.2: the only ops endpoint is comp orders; everything else goes through `wrangler d1`.
- Clinic names exist only inside `order_payload` bytes.
- `04` §4.1.8 introduces `ops_operator` + `ops_jti` + a dual-registry provisioning script + a `cat-sign`
  CLI, all to protect one endpoint.
- The design adds `control_operator` + `control_cat_jti` on the platform as a second, schema-identical
  registry.

**Impact.** "I paid, AI is not on" means the Paymob dashboard, ABO D1 with `json_extract`, platform D1,
and the clinic: four systems and three CLIs per support call, with no "retry now" action.

**Fix.**
- **Put Cloudflare Access (per-person SSO/MFA) in front of both human surfaces:** the platform
  `/control/*` routes and the ABO `/v1/ops/*` routes. The Worker validates the
  `Cf-Access-Jwt-Assertion` JWT itself (never edge-only) and records the Access identity in the audit
  row. The viewer and scripts use Access service tokens.
- **ABO ops behind Access:** order and subscription lookup (payments, segments, outbox, webhooks, live
  platform state), plus retry outbox row, record reversal, grant comp segment, cancel attempt.
- **Show a subscription short-code in Flutter** for support calls.
- **Removes:** `ops_operator`, `ops_jti`, `control_operator`, `control_cat_jti`, human CAT signing,
  the `cat-sign` CLI, and the dual-provisioning and rotation scripts.
- **Why this over human CATs:** once no HTTP route on the platform can grant (grants need an ABO proof
  through the binding), per-request signed tokens with body hashes and replay tables are overkill for
  human, non-grant actions. Access provides per-person identity, MFA and instant revocation without
  custom crypto. This resolves a disagreement between the trust analysis (keep human CATs) and the
  platform and reliability analyses (Access).

### 4.14 M14 — Nothing sells until nine bands land; bearer removal breaks existing tooling

**Evidence.**
- Delivery plan §1.2: "nothing is sold or deployed until the whole chain is complete". That covers
  bands M–U, 22 slices, 31 master-chain steps and 4 checkpoints, for a volume of a few orders a day.
- N2 deletes `OPERATOR_BEARER_TOKEN` before N3 delivers `cat-sign`.
- `ai-platform-viewer/src/lib/platform-installation-api.ts` and `ai-platform/test/e2e/harness/control.ts`
  still use the bearer, and no slice migrates them.

**Impact.** Months of zero revenue and zero customer feedback, with operator tooling broken midway.

**Fix.** Use the §8 sequence. Sell manually first, with platform coverage enforcement in place. Put
Access in front of `/control/*` *before* removing the bearer, and remove the bearer last.

### 4.15 M15 — Time-driven flows cannot be tested end to end as planned

**Evidence.**
- Delivery plan §3.13 relies on "cron invocation with injected time". But CAT and proof expiry use the
  platform's real clock, clinic `valid_until` uses Postgres `now()`, and periods are hard-coded to
  one month.

**Impact.** The master chain cannot advance a month coherently across four deployables, so dunning and
lapse are effectively untested.

**Fix.**
- **Add `interval` and `grace` to the ABO offer** and a staging-only offer with a 1-day interval and
  1-hour grace, so the full lifecycle runs in real time in staging.
- **Use a clock abstraction only for ABO state predicates** (unit tests), never for token `iat`.
- **Add a local HMAC-signed webhook replay fixture.**

### 4.16 M16 — Wrong "code-verified" claims and self-contradictions in the documents

**Evidence.**
- `02` §1 says "every contract below was verified against the code", yet:
  - All control paths are written `/control/v1/*`; the code serves `/control/*`.
  - `06` §6.2 says "no guard change is needed", which is false once coverage exists.
  - `05` §5.10 treats `GET /v1/plans` as an existing platform read; it does not exist.
- Delivery plan R-E3 ("immediate processor runs") and R-E7 ("processed inline by the clock") contradict
  R1's queue consumer.
- R-E9 expects repurchase to provision through `enroll → entitle`, which the platform rejects with 409s
  (C5).
- R1-V8 asserts byte-identical proof replay, which is the root of C4 path 5.
- Plan §5 requires feature specs to be written by transcription.

**Impact.** Specs transcribed from these documents will encode the bugs.

**Fix.** Rewrite the architecture parts to the §6 target before any spec is written, and regenerate the
delivery plan from it (§8).

---

## 5. Major findings — AI Platform rework

### 5.1 P1 — The control API is multi-step, non-idempotent, and signals success with 409s

**Evidence.**
- There are no idempotency keys on control handlers.
- `enroll` then `entitle` is two calls (`lifecycle.ts:248-288`, `entitle.ts:189-325`), and a retired
  plan between them leaves a half-applied enroll.
- `renew` is a third path (`08` §8.2) with its own allowed states.
- `entitle` takes per-request `grants[]` and budgets from the request body.

**Impact.** This is the root of C5. The ABO must choose between three calls and interpret 409s, and
`quota-inspect` cannot distinguish success from the failure cases.

**Fix.** A single `applyCoverage(proof)` in one D1 batch. It enrolls if needed, snapshots plan
economics, inserts the coverage row keyed by the proof `jti`, sets the anchor and writes the audit row.
It is idempotent by `jti` plus claims hash and returns typed permanent errors. Signatures are in §6.3.
- **Removes from the ABO path:** `enroll`, `entitle`, `renew`, `override`'s period fields,
  `entitlement-suspend`, and the 409→done mapping.

### 5.2 P2 — The plan identity model is broken

**Evidence.**
- `platform-vocabulary.ts:2-7, 92-99`: the guard ranks a fixed four-name list with
  `planTierMeetsMinimum`, and enroll uses `isKnownPlanTier`. Any new plan name (which `06` §6.6 tells
  operators to create instead of renaming) fails the tier check.
- `entitle.ts:280-311`: one clinic's `grants[]` with `scope: "plan"` inserts *global* `plan:{name}`
  grant rows as a side effect.
- The guard requires a grant as well as `allowed_capabilities` (`entitlement/index.ts:191-219`).
- `plan.ts:281-292`: plan delete writes only an audit row and returns `ok` while deleting nothing.

**Fix.**
- **Add a `plan.tier` column.** The name becomes an immutable SKU id. Status is `active` or `retired`.
- **Delete** plan delete (use retire) and plan rename.
- **`allowed_capabilities` from the coverage economics snapshot** becomes the only plan→capability map.
  `capability_grant` is kept for installation-level exceptions only.
- **Editing a plan affects new sales only.** That is intended, and should be documented.

### 5.3 P3 — Plan features are sold but not enforced

**Evidence.**
- `worker.ts:984`: the router always gets `entitlementMaxCostClass: "premium"`, so the plan's
  `max_cost_class` is never applied.
- `token_budget`/`cost_budget` come from the entitle request body (`entitle.ts:110-122, 270-271`) and
  are enforced only on the DO-unavailable fallback path (`admission/index.ts:286-301`).
- That fallback path does **not** check `credit_budget`, the unit actually sold, while the DO checks
  only credits and requests.

**Impact.** A Starter clinic can reach premium-cost models, and whether a request is admitted depends
on whether the DO was reachable.

**Fix.** Wire the snapshot's `max_cost_class` into the router, or stop selling it. Remove
`token_budget`/`cost_budget` and make credits the single economic unit on both admission paths.

### 5.4 P4 — Installation keys hard-expire at 365 days with operator-only rotation

**Evidence.**
- `lifecycle.ts:30-36`: `INSTALLATION_KEY_TTL_DAYS = 365`.
- `identity/index.ts:212-227` enforces `valid_until`.
- `rotate` is operator-only.
- `06` §6.4 couples renewals to the as-purchased key.

**Impact.** On day 365, a paying clinic's access tokens (AATs) fail while the ABO keeps renewing
coverage: paid but broken, with a support call as the only remedy.

**Fix.**
- **Clinic self-rotation:** a request signed by the current live key registers a new key, with proof of
  possession.
- **Remove key material from renewal proofs** (C5).
- **Alert the operator** when any installation's live key is within 30 days of expiry.

### 5.5 P5 — Platform invoice, `credit_price` and period close conflict with ABO billing

**Evidence.**
- `period-close/index.ts`: the invoice total is credits × `price_per_credit` (REAL), calendar-month
  keyed, active rows only, and skips zero usage.
- The design's A17 amendment (price the invoice from the proof's `amount_cents`) is not implemented, and
  `credit_price` is still live.
- The ABO sells flat prepaid plans.

**Impact.** A per-credit platform invoice is either a second, conflicting charge or dead data, and it
drags money fields (`amount_cents`, `currency`) into purchase proofs.

**Fix.**
- **Delete `invoice`, `credit_price` and its control endpoint, and the `0 5 1 * *` period close.**
- **Remove amounts from proofs.** The platform becomes genuinely money-free.
- **`usage_rollup` keyed by cycle is the usage statement,** served through `/v1/usage`.
- **Invoicing is ABO-only** (C8).

### 5.6 P6 — Delete and purge leave the ABO with live subscriptions; no reconciliation read model

**Evidence.**
- `retention/index.ts:287-358`: purge deletes a deleted installation's entitlement, keys and usage.
- `07` §11.3 reconciles by calling `quota-inspect` per installation and paging `control_audit`.

**Fix.**
- **Purge keeps coverage rows,** a financial record retained for the ledger horizon, with display
  fields anonymised.
- **`applyCoverage` returns `installation_deleted`.**
- **Add `exportCoverage(updated_since, cursor)` and `getInstallation`** as binding RPCs, replacing
  audit paging and `quota-inspect` for the ABO.

### 5.7 P7 — The clinic cannot tell "not paid" from "nothing available"

**Evidence.**
- `capability/index.ts:696-704`: discovery returns an empty list for any non-active status, with no
  reason.
- `usage-summary/index.ts:162-174` returns 500 when the DO is unavailable.

**Fix.** Extend `GET /v1/usage` (AAT) with an `access` block (state, plan, `access_until`,
`grace_until`) and cycle usage, and degrade gracefully when the DO is unavailable. This replaces the
designed `/v1/installation/status` and its receipts. When the guard denies because of coverage, it
re-reads that installation's coverage from D1 once (throttled per isolate), removing the up-to-30-second
"paid but still disabled" lag.

---

## 6. Recommended target design

### 6.1 Trust model

| Channel | Authentication | Keys |
|---------|---------------|------|
| Clinic → ABO (status, checkout, history, billing profile) | Clinic-signed request from the owner/admin-gated DB RPC; verified via the platform binding for enrolled installations; self-signed proof of possession only before the first enrollment | Existing installation key |
| Paymob → ABO webhook | HMAC-SHA512 + state-aware idempotency + Inquiry confirmation for refund/void children | `PAYMOB_HMAC_SECRET` |
| ABO → platform | Service binding to a non-public `ControlEntrypoint`; grants require an ABO-signed coverage proof (JWS stored platform-side) | **One** ABO key: the proof key (platform holds its public key set, `kid`-based; rotation has no overlap wait) |
| Humans → platform `/control/*` and ABO `/v1/ops/*` | Cloudflare Access (SSO + MFA), JWT validated in the Worker, identity in audit rows | None custom |
| Clinic app → platform `/v1/*` | Existing AATs; the guard enforces coverage per request | Existing |
| Clinic AI flag | Plain owner-gated RPC fed from `/v1/usage` `access` block; self-expires at `grace_until`; staff read only | None |

**Honest threat statement:** vendor infrastructure access (Cloudflare account, deploy rights) or a
platform compromise can grant service; nothing else can. Every grant carries a stored, verifiable ABO
signature and is reconciled against Paymob payouts. Comp grants are single-person actions, attributed by
Access identity and visible in reconciliation.

### 6.2 Billing data model (ABO)

Payments are immutable facts. Coverage segments are what payments and grants bought. Subscription
status is derived. The platform sees only coverage.

| Table | Key columns | Notes |
|-------|-------------|-------|
| `subscription` | `subscription_id`, `installation_id` UNIQUE, current `kid`/`public_key`, `anchor_day`, billing profile (legal name, TRN or national id, address, email, phone) | One per installation, forever; no status column |
| `offer` | `offer_id`, `plan`, `interval_months`, `gross_price_cents`, `vat_rate_bp`, `currency`, `grace_days`, `active_from`, `active_to` | Immutable price versions; `plan` must be active in the platform `listPlans()` |
| `payment` | `payment_id`, `subscription_id`, `offer_id` + snapshot (plan, interval, gross, VAT, currency), key snapshot, `status` (`open`/`succeeded`/`expired`/`amount_mismatch`), `refunded_cents`, `reversal` (`none`/`voided`/`refunded`/`charged_back`), `expires_at`, `paid_at` | One per checkout attempt; `special_reference = payment_id` |
| `provider_refs` | as designed, keyed by `payment_id`; kinds `intention`, `order`, `transaction`, `refund_txn` | Keeps the provider-id quarantine |
| `coverage_segment` | `segment_id` (= proof `jti` = platform `grant_id`), `subscription_id`, `source` (`payment`/`comp`), `payment_id?`, `operator_id?`, `reason?`, `plan`, `starts_at`, `ends_at`, `grace_until`, `revoked_at?`, `applied_at?` | Applied to the platform immediately (the platform enforces the dates) |
| `invoice` | `series`, `number`, `kind` (`invoice`/`credit_note`), `payment_id`, `original_invoice_id?`, buyer snapshot, net/VAT/gross, `eta_uuid`, `eta_status`, `pdf_pointer` | Kept for 5+ years |
| `webhook_events` | UNIQUE(`provider`, `provider_txn_id`, `state_hash`), raw body, `status` (`received`/`processed`/`failed`) | Store, then process in the same batch |
| `outbox` | `kind` (`apply_segment`/`void_segment`/`issue_invoice`/`issue_credit_note`/`send_email`), `dedupe_key` UNIQUE, claims JSON, lease/backoff columns, `status` (`pending`/`processing`/`done`/`blocked`) | Never purged; exported daily |
| `alert_state`, `reconciliation_alert`, `ops_audit` | — | `ops_audit` records the Access identity |

**Scenario mapping.**
- **First purchase.** A signed request creates the subscription and billing profile. `checkout(offer)`
  creates a `payment` and an intention. On a verified callback with matching amount: `succeeded`, a
  segment `[paid_at, +interval]`, `apply_segment`, and `issue_invoice`.
- **Renewal (early or late, any desktop).** The segment starts at `max(covered_until, paid_at)`. Early
  payment only extends coverage; the platform's cycle is unaffected. After a lapse it starts at
  `paid_at`, and the platform resets the anchor. There is no re-purchase concept.
- **Duplicate payment.** A second stacked segment, plus a `possible_duplicate` alert and email. A refund
  on request revokes it.
- **Stale or cheaper intention paid.** The segment carries that payment's own plan and price.
- **Refund or void (full).** The payment is reversed and its segment revoked (`void_segment` with
  `end_access_now` if current), plus a credit note.
- **Partial refund.** A credit note only, unless ops marks it as revoking.
- **Chargeback.** The ops "record reversal" action, then the full-refund path.
- **Comp, trial, goodwill, upgrade.** A `comp` segment. An upgrade is plan B over `[now, covered_until]`.
- **Plan change.** The next payment's segment carries the new plan from its own start. The platform
  picks the current segment's economics.
- **Key rotation.** A clinic self-rotates on the platform (P4). The ABO reads the current key through
  the binding, and the subscription follows it.

### 6.3 Platform contract

**Schema.**

```sql
CREATE TABLE coverage (
  grant_id         TEXT PRIMARY KEY,          -- proof jti = ABO segment id; idempotency key
  installation_id  TEXT NOT NULL REFERENCES installation(installation_id),
  plan             TEXT NOT NULL,
  economics        TEXT NOT NULL,             -- JSON snapshot at apply: tier, credit_budget,
                                              -- request_quota, soft_threshold, allowed_capabilities,
                                              -- max_cost_class (only if enforced, P3)
  starts_at        TEXT NOT NULL,
  ends_at          TEXT NOT NULL,
  grace_until      TEXT NOT NULL,             -- >= ends_at; ABO policy, enforced here
  source           TEXT NOT NULL,             -- purchase | renewal | comp | migration
  subscription_ref TEXT,
  proof            TEXT NOT NULL,             -- compact JWS as received (self-audit, M1)
  claims_hash      TEXT NOT NULL,
  applied_at       TEXT NOT NULL,
  voided_at        TEXT,
  void_reason      TEXT
);
CREATE INDEX idx_coverage_installation ON coverage (installation_id, ends_at);
ALTER TABLE entitlement ADD COLUMN cycle_anchor TEXT;   -- NULL until first coverage
ALTER TABLE plan ADD COLUMN tier TEXT NOT NULL;         -- ranked vocabulary; name = free SKU id
-- Retire: entitlement.status/period_*/token_budget/cost_budget; invoice; credit_price.
```

**Guard rule** (per request, from cached coverage rows):

```ts
const live = coverages.filter(c => !c.voided_at);
const cur  = live.find(c => c.starts_at <= now && now < c.ends_at);
const last = maxBy(live.filter(c => c.ends_at <= now), c => c.ends_at);
if (cur)                                  { state = "active"; econ = cur.economics;  meterAt = now; }
else if (last && now < last.grace_until)  { state = "grace";  econ = last.economics; meterAt = last.ends_at - 1ms; }
else deny("ai_disabled", last ? "coverage_lapsed" : "no_coverage");
cycle = monthlyCycleContaining(meterAt, entitlement.cycle_anchor);  // carried to DO + settlement
// then unchanged: tier ≥ manifest minimum; capability ∈ econ.allowed_capabilities;
// installation-scope grant exceptions; kill switches. Installation suspend stays the human abuse axis.
```

**Binding RPC** (`ControlEntrypoint`, non-public; human `/control/*` routes call the same core
functions behind Access):

```ts
applyCoverage({ proof }): Promise<
  | { ok: true; outcome: "applied" | "already_applied"; grant_id: string; installation: InstallationView }
  | { ok: false; code: "invalid_proof" | "proof_expired" | "grant_conflict" | "plan_unknown" | "plan_retired"
                     | "coverage_overlap" | "installation_deleted" | "enrollment_required"
                     | "org_has_live_installation" }>;          // thrown = retryable
voidCoverage({ grant_id, reason: "refund" | "chargeback" | "admin", end_access_now }): Promise<...>;
getInstallation(installation_id): Promise<InstallationView | null>;   // status, keys, access view
verifyInstallationToken(token, audience): Promise<{ ok: true; installation_id; kid } | { ok: false; code }>;
listPlans(): Promise<PlanEconomics[]>;
exportCoverage({ updated_since?, cursor?, limit? }): Promise<{ rows; next_cursor }>;
```

**Proof claims** (no money): `iss`, `aud`, `jti = grant_id`, `iat`, `exp ≤ 10 min`,
`installation_id`, `plan`, `starts_at`, `ends_at`, `grace_until`, `source`, `subscription_ref`, and an
optional `enrollment {org_id, display_name, region, kid, public_key}` block, used only when the
installation does not yet exist.

**Idempotency order:**
1. Verify signature, `iss` and `aud`.
2. If `grant_id` exists, return `already_applied` when the claims hash matches (even past `exp`), else
   `grant_conflict`.
3. Check `exp`.
4. Run one batch. A primary-key race means re-read, then `already_applied`.

**Clinic status:** `GET /v1/usage` gains
`access {state, plan, access_until, grace_until}` plus `cycle {start, end, credits_used, credit_budget,
requests_used, request_quota}`.

### 6.4 Async and scheduled work (ABO)

- **Producers** (webhook, ops actions, the clock) write the state change and the outbox row in **one**
  D1 batch, then call `ctx.waitUntil(processRow(id))` as a latency optimization only.
- **Claiming a row** is a lease: `UPDATE … SET status='processing', lease_until=now+120s … WHERE
  (pending ∧ due) ∨ (processing ∧ lease expired) RETURNING *`.
- **Transient errors** back off (`min(2^n min, 60 min)` + jitter) and retry forever. **Permanent errors**
  mark the row `blocked` and alert, and the ops "retry" action re-arms it.
- **Crons:**
  - `* * * * *` sweeper: due and expired-lease rows (capped), Paymob Inquiry for stale open payments,
    alert checks, heartbeat.
  - Hourly clock: expire open payments, dunning emails. No suspends.
  - Daily: reconciliation (payout direction first, plus `exportCoverage` against segments), R2 export,
    digest.

### 6.5 Clinic and Flutter

- **Remove:** the receipt RPCs, `add/revoke_platform_receipt_key`, pgsodium JWS verification, local
  poll-token storage, and the `GET /v1/platform-keys` client.
- **Add:** the `sign_ai_billing_request` RPC, a billing-profile form, an offers screen from the ABO
  `GET /v1/offers`, and an owner/admin refresh of the flag from `/v1/usage` on app start and after
  payment.
- **Purchase and renewal** work identically from any owner/admin desktop.

---

## 7. What the redesign removes and adds

| Removed | Added |
|---------|-------|
| Orchestrator CAT key, its `control_operator` row, CAT minting, `bh`/`jti` for machine calls | Service binding + `ControlEntrypoint` (6 typed methods) |
| Platform receipt key, receipts, `GET /v1/platform-keys`, clinic receipt key store and 2 RPCs, pgsodium JWS verify, receipt rotation | `access` block on `/v1/usage`; plain owner-gated flag RPC |
| `control_operator`, `control_cat_jti`, `ops_operator`, `ops_jti`, `cat-sign` CLI, dual-provisioning script, cross-deploy rotation script, boot self-check, 72 h rotation wait | Cloudflare Access on two route families; Access JWT validation; `ops_audit` |
| Cloudflare Queue, DLQ, redrive tooling | Leased D1 outbox + minute sweeper + Paymob Inquiry fallback |
| 8-state order machine, payable tail, `expired`, coherence matrix, comp orders, live-order index, poll token, `409 key_rotated`, cron pre-issued checkouts, adapter `cancel` | `subscription` / `payment` / `coverage_segment` / `offer` |
| `enroll`/`entitle`/`renew`/`entitlement-suspend` on the ABO path, 409→done mapping, `org_id` OR-clause, per-request `grants[]`/budgets | `applyCoverage` / `voidCoverage`, `coverage` table, `cycle_anchor`, `plan.tier` |
| Platform `invoice`, `credit_price`, period close, amounts in proofs, platform `GET /v1/plans`, `plan.price_*`/`grace_days` | ABO `invoice` + e-invoicing provider + billing profile (legal requirement) |
| — | `notify()` + daily digest; append-only payment ledger; raw webhook bodies; R2 export with retention lock |

Net effect: two trust roots, four tables and roughly five scripts and runbooks fewer. The new
additions are mostly in the payment domain, where correctness and law require them.

## 8. Recommended sequencing

1. **Rewrite the design first.** Rewrite the architecture parts to §6 and regenerate the delivery plan.
   Do not transcribe specs from the current documents (M16).
2. **Phase 0: the platform foundation, and sell manually.**
   - Platform: `coverage` + guard enforcement + `cycle_anchor` + forward-only DO resets (C6, C7);
     P2/P3 fixes; P4 key self-rotation or at least an expiry alert.
   - Put Access in front of `/control/*` and migrate the viewer and e2e harness. Only then delete the
     bearer.
   - Delete the invoice, `credit_price` and period close.
   - Sell through Paymob Payment Links from the dashboard. The operator applies coverage through an
     Access-protected `/control/*` action, and issues invoices through the e-invoicing provider's
     portal.
   - The guard makes non-payment enforcement automatic from day one.
   - This requires dropping the delivery plan's "nothing sold until the chain is complete" assumption
     (§10).
3. **Phase 1: automated first purchase and renewal.** ABO skeleton, `subscription`/`payment`/
   `coverage_segment`/`offer`, atomic webhook ingestion with state-aware classification, Paymob adapter
   with Inquiry fallback, leased outbox and sweeper, `applyCoverage` through the binding, `notify()`,
   Access ops, R2 export, invoicing integration, clinic signed-request RPC, Flutter purchase and
   renewal from any desktop.
4. **Phase 2.** Dunning emails, reversals UI, reconciliation (payout direction first, then
   `exportCoverage`), and term offers.

## 9. Disagreements with the prior deduplication analysis

| Prior verdict (`03-ap-abo-deduplication-analysis.md`) | This review |
|------------------------------------------------------|-------------|
| §4.1: don't merge the ABO into the platform *because it would lose independent key custody* | Custody is already not independent inside the ABO (M1). Keep two Workers, for blast-radius and payment-isolation reasons |
| §4.3: adopt the Cloudflare Queue; it "removes hand-rolled retry/backoff/sweeper code" | Backoff and redrive are still hand-written, a sweeper is still required, and the queue closes none of the stall paths (C4). Drop it |
| F1/F15: price and display copy on the platform plan catalogue, served by `GET /v1/plans` | Offers, price, interval and grace belong in the ABO; the platform keeps economics only (M8) |
| F5: keep the paid-amount chain into the platform invoice | Remove it; the platform invoice is wrong and conflicts with ABO invoicing (P5, C8) |
| §4.2: reword "the platform never learns about money" | Make it true instead: no amounts on the platform at all |
| F23: keep the receipt → clinic flag chain | Drop receipts (M3) |
| F2/F20: keep the order ↔ entitlement split and publish a coherence matrix | Keep a two-record split, but as payment/segment ↔ coverage with one shared id; the matrix shrinks to active / grace / lapsed |
| F13: single-source `grace_days` via the platform catalogue | Grace is ABO policy, snapshotted as an absolute `grace_until` per segment and enforced by the platform |

## 10. Decisions needed from the product owner

1. **Sell manually before the automated chain?** This review recommends Phase 0 (§8). It drops the
   plan's "nothing sold until complete" assumption.
2. **Vendor tax status.** Is the vendor an Egyptian VAT-registered resident? That decides ETA
   e-invoicing versus the non-resident regime. Also, are most buyers sole-practitioner doctors
   (national id, e-receipt) or companies (TRN, e-invoice)?
3. **Term offers at launch.** Quarterly or annual prepay alongside monthly?
4. **Duplicate payments.** Stack and refund on request (recommended), or auto-refund?
5. **Refund channel.** Paymob dashboard plus an ABO "record reversal" action (recommended), or
   ABO-initiated refunds through the API?
6. **Single-person comp grants.** Acceptable with Access attribution and reconciliation (recommended),
   or a two-person rule?
7. **Staff flag refresh.** Owner/admin-only refresh (recommended), or allow staff devices to refresh?
   Receipts would only be worth keeping in the second case.
8. **Card on file.** Paymob offers card-on-file subscriptions. Payer-initiated renewal remains the
   default. The §6.2 model supports merchant-initiated charges as just another `payment` row if you
   revisit this later.
9. **Legacy entitlements.** What coverage cutover dates should existing active entitlements get when
   `coverage` is backfilled?

## 11. Non-findings and refuted concerns

- **Splitting the ABO into two Workers for real key custody.** Rejected: the orchestrator would still
  be a confused deputy, and one operator and one account still hold both.
- **Suspension propagation latency.** At most the 30 s config-cache TTL (`wrangler.toml`), which is
  acceptable. Coverage dates remove even that for expiry.
- **Enroll not consuming the proof `jti`.** Not a hole, since enroll grants nothing. It disappears with
  `applyCoverage` anyway.
- **Removing `OPERATOR_BEARER_TOKEN`.** Sound once Access is in place and the viewer and harness have
  migrated. Recovery is under Cloudflare account IAM.
- **Manual chargeback handling.** Acceptable at clinic volume, given Paymob has no reliable dispute
  callback. What was missing is a recording path (M7).
- **Paymob sandbox and staging reachability.** Not blockers: test keys on the same base URL, and
  staging `workers.dev` is public. Only local development needs a replay fixture.
- **Clinic private key stored as raw `bytea`.** Not a major billing risk: ordering with a stolen key
  means the attacker pays. The existing exposure (minting the clinic's AI tokens) predates the ABO.
  Before building the §3.6 wrapping on pgsodium, confirm Supabase's current support status for it
  (medium confidence that it is being phased out in favour of Vault).
- **Pending-order blocking duration.** Short on its own (a 1 h intention expiry plus the hourly cron).
  It matters only as a squatting vector (M5), and it disappears with payment attempts.
