# Data Model: P4.3 notification intake, inquiry, work, and payment

Codebase `abo`. Migration `abo/migrations/0003_notify_work.sql`. Append-only tables use the consumed `fact_log` insert shape and the abort-update / abort-delete triggers from `abo/migrations/0001_records.sql`. Provider ids stay on `paymob_txn` and `paymob_state_seen`.

## 1. `notification`

Append-only. Columns: `notification_id` (ULID, primary key), `provider_id` (`paymob`), `channel` (`processed` or `response`), `hmac_valid` (1), `body_r2_key`, `body_sha256`, `dedupe_key`, `checkout_id` (null when unmatched), `disposition` (`enqueued`, `duplicate`, `unmatched`), `adapter_version` (`1`).

`dedupe_key` and `body_sha256` are the SHA-256 hex of the raw body (processed callback) or of the raw query string (response callback). The same `dedupe_key` inserts another row with disposition `duplicate` and does not insert another `confirm` row. HMAC-invalid bodies are not rows in this table.

## 2. `inquiry_result`

Append-only. Columns: `inquiry_id` (ULID, primary key), `subject` (`checkout:{checkout_id}` or `payment:{payment_id}`), `normalized_state`, `cumulative_reversed_minor`, `raw_r2_key`, `raw_sha256`, `at`, `adapter_version` (`1`).

Insert a row only when `normalized_state` or `cumulative_reversed_minor` differs from the latest row for that `subject`. The raw inquiry JSON is the R2 object. A first inquiry that is already a full refund or void is this row plus payment disposition `reversed_before_grant`. This unit does not add a `reversal` table.

## 3. `payment`

Append-only. A row exists only after the authenticated inquiry confirms a success. Columns match 03 §2.6: `payment_id`, `reference`, `org_id`, `checkout_id`, `provider_id`, `amount_minor`, `currency`, `paid_at`, `confirmed_at`, `confirmation_inquiry_id`, `offer_id`, `offer_version`, `billing_contact_version`, `classification`, `disposition`, `mismatch_detail`, `evidence_sha256`.

`payment_id` is SHA-256 hex of `payment:` ‖ `paymob` ‖ `:` ‖ the inquiry transaction id (03 §2.6 cites §7). `reference` is `humanRef("PAY", payment_id)` (`PAY-` plus the trailing 8 characters). `provider_id` is `paymob`. Classification is `likely_duplicate`, `late`, or `normal`, set once. Disposition is `grant`, `withheld_mismatch`, or `reversed_before_grant`. `mismatch_detail` is null except for `withheld_mismatch`. This unit does not write `payment_release`.

## 4. `work`

Mutable. Columns from 03 §2.9: `work_id` (ULID, primary key), `kind`, `subject_id`, `dedupe_key` (unique), `state` (`open`, `done`, `parked`), `attempts`, `next_attempt_at`, `lease_until`, `last_error`. Plus `opened_at`, set once at insert. Backoff rewrites `next_attempt_at`, so AL-01 reads `opened_at`: an `open` row whose `opened_at` is more than 5 minutes before the ABO clock.

Index `(state, next_attempt_at)`. This unit inserts `kind = confirm` and, when disposition is `grant`, `kind = grant` in the same batch. It takes only `confirm`. A take sets `lease_until` 60 seconds ahead and matches only when `lease_until` is null or already past, and `next_attempt_at` is due, and `state = open`.

`dedupe_key` for a processed callback is `confirm:{notification_id}`. For a return or response-callback schedule it is `confirm-schedule:{checkout_id}`. For a grant row it is `grant:{payment_id}`.

`parked` is conflict, rejected, or invariant failure. Timeout, HTTP 429, and a failed confirm batch leave the row `open`.

## 5. `paymob_txn` and `paymob_state_seen`

Adapter only. `paymob_txn`: `txn_id` (primary key), `order_id`, `checkout_id`, `payment_id` (null until a payment exists), `parent_txn_id`, `last_state_key`. `paymob_state_seen`: `dedupe_key` primary key, the unique triple of transaction, normalized state, and cumulative reversed amount; `source`; `first_seen_at`.

## 6. `notify_rate`

Operational counter, not a commercial fact. Columns: `ip` (primary key), `window_start_ms`, `hits`. `ip` is the `CF-Connecting-IP` header, or `unknown` when the header is missing. `window_start_ms` is the ABO clock truncated to 60 seconds. A new window resets `hits` to 1. The request that would make `hits` 61 answers HTTP 429 and does not increment past 60.

## 7. HMAC field list

`adapter_version` `1` pins this order, concatenated with no separator, HMAC-SHA512, lowercase hex, compared in constant time to the `hmac` query parameter (04 §5.3, processed-callback list):

`amount_cents`, `created_at`, `currency`, `error_occured`, `has_parent_transaction`, `id`, `integration_id`, `is_3d_secure`, `is_auth`, `is_capture`, `is_refunded`, `is_standalone_payment`, `is_voided`, `order.id`, `owner`, `pending`, `source_data.pan`, `source_data.sub_type`, `source_data.type`, `success`.

Booleans are `true` or `false`. Numbers are plain decimal strings. The processed callback reads them from `obj`. The response callback (GET) reads the same names from the query string (`order.id` as `order`). A missing, empty, or wrong-length `hmac` is a mismatch.

## 8. R2 keys

- Verified bodies: `evidence/notification/{notification_id}`.
- Inquiry JSON: `evidence/inquiry/{inquiry_id}`.
- HMAC failures: `hmac-invalid/{UTC-day}/{id}`. Each failure is one object and counts toward AL-02. At most 10 objects in an hour store the raw body; further objects in that hour are empty markers. No new D1 table for this counter.

## 9. Checkout rows this unit writes

It does not change the checkout API. Confirm inserts `checkout_event` (`kind` `paid` or `attempt_declined`, `source` `system`, `actor` `system`, `ref` the payment reference or the notification id, `contract_version` copied from `checkout`) and a matching `fact_log` row. `paid` sets `checkout_status.state` to `paid`. `attempt_declined` leaves `checkout_status.state` as `open`.
