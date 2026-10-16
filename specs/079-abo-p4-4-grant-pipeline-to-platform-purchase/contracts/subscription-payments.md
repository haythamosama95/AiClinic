# Contract: Subscription and payments responses

Frozen by P4.4. Clinic API on the billing hostname. Every call sends `Authorization: Bearer <billing token>` and `Abo-Contract-Version`. Every response, including errors, carries that header and a `contract_version` body field. The tenant is the token's `org` only. Error bodies stay the existing `{code, message, contract_version}` from 04 §2.3.

## 1. `GET /v1/subscription`

Request body: none.

Success HTTP 200:

```json
{
  "contract_version": 1,
  "subscription_ref": "AIC-XXXXXXXX",
  "snapshot": {},
  "notices": ["duplicate_payment"]
}
```

`contract_version` is the negotiated clinic version.

`subscription_ref` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`sub-ref:` ‖ the token's `org`). `vendor-contracts` `subscriptionRef` computes it. No lookup.

`snapshot` is the 04 §1.7 object from live `getCoverage` (`detail` parsed, then `snapshot`). When that call throws or `result` is not `ok`, `snapshot` is this tenant's `coverage_view.snapshot`. When that call fails and this tenant has no `coverage_view` row, `snapshot` is null. The success object is still returned.

`notices` is an array of code strings, in this order, including a code only when its condition holds:

| Code | Condition |
| --- | --- |
| `duplicate_payment` | A payment of this tenant has `classification` `likely_duplicate` |
| `late_payment_honoured` | A payment of this tenant has `classification` `late` |
| `payment_withheld` | A payment of this tenant has `disposition` `withheld_mismatch` |
| `reversal_recorded` | A `reversal` row exists for a payment of this tenant |
| `terms_held` | `snapshot` is an object and `snapshot.held_count` > 0 |

A null `snapshot` does not include `terms_held`. No other notice code is returned. Returning `reversal_recorded` or `terms_held` does not process a reversal.

## 2. `GET /v1/payments`

Query `cursor`: omitted or empty on the first page. Otherwise it is the previous page's last `reference`, the `PAY-` string unchanged.

Success HTTP 200:

```json
{
  "contract_version": 1,
  "payments": [
    {
      "reference": "PAY-XXXXXXXX",
      "paid_at": "2026-10-07T00:00:00.000Z",
      "amount_minor": 800,
      "currency": "EGP",
      "plan_display_name": "Clinic Pro Monthly",
      "offer_version": 1,
      "term_unit": "month",
      "term_count": 1,
      "classification": "normal",
      "reversals": [
        {
          "reference": "REV-XXXXXXXX",
          "amount_minor": 800,
          "kind": "refund",
          "is_full": true
        }
      ]
    }
  ],
  "next_cursor": "PAY-XXXXXXXX",
  "has_more": false
}
```

A page holds 20 payments of this tenant, ordered by `paid_at` ascending, then `reference` ascending. `next_cursor` is this page's last `reference`, or `""` when `payments` is empty. `has_more` is true when another payment of this tenant follows the page.

`plan_display_name` is the name `GET /v1/offers` returns for that payment's offer (`copy.en.name` on the published offer version). `offer_version` is the payment's `offer_version`. `term_unit` and `term_count` are the checkout snapshot. `classification` is `normal`, `likely_duplicate`, or `late`. `reversals` is the array of reversal rows for that payment. `kind` is `refund`, `void`, `chargeback`, or `unknown`. `is_full` is a JSON boolean: true when the stored integer is 1. This unit writes no reversal rows, so the array is empty until a later unit records one.

A `cursor` that is not a `reference` of this tenant is HTTP 422 `invalid_request`. Another tenant's token receives none of this tenant's payments.
