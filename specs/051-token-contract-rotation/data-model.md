# D1 Logical Model (J4) — `token_contract`

## Table of Contents

1. [Overview](#1-overview)
   - [1.1 Purpose](#11-purpose)
   - [1.2 Migration artifacts](#12-migration-artifacts)
   - [1.3 Relationship to A5](#13-relationship-to-a5)
2. [Entity catalog](#2-entity-catalog)
   - [2.1 `token_contract`](#21-token_contract)
3. [Accepted-`ver` set rules](#3-accepted-ver-set-rules)
4. [Writers and readers](#4-writers-and-readers)
5. [Consumer binding](#5-consumer-binding)
6. [Clinic-side mint setting (not D1)](#6-clinic-side-mint-setting-not-d1)

---

## 1. Overview

### 1.1 Purpose

This artifact documents the D1 entity **`token_contract`** created by slice J4. It is the binding
surface for the platform-global accepted AAT `ver` set — not prose in the architecture doc. Field
lists follow `docs/architecture/17-ai-platform.md` §7.3 (`token_contract` row) and the J4 Freezes.

### 1.2 Migration artifacts

| Artifact | Path |
| --- | --- |
| Forward migration | `ai-platform/migrations/20260803120000_token_contract.sql` |
| DDL snapshot | `ai-platform/schema.snap.sql` (updated to include `token_contract`) |

Migrations are forward-only and additive (§13.4).

### 1.3 Relationship to A5

A5's shipped platform schema (`20260731120000_platform_schema.sql`) and
`specs/019-ai-context-keys-d1-config/data-model.md` catalogued eleven §7.3 entities and did not
include `token_contract` (A5 presence cases predated the §7.3 amendment). J4 creates the table
forward-only. A5's `data-model.md` is **not** rewritten (delivery plan §2.3).

---

## 2. Entity catalog

### 2.1 `token_contract`

The platform-global set of accepted AAT `ver` values. `ver` versions the AAT claim contract itself,
so the set is global rather than per-installation. D1 is its only authority (§5.6; §7.3).

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `ver` | TEXT | NOT NULL | Primary key — the Token contract version string carried on the AAT `ver` claim |
| `added_at` | TEXT | NOT NULL | When this `ver` was added to the set (begin-rotation or initial seed) |
| `retired_at` | TEXT | NULL | Null while accepted; stamped by the retire mutation |
| `changed_by` | TEXT | NOT NULL | Operator identity that last changed this row |

**Deliberately absent columns:** `retire_after`, any TTL column. Retirement is not scheduled
(§5.7; FR-004).

**Growth:** a handful of rows ever. **Retention:** full history (append-only — retire stamps
`retired_at`, it does not delete the row).

**Accepted set:** rows with `retired_at IS NULL`.

**Initial seed:** migration inserts one accepted row `ver = '1'` with `retired_at` null, matching
B1's default `ai.aat.ver` (`"1"`), so the stable set holds exactly one value from first deploy
(FR-002).

---

## 3. Accepted-`ver` set rules

| State | Accepted-set size (`retired_at IS NULL`) | How it is reached |
| --- | --- | --- |
| Stable | Exactly **one** | Seed, or after retire closes a rotation |
| Mid-rotation | Exactly **two** (at most two) | Begin-rotation inserted a new `ver` while keeping the prior |
| Forbidden | Zero, or more than two | Writers must refuse; request path never writes |

"During" and "after" are **set membership**, not clock states (§5.7).

---

## 4. Writers and readers

| Role | Who | Effect |
| --- | --- | --- |
| **Begin rotation** | Control-plane operator mutation (§4.5) | `INSERT` a row for the new `ver` (`retired_at` null); prior row unchanged; also writes `control_audit` |
| **Retire** | Control-plane operator mutation (§4.5) | `UPDATE` stamps `retired_at` on the retired `ver`; accepted set returns to one; also writes `control_audit` |
| **Request path** | Identity stage (§4.3.2) | **Read only** through the config cache kind `"token_contracts"`; never writes |
| **Auto-retire** | — | **None** — no clock, scheduler, or hot-path TTL |

---

## 5. Consumer binding

| Consumer | How it binds |
| --- | --- |
| J4 identity (`EnrolledKeyVerifier`) | `loadConfig(cache, reader, "token_contracts", payload.ver)` — hit with `retired_at` null accepts; miss / retired → `unauthenticated` |
| J4 control plane | Only writers of this table; audit via existing `control_audit` |
| Later slices | May extend; may not rewrite this entity shape or the two-writer rule (delivery plan §2.3) |

Config-cache kind `"token_contracts"` is a forward-only extension of A5's `ConfigEntityKind` union.
A5's `contracts/config-cache.md` is not edited; the kind is frozen in
`contracts/token-contract-rotation.md`.

---

## 6. Clinic-side mint setting (not D1)

The minting-side counterpart is **not** a D1 entity. The issuer RPC reads `ver` from the clinic AI
schema settings row `ai.aat.ver` in `ai_internal.app_settings` (B1 Freezes; §5.6 minting side). The
platform never reads or writes that setting. It is listed here only so implementers do not invent a
D1 mint mirror.
