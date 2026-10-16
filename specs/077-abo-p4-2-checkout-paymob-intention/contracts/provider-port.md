# Provider port (frozen)

Domain modules call `abo/src/provider/port.ts` types and `abo/src/provider/registry.ts`. They do not import `abo/src/provider/paymob/`. Only `adapter.ts` imports `client.ts`.

`provider_id` `paymob` selects the Paymob adapter. The registry is the only caller of the adapter outside the adapter module.

## 1. Operations

```text
capabilities(): {
  methods: string[]
  cancel_checkout: boolean
  refunds: boolean
  mandates: boolean
  payouts: boolean
  pending_notifications: boolean
}

createCheckout(input) →
  { ok: true, redirect_url, expires_at } |
  { ok: false }

cancelCheckout(checkout_id) → { result: "unsupported" }
```

`createCheckout` input: `checkout_id`, `reference`, `amount_minor`, `currency`, `item_name`, `payer {name, email, phone}`, `expires_in_s`, `return_url`, `notify_url`.

Paymob `createCheckout`:

- `POST {PAYMOB_BASE_URL}/v1/intention/`
- `Authorization: Token {PAYMOB_SECRET_KEY}`
- JSON: `amount` = `amount_minor` (piastres), `currency` = `EGP`, `payment_methods` = `[PAYMOB_CARD_INTEGRATION_ID]` as a number, one `items` entry (`name` = `item_name`, `amount` = `amount_minor`, `quantity` = 1), `billing_data` from the payer (`first_name` / `last_name` split on the first space; a single word is used for both; `email`; `phone_number`), `special_reference` = `reference`, `expiration` = 1800, `notification_url` = `notify_url`, `redirection_url` = `return_url`
- `expires_in_s` is 1800
- `notify_url` is `https://{BILLING_HOST}/notify/paymob`
- `return_url` is `https://{BILLING_HOST}/return/paymob?v={CHANNEL_VERSIONS.paymobReturn}` (`v` is 1)
- Store `id`, `intention_order_id`, `client_secret`, `special_reference`, and `expires_at` on `paymob_intention`
- `redirect_url` is `{PAYMOB_BASE_URL}/unifiedcheckout/?publicKey={PAYMOB_PUBLIC_KEY}&clientSecret={client_secret}`
- When a `paymob_intention` row already exists for `checkout_id`, return that redirect and do not call Paymob
- Non-2xx or abort → `{ ok: false }` and no `paymob_intention` row
- Abort after 10 s. When `TEST_CLOCK` is `"1"`, abort after 500 ms

`capabilities` for Paymob returns `cancel_checkout: false`, `refunds: false`, `mandates: false`, `payouts: false`, `pending_notifications: false`, and `methods: ["card"]`.

`cancelCheckout` returns `{ result: "unsupported" }` and performs no HTTP call.

The checkout handler calls `createCheckout`. `capabilities` and `cancelCheckout` are methods on that same adapter object.
