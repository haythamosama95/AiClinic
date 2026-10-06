# Contract: `voidForReversal` and the tombstone rule

**Branch**: `ai/071-abo-p3-7-reversal-voids-tombstones-held-terms` | **Date**: 2026-10-06

**Spec**: [spec.md](../spec.md) FR-001 through FR-007

Frozen for later units. Class M on `VendorEntrypoint`. ABO-signed. Idempotent by `reversal_id`.

## 1. Request

Beyond `contract_version`: `grant_id`, `reversal_id`, `reason`, `evidence_sha256`, `partial`, `abo_kid`, `abo_signature`.

`partial` is required and is a boolean. The JWS payload is the RFC 8785 canonical form of `{contract_version, grant_id, reversal_id, reason, evidence_sha256, partial}`. `abo_kid` is the JWS `kid` and is not inside that body. Verification uses the existing paid-grant `service_key` check.

## 2. Results

| Condition | Result |
| --- | --- |
| `partial` missing or not a boolean | `rejected`, `code` `partial_invalid`, `detail` empty. Writes nothing. Does not consume `reversal_id`. |
| ABO signature bad | `rejected`, `code` `bad_signature`. Writes nothing. Does not consume `reversal_id`. |
| A void is already stored for `reversal_id`, and `grant_id`, `reason`, `evidence_sha256`, and `partial` false all match | `already_applied`. Returns the original receipt. Changes nothing. |
| A void is already stored for `reversal_id`, and any of those four differs, including `partial` true | `conflict`. Changes nothing. |
| No void stored, and `partial` is true | `rejected`, `code` `partial_void`, `detail` empty. No `grant_void` row, no R2 object, no coverage event, no tombstone, no platform alert. |
| `partial` false, and `grant_ledger` has no row for `grant_id` | `applied`. Tombstone. See §3. |
| `partial` false, and `grant_ledger` has a row | `applied`. Effect in §4. Receipt `installation_id` and `org_id` are that row's ids. Coverage events are emitted. |

A rejected call stores nothing.

## 3. Tombstone

Receipt fields: `reversal_id`, `installation_id` `00000000-0000-0000-0000-000000000000`, `org_id` the same nil UUID, `ledger_seq` 0, `term_ids` `[]`, `result` `applied`.

Writes `grant_void` (`source` `reversal`, the call's `reason` and `evidence_sha256`) and R2 `grant-ledger/<grant_id>.void.ndjson`. One JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}`. No `coverage_event`. No DO call.

A later `grant` with that `grant_id` is `rejected` with `code` `voided` and empty `detail`, after the existing validation steps and before the DO applies the grant.

## 4. Effects

The term is the one on that installation whose `origin_grant_id` or `grant_id` equals the paid `grant_id`.

| Term state | Effect | Platform action |
| --- | --- | --- |
| `active` or `grace` | `end_current` | Term `ended`, `end_reason` `reversed`, no grace. Queued terms become `held`. Snapshot `state` `reversed`. `held_count` may be non-zero. `POST /v1/requests` is `coverage_lapsed` with reason `reversed`. |
| `queued` or `held` | `remove_queued` | That term `ended`, `end_reason` `reversed`, removed from the queue. Other terms unchanged. |
| `ended` or `exhausted` | `none` | Term row unchanged. Void still stored. |

Events, in order: `term_ended` and `term_held` only when those transitions happen, then `grant_voided`. `ledger_seq` is the `clinic_seq` on `grant_voided`. `term_ids` is the ended term for `end_current` and `remove_queued`, and empty for `none`.

`envelope_sha256` on the receipt is the hex SHA-256 of the canonical signed body.
