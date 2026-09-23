# AP ↔ ABO Redundancy & Constitution Deviation Analysis

**Status:** Analysis — input to the ABO architecture-design phase
**Date:** 2026-09-13
**Scope:** Identify redundant tables, duplicated data/configuration/info between the
implemented ai-platform (AP, all bands except L) and the design-phase AI Billing
Orchestrator (ABO); evaluate where deviating from (or amending) the constitution yields
significant gain.
**Sources:** `docs/architecture/ai-billing-orchestration/01-proposal.md`,
`docs/architecture/ai-billing-orchestration/02-architecture-toc.md`,
`ai-platform/` (code: migrations, `schema.snap.sql`, `wrangler.toml`, `src/`),
`docs/architecture/ai-platform/01-ai-platform.md` (A15–A17),
`.specify/memory/constitution.md` (v1.1.0).

## Table of Contents

1. [Method and Headline Conclusions](#1-method-and-headline-conclusions)
2. [The Two Data Models at a Glance](#2-the-two-data-models-at-a-glance)
3. [Findings](#3-findings)
4. [Constitution Deviation Analysis](#4-constitution-deviation-analysis)
5. [Prioritized Recommendations](#5-prioritized-recommendations)
6. [Appendix: Design-Doc Inconsistencies Found](#6-appendix-design-doc-inconsistencies-found)

---

## 1. Method and Headline Conclusions

Four parallel analysis passes were run: (a) full inventory of the ABO design's data model
and configuration; (b) code-derived inventory of AP's implemented data model (17 D1 tables,
1 Durable Object, 2 R2 object families, all secrets/vars, control-endpoint → table map);
(c) a dedicated duplication hunt across both sides; (d) a constitution deviation/gain
analysis.

**Headline conclusions:**

1. **The ABO design is already unusually de-duplicated on paper.** It holds no plan table,
   no price table, no entitlement mirror, no usage data (02-architecture §4.1.7, deviation
   11). The single biggest duplication — a second plan/price catalogue — was designed away.
2. **…but AP's code has not caught up with its own ratified amendments.** A17 (consolidate
   pricing into the plan catalogue) is docs-only: `credit_price`, its CRUD endpoint, and
   per-credit invoice pricing in `src/period-close/` are still live. This is the one
   HIGH-severity finding and it blocks Band L.
3. **The remaining duplications are mostly deliberate and load-bearing** (two purchase-proof
   stores, dual operator registries, per-store replay guards). The real residual risks are
   *constants and config pairs that must be manually kept equal across two deployables*
   (grace period, key/issuer coordination) and *snapshot staleness* (installation identity
   copied into `orders`).
4. **No constitution deviation is worth taking structurally.** Merging the two Workers or
   sharing one D1 both spend the same load-bearing invariant — independent key custody —
   for savings that clinic-scale volume (a few orders/day) does not justify. The one
   recommended amendment is a *wording* fix: "the AI platform never learns about money" is
   already factually false (AP stores paid amounts and issues invoices per A15/A17) and
   should be reworded, not re-architected around.

## 2. The Two Data Models at a Glance

### 2.1 AP (implemented) — 17 D1 tables, 13 migrations

| Table | Role | Commercial? |
|---|---|---|
| `installation`, `installation_key` | Clinic registry + enrolled public keys | |
| `entitlement` | Enforcement record: plan, period, quotas, `credit_budget`, `max_cost_class`, status | ⚑ |
| `capability_grant` | Capability grants (installation/plan/global scope) + lifecycle | |
| `plan` | Plan catalogue: economics (`credit_budget`, `request_quota`, `max_cost_class`, `soft_threshold`, `allowed_capabilities`), **no price columns** | ⚑ |
| `credit_price` | Per-credit price list — **stale per A17, still live in code** | ⚑ |
| `invoice` | Monthly period-close invoice, PK `(installation_id, period)`, priced `credits × price_per_credit` | ⚑ |
| `usage_event`, `usage_rollup` | Metering ledger + rollups (incl. `quota_weight`) | ⚑ |
| `ai_request`, `ai_attempt` | Request journal + provider attempts | |
| `platform_counter` | Rate-limit/rejection counters | |
| `control_audit` | Operator action audit | |
| `routing_policy`, `token_contract`, `kill_switch` | Control-plane config | |
| `grace_admission_queue` | Durable grace-admission rows (table-as-queue) | |

Plus: one `GatewayObject` Durable Object per installation (period counters incl.
`creditsUsed`, AAT `jti` replay window, idempotency map, entitlement snapshots); two R2
object families (`control/routing-policy/...`, `request/{id}/envelope`); secrets
`OPERATOR_BEARER_TOKEN`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`; crons for retention,
rollup/reconciliation, and monthly period close.

### 2.2 ABO (design only) — 8 billing-D1 tables + 5 platform-D1 additions

**Billing D1:** `orders` (payment record; includes installation-identity snapshot, period
bounds, status machine, poll-token hash, checkout fields), `provider_refs` (provider-ID
quarantine), `webhook_events` (idempotent event log), `outbox` (table-as-queue handoff),
`purchase_proofs` (minting ledger), `reconciliation_alert`, `ops_operator` + `ops_jti`
(ops auth + replay store). The doc's "nine tables" (02:L522–528) enumerates eight — see
§6.

**Platform D1 additions defined by the ABO design (Band L, not yet in code):**
`control_operator` + `control_cat_jti` (CAT auth), `purchase_proof` (consumption log /
replay guard), `entitlement.order_id` + `entitlement.purchase_proof_id` (both UNIQUE),
`control_audit.order_id`.

**ABO secrets/config:** `BILLING_PURCHASE_PROOF_PRIVATE_KEY`, `ORCHESTRATOR_CAT_PRIVATE_KEY`,
`PAYMOB_SECRET_KEY` / `PAYMOB_PUBLIC_KEY` / `PAYMOB_HMAC_SECRET` / `PAYMOB_INTEGRATION_ID`,
active-`kid` vars. ABO holds **no** plan table, price table, entitlement mirror, usage
data, or clinic credentials — by design.

### 2.3 The deliberate two-record split

The design's own framing (02 §4.1.1): only two stores are *records* — ABO `orders` (what
was sold/paid) and AP `entitlement` (what the guard admits). Everything else is transport
(proofs, receipts) or evidence (audit, webhook log). When the two records disagree, that
is drift, and the billing-reconciliation cron (02 §11.3) exists to detect it. This split
is correct and should be kept; the findings below are about making it *tighter*, not
removing it.

## 3. Findings

Each finding has a **Description** (what is written/implemented now) and a **Verdict**
(keep or change, and what to do). Severity legend: **HIGH** = act before Band L;
**MEDIUM** = fix in design phase; **LOW** = justified copy, keep.

### 3.1 F1 — Two pricing artifacts live in AP code — **HIGH**

**Description.** A17 (`01-ai-platform.md` §2.11) mandates one plan catalogue holding price
+ economics, with invoices priced from the *paid amount* on the purchase proof. The ABO
design assumes this: it has no plan/price table and prices orders from a cached
`GET /v1/plans`. But in AP code today, `plan` has no
`price_cents`/`currency`/`display_name`/`description`; `credit_price`
(`schema.snap.sql:63-69`) and `src/control/credit-price.ts` are live;
`src/period-close/index.ts:13-89` prices invoices as `credits × price_per_credit`; and the
`invoice` migration shape (`credit_price_version`, `total`) predates A17's documented
shape (`plan`, `amount`, `currency`). The delivery plan admits the in-flight collision
(§3.13).

**Verdict: Change (AP side only).** Execute A17 in code before Band L: `ALTER TABLE plan
ADD price_cents, currency, display_name, description`; drop `credit_price` +
`src/control/credit-price.ts`; reprice period-close from `purchase_proof.amount_cents`;
amend the `invoice` migration to A17's shape and add `purchase_proof_id` (or `order_id`)
so invoice → proof → order is navigable in data (see F5). ABO changes: none — it was
designed assuming this happens. If Band L starts first, `GET /v1/plans` has no price to
serve and G4 invoices contradict the subscription model.

### 3.2 F2 — `orders` ↔ `entitlement`: mirrored plan/period/status — **MEDIUM**

**Description.** `orders` mirrors `plan`, `period_start`, `period_end`, and a lifecycle
status of the same installation the AP `entitlement` tracks. This is the deliberate
two-record split (02 §4.1.1): `orders` is the payment record, `entitlement` is the
enforcement record. Drift between them is detected by the billing-reconciliation cron
(02 §11.3 direction 1).

**Verdict: Keep.** Do not collapse the split or add runtime reads across the boundary
(couples guard latency to the ABO). Hardening: publish a canonical **order-status ×
entitlement-status coherence matrix** (e.g. `provisioned`↔`active`,
`past_due`↔`active`-in-grace, `provisioned`↔`suspended` = drift) as a shared contract
artifact consumed by both sides' tests and the reconciliation job — today it exists only
as prose (02 §6.1/§6.2). See F20.

### 3.3 F3 — `orders` mirrors installation identity — **MEDIUM**

**Description.** `orders` carries `installation_id`, `kid`, `public_key`, `org_id`,
`display_name`, `region` (02 §4.1.2) — a point-in-time snapshot of AP's
`installation`/`installation_key` rows, taken at order creation. Two problems: (a) silent
staleness — clinic key rotation or org rename never propagates, and every renewal proof
re-carries the *original* key material (02 §5.7); the key-rotation-vs-order story is
unspecified; (b) self-redundancy — `org_id`/`display_name`/`region` are parsed copies of
fields already inside the stored `order_payload` bytes on the same row.

**Verdict: Keep the snapshot, change the details.** The pre-enroll copy is necessary
(proof-of-possession binding before the platform knows the clinic). Actions: (a) document
the identity columns as an *as-purchased snapshot*, not a registry mirror; (b) define the
rotation story — either re-validate key material against the platform at renewal-checkout
time, or require a fresh order after rotation; (c) drop the parsed
`org_id`/`display_name`/`region` columns and read them from `order_payload` at
orchestration time — cheap, removes a drift point.

### 3.4 F4 — Purchase proof stored on both sides — **LOW**

**Description.** ABO `purchase_proofs` is the minting ledger (retry + audit); AP
`purchase_proof` is the consumption log / replay guard, inserted in the same D1 batch as
the grant. Same `purchase_proof_id`, `order_id`, `installation_id`, `kind`,
`period_start/end` on both sides (02 §4.1.6, §4.2).

**Verdict: Keep the AP copy; reconsider the ABO copy.** The AP consumption log is
load-bearing — "a guard that lives in the caller's database is no guard at all". But the
ABO table's stated *retry* justification is redundant: the outbox `payload` already embeds
the JWS (02:L655, L751). Either drop ABO `purchase_proofs` (−1 table) or re-justify it
solely as the audit/minting ledger. See §4, Candidate 5.

### 3.5 F5 — The paid-amount chain: four stores — **MEDIUM**

**Description.** "What installation I paid for period P" is copied through: ABO `orders` →
ABO `purchase_proofs.jws` claims (`amount_cents`/`currency`) → AP `purchase_proof` row →
AP `invoice`. Each copy has a distinct job (payment record / signed transport / replay
guard + pricing evidence / invoice document); the rationale — invoice priced from what was
paid, never a catalogue re-lookup (A17 item 3) — is correct. However, the current
`invoice` schema has no `purchase_proof_id`/`order_id`, so the traceability chain is not
navigable in data; and the ABO doc claims `amount_cents`/`currency` are stored on the
platform `purchase_proof` row (02:L1159) while the DDL shown has no such columns (§6,
item 7).

**Verdict: Keep the chain, fix the gaps.** Add `purchase_proof_id` (or `order_id`) to
`invoice` in the A17 amendment pass (F1); reconcile the `purchase_proof` DDL with §5.7's
claim. Do not pursue the alternative de-dup (drop AP `invoice`, serve invoice reads from
ABO order history) — it reverses A15 and couples clinic-facing reads to the ABO.

### 3.6 F6 — `ops_operator`/`ops_jti` vs `control_operator`/`control_cat_jti` — **LOW-MEDIUM**

**Description.** Schema-identical tables (same columns, same CAT-structured tokens, same
insert-if-absent `jti` rule) in two D1s: ABO's `ops_operator`/`ops_jti` for its `/v1/ops/*`
surface, AP's `control_operator`/`control_cat_jti` for `/control/*` (Band L). A human who
both issues comp orders and does platform break-glass needs their public key registered in
both.

**Verdict: Keep both tables** — the trust-boundary separation is the point; do not share a
table across D1s. Mitigate the identity-config drift: (a) share the verification *code*
via the planned `packages/ed25519-jws/` (F21); (b) one provisioning script/runbook that
writes an operator into both registries atomically.

### 3.7 F7 — Replay/idempotency store proliferation — **LOW**

**Description.** Seven single-use/idempotency stores, one invariant: AP
`control_cat_jti` + `purchase_proof` (Band L), `ai_request.idempotency_key`,
`grace_admission_queue` UNIQUE, AAT `jti` in the Quota DO; ABO `webhook_events`
UNIQUE(provider, provider_event_id), `ops_jti`, `poll_token_hash`. The co-location rule
(02 §5.1) puts each guard in the same D1 batch / DO stub as the action it protects.

**Verdict: Keep.** Co-location is what makes the guards atomic with the action. De-dup
limited to a shared "insert-if-absent + purge cron" helper.

### 3.8 F8 — `outbox` vs `grace_admission_queue`: same table-as-queue mechanism — **LOW**

**Description.** AP `grace_admission_queue` (with its reconcile cron) and ABO `outbox`
(with its Cloudflare Queue delivery) are the same pattern: a D1 row as the durable job
ledger with bounded retries. Different payloads, different delivery mechanisms.

**Verdict: Keep both tables.** Extract a shared outbox-ledger helper into a workspace
package when L4/L5 land.

### 3.9 F9 — `order_id` / `purchase_proof_id` on AP `entitlement` — **LOW**

**Description.** Planned (02 §4.2; not yet in code — `schema.snap.sql` has neither
column). The same two UUIDs live in ABO `orders.order_id` / `orders.purchase_proof_id` /
`purchase_proofs` PK. They are the join keys reconciliation directions 1–2 depend on and
the replay-defense anchors (UNIQUE partial index).

**Verdict: Keep.** Implement as designed in Band L.

### 3.10 F10 — `control_audit.order_id` — **LOW**

**Description.** Planned (02 §4.2). Duplicates the ABO order fact into AP's audit log so
"every grant traces to a payment" and reconciliation direction 2 can page `control_audit`.

**Verdict: Keep.** It is the anti-insider-tampering control.

### 3.11 F11 — Period bounds copied ~6× down the chain — **LOW**

**Description.** `orders.period_start/end` → `purchase_proofs.period_start/end` → proof
JWS claims → AP `purchase_proof.period_start/end` → `entitlement.period_start/end` →
receipt `period_end`/`valid_until` → clinic `ai.availability.valid_until`.

**Verdict: Keep.** This is the irreducible cost of a pull-based, offline-tolerant chain:
every hop is single-use (proof), short-lived (receipt 15-min `exp`), self-expiring (clinic
flag), or reconciled (§11.3). No structural change.

### 3.12 F12 — Plan name as a shared key in 5 places — **LOW**

**Description.** `orders.plan` ↔ proof claim `plan` ↔ `entitlement.plan` ↔ (post-A17)
`invoice.plan` ↔ `capability_grant.scope = 'plan:{tier}'`. The grant-scope embedding means
a plan *rename* is really a migration across grants.

**Verdict: Keep.** Add a note in the plan-retirement runbook: rename = migration across
grants (02 §6.6 covers retirement, not rename).

### 3.13 F13 — The 7-day grace constant is hardcoded on both sides — **MEDIUM**

**Description.** ABO's order clock computes `grace_until = period_end + 7d`, renewal lead
`period_end − 7d`, tail `+37d` (02 §6.3, §11.1). AP's receipt minting computes
`valid_until = period_end + grace` (02 §5.8; delivery plan L3). The doc claims the two
"agree by construction" — but the construction is two deployables independently
hardcoding `7`. Drift means the clinic UI goes dark while the guard still admits (or the
reverse), silently.

**Verdict: Change.** Single-source it: put `grace_days` on the `plan` catalogue row /
`GET /v1/plans` payload; ABO's order clock reads it from the catalogue fetch it already
makes. Zero new endpoints, and it makes grace per-plan later if desired. Fallbacks:
shared constant in a workspace package + contract test; minimum: coordinated-change note
in both runbooks.

### 3.14 F14 — Four cross-deploy config pairs that must be kept equal — **MEDIUM**

**Description.**

| Pair | AP side | ABO side |
|---|---|---|
| Purchase-proof key | `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` var (key set with validity windows) | `BILLING_PURCHASE_PROOF_PRIVATE_KEY` secret + active-`kid` var |
| CAT key | `control_operator` row (`key_id`, `public_key`, `allowed_actions`) | `ORCHESTRATOR_CAT_PRIVATE_KEY` secret + key-id var |
| Issuer id | `BILLING_ISSUER` var | `iss` claim constant |
| Receipt keys | `PLATFORM_RECEIPT_PUBLIC_KEYS` var → `GET /v1/platform-keys` | clinic `app_settings` copy (distributed by design, self-healing) |

Rotation is a manual multi-step dance across two deploys (02 §3.3). The `kid` namespacing
(02 §3.2) already prevents cross-domain resolution — good.

**Verdict: Keep the distribution (inherent to two deployables), change the process.** A
single rotation script performing both sides in one operation; plus a boot-time self-check
where ABO verifies its active `kid`/issuer against an authenticated platform read
(fail-fast on mismatch).

### 3.15 F15 — Plan catalogue: one source, two caches — **LOW**

**Description.** AP `plan` table (source) → ABO cached server-side fetch (300 s, 02
§4.1.7) → Flutter client cache (02 §5.10). Failure modes handled (`502
catalogue_unavailable`, never reprice open periods).

**Verdict: Keep.** By design; recorded for completeness.

### 3.16 F16 — Provider config vs platform config — **LOW (non-finding)**

**Description.** `PAYMOB_*` exists only on ABO; provider ids quarantined in
`provider_refs` and never cross the adapter boundary (contract-test-pinned). AP has zero
provider-payment config.

**Verdict: Keep.** The quarantine works; no duplication.

### 3.17 F17 — "Plan exists and is active" validated twice — **MEDIUM-LOW**

**Description.** ABO validates at four call sites (create order, renewal-checkout, comp
orders, order-clock pre-issue) against the cached catalogue; AP re-validates at
enroll/entitle/renew against the catalogue directly. Same rule, two implementations —
inherent to defense in depth at a trust boundary. The drift failure mode is named in the
doc ("paid order wedges at `enroll`", 02 §4.1.7).

**Verdict: Keep both validations.** Add a contract test pinning that `GET /v1/plans`
serves *exactly* `status='active'` rows, keeping the two rule-copies provably equivalent.

### 3.18 F18 — Period computation — **LOW**

**Description.** All period math lives in ABO (02 §6.4); AP applies proof bounds verbatim;
the Quota DO resets counters on bound change without recomputing. No quota math crosses
the boundary — the proof carries plan *name* only, economics resolve from the catalogue
(correctly tightened from the proposal's looser "quotas from the proof").

**Verdict: Keep.** Already single-writer.

### 3.19 F19 — Two "reconciliation" jobs — **LOW**

**Description.** ABO's billing reconciliation deliberately re-derives AP entitlement state
via `quota-inspect` + `control_audit` paging — independent re-derivation is its job
(insider-tampering control). The name collides with AP's usage-side
`runRollupAndReconciliation`; the doc already renames it "billing reconciliation" (02
§11.3).

**Verdict: Keep both; keep the rename.**

### 3.20 F20 — Order machine ↔ entitlement machine coherence — **MEDIUM**

**Description.** 8-state order machine (02 §6.1) vs 3-state entitlement machine (02 §6.2),
synchronized only via outbox + 409-mappings + daily reconciliation. E.g. `past_due` ↔
`active`-in-grace is a *coherent* divergence; `paid` ↔ `pending` is transient;
`provisioned` ↔ `suspended` is drift. The mapping exists only as prose.

**Verdict: Keep the machines, change the artifact.** Publish the coherence matrix as a
shared contract artifact both sides' tests and the reconciliation job consume (same action
as F2).

### 3.21 F21 — Ed25519 JWS verify/sign logic in 3+ places — **MEDIUM until L1**

**Description.** AP has `EnrolledKeyVerifier` (`src/identity/index.ts`) and will add CAT +
purchase-proof verifiers; ABO needs PoP verify, proof minting, ops-token verify,
poll-token compare. The doc calls three near-identical verifiers "a defect, not a pattern"
and prescribes `packages/ed25519-jws/` (02 §2.2, deviation 12) — not yet implemented.
Delivery plan L1 already sequences the extraction first.

**Verdict: Change (as already planned).** Build the shared package first in Band L. Just
execute it.

### 3.22 F22 — Triplicated uniqueness invariants — **LOW**

**Description.** One-live-order-per-installation (ABO partial unique index) ↔
one-entitlement-per-installation (migration `20260821130000`) ↔ `entitlement.order_id`
UNIQUE (Band L). Three constraints on one 1:1:1 relation across two D1s.

**Verdict: Keep all three.** Defense in depth: each catches a different attack
(double-sell, double-grant, payment replay).

### 3.23 F23 — Receipt → clinic flag — **LOW**

**Description.** The chain ABO `orders` → AP `entitlement` → receipt claims → clinic
`ai.availability` has exactly one intermediate copy per trust boundary, each with an
expiry. The clinic never talks to ABO; the status endpoint reads from the config cache;
the flag self-expires. Minor note: receipt `plan` is display-only (02 §5.8) and can lag
`entitlement.plan` between a renewal and the next status poll.

**Verdict: Keep.** This *is* the de-duplicated design. Caveat: clinic UI must not treat
receipt `plan` as authoritative.

### 3.24 F24 — `platform_base_url` in three places — **LOW**

**Description.** Flutter constant, ABO worker config (orchestrator's control client),
clinic `app_settings` (via receipt claim, 02 §5.8). One logical config distributed to each
consumer; the receipt-carried copy is self-healing.

**Verdict: Keep.**

### 3.25 Unnamed configuration in the ABO design (gap, not duplication)

**Description.** The design never names: the ABO→platform base URL var (control client +
catalogue fetch), the ABO's own public origin (used in Paymob `notification_url`), or the
catalogue-cache storage mechanism (in-memory per isolate vs Cache API).

**Verdict: Change.** Name them in the design phase.

## 4. Constitution Deviation Analysis

The governing clause is the Operating Constraints amendment (`constitution.md:96-105`): a
*single* vendor-side control service, no clinic business data, no write path into clinic
Supabase, outbox ledger + a managed Cloudflare Queue for delivery, and "the AI platform stays
additive and never learns about money."

### 4.1 Candidate 1 — Merge ABO into the AP Worker

**Description.** One deployable, one D1, one secret store instead of two. Gain: −1
deployable, −1 `wrangler.toml`, −1 CI pipeline, −3 environments; the orchestrator→platform
HTTP hop with per-call CAT minting collapses to a function call; the two purchase-proof
stores could become one table. Principle I ("no microservices") arguably favors merging,
so only a MINOR amendment is needed textually.

**Verdict: Keep the constitution — do not merge.** Cloudflare secrets are per-Worker: in
one Worker, `BILLING_PURCHASE_PROOF_PRIVATE_KEY` and `ORCHESTRATOR_CAT_PRIVATE_KEY` share
one secret store, one set of CI credentials, one IAM path. Two attack rows in the
traceability matrix become false ("orchestrator compromised → cannot grant"; "billing
compromised → cannot write to the platform"). Separate modules inside one isolate are
convention, not custody. The two-signature rule — the one invariant the entire anti-bypass
analysis reduces to — survives only as security theater. The saving is real but small at
clinic scale (a few orders/day).

### 4.2 Candidate 2 — Let AP learn about money

**Description.** The clause is already factually eroded: AP will store `order_id`/
`purchase_proof_id` on `entitlement` (Band L), store billing-signed `amount_cents`/
`currency` on `purchase_proof` rows, and **issues invoices priced from the paid amount**
(A17 item 3; `invoice` table). A service that persists amounts paid and mints invoice
documents "learns about money" by any plain reading. The operative boundary that actually
remains: no payment collection, no provider integration, no money in the request path
(A16 item 6). Full embrace (AP absorbs collection; ABO deleted) would be the largest
single gain available: −1 deployable, −4 tables, −1 cron, reconciliation directions 1–2
collapse to SQL joins — but it kills the two-signature grant rule entirely, puts money in
the request-path Worker's blast radius, and is a MAJOR amendment rewriting A15/A16.

**Verdict: Amend the wording (PATCH); full embrace not now.** Replace "never learns about
money" with *"never collects payments and holds no payment-provider integration; it
records paid amounts solely as billing-attested claims for invoicing."* Revisit full
embrace only if the ABO's operational burden proves real in production.

### 4.3 Candidate 3 — Outbox delivery: queue vs direct invocation

**Description.** The outbox row is the durable ledger; delivery runs through a managed
Cloudflare Queue (`outbox-events`, consumer = the ABO Worker, `outbox-dlq` dead-letter).
Pure direct invocation was rejected: it would drop the table but make "money received
always eventually provisions or alerts" unenforceable (dropped isolate = paid but never
provisioned). The queue adds no operated infrastructure — Cloudflare manages the broker —
and removes the hand-rolled retry/backoff/sweeper code at a volume of a few messages/day.

**Verdict: Adopt the queue.** Managed retries and dead-lettering beat a hand-rolled
sweeper; the outbox table stays as the minting ledger and audit record.

### 4.4 Candidate 4 — Single shared D1 for billing + platform

**Description.** The two-key trust chain lives in *secrets*, not D1; two Workers could
share one D1 without weakening any cryptographic property, and the constitution does not
mandate separate D1s (separation is a design choice, 01-proposal §3). Gain: reconciliation
directions 1–2 become SQL joins or disappear; the double purchase-proof storage collapses;
the cross-service audit-paging read is never needed. Cost: loses independent-ledger tamper
evidence — today an insider rewriting platform D1 to mint free entitlements is caught by
reconciliation against a *different* database; one D1 = tamper once, undetected (only the
provider-payout direction survives). Also couples migration cadence and availability of
the two schemas.

**Verdict: Keep separate D1s; no amendment needed either way.** Honest caveat the design
itself records (02 §13 item 4): with a single operator holding both services' credentials,
separation currently defends against credential/CI leakage, not against the operator —
still worth keeping, but it tempers the tamper-evidence argument.

### 4.5 Candidate 5 — ABO minimal state

**Description.** Already near-minimal (no plan/price/entitlement/usage tables). One
concrete de-dup: §4.1.6 justifies `purchase_proofs` so "outbox retries re-present the
identical JWS" — but the outbox `payload` already embeds the JWS (02:L655, L751). The
retry justification is redundant; the table's real residual job is the minting ledger for
audit, which persisted `outbox.payload` rows could serve.

**Verdict: Simplify the design; no amendment.** Drop `purchase_proofs` (−1 table) or
rewrite §4.1.6's justification to rest solely on the audit-ledger role. (Same action as
F4.)

### 4.6 Candidate 6 — Remove the break-glass bearer

**Description.** Human operators already hold personal CAT keys scoped to
suspend/resume/rotate — covering every break-glass action. The doc's stated rationale
("orchestrator as single point of failure for incident response", 02 §13 item 3) is
answered by human CAT keys; the orchestrator is never on the human incident path. Removing
the bearer: −1 auth factory, −1 secret, −1 action set, −1 composite wiring, and the
`OPERATOR_BEARER_TOKEN` attack surface (a shared, non-attributed credential — the exact
anti-pattern 02 §11.2 condemns for ABO ops) disappears. The only genuine residual
justification is *auth-system failure* recovery (corrupted `control_operator` table / all
keys lost) — answerable via `wrangler d1` insert of a new operator row under account IAM,
the same bootstrap ABO already uses for `ops_operator`.

**Verdict: Lean remove; needs more design.** Either delete the bearer and document
D1-level recovery, or keep it but rewrite the rationale to the auth-failure argument. No
amendment required.

### 4.7 Candidate 7 — Drop the billing reconciliation job

**Description.** Would remove 1 cron. But the two-signature rule only governs the API
path; D1 insider tampering bypasses it, and §11.3 is the sole after-the-fact control.

**Verdict: Keep the design.** Rejected.

### 4.8 Where the current design already strains the constitution

1. **"Never learns about money" is factually false as designed** — see Candidate 2.
   Recommend the PATCH rewording.
2. **Stale schema vs A17:** `schema.snap.sql` still contains `credit_price` and
   `invoice.credit_price_version` though A17 withdrew `credit_price` "before Band G
   completes". The repo's source of truth currently contradicts a ratified amendment.
3. **Two vendor Workers vs the "no microservices" narrative:** compliant via the
   amendment, but the constitution's simplicity narrative and its vendor-side reality are
   drifting apart. The next vendor-side need (each requires its own amendment per the
   clause) should force an explicit "vendor control plane" principle instead of
   per-service amendments.
4. **Break-glass bearer** retains a shared, unattributed credential inside a design that
   elsewhere calls exactly that an anti-pattern — a strain against Principle IV's
   auditability spirit, though within the amendment's letter.

### 4.9 Deviation verdict summary

| # | Deviation | Clause | Net gain | Verdict |
|---|---|---|---|---|
| 1 | Merge ABO into AP Worker | Principle I / vendor amendment | −1 deployable, −1 trust hop; destroys two-key custody | **Keep constitution** |
| 2 | AP learns about money | "never learns about money" | Wording: honesty. Full: −1 deployable, −4 tables, −1 job; kills two-signature rule | **Amend wording (PATCH); full embrace: not now** |
| 3 | Queue or pure in-process handoff | "no queues" / outbox clause | Managed retries + DLQ, no sweeper code; pure in-process loses durability | **Adopt managed queue; keep outbox ledger** |
| 4 | Shared D1 | None textual | −1 proof copy, simpler reconciliation; loses tamper evidence | **Keep design; no amendment** |
| 5 | ABO minimal state | None | −1 table (`purchase_proofs`) | **Simplify design; no amendment** |
| 6 | Remove break-glass bearer | None (Principle IV spirit) | −1 factory/secret/action-set; one identity mechanism | **Lean remove; needs more design** |
| 7 | Drop reconciliation | None | −1 cron; loses only insider control | **Keep design** |

## 5. Prioritized Recommendations

Ordered by leverage. Items 1–3 are prerequisites for Band L; items 4–8 are design-phase
hardening; items 9–10 are constitution hygiene.

1. **Execute A17 in code before Band L (F1).** Add `price_cents`/`currency`/
   `display_name`/`description` to `plan`; drop `credit_price` + `src/control/credit-price.ts`;
   reprice `src/period-close/` from `purchase_proof.amount_cents`; amend the `invoice`
   migration to A17's shape **and add `purchase_proof_id`/`order_id`** so
   invoice → proof → order is navigable (F5). ABO changes: none — it was designed assuming
   this happens.
2. **Single-source the grace constant (F13).** Put `grace_days` on the plan catalogue /
   `GET /v1/plans` payload; ABO's order clock reads it from the fetch it already makes.
3. **Build `packages/ed25519-jws/` first (F21, delivery plan L1).** Three near-identical
   verifiers are "a defect, not a pattern".
4. **Publish the order-status × entitlement-status coherence matrix (F2/F20)** as a shared
   contract artifact consumed by both sides' tests and the reconciliation job.
5. **Fix the `orders` identity snapshot (F3):** document as as-purchased snapshot; define
   the key-rotation story (re-validate at renewal-checkout, or fresh order after
   rotation); drop the parsed `org_id`/`display_name`/`region` columns in favor of reading
   the stored `order_payload`.
6. **Drop or re-justify ABO `purchase_proofs` (F4 / Candidate 5):** the retry
   justification is redundant with `outbox.payload`; keep only if the audit-ledger role is
   deemed worth a table.
7. **One operator-provisioning script + one key-rotation script spanning both deploys
   (F6/F14),** plus a boot-time self-check where ABO verifies its active `kid`/issuer
   against an authenticated platform read.
8. **Resolve the break-glass bearer (Candidate 6):** lean remove, with documented
   D1-level recovery; otherwise rewrite the rationale to the auth-failure argument.
9. **Amend the constitution wording (Candidate 2, PATCH):** "never learns about money" →
   "never collects payments and holds no payment-provider integration; it records paid
   amounts solely as billing-attested claims for invoicing."
10. **Name the unnamed ABO config (§3.25):** platform base URL var, ABO public origin var,
    catalogue-cache storage mechanism.

**Explicitly rejected:** merging the two Workers (Candidate 1), sharing one D1
(Candidate 4), replacing outbox+cron (Candidate 3), dropping reconciliation
(Candidate 7). Each spends independent key custody or tamper evidence for savings that
clinic-scale volume does not justify.

## 6. Appendix: Design-Doc Inconsistencies Found

Issues in `02-architecture-toc.md` itself, flagged for the design phase (not redundancies):

1. **"Nine tables" (L522) vs eight enumerated** (§4.1.2–§4.1.9) — the ninth is never named.
2. **`outbox.kind`** column table lists only `provision` (L750), but the text requires
   `entitlement_suspend` rows (L636, L1309); full enum never given.
3. **`purchase_proofs.kind`** lists only `purchase` (L776), yet §6.4/§6.5 mint `renewal`
   and `comp`; the platform-side table documents all three (L883).
4. **`webhook_events.status`** lists only `processed` (L724) — no enum for failed/pending
   despite retry semantics (L1083).
5. **`provider_refs.kind`** lists only `checkout` (L702), though settlements/inquiry flows
   reference intention/order refs (L1516).
6. **`reconciliation_alert.kind`** lists only `entitlement_without_payment` (L811); §11.3
   defines three kinds.
7. **Amount columns missing:** §5.7 (L1159) says `amount_cents`/`currency` are stored on
   the platform `purchase_proof` row, but the DDL (L877–888) has no such columns; the ABO
   `purchase_proofs` table also lacks them (amounts exist only inside the JWS), and
   `orders` has no amount/currency column — the ABO's own order record cannot
   independently restate what was charged.
8. **Doc drift on the AP side (docs 16/18 predate the 2026-09-11 commercial migrations):**
   doc 16 covers only 14 of 17 tables (missing `plan`, `credit_price`, `invoice`), lists
   `entitlement` at 11 columns (code has 13), and omits `usage_rollup.quota_weight`;
   doc 18 omits `creditsUsed`/`credit_budget` in the DO state and its "token/cost ceiling
   enforcement" claim no longer matches `isQuotaExhausted` (admission enforces only
   request quota + credit budget). `schema.snap.sql` is current.
9. **`POST /control/plans/{name}/delete` writes only `control_audit`** — the batch
   contains no `DELETE FROM plan` (`src/control/plan.ts:281-287`); the plan row is never
   removed.
