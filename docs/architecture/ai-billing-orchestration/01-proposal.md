# AI Billing Orchestrator — Architecture Proposal

**Status:** Proposal — agreed in principle, pending architecture-design phase
**Date:** 2026-09-11
**Scope:** New vendor-side AI Billing Orchestrator, trust-model redesign of the
ai-platform control plane, clinic Supabase and Flutter changes.
**Related:** `docs/architecture/ai-platform/01-ai-platform.md` (§8.1, §12.5, A15),
`docs/architecture/ai-platform/03-ai-platform-delivery-plan.md` (Band G).

---

## 1. Context and problem

Today, installation enrollment (Stage 3) and entitlement (Stage 4) are executed **manually**
by an operator holding a single shared `OPERATOR_BEARER_TOKEN` against the ai-platform
Worker (`/control/*`). The clinic-side availability flag is flipped by a manual DB update
per the operator runbook.

We are adding **paid self-service**: a clinic owner purchases a plan, pays via a third-party
payment provider, and provisioning (platform enrollment, entitlement, clinic activation)
happens automatically — with no human in the loop and no way to bypass payment.

The architecture anticipated this: `01-ai-platform.md` §12.5 defers self-service enrollment
with the written trigger *"revisit when a verified sign-up flow with payment exists."*
This proposal is that trigger, executed.

## 2. Core principle

**The ai-platform guard is the only enforcement point; everything else is provisioning.**
Entitlements default to `pending` with zero quotas (fail-closed). Granting service requires
**two independent cryptographic signatures**, so no shared secret, client, or single
compromised service can create an entitlement.

### 2.1 The three-key trust chain

| Key holder | Signs | Verified by |
|---|---|---|
| **AI Billing Orchestrator** (purchase module) | *Purchase Proof* — "order O paid for installation I, plan P, period T" | ai-platform |
| **Orchestrator** | *CAT (Control Action Token)* — short-lived Ed25519 JWS per control call: `sub`, `aud`, `exp/iat`, `jti`, request-body hash | ai-platform |
| **AI platform** | *Provisioning Receipt* — "installation I active until T, platform_base_url B" | Clinic Supabase |

All three reuse the Ed25519 / compact-JWS primitives already in production on both sides
(`EnrolledKeyVerifier` in the Worker; `pgsodium.crypto_sign_*` in clinic Postgres).

### 2.2 Operator keys — done now, not later

The shared bearer is replaced by a `control_operator` table (per-caller public keys,
action scopes, revocation). **All** control-plane callers — the orchestrator *and* human
operators — authenticate with personal keypairs via CAT from day one. The legacy
`OPERATOR_BEARER_TOKEN` is either removed or demoted to break-glass scope
(`suspend`/`resume`/`rotate`/`revoke-key`/`purge` only): **humans can stop abuse but can
never grant service.** Only the two-key flow (purchase proof + orchestrator CAT) grants.

## 3. New deployable: the AI Billing Orchestrator

