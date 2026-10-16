# Data Model: Reversal voids, tombstones, held terms and operator voids

**Branch**: `ai/071-abo-p3-7-reversal-voids-tombstones-held-terms` | **Date**: 2026-10-06

**Spec**: [spec.md](./spec.md)

This file records the entities in spec §3.2. It does not add columns or effects beyond that spec.

## 1. `grant_void`

Append-only D1 table. One row per `grant_id`.

| Column | Rule |
| --- | --- |
| `grant_id` | Primary key. The paid grant for `voidForReversal`, or the grant named by `voidGrant`. |
| `reason` | The call's `reason`. |
| `source` | `reversal` for `voidForReversal` with `partial` false. `operator` for `voidGrant`. |
| `evidence_sha256` | The call's `evidence_sha256` when `source` is `reversal`. The assertion challenge when `source` is `operator`. |
| `at` | UTC ISO-8601 time of the applied void. |

Update and delete raise, matching `grant_ledger`. A `partial` true `voidForReversal` inserts no row.

`reversal_id` is not a column. It is `receipt.reversal_id` inside the R2 object. Replay finds a stored void by reading those receipts.

### 1.1 R2 void object

Key `grant-ledger/<grant_id>.void.ndjson`. One JSON line and a trailing newline:

`{grant_id, reason, source, evidence_sha256, at, receipt}`

The line is the `grant_void` columns plus that void's receipt. It does not replace `grant-ledger/<grant_id>.ndjson`. P3.7 writes this key only when `voidForReversal` with `partial` false, or `voidGrant`, applies. `releaseHeld` does not write it.

### 1.2 Tombstone

A `partial` false `voidForReversal` stored before any `grant_ledger` row for that `grant_id`. The receipt uses `reversal_id` (not `grant_id`), `installation_id` and `org_id` `00000000-0000-0000-0000-000000000000`, `ledger_seq` 0, and `term_ids` `[]`. The call writes the D1 row and the R2 object and inserts no `coverage_event`.

A later `grant` with that `grant_id` fails validation step 5 and is `rejected` with `code` `voided`.

### 1.3 Receipt when the grant is already applied

The receipt's `installation_id` and `org_id` are that `grant_ledger` row's ids. `voidForReversal` puts `reversal_id` on the receipt. `voidGrant` and `releaseHeld` put `grant_id` on the receipt. `ledger_seq` for a void is the `clinic_seq` on the `grant_voided` coverage event. `envelope_sha256` is the hex SHA-256 of the canonical signed void body for `voidForReversal`.

## 2. Term end for reversal and void

Lookup stays on the installation named by the `grant_ledger` row. The term matches when `origin_grant_id` or `grant_id` equals the voided grant. This unit does not follow a transferred term onto another installation.

| Effect | Term before | Result |
| --- | --- | --- |
| `end_current` | `active` or `grace` | That term is `ended`, `end_reason` `reversed`, no grace. Every `queued` term becomes `held`. |
| `remove_queued` | `queued` or `held` | That term is `ended`, `end_reason` `reversed`, and leaves the queue. Other terms stay. |
| `none` | `ended` or `exhausted` | The term row stays. The void is still stored. |
| Operator void | any not `ended` | That term is `ended`, `end_reason` `voided`. If it was `active`, the first `queued` term by `position` becomes `active`. |
| `releaseHeld` | `held` | The term becomes `queued` at the next position. If no term is `active`, it becomes `active`. |

`releaseHeld` does not write `grant_void`.

## 3. Clinic coverage state `reversed`

Derived by the DO snapshot. When no term is `active` or `grace`, and the last ended term has `end_reason` `reversed`, `state` and `reason` are `reversed`. `held_count` is the number of terms in `held`. `queued_count` counts only `queued` terms. A clinic with no held terms keeps `held_count` 0. `expired`, `grace_exhausted`, and `exhausted` stay as they are today.
