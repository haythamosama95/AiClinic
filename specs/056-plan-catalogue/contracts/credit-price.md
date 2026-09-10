# Contract: Versioned credit price list table (G1)

**Frozen by:** Slice G1 — Plan catalogue and credit-denominated entitlement
**Implements:** §7.3, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices may **extend** this contract; they may not **rewrite** it
(Delivery Plan §2.3). G4 is the first slice that **activates** a version and writes `invoice`.

**Source of truth in code:** `ai-platform/migrations/20260911120000_plan_catalogue.sql`
(`CREATE TABLE credit_price`).

**Traces to:** spec FR-007, FR-009, FR-019, FR-020; Freezes in `spec.md` Slice Contract.

**Entity binding:** [`../data-model.md`](../data-model.md)

---

## 1. Overview

`credit_price` is the versioned credit price list. It answers **"what does the clinic pay per
credit"**. It is a **different table with a different job** from the bundled token-rate pricing
artifact that answers "what did this request cost us" (`ai-platform/src/pricing/`, unchanged)
(A15 item 5; FR-020).

The request path never sees a price. This list lives with the control plane (A15; FR-019).

G1 **creates the table**. It does not insert rows, set `activated_by`, or issue invoices.

---

## 2. Row shape

| Field | Meaning |
| --- | --- |
| `version` | Price-list version (PK) |
| `price_per_credit` | Clinic price per AI credit |
| `currency` | Currency |
| `active_from` | Instant from which this version is active |
| `activated_by` | Operator who activated the version |

**Growth:** a handful of rows ever. **Retention:** full history.

---

## 3. What this freeze does not include

| Concern | Owner |
| --- | --- |
| Activating a version (writing `activated_by` / `active_from` as an audited operator mutation) | G4 |
| `invoice` entity and period close | G4 |
| Debit of `credit_budget` | G2 |
| Bundled token-rate artifact (`src/pricing/`) | Existing; not this table |

No config-cache kind is defined for `credit_price`.

---

## 4. Consumers

| Slice | Binding |
| --- | --- |
| **G4** | Activates a version; prices closed-period invoices through the version active for that period; must not reprice a closed period; must not treat `src/pricing/` as this list |
