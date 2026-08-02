# D1 Logical Model (A5)

## Table of Contents

1. [Overview](#1-overview)
   - [1.1 Purpose](#11-purpose)
   - [1.2 Migration artifacts](#12-migration-artifacts)
2. [Entity catalog](#2-entity-catalog)
   - [2.1 `installation`](#21-installation)
   - [2.2 `installation_key`](#22-installation_key)
   - [2.3 `entitlement`](#23-entitlement)
   - [2.4 `capability_grant`](#24-capability_grant)
   - [2.5 `routing_policy`](#25-routing_policy)
   - [2.6 `ai_request`](#26-ai_request)
   - [2.7 `ai_attempt`](#27-ai_attempt)
   - [2.8 `usage_event`](#28-usage_event)
   - [2.9 `usage_rollup`](#29-usage_rollup)
   - [2.10 `platform_counter`](#210-platform_counter)
   - [2.11 `control_audit`](#211-control_audit)
3. [`ai_request` special constraints](#3-ai_request-special-constraints)
   - [3.1 Request-reference unique index (A2)](#31-request-reference-unique-index-a2)
   - [3.2 Nullable conversation columns (A14)](#32-nullable-conversation-columns-a14)
4. [Retention classes](#4-retention-classes)
   - [4.1 Class map](#41-class-map)
   - [4.2 A10 and F3 ownership](#42-a10-and-f3-ownership)
5. [Consumer binding](#5-consumer-binding)
   - [5.1 C3 — journal writer](#51-c3--journal-writer)
   - [5.2 H3 — conversational journaling](#52-h3--conversational-journaling)
   - [5.3 F3 — support lookup and retention](#53-f3--support-lookup-and-retention)
6. [Relationships and foreign keys](#6-relationships-and-foreign-keys)

---

## 1. Overview

### 1.1 Purpose

This artifact documents the platform's D1 logical model created by slice A5. It is the binding surface for later slices that write or read platform rows — not prose in the architecture doc. A5 creates schema only; no row-level write paths land in this slice.

The model follows `docs/architecture/17-ai-platform.md` §7.3. Field lists indicate shape and cardinality; payloads live in R2 and are referenced by pointer columns in D1.

### 1.2 Migration artifacts

| Artifact | Path |
| --- | --- |
| Forward migration | `ai-platform/migrations/20260731120000_platform_schema.sql` |
| DDL snapshot | `ai-platform/schema.snap.sql` |

Migrations are forward-only and additive (§13.4). The snapshot test (`schema_snapshot_matches`) pins the post-migration `CREATE TABLE` DDL against `schema.snap.sql`.

---

## 2. Entity catalog

Eleven entities, matching §7.3 exactly.

### 2.1 `installation`

An enrolled clinic deployment.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `installation_id` | TEXT | NOT NULL | Primary key |
| `org_id` | TEXT | NOT NULL | Clinic org identifier |
| `display_name` | TEXT | NOT NULL | Human-readable name |
| `status` | TEXT | NOT NULL | Enrollment lifecycle state |
| `region` | TEXT | NOT NULL | Deployment region |
| `enrolled_at` | TEXT | NOT NULL | Enrollment timestamp |

**Growth**: tens–thousands of rows. **Retention**: life of customer.

**First write**: B2 (enrollment). **Config cache**: read through `installations` kind (A5 cache).

### 2.2 `installation_key`

Verification material and rotation history for an installation.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `key_id` | TEXT | NOT NULL | Primary key |
| `installation_id` | TEXT | NOT NULL | FK → `installation` |
| `public_key` | TEXT | NOT NULL | Verification material |
| `algorithm` | TEXT | NOT NULL | Key algorithm identifier |
| `valid_from` | TEXT | NOT NULL | Validity start |
| `valid_until` | TEXT | Yes | Optional validity end |
| `revoked_at` | TEXT | Yes | Revocation timestamp |

**Growth**: few per installation. **Retention**: history kept for audit.

**First write**: B2. **Config cache**: read through `keys` kind (A5 cache).

### 2.3 `entitlement`

What an installation may use and how much.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `entitlement_id` | TEXT | NOT NULL | Primary key |
| `installation_id` | TEXT | NOT NULL | FK → `installation` |
| `plan` | TEXT | NOT NULL | Plan identifier |
| `period_start` | TEXT | NOT NULL | Billing period start |
| `period_end` | TEXT | NOT NULL | Billing period end |
| `request_quota` | INTEGER | NOT NULL | Request quota for period |
| `token_budget` | INTEGER | NOT NULL | Token budget for period |
| `cost_budget` | REAL | NOT NULL | Cost budget for period |
| `allowed_capabilities` | TEXT | NOT NULL | Permitted capability set |
| `soft_threshold` | REAL | NOT NULL | Soft-limit threshold |
| `status` | TEXT | NOT NULL | Entitlement lifecycle state |

**Growth**: one current + history per installation. **Retention**: history kept for billing disputes.

**First write**: B2. **Config cache**: read through `entitlements` kind (A5 cache).

### 2.4 `capability_grant`

Which capability versions a plan or installation may use.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `grant_id` | TEXT | NOT NULL | Primary key |
| `scope` | TEXT | NOT NULL | Grant scope (plan or installation) |
| `capability_id` | TEXT | NOT NULL | Capability identifier |
| `capability_version` | TEXT | NOT NULL | Granted version |
| `granted_at` | TEXT | NOT NULL | Grant timestamp |
| `revoked_at` | TEXT | Yes | Revocation timestamp |
| `changed_at` | TEXT | NOT NULL | Last change timestamp |
| `changed_by` | TEXT | NOT NULL | Actor who made the change |

**Growth**: low. **Retention**: full history (`ledger` class — see §4).

**First write**: control plane. **Config cache**: read through `grants` kind (A5 cache).

### 2.5 `routing_policy`

Versioned target chains and selection rules.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `policy_id` | TEXT | NOT NULL | Composite PK (with `version`) |
| `version` | TEXT | NOT NULL | Policy version |
| `content_pointer` | TEXT | NOT NULL | Pointer to policy content |
| `active_from` | TEXT | NOT NULL | Activation timestamp |
| `activated_by` | TEXT | NOT NULL | Actor who activated |

**Growth**: low. **Retention**: full history.

**Config cache**: the active routing policy is read through the `active routing policy` kind (A5 cache).

### 2.6 `ai_request`

One row per request — the journal spine. The dominant table.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `request_id` | TEXT | NOT NULL | Primary key; request identity (ULID, A2) |
| `request_reference` | TEXT | NOT NULL | Support handle; A2 format — see §3.1 |
| `installation_id` | TEXT | NOT NULL | FK → `installation` |
| `actor_id` | TEXT | NOT NULL | Submitting actor |
| `branch_id` | TEXT | Yes | Branch scope when applicable |
| `capability_id` | TEXT | NOT NULL | Capability identifier |
| `capability_version` | TEXT | NOT NULL | Capability version |
| `prompt_artifact_hash` | TEXT | NOT NULL | Hash of composed prompt artifact |
| `idempotency_key` | TEXT | NOT NULL | Client idempotency key |
| `state` | TEXT | NOT NULL | Request lifecycle state (§6.3) |
| `created_at` | TEXT | NOT NULL | Row creation timestamp |
| `updated_at` | TEXT | NOT NULL | Last state-change timestamp |
| `completed_at` | TEXT | Yes | Terminal completion timestamp |
| `terminal_error_code` | TEXT | Yes | Taxonomy code when terminal state is failed |
| `trace_id` | TEXT | NOT NULL | Distributed trace identifier |
| `payload_pointer` | TEXT | Yes | R2 envelope pointer (`request/{id}/envelope`) |
| `routing_tier` | TEXT | Yes | Gateway-set tier — `standard` / `degraded` (§4.3.7, §7.3); never client-supplied |
| `routing_decision` | TEXT | Yes | Serialized selection-reason object for the request (§4.3.7, §7.3) |
| `conversation_id` | TEXT | Yes | Conversational leg grouping — see §3.2 |
| `turn_ordinal` | INTEGER | Yes | Turn order within conversation — see §3.2 |

**Growth**: dominant — roughly one row per AI request. **Retention**: `journal` class (see §4).

**First write**: C3 (journal writer). A5 creates the table and index only.

`routing_tier` and `routing_decision` are listed for `ai_request` in §7.3 and detailed in
§4.3.7; they are gateway-set and never client-supplied. A5 creates them nullable because they are
written after the row is inserted (routing runs later in the pipeline) — D2/F4 populate them.

### 2.7 `ai_attempt`

One row per provider attempt for a request.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `attempt_id` | TEXT | NOT NULL | Primary key |
| `request_id` | TEXT | NOT NULL | FK → `ai_request` |
| `attempt_no` | INTEGER | NOT NULL | Attempt sequence (1–3 typical) |
| `provider` | TEXT | NOT NULL | Provider identifier |
| `model` | TEXT | NOT NULL | Model identifier |
| `outcome` | TEXT | NOT NULL | Attempt outcome |
| `latency_ms` | INTEGER | NOT NULL | Round-trip latency |
| `tokens_in` | INTEGER | NOT NULL | Input tokens |
| `tokens_out` | INTEGER | NOT NULL | Output tokens |
| `cost` | REAL | NOT NULL | Attempt cost |
| `provider_request_id` | TEXT | Yes | Provider-side request id |
| `error_code` | TEXT | Yes | Taxonomy code on failure |

**Growth**: 1–3 per request. **Retention**: with the request (`journal` class).

**First write**: C3 (post-response detail).

### 2.8 `usage_event`

Append-only quota and billing ledger.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `usage_event_id` | TEXT | NOT NULL | Primary key |
| `installation_id` | TEXT | NOT NULL | FK → `installation` |
| `period` | TEXT | NOT NULL | Billing period key |
| `request_id` | TEXT | NOT NULL | FK → `ai_request` |
| `quota_weight` | INTEGER | NOT NULL | Quota units consumed |
| `tokens` | INTEGER | NOT NULL | Tokens credited |
| `cost` | REAL | NOT NULL | Cost credited |
| `recorded_at` | TEXT | NOT NULL | Ledger write timestamp |

**Growth**: ~1 per request. **Retention**: longer than requests — billing evidence (`ledger` class).

**First write**: C3 (post-response detail).

### 2.9 `usage_rollup`

Pre-aggregated counts per installation, period, and capability.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `rollup_id` | TEXT | NOT NULL | Primary key |
| `dimensions` | TEXT | NOT NULL | Aggregation dimension set |
| `request_count` | INTEGER | NOT NULL | Aggregated request count |
| `tokens` | INTEGER | NOT NULL | Aggregated tokens |
| `cost` | REAL | NOT NULL | Aggregated cost |

**Growth**: small. **Retention**: long (`ledger` class).

**First write**: F3 (scheduled rollup job from `usage_event`).

### 2.10 `platform_counter`

Bucketed counts for events that are never journaled — chiefly guard rejections.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `counter_id` | TEXT | NOT NULL | Primary key |
| `dimension_set` | TEXT | NOT NULL | Counter dimension key |
| `time_bucket` | TEXT | NOT NULL | Time-bucket identifier |
| `count` | INTEGER | NOT NULL | Bucketed count |

**Growth**: bounded, low cardinality. **Retention**: months.

**First write**: guard rejection path (B3) and other non-journaled events.

### 2.11 `control_audit`

Control-plane mutations.

| Column | Type | Nullable | Notes |
| --- | --- | --- | --- |
| `audit_id` | TEXT | NOT NULL | Primary key |
| `operator_id` | TEXT | NOT NULL | Operator who performed the action |
| `action` | TEXT | NOT NULL | Action identifier |
| `target` | TEXT | NOT NULL | Target entity or resource |
| `before_pointer` | TEXT | Yes | State before change |
| `after_pointer` | TEXT | Yes | State after change |
| `recorded_at` | TEXT | NOT NULL | Audit timestamp |

**Growth**: low. **Retention**: long (`ledger` class).

**First write**: control-plane operations (enrollment, policy changes).

---

## 3. `ai_request` special constraints

### 3.1 Request-reference unique index (A2)

The `request_reference` column stores the format frozen by slice A2 unchanged:

- Eight Crockford-base32 symbols in the pattern `XXXX-XXXX` (hyphen between the fourth and fifth symbol).
- Alphabet: `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no I, L, O).
- Normalisation rules live in `ai-platform/src/reference.ts` (`normalizeRequestReference`).

The request reference is a **support handle**, not the request's primary identity. Request identity is `request_id` (ULID, A2).

**Index**:

```sql
CREATE UNIQUE INDEX idx_ai_request_request_reference ON ai_request (request_reference);
```

Properties asserted by `request_reference_index_exists_and_unique` (T-A5-15):

- Index exists on `request_reference`.
- Index is unique.
- Column stores the A2 format without transformation.

F3 support lookup resolves a reference through this index in exactly one D1 query, then one R2 `GetObject` (§7.6).

### 3.2 Nullable conversation columns (A14)

Amendment A14 introduces two nullable columns on `ai_request` — no separate `conversation` table:

| Column | Type | Nullable | Populated when |
| --- | --- | --- | --- |
| `conversation_id` | TEXT | Yes | Conversational legs (H3) |
| `turn_ordinal` | INTEGER | Yes | Conversational legs (H3) |

`single_shot` requests (the default) carry neither column. Both remain `NULL`.

Properties asserted by `conversation_id_and_turn_ordinal_nullable` (T-A5-16):

- `conversation_id` column exists and is nullable.
- `turn_ordinal` column exists and is nullable.

H3 writes both columns per conversational leg. A whole conversation is readable with one indexed query on `conversation_id` ordered by `turn_ordinal`. There is no conversation entity — the transcript lives on the client during chat and in per-leg R2 envelopes afterwards (§7.3, A14).

---

## 4. Retention classes

### 4.1 Class map

Retention class is a per-capability manifest field (§5.1). Each class has its own horizon (§7.7). This slice creates the tables; expiry and purge behaviour are owned by later slices.

| Class | Applies to | Default horizon | D1 entities in this model |
| --- | --- | --- | --- |
| `diagnostic` | R2 payload envelope (prompt, context, raw responses, result) | Days to weeks (per-capability) | `payload_pointer` on `ai_request` points to envelope; envelope content is not in D1 |
| `journal` | Request metadata | Months | `ai_request`, `ai_attempt` |
| `ledger` | Billing and governance evidence | Years | `usage_event`, `usage_rollup`, `control_audit`, `capability_grant` |
| `ephemeral` | Operational records inside Quota DO | Minutes to hours | Not in D1 — Quota DO only |

The `ai_request` row in §7.3 is tagged "Retention class (A10)" — meaning its **journal metadata** and linked R2 envelope follow the horizons above, not that A5 implements purge logic.

### 4.2 A10 and F3 ownership

| Concern | Owner slice | What A5 provides |
| --- | --- | --- |
| Retention and purge policy definition (A10) | Architecture amendment + manifest per-capability field | Tables and pointer columns that retention jobs target |
| Retention expiry execution | F3 | Schema: `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `control_audit`, `capability_grant`; R2 envelope keys derived from `request_id` |
| Per-capability diagnostic horizon | A10 (manifest field) + F3 (purge job) | `payload_pointer` column; envelope at `request/{id}/envelope` |
| Installation deletion purge | F3 | All eleven entities are purgeable by `installation_id` (directly or via FK chain) |
| Usage rollup production | F3 | `usage_rollup` table; source is `usage_event` |

A5 does not implement cron jobs, lifecycle rules, or purge queries. It freezes the schema F3 binds to.

---

## 5. Consumer binding

Later slices bind to this artifact — not to architecture prose.

### 5.1 C3 — journal writer

C3 writes against the schema defined here:

| Operation | Entities | Timing |
| --- | --- | --- |
| Insert request row (`state = accepted`) | `ai_request` | Synchronously before provider invocation (stage 9) |
| Update terminal state and timestamps | `ai_request` | On completion, failure, or cancellation |
| Insert attempt detail | `ai_attempt` | Post-response (stage 15–16) |
| Insert usage credit | `usage_event` | Post-response |
| Write R2 envelope | R2 (one object per request) | Post-response; `payload_pointer` set on `ai_request` |

Guard-rejected requests produce **no** `ai_request` row. Rejection counts go to `platform_counter`.

### 5.2 H3 — conversational journaling

H3 populates the nullable columns A14 introduces:

- Sets `conversation_id` and `turn_ordinal` on each conversational leg's `ai_request` row.
- Each leg is independently admitted, journaled, and credited.
- No `conversation` table is created.
- No per-request server-side state object is introduced.

Query pattern: `WHERE conversation_id = ? ORDER BY turn_ordinal`.

### 5.3 F3 — support lookup and retention

F3 reads and purges against this schema:

| Capability | Binding |
| --- | --- |
| Support lookup by request reference | `idx_ai_request_request_reference` → one D1 query → `payload_pointer` → one R2 `GetObject` |
| Whole-conversation support read | Indexed query on `conversation_id` + `turn_ordinal` |
| Retention purge per class | Delete or expire rows in `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `control_audit`, `capability_grant` on class horizon; R2 envelope lifecycle by `request_id` key |
| Usage rollup | Aggregate `usage_event` → insert `usage_rollup` |
| Journal dashboards | Query `ai_request`, `ai_attempt`, `usage_rollup`, `platform_counter` |
| Installation deletion | Purge by `installation_id` across D1 entities and R2 |

---

## 6. Relationships and foreign keys

```
installation
  ├── installation_key (installation_id)
  ├── entitlement (installation_id)
  └── ai_request (installation_id)
        ├── ai_attempt (request_id)
        └── usage_event (request_id, installation_id)

capability_grant    — no FK; scoped by scope column
routing_policy      — composite PK (policy_id, version); no FK
usage_rollup        — no FK; dimensions encode aggregation keys
platform_counter    — no FK; dimension_set encodes counter keys
control_audit       — no FK; target encodes affected resource
```

Foreign keys enforced in migration:

| Child | Column | Parent |
| --- | --- | --- |
| `installation_key` | `installation_id` | `installation.installation_id` |
| `entitlement` | `installation_id` | `installation.installation_id` |
| `ai_request` | `installation_id` | `installation.installation_id` |
| `ai_attempt` | `request_id` | `ai_request.request_id` |
| `usage_event` | `installation_id` | `installation.installation_id` |
| `usage_event` | `request_id` | `ai_request.request_id` |

Indexes beyond PKs:

| Index | Table | Unique | Purpose |
| --- | --- | --- | --- |
| `idx_ai_request_request_reference` | `ai_request` | Yes | Support lookup (F3); A2 format |
