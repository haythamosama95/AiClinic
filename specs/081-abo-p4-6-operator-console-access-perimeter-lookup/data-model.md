# Data Model: P4.6 operator console

Codebase `abo`. Migration `abo/migrations/0006_operator_action.sql`. The platform table `control_audit` already exists. This unit inserts into it and does not migrate it.

## 1. `operator_action`

Append-only ABO table. Abort-update and abort-delete triggers use the same `RAISE(ABORT, 'append_only')` pattern as `checkout`. The insert and its `fact_log` row (`"table"` `operator_action`, `key` `action_id`, `row_sha256` the hex SHA-256 of the canonical row) are one D1 batch. That batch commits before `recordOperatorAction`.

| Column | Rule |
| --- | --- |
| `action_id` | Primary key. A new id for this console action. Copied to `recordOperatorAction` and stored as `control_audit.target`. |
| `actor_email` | The verified Access JWT `email` claim. |
| `access_jti` | The verified Access JWT `jti` claim. A token with no `jti` string is refused and this row is not inserted. |
| `action` | `Retry parked work` or `Cancel an open checkout`. |
| `subject` | The `work_id` for retry. The `checkout_id` for cancel. |
| `params_sha256` | Hex SHA-256 of `canonicalize({ action, subject })`. |
| `assertion_sha256` | Null for both of this unit’s actions. |
| `result` | `open` after retry moves the parked grant work row to `open`. `cancelled` after cancel. |

This unit does not update or delete the row. A repeated platform `action_id` does not insert a second `operator_action` row; the repeat is a second `recordOperatorAction` call.

## 2. Rows this unit reads or updates, and does not redefine

| Table | Use |
| --- | --- |
| `work` | Retry updates one `kind = 'grant'` row from `parked` to `open` (`lease_until`, `last_error`, and `next_attempt_at` null). The parked-work view lists `state = 'parked'`. |
| `checkout_status` | Cancel sets `state` from `open` to `cancelled`. A later sweep may set `paid_late`. This unit does not change that sweep. |
| `checkout_event` | Cancel inserts one row, `kind` `cancelled`. `checkout` itself stays append-only and is not updated. |
| `checkout`, `payment`, `reversal`, `grant_request`, `grant_outcome`, `billing_contact`, `coverage_view` | Lookup and the clinic page. |
| `finding` | Clinic page and the open-findings view. No resolution table is created here. |
| `alert` | Clinic page lists rows with `active = 1` tied to that clinic. |

`payout_import` is not created. The payout-imports view returns an empty list.

## 3. `control_audit` insert

Not an ABO table. `recordOperatorAction` inserts one existing platform row and leaves every other platform table unchanged.

| Column | Value |
| --- | --- |
| `actor` | Access email. |
| `operator_id` | The same Access email. |
| `action` | The `action` argument, copied from `operator_action.action`. |
| `target` | The `action_id` argument. |
| `assertion_sha256` | Null. |

A second call with the same `action_id` inserts no second row. `inspectCoverage` inserts no row in this table.
