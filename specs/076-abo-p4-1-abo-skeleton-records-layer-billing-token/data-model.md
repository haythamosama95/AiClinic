# Data Model: ABO skeleton, records, and catalogue

**Unit**: P4.1 · **Requirements**: FR-006, FR-007, FR-008, FR-009

D1 binding `DB`. R2 binding `R2`. Migration `abo/migrations/0001_records.sql`. The harness creates the two harness tables itself. Product code reads them only when `TEST_CLOCK` is `"1"`.

## 1. Conventions

Ids that the spec calls ULIDs are `ulid` from `vendor-contracts` with the clock time and 10 random bytes. Money is an integer minor amount plus a 3-letter ISO 4217 currency. Times are UTC ISO-8601 from `clock.ts`. `contract_version` on a stored row is the accepted `Abo-Contract-Version` of the message that wrote it. Seeded offer rows use `1`. Tenant reads and writes use the token `org` as `org_id` and are backed by an index.

Append-only tables have `BEFORE UPDATE` and `BEFORE DELETE` triggers that `RAISE(ABORT, 'append_only')`.

## 2. Append-only catalogue

### 2.1 `offer`

| Column | Rule |
| --- | --- |
| `offer_id` | ULID, primary key |
| `code` | Stable slug, unique |
| `contract_version` | Integer |

`fact_log.key` is `offer_id`.

### 2.2 `offer_version`

| Column | Rule |
| --- | --- |
| `offer_id` | |
| `version` | Integer ≥ 1 |
| `plan_id` | Text |
| `plan_version` | Integer |
| `term_unit` | `month` |
| `term_count` | 1, 3, or 12 |
| `price_minor` | Integer |
| `currency` | ISO 4217 |
| `allowance_credits` | Integer |
| `grace_days` | 7 in the fixture |
| `grace_cap_rule` | `proportional` |
| `copy` | JSON text, per-locale `{name, summary}` |
| `terms_version` | |
| `published_by` | Text |
| `assertion_sha256` | Text |
| `contract_version` | Integer |

Primary key `(offer_id, version)`. `fact_log.key` is `offer_id` + `:` + `version`. Past versions stay in this table. `GET /v1/offers` returns only the sellable latest one.

### 2.3 `offer_event`

| Column | Rule |
| --- | --- |
| `offer_id` | |
| `kind` | `published`, `retired`, or `reinstated` |
| `version` | The offer version this event names |
| `actor` | Text |
| `at` | UTC ISO-8601 |
| `contract_version` | Integer |

Primary key `(offer_id, kind, version, at)`. `fact_log.key` is those four fields joined by `:`. An offer is sellable when the row with the greatest `at` for that `offer_id` has `kind` `published`. The sellable version is the greatest `version` on a `published` event for that offer.

### 2.4 `terms_version`

| Column | Rule |
| --- | --- |
| `terms_version` | Integer |
| `locale` | `en` in the fixture |
| `text_r2_key` | R2 key of the terms text |
| `text_sha256` | Hex SHA-256 of that UTF-8 text |
| `published_by` | Text |
| `contract_version` | Integer |

Primary key `(terms_version, locale)`. `fact_log.key` is `terms_version` + `:` + `locale`.

## 3. Billing contact

`billing_contact` is insert-only. This unit does not update or delete it. No abort trigger, so a later erasure unit can update the row.

| Column | Rule |
| --- | --- |
| `org_id` | Token `org` |
| `version` | Integer, starts at 1 per `org_id` |
| `client_request_id` | Idempotency key |
| `name` | Text |
| `email` | Text |
| `phone` | E.164 |
| `contact_sha256` | `sha256Hex(canonicalize({name, email, phone}))` |
| `created_by_sub` | Token `sub` |
| `contract_version` | Accepted request version |
| `erased_at` | Null in this unit |
| `erased_by` | Null in this unit |

Primary key `(org_id, version)`. Unique `(org_id, client_request_id)`. Index `(org_id, version)`. This table has no `fact_log` row. Its columns do not appear in `ledger/` objects.

