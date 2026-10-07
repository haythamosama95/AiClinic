# Data Model: P4.10 reconciliation, payout import and findings

Codebase `abo`. Migration `abo/migrations/0008_reconciliation.sql`. `finding` already exists in `abo/migrations/0005_reversal.sql` and already has abort-update and abort-delete triggers. This unit writes the eleven 05 §3.3 kinds into that table. New append-only tables use those same triggers and a `fact_log` insert on each row.

## 1. `finding`

Append-only. Existing columns, unchanged: `finding_id` (ULID primary key), `kind`, `subject`, `detail`, `detected_at` (ABO clock, ISO-8601).

This unit inserts a row only when no row with the same `kind` and `subject` exists. A passing re-run does not delete it. `detail` is the other side's identifier, or an empty string.

| `kind` | `subject` |
| --- | --- |
| `payment_without_grant` | `payment_id` |
| `grant_without_payment` | `grant_id` |
| `grant_without_operator_action` | `grant_id` |
| `transfer_without_authorisation` | `grant_id` |
| `reversal_not_applied` | `reversal_id` |
| `payout_unmatched` | `import_id` + `:` + `line_no` |
| `payment_not_in_payout` | `payment_id` |
| `unrecorded_reversal` | `import_id` + `:` + `line_no` |
| `callback_without_confirmation` | `notification_id` |
| `feed_divergence` | `org_id` |
| `receipt_mismatch` | `grant_id` |

`inquiry_disagrees` stays a P4.5 kind. This unit does not write it.

## 2. `finding_resolution`

Append-only. Written by `POST /ops/findings/{findingId}/resolve`.

| Column | Rule |
| --- | --- |
| `finding_id` | Primary key. The finding that was resolved. |
| `resolved_by` | Access email from the ops session. |
| `note` | String from the JSON body. |
| `at` | ABO clock, ISO-8601. |

A second resolve of the same `finding_id` inserts nothing.

## 3. `payout_import`

Append-only. Written by `POST /ops/payout-imports` before reconciliation runs.

| Column | Rule |
| --- | --- |
| `import_id` | ULID primary key. |
| `provider_id` | `paymob`. |
| `file_sha256` | Hex SHA-256 of the raw CSV body. |
| `r2_key` | `payouts/` plus `file_sha256`. The R2 object is those bytes. |
| `imported_by` | Access email from the ops session. |
| `period` | `YYYY-MM`. UTC month of the first line's `settled_at`, or the clock month when the file has no lines. |

## 4. `payout_line`

Append-only. One row per `PayoutLine` from `payoutLines`.

| Column | Rule |
| --- | --- |
| `import_id` | The import. Primary key with `line_no`. |
| `line_no` | 1-based position in the file. |
| `kind` | `payment`, `refund`, `chargeback`, `fee`, or `other`. |
| `gross_minor` | Integer minor units. |
| `fee_minor` | Integer minor units. |
| `net_minor` | Integer minor units. |
| `settled_at` | ISO-8601 from the CSV. |
| `payment_id` | From `paymob_txn.payment_id` for `transaction_id`. Null when that lookup misses. |

Index `payout_line_payment_id` on `payment_id`. Index `payout_import_period` on `period`.

## 5. `PayoutLine`

Adapter output. Not a D1 table. Fields are `kind`, `payment_id` (null if unknown), `gross_minor`, `fee_minor`, `net_minor`, `settled_at`. The Paymob CSV header the adapter reads is `transaction_id,type,gross_minor,fee_minor,net_minor,settled_at`. That header is not frozen.

## 6. Rows this unit reads and does not change

`payment` (`disposition`, `amount_minor`, `paid_at`, `confirmed_at`, `confirmation_inquiry_id`, `checkout_id`). `grant_outcome.receipt` for `applied` and `already_applied`, except `grant_request.source_kind = transfer`. `grant_request`. `operator_action`. `reversal` (`is_full`, `effect`, `payment_id`). `reversal_outcome`. `notification` (`hmac_valid`, body in R2). `coverage_view.snapshot`. `paymob_txn` (`txn_id`, `payment_id`). Platform `listGrants` receipts and `getCoverage` snapshots are read over `PLATFORM` and are not written by this unit.
