# Data Model: Console relays for complimentary grants and the transfer saga

**Spec**: [spec.md](./spec.md)

**Date**: 2026-10-07

## 1. Scope

This unit writes existing ABO tables. It adds no migration and no new table. Platform tables (`transfer`, platform `transfer_step`, `grant_ledger`, `grant_void`, `control_audit`, `tenant_binding`) stay on the AI Platform and are not changed.

## 2. `grant_request`

Append-only. The table and its abort-update and abort-delete triggers already exist (`abo/migrations/0004_grant.sql`).

| Field | This unit |
| --- | --- |
| `grant_id` | Complimentary and term adjustment: SHA-256 hex over `"grant:comp:"` ‖ the operator action id. Transfer: SHA-256 hex over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. n is the 0-based index of that element in the transfer package, decimal digits, no leading zeros. n runs 0 … k−1. k is the number of elements. |
| `org_id` | The clinic org. |
| `source_kind` | `complimentary` or `transfer`. |
| `source_ref` | Operator action id, or `transfer_id`. |
| `envelope` | Canonical JSON. For a transfer, the package element. |
| `envelope_sha256` | SHA-256 of that canonical envelope. |
| `assertion` | The forwarded assertion for complimentary and term adjustment. Null for transfer. |

One transfer writes k rows, and none when the package is empty. A later saga run does not insert a second row for the same n.

## 3. `grant_outcome`

Append-only. The table already exists.

| Field | This unit |
| --- | --- |
| `grant_id` | The complimentary or term-adjustment `grant_id`. |
| `result` | `applied`, `already_applied`, `conflict`, or `rejected`. |
| `abo_kid`, `abo_signature` | Null. Paid attempts only. |
| `receipt` | The platform receipt when the result carries one. |
| `term_ids` | From that receipt when present. |
| `at` | The ABO clock time of the attempt. |

One row per `grant_id`. Transfer package rows do not get a `grant_outcome` from this saga. The platform applies those terms in `transferIn`.

## 4. `transfer_step` work row

This is a row in the existing `work` table (`abo/migrations/0003_notify_work.sql`), not the platform `transfer_step` table.

| Field | This unit |
| --- | --- |
| `kind` | `transfer_step` |
| `subject_id` | `transfer_id` |
| `dedupe_key` | `transfer_step:` ‖ `transfer_id`. One row per transfer. |
| `state` | `open` until both `transferOut` and `transferIn` are `applied` or `already_applied`, then `done`. |
| `next_attempt_at` | Null at insert. A `transient` result does not set a backoff. |
| `lease_until` | Held only while a run is in progress, then cleared. |
| `last_error` | `awaiting_transfer_out` when `transferIn` runs before `transferOut` has applied. |

`beginTransfer` inserts the row. The minute `scheduled()` handler drives it.

## 5. `operator_action`

Append-only. The table already exists (`abo/migrations/0006_operator_action.sql`).

One row per console action. `actor_email` is the Access email. `action_id` is the id the console sends, and it is the id inside the complimentary `grant_id`. `result` is the platform result for that action. These relays do not call `recordOperatorAction`. The platform writes `control_audit` for the class-H and class-HP calls it verifies.
