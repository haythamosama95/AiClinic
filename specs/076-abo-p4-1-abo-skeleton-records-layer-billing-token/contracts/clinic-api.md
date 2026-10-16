# Contract: ABO clinic API envelope, auth, and errors

**Unit**: P4.1 · **Requirements**: FR-002, FR-003, FR-004, FR-005, FR-006, FR-007

Later units extend this envelope and do not rewrite these rules. Checkouts, subscription, payments, and `/ops` console behavior stay with their units. This unit freezes the gate and the two catalogue routes.

N at launch is `CHANNEL_VERSIONS.aboClinic` and `CHANNEL_VERSIONS.aboConsole`, both 1. `acceptedVersions(1)` is `[0, 1]`.

## 1. Hosts

| Host var | Value in this unit's wrangler | Paths |
| --- | --- | --- |
| `BILLING_HOST` | `billing.vendor.test` | `/v1/`, `/notify/`, `/return/` |
| `OPS_HOST` | `ops.vendor.test` | `/ops/` |

`/ops/` on `BILLING_HOST` and `/v1/` on `OPS_HOST` are HTTP 404 with an empty body. That response has no `Abo-Contract-Version` header and no JSON body. It is decided before the version check and before authentication, and it writes nothing. A path this unit does not implement, on the host that owns that prefix, is the same empty 404.

## 2. Version gate

Every `/v1/` and `/ops/` request is checked here before authentication and before any write. The header is `Abo-Contract-Version`. A missing header or a value that is not an integer is passed to `negotiate` as `null`.

| Outcome | HTTP | Header `Abo-Contract-Version` | Body |
| --- | --- | --- | --- |
| Requested version is N or N−1 | Continue | The requested version, on the eventual response | `contract_version` echoes the requested version |
| Missing or outside N and N−1 | 400 | N | `{code, message, contract_version, accepted_versions}` |

Refusal fields: `code` is `contract_version_unsupported`, `message` is `contract_version_unsupported`, `contract_version` is N, `accepted_versions` is `[N−1, N]`. An invalid bearer on that request still receives this refusal.

## 3. Billing token

`/v1/` requires `Authorization: Bearer`. The ABO calls `validateTokenClaims` with `audience` `"abo"`, `issuerId` from `ISSUER_ID`, and the public key for the header `kid` in `ISSUER_KEYS` (or in `harness_issuer_pin` when `TEST_CLOCK` is `"1"`). It does not fetch keys.

| Case | HTTP | `code` |
| --- | --- | --- |
| Header missing, malformed, bad signature, unknown `kid`, `aud` other than `abo`, `ver` other than `"2"`, or `exp - iat` outside 0 through 300 | 401 | `unauthenticated` |
| Signature holds and `role` is not `administrator` | 403 | `forbidden_role` |
| `validateTokenClaims` returns `ok: true` | Continue | |

`validateTokenClaims` returns `ok: false` for both a bad token and a non-administrator role. The 403 is chosen only after the pinned key verifies the 04 §2.1 signature and the audience, `ver`, and lifetime hold. The tenant is payload `org`. An `org` field on a body is ignored.

## 4. Rate limit

After the token is accepted, `token_use.hits` for that `jti` may be at most 60. The 61st accepted presentation is HTTP 429 `rate_limited` and does not increment `hits`. The body is the error object in §5.

## 5. Error object

Clinic errors use HTTP status from 04 §2.3 and this body:

```json
{"code": "<code>", "message": "<code>", "contract_version": 1}
```

`message` equals `code`. The body does not echo the token, the phone, or contact fields. Header `Abo-Contract-Version` is the version the response answers in: the requested version when it was accepted, and N on `contract_version_unsupported`.

| `code` | HTTP | When this unit returns it |
| --- | --- | --- |
| `unauthenticated` | 401 | §3 |
| `forbidden_role` | 403 | §3 |
| `not_found` | 404 | `GET /v1/billing-contact` when this `org` has no row |
| `invalid_request` | 422 | `PUT` phone is not `^\+[1-9][0-9]{1,14}$`, or a required field is missing |
| `rate_limited` | 429 | §4 |
| `contract_version_unsupported` | 400 | §2. This code also includes `accepted_versions` |

`not_found` means this tenant has no contact. It is not the cross-host empty 404.

## 6. `GET /v1/offers`

Administrator token. No body.

```json
{
  "contract_version": 1,
  "offers": [
    {
      "offer_id": "<ulid>",
      "version": 2,
      "plan_display_name": "<copy.en.name>",
      "term_unit": "month",
      "term_count": 1,
      "price_minor": 1000,
      "currency": "EGP",
      "allowance_credits": 100,
      "grace_days": 7,
      "copy": {"en": {"name": "<name>", "summary": "<summary>"}},
      "terms": {"version": 1, "text": "<utf-8 from R2>"}
    }
  ]
}
```

`offers` contains one object per offer whose latest `offer_event` is `published`. `version` is the latest published version. A retired offer is absent. An older `offer_version` row is not a second object.

## 7. Billing contact

### 7.1 `GET /v1/billing-contact`

When this `org` has a row, the body is the current (greatest) version:

```json
{"contract_version": 1, "version": 1, "name": "<name>", "email": "<email>", "phone": "<phone>"}
```

When it has none, the response is 404 `not_found`.

### 7.2 `PUT /v1/billing-contact`

```json
{"client_request_id": "<id>", "name": "<name>", "email": "<email>", "phone": "+201001234567"}
```

A new `client_request_id` for this `org` inserts the next version and returns the GET shape for that version. The same `client_request_id` returns the already stored version and does not insert, including when `name`, `email`, or `phone` differ. The first version is 1. The next new request is version 2.
