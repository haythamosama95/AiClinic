# Data Model: P4.4 paid grant pipeline

Codebase `abo`. Migration `abo/migrations/0004_grant.sql`. Append-only tables use the consumed `fact_log` insert shape and the abort-update / abort-delete triggers from `abo/migrations/0001_records.sql`.

## 1. `grant_request`

Append-only. One row for each payment whose disposition is `grant`. Columns from 03 §2.8: `grant_id` (primary key), `org_id`, `source_kind`, `source_ref`, `envelope`, `envelope_sha256`, `assertion`.

This unit writes `source_kind` `paid` only. `source_ref` is the `payment_id`. `grant_id` is `grantIdPaid(payment_id)` from `vendor-contracts`: hex SHA-256 of `grant:paid:` ‖ `payment_id`. `envelope` is the canonical JSON of the 04 §1.4 paid envelope, including the one approvals element. `envelope_sha256` is the hex SHA-256 of those canonical bytes. `assertion` is null. A retry of the same payment does not insert a second row. A key rotation does not insert a second row; the next attempt signs the same envelope with the current `kid`.

## 2. `grant_outcome`

Append-only. Columns from 03 §2.8: `grant_id`, `result`, `abo_kid`, `abo_signature`, `receipt`, `term_ids`, `at`. Primary key `grant_id` (one outcome row).

`result` is `applied`, `already_applied`, `conflict`, or `rejected`. `transient` is not stored. `at` is the ABO clock when the row is inserted.

For `applied` and `already_applied`, the row is inserted only after `receipt.signature` verifies against `PLATFORM_PUBLIC_KEYS`. Those rows store `abo_kid`, `abo_signature`, `receipt` (the §1.6 object as JSON), and `term_ids` (JSON array from the receipt). An `applied` or `already_applied` result whose signature does not verify does not insert this row.

For `conflict` and `rejected`, `abo_kid`, `abo_signature`, `receipt`, and `term_ids` are null. The work row is parked in the same write.

## 3. `signing_key_gate`

Operational, not a commercial fact. One row, `id` = 1. Columns: `paused` (0 or 1), `checked_at` (ABO clock, ISO-8601).

`paused` is 1 when `listServiceKeys` does not show the ABO signing `kid` as `active` inside `not_before` and `not_after`, or when that call fails. The grant runner does not take `grant` or `reverse` rows while `paused` is 1. Those work rows stay `open`.

## 4. `reversal`

Append-only. This unit inserts no rows. P4.5 owns reversal processing. The table exists so the frozen payments and subscription reads have a place to look.

Columns used by those reads: `reversal_id` (primary key), `payment_id`, `reference`, `amount_minor`, `kind`, `is_full` (0 or 1). `kind` is `refund`, `void`, `chargeback`, or `unknown`. Tenant scope is `payment.org_id` joined on `payment_id`.

## 5. Work row for `grant`

The `work` table is the P4.3 table. This unit does not add columns. P4.3 inserts `kind` `grant`, `subject_id` the `payment_id`, `dedupe_key` `grant:{payment_id}`, `state` `open`.

This unit sets `state` to `done` after a verified `applied` or `already_applied`. It sets `state` to `parked` for `conflict`, `rejected`, or an unverified receipt. `transient` and an unreachable `grant` call leave `state` `open`, set `last_error` to `wait:{iso}` on the first failure (that timestamp is kept), and set `next_attempt_at` with backoff from 1 minute doubling to 15 minutes. A paused signing key does not change `state`.

## 6. Checkout shown state

`checkout_status.state` stays `paid` after confirm. Shown state `Active` is derived: that checkout's payment has a `grant_outcome.result` of `applied` or `already_applied`. No new checkout column.
