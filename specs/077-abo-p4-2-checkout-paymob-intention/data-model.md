# Data model: P4.2 checkout, intention, coverage view

ABO D1. New migration `abo/migrations/0002_checkout.sql`. Ids are ULIDs from `ulid` in `vendor-contracts`. Times are UTC ISO-8601. Money is an integer in minor units plus the offer currency. Append-only tables use `BEFORE UPDATE` and `BEFORE DELETE` triggers that `RAISE(ABORT, 'append_only')`. Each insert into an append-only table also inserts `fact_log` (`table`, key, SHA-256 of the canonical row, `created_at` from the ABO clock). `contract_version` on a fact is the negotiated `aboClinic` version. Mutable tables have no `fact_log` row.

`paymob_intention` is written only by `abo/src/provider/paymob/adapter.ts`.

## 1. `checkout` (append-only)

Primary key `checkout_id`. Unique `(org_id, client_request_id)`. Index on `org_id`.

| Column | Notes |
| --- | --- |
| `checkout_id` | ULID |
| `reference` | `humanRef("CK", checkout_id)` |
| `org_id` | Token `org` |
| `created_by_sub` | Token `sub` |
| `billing_token_jti` | Token `jti` |
| `client_request_id` | |
| `offer_id`, `offer_version` | Requested pair, after it is accepted as current |
| `plan_id`, `plan_version`, `term_unit`, `term_count` | Snapshot from `offer_version` |
| `allowance_credits`, `grace_days`, `grace_cap_rule` | Snapshot |
| `list_price_minor`, `charged_price_minor` | Both the offer `price_minor` (`adjustment_id` is null) |
| `adjustment_id` | Always null in this unit |
| `currency` | Snapshot |
| `terms_version` | Snapshot |
| `billing_contact_version`, `billing_contact_sha256` | Current contact |
| `opened_with_coverage_through` | ISO time, or null when neither live coverage nor `coverage_view` has a snapshot |
| `coverage_source` | `live` or `view` |
| `provider_id` | `paymob` |
| `initiator` | `payer` |
| `expires_at` | Clock plus 30 minutes |
| `contract_version` | |

The hourly cap counts `fact_log` rows for `table = 'checkout'` whose key is one of this org's `checkout_id`s and whose `created_at` is inside the last hour on the ABO clock.

## 2. `checkout_event` (append-only)

Primary key `(checkout_id, kind, at)`. This unit inserts one event per checkout.

| Column | Notes |
| --- | --- |
| `checkout_id` | |
| `kind` | `opened` or `open_failed` in this unit |
| `source` | `system` |
| `ref` | Checkout `reference` |
| `actor` | `created_by_sub` |
| `at` | ABO clock |
| `contract_version` | |

Fact key is `checkout_id` + `kind` + `at`.

## 3. `checkout_status` (mutable)

Primary key `checkout_id`.

| Column | Notes |
| --- | --- |
| `checkout_id` | |
| `state` | `open` or `open_failed` |
| `last_event_at` | The event `at` |

Shown state is derived, not stored: `open` → Waiting; `open_failed` → Abandoned.

## 4. `paymob_intention` (adapter)

Primary key `checkout_id`.

| Column | Notes |
| --- | --- |
| `checkout_id` | |
| `intention_id` | Intention response `id` |
| `order_id` | Intention response `intention_order_id` |
| `client_secret` | |
| `special_reference` | The checkout `reference` |
| `expires_at` | Same instant as `checkout.expires_at` |

## 5. `coverage_view` (mutable)

Primary key `org_id`.

| Column | Notes |
| --- | --- |
| `org_id` | |
| `binding_epoch` | Integer |
| `clinic_seq` | Integer |
| `snapshot` | JSON text of the platform coverage snapshot |

An event replaces the row only when `(binding_epoch, clinic_seq)` is strictly greater than the stored pair (epoch first, then seq). A missing row accepts the first event. An equal or older pair leaves the row unchanged.

## 6. `feed_cursor` (mutable)

One row, primary key `id = 1`.

| Column | Notes |
| --- | --- |
| `id` | Always 1 |
| `feed_seq` | Last platform `feed_seq` read. Starts at 0 when the row is absent |

The cursor advances to the last `feed_seq` read even when that event's pair is ignored.
