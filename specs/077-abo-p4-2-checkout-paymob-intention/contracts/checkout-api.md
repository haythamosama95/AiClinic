# Checkout API (frozen)

Billing hostname. Consumed clinic envelope: `Abo-Contract-Version` on the response, `contract_version` in every JSON body, errors `{code, message, contract_version}` plus the extra fields named below. Tenant is the token `org` only.

## 1. `POST /v1/checkouts`

Request JSON: `client_request_id`, `offer_id`, `offer_version`, `terms_version`. A missing or non-string field is HTTP 422 `invalid_request`.

Checks, in order, after the consumed version, auth, and per-token rate gates:

1. Same `(org_id, client_request_id)` already stored: return that checkout and do not call Paymob again. `open` → HTTP 201 with the body below, `redirect_url` rebuilt by the adapter from the stored intention. `open_failed` → HTTP 503 `provider_unavailable`.
2. Ten `checkout` facts for this org already exist in the last hour on the ABO clock → HTTP 429 `rate_limited`.
3. No current billing contact (no row, or the latest row has `erased_at`) → HTTP 409 `billing_contact_required`.
4. `terms_version` is not the maximum `terms_version` in `terms_version` → HTTP 409 `terms_not_accepted`.
5. `(offer_id, offer_version)` is not that offer's current sellable version (latest `published` event's version) → HTTP 409 `offer_unavailable` with `current_version` set to that sellable version, or `null` when the offer has none.

Success HTTP 201:

| Field | Value |
| --- | --- |
| `contract_version` | Negotiated `aboClinic` version |
| `checkout_id` | ULID |
| `reference` | `CK-` plus the last 8 characters of `checkout_id` |
| `redirect_url` | `{PAYMOB_BASE_URL}/unifiedcheckout/?publicKey={PAYMOB_PUBLIC_KEY}&clientSecret={client_secret}` |
| `expires_at` | ABO clock plus 30 minutes, UTC ISO-8601 |
| `starts` | `after_current` when the coverage snapshot `state` is `active`; otherwise `now` |
| `projected_start` | Present only when `starts` is `after_current`. Equals `coverage_through` |

`coverage_source` and `opened_with_coverage_through` are stored on the fact. They are not response fields. The test reads them from D1.

Coverage read: `PLATFORM.getCoverage({ contract_version, org_id })` with `contract_version` = `CHANNEL_VERSIONS.vendorEntrypoint`. `result` `ok` and a snapshot → `coverage_source = live`. `result` `transient`, any other non-ok result, or a throw → read `coverage_view` for this org, `coverage_source = view`. A missing view row still creates the checkout, with `opened_with_coverage_through` null and `starts` `now`.

Provider refusal or abort → the checkout and an `open_failed` event are stored, `checkout_status.state` is `open_failed`, HTTP 503 `provider_unavailable`. Success stores `opened` and `state` `open`.

## 2. `GET /v1/checkouts/{id}`

Unknown id, or an id whose `org_id` is not the token `org` → HTTP 404 `not_found`.

HTTP 200:

| Field | Value |
| --- | --- |
| `contract_version` | Negotiated version |
| `reference` | |
| `shown_state` | `Waiting` when `state` is `open`. `Abandoned` when `state` is `open_failed` |
| `offer` | `{offer_id, version, term_unit, term_count, charged_price_minor, currency}` |
| `payment_reference` | `null` in this unit |
| `term_ref` | `null` in this unit |
| `updated_at` | `checkout_status.last_event_at` |

## 3. `GET /v1/checkouts?open=1`

HTTP 200 `{contract_version, checkouts}`. `checkouts` lists this org's rows whose `checkout_status.state` is `open`, `paid`, or `paid_late`, each with the GET-one object. This unit writes only `open` and `open_failed`. `open_failed` is not listed. Any other `GET /v1/checkouts` is HTTP 404 with an empty body, the same as an unknown billing path.
