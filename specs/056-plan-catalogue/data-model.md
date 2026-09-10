# D1 Logical Model (G1) — plan catalogue and credit-denominated entitlement

## Table of Contents

1. [Overview](#1-overview)
   - [1.1 Purpose](#11-purpose)
   - [1.2 Migration artifacts](#12-migration-artifacts)
   - [1.3 Relationship to A5](#13-relationship-to-a5)
2. [Entity catalog](#2-entity-catalog)
   - [2.1 `plan`](#21-plan)
   - [2.2 `credit_price`](#22-credit_price)
   - [2.3 `entitlement` (extended)](#23-entitlement-extended)
3. [Pending non-null shape](#3-pending-non-null-shape)
4. [Writers and readers](#4-writers-and-readers)
5. [Consumer binding](#5-consumer-binding)
6. [Deliberately absent](#6-deliberately-absent)

---

## 1. Overview

### 1.1 Purpose

This artifact documents the D1 entities **G1 creates or extends**: `plan`, `credit_price`, and
the entitlement monthly credit-budget column (frozen admission snapshot name **`credit_budget`**),
plus `max_cost_class` on `entitlement` so assignment can persist the §7.3 field A5 omitted from
the physical table. It is the binding surface for later slices — not prose in the architecture
doc. Field lists follow `docs/architecture/ai-platform/01-ai-platform.md` §7.3 and A15, and the
G1 Freezes.

### 1.2 Migration artifacts

| Artifact | Path |
| --- | --- |
| Forward migration | `ai-platform/migrations/20260911120000_plan_catalogue.sql` |
| DDL snapshot | `ai-platform/schema.snap.sql` (updated to include `plan`, `credit_price`, and the new entitlement columns) |

Migrations are forward-only and additive (A5 discipline; §13.4). Enroll's INSERT list does not
change: new entitlement columns use `NOT NULL DEFAULT` so pending rows stay complete.

### 1.3 Relationship to A5

A5's shipped platform schema (`20260731120000_platform_schema.sql`) and
`specs/019-ai-context-keys-d1-config/data-model.md` catalogued `entitlement` without a credit
column and without `plan` / `credit_price` tables. G1 creates those forward-only. A5's
`data-model.md` is **not** rewritten (delivery plan §2.3).

No foreign key from `entitlement.plan` to `plan.name`: enroll writes the plan name before a
catalogue row exists (A15; Consumes B2).

---

## 2. Entity catalog

### 2.1 `plan`

The commercial catalogue — what a named plan includes (A15; §7.3).

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `name` | TEXT | NOT NULL | Primary key — the plan name enroll already stores on `entitlement.plan` |
| `credit_budget` | INTEGER | NOT NULL | Monthly credit budget (quota unit = AI credit; A15) |
| `request_quota` | INTEGER | NOT NULL | Request-count guard |
| `max_cost_class` | TEXT | NOT NULL | Plan ceiling copied onto entitlement at assignment |
| `soft_threshold` | REAL | NOT NULL | Soft-limit threshold (same fraction contract B2/I4 already use) |
| `allowed_capabilities` | TEXT | NOT NULL | Capability set as JSON array text (same encoding as `entitlement.allowed_capabilities`) |
| `status` | TEXT | NOT NULL | Persisted; this slice does not freeze a closed enum (spec Assumptions) |

**Growth:** a handful of rows. **Retention:** full history — delete journals `control_audit` and
does not `DELETE` the row.

**First write:** G1 plan CRUD. **Config cache:** kind `"plans"` (see
[`contracts/plan-catalogue.md`](./contracts/plan-catalogue.md)).

### 2.2 `credit_price`

The versioned credit price list (A15; §7.3). Answers "what does the clinic pay per credit". It is
**not** the bundled token-rate pricing artifact under `ai-platform/src/pricing/` (FR-020).

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `version` | TEXT | NOT NULL | Primary key |
| `price_per_credit` | REAL | NOT NULL | Price per AI credit |
| `currency` | TEXT | NOT NULL | Currency code |
| `active_from` | TEXT | NOT NULL | Activation instant (ISO-8601); G4 is the first writer that activates |
| `activated_by` | TEXT | NOT NULL | Operator identity that activated the version (G4) |

**Growth:** a handful of rows ever. **Retention:** full history.

**This slice:** creates the empty table. No G1 control mutation inserts or activates rows.
**Config cache:** not a cached kind — the request path never sees a price (A15; FR-019).

Wire shape: [`contracts/credit-price.md`](./contracts/credit-price.md).

### 2.3 `entitlement` (extended)

A5/B2 already persist: `entitlement_id`, `installation_id`, `plan`, `period_start`,
`period_end`, `request_quota`, `token_budget`, `cost_budget`, `allowed_capabilities`,
`soft_threshold`, `status`. G1 adds:

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `credit_budget` | INTEGER | NOT NULL | **Frozen admission snapshot name.** Monthly credit budget. Default `0` so enroll/pending stay non-null. Token and cost budgets keep their meanings (A15). |
| `max_cost_class` | TEXT | NOT NULL | §7.3 field assignment copies from `plan.max_cost_class`. Default `''` (empty, analogous to empty capability set) so enroll does not change. |

**Status** remains `pending` / `active` / `suspended` (B2 freeze). Assignment moves `pending` →
`active` (FR-011).

**Config cache:** existing kind `"entitlements"`; the cached row includes `credit_budget` after
this migration (`SELECT *` already returns new columns).

G2 extends B4's `EntitlementSnapshot` with `credit_budget`; G1 does **not** modify the Quota DO.

---

## 3. Pending non-null shape

Every entitlement column stays non-null throughout (§7.3). After G1's migration, a B2 enroll row
is:

| Column | Pending value |
| --- | --- |
| `status` | `pending` |
| `plan` | Name from the enroll payload |
| `request_quota` | `0` |
| `token_budget` | `0` |
| `cost_budget` | `0` |
| `credit_budget` | `0` (column default) |
| `allowed_capabilities` | `[]` |
| `soft_threshold` | `0` |
| `max_cost_class` | `''` (column default) |
| `period_start` / `period_end` | Enrollment instant (B2 freeze) |

Assignment copies catalogue economics onto that row in one mutation and sets `status = 'active'`.

---

## 4. Writers and readers

| Entity / column | Writer in G1 | Reader in G1 |
| --- | --- | --- |
| `plan` | Operator plan CRUD (`src/control/plan.ts`) | Assign-plan (`handleEntitle`); config cache kind `"plans"` |
| `credit_price` | None (table exists for G4) | None on the request path |
| `entitlement.credit_budget` / `max_cost_class` | Assign-plan (from catalogue); override may set budget | Config cache kind `"entitlements"` |
| `control_audit` | Every plan CRUD, assign-plan, and override | Not cached |

The request path (guard / Quota DO) does not gain new reads in this slice.

---

## 5. Consumer binding

| Slice | What it binds from this model |
| --- | --- |
| **G2** | `entitlement.credit_budget` as the monthly budget admission debits; token/cost columns unchanged in meaning |
| **G4** | `credit_price` rows (activation + invoice pricing); must not confuse with `src/pricing/` |
| **V4** | Plan CRUD mutations and the catalogue rows they write |

---

## 6. Deliberately absent

- **`invoice` table** — G4.
- **FK `entitlement.plan` → `plan.name`** — enroll is plan-name-only.
- **`credit_price` cache kind** — prices stay on the control plane.
- **Quota DO / `EntitlementSnapshot` fields** — G2.
- **Overage / debit / period-close columns** — G2 / G4.