## 4. Facts

### 4.1 `fact_log`

One row per append-only insert, written in the same D1 batch as that insert.

| Column | Rule |
| --- | --- |
| `fact_seq` | Integer primary key, ascending |
| `table` | `offer`, `offer_version`, `offer_event`, or `terms_version` |
| `key` | The key named on that table |
| `row_sha256` | `sha256Hex(canonicalize(row))` of the appended columns |
| `created_at` | `clockNowIso` at insert. Export lag is `clockNowMs` minus this time |

`created_at` is the clock time FR-009 compares. The cited `fact_log` tuple has no time column, and the one-hour stall needs one.

### 4.2 `fact_export`

| Column | Rule |
| --- | --- |
| `fact_seq` | Primary key, references the exported fact |
| `exported_at` | `clockNowIso` when the put succeeds |

Insert-only. The exporter writes the lowest `fact_seq` that has no `fact_export` row, puts `ledger/<fact_seq>.ndjson`, then inserts this row. `<fact_seq>` is decimal with no padding. The object body is one JSON line, `canonicalize({fact_seq, table, key, row_sha256})`. A failed put writes no later fact.

## 5. Token use

`token_use` is mutable. It is not append-only and it is not exported.

| Column | Rule |
| --- | --- |
| `jti` | Primary key |
| `org_id` | Token `org` |
| `hits` | Integer |

Index `(org_id)`. A request that passes `validateTokenClaims` increments `hits` when `hits` is below 60. At 60 the response is 429 and `hits` stays 60.

## 6. Alert

`alert` is mutable. It is not append-only and it is not exported.

| Column | Rule |
| --- | --- |
| `alert_key` | Primary key |
| `code` | `AL-16` |
| `active` | 1 while the condition holds, 0 when it has cleared |
| `unsent` | 1 when a send is due or the last send threw |
| `last_sent_at` | UTC ISO-8601, null until a send succeeds |
| `next_send_at` | UTC ISO-8601. After a success, 24 hours after `last_sent_at` |
| `detail_id` | `fact_seq` decimal for export lag, or `r2-lock` for the lock |

| `alert_key` | When it becomes due |
| --- | --- |
| `AL-16:export-lag` | The oldest unexported `fact_log.created_at` is more than one hour before the clock. Evaluated on the minute cron, after export. |
| `AL-16:r2-lock` | The daily lock GET returns `success` true and `result.rules` has no enabled rule whose `condition.type` is `Indefinite` and whose `prefix` is `ledger/` or empty. |

A successful send sets `unsent` 0, `last_sent_at` now, and `next_send_at` 24 hours later. While `active` is 1 and the clock has reached `next_send_at`, the next send path sets `unsent` 1 and sends again. A thrown `send_email` leaves `unsent` 1. Clearing sets `active` 0 and `unsent` 0. A lock GET that is not `success` true does not insert, due, or clear `AL-16:r2-lock`.

The email body is `AL-16` plus `detail_id`. It does not contain `name`, `email`, or `phone`.

## 7. Harness tables

Created by `abo/test/system/harness.ts`, not by `0001_records.sql`.

| Table | Columns | Read |
| --- | --- | --- |
| `harness_test_clock` | `id` (`default`), `now_iso` | `clock.ts` when `TEST_CLOCK` is `"1"` |
| `harness_issuer_pin` | `kid`, `public_key` | `auth.ts` when `TEST_CLOCK` is `"1"` and the table has at least one row |

`public_key` is the base64url raw 32-byte Ed25519 key.

## 8. Fixture

`abo/fixtures/offers.json` loads through `records/append.ts`. It contains:

- One offer whose latest event is `published`, with an older `offer_version` and a later published version. The GET returns the later version only.
- One offer whose latest event is `retired`. The GET omits it.
- One `terms_version` whose R2 object, at `text_r2_key`, is the terms text the GET returns.

`copy` includes `en.name` and `en.summary`. `plan_display_name` in the response is `en.name`.
