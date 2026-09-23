# AI Billing Orchestration — Flutter Flows

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.
**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [10. Flutter flows](#10-flutter-flows)
  - [10.1 Purchase](#101-purchase)
  - [10.2 Activation (pull model)](#102-activation-pull-model)
  - [10.3 Renewal and dunning UX](#103-renewal-and-dunning-ux)
  - [10.4 Self-healing and failure modes](#104-self-healing-and-failure-modes)

---

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




