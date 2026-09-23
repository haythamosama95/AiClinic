# D1 Logical Model (M1) — A17 catalogue columns and `credit_price` withdrawal

## Table of Contents

1. [Overview](#1-overview)
   - [1.1 Purpose](#11-purpose)
   - [1.2 Migration artifacts](#12-migration-artifacts)
   - [1.3 Relationship to G1](#13-relationship-to-g1)
2. [Entity catalog](#2-entity-catalog)
   - [2.1 `plan` (extended)](#21-plan-extended)
   - [2.2 `credit_price` (withdrawn)](#22-credit_price-withdrawn)
   - [2.3 `control_audit` (unchanged shape)](#23-control_audit-unchanged-shape)
3. [Writers and readers](#3-writers-and-readers)
4. [Delete semantics](#4-delete-semantics)
5. [Consumer binding](#5-consumer-binding)
6. [Deliberately absent](#6-deliberately-absent)

---

## 1. Overview

### 1.1 Purpose

This artifact documents the D1 entities **M1 extends or withdraws**: A17 columns on
platform `plan`, and the removal of `credit_price`. It is the binding surface for later
slices (P2 `GET /v1/plans`, M2 period-close / invoice reshape) — not prose in the
architecture doc. Field lists follow AP-ARCH A17 / §7.3, ABO §4.1.6 / §4.2, and the M1
Freezes in [`spec.md`](./spec.md).

### 1.2 Migration artifacts

| Artifact | Path |
| --- | --- |
| Forward migration | `ai-platform/migrations/20260923120000_catalogue_grace_days.sql` |
| Prior catalogue migration (unchanged) | `ai-platform/migrations/20260911120000_plan_catalogue.sql` |
| DDL snapshot | `ai-platform/schema.snap.sql` (updated: A17 `plan` columns present; `credit_price` absent) |

Migrations are forward-only (A5/G1 discipline). There is no down migration. Existing `plan`
rows survive; `grace_days` backfills via `DEFAULT 7`.

### 1.3 Relationship to G1

G1 created `plan` (economics columns only), `credit_price`, and entitlement
`credit_budget` / `max_cost_class` (`specs/056-plan-catalogue/data-model.md`). M1 **extends**
`plan` and **withdraws** `credit_price`. G1's `data-model.md` and
`contracts/plan-catalogue.md` / `credit-price.md` are **not** rewritten (delivery plan §2.3).
A17-authorized withdrawal of `credit_price` is recorded here and in code deletion.

G1 economics columns on `plan` (`credit_budget`, `request_quota`, `max_cost_class`,
`soft_threshold`, `allowed_capabilities`, `status`) retain their meanings. Plan update that
changes only A17 fields leaves those columns unchanged.

---

## 2. Entity catalog

### 2.1 `plan` (extended)

The commercial catalogue — what a named plan includes (A15), plus subscription price, display
copy, and `grace_days` (A17). The **only** plan and pricing catalogue (ABO §4.1.6; FR-007).

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `name` | TEXT | NOT NULL | Primary key — unchanged from G1 |
| `credit_budget` | INTEGER | NOT NULL | G1 — monthly credit budget |
| `request_quota` | INTEGER | NOT NULL | G1 — request-count guard |
| `max_cost_class` | TEXT | NOT NULL | G1 — cost-class ceiling |
| `soft_threshold` | REAL | NOT NULL | G1 — soft-limit threshold |
| `allowed_capabilities` | TEXT | NOT NULL | G1 — capability set as JSON array text |
| `status` | TEXT | NOT NULL | G1 — persisted TEXT; no closed enum in this slice |
| `price_cents` | INTEGER | NOT NULL\* | **M1** — subscription price in minor units (A17 item 1) |
| `currency` | TEXT | NOT NULL\* | **M1** — currency code (A17 item 1) |
| `display_name` | TEXT | NOT NULL\* | **M1** — display copy (A17 item 1) |
| `description` | TEXT | NOT NULL\* | **M1** — display copy (A17 item 1) |
| `grace_days` | INTEGER | NOT NULL | **M1** — `DEFAULT 7`; single timing source for dunning/grace (A17 item 1; ABO §4.1.6; ABO §4.2). Explicit `0` is representable. |

\*Column nullability for `price_cents` / `currency` / `display_name` / `description` follows the
forward-only migration DDL pinned by the schema snapshot (FR-001, FR-003). Operator create/update
rejects empty `currency` / empty `display_name`, negative or non-integer `price_cents`, and
negative `grace_days` with `400` `invalid_payload` (FR-011). Omitting `grace_days` on create
stores `7` via the schema default (FR-010).

**Growth:** a handful of rows. **Retention:** catalogue delete removes the row (see §4) and
journals `plan_delete` — behavioural fix vs G1's audit-only delete (Delivery Plan §3.2 Code sync).

**Config cache:** existing kind `"plans"`; `SELECT *` returns the new columns after migration.
This slice does not change TTL, miss, or ownership. Public HTTP serve of active rows is P2
(`GET /v1/plans`, ABO §5.10) — out of scope here (FR-017).

### 2.2 `credit_price` (withdrawn)

| Aspect | M1 outcome |
| --- | --- |
| Table | Dropped by the M1 forward-only migration (FR-002; A17 item 2) |
| Control module | `src/control/credit-price.ts` deleted |
| Payload type | `CreditPriceActivatePayload` removed from `types.ts` |
| Route | `POST /control/credit-price/activate` unregistered → **404** |
| `src/` references | No remaining `credit_price` / `CreditPriceActivatePayload` / `credit-price` (FR-005) |

Under the subscription model the clinic pays the plan price per period, never a metered credit
total (A17 item 2). Period-close paid-amount pricing is M2; until then period-close issues no
invoices after `credit_price` reads are stripped (spec Assumptions).

### 2.3 `control_audit` (unchanged shape)

Existing control-plane audit journal (A15 / G1). Plan create/update/delete continue to write
action rows in the same D1 batch as the catalogue mutation:

| Action | When |
| --- | --- |
| `plan_create` | Successful create carrying A17 fields |
| `plan_update` | Successful update (including A17-only field changes) |
| `plan_delete` | Successful delete that removed the `plan` row |

No schema change to `control_audit` in this slice. `operator_id` remains the G1/B2 operator
principal until Band N.

---

## 3. Writers and readers

| Actor | Read | Write |
| --- | --- | --- |
| Operator plan CRUD (`plan.ts`) | Existing row on update/delete | `plan` INSERT/UPDATE/DELETE + `control_audit` |
| Config cache kind `"plans"` | `plan` rows (including A17 columns after M1) | — |
| `GET /v1/plans` (P2, not this slice) | Active rows' price / display / `grace_days` | — |
| ABO purchase module / receipt mint (later bands) | Via P2 catalogue fetch / receipt path | — |
| Period-close (this slice) | Must not read `credit_price`; issues no invoices until M2 | — |

No foreign key from `entitlement.plan` or `invoice.plan` to `plan.name` (G1/A5; FR-015).

---

## 4. Delete semantics

`POST /control/plans/{name}/delete`:

1. Missing/invalid operator credential → `401` `{"error":"unauthorized"}`; no writes (FR-016).
2. Unknown plan name → `404` `plan_not_found`; no audit row (FR-014).
3. Existing plan → `DELETE FROM plan` **and** `control_audit` `plan_delete` in one batch
   (FR-013). Referencing `entitlement` / `invoice` rows are untouched (FR-015).
   Retirement-by-status remains the live-entitlement policy; delete is a catalogue operation.

This supersedes G1's "delete journals audit and retains the row" behaviour for catalogue rows
(Delivery Plan §3.2 Code sync). G1 contract files are not edited; this data-model is the
binding note for the M1 freeze.

---

## 5. Consumer binding

| Later consumer | What it binds to |
| --- | --- |
| P2 (`GET /v1/plans`) | A17 columns on `plan` (§2.1); serves `status = 'active'` rows with price and `grace_days` (ABO §4.1.6 / §5.10) |
| M2 (period-close / invoice / `purchase_proof`) | Absence of `credit_price`; paid-amount pricing replaces credits×price |
| M3 (data-journey docs) | Schema snapshot including A17 `plan` columns and excluding `credit_price` |
| Band Q/R/T (ABO / Flutter) | Catalogue via P2 fetch — no local plan table (ABO §4.1.6) |

---

## 6. Deliberately absent

- `GET /v1/plans` HTTP contract (P2).
- `purchase_proof` table and invoice reshape columns (M2).
- Period-close paid-amount pricing logic (M2).
- Any plan/price table in `ai-billing-orchestrator/` (constitution / ABO §4.1.6).
- Clinic Postgres writes; shared bearer; money or provider prices on the AI request path.
