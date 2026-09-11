# D1 Logical Model (G3) — `usage_rollup` quota-weight aggregate

## Table of Contents

1. [Overview](#1-overview)
   - [1.1 Purpose](#11-purpose)
   - [1.2 Migration artifacts](#12-migration-artifacts)
   - [1.3 Relationship to A5 and F3](#13-relationship-to-a5-and-f3)
2. [Entity catalog](#2-entity-catalog)
   - [2.1 `usage_rollup` (extended)](#21-usage_rollup-extended)
3. [Aggregation](#3-aggregation)
4. [Readers](#4-readers)
5. [Deliberately absent](#5-deliberately-absent)

---

## 1. Overview

### 1.1 Purpose

This artifact documents the D1 column **G3 adds** to the existing `usage_rollup` row: the
quota-weight aggregate, the pre-aggregated `SUM(usage_event.quota_weight)` that prior-period
credits on the usage-summary read consume (FR-013; spec Key Entities; A15; §7.3).

It introduces **no table**. Adding the field is Delivery Plan §2.3 extension: existing
dimensions, counts, tokens, and cost keep their meanings.

### 1.2 Migration artifacts

| Artifact | Path |
| --- | --- |
| Forward migration | `ai-platform/migrations/20260911180000_usage_rollup_quota_weight.sql` |
| DDL snapshot | `ai-platform/schema.snap.sql` (updated to include `usage_rollup.quota_weight`) |

Migrations are forward-only and additive (A5 discipline; §13.4). `NOT NULL DEFAULT 0`
keeps existing `INSERT` lists that omit the column valid until the next F3 rollup pass
fills the SUM.

### 1.3 Relationship to A5 and F3

A5's shipped platform schema created `usage_rollup` as `rollup_id`, `dimensions`,
`request_count`, `tokens`, `cost`. F3 produces those rows from `usage_event` and already
stores per-request `quota_weight` on the ledger (`usage_event.quota_weight` — A15; the
ledger itself needed no change).

G3 extends the rollup row and F3's aggregation with the missing SUM. A5
`specs/019-ai-context-keys-d1-config/data-model.md` and F3
`specs/041-support-retention-rollups/contracts/usage-rollup-reconciliation.md` are **not**
rewritten (delivery plan §2.3). F3 cadence, retention, purge, and reconciliation are out of
scope for this slice.

Architecture §7.3 key fields for `usage_rollup` (working-tree): dimensions, counts, quota
weight, tokens, cost.

---

## 2. Entity catalog

### 2.1 `usage_rollup` (extended)

Pre-aggregated per installation/period (F3 dimensions `{ installation_id, period }`).

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `rollup_id` | TEXT | NOT NULL | Primary key — unchanged (F3 hash of dimensions) |
| `dimensions` | TEXT | NOT NULL | JSON `{ installation_id, period }` — unchanged |
| `request_count` | INTEGER | NOT NULL | Aggregated request count — meaning unchanged |
| `tokens` | INTEGER | NOT NULL | Aggregated tokens — meaning unchanged |
| `cost` | REAL | NOT NULL | Aggregated cost — meaning unchanged |
| `quota_weight` | INTEGER | NOT NULL | **G3** — `SUM(usage_event.quota_weight)` for those dimensions. Default `0` until the next rollup pass. This is prior-period credits on the usage-summary read |

**Growth:** small. **Retention:** long (`ledger` class) — F3 horizon unchanged.

**Writers:** F3 scheduled `runRollup` only, with the SUM extended. G3's usage-summary handler
does not write this table.

**First write of the new column:** next F3 rollup after this migration applies. Historical
rows remain `0` until that pass; the usage-summary read still does not scan `usage_event`.

---

## 3. Aggregation

F3 `aggregateUsageEvents` already `GROUP BY installation_id, period` and sums `tokens` /
`cost` with `COUNT(*)` as `request_count`. G3 adds:

```sql
SUM(quota_weight) AS quota_weight
```

to the same `GROUP BY`. Period-window behaviour (full-period sums; window only selects which
periods to re-aggregate) is unchanged. Equality-to-ledger now also includes the
quota-weight SUM. Idempotent upsert sets `quota_weight = excluded.quota_weight` alongside the
existing columns.

The usage-summary **read** MUST NOT re-run this aggregation and MUST NOT `SELECT` from
`usage_event`.

---

## 4. Readers

| Reader | What it reads | Notes |
| --- | --- | --- |
| G3 usage-summary handler | `quota_weight` for the authenticated installation where `dimensions.period` is not the current period | Current-period credits come from the Quota DO, not this table |
| G4 invoice generation | Out of scope | Must not be started here |
| F3 dashboards / retention | Existing columns; new column is inert for those jobs | Do not rewrite purge SQL beyond what `SELECT *` / table-level delete already does |

Current period key matches C3/F3 `periodFromIso(period_start)` → `YYYY-MM`.

---

## 5. Deliberately absent

- A new D1 table for usage summary or credit history
- A `usage_event` scan on the usage-summary read
- Historical answers from the Quota DO
- Token, cost, or provider-price columns on the usage-summary payload
- Changes to `usage_event` (ledger already has `quota_weight`)
- G4 `invoice` rows or `credit_price` activation
- F3 cadence, retention horizons, purge, or reconciliation report shape
