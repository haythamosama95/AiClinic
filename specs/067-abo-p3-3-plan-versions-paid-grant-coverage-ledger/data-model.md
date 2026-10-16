# Data Model: P3.3 plan versions, paid grants, and the coverage ledger

**Unit**: P3.3

Vendor state on the existing AI Platform worker. D1 uses the `DB` binding. The per-clinic Durable Object uses the SQLite storage already declared for `GatewayObject`. R2 uses the existing `R2` binding. Clinic PostgreSQL is unchanged. Wire shapes are in `contracts/`.

`issuer_key`, `tenant_binding`, and `installation` keep the columns P3.2 froze. This unit does not alter those tables. A paid grant for an org with no active binding inserts an `installation` and a `tenant_binding` of epoch 1 with the same column values the token path inserts. It does not change the token verifier.

## 1. `service_key` (D1)

New table. One row per ABO signing `kid`. (FR-004, 03 §3.2)

| Column | Type | Rule |
| --- | --- | --- |
| `kid` | TEXT primary key | Caller-supplied. |
| `service` | TEXT NOT NULL | `abo`. |
| `public_key` | TEXT NOT NULL | Base64url of the raw 32-byte Ed25519 public key, stored unchanged. |
| `status` | TEXT NOT NULL | `active` or `revoked`. There is no `retiring` status. Expired is not a stored status. |
| `not_before` | TEXT NOT NULL | UTC ISO-8601 validity start. |
| `not_after` | TEXT NOT NULL | UTC ISO-8601 validity end. A `kid` is expired when `status` is `active` and now is before `not_before` or after `not_after`. |
| `registered_by` | TEXT NOT NULL | Access email of the registering call. |
| `assertion_sha256` | TEXT NOT NULL | Assertion challenge hash of the registering call. |

`registerServiceKey` inserts `active`. `revokeServiceKey` is the only writer of `revoked`.

## 2. `plan_version` (D1)

New table. One row per published plan version. (FR-006, 03 §3.2)

| Column | Type | Rule |
| --- | --- | --- |
| `plan_id` | TEXT NOT NULL | Caller-supplied. |
| `version` | INTEGER NOT NULL | Caller-supplied. |
| `display_name` | TEXT NOT NULL | Content field. Immutable once published. |
| `capabilities` | TEXT NOT NULL | JSON array of capability id strings. Immutable once published. |
| `max_cost_class` | TEXT NOT NULL | Same TEXT form as the existing `plan.max_cost_class`. Immutable once published. |
| `concurrency_limit` | INTEGER NOT NULL | Content field. Immutable once published. |
| `max_allowance_per_month` | INTEGER NOT NULL | Content field. Immutable once published. |
| `status` | TEXT NOT NULL | `published` or `retired`. |
| `published_by` | TEXT NOT NULL | Access email of the publishing call. |
| `assertion_sha256` | TEXT NOT NULL | Assertion challenge hash of the publishing call. |

Primary key is `(plan_id, version)`. `publishPlanVersion` inserts `published`. `retirePlanVersion` is the only writer of `retired`. A same-pair replay with the same content fields does not update the row.

## 3. `coverage_event` (D1)

New append-only table. Never purged. (FR-011, 03 §3.2, 03 §6.7)

| Column | Type | Rule |
| --- | --- | --- |
| `feed_seq` | INTEGER primary key AUTOINCREMENT | Global cursor. |
| `event_id` | TEXT NOT NULL UNIQUE | `coverageEventId(installation_id, clinic_seq)` from `vendor-contracts`. |
| `org_id` | TEXT NOT NULL | |
| `installation_id` | TEXT NOT NULL | |
| `binding_epoch` | INTEGER NOT NULL | |
| `clinic_seq` | INTEGER NOT NULL | Rises by 1 for each event of that clinic. The first event is 1. |
| `kind` | TEXT NOT NULL | `grant_applied`, `grant_voided`, `term_activated`, `term_ended`, `term_held`, `term_released`, `grace_started`, `band_crossed`, `suspension_changed`, or `transfer`. |
| `snapshot` | TEXT NOT NULL | JSON coverage snapshot. Its `clinic_seq` equals this row's `clinic_seq`. |
| `at` | TEXT NOT NULL | UTC ISO-8601. For a paid grant, the grant time. |

The migration adds triggers that abort `UPDATE` and `DELETE`. The alarm inserts with `INSERT OR IGNORE` on `event_id`.

A paid grant writes `grant_applied`, plus `term_activated` when the new term is `active`, plus `term_ended` when placement ends the grace term. A grant that only queues writes `grant_applied` alone. Insert order is `term_ended`, then `term_activated`, then `grant_applied`, skipping any the grant does not emit.

## 4. `grant_ledger` (D1)

New append-only table. (FR-012, 03 §3.2)

