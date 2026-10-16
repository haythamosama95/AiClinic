# Contract: Price-list activation (G4)

**Frozen by:** Slice G4 — Billing period close and invoice generation
**Implements:** §4.5, §7.3, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices may **extend** this contract; they may not **rewrite** it
(Delivery Plan §2.3). G1 created the empty `credit_price` table; this slice is the first
activation writer. G1 `contracts/credit-price.md` is **not** rewritten.

**Source of truth in code:** `ai-platform/src/control/credit-price.ts`
(`handleCreditPriceActivate`); dispatch in `ai-platform/src/control/index.ts`.

**Traces to:** spec FR-001, FR-003, FR-004, FR-013, FR-014, FR-025; Freezes in `spec.md`
Slice Contract (*Price-list activation*).

**Consumes (unchanged):** G1 `credit_price` row shape; B2/G1 operator auth and `control_audit`
write pattern (`401 unauthorized` on missing credentials; no new diagnostic code).

---

## 1. Overview

Activating a new `credit_price` version is an audited operator control-plane mutation. It
writes `version`, price per credit, `currency`, `active_from`, and `activated_by`, and journals
`control_audit` with the operator identity. A new version never reprices a closed period.

The request path never sees a price. No config-cache kind is defined for `credit_price` (G1
freeze).

---

## 2. HTTP surface (operator-authenticated)

`POST` only, dispatched through B2 `dispatchControlRequest`. Operator auth is B2
`OperatorAuth` / `requireOperator`. Missing credentials → **`401` `{"error":"unauthorized"}`**
and **no** D1 write (FR-004; Consumes G1/B2).

Malformed JSON → B2 `400 invalid_json`. Missing/invalid fields → B2 `400 invalid_payload`.

| Route | Handler | D1 writes | `control_audit.action` |
| --- | --- | --- | --- |
| `POST /control/credit-price/activate` | `handleCreditPriceActivate` | `credit_price`, `control_audit` | `credit_price_activate` |

`target` on `control_audit` is the price-list `version`. `operator_id` is the resolved operator
principal. `activated_by` on `credit_price` is that same operator identity.

---

## 3. Request body

| Field | Meaning |
| --- | --- |
| `version` | Price-list version (becomes `credit_price.version` PK) |
| `price_per_credit` | Clinic price per AI credit |
| `currency` | Currency |
| `active_from` | Instant from which this version is active (ISO-8601) |

`activated_by` is **not** a client-supplied field; it is taken from the operator principal.

---

## 4. Closed-period and mid-period rules

| Given | Then |
| --- | --- |
| A period already closed with invoices priced through version *V* | Activating a new version leaves those invoices' `credit_price_version` and `total` unchanged (FR-014) |
| A version with `active_from` inside the current unclosed period | Close still prices that period through the latest version with `active_from` at or before the period start; the new version applies only to periods whose start is at or after its `active_from` (FR-025) |

Activation itself does not rewrite `invoice` rows.

---

## 5. What this freeze does not include

| Concern | Owner |
| --- | --- |
| `credit_price` table DDL | G1 (`specs/056-plan-catalogue/contracts/credit-price.md`) |
| Period close and `invoice` insert | [`period-close.md`](./period-close.md) |
| Plan CRUD / assign-plan / override | G1 (unchanged) |
| Payment collection | Outside the platform (FR-019) |

No payment-provider call exists on this mutation.
