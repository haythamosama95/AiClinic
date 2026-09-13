# AI Billing Orchestration — Delivery Plan

- Purpose: Decompose the AI billing orchestration architecture into small, individually specifiable, individually implementable slices across the four codebases it touches (`ai-platform/`, `ai-billing-orchestrator/`, `backend/`, `frontend/`), and define the rules that keep those slices from drifting away from the architecture. This plan **replaces Band L** of the AI platform delivery plan.
- Read this when: choosing what to build next on the AI Billing Orchestrator introduction, opening a new Spec Kit feature for ABO-related work in any of the four codebases, or reviewing a completed ABO slice.
- Canonical for: the ABO-introduction build order, slice boundaries, slice completion criteria, and the authoring rules for ABO feature specs.
- Usually paired with: `docs/architecture/ai-billing-orchestration/02-architecture.md` (the architecture this plan sequences, cited as **ABO** below), `docs/architecture/ai-billing-orchestration/01-proposal.md` (agreed decisions), `docs/architecture/ai-platform/01-ai-platform.md` (amendments A15 §2.6, A16 §2.10, A17 §2.11 — the platform-side canonical anchors, cited as **AP-ARCH**), `docs/architecture/ai-platform/03-ai-platform-delivery-plan.md` (the platform plan whose format and governance this plan adopts, cited as the **AP plan**), `03-ap-abo-deduplication-analysis.md` (the analysis that shaped the band decomposition), and `.specify/memory/constitution.md`.
- Not covered here: any architectural decision. This document sequences decisions made in `02-architecture.md` and AP-ARCH A15–A17; it never makes new ones. Where the two appear to conflict, `02-architecture.md` wins and this document is wrong.

> **Status:** Delivery plan. Bands M–U are sliced; together they supersede Band L of the AP plan
> (§3.15 there), which was written before the ABO design stabilized. Section references of the form
> §N.M refer to `02-architecture.md` unless stated otherwise; references of the form A15/A16/A17 or
> "AP-ARCH §N.M" refer to `docs/architecture/ai-platform/01-ai-platform.md`.

---

## Table of Contents

