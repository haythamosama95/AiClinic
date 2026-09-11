# Contract: `invoice` entity (G4)

**Frozen by:** Slice G4 — Billing period close and invoice generation
**Implements:** §7.3, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices may **extend** this contract; they may not **rewrite** it
(Delivery Plan §2.3). V4 renders list/detail over these rows. Band L collects payment outside
this platform.

**Source of truth in code:** `ai-platform/migrations/20260911200000_invoice.sql`
(`CREATE TABLE invoice`).

**Traces to:** spec FR-007, FR-009, FR-011, FR-020; Freezes in `spec.md` Slice Contract
(*The `invoice` entity*).

**Entity binding:** [`../data-model.md`](../data-model.md)

---

## 1. Overview

`invoice` is one issued invoice per installation per period. This slice is the first writer.
The row is immutable once issued: a re-run of close and a later `credit_price` activation MUST
NOT change it.

---

## 2. Row shape

| Field | Meaning |
| --- | --- |
| `installation_id` | Installation the invoice belongs to |
| `period` | Calendar month (`YYYY-MM`) |
| `credits_consumed` | Consumed credits from that installation and period's `usage_rollup.quota_weight` aggregate |
| `credit_price_version` | `credit_price.version` active for the period |
| `total` | Credits consumed × that version's price per credit |
| `status` | Persisted TEXT; close writes `"issued"`; no closed enum in this slice |
| `issued_at` | Instant the close wrote the row |

**Growth:** one per installation per month. **Retention:** long — billing evidence.

**Primary key:** `(installation_id, period)`.

---

## 3. Invariants

| Invariant | Rule |
| --- | --- |
| Cardinality | Exactly one row per (`installation_id`, `period`) when an invoice is issued (FR-007) |
| Idempotent re-run | A second close MUST NOT insert a second row and MUST NOT mutate the existing row (FR-011) |
| Immutability | No UPDATE of issued columns; a new price-list version MUST NOT reprice a closed period (FR-014) |
| Zero consumption | No row when consumed credits are zero (FR-012) |
| No applicable price | No row when no `credit_price` has `active_from` at or before the period start (FR-024) |

---

## 4. What this freeze does not include

| Concern | Owner |
| --- | --- |
| Scheduled close algorithm | [`period-close.md`](./period-close.md) |
| Price-list activation HTTP | [`price-list-activation.md`](./price-list-activation.md) |
| Evidence joins to `usage_rollup` / `usage_event` / `ai_request` | [`invoice-evidence.md`](./invoice-evidence.md) |
| Invoice list/detail UI | V4 |
| Payment collection | Band L / outside the platform (FR-019) |

No config-cache kind is defined for `invoice`. No invoice HTTP read surface is defined in this
slice.

---

## 5. Consumers

| Slice | Binding |
| --- | --- |
| **V4** | Reads issued rows for list and detail |
| **Band L** | Payment remains outside; this row is the issued document |
