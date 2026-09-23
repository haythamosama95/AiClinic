# AI Billing Orchestration — Governance

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.
**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [12. Security traceability](#12-security-traceability)
- [13. Proposal open items — resolutions](#13-proposal-open-items-resolutions)
- [14. Deviations from the proposal](#14-deviations-from-the-proposal)
- [15. Constitution compliance check](#15-constitution-compliance-check)

---

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
  scheduled with the §3.6 migration, honest about the live-`postgres` residual.
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
  a consequence of the plan catalogue existing in code; the closed four-tier list would otherwise drift from
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

- **I. Product fit and simplicity** — one new vendor Worker; a single managed Cloudflare Queue
for the outbox handoff (no broker to operate, no polling cron); no microservice sprawl;
payer-initiated renewal avoids stored-credential
machinery. The constitution amendment registering this deployable is in
`.specify/memory/constitution.md` (Operating Constraints) and lands before ABO implementation code.
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

