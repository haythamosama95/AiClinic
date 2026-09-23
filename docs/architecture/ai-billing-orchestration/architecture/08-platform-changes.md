# AI Billing Orchestration — Platform Changes

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.
**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [8. Platform-side changes](#8-platform-side-changes)
  - [8.1 CAT verification through the existing `OperatorAuth` port](#81-cat-verification-through-the-existing-operatorauth-port)
  - [8.2 Purchase-proof-gated grants](#82-purchase-proof-gated-grants)
  - [8.3 New read surfaces](#83-new-read-surfaces)
  - [8.4 Untouched](#84-untouched)

---

## 8. Platform-side changes

These are recorded as **Amendment A16** in [`../../ai-platform/01-ai-platform.md`](../../ai-platform/01-ai-platform.md) (§2.10) and sliced in
[`../04-abo-delivery-plan.md`](../04-abo-delivery-plan.md); this section is the design summary.
Sequenced after the platform plan catalogue and control-plane prerequisites are in place, per
the proposal — the expected refactor collision point is `src/control/entitle.ts` (proposal §9
finding 1), and existing plan-catalogue assignment logic is reused as-is.

### 8.1 CAT verification through the existing `OperatorAuth` port

The port (`src/control/types.ts`) is the designed injection point, and it is used. One
mechanical change is required and is a recorded deviation (§14, item 2): `resolve` is
synchronous today, but CAT verification needs `crypto.subtle` and a D1 `jti` insert, so the
port becomes:

```ts
export type OperatorAuth = {
  resolve(request: Request, action: string): Promise<OperatorPrincipal | null>;
};
```

`requireOperator(request, operatorAuth, action)` gains the action argument and an `await` at
each handler — the call sites' shape is otherwise unchanged, and dispatch
(`src/control/index.ts`) is untouched except for the two new routes. Exactly one factory
remains:

- `createCatOperatorAuth({ db, … })` — the only production path (§5.6 verification order).

The legacy `createSecretOperatorAuth` bearer factory and its break-glass action set are
**deleted, not demoted**: every `/control/v1/*` caller — orchestrator or human — authenticates
with a personal CAT key registered in `control_operator`, and there is no composite wiring in
`worker.ts`. A shared, non-attributed bearer is the exact anti-pattern §11.2 refuses for the
ABO's own ops surface; the platform does not keep it either. The one genuine residual the
bearer covered — auth-system failure (a corrupted `control_operator` table, or all operator
keys lost) — is answered at the D1 level: an operator with Cloudflare account IAM inserts a
new `control_operator` row via `wrangler d1`, the same bootstrap mechanism the ABO uses for
`ops_operator` (§4.1.8). No standing credential exists to leak.

Human operators sign CATs with a small local CLI
(`ai-platform/scripts/cat-sign`, alongside the key-generation recipe); the private key never
leaves the operator's machine, and the viewer may grow the same capability later.

`control_audit.operator_id` becomes the CAT `iss` — real per-caller attribution (proposal §4.7),
with `order_id` added on grant actions (§4.2).

### 8.2 Purchase-proof-gated grants

- `enroll` — body shrinks to `{ purchase_proof, org_id, display_name, region }`;
`kid`/`public_key`/`plan` come from the purchase proof claims (§5.7), and the orchestrator
reads `org_id` / `display_name` / `region` from the order's stored `order_payload` bytes at
orchestration time — they are not `orders` columns (§4.1.2). Dedup is tightened to
`installation_id` **only** (§13 item 2): the `org_id` OR-clause in `handleEnroll`'s
existence check is removed; `org_id` remains stored metadata. Plan validation changes from
the hardcoded `isKnownPlanTier` list to a `plan`-catalogue lookup (`status = 'active'`),
which the plan catalogue makes possible.
- `entitle` — requires `{ purchase_proof }` with `kind ∈ {purchase, comp}`; economics still
resolve from the catalogue exactly as enroll/entitle already do; the batch gains the `purchase_proof` insert
and the entitlement `order_id`/`purchase_proof_id` writes.
- `renew` (new) — `POST /control/v1/installations/{id}/renew`, body `{ purchase_proof }`.
Mechanical extension of `CONTROL_ACTION_PATTERN` + dispatch switch + handler, per the
proposal. Requires entitlement `active` or `suspended` (404 `entitlement_not_found`,
409 `not_renewable` from `pending` — renew is never the first grant). Writes: entitlement
UPDATE (plan, all economics from the catalogue, period from the purchase proof,
`status = 'active'`, `order_id`, `purchase_proof_id`), `purchase_proof` INSERT, audit INSERT with
`order_id`. Response `{ installation_id, status: "active", period_end }`.
- `entitlement-suspend` (new) — `POST /control/v1/installations/{id}/entitlement-suspend`,
body-less. `active → suspended`, else `409 illegal_lifecycle_transition`. CAT-only (no
purchase proof — it grants nothing). Orchestrator scope; human operators use installation
`suspend`/`resume` with their own scoped CAT keys (§6.2).
- `override` — now requires `{ purchase_proof }` with `kind = comp` in addition to its existing
payload (§6.5). Its economics-merging logic is unchanged.



### 8.3 New read surfaces

`GET /v1/installation/status` and `GET /v1/platform-keys` (§5.9). The status endpoint is the
platform's first production **signing** path: the receipt key arrives as the
`PLATFORM_RECEIPT_PRIVATE_KEY` secret, imported as PKCS#8 Ed25519, used only here.

### 8.4 Untouched

Guard pipeline, Quota DO admission contract, plan-catalogue economics and period-close invoicing, `/v1/*` data path,
journal, R2 layout — proposal §4.8, confirmed against the code: nothing in the request path
reads `order_id`, purchase proofs, or receipts.