One new Cloudflare Worker, vendor-operated. Same account/stack/workflow as `ai-platform`,
but **separate Worker, separate D1, separate secrets**. Repository layout:
`ai-billing-orchestrator/` (optional hardening: separate Cloudflare account so CI credentials
for one service cannot touch the other's secrets.)

Two modules, one deployable, **two keys**:

```
AI Billing Orchestrator (`ai-billing-orchestrator`)
├─ purchase module        (purchase proof signing key)
│   ├─ provider adapter   — thin, swappable (Paymob first)
│   ├─ order state machine — provider-agnostic
│   └─ webhook endpoint   — provider signature verification, idempotent event table
└─ orchestrator module    (CAT signing key)
    ├─ consumes paid events via outbox table (in-process handoff; no queue infra)
    └─ drives ai-platform /control/* (enroll → entitle / renew / suspend)
```

### 3.1 Purchase module (payment layer)

- **Provider adapter seam.** The system speaks only canonical domain language:
  - Commands: `create_checkout(order) → url`, `cancel(order)`
  - Events: `payment_succeeded`, `renewal_paid`, `payment_failed`, `refunded`, `chargeback`
  - Provider IDs quarantined in a `provider_refs` table keyed by `order_id`; provider
    event names never travel past the adapter.
  - **Provider swap impact: rewrite the adapter + migrate `provider_refs`. Nothing else
    moves** — not the order machine, not the orchestrator, not the platform, not Flutter.
- **Order state machine:** `pending → paid → provisioned`, plus `past_due`, `refunded`,
  `expired`.
- **Webhook handling:** provider signature verification + timestamp tolerance +
  idempotent processing on provider event ID. A periodic reconciliation poll of provider
  subscription state guards against missed webhooks.
- **Anti-lock-in rules:** no provider IDs in orders/purchase_proofs/audit; no provider event
  names past the adapter boundary; billing *policy* (proration, dunning, grace) is decided
  in the core module — the adapter only executes mechanics.

### 3.2 Orchestrator module (provisioning)

- Consumes `paid` events from the outbox; calls `enroll` then `entitle` (or `renew`),
  presenting the purchase proof + its own CAT.
- On `refunded` / `chargeback` / terminal `past_due`: calls `suspend`.
- **Never holds clinic credentials** — clinic activation is pull-based (§5).
- Renewal payments produce a new purchase proof per period → `renew`.

### 3.3 Scheduled work (Cron Triggers)

- Renewal checks, outbox retries.
- **Reconciliation job:** provider payouts vs active entitlements; drift = alert
  (catches collusion and insider D1 tampering after the fact).

## 4. ai-platform changes

Sequenced **after Band G completes** (Band G is implemented as written first; see §9).

1. **`control_operator` table:** `operator_id, public_key, allowed_actions[], revoked_at`.
   CAT verification implemented as a new `OperatorAuth` factory — the port is injected once
   in `worker.ts`; per-handler `requireOperator` calls are unchanged.
2. **CAT middleware:** verifies Ed25519 JWS (`sub`, `aud`, `exp/iat`, `jti`, body hash);
   `jti` replay store. Bearer removed or scoped to break-glass actions.
3. **Purchase-proof-gated grants:** `enroll` / `entitle` / `renew` require a valid purchase
   proof (billing public key in Worker config). `installation_id`, `kid`,
   `public_key`, `plan`, quotas are taken from / validated against the purchase proof, never
   trusted from the caller. The plan name resolves through Band G's plan catalogue —
   G1's assignment logic (one mutation populating all economics fields) is reused as-is.
4. **D1:** `order_id` + `purchase_proof_id` columns on `entitlement`, both UNIQUE —
   one payment → one entitlement; purchase proofs cannot be replayed. Forward-only migration
   per convention (`YYYYMMDDHHMMSS_snake_case.sql`).
5. **New `POST /control/installations/{id}/renew`:** extends period/quotas on a new
   purchase proof (current `entitle` is one-shot, `409 not_pending`). Mechanical extension of
   `CONTROL_ACTION_PATTERN` + dispatch switch + handler.
6. **New `GET /v1/installation/status`:** AAT-authenticated (reuses the
   `EnrolledKeyVerifier` pattern from discovery/journal endpoints); returns a signed
   Provisioning Receipt when the installation is active. Requires a new platform
   receipt-signing key in secrets (first production signing key in the Worker).
7. **`control_audit`:** real `operator_id` attribution (CAT `sub`) and `order_id` on every
   grant — every entitlement traces to a payment.
8. **Untouched:** guard pipeline, Quota DO, Band G economics (G1–G4), `/v1/*` data path.

## 5. Clinic Supabase changes (per-clinic backend)

1. **Order initiation (corrected flow):** the database has no outbound HTTP capability
   (no `pg_net`/`http`), so the flow is:
   - Owner runs Stage 2 `enroll_installation_keypair()` as today.
   - A new RPC **signs the order payload** (`installation_id, kid, public_key, plan`) with
     the installation private key (proof of possession — same `pgsodium.crypto_sign_detached`
     pattern as `issue_ai_token`) and returns it.
   - **Flutter transports** the signed payload to the AI Billing Orchestrator `POST /orders`.
   - Billing verifies the self-signature: a paid order is cryptographically bound to that
     installation and cannot be redirected to another clinic after payment.
2. **Replace `set_ai_availability`:** the existing RPC
   (`20260905120100_set_ai_availability_rpc.sql`, owner/admin-gated, takes raw
   `boolean, text`) is **replaced** — not supplemented — by `set_ai_availability(receipt)`
   which verifies the platform's Ed25519 signature on the Provisioning Receipt
   (`pgsodium.crypto_sign_verify_detached`, same pattern as `auth_internal.verify_aat`)
   against a platform public key seeded in `ai_internal.app_settings`, then writes
   `ai.availability`. Leaving the old RPC in place would keep a permanent bypass of the
   activation ceremony. Existing deny-all RLS on `app_settings` stays.
3. **No vendor/orchestrator credentials are stored in any clinic** — activation is pull,
   so there is no credential honeypot.

## 6. Flutter changes

1. **Purchase:** `POST /orders` (carrying the RPC-signed payload) → receive
   `{order_id, checkout_url}` → open the URL in the **system browser** (`url_launcher`;
   the provider's hosted checkout page) → poll `GET /orders/{order_id}` until `paid`.
2. **Activation (pull model):** poll `GET /v1/installation/status` with a staff AAT
   (identity passes once enrolled, even while pending) → on active, receive the
   Provisioning Receipt → call `set_ai_availability(receipt)`. Self-healing (re-poll
   anytime); receipts expire with the period so unpaid clinics go dark on re-check.
3. **Rules:** no provider SDK, no card data in the app process, provider swap = zero
   Flutter change; Flutter never calls `/control/*` and never holds control-plane
   credentials.

## 7. End-to-end flows

### 7.1 Happy path (new purchase)

1. Owner: Stage 2 keypair → order-signing RPC → Flutter `POST /orders` → checkout URL →
   pays on the provider's hosted page.
2. Provider webhook → purchase module verifies + records → order `paid` → signs purchase
   proof → outbox.
3. Orchestrator: `enroll` (CAT + purchase proof) → `entitle` (CAT + purchase proof; plan resolved
   via the G1 catalogue) → order `provisioned`.
4. Flutter polls status → receipt → `set_ai_availability(receipt)` → AI chrome enabled;
   the guard admits requests.

### 7.2 Renewal

Provider renewal payment → new purchase proof (same `order_id`, new `purchase_proof_id`, new
period) → orchestrator calls `renew` → new period/quotas. Composes with Band G's G4:
period close invoices the old period; the paid renewal opens the next.

### 7.3 Refund / chargeback / non-payment

Provider event → orchestrator `suspend` (after the dunning/grace policy — see open items).
Receipt expiry + entitlement `period_end` bound the abuse window even before suspension.

## 8. Security analysis — why bypass fails

The guard is the enforcement point and defaults to deny; the entire anti-bypass question
reduces to the integrity of the grant path.

| Attack | Why it fails |
|---|---|
| Self-enroll keypair from the app | Without platform enroll: `401 unauthenticated`; without entitle: `403 ai_disabled` |
| Forge payment webhook | Provider signature verification + idempotency table |
| Call `/control/*` directly | Needs an orchestrator/operator private key — server-side only, never shipped |
| Orchestrator fully compromised | Cannot grant (no purchase proof signing key); worst case DoS via suspend — revocable, audited, rate-limited |
| Billing fully compromised | Cannot write to the platform (no CAT key) |
| Replay one payment for many clinics | UNIQUE `order_id` / `purchase_proof_id`; order bound to one installation by proof-of-possession signature |
| Redirect a paid order to another installation | Purchase proof binds `installation_id` + key material at order creation |
| Rogue human operator | Break-glass credential has no grant scope |
| Flip `ai.availability` in clinic DB | Receipt-verified RPC is the only write path; and even a flipped flag yields no AI access — the guard re-checks entitlement |
| Insider tampers with platform D1 | Reconciliation job (payouts vs active entitlements) + `control_audit` with `order_id` |

**Honest residual risks:** billing + orchestrator key collusion (mitigated by separate
secret stores/access policies + reconciliation); platform D1 insider tampering
(reconciliation + audit review; consider periodic signed audit export); orchestrator DoS
(rate limits + revocation via `control_operator.revoked_at`).

## 9. Verification findings (checked against code 2026-09-11)

Verified feasible with existing production primitives: `OperatorAuth` port injection
(`src/control/auth.ts`, wired once in `worker.ts`); Ed25519 JWS verification
(`src/identity/index.ts`); route/dispatch extension points (`src/control/index.ts`);
one-shot entitle (`src/control/entitle.ts:209`); UNIQUE entitlement per installation
(`migrations/20260821130000_entitlement_installation_unique.sql`); AAT-authenticated GET
precedents (discovery, journal); pgsodium sign/verify in clinic RPCs
(`issue_ai_token`, `verify_aat`); `app_settings` seed pattern for the platform pubkey.

Five findings that shape the work:

1. **Band G has started in code** — `migrations/20260911120000_plan_catalogue.sql`,
   `src/control/plan.ts`, plan economics inside `entitle.ts`. Sequence: **finish Band G
   as written, then refactor.** Expect the refactor collision point to be `entitle.ts`.
2. **Clinic DB cannot make HTTP calls** — order initiation is "RPC signs, Flutter
   transports" (§5.1). Simpler than the original push idea.
3. **`set_ai_availability(boolean, text)` already exists** and is owner/admin callable
   without any proof — must be *replaced* by the receipt-verifying variant (§5.2).
4. **Clinic installation private key is raw `bytea`** (`ai_internal.installation_keys.secret_key`).
   Pre-existing, but this design makes it purchase-authorizing — schedule hardening
   (pgsodium key wrapping) in the architecture phase.
5. **Key rotation for the new trust roots is undesigned** — platform receipt key and
   purchase proof signing key need `kid`-based rotation stories (clinic stores the platform
   pubkey; rotating it needs a clinic-side config update path). Must be designed, not
   hand-waved.

## 10. Required amendments

- **Constitution** (`.specify/memory/constitution.md`): new clause permitting a single
  vendor-side control service (the AI Billing Orchestrator). Outbox table + Cron Triggers (not a
  queue system) keeps the "no queues" rule intact. Supabase still owns clinic domain
  integrity; the ai-platform stays additive and never learns about money.
- **`01-ai-platform.md`:** §8.1 (enrollment trust bootstrap), §12.5 (move self-service
  enrollment from "not yet" to designed, citing the payment trigger), A15 (the payment
  collection boundary it drew is preserved — collection lives in the AI Billing Orchestrator).
- **Delivery plan** (`03-ai-platform-delivery-plan.md`): new band after G for the
  control-plane refactor + AI Billing Orchestrator + clinic/Flutter changes.
- **Stage 3/4 docs and probes:** bearer-based instructions rewritten to CAT.

## 11. Sequencing

1. Band G implemented to completion as written (bearer-based tests acceptable for now).
2. Control-plane refactor: `control_operator` + CAT auth, purchase proof gating on
   `enroll`/`entitle`, new `renew`, `GET /v1/installation/status` + receipt signing.
3. Billing Worker (purchase + orchestrator modules, Paymob adapter first).
4. Clinic Supabase changes (order-signing RPC, receipt-verified `set_ai_availability`,
   platform pubkey seed).
5. Flutter changes (purchase flow, activation polling).

## 12. Open items for the architecture-design phase

- Dunning/grace policy before suspend (how long is `past_due` before access stops?).
- Tighten enroll dedup to `installation_id` only (known `org_id` cross-deployment
  collision risk documented in Stage 3).
- Break-glass bearer: kept scoped, or removed entirely once operator keys exist?
- Separate Cloudflare account for the AI Billing Orchestrator (optional hardening)?
- Trust-root key rotation design (finding 5).
- Clinic private-key wrapping (finding 4).
- CAT `jti` replay store mechanics (D1 table vs DO) at control-plane volume.
