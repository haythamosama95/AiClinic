# Data Model: P4.5 sweeps, reversals and the inquiry budget

Codebase `abo`. Migration `abo/migrations/0005_reversal.sql`. Append-only tables use the consumed `fact_log` insert and the abort-update / abort-delete triggers. `reversal` already has those triggers in `abo/migrations/0004_grant.sql`.

## 1. `reversal`

Append-only. P4.4 created the table so the frozen payments read could join it, and inserted no rows. This unit adds the columns below and is the writer.

Existing columns, unchanged: `reversal_id` (primary key), `payment_id`, `reference`, `amount_minor`, `kind`, `is_full` (0 or 1).

Columns this migration adds:

| Column | Rule |
| --- | --- |
| `source` | `provider` for this unit. `vendor` is rejected and is not inserted. |
| `cumulative_reversed_minor` | The inquiry cumulative. `is_full` is 1 when this is at least `payment.amount_minor`. |
| `detected_via` | `notification` or `inquiry`. |
| `recorded_by` | `abo`. |
| `evidence_sha256` | Hex SHA-256 of the notification body or the inquiry evidence. |
| `effect` | `tombstone`, `end_current`, `remove_queued`, `none`, or `review_partial`. |
| `dedupe_key` | Unique. `paymob:{parentTxnRef}:reversal:{cumulative_reversed_minor}`. |

`reversal_id` is the hex SHA-256 of `reversal:` ‖ `dedupe_key`. `reference` is `REV-` plus the trailing 8 characters of that id. A second insert with the same `dedupe_key` writes nothing. Dismissal does not update the row. A `finding` records that the inquiry disagreed.

`kind` for these refunds is `refund`.

## 2. `reversal_outcome`

Append-only. Written only when `voidForReversal` returns a receipt that verifies.

| Column | Rule |
| --- | --- |
| `reversal_id` | The reversal that was voided. |
| `result` | `applied` or `already_applied`. |
| `receipt` | The platform receipt JSON. |
| `at` | ABO clock, ISO-8601. |

`transient` is not stored. `conflict` and `rejected` are not stored here; the `reverse` work row is parked instead.

## 3. `finding`

Append-only. This unit writes one row when an inquiry disagrees with a recorded refund callback.

| Column | Rule |
| --- | --- |
| `finding_id` | ULID primary key. |
| `kind` | `inquiry_disagrees`. |
| `subject` | The `reversal_id`. |
| `detail` | The inquiry id. |
| `detected_at` | ABO clock, ISO-8601. |

No `voidForReversal` call is made for that reversal. Reconciliation finding kinds stay with P4.10.

## 4. `inquiry_spend`

Operational. Not a commercial fact.

| Column | Rule |
| --- | --- |
| `minute_key` | Primary key. UTC minute `YYYY-MM-DDTHH:MM` from the ABO clock. |
| `spent` | Count of provider-inquiry slots started in that minute. The cap is 2. |

Confirm, grant, and sweep inquiries share this counter. A `reverse` row does not increment it. A due inquiry that does not get a slot stays on its `work` row.

## 5. `reverse` work row

The existing `work` table. No new columns. Inserted only for effect `tombstone`, `end_current`, or `remove_queued`, and only after the inquiry agrees.

`kind` is `reverse`. `subject_id` is the `reversal_id`. `dedupe_key` is `reverse:{reversal_id}`. `state` moves the way 03 §5.6 describes: `open` on a transient answer, `done` when a verified receipt is stored, `parked` on `conflict` or `rejected`. While `signing_key_gate.paused` is 1 the row stays `open` and is not taken. Effect `none`, a dismissed reversal, and `review_partial` do not insert this row.

## 6. Sweep work rows

Same `work` table.

`sweep_checkout`: `subject_id` is the checkout. `dedupe_key` is `sweep_checkout:{checkout_id}:{offset_ms}`. Offsets from the `opened` event are +2, +5, +10, and +20 minutes, then every 10 minutes until `expires_at`, including a final row at `expires_at`. After `expired` or `cancelled`, rows at `expires_at` plus 1 day, 3 days, and 7 days.

`sweep_payment`: `subject_id` is the payment. The hourly and 6-hour crons set `next_attempt_at` to now. The 06:00 UTC cron sets `next_attempt_at` to the payment's due minute in the following 24 hours. Slot is `payment_id` interpreted as a hex integer, modulo 7, compared to the UTC epoch-day modulo 7.

## 7. Checkout states this unit writes

`checkout_status` is the existing mutable row. This unit sets `expired` after the unpaid final inquiry, and `paid_late` when a payment is confirmed from `expired` or `cancelled`. Classification on that payment is `late`. Shown state is derived, not stored: `expired` or `cancelled` with no payment is `Abandoned`; `paid` or `paid_late` is `Paid` until the grant outcome is `applied` or `already_applied`, then `Active`.
