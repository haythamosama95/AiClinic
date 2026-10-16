# D1 Logical Model (G4) — `invoice`

## Table of Contents

1. [Overview](#1-overview)
   - [1.1 Purpose](#11-purpose)
   - [1.2 Migration artifacts](#12-migration-artifacts)
   - [1.3 Relationship to G1 and F3](#13-relationship-to-g1-and-f3)
2. [Entity catalog](#2-entity-catalog)
   - [2.1 `invoice`](#21-invoice)
3. [Resolution of consumed credits and price](#3-resolution-of-consumed-credits-and-price)
4. [Writers and readers](#4-writers-and-readers)
5. [Consumer binding](#5-consumer-binding)
6. [Deliberately absent](#6-deliberately-absent)

---

## 1. Overview

### 1.1 Purpose

This artifact documents the D1 entity **G4 creates**: `invoice`. It is the binding surface
for later slices (V4 renders list/detail; Band L collects payment outside this platform) —
not prose in the architecture doc. Field lists follow `docs/architecture/ai-platform/01-ai-platform.md`
§7.3 and A15, and the G4 Freezes. G1 `credit_price` and F3 `usage_rollup` / `usage_event`
are consumed, not redefined.

### 1.2 Migration artifacts

| Artifact | Path |
| --- | --- |
| Forward migration | `ai-platform/migrations/20260911200000_invoice.sql` |
| DDL snapshot | `ai-platform/schema.snap.sql` (updated to include `invoice`) |

Migrations are forward-only and additive (A5 discipline; FR-020).

### 1.3 Relationship to G1 and F3

G1 created `credit_price` empty of activation rows (`specs/056-plan-catalogue/data-model.md`
§2.2; `contracts/credit-price.md`). G4 is the first writer that INSERTs a version. G1's
data-model and credit-price contract are **not** rewritten (delivery plan §2.3).

F3 produces `usage_rollup` from `usage_event` (`specs/041-support-retention-rollups/contracts/usage-rollup-reconciliation.md`).
G4 reads those rows as invoice evidence and does not rewrite them. No freeze column is added
to `usage_rollup`.

---

## 2. Entity catalog

### 2.1 `invoice`

One issued invoice per installation per period (A15; §7.3). Growth: one per installation per
month. Retention: long — billing evidence.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `installation_id` | TEXT | NOT NULL | Installation the invoice belongs to. Part of the primary key. |
| `period` | TEXT | NOT NULL | Calendar month (`YYYY-MM`), the same period key F3 stores on `usage_event.period` / `usage_rollup.dimensions`. Part of the primary key. |
| `credits_consumed` | INTEGER | NOT NULL | Consumed credits evidenced by `SUM(usage_rollup.quota_weight)` for this installation and period. Ledger tokens and cost MUST NOT determine this value (FR-010). |
| `credit_price_version` | TEXT | NOT NULL | `credit_price.version` active for the period — the latest row whose `active_from` is at or before the period start (FR-023). |
| `total` | REAL | NOT NULL | `credits_consumed * credit_price.price_per_credit` for that version. Not computed from `src/pricing/` (FR-017). |
| `status` | TEXT | NOT NULL | Persisted. This slice writes `"issued"` on insert and never updates the row. It does not freeze a closed enum (spec Assumptions; same discipline G1 used for `plan.status`). |
| `issued_at` | TEXT | NOT NULL | ISO-8601 instant the close wrote the row. |

**Primary key:** `(installation_id, period)` — the natural key named by §7.3 Growth ("One per
installation per month") and FR-007 / FR-011. A re-run `INSERT` conflicts and is a no-op
(`ON CONFLICT DO NOTHING`); existing columns are not mutated.

**Immutability:** no UPDATE of an issued row. Activating a later `credit_price` version MUST
NOT change `credit_price_version` or `total` on a closed period (FR-014).

**First write:** G4 scheduled period close. **Config cache:** not a cached kind — invoices are
issued on the control plane; the request path never sees a price (FR-018).

Wire shape: [`contracts/invoice.md`](./contracts/invoice.md).

---

## 3. Resolution of consumed credits and price

Close does not invent a default price or currency (FR-024).

| Input | Rule |
| --- | --- |
| Entitlement | Invoice only installations whose `entitlement.status` is `active` (FR-007). |
| Credits consumed | `SUM(usage_rollup.quota_weight)` for `json_extract(dimensions, '$.installation_id')` and `json_extract(dimensions, '$.period')` matching the close period. Zero (or no rows) → no invoice (FR-012). |
| Price list | Latest `credit_price` row with `active_from` ≤ period start (`{period}-01T00:00:00.000Z`). A version whose `active_from` falls inside or after the period MUST NOT apply (FR-023, FR-025). None → no invoice (FR-024). |
| Total | Product of credits consumed and that row's `price_per_credit`. Currency stays on `credit_price`; it is not an `invoice` column (§7.3 invoice field list). |

---

## 4. Writers and readers

| Entity / column | Writer in G4 | Reader in G4 |
| --- | --- | --- |
| `invoice` | Scheduled `runPeriodClose` (`src/period-close/index.ts`) | Evidence resolution (SELECT by installation + period); re-run conflict check |
| `credit_price` | Operator `handleCreditPriceActivate` (`src/control/credit-price.ts`) | Close, to resolve the version active for the period |
| `usage_rollup` | None (F3 remains the writer) | Close (credits consumed) and evidence (lines) |
| `usage_event` / `ai_request` | None | Evidence trace: rollup line → `usage_event.request_id` → `ai_request.request_reference` |
| `entitlement.status` | None | Close filters `active` |
| `control_audit` | Price-list activation only (close is scheduled, not an operator HTTP mutation) | Not cached |

The request path (guard / Quota DO) does not gain reads or writes in this slice (FR-018).

---

## 5. Consumer binding

| Slice | What it binds from this model |
| --- | --- |
| **V4** | Invoice rows and their `usage_rollup` evidence; list and detail rendering |
| **Band L** | Payment collection remains outside; this table is the issued document, not a payment record |

---

## 6. Deliberately absent

- **`invoice_line` table** — a line is a `usage_rollup` row (spec Assumptions; FR-015).
- **Freeze column on `usage_rollup`** — freeze means close does not rewrite F3 rows (FR-006).
- **`invoice_id` surrogate** — the natural key is `(installation_id, period)`.
- **Currency column on `invoice`** — currency lives on `credit_price` (§7.3).
- **Closed `status` enum / CHECK** — persisted TEXT only.
- **`credit_price` cache kind** — G1 freeze; prices stay on the control plane.
- **Payment-provider columns or FK** — no payment-provider integration (FR-019).
- **FK `credit_price_version` → `credit_price.version`** — not named; do not add one.
- **Gauge / debit / overage columns** — G2 / G3 / FR-022.