1. [Purpose and Operating Assumptions](#1-purpose-and-operating-assumptions)
2. [What a Slice Is](#2-what-a-slice-is)
3. [The Slice Sequence](#3-the-slice-sequence)
   - [Master end-to-end verification chain](#313-master-end-to-end-verification-chain)
4. [Review Checkpoints](#4-review-checkpoints)
5. [Spec Authoring Protocol](#5-spec-authoring-protocol)
6. [Constitution Compliance Check](#6-constitution-compliance-check)
7. [Dependencies Outside This Plan](#7-dependencies-outside-this-plan)
8. [Implementation Status](#8-implementation-status)

---

## 1. Purpose and Operating Assumptions

### 1.1 Why this document exists separately

The AP plan's Band L sliced the ABO introduction when the ABO architecture was still moving. The
design has since stabilized with revisions that invalidate Band L's foundations — the break-glass
bearer is removed entirely, the ABO `purchase_proofs` table is dropped, `grace_days` is
single-sourced in the plan catalogue, and `orders` is slimmed to an as-purchased snapshot. Rather
than patch stale slices, the ABO introduction is re-planned here, against the current architecture,
as bands M–U.

A separate document is also warranted on scope grounds: this introduction spans four codebases and
two deployables that do not yet exist, while the AP plan sequences one deployable. Keeping the
volatile sequencing document close to the architecture it sequences follows the same rule the AP
plan states in its §1.1.

### 1.2 Operating assumptions

The four assumptions of the AP plan (§1.2 there) hold unchanged and are adopted by reference:
nothing is sold or deployed until the whole chain is complete; specs are authored by transcription,
not design; implementation follows the spec literally, so contracts are frozen as code before their
consumers; and one human's review capacity is the binding constraint. Two consequences are worth
restating for this plan:

1. No slice needs to be demoable. In particular, the platform-side bands (M, N, O, P) are allowed
   to land with no clinic ever calling them — their consumers are built in bands Q, R, S, T.
2. A slice is complete when an automated test proves it (AP plan DP-3). For this plan that includes
   the cross-deployable contract artifacts: the §6.7 coherence matrix, the §4.1.6 catalogue contract
   test, and the §7.1 provider-quarantine contract test are *executable* artifacts consumed by both
   sides' suites, not prose.

### 1.3 Decisions this plan records

| #     | Decision                                                                                                                                                                          | Rationale                                                                                                                                                                                                                                                                                                                                                         |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DP-L1 | **Band L of the AP plan is superseded; this plan replaces it.** L1–L8 are never started; their intended scope is re-decomposed as bands M–U                                       | Band L assumed the break-glass bearer, the ABO `purchase_proofs` table, hardcoded 7-day grace, and unslimmed `orders`. All four premises were revised out of the architecture on 2026-09-13 (§8.1/§13 item 3; §4.1.5; §4.1.6/§6.3; §4.1.2)                                                                                                                          |
| DP-L2 | **A slice is still one Spec Kit feature — one `specs/<NNN>-<name>/` directory, one branch, one review — but its code may live in any of the four codebases**                       | The introduction is one logical effort; splitting it into four independent plans would hide the cross-codebase dependencies (e.g. T needs Q + S) that most need review discipline                                                                                                                                                                                    |
| DP-L3 | **A17 economics execution (Band M) is pulled ahead of everything else**                                                                                                           | The dedup analysis (§3.1, finding F1) rates the live `credit_price` code the one HIGH-severity finding: A17 is ratified but unexecuted, and every later band reads the catalogue or the invoice shape. Finishing `credit_price` as written and then ripping it out would be waste                                                                                      |
| DP-L4 | **The shared `packages/ed25519-jws/` extraction is the first slice of Band N and precedes any new verifier**                                                                       | Three near-identical JWS verifiers in one repository is a defect, not a pattern (§2.2, deviation 12; dedup analysis F21). The CAT verifier, the purchase-proof verifier, and the ABO-side PoP/proof/ops-token code all consume the package                                                                                                                            |
| DP-L5 | **The constitution amendment precedes the first ABO slice — and is already satisfied**                                                                                             | The Operating Constraints amendment registering `ai-billing-orchestrator/` is in `.specify/memory/constitution.md` (registered 2026-09-11). Per the AP plan's §7 rule, the first slice of a new deployable must not itself be architectural drift; that gate is met before Q1 opens                                                                                    |
| DP-L6 | **Renewal-checkout and the order clock are sliced together in Band R, not with the purchase module**                                                                              | Both renewal-checkout (§5.4) and the order clock's pre-issued checkouts (§11.1) must re-validate the order's key material against the platform through an orchestrator-scoped CAT read before calling the adapter. Grouping both checkout-issuance paths in one band keeps the CAT minter's consumers in one review and avoids a purchase→orchestrator dependency inversion |

---

## 2. What a Slice Is

The AP plan's §2 is adopted by reference: the definition (§2.1), the completion criterion (§2.2),
the no-rework rule (§2.3), the mandatory exclusions list (§2.4), and the sizing guidance (§2.5) all
apply unchanged, with three deltas:

1. **Canonical sources are two documents.** A slice's `Canonical` column cites sections of
   `02-architecture.md` and, for platform-side slices, the AP-ARCH amendments (A15 §2.6, A16 §2.10,
   A17 §2.11) and the AP-ARCH sections they modify. A slice that cannot be answered entirely from
   those two documents is mis-scoped (§5.3 stop conditions).
2. **The no-rework rule applies across the deployable boundary.** A later ABO slice may extend a
   frozen platform contract; it may never rewrite one. A discovered defect in a frozen contract is
   an architecture amendment (to `02-architecture.md` or AP-ARCH, whichever owns it), reviewed on
   its own.
3. **Each slice names its codebase** in its row's `Slice` column when it is not obvious from the
   band.

---

## 3. The Slice Sequence

### 3.1 How to read the tables

`Canonical` names the sections of `02-architecture.md` (and AP-ARCH) a slice implements; these are
the sections the spec must cite and the reviewer must check against. `Needs` lists prerequisite
slices. `Done when` states the acceptance shape — the spec expands each into named test cases
(§3.12).

The dependency spine is: **M → P → Q → R → S → T → U**, with **N** parallel to M and required by O,
and **O** (needs M + N) required by R. Explicitly:

- **Band M** (A17 economics) needs only Band G's in-flight code. Everything commercial reads what M
  produces.
- **Band N** (caller identity) is independent of M and may run in parallel with it.
- **Band O** (gated grants) needs M2 (the `purchase_proof` table and invoice shape) and N2 (CAT
  auth is the caller identity every grant checks first).
- **Band P** (receipt + read surface) needs M1 (`grace_days` and price columns exist) and N1 (the
  shared JWS package signs receipts).
- **Band Q** (ABO purchase module) needs P2 — the ABO holds no plan table, so `POST /v1/orders`
  cannot validate or price anything until `GET /v1/plans` serves price and `grace_days` (§4.1.6).
- **Band R** (ABO orchestrator module) needs O (the platform grant paths it drives) and Q (the
  orders/outbox schema and the paid-order producers).
- **Band S** (clinic Supabase) needs P1 (the receipt contract and `GET /v1/platform-keys` it
  verifies against).
- **Band T** (Flutter) needs Q (the orders API) and S (the signing and activation RPCs).
- **Band U** (docs, probes, viewer) is last: it documents and drives what exists.

### 3.2 Band M — A17 economics execution (finishing Band G)

**What this band does:** Executes amendment A17 (AP-ARCH §2.11) in code, finishing what Band G
started: the `plan` catalogue gains the subscription price, display copy, and `grace_days` by
forward-only migration; `credit_price` is withdrawn (table, control endpoint, and
`src/control/credit-price.ts`); period close is repriced from the consumed purchase proof's
`amount_cents` / `currency` (A17 item 3, §5.7); the `invoice` migration is reshaped to the A17
form (`plan`, `amount`, `currency`, credits as evidence, `purchase_proof_id`) so the chain
invoice → proof → order is navigable in data (§4.2, §6.4); spec 059 is superseded; the
plan-delete bug is fixed; and the data-journey docs 16/18 drift is repaired.

**Useful to know:** This band is sequenced first (DP-L3): the dedup analysis (§3.1, F1) rates the
live `credit_price` code the one HIGH-severity finding, and bands P, Q, and U all read what M
produces. M1 and M2 are sequential; M3 may proceed in parallel once M1 lands. **Judgment call
(recorded per §2):** the platform `purchase_proof` *table* migration lands in M2, not Band O —
period close must read the table, and §4.2 groups the invoice linkage with the A17 amendment pass.
Band O owns the *consumption writes* (the batch-atomic insert on `entitle` / `renew` / `override`)
and the `entitlement` / `control_audit` columns. Until Band O lands, no purchase proof can be
consumed, so period close issues no invoices — which is already the A17 rule for a period with no
paid grant.

**Code sync (verified against `ai-platform/` as of 2026-09-13):**
- `migrations/20260911120000_plan_catalogue.sql` creates `plan` **without** price, display, or
  `grace_days` columns, and creates `credit_price`; `migrations/20260911200000_invoice.sql` has the
  pre-A17 shape (`credit_price_version`, `total`) and no `purchase_proof_id`.
- `src/control/credit-price.ts` and its route registration in `src/control/index.ts` are live;
  `CreditPriceActivatePayload` is in `src/control/types.ts`; `src/period-close/index.ts` prices
  invoices as `credits × price_per_credit`.
- `src/control/plan.ts:281-287` — the delete handler's D1 batch contains only the `control_audit`
  INSERT; the `plan` row is never deleted (dedup analysis §6 item 9).
- `specs/059-billing-period-close/spec.md` (FR-023..025) is built on `credit_price` versioning and
  is moot under A17.
- `docs/architecture/ai-platform/data-journey/16-complete-d1-column-reference.md` covers only 14 of
  17 tables (missing `plan`, `credit_price`, `invoice`) and lists `entitlement` at 11 columns;
  `18-quota-durable-object-state-reference.md` omits `creditsUsed` / `credit_budget` and its
  enforcement claims predate `isQuotaExhausted` (dedup analysis §6 item 8). `schema.snap.sql` is
  current and is the repair target.
- The `ai-platform-viewer` invoice views predate the A17 invoice shape; repairing them is Band U
  (U2), not this band.

| ID     | Slice                                                                 | Canonical                                                        | Needs | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------ | -------------------------------------------------------------------- | ---------------------------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **M1** | Catalogue price/display/`grace_days` columns, `credit_price` withdrawal, plan-delete fix | AP-ARCH A17 items 1–2, A15 item 4; ABO §4.1.6, §4.2, §5.10        | G1    | A forward-only migration adds `price_cents` / `currency` / `display_name` / `description` / `grace_days INTEGER NOT NULL DEFAULT 7` to `plan` and drops `credit_price`, pinned by a schema snapshot test; `src/control/credit-price.ts`, its route, and `CreditPriceActivatePayload` are deleted and no `credit_price` reference remains in `src/`; plan CRUD carries the new fields with the usual `control_audit` rows; `POST /control/plans/{name}/delete` actually deletes the row |
| **M2** | Period-close repricing and invoice reshape                            | AP-ARCH A17 item 3, A15 item 5; ABO §4.2, §5.7, §6.4             | M1    | The `purchase_proof` table is created per the §4.2 DDL (including `amount_cents` / `currency`); the `invoice` migration is reshaped to `plan`, `amount`, `currency`, credits consumed as usage evidence, and nullable `purchase_proof_id`; `src/period-close/index.ts` prices each invoice from the period's consumed purchase proof amount, never from a catalogue re-lookup; a re-run is idempotent; a period with no paid grant closes with no invoice; `specs/059-billing-period-close/spec.md` carries a superseded banner citing A17 and this plan, with FR-023..025 withdrawn |
| **M3** | Data-journey docs 16/18 drift repair                                  | Dedup analysis §6 item 8; ABO §4.2                                | M1    | Doc 16 covers every current table (including `plan` with its new columns and the reshaped `invoice`, excluding `credit_price`) and matches `schema.snap.sql` column-for-column; doc 18's DO state lists `creditsUsed` / `credit_budget` and its enforcement claims match `isQuotaExhausted`; a scripted diff of doc 16 against the schema snapshot runs in CI                                                                                                                |

#### 3.2.1 Band M — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| M1-V1 | unit | M1 migration applied to an empty D1 database | `plan` has `price_cents`, `currency`, `display_name`, `description`, `grace_days INTEGER NOT NULL DEFAULT 7`; `credit_price` table absent; schema snapshot test pinned and green |
| M1-V2 | unit | M1 migration applied over the existing pre-A17 catalogue (seeded `plan` rows, existing `credit_price` rows) | Existing `plan` rows preserved with `grace_days = 7` backfilled by default; `credit_price` dropped with no error; forward-only (no down migration) |
| M1-V3 | unit | Plan create carrying all new fields (price_cents=150000, currency="EGP", display_name, description, grace_days=14) | 200; row round-trips every field exactly; `control_audit` row with action `plan_create` written in the same batch |
| M1-V4 | unit | Plan create omitting `grace_days` | Row stored with `grace_days = 7` (schema default) |
| M1-V5 | unit | Plan create with explicit `grace_days = 0` | Stored as 0 — explicit value wins over default (boundary: zero-length grace is representable) |
| M1-V6 | unit | Plan create/update with negative `grace_days`, negative or non-integer `price_cents`, empty `currency`, empty `display_name` | Each → 400 `invalid_payload`; no row written; no audit row |
| M1-V7 | unit | Plan update changing only price/display/`grace_days` fields | 200; economics columns (credit_budget, request_quota, …) unchanged; `plan_update` audit row written |
| M1-V8 | unit | Plan update on unknown plan name | 404 `plan_not_found`; no audit row |
| M1-V9 | unit | `POST /control/plans/{name}/delete` on an existing plan (the G-era bug fix) | 200; `SELECT` afterwards returns no `plan` row; `plan_delete` audit row present |
| M1-V10 | unit | Plan delete on unknown plan name | 404 `plan_not_found`; no audit row written |
| M1-V11 | unit | Plan delete on a plan still referenced by existing `entitlement.plan` / `invoice.plan` rows | Delete succeeds (no FK); referencing entitlement/invoice rows untouched — retirement-by-status (§6.6) is the policy, delete is a catalogue operation |
| M1-V12 | unit | `POST /control/credit-price/activate` after M1 | 404 — route unregistered; no `credit_price` table to write to |
| M1-V13 | unit | Grep test over `ai-platform/src/` | No reference to `credit_price`, `CreditPriceActivatePayload`, or `credit-price` remains; `src/control/credit-price.ts` deleted; route registration and export removed from `src/control/index.ts` |
| M1-V14 | unit | Unauthenticated (no valid operator credential) plan create/update/delete | 401 `{"error":"unauthorized"}` on each; no rows written |
| M2-V1 | unit | M2 migration applied | `purchase_proof` table exists with the §4.2 DDL columns (`purchase_proof_id` PK, `order_id`, `installation_id`, `kind`, `period_start`, `period_end`, `amount_cents`, `currency`, `processed_at`); snapshot pinned |
| M2-V2 | unit | M2 invoice reshape migration | `invoice` carries `plan`, `amount`, `currency`, `credits_consumed` (evidence), nullable `purchase_proof_id`; `credit_price_version` and `total` columns gone; PK `(installation_id, period)` retained; snapshot pinned |
| M2-V3 | unit | Period close for an installation with a consumed proof (`amount_cents=150000`, `currency="EGP"`) covering the period | Invoice inserted with `amount = 150000`, `currency = "EGP"`, `plan` = proof's plan, `purchase_proof_id` = the proof's jti |
| M2-V4 | unit | Catalogue price changed between period 1 close and period 2 close | Period-1 invoice unchanged; period-2 invoice priced from the period-2 proof's `amount_cents` — never from a catalogue re-lookup (spy: close performs no price read from `plan`) |
| M2-V5 | unit | Period close where an active entitlement has no consumed purchase proof for the period | No invoice row for that installation (A17: no paid grant → no invoice) |
| M2-V6 | unit | Credits consumed recorded as evidence | `credits_consumed` equals the `usage_rollup` sum for the installation+period; changing the usage sum does not change `amount` |
| M2-V7 | unit | Zero-usage period with a paid grant (credits_consumed = 0) | Invoice still issued — A17 invoices the subscription, not usage; `credits_consumed = 0`, `amount` = proof amount (behavioral break from the G-era `credits × price` skip) |
| M2-V8 | unit | Comp-consumed proof (`amount_cents = 0`, `kind = comp`) covering the period | Invoice issued with `amount = 0` and the proof's currency; chain to the comp order navigable |
| M2-V9 | unit | Re-run of period close for an already-closed period | Idempotent: no duplicate invoice rows (PK conflict absorbed), no error, row contents byte-identical |
| M2-V10 | unit | Renewal mid-stream: two consumed proofs with adjacent period bounds; close the earlier period | Close selects the proof whose `period_start`/`period_end` cover the closed period, not the latest proof; invoice linked to the correct `purchase_proof_id` |
| M2-V11 | unit | Proof currency differs from the catalogue's current currency (proof EGP, catalogue since changed to USD) | Invoice `currency = "EGP"` — carried from the proof, never re-resolved |
| M2-V12 | unit | Mixed population: three active entitlements — one with consumed proof, one pending (never entitled), one active with no proof | Exactly one invoice row, for the proof-backed installation only |
| M2-V13 | unit | Invoice → proof → order navigability | Single SQL join `invoice.purchase_proof_id → purchase_proof.purchase_proof_id → purchase_proof.order_id` resolves for every issued invoice |
| M2-V14 | unit | `runPeriodClose` with malformed period input (not `YYYY-MM`) | Rejected/no-op with no partial writes; no invoice rows |
| M2-V15 | unit | Spec 059 supersession | `specs/059-billing-period-close/spec.md` carries a superseded banner citing A17 and this plan; FR-023..025 marked withdrawn (doc grep test) |
| M3-V1 | unit | Scripted diff of data-journey doc 16 against `schema.snap.sql` | Every current table (incl. `plan` with new columns, reshaped `invoice`, `purchase_proof`) and every column matches; `credit_price` absent from both |
| M3-V2 | unit | Doc 18 DO-state repair | Doc lists `creditsUsed` / `credit_budget`; enforcement claims match `isQuotaExhausted` behavior in `src/quota-do/` (asserted by a doc-content check against the source symbols) |
| M3-V3 | unit | CI wiring of the doc-16 diff | A deliberately drifted fixture (extra/missing column in the doc) fails the CI job; clean tree passes |
| M-E1 | e2e-seq | Apply all migrations to local D1 (wrangler dev); create plan `standard` via control route with price 150000 EGP, grace_days 7 | Plan row present with all A17 columns; audit row present; snapshot matches pinned file |
| M-E2 | e2e-seq | Enroll + entitle installation A (pre-O grant shape); SQL-fixture a consumed `purchase_proof` row (amount 150000 EGP) covering period 2026-08; run period close for 2026-08 | Invoice row for A: `amount=150000`, `currency=EGP`, `purchase_proof_id` = fixture jti |
| M-E3 | e2e-seq | Update plan `standard` price to 180000; fixture a second consumed proof (amount 180000) for period 2026-09; close 2026-09 | Period-08 invoice unchanged at 150000; period-09 invoice at 180000 — proving no catalogue re-lookup |
| M-E4 | e2e-seq | Re-run period close for 2026-08 and 2026-09 | Invoice count unchanged (2); no duplicates, no errors |
| M-E5 | e2e-seq | Enroll + entitle installation B with no proof fixture; close a new period 2026-10 with a proof only for A | Invoice only for A; B closes silently with no invoice |
| M-E6 | e2e-seq | Attempt `POST /control/credit-price/activate` with a valid operator credential; query `sqlite_master` for `credit_price` | 404; table absent |
| M-E7 | e2e-seq | Delete plan `standard` via control route; then attempt to read it | Row gone; `plan_delete` audit row present; subsequent plan read → 404 `plan_not_found` |
| M-X1 | x-e2e | Full money chain (end-state stack): ABO webhook `payment_succeeded` (amount 150000 EGP) → proof minted → consumed at entitle → AP period close | AP invoice `amount`/`currency` exactly equal the amount the ABO bound into the proof at payment time; invoice → proof → ABO `orders` row navigable by `order_id` |
| M-X2 | x-e2e | Catalogue price changed on AP between ABO order creation (price X) and payment capture; proof carries X | AP invoice prices the period at X, not the new catalogue price Y; ABO checkout was created at X from its cached `GET /v1/plans` fetch |
| M-X3 | x-e2e | `grace_days` single-sourcing: change `grace_days` 7 → 10 on the AP catalogue row | ABO order clock's next run computes `grace_until` / renewal-checkout timing from 10 with no ABO code or config edit (observed via the cached `GET /v1/plans` payload); AP receipt `valid_until` uses the same value |

### 3.3 Band N — Control-plane caller identity

**What this band does:** Executes A16 (AP-ARCH §2.10) item 1 as revised by the ABO design: extracts
`packages/ed25519-jws/` first (DP-L4), adds the `control_operator` and `control_cat_jti` migrations,
makes `OperatorAuth.resolve` async with the action argument (deviation 2), implements
`createCatOperatorAuth` with the §5.6 verification order, makes `control_audit.operator_id` the CAT
`iss`, and **removes the bearer entirely** — `createSecretOperatorAuth` and
`OPERATOR_BEARER_TOKEN` are deleted, not demoted (§8.1, §13 item 3). Auth-system recovery is a
D1-level operation under Cloudflare account IAM, documented as a runbook; human operators get a
local signing CLI (`scripts/cat-sign`) and one dual-registry provisioning script.

**Useful to know:** N1 is first and blocks nothing else in this band's consumers — but every later
verifier (purchase proof in O, receipts in P, PoP/proofs/ops tokens in Q/R) consumes the package, so
skipping it re-creates the three-verifier defect. N1 and N2 are sequential; N3 needs N2. **Doc
drift to note:** A16 item 1 still says the bearer is "demoted to break-glass scope"; the newer ABO
design (§8.1, §13 item 3) removes it, and this plan follows the ABO design. Patching A16's wording
is recorded as an optional governance task in U1 — it is an AP-ARCH amendment, not something a
slice may silently do (§2, no-rework rule).

**Code sync (verified against `ai-platform/` as of 2026-09-13):**
- `src/control/types.ts` — `OperatorAuth.resolve(request)` is synchronous and takes no action
  argument; `OperatorPrincipal` carries only `operatorId`.
- `src/control/auth.ts` — the bearer factory and `timingSafeEqualString` live here;
  `OPERATOR_BEARER_TOKEN` is the only control-plane credential. No `control_operator`,
  `control_cat_jti`, or CAT code exists (grep-verified).
- `src/identity/index.ts` — `EnrolledKeyVerifier` holds the Ed25519 compact-JWS verify logic and
  the validity-window helper (`isKeyWithinValidityWindow`) that N1 extracts.
- No `packages/` workspace directory exists; `ai-platform/scripts/` contains only
  `bootstrap-routing-policy.sh`.

| ID     | Slice                                                                       | Canonical                                              | Needs | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------ | --------------------------------------------------------------------------- | ------------------------------------------------------ | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **N1** | `packages/ed25519-jws/` extraction                                          | ABO §2.2, §5.1, deviation 12                            | —     | The workspace package exports compact-JWS sign/verify with `alg` pinned to EdDSA, the base64url codec, and a timing-safe string compare; `EnrolledKeyVerifier` internals and the `control/auth.ts` compare consume it; no behaviour changes — the existing AAT and control-plane suites pass unmodified against the extracted package                                                                                                                                                                            |
| **N2** | `control_operator` + `control_cat_jti`, async CAT `OperatorAuth`, bearer removal | AP-ARCH A16 item 1; ABO §3.4, §4.2, §5.6, §8.1, §13 item 3 | N1    | Forward-only migrations create both tables, pinned by a schema snapshot test; `OperatorAuth.resolve` is async and takes the action, with `requireOperator` gaining `await` + the action at every call site and dispatch otherwise untouched; `createCatOperatorAuth` implements the §5.6 verification order exactly (structure → `alg` pin → `kid` → row not revoked → signature → `aud` → `iat`/`exp` ≤ 120 s with 60 s skew → `act` in `allowed_actions` → `tgt` → body hash over raw bytes → `jti` insert-if-absent), any failure → `401 {"error":"unauthorized"}`; `createSecretOperatorAuth`, `OPERATOR_BEARER_TOKEN`, and every composite wiring are deleted; `control_audit.operator_id` is the CAT `iss`; the `jti` purge rides the existing daily retention cron; every existing control route's tests are rewritten to CAT and pass, and a bearer attempt fails with 401 because the credential no longer exists |
| **N3** | Human operator tooling: `cat-sign` CLI, dual-registry provisioning script, D1-recovery runbook | ABO §3.7, §4.1.8, §8.1, §11.2                            | N2    | `ai-platform/scripts/cat-sign` generates a personal Ed25519 keypair and signs CATs locally — the private key never leaves the operator's machine; one provisioning script registers an operator's public key into `control_operator` and (for dual-role operators) the ABO `ops_operator` registry atomically, exercised here against a local fixture of the §4.1.8 schema and re-validated against the real deployable in R3; the runbook documents auth-system recovery as a `wrangler d1` insert of a new `control_operator` row under Cloudflare account IAM, with no standing credential |

#### 3.3.1 Band N — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| N1-V1 | unit | Package sign/verify round trip with a fresh Ed25519 keypair | `verify(sign(payload))` true; compact JWS with `alg: "EdDSA"` header |
| N1-V2 | unit | `alg` confusion: token headers `alg: "none"` and `alg: "HS256"` (HMAC-signed with the public key as secret) | Both rejected — the `alg` pin is enforced before any key lookup |
| N1-V3 | unit | base64url codec vectors (RFC 4648 cases, padding-less encoding, embedded `-`/`_`) | Decode matches vectors; invalid characters / bad length → null, never throw |
| N1-V4 | unit | Timing-safe compare: equal strings, differing strings, unequal-length strings | true / false / false; unequal-length inputs do not short-circuit (constant-time loop over max length, as in the extracted `timingSafeEqualString`) |
| N1-V5 | unit | Malformed JWS structure: 2 segments, 4 segments, empty segment, non-base64url segment | All rejected at the structure step |
| N1-V6 | unit | Tampered payload byte after signing (exact-bytes rule, §5.1) | Verify false — the package verifies over the received segments, never a re-serialized parse |
| N1-V7 | unit | `isKeyWithinValidityWindow` extraction boundaries | `now == valid_from` accepted; `now == valid_until` rejected; missing bounds treated as open |
| N1-V8 | unit | `EnrolledKeyVerifier` consumes the package | Existing AAT and control-plane suites pass unmodified against the extracted package — zero behavior change, zero test edits |
| N2-V1 | unit | Happy path per action class: valid CAT (correct key, aud, act, tgt, bh, fresh jti, 120 s lifetime) for `enroll`, `entitle`, `plan_create`, body-less `suspend` | Each resolves a principal; `operatorId` = CAT `iss`; handler proceeds |
| N2-V2 | unit | Malformed JWS (not three segments) | 401 `{"error":"unauthorized"}`; fails at structure step |
| N2-V3 | unit | Wrong `alg` (`none`, HS256) | 401; fails at alg pin, before `kid` lookup |
| N2-V4 | unit | Unknown `kid` (no `control_operator` row) | 401 |
| N2-V5 | unit | Revoked operator key (`revoked_at` set) | 401 |
| N2-V6 | unit | Bad signature (valid structure, signed by a different key) | 401; fails after the row lookup, at signature |
| N2-V7 | unit | Wrong `aud` (e.g. `"ai-platform"` instead of `"ai-platform-control"`) | 401 |
| N2-V8 | unit | Expired CAT (`now > exp + 60 s` skew) | 401 |
| N2-V9 | unit | `iat` in the future beyond 60 s skew | 401 |
| N2-V10 | unit | Lifetime `exp − iat > 120 s` (both instants currently valid) | 401 — max-lifetime enforced independently of expiry |
| N2-V11 | unit | Skew boundaries: `exp` passed by exactly 60 s; by 61 s | 60 s → accepted; 61 s → 401 |
| N2-V12 | unit | `act` ≠ route action (CAT for `entitle` presented to `enroll`) | 401 |
| N2-V13 | unit | `act` not in the row's `allowed_actions` (human key scoped `["quota-inspect"]` attempts `entitle`) | 401 — scope enforced from the `control_operator` row, not the token |
| N2-V14 | unit | `tgt` mismatch (CAT targets installation B, path is installation A) | 401 |
| N2-V15 | unit | Body-hash mismatch (body byte modified after signing) | 401; handler never parses the body |
| N2-V16 | unit | Body-less route with `bh` = SHA-256 of the empty string | Accepted; same route with any other `bh` → 401 |
| N2-V17 | unit | `jti` replay: identical CAT presented twice | First 200, second 401 (insert-if-absent conflict) |
| N2-V18 | unit | Concurrent identical-CAT requests (same `jti`, raced) | Exactly one succeeds; the other 401 — no double-mutation |
| N2-V19 | unit | Failed verification does not burn the `jti` (fails at an earlier step, e.g. expired) | No `control_cat_jti` row written; a corrected CAT with the same `jti` is then accepted |
| N2-V20 | unit | Mutation failure rolls the `jti` back (replay-guard co-location, §5.1): force the control mutation's batch to fail after auth | `control_cat_jti` row absent afterwards; a retry with the same `jti` is not rejected as replay |
| N2-V21 | unit | `jti` purge on the daily retention cron | Rows with `expires_at < now` deleted; unexpired rows kept; cron otherwise unchanged |
| N2-V22 | unit | `control_audit.operator_id` attribution | Carries the CAT `iss` (e.g. `"orchestrator"`, `"haytham"`), never the key id and never an env-configured id |
| N2-V23 | unit | Bearer attempt on a control route (`Authorization: Bearer <old token>`) | 401 — the credential no longer exists; `createSecretOperatorAuth` deleted |
| N2-V24 | unit | Grep test over code, `wrangler.toml`, and `worker.ts` wiring | No `OPERATOR_BEARER_TOKEN`, no `createSecretOperatorAuth`, no composite auth wiring; exactly one factory (`createCatOperatorAuth`) remains |
| N2-V25 | unit | Port shape: `OperatorAuth.resolve(request, action)` async | Every `requireOperator` call site awaits and passes the route's action; dispatch (`src/control/index.ts`) otherwise untouched; type check fails on any missed call site |
| N2-V26 | unit | Uniform rejection body | Every failure above returns the identical `401 {"error":"unauthorized"}` body — no step-identifying detail, no 403 anywhere (no-oracle convention) |
| N2-V27 | unit | Migrations for `control_operator` / `control_cat_jti` | Apply cleanly to empty and existing databases; snapshot pinned; one operator may hold many key rows |
| N2-V28 | unit | Rotation overlap: two unrevoked key rows for one `operator_id` | CATs signed by either key verify and attribute the same `iss` |
| N2-V29 | unit | Every pre-existing control route's suite rewritten to CAT | Full control-plane suite green with CAT auth; no route skipped |
| N3-V1 | unit | `cat-sign` CLI: generate keypair, sign a CAT, present to the local control plane | CAT accepted (200 on a control route); public key printable for registration |
| N3-V2 | unit | `cat-sign` private-key hygiene | Private key material appears in no stdout/stderr/log artifact (grep over captured output) |
| N3-V3 | unit | Dual-registry provisioning script with a forced mid-script failure (after `control_operator` insert, before `ops_operator` insert) | Neither registry retains the row — atomic across both, exercised against the local §4.1.8 fixture |
| N-E1 | e2e-seq | Apply migrations; insert `control_operator` row for `orchestrator`; sign a CAT via `cat-sign`; call plan create | 200; `control_audit.operator_id = "orchestrator"`; `control_cat_jti` row present |
| N-E2 | e2e-seq | Re-present the identical CAT from E1; then a fresh-`jti` CAT | Replay → 401; fresh → 200 |
| N-E3 | e2e-seq | Register a second key for `orchestrator` (rotation), revoke the first | Old-key CAT → 401; new-key CAT → 200; audit `iss` unchanged |
| N-E4 | e2e-seq | Run the daily retention cron with a mix of expired and live `jti` rows from E1–E3 | Only expired rows purged |
| N-E5 | e2e-seq | Walk every control route (enroll, entitle, plan CRUD, suspend, resume, quota-inspect, support-lookup, kill-switch, …) with (a) a scoped CAT, (b) a bearer header | (a) each succeeds or fails only on its own domain rules; (b) every route → 401 |
| N-E6 | e2e-seq | D1-level recovery drill: delete all `control_operator` rows (auth system lost) → confirm all CAT calls 401 → execute the runbook (`wrangler d1` insert of a fresh operator row under account IAM) → sign a CAT with the new key | Control access fully restored; no standing credential existed at any point; drill log attached to the runbook |
| N-X1 | x-e2e | ABO outbox processor calls AP `enroll` with a freshly minted orchestrator-scoped CAT | AP 200; audit attributes `orchestrator`; each ABO call carries a unique `jti` (spy over consecutive calls) |
| N-X2 | x-e2e | ABO key row mis-scoped (e.g. `allowed_actions` lacking `entitle`) while the ABO attempts `entitle` | AP 401; ABO outbox row not marked done; alert surfaced |
| N-X3 | x-e2e | Clock skew between services: ABO clock 45 s ahead of AP; then 75 s ahead | 45 s → CAT accepted (within 60 s skew); 75 s → 401 |
| N-X4 | x-e2e | Orchestrator CAT key rotation handshake (§3.4): insert new `control_operator` row → rotate ABO secret + kid var → revoke old row | Mid-rotation both keys work; post-revocation old-kid CATs → 401, new-kid CATs → 200; overlap window ≤ 120 s CAT lifetime |
| N-X5 | x-e2e | Cross-service audience isolation: ABO ops token (`aud = "ai-billing-orchestrator-ops"`) presented to AP control; AP CAT (`aud = "ai-platform-control"`) presented to ABO ops | Both 401 — neither verifier accepts the other's audience |
| N-X6 | x-e2e | CAT signed with the wrong trust-domain key (purchase-proof signing key used as a CAT key) | AP 401 at `kid` lookup — `bill-<n>` kids never resolve in `control_operator` (§3.2 namespace) |
| N-X7 | x-e2e | No-bearer proof across both deployables: grep both repos and both `wrangler.toml`s for bearer/`OPERATOR_BEARER_TOKEN`/shared ops credentials; attempt bearer auth on every AP control route and the ABO ops surface | Zero matches; 401 everywhere — there is no bearer path anywhere (CP-ABO-1 evidence) |

### 3.4 Band O — Purchase-proof-gated grants

**What this band does:** Executes A16 items 2–4 and ABO §8.2: the `entitlement` table gains
`order_id` (UNIQUE partial index) and `purchase_proof_id`, `control_audit` gains `order_id`; every
grant path (`enroll`, `entitle`, the new `renew`, `override`) is gated on a verified purchase
proof; consumption is batch-atomic (`409 purchase_proof_replayed` rolls the grant back); enroll
dedup tightens to `installation_id` only and plan validation moves from the hardcoded
`isKnownPlanTier` list to the catalogue; `renew` and `entitlement-suspend` are added;
`BILLING_PURCHASE_PROOF_PUBLIC_KEYS` and `BILLING_ISSUER` become platform vars.

**Useful to know:** O1 needs M2 (the `purchase_proof` table exists) and N2 (CAT auth is checked
before any proof verification matters). O2 and O3 are sequential — `renew` reuses O2's consumption
machinery. The expected refactor collision point is `src/control/entitle.ts` (proposal §9 finding
1); G1's one-mutation catalogue assignment logic is reused as-is (§8.2). The guard needs no change:
it already rejects any entitlement `status ≠ active` (§6.2, code-verified).

**Code sync (verified against `ai-platform/` as of 2026-09-13):**
- No AP code exists yet for `purchase_proof`, `renew`, or `entitlement-suspend` (grep-verified).
- `src/control/lifecycle.ts:110` validates the enroll plan via the hardcoded `isKnownPlanTier`
  (`src/platform-vocabulary.ts:27`), and `handleEnroll`'s existence check carries the `org_id`
  OR-clause that §13 item 2 removes.
- `src/control/entitle.ts` is the G1 assignment logic O2/O3 extend; `EnrollPayload` in
  `src/control/types.ts` still carries caller-supplied `plan` / `public_key` / `kid`.
- The `purchase_proof` table DDL lands with M2; `entitlement` currently has neither `order_id` nor
  `purchase_proof_id` (`schema.snap.sql`).

| ID     | Slice                                                              | Canonical                                              | Needs   | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------ | ------------------------------------------------------------------ | ------------------------------------------------------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **O1** | Grant-path schema and the shared purchase-proof verifier           | AP-ARCH A16 item 2; ABO §4.2, §5.7                      | M2, N2  | A forward-only migration adds `entitlement.order_id` (with the partial UNIQUE index), `entitlement.purchase_proof_id`, and `control_audit.order_id`, pinned by a schema snapshot test, with legacy null-`order_id` rows untouched; the shared verifier module implements the §5.7 platform verification order (structure → `alg` pin → `kid` → key from `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` within its validity window → signature → `iss`/`aud` against `BILLING_ISSUER` → `exp`/`iat` with 60 s skew); every failure rejects with no writes |
| **O2** | Gated `enroll` / `entitle` / `override`, enroll dedup, catalogue plan validation | AP-ARCH A16 items 2, 4; ABO §5.7, §8.2, §13 item 2      | O1      | Enroll's body shrinks to `{ purchase_proof, org_id, display_name, region }` with `kid` / `public_key` / `plan` taken from the proof claims and validated against the body; dedup is on `installation_id` only (the `org_id` OR-clause is removed); plan validation is a catalogue lookup (`status = 'active'`) and `isKnownPlanTier` leaves the enroll path; `entitle` requires `kind ∈ {purchase, comp}` on a `pending` entitlement; `override` requires `kind = comp`; the `purchase_proof` insert shares the grant's D1 batch so a replay rolls everything back with `409 purchase_proof_replayed`; every grant's audit row carries `order_id`; a grant without a valid proof writes nothing |
| **O3** | `renew` and `entitlement-suspend` endpoints                        | AP-ARCH A16 item 3; ABO §5.7, §6.2, §6.4, §8.2          | O2      | `POST /control/v1/installations/{id}/renew` requires entitlement `active` or `suspended` (`404 entitlement_not_found`, `409 not_renewable` from `pending`), applies catalogue economics and the proof's period bounds (early renewals start at the current `period_end`; reactivations run `[paid_at, paid_at + 1 month]`), sets `status = active`, writes `order_id` / `purchase_proof_id`, consumes the proof batch-atomically, and audits with `order_id`; `POST /control/v1/installations/{id}/entitlement-suspend` is body-less and CAT-only, moving `active → suspended` else `409 illegal_lifecycle_transition`; `renew` is the only `suspended → active` path and installation-level suspend/resume are untouched |

#### 3.4.1 Band O — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| O1-V1 | unit | O1 migration | `entitlement.order_id` + partial UNIQUE index (`WHERE order_id IS NOT NULL`), `entitlement.purchase_proof_id`, `control_audit.order_id` present; snapshot pinned |
| O1-V2 | unit | Legacy rows with null `order_id` | Untouched; multiple null-`order_id` entitlement rows coexist (partial index) |
| O1-V3 | unit | Verifier happy path: well-formed proof, known `kid` in window, valid signature, correct `iss`/`aud`, fresh | Accepted; claims returned to the handler |
| O1-V4 | unit | Structure failure (2/4 segments, empty segment) | Rejected at structure step; no writes |
| O1-V5 | unit | `alg` ≠ EdDSA (`none`, HS256) | Rejected at alg pin; no writes |
| O1-V6 | unit | Unknown `kid` (not in `BILLING_PURCHASE_PROOF_PUBLIC_KEYS`) | Rejected; no writes |
| O1-V7 | unit | Key validity-window edges: `now < not_before`; `now ≥ not_after`; `now == not_before`; `now == not_after` | Reject; reject; accept; reject (mirrors `isKeyWithinValidityWindow`) |
| O1-V8 | unit | Bad signature (signed by a non-billing key) | Rejected; no writes |
| O1-V9 | unit | Wrong `iss` (≠ `BILLING_ISSUER`) | Rejected; no writes |
| O1-V10 | unit | Wrong `aud` (≠ `"ai-platform-control"`) | Rejected; no writes |
| O1-V11 | unit | `exp` passed beyond 60 s skew; `iat` in the future beyond 60 s skew | Both rejected; no writes |
| O1-V12 | unit | Skew boundaries: `exp + 60 s` exactly; `exp + 61 s` | Accept; reject |
| O1-V13 | unit | Malformed claims: missing `kind`/`order_id`/`period_start`/`period_end`; `period_start ≥ period_end`; non-UUID `jti` | Each rejected; no writes |
| O1-V14 | unit | `amount_cents` boundaries: 0 (comp), negative, non-integer, missing | 0 accepted; negative / non-integer / missing rejected |
| O1-V15 | unit | Every rejection above writes nothing | Row-count assertions: no `purchase_proof` insert, no entitlement mutation, no `control_audit` row, no `installation`/`installation_key` row |
| O1-V16 | unit | Platform vars wired: `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` parses as the §3.3 key-set shape; `BILLING_ISSUER` non-empty | Missing/malformed var fails fast at isolate init, not per-request |
| O2-V1 | unit | Enroll happy path: body `{ purchase_proof, org_id, display_name, region }`, proof `kind = purchase` | 200; `installation` + `installation_key` + `entitlement (pending, zero quotas)` inserted; `kid`/`public_key`/`plan` taken from proof claims; audit row carries `order_id` |
| O2-V2 | unit | Enroll without a proof; enroll with a forged proof | Both rejected; zero rows written |
| O2-V3 | unit | Enroll body `kid`/`public_key`/`plan` mismatch against proof claims (each field independently) | Each rejected; no writes |
| O2-V4 | unit | Enroll does not consume the proof | No `purchase_proof` row after enroll; the identical JWS is presentable to `entitle` immediately after |
| O2-V5 | unit | Enroll dedup on `installation_id` only: second enroll for the same installation | 409 `already_enrolled` |
| O2-V6 | unit | `org_id` collision under a different `installation_id` (OR-clause removed, §13 item 2) | Second enroll succeeds; `org_id` stored as metadata only |
| O2-V7 | unit | Enroll with a plan unknown to the catalogue; with a catalogue plan whose `status ≠ 'active'` | Both rejected; no writes (catalogue lookup replaced `isKnownPlanTier`) |
| O2-V8 | unit | Plan active in the catalogue but absent from the legacy hardcoded tier list | Enroll succeeds — `isKnownPlanTier` is out of the enroll path (grep: no import in `lifecycle.ts`) |
| O2-V9 | unit | Entitle happy path: `kind = purchase` proof on a `pending` entitlement | 200; entitlement `active` with catalogue economics; `order_id`/`purchase_proof_id` written; `purchase_proof` row inserted in the same batch; audit carries `order_id` |
| O2-V10 | unit | Entitle with `kind = renewal` | Rejected; entitlement stays `pending`; no writes |
| O2-V11 | unit | Entitle with `kind = comp` on `pending` | Succeeds (comp first-grant path) |
| O2-V12 | unit | Entitle on `active` entitlement → 409 `not_pending`; missing entitlement → 404 `entitlement_not_found`; missing installation → 404 `installation_not_found` | Existing codes preserved; no writes |
| O2-V13 | unit | Proof replay at entitle: same `jti` presented twice | Second attempt → 409 `purchase_proof_replayed`; entitlement state, capability grants, and audit identical to after the first success |
| O2-V14 | unit | Batch atomicity: pre-seed the `purchase_proof` row so the insert PK-conflicts mid-batch | Whole grant rolls back: entitlement still `pending` with zero quotas, no `capability_grant` rows, no audit row; response 409 `purchase_proof_replayed` |
| O2-V15 | unit | `order_id` reuse across two installations (proof B for installation B carrying an `order_id` already on installation A's entitlement) | UNIQUE index violation → 409; installation B's grant fully rolled back; installation A untouched |
| O2-V16 | unit | Entitle economics source: proof `plan` claim = `standard`; catalogue row for `standard` updated after proof minting | Entitlement receives current catalogue economics; proof claims never set quotas/budgets |
| O2-V17 | unit | Catalogue-inactive plan at entitle (plan retired between enroll and entitle) | Entitle rejected; no writes; entitlement stays `pending` |
| O2-V18 | unit | Override with `kind = purchase`; with `kind = renewal` | Both rejected; no writes |
| O2-V19 | unit | Override happy path: `kind = comp` proof, economics-merging payload | 200; merge logic unchanged from G; `order_id`/`purchase_proof_id` written; proof consumed batch-atomically; audit carries `order_id` |
| O2-V20 | unit | Override without a proof | Rejected; no writes |
| O2-V21 | unit | Proof `installation_id` ≠ path installation id (enroll/entitle/override) | Rejected; no writes |
| O2-V22 | unit | Audit attribution: grant actions vs non-grant actions | Every grant audit row carries `order_id`; non-grant audit rows (plan CRUD, suspend) leave `order_id` null |
| O2-V23 | unit | Entitlement state × action matrix — `pending`: enroll (n/a, creates it), entitle purchase/comp, entitle renewal, override comp, renew, entitlement-suspend | entitle purchase/comp → succeed; entitle renewal → reject; override comp → per §5.7 kind rule (comp allowed, state rule per implementation — see open questions); renew → 409 `not_renewable`; entitlement-suspend → 409 `illegal_lifecycle_transition` |
| O3-V1 | unit | Renew on `active` with `kind = renewal` (early payer inside the lead window) | New `period_start` = current `period_end` (remaining days kept); `status = active`; `order_id`/`purchase_proof_id` updated; audit carries `order_id`; response `{ installation_id, status: "active", period_end }` |
| O3-V2 | unit | Renew on `suspended` (reactivation) | Period = `[paid_at, paid_at + 1 month]`; `status → active`; proof consumed |
| O3-V3 | unit | Renew on `pending` | 409 `not_renewable`; no writes |
| O3-V4 | unit | Renew on missing entitlement / missing installation | 404 `entitlement_not_found` / 404 `installation_not_found` |
| O3-V5 | unit | Renew kind acceptance: `purchase`, `renewal`, `comp` | All three accepted on `active`/`suspended` (§6.2) |
| O3-V6 | unit | Renew economics resolve from the catalogue, never the proof; proof `plan` claim absent from the catalogue (retired) | Catalogue economics applied on success; retired-plan proof → rejected with no writes (§6.6) |
| O3-V7 | unit | Renew replay: same renewal `jti` twice | Second → 409 `purchase_proof_replayed`; entitlement unchanged |
| O3-V8 | unit | Renew batch atomicity: forced `purchase_proof` insert conflict | Entitlement UPDATE and audit INSERT roll back; prior period bounds intact |
| O3-V9 | unit | Renew with an `order_id` already attached to another entitlement | UNIQUE violation → 409; full rollback |
| O3-V10 | unit | Renew never touches `installation.status`: installation-level `suspended` (human incident response) + valid renewal proof | Entitlement → `active`, installation stays `suspended`; identity layer still rejects with `installation_suspended` (two independent suspension axes, §6.2) |
| O3-V11 | unit | No entitlement-resume route exists | Route grep: renew is the only `suspended → active` path; a hypothetical `/entitlement-resume` request → 404 |
| O3-V12 | unit | Entitlement-suspend happy path: body-less CAT request on `active` entitlement | 200; `status → suspended`; audit row; no purchase proof consulted |
| O3-V13 | unit | Entitlement-suspend on `pending`; on already `suspended`; on missing entitlement | 409 `illegal_lifecycle_transition`; 409 `illegal_lifecycle_transition`; 404 `entitlement_not_found` |
| O3-V14 | unit | Entitlement-suspend scope: human CAT without `entitlement-suspend` in `allowed_actions` | 401 — orchestrator-scoped action |
| O3-V15 | unit | Guard against a suspended entitlement (no guard diff, §6.2) | Data-path request rejected with the existing `forbidden_capability` / `ai_disabled` codes; guard source unchanged |
| O3-V16 | unit | Renew period-bounds validation: proof with `period_start ≥ period_end` or malformed ISO instants | 400 `invalid_payload`; no writes |
| O3-V17 | unit | Installation-level suspend/resume untouched | Existing suspend/resume suites pass unmodified; they mutate `installation.status` only, never `entitlement.status` |
| O-E1 | e2e-seq | Local stack: migrations applied; catalogue seeded (`standard` active, grace_days 7); `control_operator` row + CAT signing key; `BILLING_*` vars + test proof key configured | Boot clean; `GET`-level health of control dispatch confirmed |
| O-E2 | e2e-seq | Enroll installation A with a valid `kind = purchase` proof (test-signed) | 200; entitlement `pending` zero quotas; audit has `order_id`; `purchase_proof` table still empty (not consumed) |
| O-E3 | e2e-seq | Entitle A presenting the identical JWS from E2 | 200 `active`; `purchase_proof` row now present with `amount_cents`/`currency` stored; entitlement carries `order_id`/`purchase_proof_id` |
| O-E4 | e2e-seq | Replay the E3 entitle | 409 `purchase_proof_replayed`; state byte-identical to post-E3 |
| O-E5 | e2e-seq | Entitlement-suspend A (body-less, CAT only); then a data-path request as A | `active → suspended`; guard rejects A's request with existing codes |
| O-E6 | e2e-seq | Renew A with a fresh `kind = renewal` proof (same `order_id`, new `jti`, `paid_at = now`) | `suspended → active`; period `[paid_at, +1 month]`; new proof row consumed; audit carries `order_id` |
| O-E7 | e2e-seq | Early renewal: renew A again while `active` with another renewal proof | New `period_start` = previous `period_end` — remaining paid days preserved |
| O-E8 | e2e-seq | Override A with a `kind = comp` proof (credit_budget bump) | 200; economics merged; comp proof consumed |
| O-E9 | e2e-seq | Run period close for A's first period (joins Band M's chain) | Invoice priced from the E3 proof's `amount_cents`/`currency`; `invoice.purchase_proof_id` = E3 jti; invoice → proof → order navigable |
| O-E10 | e2e-seq | Enroll installation B with its own valid proof whose `order_id` equals A's | Entitle B → 409 (UNIQUE `order_id`); B's grant rolled back; A unaffected |
| O-X1 | x-e2e | Full provision chain: ABO webhook `payment_succeeded` → proof minted → outbox `provision` drives AP `enroll` then `entitle`, presenting the identical JWS both times | AP: enroll 200 (proof unconsumed), entitle 200 (proof consumed); ABO: order `paid → provisioned`, `provisioned_at` set |
| O-X2 | x-e2e | Replay across the boundary: ABO sweeper re-presents the identical JWS after a dropped first attempt that actually committed | AP 409 `purchase_proof_replayed`; ABO treats it as success per §11.1 — confirming `quota-inspect` read, outbox row marked `done`, no double grant (§3.11 rule 3) |
| O-X3 | x-e2e | Wrong issuer: ABO configured with `iss` ≠ AP's `BILLING_ISSUER` | AP rejects the proof with no writes; ABO outbox row never `done`; drift visible to reconciliation |
| O-X4 | x-e2e | Wrong audience: proof minted with `aud ≠ "ai-platform-control"` | AP rejects; no writes |
| O-X5 | x-e2e | Purchase-proof key rotation handshake (§3.3): add `bill-2` to AP key set → rotate ABO secret + active kid → overlap → retire `bill-1` | During overlap both `bill-1` and `bill-2` proofs verify; after retirement a `bill-1` proof is rejected at the key-window step; no paid order stranded |
| O-X6 | x-e2e | Clock skew between services: ABO-minted proof with `iat` 45 s in AP's future; then 75 s | 45 s → accepted; 75 s → rejected |
| O-X7 | x-e2e | ABO boot-time self-check vs AP config (§3.7): active proof `kid` missing from AP's key set, or issuer mismatch | ABO fails fast at boot: refuses to mint proofs and to run the outbox processor; structured alert emitted; AP sees zero malformed calls |
| O-X8 | x-e2e | Kind mismatches across the boundary: renewal proof presented at `entitle`; renewal proof at `enroll`; purchase proof at `override` | Each rejected by AP with no writes; ABO surfaces the failure instead of retrying forever |
| O-X9 | x-e2e | Key custody / two-signature rule: proof signed with the orchestrator CAT key; CAT signed with the purchase-proof key; grep both deployables for co-located signing keys | Both cross-signed tokens rejected (kid namespaces never resolve cross-domain, §3.2); no deployable holds both a grant-action CAT key and the proof signing key (§5.6 custody rule) |
| O-X10 | x-e2e | Forged proof (attacker-generated keypair, self-issued `kid`) driven through the real ABO outbox path against AP | AP rejects at `kid` lookup; no grant; no writes; ABO row fails and alerts (CP-ABO-3 falsification evidence) |

### 3.5 Band P — Provisioning receipt and commercial read surface

**What this band does:** Executes A16 item 5 and A17 item 4: the platform gains its first
production signing key (`PLATFORM_RECEIPT_PRIVATE_KEY` secret, `PLATFORM_RECEIPT_PUBLIC_KEYS`
var), the AAT-authenticated `GET /v1/installation/status` that mints provisioning receipts, the
unauthenticated `GET /v1/platform-keys`, and the unauthenticated `GET /v1/plans` serving the
sellable catalogue with price and `grace_days`; all new vars and secrets are registered in AP-ARCH
§13.4.

**Useful to know:** P1 needs M1 (`grace_days` exists for `valid_until = period_end + grace_days`)
and N1 (receipts sign through the shared package). P2 needs M1 only; the two slices may run in
parallel. The status endpoint authenticates through the existing `EnrolledKeyVerifier` /
`authenticateGetRequest` pattern — it is a data-path (`/v1/*`) endpoint with taxonomy errors, not a
control route, so it does not wait on N2. Reads come from the config cache (the A5 pattern): a warm
isolate pays no D1 I/O, and receipt signing is one `crypto.subtle.sign` per call — no DO, no
journal row (§5.9).

**Code sync (verified against `ai-platform/` as of 2026-09-13):**
- No `status`, `platform-keys`, or `plans` endpoint exists (grep-verified); the Worker has no
  signing secret today.
- AP-ARCH §13.4's configuration/secrets table does not yet name
  `BILLING_PURCHASE_PROOF_PUBLIC_KEYS`, `BILLING_ISSUER`, `PLATFORM_RECEIPT_PRIVATE_KEY`, or
  `PLATFORM_RECEIPT_PUBLIC_KEYS`.
- The config cache already serves `plan` rows (A5/G1), so both new read endpoints ride the existing
  warm/cold read pattern.

| ID     | Slice                                                                    | Canonical                                  | Needs     | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------ | ------------------------------------------------------------------------ | ------------------------------------------ | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **P1** | `GET /v1/installation/status` and `GET /v1/platform-keys`                | AP-ARCH A16 item 5; ABO §3.5, §5.8, §5.9, §8.3 | M1, N1    | The status endpoint authenticates via `EnrolledKeyVerifier` (audience `"ai-platform"`, 60 s skew), serves installation/entitlement status and `period_end` from the config cache, and includes a signed receipt — 15-minute `exp`, `aud` = installation id, `status = "active"`, `plan`, `period_end`, `valid_until = period_end + grace_days` from the catalogue, and the `platform_base_url` claim — exactly when both statuses are active; `platform-keys` serves the `PLATFORM_RECEIPT_PUBLIC_KEYS` var as a JWK key set, unauthenticated and cacheable; no journal row and no DO round trip per call; both secret and var are wired per environment |
| **P2** | `GET /v1/plans` and AP-ARCH §13.4 registration                           | AP-ARCH A17 item 4; ABO §4.1.6, §5.10       | M1        | The unauthenticated, edge-rate-limited endpoint serves exactly the `status = 'active'` catalogue rows from the config cache, each with `display_name`, `description`, `price_cents`, `currency`, and `grace_days`, with `Cache-Control: public, max-age=300` — pinned by the §4.1.6 contract test; the response is identical for every caller; AP-ARCH §13.4 is amended to name `BILLING_PURCHASE_PROOF_PUBLIC_KEYS`, `BILLING_ISSUER`, `PLATFORM_RECEIPT_PRIVATE_KEY`, and `PLATFORM_RECEIPT_PUBLIC_KEYS`          |

#### 3.5.1 Band P — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| P1-V1 | unit | Status call for installation with entitlement `pending` (both rows readable from config cache) | `200`; `entitlement_status: "pending"`; `receipt` field absent/null — receipts minted only when both statuses are `active` (§5.8) |
| P1-V2 | unit | Status call with entitlement `suspended`, installation `active` | `200`; `entitlement_status: "suspended"`; no receipt minted |
| P1-V3 | unit | Both statuses `active` — inspect minted receipt claims | Claims exactly: `iss = "ai-platform"`, `aud = <installation_id>`, `status = "active"`, `plan`, `period_end`, `valid_until`, `platform_base_url` present; no extra claims |
| P1-V4 | unit | Receipt lifetime | `exp − iat = 900` (15 min) exactly; header `{ alg: "EdDSA", kid: "rcpt-<n>" }` with the active signing kid |
| P1-V5 | unit | `valid_until` derivation with catalogue `grace_days = 7` | `valid_until = period_end + 7 days`; changing the catalogue row to `grace_days = 14` changes the next minted receipt with no code edit (single-source proof, §4.1.6) |
| P1-V6 | unit | `valid_until` boundary: plan with `grace_days = 0` | `valid_until == period_end` exactly |
| P1-V7 | unit | Receipt signature round trip | Signature verifies over the exact `base64url(header) + "." + base64url(payload)` bytes with the public key served by `platform-keys`; recomputed over re-serialized JSON it must NOT be relied on (§5.1 — verify over received segments) |
| P1-V8 | unit | Receipt `aud` binding | Receipt minted for installation A has `aud = A`; a verifying fixture checking against installation B rejects (cross-clinic use impossible) |
| P1-V9 | unit | AAT auth: wrong `aud` claim on the AAT (audience `"ai-platform"` expected) | Taxonomy `401 unauthenticated`; no status data served |
| P1-V10 | unit | AAT expiry skew edges (60 s) | `now = exp + 59 s` → accepted; `now = exp + 61 s` → `401 unauthenticated` |
| P1-V11 | unit | AAT future-`iat` skew edges | `iat = now + 59 s` → accepted; `iat = now + 61 s` → `401` |
| P1-V12 | unit | AAT lifetime cap | `exp − iat > MAX_AAT_LIFETIME_SECONDS (600)` → `401` even with valid signature |
| P1-V13 | unit | AAT key selection: unknown `kid`; revoked key; key whose `installation_id` ≠ token `iss` | Each → `401 unauthenticated` (ownership bound before verify, `EnrolledKeyVerifier` pattern) |
| P1-V14 | unit | Enrolled-key validity-window edges (`isKeyWithinValidityWindow`) | `now < valid_from` → `401`; `now == valid_from` → accepted; `now == valid_until` → `401` (exclusive upper bound); `now < valid_until` → accepted |
| P1-V15 | unit | Installation `suspended` with otherwise valid AAT | Taxonomy `403 installation_suspended` (fail-closed lifecycle check after signature verification) |
| P1-V16 | unit | Malformed auth input matrix: missing header; 2-segment token; 4-segment token; `alg = "none"`; `alg = "HS256"`; non-base64url segments; non-JSON header/payload | Each → taxonomy `401 unauthenticated`; `alg` confusion impossible (EdDSA pin) |
| P1-V17 | unit | Warm-isolate read path | Second status call within config-cache TTL performs zero D1 reads (D1Reader spy); cold isolate reads installation/key/entitlement/plan once each |
| P1-V18 | unit | No write side effects per status call | No journal row inserted; no Quota DO round trip (spies); exactly one `crypto.subtle.sign` per call when a receipt is minted |
| P1-V19 | unit | `GET /v1/platform-keys` shape | Unauthenticated `200`; body `{ keys: [...] }` with each entry `{ kid, kty: "OKP", crv: "Ed25519", x, valid_from }` rendered from the `PLATFORM_RECEIPT_PUBLIC_KEYS` var |
| P1-V20 | unit | `platform-keys` during rotation overlap | Var holding two keys → both served; after old-key removal → only the active key served |
| P1-V21 | unit | `platform-keys` malformed var entry (bad base64url `x`, wrong `crv`, non-JSON var) | Endpoint fails closed: invalid entries never served as verifiable keys (exact disposition — drop-entry vs 500 — flagged as unsure below) |
| P1-V22 | unit | `platform-keys` cacheability | Response carries a public cache directive; no per-caller variation (two different callers get byte-identical bodies) |
| P2-V1 | unit | Catalogue filter: seed `active` + `retired` + `disabled` plans | Response contains exactly the `status = 'active'` rows — pinned by the §4.1.6 contract test |
| P2-V2 | unit | Per-plan response shape | Each entry carries exactly `plan`, `display_name`, `description`, `price_cents`, `currency`, `grace_days`; no internal catalogue columns leak |
| P2-V3 | unit | Cache header | `Cache-Control: public, max-age=300` exactly |
| P2-V4 | unit | Caller invariance | Two requests with different/absent auth headers → byte-identical bodies; unauthenticated → `200` |
| P2-V5 | unit | Empty sellable catalogue | `200` with `{ "plans": [] }` — not an error |
| P2-V6 | unit | Config-cache behaviour | Warm isolate serves with zero D1 I/O (spy); a catalogue change is invisible inside the cache TTL and visible after expiry + refetch |
| P2-V7 | unit | `grace_days` default surfaced | A plan row relying on `DEFAULT 7` serves `grace_days: 7` |
| P2-V8 | unit | Edge rate limiting | Requests beyond the configured edge rate-limit binding → `429`; normal callers unaffected |
| P-E1 | e2e-seq | Seed catalogue (plan `standard`, `grace_days = 7`, price); enrol an installation and activate its entitlement on the local AP stack — **dependency note:** if Band O is not yet landed, enrol/entitle via stubbed purchase-proof path or direct seed; the status endpoint itself only needs the rows | `GET /v1/installation/status` with a valid AAT → `200`, both statuses `active`, receipt present |
| P-E2 | e2e-seq | Fetch `GET /v1/platform-keys`; verify the P-E1 receipt against the served key set | Signature verifies; `aud` = installation id; `exp − iat = 900`; `valid_until = period_end + 7 d` |
| P-E3 | e2e-seq | Suspend the entitlement (D1 update or control call); re-poll status | `entitlement_status: "suspended"`; receipt absent |
| P-E4 | e2e-seq | Reactivate the entitlement; re-poll | Receipt present again with fresh `iat`/`exp` |
| P-E5 | e2e-seq | Rotate the receipt key: add `rcpt-2` to `PLATFORM_RECEIPT_PUBLIC_KEYS`, switch `PLATFORM_RECEIPT_PRIVATE_KEY` to the new key; refetch `platform-keys`; re-poll status | `platform-keys` serves both `rcpt-1` and `rcpt-2`; new receipt carries `kid: "rcpt-2"` and verifies against `rcpt-2` |
| P-E6 | e2e-seq | Unknown-`kid` self-heal: client fixture holding only `rcpt-1` fails to verify the P-E5 receipt, re-fetches `platform-keys`, retries once | First verification fails with unknown `kid`; after refetch the retry verifies — no operator action (§3.5 step 2) |
| P-E7 | e2e-seq | Retire `rcpt-1` from the served set; re-poll status and refetch keys | `platform-keys` serves only `rcpt-2`; receipts still mint and verify |
| P-E8 | e2e-seq | Change the plan price in the catalogue; observe `GET /v1/plans` before and after config-cache TTL expiry | Old price served within TTL; new price served after expiry — staleness delays the new price only |
| P-X1 | x-e2e | ABO cold isolate validates a plan: fetches AP `GET /v1/plans` once; second validation within 300 s | Exactly one upstream fetch (spy/log); second validation served from the ABO's per-isolate memory cache |
| P-X2 | x-e2e | AP unreachable (worker stopped) while ABO needs the catalogue | ABO surfaces `502 catalogue_unavailable` to its caller; no stale or fabricated catalogue used |
| P-X3 | x-e2e | Cache expiry mid-flow: catalogue cached in ABO; price changed on AP; new ABO validation before and after the 300 s max-age | Before expiry: old price used for a NEW checkout (allowed staleness); after expiry: refetch picks up the new price |
| P-X4 | x-e2e | `grace_days` single-source: change `grace_days` on the AP catalogue row | After cache expiry the ABO reads the new value from the catalogue payload with no ABO config change or redeploy (§4.1.6) |
| P-X5 | x-e2e | Clinic-style verifying client (pgsodium-equivalent fixture) against real AP: fetch `platform-keys` → seed local key store → fetch status receipt → run the §5.8 verification order | Valid receipt accepted; the same receipt with one flipped payload byte rejected; receipt for a different installation id rejected at the `aud` step |
| P-X6 | x-e2e | Key rotation propagated across origins: rotate on AP (P-E5 procedure) while the client fixture holds only the old key | Client's unknown-`kid` failure triggers one refetch of AP `platform-keys` and a successful retry — the §3.5 self-heal loop works over real HTTP |
| P-X7 | x-e2e | ABO consumes only the sanctioned AP surface | During all P-X/Q-X flows, the ABO origin issues no AP calls other than `GET /v1/plans` (purchase module) — outbound-call spy/log assertion (§2.3: never calls `/v1/*` data path otherwise, never `/control/v1/*` from the purchase module) |

### 3.6 Band Q — ABO purchase module

**What this band does:** Creates the `ai-billing-orchestrator/` deployable and its selling half
(§2, §4.1, §5.2–§5.5, §7): the Worker skeleton with its own D1, secrets, and three environments;
the slim `orders` schema with `provider_refs`, `webhook_events`, and the `outbox` table; the
per-isolate catalogue cache over `GET /v1/plans`; `POST /v1/orders` with clinic proof-of-possession
verification; poll-token-gated `GET /v1/orders/{id}`; and the Paymob adapter with its HMAC-verified,
idempotent webhook endpoint.

**Useful to know:** The constitution amendment registering this deployable is already in force
(DP-L5), so Q1 is not architectural drift. Q1 needs P2: with no local plan table (§4.1.6), order
creation cannot validate or price a plan until the platform serves the catalogue. Q2 and Q3 are
sequential. **Judgment call (DP-L6):** the `outbox` *table* migration lands in Q2 — it is part of
the §4.1 schema family hanging off `orders`, and the Q3 webhook must enqueue into it — while the
outbox *consumer* is Band R (R1). Renewal-checkout is likewise in Band R (R2), because §5.4's
key-rotation re-validation needs the orchestrator-scoped CAT minter. The ABO's error style is the
flat `{"error": "<snake_code>"}` family from day one (§5.1); the taxonomy machinery is never
imported.

**Code sync (verified against the repository as of 2026-09-13):**
- `ai-billing-orchestrator/` does not exist. The conventions to mirror are `ai-platform/`'s:
  forward-only D1 migrations named `YYYYMMDDHHMMSS_snake_case.sql`, three `wrangler.toml`
  environments, secrets via `wrangler secret`, Cron Triggers dispatched from `worker.ts`.
- `.specify/memory/constitution.md` (Operating Constraints, registered 2026-09-11) already
  registers the deployable; `AGENTS.md` has no `ai-billing-orchestrator/` line yet (§2.2 requires
  one).
- Paymob grounding (§7.2) was verified against Paymob's API on 2026-09-11: intention create with
  the merchant secret key, Unified Checkout URL composition, HMAC-SHA512 over the 20-field
  concatenation, and the documented chargeback-detection gap.

| ID     | Slice                                                                     | Canonical                                   | Needs | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------ | ------------------------------------------------------------------------- | ------------------------------------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Q1** | Worker skeleton, config inventory, catalogue cache                        | ABO §2.1–§2.4, §4.1.6, §5.10                 | P2    | `ai-billing-orchestrator/` deploys to development/staging/production, each with its own D1 and secrets, with a health endpoint reporting build and environment identity; the §2.4 inventory is wired — secrets `BILLING_PURCHASE_PROOF_PRIVATE_KEY`, `ORCHESTRATOR_CAT_PRIVATE_KEY`, `PAYMOB_SECRET_KEY` / `PAYMOB_PUBLIC_KEY` / `PAYMOB_HMAC_SECRET`, vars for the active `kid`s, `PAYMOB_INTEGRATION_ID`, `AI_PLATFORM_BASE_URL`, and `BILLING_PUBLIC_ORIGIN`; the server-side `GET /v1/plans` fetch is cached per isolate in memory for 300 s, a cold isolate fetches once, and a fetch failure surfaces as `502 catalogue_unavailable`; `AGENTS.md` gains the `ai-billing-orchestrator/` line; no plan or price table exists in the ABO's migrations (grep-pinned) |
| **Q2** | Billing schema, `POST /v1/orders`, `GET /v1/orders/{id}`                  | ABO §4.1.1–§4.1.5, §5.1–§5.4, §6.1           | Q1    | Forward-only migrations create `orders` (slim shape — no `org_id` / `display_name` / `region` columns; as-purchased `installation_id` / `kid` / `public_key` snapshot; stored `order_payload` bytes), `provider_refs`, `webhook_events`, and `outbox`, with the live-order partial unique index, pinned by a schema snapshot test; `POST /v1/orders` implements the §5.3 verification order over the exact payload bytes, mints the poll token (256-bit, SHA-256 hex stored, returned once), creates the checkout through the adapter port at the catalogue's current price, and returns `409 order_exists` with the existing `order_id` and no new token on a live-order conflict; `GET /v1/orders/{id}` is poll-token gated with timing-safe compare and returns the same `404` for unknown order and wrong token |
| **Q3** | Paymob adapter and webhook endpoint                                       | ABO §5.5, §6.1, §7.1, §7.2                   | Q2    | The adapter port (`create_checkout` / `cancel` / `list_settlements`; canonical events) is defined with Paymob as the first implementation: intention create, Unified Checkout URL composition, `notification_url` built from `BILLING_PUBLIC_ORIGIN`, HMAC-SHA512 20-field verification with timing-safe hex compare; the webhook resolves orders via `provider_refs`, enforces idempotency on `UNIQUE (provider, provider_event_id)` with no timestamp rejection gate, maps to canonical events at the edge, transitions the order machine, mints the purchase proof, enqueues the `outbox` row with the JWS embedded in `payload`, and triggers the processor via `ctx.waitUntil`; provider identifiers appear only in `provider_refs`, pinned by the §7.1 rule-4 contract test |

#### 3.6.1 Band Q — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| Q1-V1 | unit | Health endpoint per environment (development/staging/production) | `200` reporting build and environment identity; each environment's response names its own environment |
| Q1-V2 | unit | Boot with a required secret unset (each of `BILLING_PURCHASE_PROOF_PRIVATE_KEY`, `ORCHESTRATOR_CAT_PRIVATE_KEY`, `PAYMOB_SECRET_KEY`, `PAYMOB_PUBLIC_KEY`, `PAYMOB_HMAC_SECRET` in turn) | Startup fails fast with a named-missing-secret error; the worker never serves requests half-configured |
| Q1-V3 | unit | Catalogue cache: cold isolate validates a plan, then validates again within 300 s | Exactly one upstream `GET /v1/plans` fetch (spy); the second validation performs zero fetches |
| Q1-V4 | unit | Cache expiry boundary and stampede | At max-age boundary the next validation refetches exactly once; N concurrent cold validations collapse to one upstream fetch (single-flight) |
| Q1-V5 | unit | Fetch failure semantics | Upstream 5xx/network error → caller gets `502 catalogue_unavailable`; an expired entry plus a failing upstream still → `502` (no stale serve, §4.1.6); the failure does not poison the cache — a later successful fetch is cached normally |
| Q1-V6 | unit | Schema and style guards (grep/migration tests) | No plan or price table in `ai-billing-orchestrator/migrations/`; no taxonomy-envelope import anywhere in ABO `src/`; `AGENTS.md` carries the `ai-billing-orchestrator/` line |
| Q2-V1 | unit | Happy-path `POST /v1/orders` with a correctly signed payload | `201` with `order_id`, `status: "pending"`, `checkout_url`, `checkout_expires_at`, `poll_token`; DB row stores only the SHA-256 hex of the token; `order_payload` stored byte-identical to the received string |
| Q2-V2 | unit | Bad PoP signature | `400 {"error":"invalid_signature"}`; zero rows in `orders` / `provider_refs` |
| Q2-V3 | unit | Payload tamper matrix: re-sign nothing, flip in turn `plan`, `installation_id`, `kid`, `public_key`, `nonce`, `issued_at`, one whitespace byte, key order | Every variant → `400 invalid_signature` — verification runs over the exact received bytes before parsing (§5.1/§5.3) |
| Q2-V4 | unit | Signature valid but computed over different bytes than the transmitted `order_payload` | `400 invalid_signature` |
| Q2-V5 | unit | `public_key` field malformed (not base64url, decodes to ≠ 32 bytes) | `400 invalid_payload` (fails at the key-decode step of the §5.3 order, before signature verify) |
| Q2-V6 | unit | `issued_at` age edges (24 h rule) | `issued_at = now − 24 h + 1 s` → accepted; `now − 24 h − 1 s` → `400 invalid_payload`; far-future `issued_at` → `400 invalid_payload` (future-policy flagged as unsure below) |
| Q2-V7 | unit | Missing/empty required field (each of the 8 §5.2 fields in turn); `order_payload` not valid JSON | Each → `400 invalid_payload` |
| Q2-V8 | unit | Plan not in the cached catalogue; plan present on AP but `status ≠ active` | Both → `404 plan_not_found` (the catalogue serves only active rows, so retired is indistinguishable from unknown — §6.6) |
| Q2-V9 | unit | Catalogue fetch failure at order time | `502 catalogue_unavailable`; no `orders` row written |
| Q2-V10 | unit | Live-order guard: existing order in each live state (`pending`, `paid`, `provisioned`, `past_due`) | Each → `409 order_exists` carrying the existing `order_id`; no new poll token; adapter `create_checkout` not called (spy) |
| Q2-V11 | unit | Repurchase after each terminal state (`cancelled`, `expired`, `refunded`, `chargeback`) | New `POST /v1/orders` → `201`; partial unique index does not block |
| Q2-V12 | unit | Two concurrent creates for the same `installation_id` | Exactly one `201`, one `409 order_exists` — the partial unique index is the enforcement, not a read-then-write check |
| Q2-V13 | unit | Poll-token auth on `GET /v1/orders/{id}` | Correct token → `200` with the §5.4 provider-agnostic shape (no provider ids, no amounts); wrong token → `404`; unknown order id → `404`; the two `404` bodies are byte-identical; timing-safe compare helper invoked (spy); missing/malformed `Authorization` → same `404` (uniform-404 policy for missing header flagged as unsure) |
| Q2-V14 | unit | Order state machine illegal-transition matrix: `pending → provisioned`, `pending → past_due`, `paid → pending`, `provisioned → pending`, any transition out of `refunded`/`chargeback`/`expired`/`cancelled` | Each rejected by the machine; order row unchanged (§6.1) |
| Q2-V15 | unit | Checkout expiry and schema guards | Expired checkout (`checkout_expires_at` passed, unpaid) → order transitions `pending → cancelled`; migrations apply cleanly to empty D1; schema snapshot pinned including `idx_orders_live_installation`; `orders` has no `org_id`/`display_name`/`region` columns; every error body is the flat `{"error": "<snake_code>"}` shape |
| Q3-V1 | unit | Paymob intention-create golden fixture | Request carries `Authorization: Token <PAYMOB_SECRET_KEY>`, amount in cents, `currency: "EGP"`, `payment_methods: [<PAYMOB_INTEGRATION_ID>]`, `special_reference = order_id`, `notification_url = <BILLING_PUBLIC_ORIGIN>/v1/webhooks/paymob` |
| Q3-V2 | unit | Unified Checkout URL composition and ref storage | `checkout_url = …/unifiedcheckout/?publicKey=<PAYMOB_PUBLIC_KEY>&clientSecret=<…>`; intention id and Paymob order id land only in `provider_refs` (kinds `intention` / `checkout`); `UNIQUE (provider, kind, provider_ref)` enforced |
| Q3-V3 | unit | HMAC verification vectors | HMAC-SHA512 over the documented 20-field concatenation of `body.obj` (booleans as literal `true`/`false`, no separators), lowercased hex, timing-safe hex compare (spy); golden Paymob fixture verifies; each single-field mutation fails |
| Q3-V4 | unit | Webhook reject paths | Invalid HMAC → `400` before ANY write (no `webhook_events` row, no order transition — spies); missing `hmac` query param → `400`; malformed body → `400` |
| Q3-V5 | unit | Duplicate delivery idempotency | Second delivery of the same `(provider, provider_event_id)` → `200` with no re-processing: no second order transition, no second outbox row, no second proof minted (spies); insert conflict on the UNIQUE key is the mechanism |
| Q3-V6 | unit | No timestamp rejection gate | Authentic payload whose `obj.created_at` is days old → processed normally; `obj.created_at` recorded on the `webhook_events` row for observability only |
| Q3-V7 | unit | Unresolvable provider ref | Webhook whose ids match no `provider_refs` row → `200`; `webhook_events` row inserted with `order_id = null`; no order touched |
| Q3-V8 | unit | Canonical event mapping matrix | `success=true` → `payment_succeeded`; `success=false` → `payment_failed`; `is_refunded=true` → `refunded`; `is_voided=true` → ignored (no transition); the Paymob adapter never emits `chargeback` (documented gap — asserted against the mapping table) |
| Q3-V9 | unit | First-payment vs renewal distinction owned by core | `payment_succeeded` against a `pending` order → purchase (`paid`); the same canonical event against `provisioned` / `past_due` → recorded as `renewal_paid`; the adapter emits money movement only |
| Q3-V10 | unit | Out-of-order / inapplicable webhook events | `refunded` event for a `pending` order; `payment_succeeded` for a `cancelled` order → no state-machine transition; event still logged in `webhook_events`; disposition of the row (`processed` vs `failed`) and any alerting flagged as unsure below |
| Q3-V11 | unit | Purchase-proof minting on success | Proof claims per §5.7: `iss = BILLING_ISSUER`, `aud = "ai-platform-control"`, `jti` = new UUID recorded as `orders.purchase_proof_id`, `exp = iat + 72 h`, `kind = purchase`, `order_id`, the as-purchased `installation_id`/`kid`/`public_key` triple, `plan`, `period_start < period_end`, `amount_cents`/`currency` taken from the verified payment event — never a catalogue re-lookup; header `{ alg: "EdDSA", kid: "bill-<n>" }` |
| Q3-V12 | unit | Amount/plan tampering between order and webhook | Catalogue price changed after checkout creation: the minted proof still binds the amount actually paid (from the verified webhook), and `orders.plan` is unchanged until a paid renewal applies a new plan |
| Q3-V13 | unit | Outbox handoff from the webhook | Success webhook's D1 batch commits order transition + `webhook_events` + `outbox` row with the proof JWS embedded in `payload`; `ctx.waitUntil` invokes the processor for that row (spy); the HTTP `200` to the provider is not awaited on the processor; a dropped `waitUntil` leaves the row `pending` for the sweeper |
| Q3-V14 | unit | Refund/chargeback immediacy and failure split | `refunded`/`chargeback` from `paid`/`provisioned`/`past_due` → terminal status + `entitlement_suspend` outbox row enqueued immediately (no grace); failures before the idempotency insert → `400` (provider retries); failures after → `200`, row marked `failed`, recovery via outbox only |
| Q3-V15 | unit | Provider quarantine (§7.1) | Rule-4 contract test greps `orders`/`outbox`/proof serializers for adapter imports and fails on any; provider identifiers appear in no client response (`GET /v1/orders/{id}` body, error bodies) and no proof claim; comp-proof minter accepts `kind = comp`, `amount_cents = 0` (minter shared with R3 — flagged) |
| Q-E1 | e2e-seq | Lineage A — create: signed order payload from a fixture clinic keypair → `POST /v1/orders` on the local ABO stack (stubbed AP catalogue fetch, fake Paymob adapter) | `201 pending`; `checkout_url` present; poll token returned once |
| Q-E2 | e2e-seq | Poll with the Q-E1 token | `200`, `status: "pending"`, `checkout_url` non-null; poll with a wrong token → same `404` as an unknown order |
| Q-E3 | e2e-seq | Deliver an authentic-HMAC `success=true` webhook fixture for the Q-E1 checkout refs | Order → `paid`; `paid_at` and period bounds set; `webhook_events` row `processed`; outbox `provision` row `pending` with the proof JWS in `payload`; `orders.purchase_proof_id` set |
| Q-E4 | e2e-seq | Run the outbox processor against a stubbed platform control client — **dependency note:** the real enroll/entitle chain is Band R/O; if those are not landed, assert `paid` + pending outbox row and stop the lineage here | On success: order → `provisioned`, `provisioned_at` set; poll reflects `provisioned` |
| Q-E5 | e2e-seq | `POST /v1/orders/{id}/renewal-checkout` on the provisioned order with a valid target plan | `200`; new `checkout_url`/`checkout_expires_at` replace the old; new `provider_refs` rows added; old refs retained |
| Q-E6 | e2e-seq | Rotate the clinic key in the (stubbed) platform read, then retry renewal-checkout | `409 key_rotated`; no adapter call made (spy); order state unchanged |
| Q-E7 | e2e-seq | Deliver an authentic `is_refunded=true` webhook for lineage A | Order → `refunded` (terminal); `entitlement_suspend` outbox row enqueued immediately; further webhook events for the order cause no transitions |
| Q-E8 | e2e-seq | Lineage B — failure branch: create order → authentic `success=false` webhook | Order → `cancelled`; a fresh `POST /v1/orders` for the same installation → `201` (repurchase after terminal) |
| Q-E9 | e2e-seq | Lineage C — duplicate create: create order, then re-POST the identical payload | Second POST → `409 order_exists` carrying the first `order_id` and no new token; the original poll token still polls the original order (reinstall-resume shape, §10.4) |
| Q-E10 | e2e-seq | Lineage D — redelivery: pay an order, then redeliver the identical webhook bytes twice | Both redeliveries → `200`; exactly one `webhook_events` row, one outbox row, one proof; `past_due` flip itself is Band R2's order clock — out of Band Q scope (noted) |
| Q-X1 | x-e2e | Order creation against the live AP catalogue: active plan on real AP → `POST /v1/orders`; then retire the plan on AP and retry after ABO cache expiry | Active plan → `201`; retired plan → `404 plan_not_found` once the ABO's 300 s cache expires (before expiry the stale-but-active entry still validates — documented staleness) |
| Q-X2 | x-e2e | AP down at order time | `POST /v1/orders` → `502 catalogue_unavailable`; no `orders` row; renewal-checkout under the same condition → `502 catalogue_unavailable` |
| Q-X3 | x-e2e | Price-change propagation mid-flow: order A created at price X; price changed to Y on AP; order B (different installation) created within 300 s; order C after cache expiry | B's checkout is created at X (staleness window); C's at Y; A's already-issued checkout and any paid amount are never repriced |
| Q-X4 | x-e2e | `grace_days` read from the live catalogue | Changing `grace_days` on the AP row changes the value the ABO catalogue consumer observes after cache expiry, with no ABO redeploy (feeds R2's clock later) |
| Q-X5 | x-e2e | Renewal-checkout key-rotation re-validation against real AP: enrol the installation key on AP (stubbed grant path if Band O not landed), create + pay an order, rotate the installation key on AP, call renewal-checkout | `409 key_rotated` decided from a live authenticated AP read of the installation's active key; matching key material (no rotation) → checkout issued |
| Q-X6 | x-e2e | Minted proof verified by the real AP verifier: pay an order via webhook, extract the proof JWS from the outbox `payload`, run it through AP's §5.7 verification module with the real `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` / `BILLING_ISSUER` vars — **dependency note:** needs O1's verifier; otherwise verify with the shared `packages/ed25519-jws/` + claim assertions | Proof passes the full platform verification order; a proof minted with the wrong `kid` or wrong issuer fails closed |
| Q-X7 | x-e2e | Catalogue contract artifact consumed by both sides | The §4.1.6 contract test runs against the live AP `GET /v1/plans` response AND against the ABO's plan-validation logic, proving "exists and active" is one rule, not two implementations |

### 3.7 Band R — ABO orchestrator module

**What this band does:** Builds the orchestration half (§4.1.5, §4.1.7, §4.1.8, §5.4, §5.6, §6,
§11): the outbox consumer (whose never-purged rows double as the purchase-proof minting ledger),
the per-call CAT minter and platform control client, the per-minute sweeper cron, the order-clock
cron driven by catalogue `grace_days`, dunning per §6.3, the renewal-checkout endpoint, the
`entitlement_suspend` path, the ops surface (`ops_operator` / `ops_jti`, comp orders), daily
billing reconciliation consuming the §6.7 coherence matrix, the boot-time self-check, and the
key-rotation script.

**Useful to know:** R1 needs O3 (every platform grant path it drives exists) and Q2 (the schema and
producers exist). R2 needs R1 (CAT minter, adapter access) and Q3 (the webhook's order machine).
R3 needs R2. The two modules share a deployable and D1 but never keys: the purchase module cannot
sign a CAT and the orchestrator cannot sign a purchase proof (§2.1) — reviews must keep that
custody line bright. Platform-side idempotency (the 409 mappings of §11.1) is the backstop when an
outbox claim races; the processor confirms with a `quota-inspect` read before closing such a row.

**Code sync (verified against the repository as of 2026-09-13):**
- Nothing of this band exists; the platform-side routes it calls are Band O's output.
- The orchestrator CAT key's scope is exactly
  `["enroll","entitle","renew","entitlement-suspend","quota-inspect","support-lookup"]` (§5.6) —
  no grant action key ever co-locates with the purchase-proof signing key.
- The platform Worker's existing daily retention cron gains the `control_cat_jti` purge in N2; the
  ABO's three crons (`* * * * *` sweeper, `10 * * * *` order clock, `0 5 * * *` billing
  reconciliation) follow the `worker.ts` scheduled-dispatch pattern (§11.1).

| ID     | Slice                                                                     | Canonical                                   | Needs    | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------ | ------------------------------------------------------------------------- | ------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R1** | Outbox consumer, CAT minter, platform control client, sweeper cron        | ABO §3.4, §4.1.5, §5.6, §11.1                | O3, Q2   | Producers trigger the shared processor immediately (`ctx.waitUntil` from webhook and comp-order handlers); the processor claims rows atomically (`pending → processing` conditional update) so the immediate trigger and the sweeper cannot double-process; the `* * * * *` sweeper drains due rows with exponential backoff capped at 10 attempts, then `failed` + alert; `409 already_enrolled` / `409 not_pending` / `409 purchase_proof_replayed` mark the row `done` after a confirming `quota-inspect` read; each platform call carries a freshly minted CAT with the exact orchestrator scope; the provision job drives `enroll → entitle` presenting the identical JWS from `payload` on every retry and sets `orders.provisioned_at` on completion; outbox rows are never purged |
| **R2** | Order clock, dunning, renewal-checkout endpoint                           | ABO §5.4, §6.3, §6.4, §6.6, §11.1            | R1, Q3   | The `10 * * * *` order clock reads `grace_days` from the cached catalogue fetch; issues renewal checkouts at `period_end − grace_days` only when `orders.plan` is sellable and the order's key material still matches the platform (otherwise skips the adapter call and logs `renewal_checkout_skipped_plan_retired` / `renewal_checkout_skipped_key_rotated`); flips `past_due` at `period_end` setting `grace_until`; enqueues `entitlement_suspend` at `grace_until` and `await`s the processor inline; flips `expired` at `period_end + grace_days + 30 days`; cancels expired checkouts; `POST /v1/orders/{id}/renewal-checkout` (poll-token auth, uniform `404`) validates the target plan against the cached catalogue, re-validates key material through an orchestrator-scoped platform read, fails `409 key_rotated` after clinic key rotation, and replaces the checkout fields |
| **R3** | Ops surface, billing reconciliation, boot-time self-check, rotation script | ABO §3.7, §4.1.7, §4.1.8, §6.5, §6.7, §11.2, §11.3 | R2       | Migrations create `ops_operator` / `ops_jti` and `reconciliation_alert`; `POST /v1/ops/comp-orders` authenticates per-operator CAT-structured tokens (`aud = "ai-billing-orchestrator-ops"`) via the shared package with the `jti` insert in the same batch as the comp-order write, records `comp_operator_id`, and drives the order `pending → paid → provisioned` with no provider interaction; the daily reconciliation runs all three §11.3 directions, consumes the §6.7 coherence matrix as a contract artifact, and persists drift as `reconciliation_alert` rows with no alerts HTTP endpoint; the boot-time self-check verifies the active purchase-proof `kid` and `BILLING_ISSUER` against an authenticated platform read and fails fast on mismatch; the rotation script performs both sides of each §3.3 / §3.4 / §3.5 procedure in one operation with the overlap waits enforced; there is no shared ops bearer anywhere |

#### 3.7.1 Band R — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| R1-V1 | unit | Outbox claim atomicity: the producer's immediate `ctx.waitUntil` trigger and a sweeper tick race on the same `pending` row (§4.1.5) | The conditional `UPDATE … SET status='processing' … WHERE status='pending' AND next_attempt_at ≤ now` lets exactly one claimant win; the loser observes 0 rows updated and backs off; the platform control client is invoked exactly once |
| R1-V2 | unit | Backoff schedule: a platform call fails repeatedly; inspect `next_attempt_at` after attempts 1, 2, 3, … | Delays grow exponentially per attempt; `attempts` increments by 1 each time; status stays `pending`; a row whose `next_attempt_at` is in the future is never selected by the sweeper's due-row query |
| R1-V3 | unit | Attempt cap: 10th consecutive failure of a `provision` row | Row flips to `failed` with `last_error` populated and an alert log emitted; the sweeper never selects it again; the order remains `paid` (money received, provisioning alerted — §6.1) |
| R1-V4 | unit | 409 mappings as success (DP §3.11 rule 3): platform returns `409 already_enrolled` (enroll), `409 not_pending` (entitle), and `409 purchase_proof_replayed` (entitle) in three separate runs | Each run issues a confirming `quota-inspect` read showing the grant committed, then marks the outbox row `done` — never `failed`; no retry is scheduled |
| R1-V5 | unit | 409 mapping with a *failed* confirm: platform returns `409 already_enrolled` but the `quota-inspect` read shows no entitlement for the order's installation | The row is **not** closed as `done`; it follows the normal retry/failure path and the discrepancy surfaces as an alert (a 409 without a confirming read is drift, not success) |
| R1-V6 | unit | CAT minting claims (§5.6): inspect the token sent on an enroll call | Header `alg=EdDSA`, `kid` = active key-id var; claims `iss` = orchestrator operator id, `aud="ai-platform-control"`, `exp−iat ≤ 120`, `act="enroll"`, `tgt` = target installation id, `bh` = base64url SHA-256 of the exact raw body bytes (empty-string hash for body-less `entitlement-suspend`); two consecutive calls carry distinct `jti`s |
| R1-V7 | unit | CAT scope custody (§5.6): enumerate every action the orchestrator module can mint | Exactly `["enroll","entitle","renew","entitlement-suspend","quota-inspect","support-lookup"]`; no code path mints any other `act`, and the purchase module holds no CAT signing key (grep-level custody assertion) |
| R1-V8 | unit | Minting ledger (§4.1.5): a `provision` row fails twice, then succeeds on attempt 3 | Attempts 1, 2, and 3 present the **byte-identical** purchase-proof JWS read from `payload` (proofs are single-use platform-side, so re-minting would break retries); after completion the `done` row persists — a retention/purge sweep leaves `done` and `failed` outbox rows untouched |
| R1-V9 | unit | Platform down during provision: control client gets network error / 5xx | Attempt fails, row stays `pending` with backoff, order stays `paid`, `provisioned_at` remains null; a later successful attempt sets `orders.provisioned_at` and flips the order to `provisioned` exactly once |
| R1-V10 | unit | Enroll metadata source (§4.1.2, §8.2): order row has no `org_id`/`display_name`/`region` columns | The provision job parses `org_id` / `display_name` / `region` from the stored `order_payload` bytes and sends them in the enroll body; a tampered-column probe is impossible because the columns do not exist |
| R2-V1 | unit | Dunning date math is catalogue-derived (§6.3, §4.1.6): seed catalogue `grace_days = 7`, compute all three instants for an order; then change the catalogue value to 14 with no code edit | `grace_until = period_end + grace_days`, renewal lead = `period_end − grace_days`, expiry = `period_end + grace_days + 30 days` — all from the cached `GET /v1/plans` value; the next clock run uses 14 days with zero code changes (no hardcoded 7 anywhere in the clock) |
| R2-V2 | unit | Renewal-checkout lead boundary: run the order clock at `period_end − grace_days − 1s`, exactly at `period_end − grace_days`, and after | No checkout before the boundary; checkout issued at the boundary (adapter `create_checkout` called once, `checkout_url`/`checkout_expires_at` written, refs in `provider_refs`); no duplicate checkout on the next tick |
| R2-V3 | unit | Plan retired (§6.6): `orders.plan` absent from the cached catalogue at renewal-lead time | Adapter `create_checkout` is **not** called (spy assertion); no `checkout_url` written; order stays `provisioned`; structured log `renewal_checkout_skipped_plan_retired` names `order_id` and the retired plan |
| R2-V4 | unit | Clinic key rotated since purchase (§5.4, §6.4): the platform read shows a different active `kid` than the order's as-purchased snapshot | Adapter not called (spy); no checkout written; structured log `renewal_checkout_skipped_key_rotated`; dunning transitions proceed unchanged |
| R2-V5 | unit | `past_due` flip and suspend enqueue: clock runs with `period_end` passed, unpaid; then with `grace_until` passed | At `period_end`: order → `past_due`, `grace_until` set, no suspend yet (service continues in grace). At `grace_until`: an `entitlement_suspend` outbox row is enqueued and the processor is `await`ed inline (not `waitUntil`); the platform call happens inside the clock run |
| R2-V6 | unit | Terminal expiry: clock runs at `period_end + grace_days + 30 days − 1s`, at the tail, and after, with an open checkout | No flip before the tail; at the tail the order → `expired`; the adapter `cancel` is invoked for the open checkout and `checkout_url` cleared; post-tail runs are no-ops |
| R2-V7 | unit | Renewal-checkout endpoint error matrix (§5.4): wrong poll token; unknown order id; terminal order; retired target plan; catalogue fetch down; adapter failure | Wrong token and unknown order both → identical `404` (existence not enumerable); terminal order → `409 illegal_state`; valid targets are `provisioned` and `past_due` only; retired plan → `404 plan_not_found`; catalogue failure → `502 catalogue_unavailable`; adapter failure → `502 provider_error`; all bodies flat `{"error": …}` |
| R2-V8 | unit | Renewal-checkout key re-validation (§5.4): order's snapshot `kid`/`public_key` no longer the installation's active key | `409 key_rotated`; no adapter call (spy); no `provider_refs` row; checkout fields unchanged. On the matching-key path the endpoint replaces `checkout_url`/`checkout_expires_at` and appends new `provider_refs` rows (old refs retained as history) |
| R2-V9 | unit | Renewal period bounds (§6.4): renewal paid inside the lead window (entitlement still `active`) vs paid after suspension | Early payer: renewal proof's `period_start` = current `period_end` (remaining days kept). Reactivation: period = `[paid_at, paid_at + 1 month]`. The core (not the adapter) classifies `payment_succeeded` on a `provisioned`/`past_due` order as `renewal_paid` |
| R2-V10 | unit | Refund timing (§6.1, §6.3): refund webhook while `past_due` (in grace) vs after `expired` | In grace: order → `refunded` (terminal) and an `entitlement_suspend` outbox row fires **immediately** — no grace on clawed-back money. After expiry: event recorded in `webhook_events`, no state change, no outbox row |
| R3-V1 | unit | Ops token matrix part 1 (§11.2, §5.6): bad signature; expired token; `exp − iat > 120`; `iat` in the future beyond skew | Each → `401 {"error":"unauthorized"}`; no `ops_jti` row written; no order created |
| R3-V2 | unit | Ops token matrix part 2: `aud` ≠ `"ai-billing-orchestrator-ops"`; unknown `kid`; revoked operator key | Each → `401`; a token with `aud="ai-platform-control"` (a platform CAT) is rejected on the ops surface and vice versa |
| R3-V3 | unit | Ops `jti` replay (§4.1.8): the same token is presented twice | Second presentation → `401`; the `jti` insert-if-absent shares the D1 batch with the comp-order write, so the replay conflict rolls the order write back — no partial comp order exists |
| R3-V4 | unit | Ops token with `act` outside the operator's `allowed_actions` (e.g. operator provisioned without `"comp-order"`) | `401`; the check is against the operator's own row, not a global scope |
| R3-V5 | unit | Comp-order zero-amount flow (§6.5): valid operator token issues a comp order | Order created and driven `pending → paid → provisioned` with **no** adapter interaction (spy: `create_checkout` never called); minted proof has `kind="comp"` and `amount_cents=0`; `orders.comp_operator_id` = verified `operator_id`; outbox `provision` row enqueued and triggered via `ctx.waitUntil` |
| R3-V6 | unit | Coherence-matrix classification (§6.7): feed every listed pair plus unlisted pairs (e.g. `cancelled` × `active`, `expired` × `active`, `pending` × `active`) through the classifier | Every matrix-listed pair classifies as its stated verdict (coherent/transient); every unlisted pair classifies as drift; the matrix is consumed as a contract artifact, not re-implemented in prose |
| R3-V7 | unit | Reconciliation alert generation, all three kinds (§11.3): seed (a) a `paid` order with no matching entitlement `order_id`, (b) a platform `control_audit` grant whose `order_id` is unknown to the ABO, (c) a payout with no order and a provisioned order with no payout | Three `reconciliation_alert` rows with kinds `payment_without_entitlement`, `entitlement_without_payment`, `payout_mismatch`; each `detail` JSON cites order id, installation id, and amounts; every run and alert is also a structured log line |
| R3-V8 | unit | Reconciliation edge cases: payout reversal against a provisioned order (the Paymob chargeback gap, §7.2); a period closed < 3 days ago with no settlement yet; completely empty cohorts | Reversal → `payout_mismatch` alert (chargeback surfaces here, never from the adapter). Recent period → tolerated, no alert (settlement-lag rule). Empty cohorts → zero alerts, run still logged, no error |
| R3-V9 | unit | Boot-time self-check (§3.7): boot with active purchase-proof `kid` absent from the platform key set; boot with `BILLING_ISSUER` mismatch; boot correctly | Mismatch (either case) → fail-fast: the Worker refuses to mint proofs and refuses to run the outbox processor, and emits a structured alert. Correct config → normal operation; the check is an authenticated platform read (orchestrator-scoped CAT) cached for the isolate's lifetime (one read per isolate, spy-verified) |
| R3-V10 | unit | Rotation script (§3.7): run each key domain's procedure against fixtures | Purchase-proof key: platform key-set update → ABO secret + active `kid` var → enforced 72 h overlap wait → old-key retirement, in one operation. CAT key: `control_operator` insert → ABO secret + key-id var → old-row `revoked_at`. Receipt key: platform secret + served set → clinic refetch window → retirement. The script refuses to skip the overlap waits |
| R3-V11 | unit | Ops surface hygiene (§11.2): grep the deployable for any shared ops bearer; probe for an alerts read endpoint | No `BILLING_OPS_TOKEN`-style secret exists in code or `wrangler.toml`; `GET /v1/ops/reconciliation-alerts` (or any alerts HTTP route) does not exist — alerts are read/acknowledged via `wrangler d1` only |
| R-E1 | e2e-seq | Chain start: clinic-signed payload → `POST /v1/orders` | `201`, order O1 `pending`, `checkout_url` + `checkout_expires_at` set, poll token returned once (only its SHA-256 hex stored) |
| R-E2 | e2e-seq | HMAC-valid `payment_succeeded` webhook for O1's checkout | `webhook_events` row `processed`; O1 → `paid` with `paid_at`, period bounds, `purchase_proof_id`; outbox `provision` row `pending` with the minted JWS embedded in `payload`; processor triggered via `ctx.waitUntil` |
| R-E3 | e2e-seq | Immediate processor runs against the (mocked or real) platform: enroll 200 then entitle 200 | Outbox row → `done` with `processed_at`; O1 → `provisioned`, `provisioned_at` set; enroll and entitle carried the identical JWS from `payload` |
| R-E4 | e2e-seq | Clock reaches `period_end − grace_days` for O1 (plan still sellable, keys unchanged) | Renewal checkout pre-issued: new `checkout_url` on O1, new `provider_refs` rows; order stays `provisioned` |
| R-E5 | e2e-seq | Renewal paid: webhook for the renewal checkout | O1 stays one row (same `order_id`); new `purchase_proof_id`, `kind=renewal` proof; outbox renew job → platform `renew` 200 → new period starts at the old `period_end`; `orders.plan`/period updated |
| R-E6 | e2e-seq | Next `period_end` passes with no renewal payment | O1 → `past_due`, `grace_until = period_end + grace_days` (catalogue value); no suspend yet |
| R-E7 | e2e-seq | `grace_until` passes, still unpaid | `entitlement_suspend` outbox row enqueued and processed inline by the clock; platform entitlement → `suspended`; O1 remains `past_due` |
| R-E8 | e2e-seq | Tail passes (`period_end + grace_days + 30d`), still unpaid | O1 → `expired` (terminal); any open checkout cancelled via the adapter |
| R-E9 | e2e-seq | Repurchase after terminal: same installation posts a fresh signed order O2 | `201` accepted (live-order partial unique index no longer blocks); O2 pays and provisions end-to-end like E2–E3 |
| R-E10 | e2e-seq | Refund branch: `is_refunded` webhook arrives for O2 while `provisioned` | O2 → `refunded` (terminal); `entitlement_suspend` outbox row fires immediately (no grace); platform entitlement suspended within the same run |
| R-E11 | e2e-seq | Failed-provisioning branch: new order O3 paid; platform enroll returns 500 on attempts 1–3, then 200 | O3 stays `paid` through the failures; `attempts` and `next_attempt_at` progress per backoff; the sweeper (not the producer) drives retries 2+; attempt 4 succeeds with the identical JWS → row `done`, O3 `provisioned` |
| R-E12 | e2e-seq | Persistent platform failure on a new order O4; plus a duplicate delivery of O4's paid webhook | After the 10th attempt the outbox row is `failed` with an alert log; O4 stays `paid` (never silently dropped). The duplicate webhook → `200` with no re-processing, no second proof minted, no second outbox row (`UNIQUE (provider, provider_event_id)` conflict) |
| R-X1 | x-e2e | Full provision chain against the **real** AP: paid webhook → outbox → real CAT + real purchase proof → AP `enroll` + `entitle` | AP accepts the CAT (row in `control_operator`, `jti` consumed in `control_cat_jti`); the purchase proof verifies against `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` and its `jti` lands in the AP `purchase_proof` table; entitlement `active` with `order_id` set; `control_audit` rows carry `operator_id="orchestrator"` and the `order_id` |
| R-X2 | x-e2e | Double-claim race against real AP: immediate trigger and sweeper both process the same row before the claim lands | One attempt's enroll commits; the other gets `409 already_enrolled`, issues a real `quota-inspect` confirm, and closes its row `done`; exactly one entitlement row exists; no `failed` row |
| R-X3 | x-e2e | AP down during provision (Worker unreachable), then restored | Attempts fail with backoff while AP is down; order stays `paid`; after AP recovers, a sweeper-driven retry completes enroll+entitle → `done`, order `provisioned` — no manual intervention |
| R-X4 | x-e2e | Suspend propagation: grace expiry drives `entitlement-suspend` to real AP, then a data-path request is made with a valid AAT | AP entitlement → `suspended`; the guard rejects the request with the existing `forbidden_capability` / `ai_disabled` codes (no guard diff); installation-level status untouched |
| R-X5 | x-e2e | Renewal end-to-end against real AP: renewal paid → `renew` | Entitlement `active` with new period bounds and new `purchase_proof_id`; economics resolved from the AP catalogue (not the proof); Quota DO period counters reset on the bounds change; audit row carries `order_id` |
| R-X6 | x-e2e | Injected drift: manually flip an entitlement `active → suspended` in AP D1 while the ABO order is `provisioned` | Next daily reconciliation classifies `provisioned × suspended` as drift per the §6.7 matrix and writes a `reconciliation_alert` (`payment_without_entitlement` direction) citing the order and installation |
| R-X7 | x-e2e | Both drift directions against real AP: (a) `paid` order whose entitlement was never created; (b) a platform-side grant (human `override` with comp proof) whose `order_id` the ABO has never seen | (a) → `reconciliation_alert` kind `payment_without_entitlement`; (b) → kind `entitlement_without_payment` found via the audit-paging read; both alerts' `detail` JSON navigable to the offending records |
| R-X8 | x-e2e | Clock skew between ABO and AP on CAT `exp`/`iat`: ABO clock +45 s, then +90 s vs AP | +45 s: CAT accepted (within the 60 s skew allowance), grant proceeds. +90 s: `401 unauthorized`; the outbox row retries with a freshly minted CAT — and succeeds once clocks are re-aligned, proving retries re-mint rather than reuse CATs |
| R-X9 | x-e2e | Boot self-check against live AP: deploy with matching `kid`/`BILLING_ISSUER`, then with a mismatched active `kid` | Matching: isolate boots, one authenticated platform read, proofs mint normally. Mismatched: boot fails fast — no proof minting, no outbox processing, structured alert emitted — before any paid order can hit a failing `enroll` |
| R-X10 | x-e2e | Rotation script rotates the purchase-proof key across both deployables with live traffic | After step 2 both `bill-n` and `bill-(n+1)` verify at AP; new proofs carry `bill-(n+1)` and are accepted; a proof signed by `bill-n` during the overlap is still accepted; after step 4 retirement, a `bill-n` proof is rejected (`401`/grant rejection with no writes). CAT-key rotation likewise: new `control_operator` row live, old row revoked, in-flight old-key CATs fail after revocation |
| R-X11 | x-e2e | Suspend-to-clinic propagation: after R-X4's suspension, the clinic polls `GET /v1/installation/status` | Status returns `entitlement_status="suspended"` and **no receipt**; the clinic flag self-expires at the previously stored `valid_until` with no network call (handoff to Band S's verifier) |

### 3.8 Band S — Clinic Supabase

**What this band does:** The clinic-side half (§9, §3.6), all in one forward-only migration family
reusing the B1 patterns (SECURITY DEFINER functions in `auth_internal`, thin `public` wrappers,
`GRANT EXECUTE … TO authenticated`, deny-all RLS untouched): the `create_ai_order` signing RPC, the
receipt-verified `set_ai_availability` **replacing** the boolean variant, the platform receipt key
seed and add/revoke RPCs, the self-expiring `get_ai_availability`, and pgsodium key wrapping of
installation secret keys.

**Useful to know:** S1 is independent and may start immediately (it records nothing and calls
nothing external). S2 needs P1 — the receipt contract and the key-distribution endpoint it verifies
against must be frozen first. S3 needs S1 (it re-points the signing internals). The clinic database
stays ignorant of money: no order state, no vendor credentials, no provider anything (§9.5) — the
A15 boundary holds in both directions. The key-wrapping slice documents its honest boundary (§3.6):
protection against SQL-level exfiltration, not against live `postgres` access.

**Code sync (verified against `backend/` as of 2026-09-13):**
- The B1 migration family exists (`20260801120000_ai_keystore_schema.sql`,
  `20260801120200_ai_token_issuer_rpc.sql`); `ai_internal.installation_keys.secret_key` is raw
  `bytea` today (§3.6).
- `public.set_ai_availability(boolean, text)` and its `auth_internal` twin exist
  (`20260905120100_set_ai_availability_rpc.sql`) and are dropped by S2 — leaving both would keep a
  permanent bypass of the activation ceremony (§9.2).
- `public.get_ai_availability()` returns plain `jsonb` without `valid_until` today.

| ID     | Slice                                                                                  | Canonical                          | Needs | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------ | -------------------------------------------------------------------------------------- | ---------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **S1** | `public.create_ai_order(p_plan text)` signing RPC                                      | ABO §5.2, §9.1; AP-ARCH §4.2.1      | —     | The owner/admin-gated RPC selects the active installation key (same ordering as the issuer), builds the §5.2 payload with `jsonb_build_object`, signs the exact payload text with `pgsodium.crypto_sign_detached`, and returns `{ order_payload, signature, installation_id, kid, public_key }`; it records nothing; errors are `FORBIDDEN`, `INSTALLATION_NOT_ENROLLED`, `INVALID_INPUT`; deny-all RLS is untouched                                                                                                                                                        |
| **S2** | Receipt-verified `set_ai_availability`, platform key seed RPCs, self-expiring `get_ai_availability` | ABO §3.5, §5.8, §9.2, §9.3          | P1    | The boolean `set_ai_availability` variants are dropped in the same migration that creates `public.set_ai_availability(p_receipt text)`: `NULL` always deactivates; non-null runs the full §5.8 verification against `ai.platform_receipt_keys` (structure → `alg` pin → `kid` known and unrevoked → `pgsodium.crypto_sign_verify_detached` over the exact signing input → `iss` → `aud` equals own installation id → `exp` → `status = "active"`) before writing `ai.availability`; failures are `INVALID_RECEIPT` (one code, no oracle) or `RECEIPT_EXPIRED`; `get_ai_availability` gains `valid_until` and self-expires without touching the stored row; `add_platform_receipt_key` validates 32-byte base64url keys and `revoke_platform_receipt_key` refuses the last unrevoked key (`CANNOT_REVOKE_LAST_PLATFORM_KEY`) |
| **S3** | pgsodium wrapping of installation secret keys                                          | ABO §3.6, §9.4                      | S1    | A migration adds `secret_key_wrapped` / `wrap_key_id`, populates them with `pgsodium.crypto_aead_det_encrypt` under a named pgsodium-managed key (`ai_installation_key_wrap`, id stored as `ai.key_wrap_id` in `app_settings`), and drops the plaintext column; `issue_ai_token` and `create_ai_order` decrypt at point of use with no RPC signature change; existing AAT issuance and order-signing tests pass unchanged; the slice documents the live-`postgres` honest boundary                                                                                                  |

#### 3.8.1 Band S — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| S1-V1 | unit | Owner calls `create_ai_order('standard')` with an enrolled keypair | Returns `{ order_payload, signature, installation_id, kid, public_key }`; `pgsodium.crypto_sign_verify_detached` over the exact `order_payload` UTF-8 bytes with the row's public key returns true |
| S1-V2 | unit | Payload shape (§5.2): parse the returned `order_payload` | Contains exactly `installation_id`, `kid`, `public_key`, `plan`, `org_id`, `display_name`, `region`, `nonce`, `issued_at` — no additional keys; `plan` echoes the argument; `public_key` is base64url of the active row's 32-byte key |
| S1-V3 | unit | Active-key selection: two unrevoked keys with different `valid_from`, plus a newer revoked key | The RPC selects by `valid_from DESC, kid DESC` among `revoked_at IS NULL` — the same row `issue_ai_token` would pick; the revoked key is never selected |
| S1-V4 | unit | Permission gate: plain staff (non-owner/non-admin) and an unauthenticated call | Both → `FORBIDDEN` (via `assert_owner_or_administrator`); nothing is written |
| S1-V5 | unit | No active installation key (never enrolled, or all revoked) | `INSTALLATION_NOT_ENROLLED` |
| S1-V6 | unit | Blank / whitespace-only `p_plan` | `INVALID_INPUT`; no signature produced |
| S1-V7 | unit | Side-effect freeness and freshness: call twice, diff the database | No rows written anywhere — `ai_token_issuance` count unchanged, `app_settings` unchanged (the RPC records nothing, §9.1); the two calls carry distinct `nonce`s and `issued_at ≈ clock_timestamp()`; deny-all RLS policies on `ai_internal` tables unchanged |
| S2-V1 | unit | Valid receipt (correct key, `aud` = own installation, `status="active"`, unexpired) → `set_ai_availability(receipt)` | `ai.availability` written as `{ enrolled: true, platform_base_url, valid_until }` taken from the receipt claims; success result returned |
| S2-V2 | unit | Bad signature (valid structure, signature over different bytes) | `INVALID_RECEIPT`; stored flag unchanged |
| S2-V3 | unit | Wrong `aud` (receipt minted for a different installation id) | `INVALID_RECEIPT`; unchanged |
| S2-V4 | unit | Unknown `kid` (not present in `ai.platform_receipt_keys`) | `INVALID_RECEIPT`; unchanged (this is the Flutter self-heal trigger, §3.5) |
| S2-V5 | unit | Revoked `kid` (entry present, `revoked_at` stamped) | `INVALID_RECEIPT`; unchanged |
| S2-V6 | unit | Wrong `iss` (≠ `"ai-platform"`), and `status ≠ "active"` | Both → `INVALID_RECEIPT`; unchanged |
| S2-V7 | unit | `alg` confusion and malformed structure: header `alg="none"`/`HS256`; token with ≠ 3 segments; non-base64url segments | All → `INVALID_RECEIPT`; the `alg` pin rejects before any key lookup |
| S2-V8 | unit | Expired receipt (`exp` in the past, everything else valid) | `RECEIPT_EXPIRED` — the one distinct code; unchanged flag |
| S2-V9 | unit | No oracle: compare error payloads of S2-V2…S2-V7 | Identical `INVALID_RECEIPT` code and message for every non-expiry failure — an attacker cannot tell which verification step failed |
| S2-V10 | unit | `NULL` receipt: owner deactivates an active flag; owner deactivates when never activated | Both succeed: flag written `{ enrolled: false, platform_base_url: null, valid_until: null }` — turning AI off never needs a proof (§9.2) |
| S2-V11 | unit | Old boolean variant is gone: call `public.set_ai_availability(true, 'https://…')` after the migration | Function-does-not-exist error — the boolean bypass of the activation ceremony is dropped, not supplemented (§9.2); its `auth_internal` twin is also absent |
| S2-V12 | unit | Self-expiry: `get_ai_availability` before and after `valid_until` | Before: `{ enrolled: true, …, valid_until }`. After: returns `enrolled: false` while the **stored row is untouched** (still says `enrolled: true`); the next successful activation overwrites it |
| S2-V13 | unit | `add_platform_receipt_key` validation: 31-byte, 33-byte, and non-base64url keys; a valid 32-byte key; the same `kid` twice | Invalid lengths/encodings → `INVALID_INPUT`; valid key upserts `{ kid, public_key, added_at, revoked_at: null }`; duplicate `kid` upserts (refreshes the entry, clears revocation) rather than erroring |
| S2-V14 | unit | `revoke_platform_receipt_key`: revoke one of two keys; then revoke the last unrevoked key | First succeeds (`revoked_at` stamped); second → `CANNOT_REVOKE_LAST_PLATFORM_KEY`, mirroring the installation-keystore rule |
| S2-V15 | unit | Fail-closed with no keys: a clinic that never seeded keys receives an otherwise-valid receipt | `INVALID_RECEIPT` — no keys means no activation (§9.3); key RPCs are owner/admin-gated (`FORBIDDEN` for plain staff); deny-all RLS on `app_settings` untouched — only the SECURITY DEFINER RPCs reach the key set |
| S3-V1 | unit | Wrapping migration over a database with existing plaintext `secret_key` rows | Every existing row gains `secret_key_wrapped` / `wrap_key_id` populated via `pgsodium.crypto_aead_det_encrypt(secret_key, kid::bytea, key_id)`; the plaintext `secret_key` column is absent from the schema afterwards |
| S3-V2 | unit | Round-trip: decrypt a wrapped row with `crypto_aead_det_decrypt` under the named key | Yields the original 64-byte Ed25519 secret; a token signed with the decrypted key verifies against the row's public key |
| S3-V3 | unit | `issue_ai_token` after wrapping (regression) | Still mints AATs that `verify_aat` accepts; RPC signature unchanged; issuance ledger row written as before |
| S3-V4 | unit | `create_ai_order` after wrapping (regression) | Still returns signatures that verify over the exact payload bytes; RPC signature unchanged — S1's suite passes unmodified |
| S3-V5 | unit | Wrap-key bookkeeping | `app_settings` carries `ai.key_wrap_id` equal to the id of the pgsodium-managed key named `ai_installation_key_wrap`; the id itself is not treated as secret |
| S3-V6 | unit | SQL-dump protection (the §3.6 honest boundary): use dumped `secret_key_wrapped` bytes directly as a signing key | `crypto_sign_detached` with the wrapped bytes produces signatures that fail verification — a dumped table without the pgsodium root key is not a signing key; new enrollments post-migration write only the wrapped columns |
| S-E1 | e2e-seq | Chain start: owner runs keypair enrollment (`enroll_installation_keypair()`) | Active row in `ai_internal.installation_keys`; `installation_id` established |
| S-E2 | e2e-seq | Owner calls `create_ai_order('standard')` | Payload + signature returned; signature verifies against the E1 row's public key; payload `kid`/`installation_id` match E1 |
| S-E3 | e2e-seq | Seed the platform receipt key: owner calls `add_platform_receipt_key('rcpt-test', <32-byte base64url>)` | Entry present in `ai.platform_receipt_keys` with `revoked_at: null` |
| S-E4 | e2e-seq | A receipt arrives (test-signed by `rcpt-test`, `aud` = E1 installation, `status="active"`, `valid_until` = period_end + grace): `set_ai_availability(receipt)` | Full §5.8 verification passes; `ai.availability` = `{ enrolled: true, platform_base_url, valid_until }` |
| S-E5 | e2e-seq | `get_ai_availability()` immediately after E4 | `{ enrolled: true, platform_base_url, valid_until }` — flag live for all staff readers |
| S-E6 | e2e-seq | Advance the clock past `valid_until`; call `get_ai_availability()` again | Returns `enrolled: false` with no network and no write; the stored row still reads `enrolled: true` (self-expiry is read-time only) |
| S-E7 | e2e-seq | Rotation: add a second platform key `rcpt-test-2`; a receipt signed by the new `kid` arrives | `set_ai_availability` accepts it; `valid_until` extends (refresh path, §10.2) |
| S-E8 | e2e-seq | Revoke `rcpt-test-2`'s predecessor; replay the E4 receipt (old `kid`); then try to revoke the now-last key | Old-`kid` receipt → `INVALID_RECEIPT`; revoking the last unrevoked key → `CANNOT_REVOKE_LAST_PLATFORM_KEY` |
| S-E9 | e2e-seq | Attempt the legacy path: call the old boolean `set_ai_availability(true, …)` | Errors — function does not exist; the only activation path left is receipt-verified |
| S-E10 | e2e-seq | Permission matrix and recovery: plain staff calls each of `create_ai_order`, `set_ai_availability`, `add_platform_receipt_key`, `revoke_platform_receipt_key`; then owner deactivates with `NULL` and re-activates with a fresh receipt | Every staff call → `FORBIDDEN`; owner `NULL` deactivate succeeds; fresh receipt re-activates and overwrites the stored row |
| S-X1 | x-e2e | Real AP receipt: with a provisioned entitlement on AP, fetch `GET /v1/installation/status` (staff AAT) and feed the returned receipt to the clinic's `set_ai_availability` | Accepted: flag written with `platform_base_url` equal to the AP origin and `valid_until` from the receipt; the receipt verifies against the key set served by `GET /v1/platform-keys` |
| S-X2 | x-e2e | Forged receipt: attacker mints a well-formed JWS with their own Ed25519 keypair, `kid="rcpt-1"` | `INVALID_RECEIPT` — signature fails against the seeded platform key; flag unchanged |
| S-X3 | x-e2e | Tampered receipt: take S-X1's genuine receipt and flip a claim (extend `valid_until`) without re-signing | `INVALID_RECEIPT` — verification runs over the exact received segments, never a re-serialization (§5.1) |
| S-X4 | x-e2e | Expired receipt: hold S-X1's receipt until its 15-minute `exp` passes, then submit | `RECEIPT_EXPIRED`; flag unchanged |
| S-X5 | x-e2e | Cross-clinic receipt: a genuine AP receipt minted for installation B presented to clinic A | `INVALID_RECEIPT` — `aud` ≠ A's installation id; a receipt for one clinic can never activate another (§5.8) |
| S-X6 | x-e2e | Receipt after suspension: AP suspends the entitlement (ABO grace expiry), clinic polls status and attempts refresh | Status returns `entitlement_status="suspended"` with no receipt; there is nothing to submit; the clinic flag self-expires at the previously stored `valid_until` on the next read — enforcement needs no network |
| S-X7 | x-e2e | Platform receipt-key rotation self-heal (§3.5): AP rotates to `rcpt-2` and signs with it; the clinic holds only `rcpt-1` | First submit → `INVALID_RECEIPT` (unknown `kid`); the client re-fetches `GET /v1/platform-keys`, seeds `rcpt-2` via `add_platform_receipt_key`, retries exactly once → accepted |
| S-X8 | x-e2e | `valid_until` coherence across deployables (§4.1.6, §6.3): compare the receipt's `valid_until` with the ABO order clock's suspend instant for the same period | Both equal `period_end + grace_days` read from the same catalogue row — the clinic self-expiry and the orchestrator suspension agree by construction, with no shared hardcoded constant |
| S-X9 | x-e2e | Full purchase-to-activation chain (CP-ABO-3 shape): `create_ai_order` → ABO `POST /v1/orders` → paid webhook → provision → AP status receipt → clinic activation | The clinic-signed payload passes ABO PoP verification; the provisioned entitlement yields a receipt; the clinic flag flips to `enrolled: true` with no human in the loop; a forged purchase proof anywhere in the chain fails closed |

### 3.9 Band T — Flutter purchase and activation

**What this band does:** The client flows of §10: the plan picker rendered from `GET /v1/plans`,
the purchase flow (sign → order → system-browser checkout → poll), the pull-based activation flow,
renewal and dunning UX, and the E1 architecture-lint extension covering the ABO origin.

**Useful to know:** T1 needs Q3 (the orders API and a working checkout), S1 (the signing RPC), and
P2 (the plan read). T2 needs T1, S2, and P1. The carried rules are pinned in §10: no provider SDK,
no card data in the app process, Flutter never calls `/control/v1/*` and never holds control-plane
credentials, provider swap means zero Flutter change. The `(order_id, poll_token)` pair lives in
the app's local secure storage and is never written to clinic Postgres (§10.1). All ABO error codes
map to UI states; platform unreachability renders as a normal state, never an error dialog (the E4
rule).

**Code sync (verified against `frontend/` as of 2026-09-13):**
- Stage-2 keypair enrollment (`enroll_installation_keypair()`) is already built (§10.1 step 2).
- The E1 lint exists and rejects prompt text, provider names, and model identifiers; it does not
  yet know the ABO origin or provider payment hostnames.
- The AI purchase surface does not exist; the existing hide-without-probing rule
  (`get_ai_availability().enrolled` gate) is its entry condition.

| ID     | Slice                                                          | Canonical                    | Needs         | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------ | -------------------------------------------------------------- | ---------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T1** | Plan picker and purchase flow, E1 lint extension               | ABO §5.10, §10.1; AP-ARCH §13.5 (R-12) | Q3, S1, P2    | The purchase surface appears only when `get_ai_availability().enrolled` is false; the plan picker renders entirely from `GET /v1/plans` (no plan name, price, or copy in the app binary) with fetch failure as a normal empty/retry state; the flow runs `create_ai_order` → `POST /v1/orders` → persist `(order_id, poll_token)` in local secure storage → `url_launcher` opens the checkout in the system browser → poll `GET /v1/orders/{id}` at 5 s with backoff in a visible, cancelable waiting state; terminal `cancelled` or poll timeout abandons and clears local state; the E1 lint fails the build on the ABO origin or any provider payment hostname in client code, proven by a deliberately failing fixture |
| **T2** | Activation pull flow, renewal and dunning UX                   | ABO §3.5, §6.3, §6.6, §10.2–§10.4 | T1, S2, P1    | On `paid` / `provisioned` (and on app start with a completed order in local storage) the app mints a staff AAT, seeds platform receipt keys on first activation, polls `GET /v1/installation/status` until `entitlement_status = active` with a receipt, and calls `set_ai_availability(receipt)`; an unknown-`kid` failure re-fetches `/v1/platform-keys` and retries once; an enrolled installation refreshes its receipt on every app start and whenever `valid_until` is within 3 days; the renewal banner appears from `period_end − grace_days`, offers plan selection from a cached `GET /v1/plans` and an explicit `renewal-checkout` call when `checkout_url` is null (retired plan), becomes a `grace_until` warning in `past_due`, and a suspended/expired state renders as a normal pay-to-reactivate surface; reinstall recovery via `409 order_exists` offers the reactivate path (§10.4) with no checkout |

#### 3.9.1 Band T — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| T1-V1 | unit | Purchase surface entry condition: `get_ai_availability().enrolled` true vs false | Surface visible only when `enrolled` is false (hide-without-probing rule, §10.1 step 1); no platform probe is issued to decide visibility (spy on HTTP layer) |
| T1-V2 | unit | Plan picker renders from a fetched `GET /v1/plans` response containing multiple active plans | Every rendered plan name, price, and display copy string traces to the response payload; nothing rendered comes from the app binary |
| T1-V3 | unit | Catalogue fetch fails (network error, 5xx) when the picker opens | Normal empty/retry state renders; no error dialog (E4 rule); retry re-fetches and renders |
| T1-V4 | unit | Purchase state machine happy path: sign → order → persist → browser → poll | States transition in order; `create_ai_order` RPC called with the chosen plan; `POST /v1/orders` body carries `order_payload` / `signature` unmodified from the RPC |
| T1-V5 | unit | `(order_id, poll_token)` persistence after `201` | Pair written to local secure storage; spy on the Supabase/RPC layer proves neither value is ever sent to clinic Postgres (§10.1) |
| T1-V6 | unit | Poll loop at 5 s with backoff; user taps cancel mid-poll | Cancellation abandons the flow, stops the poller, and clears the persisted pair; no further requests issued after cancel |
| T1-V7 | unit | Poll never reaches a terminal state within the timeout | Flow abandons with a defined timeout state and clears local state; no zombie poller survives |
| T1-V8 | unit | Poll observes terminal `cancelled` (abandoned/expired checkout server-side) | Flow abandons, local state cleared, purchase surface returns to its initial state |
| T1-V9 | unit | `POST /v1/orders` answers `409 order_exists` (reinstall / lost local storage) | Surface offers "already purchased — reactivate" carrying the returned `order_id`; no checkout is opened and no new poll token is expected (§10.4) |
| T1-V10 | unit | ABO error-code → UI-state mapping, one case per code: `invalid_payload`, `invalid_signature`, `plan_not_found`, `provider_error`, `catalogue_unavailable` | Each code renders its defined state; `catalogue_unavailable` / `provider_error` are retryable states; `plan_not_found` returns to the picker with a refreshed catalogue |
| T1-V11 | unit | `checkout_expires_at` passes while the order is still `pending` | Waiting state transitions to an expired-checkout state offering restart; the stale checkout URL is never re-opened |
| T1-V12 | unit | Poll observes `payment_failed` mapping (order → `cancelled`) | Failure state with explicit retry; retry starts a fresh order (new payload, new nonce) |
| T1-V13 | unit | Checkout launch | `url_launcher` opens `checkout_url` in the system browser (external-application mode); no in-app webview is instantiated and no card data enters the app process (spy) |
| T1-V14 | unit | App restart while an order is mid-poll | On start, the persisted pair resumes polling the same `order_id` without re-creating an order |
| T1-V15 | unit | E1 lint fixture: the ABO origin string appears in client code outside its single designated vendor-constant declaration | Build fails; the fixture is deliberately failing and pinned in CI (§10 carried rule) |
| T1-V16 | unit | E1 lint fixture: a provider payment hostname (e.g. the Paymob checkout host) anywhere in client code | Build fails; provider swap remains a zero-Flutter-change property |
| T1-V17 | unit | E1 lint on a clean tree with the coverage assertion enabled | Build passes; the guard covers every client source path (existing E1 behaviour preserved) |
| T1-V18 | unit | E1 lint origin allowlist | Only the platform origin and the single ABO-origin constant pass; any other non-allowlisted origin literal in client code fails the build |
| T2-V1 | unit | Activation pull state machine on poll observing `paid` / `provisioned` | Steps run in order: mint staff AAT → (first activation) fetch `GET /v1/platform-keys` → seed via `add_platform_receipt_key` → poll `GET /v1/installation/status` → `set_ai_availability(receipt)` (§10.2) |
| T2-V2 | unit | Staff AAT mint while entitlement is still `pending` | `issue_ai_token` succeeds — identity passes once enrolled even while `pending` (§5.9); activation poll can proceed before the grant lands |
| T2-V3 | unit | Status poll returns `entitlement_status = pending` (no receipt), then `active` with receipt | Poller continues with backoff while pending/absent-receipt and stops only when both conditions hold; receipt is passed to the RPC byte-exact |
| T2-V4 | unit | `set_ai_availability` fails with unknown-`kid` receipt | App re-fetches `GET /v1/platform-keys`, seeds new keys, and retries exactly once; a second failure surfaces a defined state and stops (§10.2 step 5) |
| T2-V5 | unit | Clinic RPC rejects the receipt: `INVALID_RECEIPT` vs `RECEIPT_EXPIRED` | Each maps to its defined UI state; expired triggers a fresh status poll (new receipt), invalid triggers the key-refetch path once |
| T2-V6 | unit | App start while enrolled | A receipt refresh (status poll → `set_ai_availability`) runs on every start, independent of the `valid_until` window (§10.2 refresh rule) |
| T2-V7 | unit | Refresh window math: `valid_until` at 3 days + 1 h vs 3 days − 1 h from now | Refresh is not triggered in the first case (beyond the start-of-app refresh) and is triggered in the second; boundary computed from the flag's `valid_until`, not from a hardcoded constant |
| T2-V8 | unit | Renewal banner window math: `period_end − grace_days` ± 1 h, `grace_days` from the catalogue | No banner before the window; banner from `period_end − grace_days`; changing the catalogue `grace_days` changes banner timing with no app edit |
| T2-V9 | unit | Banner while plan is sellable and the order poll shows a non-null `checkout_url` | One-tap "Renew" opens the pre-issued URL directly; no `renewal-checkout` call is made (spy) |
| T2-V10 | unit | Banner while plan is retired (`checkout_url` null) | Banner requires plan selection rendered from a cached `GET /v1/plans`; an explicit `POST /v1/orders/{id}/renewal-checkout` is issued with the chosen plan; spy proves no silent old-tier charge path exists (§6.6, §10.3) |
| T2-V11 | unit | Order poll observes `past_due` with `grace_until` set | Banner becomes a warning naming `grace_until`; AI chrome stays enabled; no blocking dialog |
| T2-V12 | unit | After suspension: device offline, `valid_until` in the past | `get_ai_availability` self-expires (`enrolled: false`) with no network; AI chrome hides on next flag read; purchase surface shows "suspended — pay to reactivate" |
| T2-V13 | unit | Order poll observes terminal `expired` | Pay-to-reactivate renders as a normal surface (not an error); tapping it starts a fresh purchase flow |
| T2-V14 | unit | Platform unreachable during status poll / refresh | Normal degraded state, never an error dialog (E4); the stored flag is left unchanged |
| T2-V15 | unit | Reinstall recovery end to end inside the flow: `409 order_exists` → reactivate | Reactivate path skips the ABO checkout entirely and runs §10.2 steps 2–4 (status + receipt need only an AAT); activation completes with no payment |
| T2-V16 | unit | Renewal paid from another device while this device is enrolled | This device's next start/window refresh picks up the fresh receipt and extends `valid_until`; AI chrome never goes dark |
| T2-V17 | unit | Clinic clock skew: receipt `exp` (15 min) appears expired on a skewed clock | Activation poll retries and self-resolves transient skew; `valid_until` (day-granular) tolerates hours of skew (§10.4) |
| T2-V18 | unit | App start with a completed order in local storage but `enrolled = false` | Activation pull resumes automatically from local state without user action (§10.2 step 1) |
| T-E1 | e2e-seq | Against mocked ABO/AP servers: open purchase surface, fetch catalogue | Picker renders two mocked plans; surface was hidden before flag flip and visible after |
| T-E2 | e2e-seq | Ensure Stage-2 keypair, then sign via `create_ai_order` | RPC returns `{ order_payload, signature, installation_id, kid, public_key }`; signature verifies over the exact payload bytes with the returned public key |
| T-E3 | e2e-seq | Submit order to mock ABO; persist; launch browser | Mock returns `201` with checkout URL + poll token; pair persisted; `url_launcher` invoked with the URL (mocked launcher spy) |
| T-E4 | e2e-seq | Mock advances the order `pending → paid → provisioned` while the app polls | Poller observes both transitions; on `provisioned` the flow hands off to activation without user input |
| T-E5 | e2e-seq | Activation pull against mock AP: keys seeded, status poll, receipt, flag write | `add_platform_receipt_key` called once per served key; `set_ai_availability(receipt)` called; `get_ai_availability` now returns `enrolled: true` with `valid_until = period_end + grace_days`; AI chrome enabled |
| T-E6 | e2e-seq | Mock advances `period_end` into the renewal window; user renews and mock confirms payment | Banner appears at `period_end − grace_days`; renew opens checkout; after mock `renewal_paid`, refresh extends `valid_until` and the banner disappears |
| T-E7 | e2e-seq | Mock advances past `period_end` unpaid, then past `grace_until` | Banner becomes the `past_due` warning naming `grace_until`; after `grace_until` the flag self-expires offline and the suspended surface renders |
| T-E8 | e2e-seq | From the suspended surface, complete a mock reactivation payment | `renewal-checkout` → pay → status poll returns active with fresh receipt → flag reactivates; chrome returns |
| T-E9 | e2e-seq | Wipe local storage (reinstall), re-enter purchase surface against the same mock order | Mock answers `409 order_exists`; surface offers reactivate; activation completes with no checkout and no payment |
| T-X1 | x-e2e | Real local AP + ABO + clinic Supabase: full purchase and activation, then one real AI request | ABO `orders` row `provisioned` with `provisioned_at` set; AP `entitlement` `active` with `order_id` / `purchase_proof_id`; clinic flag `enrolled: true`; Flutter chrome enabled; the guard admits a staff AAT request and a response streams |
| T-X2 | x-e2e | Catalogue-driven picker: operator edits price/copy and adds a plan on the real platform, then reopens the picker | Picker reflects the change within the cache window with zero app changes; grep of the built app finds no plan name, price, or copy (§4.1.6 rule) |
| T-X3 | x-e2e | Renewal against the real order clock (clock advanced to `period_end − grace_days`) | Real cron pre-issues `checkout_url`; banner appears; real sandbox/mock payment → webhook → `renew` → entitlement period starts at the old `period_end` (early payer keeps remaining days, §6.4); receipt refresh extends `valid_until` |
| T-X4 | x-e2e | Dunning propagation as the real order clock advances unpaid | Order flips `past_due` with `grace_until`; banner warning renders; at `grace_until` the real `entitlement_suspend` outbox row lands; the real guard denies the next AI request; the clinic flag self-expires at `valid_until` with no network |
| T-X5 | x-e2e | Reactivation after the real suspension with a new payment | `renewal-checkout` → real payment → `renew` runs `[paid_at, +1 month]`; entitlement `active`; Flutter reactivates end-to-end with no vendor contact |
| T-X6 | x-e2e | Reinstall recovery against the real ABO | Fresh app install re-runs purchase → real `409 order_exists` → reactivate path activates via status + receipt only; no second charge exists in the provider sandbox |
| T-X7 | x-e2e | Receipt self-heal after a real platform receipt-key rotation (§3.5) | Platform serves `rcpt-2` and signs with it; clinic's first `set_ai_availability` fails unknown-`kid`; Flutter re-fetches `/v1/platform-keys`, seeds, retries once; flag activates; no operator action clinic-side |
| T-X8 | x-e2e | Retired-plan renewal on the real stack | Operator retires the plan; order clock logs `renewal_checkout_skipped_plan_retired` and writes no checkout (adapter spy); banner requires plan selection from the live catalogue; `renewal-checkout` → pay → `renew` applies the new plan on the same `order_id` |

### 3.10 Band U — Docs, probes, and viewer

**What this band does:** Rewrites the operator-facing documentation to the CAT world (no bearer
anywhere, D1-level recovery), with docs-as-tests so every example executes; and aligns the
`ai-platform-viewer` commercial views to the A17 invoice shape.

**Useful to know:** Last band, because it documents and drives what exists. U1 needs N3 (the CLI
and runbook it documents) and R3 (the ops surface); U2 needs M2 (the invoice shape). U1 also
carries the two optional governance patches this plan deliberately does **not** fold into code
slices: the A16 item 1 wording ("demoted to break-glass" → "removed", an AP-ARCH amendment
reviewed as a contract change) and the constitution wording patch (§6 below). Both are doc edits
against governance files, reviewed on their own.

**Code sync (verified against the repository as of 2026-09-13):**
- `docs/architecture/ai-platform/04-ai-platform-operator-runbook.md` and the data-journey stage
  3/4 docs (`data-journey/05-stage-3-…`, `06-stage-4-…`) instruct bearer-based control-plane calls.
- The `ai-platform-viewer` invoice views render the pre-A17 shape (`credit_price_version`,
  `total`); the viewer's plan-catalogue CRUD predates the price/display/`grace_days` columns, and
  `specs/060-viewer-commercial-surface` (V4) is built on that shape.

| ID     | Slice                                                              | Canonical                          | Needs    | Done when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------ | ------------------------------------------------------------------ | ---------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **U1** | Stage 3/4 docs and operator runbook rewritten to CAT, docs-as-tests | ABO §8.1, §13 item 3; A16 item 1    | N3, R3   | The stage 3/4 data-journey docs and the operator runbook contain no bearer-based instruction — `OPERATOR_BEARER_TOKEN` appears only in historical or superseded notes; the runbook gains the D1-level auth-recovery section (`wrangler d1` insert under Cloudflare account IAM) and the `cat-sign` local key-generation recipe; every `curl` example executes verbatim against the local stack under the docs-as-tests harness; the A16 wording patch is proposed as its own reviewed amendment |
| **U2** | Viewer commercial views aligned to A17                              | AP-ARCH A17 item 3; specs/060 (V4)  | M2       | The viewer builds and its invoice list/detail render the A17 invoice shape (`plan`, `amount`, `currency`, credits evidence, `purchase_proof_id`) against the local stack with raw request/response visible; plan-catalogue CRUD carries price, display copy, and `grace_days`; no `credit_price` CRUD remains; the V4 slice's invoice clauses are amended to this shape                                                                                                                          |

#### 3.10.1 Band U — verification work

| ID | Layer | Scenario | Expected result |
|---|---|---|---|
| U1-V1 | unit | Docs-as-tests harness extraction over the rewritten stage 3/4 docs and operator runbook | Every `curl`/probe example is extracted; the extracted-example count is pinned so a silently dropped example fails the harness |
| U1-V2 | unit | Each extracted example executes verbatim against the local stack | Documented response status and body shape returned for every example; no example requires hand-editing to run |
| U1-V3 | unit | Bearer grep over the rewritten docs | `OPERATOR_BEARER_TOKEN` and bearer-based invocations appear only inside marked historical/superseded notes; every control-plane example authenticates with `Authorization: CAT` |
| U1-V4 | unit | Drift canary: a deliberately broken fixture example (wrong route/shape) is fed to the harness | Harness fails CI and names the doc and example — proving the harness executes examples rather than skimming them |
| U1-V5 | unit | Documented error examples (401 unauthorized, 404, 409 cases in the docs) | Each error example returns exactly the documented error body/code against the local stack |
| U1-V6 | unit | `cat-sign` recipe from the runbook | Keypair generation + CAT signing execute as written; the local control plane accepts the signed CAT; the private key never appears in any output, log, or shell history artifact (grep) |
| U1-V7 | unit | D1-recovery section of the runbook | Executed once end to end: operator key revoked/lost → control calls 401 → `wrangler d1` insert of a new `control_operator` row under account IAM → control access restored; no standing recovery credential exists afterward |
| U1-V8 | unit | Dual-registry provisioning script recipe (§4.1.8) | Script registers the operator public key into `control_operator` and `ops_operator` atomically; a forced mid-script failure leaves neither registry written |
| U1-V9 | unit | Governance patches carried by U1 | The A16 item 1 wording patch ("demoted to break-glass" → "removed") and the constitution wording patch each exist as standalone reviewed diffs against governance files, not folded into code slices |
| U2-V1 | unit | Viewer build | `ai-platform-viewer` builds clean against the post-M2 platform |
| U2-V2 | unit | Invoice list rendering | List renders the A17 shape per row: `plan`, `amount`, `currency`, credits consumed as evidence, `purchase_proof_id`; no `credit_price_version` / `total` field is referenced |
| U2-V3 | unit | Invoice detail navigation | Detail view follows the chain invoice → purchase proof → order by id; each hop resolves against the local stack |
| U2-V4 | unit | Plan-catalogue CRUD in the viewer | Create/edit carry `price_cents`, `currency`, `display_name`, `description`, `grace_days`; validation rejects a missing price or `grace_days` |
| U2-V5 | unit | `credit_price` absence | Grep over the viewer source finds no `credit_price` CRUD, route, or model |
| U2-V6 | unit | Raw request/response visibility | Every commercial view can show the raw request and response it rendered from (V4 surface rule) |
| U2-V7 | unit | specs/060 (V4) amendment | The V4 slice's invoice clauses are amended to the A17 shape; the amendment diff is reviewable on its own |
| U-E1 | e2e-seq | Bootstrap the local stack exactly per the rewritten runbook (AP + ABO + clinic Supabase) | Stack healthy; the runbook's own bootstrap commands are the ones executed (harness log proves provenance) |
| U-E2 | e2e-seq | Execute every stage-3 doc example verbatim, in document order, against the running stack | All stage-3 examples pass; state created by earlier examples is what later examples consume |
| U-E3 | e2e-seq | Execute every stage-4 doc example verbatim, building on U-E2 state | All stage-4 examples pass, including the CAT-authenticated control-plane calls that replaced bearer examples |
| U-E4 | e2e-seq | Runbook operator chain: `cat-sign` → CAT control call → audit read | The CAT call succeeds; `control_audit.operator_id` carries the operator's `iss`; the doc's claimed attribution is verified in data |
| U-E5 | e2e-seq | D1-recovery drill verbatim from the runbook | Operator key loss → all control calls 401 → `wrangler d1` insert → access restored; the drill leaves the stack fully functional for subsequent steps |
| U-E6 | e2e-seq | Rotation runbook chains for all three key domains (purchase-proof, CAT, receipt), executed as written | Each rotation's both-sides procedure completes with the script-enforced overlap waits; mid-rotation the system keeps serving (old-key window); post-rotation the old key is retired |
| U-E7 | e2e-seq | Viewer smoke chain against the running stack | Build → open → invoice list → invoice detail with raw response → plan CRUD round-trip carrying price/display/`grace_days` |
| U-X1 | x-e2e | Full docs-as-tests pass against the real combined local stack (AP + ABO + clinic Supabase + viewer) | Every example in every rewritten doc executes green in one run; CP-ABO-4's "operable by its docs" question is answered by this artifact |
| U-X2 | x-e2e | Viewer renders invoices produced by a real purchase → real period close on the combined stack | Invoice rows show the A17 shape with amounts equal to what the real purchase actually paid (from the consumed proof, not the catalogue); the invoice → proof → order chain navigates to the real ABO order id |
| U-X3 | x-e2e | Post-recovery ops: after the D1-recovery drill, the recovered operator issues a real comp order via `POST /v1/ops/comp-orders` | Comp order provisions a clinic end to end with `comp_operator_id` attribution; proves the recovery restored operational capability, not just read access |
| U-X4 | x-e2e | Receipt-key rotation runbook executed live while a clinic is mid-period on the combined stack | Clinic self-heals via the unknown-`kid` refetch path with no operator action clinic-side; old key retired after the overlap; the runbook's claims match observed behaviour step by step |

### 3.11 Coverage rule

The AP plan's §3.11 is adopted by reference — happy path of every requirement, one case per error
code, every branch of every rule, every inherited invariant, every named boundary; behavioural, not
line-based; *spy* assertions where the invariant is about work not done. This plan adds three
band-specific rules:

1. **Verification orders are tested step by step.** For §5.3 (orders), §5.5 (webhooks), §5.6
   (CAT), §5.7 (purchase proof), and §5.8 (receipt), each verification step has at least one case
   that passes every earlier step and fails at that one.
2. **Cross-deployable contract artifacts are executable.** The §6.7 coherence matrix, the §4.1.6
   catalogue rule (`GET /v1/plans` serves exactly `status = 'active'` rows with price and
   `grace_days`), and the §7.1 provider-quarantine rules are consumed by tests on both sides, not
   restated in prose.
3. **Every 4xx mapping that means "a prior attempt committed" is tested as success, not failure.**
   The outbox processor's handling of `409 already_enrolled` / `409 not_pending` /
   `409 purchase_proof_replayed` (§11.1) is where double-provisioning would hide.

Every slice's suite joins CI permanently. A checkpoint (§4) requires every prior suite green, not
just the latest.

Each band section above ends with a verification-work subsection (§3.2.1–§3.10.1) tabulating that
band's full behavioral matrix. The `Layer` column distinguishes three layers, each with its own ID
scheme: `unit` rows (`<slice>-V<n>`, e.g. `O2-V13`) are behavioral unit/integration tests on a
single deployable; `e2e-seq` rows (`<band>-E<n>`, e.g. `R-E5`) form one sequential end-to-end chain
against a single deployable's real local stack, where each step reuses the state left by the
previous steps; and `x-e2e` rows (`<band>-X<n>`, e.g. `T-X4`) are cross-service scenarios requiring
both AP and ABO running — plus the clinic Supabase and the Flutter app where the flow reaches them.
The per-slice test floors of §3.12 are the minimum gate — every floor case is subsumed and extended
by the band tables — while the per-band verification tables are the full behavioral matrix each
band's specs expand into named test cases.

### 3.12 Required test cases per slice

#### 3.12.1 Band M

| ID | Layer | Required cases |
| --- | --- | --- |
| **M1** | SQL / migration + integration | *Migration:* applies cleanly to an empty database and over the existing catalogue; snapshot pinned including `grace_days DEFAULT 7`; `credit_price` absent from the snapshot. *Code:* no `credit_price` reference remains in `src/` (grep test); the deleted endpoint returns 404; plan CRUD round-trips the new fields with `control_audit` rows; non-operator rejected. *Bug fix:* delete removes the `plan` row and writes the audit row; deleting an unknown plan still 404s |
| **M2** | Scheduled job + integration | *Close:* an invoice is priced from the seeded consumed proof's `amount_cents` / `currency`; a catalogue price change between periods never reprices a closed period; credits consumed are recorded as evidence; re-run idempotent; no paid grant → no invoice. *Shape:* invoice carries `plan`, `amount`, `currency`, `purchase_proof_id`; the chain invoice → proof → order is navigable by query. *Spec:* 059's banner cites A17 and this plan, FR-023..025 withdrawn |
| **M3** | Docs verification (CI) | Scripted diff of doc 16 against `schema.snap.sql` passes (every table, every column); doc 18's DO state matches `src/quota-do/`; no `credit_price` mention survives in either doc |

#### 3.12.2 Band N

| ID | Layer | Required cases |
| --- | --- | --- |
| **N1** | Unit + contract | Sign/verify round trip; `alg` confusion rejected (`none`, HS256); base64url codec vectors; timing-safe compare rejects unequal-length and differing strings; `EnrolledKeyVerifier` behaviour unchanged — the existing AAT suites pass against the extracted package with no test edits |
| **N2** | Workers integration + SQL | *CAT 401 matrix:* happy path per action class; one 401 case each for expired, future-`iat`, lifetime > 120 s, wrong `aud`, wrong `act`, `act` not in `allowed_actions`, wrong `tgt`, wrong body hash, unknown `kid`, revoked key, `jti` replay, malformed structure, wrong `alg`. *Bearer:* a bearer attempt on any control route → 401 because the credential no longer exists; no `OPERATOR_BEARER_TOKEN` reference remains in code or `wrangler.toml`. *Audit:* `control_audit.operator_id` carries the CAT `iss`. *Schema:* migrations apply cleanly; snapshot pinned; `jti` purge cron deletes only expired rows |
| **N3** | CLI + script + runbook | `cat-sign` generates a keypair and signs a CAT the local control plane accepts; the private key never appears in any output or log; the provisioning script writes both registries atomically (a forced mid-script failure leaves neither); the runbook's recovery procedure is executed once against the local stack — operator key loss → `wrangler d1` insert → control access restored |

#### 3.12.3 Band O

| ID | Layer | Required cases |
| --- | --- | --- |
| **O1** | SQL / migration + unit | *Schema:* columns and partial UNIQUE index present; legacy null-`order_id` rows untouched; snapshot pinned. *Verifier:* one reject case per §5.7 verification-order step, each passing all earlier steps; validity-window edges (`not_before` / `not_after`); unknown `kid`; wrong `iss`; every rejection writes nothing |
| **O2** | Workers integration | *Gating:* enroll/entitle/override without a proof and with a forged proof → reject with no writes; replay → `409 purchase_proof_replayed` with the grant fully rolled back; `order_id` reuse across two installations → UNIQUE failure. *Enroll:* body `kid`/`public_key`/`plan` mismatch against claims → reject; an `org_id` collision under a different installation id no longer dedups; unknown or retired catalogue plan → reject. *Kinds:* `entitle` with `kind = renewal` → reject; `override` with `kind = purchase` → reject; `override` with `kind = comp` succeeds. *Audit:* every grant's audit row carries `order_id` |
| **O3** | Workers integration | *Renew:* on `pending` → `409 not_renewable`; missing → `404 entitlement_not_found`; on `active` the new period starts at the current `period_end` (early payer keeps remaining days); on `suspended` the period runs `[paid_at, +1 month]`; economics resolve from the catalogue, never the proof; proof consumed batch-atomically. *Suspend:* `active → suspended` under CAT alone; on `suspended` → `409 illegal_lifecycle_transition`; the guard rejects a suspended entitlement with the existing codes and no guard diff; no entitlement-resume route exists — renew is the only reactivation path |

#### 3.12.4 Band P

| ID | Layer | Required cases |
| --- | --- | --- |
| **P1** | Workers integration | *Status:* `pending` entitlement → no receipt; both active → receipt verifies against the served key set; wrong-`aud` / expired / unknown-`kid` receipts fail closed at a verifying fixture; suspended installation → taxonomy `installation_suspended`; unauthenticated → taxonomy `401`; `valid_until = period_end + grace_days` from the catalogue; `platform_base_url` claim present; no journal row and no DO round trip per call; warm isolate pays no D1 read. *Keys:* `platform-keys` serves the var as a JWK set, unauthenticated, cacheable |
| **P2** | Workers integration + contract | *Contract:* seeded active + retired + disabled plans — the response contains exactly the `status = 'active'` rows, each with `price_cents` / `currency` / `display_name` / `description` / `grace_days`; `Cache-Control: public, max-age=300`; identical for every caller; unauthenticated. *Docs:* the AP-ARCH §13.4 diff names all four new vars/secrets |

#### 3.12.5 Band Q

| ID | Layer | Required cases |
| --- | --- | --- |
| **Q1** | Infra / config + contract | Each environment deploys with its own D1 and secrets; health endpoint returns build and environment identity; no binding shared between environments; a missing required secret fails at startup. *Catalogue cache:* cold isolate fetches once; warm isolate serves from memory inside 300 s; expiry refetches exactly once; fetch failure → `502 catalogue_unavailable`; no plan or price table exists in `migrations/` (grep test) |
| **Q2** | Workers integration + SQL | *PoP:* valid order accepted; invalid signature → `400 invalid_signature`; tampered payload bytes rejected (verification over exact bytes); `issued_at` older than 24 h rejected; malformed `public_key` rejected; missing fields → `400 invalid_payload`. *Catalogue:* unknown or retired plan → `404 plan_not_found`; catalogue fetch failure → `502 catalogue_unavailable`. *Live-order guard:* duplicate live order → `409 order_exists` carrying the existing `order_id` and no new poll token; a terminal-state order allows repurchase. *Poll token:* returned once, only its hash stored; wrong token and unknown order both → `404`; timing-safe compare used (spy). *Schema:* migrations apply cleanly; snapshot pinned; partial unique index present. *Style:* every error body is the flat `{"error": …}` shape |
| **Q3** | Adapter fixtures + Workers integration | *Checkout:* intention-create golden; Unified Checkout URL composition; refs stored only in `provider_refs`. *Webhook fixtures:* valid HMAC → processed; invalid HMAC → rejected before any write; duplicate delivery → `200` with no re-processing; an authentic payload with an old provider timestamp is still processed (no timestamp gate); unresolvable provider ref → `webhook_events` row with null `order_id`. *Mapping:* `success=true` → `payment_succeeded`; `success=false` → `payment_failed`; `is_refunded` → `refunded`; `is_voided` → ignored; the Paymob adapter never emits `chargeback` (documented gap). *Quarantine:* the §7.1 rule-4 contract test greps order/proof/outbox serializers for adapter imports and fails on any. *Handoff:* a success webhook enqueues the outbox row with the JWS in `payload` and triggers the processor via `ctx.waitUntil` (spy) |

#### 3.12.6 Band R

| ID | Layer | Required cases |
| --- | --- | --- |
| **R1** | Workers integration (fake platform client) | *Triggering:* producer `waitUntil` processes a fresh row immediately; the sweeper recovers a row whose immediate attempt was dropped; the atomic claim prevents double-processing under a concurrent trigger + sweep. *Backoff:* retry schedule honoured; cap 10 → `failed` + alert log; a failed platform call never marks a row `done`. *409 mappings:* `already_enrolled` / `not_pending` / `purchase_proof_replayed` → confirming `quota-inspect` read → row `done` (§3.11 rule 3). *CAT:* claims per §5.6 with exactly the orchestrator scope; a fresh `jti` per call. *Ledger:* retries re-present the identical JWS from `payload`; `done` rows are never purged; `orders.provisioned_at` set on completion |
| **R2** | Workers integration (clock) + endpoint | *Clock:* renewal checkout issued at `period_end − grace_days` using the catalogue value (a changed `grace_days` changes the next run's behaviour with no code edit); skipped with `renewal_checkout_skipped_plan_retired` when the plan is not sellable and no adapter call is made (spy); skipped with `renewal_checkout_skipped_key_rotated` after clinic key rotation; `past_due` flip sets `grace_until`; `entitlement_suspend` enqueued at `grace_until` and awaited inline; `expired` at `period_end + grace_days + 30 days`; expired checkouts cancelled. *Renewal-checkout:* poll-token auth with uniform `404`; valid while `provisioned` / `past_due`; terminal order → `409 illegal_state`; retired target plan → `404 plan_not_found`; rotated keys → `409 key_rotated`; catalogue failure → `502 catalogue_unavailable`; provider failure → `502 provider_error` |
| **R3** | Workers integration + script | *Comp orders:* per-operator token accepted; unknown / revoked / wrong-`aud` token → 401; `jti` replay → 401; comp order flows `pending → paid → provisioned` with `comp_operator_id` recorded and zero expected payout; no shared ops bearer exists (grep test). *Reconciliation:* seeded drift of each kind produces the right `reconciliation_alert` (`payment_without_entitlement`, `entitlement_without_payment`, `payout_mismatch`); every §6.7 coherent pair produces no alert and every non-listed pair alerts (matrix consumed as a contract artifact); a payout reversal against a provisioned order (the Paymob chargeback path) alerts; settlement-lag tolerance excludes periods closed < 3 days; no alerts HTTP endpoint exists. *Self-check:* boot fails fast on `kid` or issuer mismatch and emits a structured alert. *Rotation script:* each key domain's both-sides procedure runs with the overlap wait enforced between phases |

#### 3.12.7 Band S

| ID | Layer | Required cases |
| --- | --- | --- |
| **S1** | SQL / pgTAP | Owner/admin gate → `FORBIDDEN`; no active key → `INSTALLATION_NOT_ENROLLED`; blank plan → `INVALID_INPUT`; the payload contains exactly the §5.2 fields; the returned signature verifies over the exact payload bytes with the row's public key; nothing is recorded by the call; deny-all RLS unchanged |
| **S2** | SQL / pgTAP | *Replacement:* the old boolean signature is absent after the migration. *Receipt accept/reject matrix:* valid receipt activates and writes `platform_base_url` / `valid_until`; one reject case each for bad signature, wrong `aud`, unknown `kid`, revoked `kid`, wrong `iss`, non-`active` status → `INVALID_RECEIPT` (one code); expired receipt → `RECEIPT_EXPIRED`. *Deactivate:* `NULL` always deactivates for owner/admin. *Self-expiry:* `get_ai_availability` returns `enrolled: false` past `valid_until` with the stored row untouched. *Key set:* add validates 32-byte base64url; duplicate kid upserts; last-key revocation refused (`CANNOT_REVOKE_LAST_PLATFORM_KEY`); deny-all RLS unchanged |
| **S3** | SQL / pgTAP | Wrapped columns populated for existing rows; the plaintext column is absent; `issue_ai_token` still mints verifying AATs; `create_ai_order` still signs; `ai.key_wrap_id` recorded in `app_settings`; no RPC signature changed; deny-all RLS unchanged |

#### 3.12.8 Band T

| ID | Layer | Required cases |
| --- | --- | --- |
| **T1** | Flutter widget + CI lint | *Picker:* renders from a fetched catalogue; fetch failure → normal empty/retry state, never an error dialog; no plan name, price, or copy in the app binary (grep). *Purchase:* full state machine sign → order → persist → browser → poll; `(order_id, poll_token)` in secure storage and never in clinic Postgres; cancel abandons and clears state; poll timeout abandons. *Lint:* a fixture containing the ABO origin fails the build; a provider payment hostname fails; a clean tree passes |
| **T2** | Flutter widget + local-stack E2E | *Activation:* first activation seeds keys, polls to `active`, and flips the flag via `set_ai_availability(receipt)`; unknown-`kid` failure re-fetches keys and retries exactly once. *Refresh:* receipt refresh runs on app start and inside the 3-day window; `valid_until` extends after a renewal paid from another device. *Dunning:* banner appears at `period_end − grace_days`; retired-plan banner requires plan selection and an explicit `renewal-checkout` call (no silent old-tier charge); `past_due` warning names `grace_until`; post-suspension the flag self-expires with no network and the pay-to-reactivate path completes with no vendor contact. *Recovery:* reinstall → `409 order_exists` → reactivate path activates without a checkout |

#### 3.12.9 Band U

| ID | Layer | Required cases |
| --- | --- | --- |
| **U1** | Docs-as-tests | Every `curl` example in the rewritten docs executes verbatim against the local stack; no bearer-based instruction remains outside historical/superseded notes (grep); the D1-recovery procedure is executed once end to end; the A16 wording patch is a standalone reviewed diff |
| **U2** | Viewer build + smoke | The viewer builds; invoice list/detail render the A17 shape against the local stack with raw request/response visible; plan CRUD carries price, display copy, and `grace_days`; no `credit_price` CRUD remains (grep) |

### 3.13 Master end-to-end verification chain

The master end-to-end verification chain for the ABO introduction — the final acceptance gate
(CP-ABO-3, satisfying the AP plan's CP7). One ordered chain where every step builds on the state
of all previous steps, with all four deployables running (ABO + AP + clinic Supabase + Flutter)
against a provider sandbox/mock. "Clock advance" means the local stack's time control (cron
invocation with injected time); the order clock reads `grace_days` from the live catalogue.
Negative branches follow as short chains MC-N1…; each starts from the healthy state of the main
chain step it cites and must leave that state unaltered.

State legend per step: **ABO** = `orders` row / outbox; **AP** = `entitlement` row / audit;
**Clinic** = `ai.availability` flag; **Flutter** = rendered UI state.

#### 3.13.1 Master E2E chain

| Step | Services | Action | Expected state after step |
|---|---|---|---|
| MC-01 | clinic+Flutter | Fresh clinic: bootstrap Supabase, run Stage-2 keypair enrollment (`enroll_installation_keypair()`) from the app | ABO: no order rows. AP: installation key enrolled, no `entitlement` row. Clinic: flag `enrolled: false`, installation keypair present (secret wrapped per §3.6). Flutter: purchase surface visible (hide-without-probing gate open) |
| MC-02 | AP+ABO+Flutter | Seed the plan catalogue on AP (one active plan with `price_cents` / `currency` / `grace_days = 7`); open the Flutter plan picker | AP: `plan` row active; `GET /v1/plans` serves it with price and `grace_days`. ABO: catalogue cache populates on first fetch (cold isolate, one fetch). Flutter: picker renders the plan entirely from the response |
| MC-03 | Flutter+clinic+ABO | `create_ai_order(plan)` → `POST /v1/orders` | Clinic: RPC returns payload+signature, records nothing. ABO: `orders` row `pending` with as-purchased `installation_id` / `kid` / `public_key` snapshot, stored `order_payload` bytes, `provider_refs` row, `checkout_url` set; poll token returned once, only its SHA-256 hash stored; outbox empty. Flutter: pair persisted in secure storage, system browser opened on the checkout URL, visible cancelable waiting state |
| MC-04 | provider | Pay the hosted checkout in the provider sandbox/mock | Provider: payment recorded against the intention. ABO/AP/clinic/Flutter: unchanged (no client-side trust of the redirect URL, §5.5) |
| MC-05 | provider→ABO | Provider delivers the success webhook | ABO: HMAC verified; `webhook_events` row inserted; order `pending → paid`; purchase proof minted (`kind = purchase`, bound `installation_id` + key material, paid `amount_cents` / `currency`); outbox `provision` row enqueued with the JWS in `payload`; processor triggered via `ctx.waitUntil`. Flutter: poll observes `paid` |
| MC-06 | ABO→AP | Outbox processor runs `enroll` then `entitle`, each with a fresh orchestrator-scoped CAT and the identical proof JWS | AP: `entitlement` row created `pending` then `active` with plan economics from the catalogue, `order_id` set, proof consumed batch-atomically (`purchase_proof` row inserted); `control_audit` rows carry `operator_id = orchestrator` and `order_id`. ABO: order `provisioned`, `provisioned_at` set, outbox row `done`. Clinic/Flutter: not yet changed |
| MC-07 | Flutter+AP+clinic | Activation pull: mint staff AAT → seed `GET /v1/platform-keys` → poll `GET /v1/installation/status` → `set_ai_availability(receipt)` | AP: status serves both-active with a signed receipt (`valid_until = period_end + grace_days`, `platform_base_url` claim). Clinic: `ai.platform_receipt_keys` seeded; flag written `{ enrolled: true, platform_base_url, valid_until }`. Flutter: AI chrome enabled for all staff on next flag read |
| MC-08 | Flutter+AP | Staff issues a real AI request through the guard | AP: guard admits (entitlement `active`); SSE response streams; Quota DO counters increment. Flutter: response renders; usage gauge reflects consumption |
| MC-09 | AP+Flutter | Usage metering check: continue requests; read the usage summary | AP: quota consumption and journal rows accumulate against the open period; usage summary endpoint reflects them. Flutter: usage surface matches server-reported consumption |
| MC-10 | ABO+Flutter | Advance the clock to `period_end − grace_days`; run the order clock | ABO: plan still sellable and key material still matches → renewal checkout pre-issued, `checkout_url` non-null on the order. Flutter: "Renew AI" banner appears (driven by status `period_end` and the order poll) |
| MC-11 | Flutter+provider+ABO+AP+clinic | Pay the renewal from the banner; webhook → renewal proof → `renew` | ABO: order stays `provisioned` with new period bounds; second `webhook_events` row; new proof (`kind = renewal`, same `order_id`, new `purchase_proof_id`). AP: `renew` sets the new period starting at the old `period_end` (early payer keeps remaining days, §6.4), consumes the new proof, audits with `order_id`; Quota DO resets counters on the bound change. Clinic: refreshed receipt extends `valid_until`. Flutter: banner disappears |
| MC-12 | AP | Run period close for the first (now-closed) period | AP: `invoice` row in the A17 shape priced from the consumed proof's `amount_cents` / `currency` (never a catalogue re-lookup); the chain invoice → proof → order is navigable by query to the real ABO order id |
| MC-13 | ABO+Flutter+AP | Non-payment path: advance the clock past the new `period_end` with no renewal; run the order clock | ABO: order `provisioned → past_due`, `grace_until = period_end + grace_days` set. AP: entitlement still `active` (grace — service continues by policy, §6.3); guard still admits. Flutter: banner becomes the `past_due` warning naming `grace_until` |
| MC-14 | ABO+AP+clinic+Flutter | Advance past `grace_until`; run the order clock | ABO: `entitlement_suspend` outbox row fired and awaited inline, row `done`. AP: entitlement `active → suspended`; the guard denies the next AI request with the existing codes (no guard diff). Clinic: flag self-expires at `valid_until` (= `grace_until`) with no network. Flutter: AI chrome hides; purchase surface shows "suspended — pay to reactivate" |
| MC-15 | Flutter+provider+ABO+AP+clinic | Reactivate: `renewal-checkout` from the suspended surface → pay → webhook → `renew` | ABO: order `past_due → provisioned`, period `[paid_at, paid_at + 1 month]` (§6.4). AP: entitlement `suspended → active` via `renew` (the only reactivation path); proof consumed; guard admits again. Clinic: fresh receipt reactivates the flag. Flutter: chrome returns — full reactivation with no vendor contact |
| MC-16 | provider→ABO+AP+clinic+Flutter | Issue a refund/chargeback on the latest payment in the provider sandbox | ABO: webhook (`refunded`) or reconciliation-detected chargeback → order `refunded` (terminal); `entitlement_suspend` fired immediately — no grace (§6.1/§6.3). AP: entitlement `suspended`; guard denies at once. Clinic: flag persists only until `valid_until`, but no AI request succeeds regardless (guard re-checks per request). Flutter: order poll shows the terminal state; pay-to-reactivate surface renders |
| MC-17 | clinic+Flutter+ABO+AP | Clinic key rotation mid-life: rotate the installation keypair, then attempt `renewal-checkout` on the existing order | ABO: key-material re-validation against the platform fails → `409 key_rotated`, no adapter call (§5.4). Flutter: starts a fresh order with a newly signed payload (new `kid` / `public_key`). Payment → proof carrying the new key material → platform grant path reactivates service bound to the rotated key; AATs mint only under the new key |
| MC-18 | AP+ABO+Flutter+provider | Plan catalogue change: operator retires the current plan and adds a replacement on AP; advance into the next renewal window | AP: `GET /v1/plans` serves only the new plan. ABO: order clock logs `renewal_checkout_skipped_plan_retired` and writes no checkout (adapter spy: no call). Flutter: banner offers plan selection from the live catalogue; explicit `renewal-checkout` with the new plan → pay → `renew` applies the new plan and catalogue economics on the same `order_id`; `orders.plan` updated on payment |
| MC-19 | ABO+AP+clinic(2)+Flutter(2) | Comp order for a second clinic: second clinic enrolls a keypair; operator signs an ops token (`cat-sign`, `aud = ai-billing-orchestrator-ops`) → `POST /v1/ops/comp-orders` | ABO: order `pending → paid → provisioned` with `amount = 0`, `comp_operator_id` recorded, zero provider interaction; `ops_jti` consumed in the same batch. AP: entitlement `active` via comp proof (`kind = comp`); audit attributes the operator. Clinic 2: activates via the same pull flow. Flutter 2: chrome enabled |
| MC-20 | ABO+AP+provider | Run daily billing reconciliation over the whole exercise (all three §11.3 directions) | Zero `reconciliation_alert` rows: every paid/provisioned/past_due order has a coherent entitlement per the §6.7 matrix; every audit grant carries an existing `order_id`; every payout traces to an order and every provisioned order to a payout, with the comp order at expected payout zero and the refunded order coherent (`refunded` × `suspended`) |
| MC-21 | AP+ABO | D1-recovery drill: revoke/lose the operator's `control_operator` key; attempt control calls; recover per the runbook | AP: all control calls 401 (credential gone, no bearer fallback exists). Recovery: `wrangler d1` insert of a new `control_operator` row under Cloudflare account IAM → control access restored; same drill for `ops_operator` on the ABO. No standing recovery credential exists afterward; the drill is the runbook executed verbatim |
| MC-22 | AP+clinic+Flutter | Receipt key rotation with clinic self-heal: add `rcpt-2` to `PLATFORM_RECEIPT_PUBLIC_KEYS`, switch the signing secret, keep serving both | AP: `GET /v1/platform-keys` serves both keys; new receipts sign as `rcpt-2`. Clinic: first `set_ai_availability` with a `rcpt-2` receipt fails unknown-`kid`. Flutter: re-fetches `/v1/platform-keys`, seeds `rcpt-2`, retries once → flag activates; no clinic-side operator action. After the overlap window the old key is retired from the served set and revoked clinic-side (last-key revocation still refused) |

#### 3.13.2 Negative branches

| Step | Services | Action | Expected state after step |
|---|---|---|---|
| MC-N1 | provider→ABO | From MC-05 state: deliver a forged webhook (valid shape, bad HMAC) | Rejected before any write: no `webhook_events` row, no order transition, no outbox row, no proof minted; order still `pending`; provider-side retry semantics preserved (4xx) |
| MC-N2 | attacker→AP | From MC-06 state: call `entitle` / `renew` directly with a self-signed (forged) purchase proof | Platform verification order rejects (unknown `kid` / bad signature / wrong `iss`); no writes — no entitlement change, no `purchase_proof` row, no audit row; guard state unchanged |
| MC-N3 | attacker→AP | From any state: call `/control/v1/*` with no token, and again with a legacy bearer token | Both 401 `{"error":"unauthorized"}`; the bearer fails because the credential no longer exists anywhere in code or config (grep-pinned); no control route is reachable without a `control_operator` key |
| MC-N4 | attacker→AP | From MC-06 state: re-present the already-consumed purchase proof JWS to `entitle` / `renew` | `409 purchase_proof_replayed`; the grant batch rolls back completely — entitlement, audit, and proof table unchanged; the single consumed row remains the only record |
| MC-N5 | attacker→clinic+AP | From MC-07 state: (a) present a tampered receipt (modified claim / bad signature) to `set_ai_availability`; (b) flip `ai.availability` directly in the DB | (a) `INVALID_RECEIPT` — one code, no oracle; stored flag untouched. (b) The old boolean RPC does not exist (dropped by S2); even a directly flipped flag yields no AI access — the guard re-checks entitlement per request and denies |
| MC-N6 | Flutter+ABO | From MC-06 state (live order exists): attempt a second `POST /v1/orders` for the same installation (double-sell) | `409 order_exists` carrying the existing `order_id` and **no** new poll token; the partial unique index holds; no second checkout, no second `provider_refs` row, no double charge possible |
| MC-N7 | attacker→ABO+AP | From MC-05 state: take installation A's paid order / purchase proof and present it for installation B (enroll/renew with B's path id or body) | Rejected at the binding checks: proof `installation_id` ≠ path id, and enroll body `kid` / `public_key` / `plan` must equal the claims; no writes for B; A's order and entitlement untouched |
| MC-N8 | provider→ABO | From MC-05 state: redeliver the authentic success webhook verbatim (duplicate delivery, original old timestamp) | `200` with no re-processing: idempotency on `(provider, provider_event_id)` is the authoritative replay guard; no second proof, no second outbox row, no timestamp-based rejection of the legitimate redelivery |
| MC-N9 | attacker→AP+ABO | From MC-19/MC-21 state: replay a captured CAT (same `jti`) against a control route, and replay a captured ops token against `POST /v1/ops/comp-orders` | Both 401: `control_cat_jti` insert-if-absent conflict on the platform; `ops_jti` replay guard on the ABO — the comp-order write and the `jti` insert are one batch, so a replay writes nothing |

#### 3.13.3 Open questions surfaced by verification design

Designing the verification matrices surfaced places where the architecture is silent. Each is a
spec-time decision for the owning slice — resolve them during spec authoring (§5), not at the
keyboard. Verification rows marked below assumed the *italicized* answer; if the spec decides
otherwise, amend the row.

1. **Zero-usage paid period (M2-V7):** does period close still issue an invoice? *Assumed yes* —
   A17 prices the subscription, not usage.
2. **Comp period at amount 0 (M2-V8):** does close issue a zero invoice? *Assumed yes* (§6.5
   "expected payout zero").
3. **Refund-suspended entitlement at period close:** invoiced or skipped? *Unspecified.*
4. **Missing-proof rejection and UNIQUE `order_id` violation error codes (O2):** the architecture
   says "reject with no writes" but names no codes. *Rows use generic codes; pin them in the O2
   spec.*
5. **Override on a `pending` entitlement (O2-V15):** §5.7 pins only `kind = comp`; no state rule.
   *Assumed allowed (today's `handleOverride` accepts any status).*
6. **Enroll proof kind set (O-X8):** §6.2's diagram allows `purchase | comp` at enroll; §5.7 does
   not restate it. *Assumed comp-at-enroll is accepted.*
7. **CAT `jti` burn timing (N2-V19/V20):** whether the `jti` insert shares the auth batch or the
   handler batch changes failure semantics. *Rows follow §5.6's verification order + §5.1's
   co-location rule.*
8. **Malformed `PLATFORM_RECEIPT_PUBLIC_KEYS` entry (P1-V21):** drop the entry or fail the whole
   response? *Unspecified.*
9. **Far-future `issued_at` on orders (Q2-V6):** §5.3 defines only the 24 h age rejection.
10. **Extra fields in `order_payload` (Q2-V7):** the signature verifies over exact bytes;
    post-parse rejection policy for unknown fields is unspecified.
11. **Missing `Authorization` header on order poll (Q2-V13):** *assumed* uniform 404, matching
    wrong-token behavior.
12. **Out-of-order webhook disposition (Q3-V10):** logged with no transition, but `processed` vs
    `failed` row status and pre-reconciliation surfacing are unspecified.
13. **409-confirm contradiction (R1-V5):** when the confirming `quota-inspect` read contradicts
    the 409, *assumed* not-`done` + normal retry/alert path.
14. **Refund webhook after terminal expiry (R2-V10):** *assumed* record-only (row in
    `webhook_events`, no state change, no outbox row).
15. **Duplicate platform-key `kid` upsert semantics (S2-V13):** *assumed* the upsert refreshes
    `added_at` and clears `revoked_at`.
16. **Reactivation dispatch (MC-17):** for a paid order on an existing suspended entitlement, the
    outbox processor's choice between `enroll → entitle` (which 409s / requires `pending`) and
    `renew` is never explicit. *Assumed `renew` (§6.4); pin the dispatch rule in the R1 spec.*
17. **Proactive chrome hiding on refund (MC-16):** the guard denies immediately, but whether
    Flutter hides AI chrome on observing `refunded`/`suspended` or waits for flag self-expiry at
    `valid_until` is not pinned (§10.3).
18. **E1 lint vs the ABO origin (T1-V15/V18):** the origin is a vendor-published constant the app
    must call, yet the lint fails the build on the ABO origin in client code. *Assumed: allowed
    only in its single designated constant; any other occurrence fails.*
19. **Clock control in x-e2e (T-X3/X4, MC-10/13/14):** the local-stack time-travel mechanism
    (injected cron time vs waiting) is unspecified; the harness must define it.

---

## 4. Review Checkpoints

A checkpoint is a point at which the *composition* of the preceding slices is examined, rather than
any single slice (AP plan §5). It is not a gate on shipping, because nothing ships; it is a gate on
continuing to build in the same direction.

| #          | After                    | Question the checkpoint answers                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ---------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **CP-ABO-1** | N2                     | Is the control plane CAT-only? Every control route authenticates per-caller keys from `control_operator`, the CAT 401 matrix is green, `control_audit` attributes real identities — and a bearer-token attempt fails because the credential no longer exists anywhere in code, config, or docs-in-scope                                                                                                                                                  |
| **CP-ABO-2** | P2                     | Is the platform's commercial read surface complete and single-sourced? `GET /v1/plans` serves exactly the active rows with price and `grace_days` (the §4.1.6 contract test), status/platform-keys are live, AP-ARCH §13.4 names every new var and secret, and `credit_price` is gone from code, schema, and docs                                                                                                                                          |
| **CP-ABO-3** | R3, with S2 and T2     | **The end-to-end falsification checkpoint (satisfies the AP plan's CP7).** A throwaway clinic completes purchase → pay → activate against the local stack with no human in the loop; a forged purchase proof fails; a bearer-token grant attempt fails because the bearer no longer exists; a comp order provisions with operator attribution; and billing reconciliation of the whole exercise finds zero drift against the §6.7 coherence matrix. The verification instrument is the master end-to-end chain of §3.13: MC-01…MC-22 executed in order across all four deployables, plus the negative branches MC-N1…N9        |
| **CP-ABO-4** | U2                     | Is the system operable by its docs? Docs-as-tests is green, the viewer drives the commercial surface in the A17 shape, and the runbook's D1-level recovery procedure has been executed once against the local stack (operator key loss → `wrangler d1` insert → access restored)                                                                                                                                                                            |

At CP-ABO-1 and CP-ABO-3, also perform the R-19/R-20 review the AP plan requires at its
checkpoints: diff the implemented components against §4 of AP-ARCH and §2/§4 of the ABO
architecture, and confirm nothing was added without its trigger.

---

## 5. Spec Authoring Protocol

The AP plan's §6 is adopted by reference — transcription not design (§6.1), the required spec
sections (§6.2), stop conditions (§6.3), and the never-do list (§6.4) — with these deltas:

1. **Implements** cites sections of `02-architecture.md` and, where applicable, AP-ARCH amendments
   (A15/A16/A17), copied from the slice's `Canonical` column here.
2. **Escalation** means amending `02-architecture.md` (ABO-owned decisions) or AP-ARCH
   (platform-owned decisions) first, then returning. A slice never patches either document.
3. The never-do list gains four ABO-specific entries:
   - Introduce a shared bearer or any standing, unattributed credential anywhere — control plane,
     ops surface, or docs (§8.1, §11.2).
   - Add a plan, price, entitlement-mirror, or usage table to the ABO (§4.1.6); the catalogue is
     read through the cached `GET /v1/plans` fetch or the request fails `502 catalogue_unavailable`.
   - Let a provider identifier, event name, or enum value cross the adapter boundary (§7.1) — the
     contract test exists to make this fail.
   - Write order state, vendor credentials, or provider data into the clinic database (§9.5).

---

## 6. Constitution Compliance Check

The governing text is the Operating Constraints amendment in `.specify/memory/constitution.md`
(registered 2026-09-11 for this architecture): a single vendor-operated control service
(`ai-billing-orchestrator/`, Cloudflare Worker + D1, outbox table + Cron Triggers — no queue
infrastructure), vendor-side control plane only, no clinic business data, no write path into any
clinic's Supabase, never on the clinic's request path. This plan conforms:

- **I. Product fit and simplicity** — one new vendor Worker; no queues (outbox table + Cron
  Triggers, §4.1.5); payer-initiated renewal avoids stored-credential machinery (§1).
- **II. Replaceable layer boundaries** — Flutter orchestrates and transports; clinic Postgres owns
  clinic-side integrity; the provider adapter is a port with a contract test pinning the seam
  (§7.1).
- **III. Backend authority** — clinic-side writes stay RPC-enforced under deny-all RLS (Band S);
  the platform's grant path is constraint-enforced (UNIQUE indexes, batch-atomic proof consumption,
  Band O).
- **IV. Secure, human-gated operations** — every grant is two-signature gated and audited with real
  operator identity and order id; human incident response runs on personal scoped CAT keys with
  D1-level recovery under Cloudflare account IAM (§8.1, §13 item 3).
- **V. Operational continuity** — grace before any suspension, AI loss never blocks clinical
  workflows, the clinic flag fails closed, reactivation is self-service (§6.3).

**Optional governance task (not performed by this plan).** The dedup analysis (§4.2, Candidate 2)
recommends a wording PATCH to the amendment: "the AI platform stays additive and never learns about
money" is factually false once the platform stores billing-attested `amount_cents` / `currency` and
issues invoices (A17 item 3). The recommended rewording — *"never collects payments and holds no
payment-provider integration; it records paid amounts solely as billing-attested claims for
invoicing"* — is a constitution amendment of its own, to be proposed and reviewed separately (it is
listed in U1's scope as a docs task). This plan does not edit the constitution.

---

## 7. Dependencies Outside This Plan

| Dependency                                                        | Blocks         | Note                                                                                                                                                                                                                    |
| ----------------------------------------------------------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AP bands A–J implemented (except former band L)                    | M, N, O, P     | Given: the platform code exists as verified in the bands' Code sync blocks; Band G is partially implemented and Band M completes its A17 amendment in flight                                                             |
| Paymob merchant account and dashboard values                       | Q3             | `PAYMOB_SECRET_KEY` / `PAYMOB_PUBLIC_KEY` / `PAYMOB_HMAC_SECRET` / `PAYMOB_INTEGRATION_ID` come from the provider dashboard per environment; sandbox values suffice until production                                    |
| Clinic Stage-2 keypair enrollment in Flutter                       | T1             | Already built (`enroll_installation_keypair()`); the purchase flow assumes it                                                                                                                                            |
| pgsodium available in the clinic Supabase environments             | S1–S3          | The B1 family already depends on it; S3 additionally requires `pgsodium.root_key` custody outside the database for the §3.6 boundary to hold — a clinic-environment property, documented in the slice                       |
| Cloudflare account IAM for the vendor                              | N3, R3, CP-ABO-4 | D1-level recovery and ops bootstrap are `wrangler d1` operations under per-person, Cloudflare-audited IAM; there is deliberately no app-level recovery credential                                                          |

---

## 8. Implementation Status

**Instructions for implementing agents (human or AI).** This section is the single live
progress record for the plan. When you finish a unit of work, update this section **in the
same commit** as the work itself:

1. Change the item's `☐` to `☑` and fill the Evidence column with the date and commit SHA
   (and the test-run reference where relevant).
2. Tick a slice's **Impl** box only when its *Done when* sentence (§3) is fully met.
3. Tick **Unit**, **E2E-seq**, or **X-E2E** only when *every* row of that layer in the
   band's verification table (§3.2.1–§3.10.1) is implemented **and passing** — not a
   subset. Partial progress is recorded only in the Notes column; never tick partially.
4. Tick a master-chain step (§8.2) only after executing it against the real local
   four-deployable stack (AP + ABO + clinic Supabase + Flutter) and observing the expected
   state in every service the row names.
5. Tick a band roll-up (§8.3) only when all its slices are fully ticked; tick a checkpoint
   only after its §4 question has been answered with evidence.
6. Never tick anything without evidence. An unticked box with an honest note is worth more
   than a ticked box without a passing test.

### 8.1 Slice status

| Slice | Impl | Unit | E2E-seq | X-E2E | Evidence (date · commit) | Notes |
|---|---|---|---|---|---|---|
| **M1** — catalogue price/display/`grace_days`, `credit_price` withdrawal, plan-delete fix | ☐ | ☐ | ☐ | ☐ | | |
| **M2** — period-close repricing, invoice reshape, `purchase_proof` table | ☐ | ☐ | ☐ | ☐ | | |
| **M3** — data-journey docs 16/18 drift repair | ☐ | ☐ | ☐ | ☐ | | |
| **N1** — `packages/ed25519-jws/` extraction | ☐ | ☐ | ☐ | ☐ | | |
| **N2** — `control_operator` + CAT auth + bearer removal | ☐ | ☐ | ☐ | ☐ | | |
| **N3** — `cat-sign` CLI, dual-registry provisioning, D1-recovery runbook | ☐ | ☐ | ☐ | ☐ | | |
| **O1** — grant-path schema + shared purchase-proof verifier | ☐ | ☐ | ☐ | ☐ | | |
| **O2** — gated enroll/entitle/override, dedup, catalogue validation | ☐ | ☐ | ☐ | ☐ | | |
| **O3** — `renew` + `entitlement-suspend` | ☐ | ☐ | ☐ | ☐ | | |
| **P1** — `GET /v1/installation/status` + `GET /v1/platform-keys` | ☐ | ☐ | ☐ | ☐ | | |
| **P2** — `GET /v1/plans` + §13.4 registration | ☐ | ☐ | ☐ | ☐ | | |
| **Q1** — ABO skeleton, config inventory, catalogue cache | ☐ | ☐ | ☐ | ☐ | | |
| **Q2** — billing schema, `POST`/`GET /v1/orders` | ☐ | ☐ | ☐ | ☐ | | |
| **Q3** — Paymob adapter + webhook endpoint | ☐ | ☐ | ☐ | ☐ | | |
| **R1** — outbox consumer, CAT minter, sweeper | ☐ | ☐ | ☐ | ☐ | | |
| **R2** — order clock, dunning, renewal-checkout | ☐ | ☐ | ☐ | ☐ | | |
| **R3** — ops surface, reconciliation, self-check, rotation script | ☐ | ☐ | ☐ | ☐ | | |
| **S1** — `create_ai_order` signing RPC | ☐ | ☐ | ☐ | ☐ | | |
| **S2** — receipt-verified `set_ai_availability` + key seed RPCs | ☐ | ☐ | ☐ | ☐ | | |
| **S3** — pgsodium key wrapping | ☐ | ☐ | ☐ | ☐ | | |
| **T1** — plan picker + purchase flow + E1 lint | ☐ | ☐ | ☐ | ☐ | | |
| **T2** — activation pull + renewal/dunning UX + reinstall recovery | ☐ | ☐ | ☐ | ☐ | | |
| **U1** — stage 3/4 docs + runbook rewrite (CAT, docs-as-tests) | ☐ | ☐ | ☐ | ☐ | | |
| **U2** — viewer invoice views aligned to A17 shape | ☐ | ☐ | ☐ | ☐ | | |

### 8.2 Master end-to-end chain status

Tick each step only after executing it in order against the real local stack (rule 4).
Negative branches may be executed in any order after the chain step they fork from.

| Step | Done | Evidence (date · run) |
|---|---|---|
| MC-01 | ☐ | |
| MC-02 | ☐ | |
| MC-03 | ☐ | |
| MC-04 | ☐ | |
| MC-05 | ☐ | |
| MC-06 | ☐ | |
| MC-07 | ☐ | |
| MC-08 | ☐ | |
| MC-09 | ☐ | |
| MC-10 | ☐ | |
| MC-11 | ☐ | |
| MC-12 | ☐ | |
| MC-13 | ☐ | |
| MC-14 | ☐ | |
| MC-15 | ☐ | |
| MC-16 | ☐ | |
| MC-17 | ☐ | |
| MC-18 | ☐ | |
| MC-19 | ☐ | |
| MC-20 | ☐ | |
| MC-21 | ☐ | |
| MC-22 | ☐ | |
| MC-N1 | ☐ | |
| MC-N2 | ☐ | |
| MC-N3 | ☐ | |
| MC-N4 | ☐ | |
| MC-N5 | ☐ | |
| MC-N6 | ☐ | |
| MC-N7 | ☐ | |
| MC-N8 | ☐ | |
| MC-N9 | ☐ | |

### 8.3 Band and checkpoint roll-up

| Band / checkpoint | Done | Evidence (date · commit) |
|---|---|---|
| **Band M** — A17 economics execution | ☐ | |
| **Band N** — control-plane caller identity | ☐ | |
| **Band O** — purchase-proof-gated grants | ☐ | |
| **Band P** — provisioning receipt and commercial read surface | ☐ | |
| **Band Q** — ABO purchase module | ☐ | |
| **Band R** — ABO orchestrator module | ☐ | |
| **Band S** — clinic Supabase | ☐ | |
| **Band T** — Flutter purchase and activation | ☐ | |
| **Band U** — docs, probes, and viewer | ☐ | |
| **CP-ABO-1** — CAT-only control plane (after N2) | ☐ | |
| **CP-ABO-2** — commercial read surface single-sourced (after P2) | ☐ | |
| **CP-ABO-3** — end-to-end falsification (after R3, with S2 and T2) | ☐ | |
| **CP-ABO-4** — operable by its docs (after U2) | ☐ | |