| Column | Type | Rule |
| --- | --- | --- |
| `grant_id` | TEXT primary key | The envelope `grant_id`. |
| `origin_grant_id` | TEXT NOT NULL | For a term this unit creates, the same `grant_id`. |
| `org_id` | TEXT NOT NULL | |
| `installation_id` | TEXT NOT NULL | |
| `kind` | TEXT NOT NULL | Envelope `kind` (`term`). |
| `source_kind` | TEXT NOT NULL | `paid`. |
| `operator_credential_id` | TEXT NOT NULL | `credential_id` of the first `evidence.approvals` element. |
| `envelope_sha256` | TEXT NOT NULL | Hex SHA-256 of the canonical envelope. |
| `receipt` | TEXT NOT NULL | JSON receipt object (04 §1.6). |
| `applied_at` | TEXT NOT NULL | UTC ISO-8601. |

Indexes: `(org_id, applied_at)`, `(origin_grant_id)`, `(operator_credential_id, applied_at)`.

Triggers abort `UPDATE` and `DELETE`. The alarm inserts with `INSERT OR IGNORE` on `grant_id`. There is no `ledger_seq` column. That integer lives on the `grant_applied` coverage event as `clinic_seq`.

## 5. `coverage_mirror` (D1)

New table. One row per installation. Written only when an event ships. (FR-012, 03 §3.2, 03 §6.7)

| Column | Type | Rule |
| --- | --- | --- |
| `installation_id` | TEXT primary key | |
| `org_id` | TEXT NOT NULL | |
| `binding_epoch` | INTEGER NOT NULL | |
| `clinic_seq` | INTEGER NOT NULL | |
| `state` | TEXT NOT NULL | 03 §5.7 value from the snapshot. |
| `suspended` | INTEGER NOT NULL | 0 or 1. |
| `hard_stop_at` | TEXT | Null in this unit. P3.5 fills it. |
| `term_snapshot` | TEXT NOT NULL | JSON of the snapshot `term` object, or `null`. |

Replace the row only when `(binding_epoch, clinic_seq)` is strictly greater than the stored pair. A lower or equal pair does not write.

## 6. Per-clinic DO tables

Created on the first `GatewayObject.fetch` that passes the contract-version check. The JSON blob at storage key `state` is not deleted and is not rewritten by this unit. (FR-001, FR-002, 03 §3.1)

### 6.1 `hot`

One row. This unit sets `binding_epoch`, `clinic_seq`, `next_alarm_at`, `active_term_id`, and `used`. The other columns exist so the frozen schema matches 03 §3.1; this unit stores the inactive defaults and does not run admission.

| Column | Rule |
| --- | --- |
| `suspended` | 0 |
| `transferred_out_to` | NULL |
| `awaiting_transfer` | 0 |
| `transfer_pending` | 0 |
| `active_term_id` | The active term, or unchanged when the new term is queued. |
| `used` | 0 when this unit sets the active term. |
| `reserved` | 0 |
| `grace_base_used` | 0 |
| `reservations` | `[]` |
| `replay` | `{}` |
| `idempotency` | `{}` |
| `band_emitted` | `{}` |
| `binding_epoch` | The binding epoch used for the grant. |
| `clinic_seq` | Last assigned event sequence. 0 before any event. |
| `next_alarm_at` | UTC ISO-8601 of the alarm, or NULL when none is set. |

### 6.2 `term`

One row per term. Primary key `term_id` (UUID from `crypto.randomUUID()`).

Columns: `term_id`, `grant_id`, `origin_grant_id`, `position`, `state`, `end_reason`, `plan_snapshot`, `allowance`, `used_final`, `duration_unit`, `duration_count`, `grace_days`, `grace_cap`, `calendar_start`, `starts_at`, `ends_at`, `grace_ends_at`, `ended_at`.

`plan_snapshot` is the JSON object `{plan_id, version, display_name, capabilities, max_cost_class, concurrency_limit}`. `capabilities` is the published array, copied unchanged. `position` starts at 1 and rises by 1. A queued term stores `duration_unit` and `duration_count` and leaves the date columns NULL. `grace_cap` and `grace_ends_at` stay NULL in this unit. `used_final` stays NULL until the term ends.

### 6.3 `grant`

One row per grant. Primary key `grant_id`.

Columns: `grant_id`, `kind`, `source_kind`, `envelope_sha256`, `envelope`, `evidence`, `receipt`, `applied_at`, `voided_at`, `void_reason`.

`envelope` and `evidence` are the JSON text of those objects. `receipt` is the signed receipt JSON. `voided_at` and `void_reason` stay NULL.

### 6.4 `outbox`

Transient. Primary key `seq` INTEGER AUTOINCREMENT.

Columns: `seq`, `kind`, `payload`. `kind` is `coverage_event`, `grant_ledger`, `usage_adjustment`, or `alert`. This unit enqueues `coverage_event`, `grant_ledger`, and `alert`. The alarm deletes a row after that row is shipped.

## 7. R2 `grant-ledger/`

One NDJSON object per grant. Key `grant-ledger/<grant_id>.ndjson`. One JSON line, the `grant_ledger` columns plus `receipt` as the receipt object. A void, written by a later unit, is `grant-ledger/<grant_id>.void.ndjson` and does not replace the grant object. The bucket lock itself is the P8.1 operational setting. This unit writes the object with `R2.put`.

## 8. Unchanged tables

`issuer_key`, `tenant_binding`, `installation`, `operator_credential`, `assertion_used`, `platform_alert`, `control_audit`, and the quota blob stay. `platform_alert` gains rows for AL-11, AL-13 (service key), and AL-17. No new alert column.
