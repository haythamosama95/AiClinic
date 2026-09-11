# Contract: Invoice evidence (G4)

**Frozen by:** Slice G4 — Billing period close and invoice generation
**Implements:** §7.3, §12.3 Billing, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices may **extend** this contract; they may not **rewrite** it
(Delivery Plan §2.3). V4 renders rollup evidence over this join path.

**Source of truth in code:** D1 queries in G4 tests and any helper used by
`ai-platform/src/period-close/index.ts` to read evidence. No new HTTP read surface in this
slice.

**Traces to:** spec FR-010, FR-015, FR-016, FR-019; Freezes in `spec.md` Slice Contract
(*Invoice evidence*).

**Consumes (unchanged):** F3 `usage_rollup` production (dimensions JSON
`{ installation_id, period }`, `quota_weight`, `tokens`, `cost`, `request_count`); A5
`usage_event` (`installation_id`, `period`, `request_id`, `quota_weight`) and `ai_request`
(`request_id`, `request_reference`).

---

## 1. Overview

An invoice resolves to its `usage_rollup` rows for that installation and period. Any such row
(the invoice line) traces through `usage_event` request id to request references. Payment
collection remains outside: the platform issues the invoice document and does not integrate a
payment provider.

Credits consumed on the invoice come from the `usage_rollup.quota_weight` aggregate. Actual
tokens and cost on the ledger remain billing evidence and MUST NOT determine the invoice debit
(FR-010).

There is no `invoice_line` table. There is no freeze column on `usage_rollup`.

---

## 2. Invoice → rollup lines

Given `invoice.installation_id` and `invoice.period`, the lines are:

```sql
SELECT rollup_id, dimensions, request_count, quota_weight, tokens, cost
  FROM usage_rollup
 WHERE json_extract(dimensions, '$.installation_id') = ?
   AND json_extract(dimensions, '$.period') = ?
```

`credits_consumed` on the invoice MUST equal `SUM(quota_weight)` of those rows (FR-010,
FR-015). Close MUST NOT rewrite those rows (FR-006).

---

## 3. Line → request references

Given a line (`usage_rollup` row) for that installation and period, contributing ledger rows
are `usage_event` rows with the same `installation_id` and `period`. Each contributing
`usage_event.request_id` resolves to `ai_request.request_reference` (FR-016):

```sql
SELECT ue.request_id, ar.request_reference
  FROM usage_event ue
  JOIN ai_request ar ON ar.request_id = ue.request_id
 WHERE ue.installation_id = ?
   AND ue.period = ?
   AND ue.request_id IS NOT NULL
```

Journal-retention nulling of `usage_event.request_id` (F3) is unchanged; evidence tests seed
live request ids.

---

## 4. Payment boundary

No payment-provider call exists on close or on price-list activation (FR-019; §12.3 Billing;
§4.5). There is no payment-provider error path because no call exists. This freeze spies
absence of a call; it does not introduce a payment-provider port.

---

## 5. What this freeze does not include

| Concern | Owner |
| --- | --- |
| Rollup production / reconciliation | F3 (`usage-rollup-reconciliation.md`) |
| Invoice list/detail rendering | V4 |
| Usage-summary gauge | G3 (out of scope) |
| Token-rate artifact (`src/pricing/`) | Existing; not invoice evidence |
