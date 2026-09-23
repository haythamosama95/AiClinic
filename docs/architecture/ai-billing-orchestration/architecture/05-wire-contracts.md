# AI Billing Orchestration — Wire Contracts

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.
**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [5. Wire contracts](#5-wire-contracts)
  - [5.1 Canonicalization rules](#51-canonicalization-rules)
  - [5.2 Order payload and clinic proof of possession](#52-order-payload-and-clinic-proof-of-possession)
  - [5.3 `POST /v1/orders` (AI Billing Orchestrator)](#53-post-v1-orders-ai-billing-orchestrator)
  - [5.4 `GET /v1/orders/{order_id}` (AI Billing Orchestrator)](#54-get-v1-orders-order_id-ai-billing-orchestrator)
  - [5.5 `POST /v1/webhooks/{provider}` (AI Billing Orchestrator)](#55-post-v1-webhooks-provider-ai-billing-orchestrator)
  - [5.6 CAT — Control Action Token](#56-cat-control-action-token)
  - [5.7 Purchase Proof](#57-purchase-proof)
  - [5.8 Provisioning Receipt](#58-provisioning-receipt)
  - [5.9 Platform status and key endpoints](#59-platform-status-and-key-endpoints)
  - [5.10 `GET /v1/plans` (ai-platform)](#510-get-v1-plans-ai-platform)

---

## 5. Wire contracts

All HTTP paths on both origins are versioned: client/ops endpoints under `/v1/…`, server-to-server control-plane endpoints under `/control/v1/…`. A breaking change increments the version prefix; unversioned paths are never served.

### 5.1 Canonicalization rules

**There is no JSON canonicalization anywhere in this design.** Every signature covers the exact
bytes transported:

- JWS compact serialization is self-canonicalizing: the signed input is the literal
`base64url(header) || "." || base64url(payload)` string. Verifiers recompute over the received
segments, never over a re-serialized parse — this is already how `EnrolledKeyVerifier` and
`auth_internal.verify_aat` work.
- The clinic-signed order payload (§5.2) is signed **as produced by the RPC** and transported
verbatim as a string field; the AI Billing Orchestrator verifies the signature over those exact bytes before
parsing. Field order, whitespace, and number formatting are therefore irrelevant.
- The CAT body hash (§5.6) is SHA-256 over the **raw request body bytes**; for routes that read
no body (existing body-ignoring routes such as `suspend`), it is the hash of the empty string.

This removes the entire class of canonicalization mismatches between Postgres, Workers, and
Flutter. The cost — payloads must be transported unmodified — is paid by making the payload an
opaque string in every envelope that carries it.

All three JWS types pin `alg: "EdDSA"` in the header and reject anything else, matching the
existing verifier (`header.alg !== "EdDSA"` → reject) so `none`/HMAC confusion is impossible.

**The replay-guard co-location rule.** Every single-use credential in this system is consumed in
the same store and the same atomic unit as the action it protects: the CAT `jti` inserts with the
control mutation, the purchase proof `jti` inserts in the grant's D1 batch, the webhook event id
inserts with event processing, the AAT `jti` lives in the Quota DO that admits the request. A
replay guard that lives outside the enforcing store — or commits in a separate transaction — is
a race window, not a guard. This is why each service keeps its own replay tables rather than
sharing one.

**Error style.** Two families, named once: clinic-facing data-path endpoints (platform `/v1/*`)
use the taxonomy envelope (`{ code, request_reference, trace_id, retry_safe, … }`);
control-plane-family endpoints — platform `/control/v1/*` and **all AI Billing Orchestrator endpoints** —
use the flat `{"error": "<snake_code>"}` body. Flutter maps ABO error codes to UI states; the
taxonomy machinery is not imported into the AI Billing Orchestrator.

### 5.2 Order payload and clinic proof of possession

The clinic's order-signing RPC (§9.1) returns two strings; Flutter transports them unmodified:

```json
{
  "order_payload": "{\"display_name\":\"…\",\"installation_id\":\"…\",…}",
  "signature": "<base64url Ed25519 detached signature over the UTF-8 bytes of order_payload>"
}
```

`order_payload` is a JSON object with **exactly** these fields (produced by
`jsonb_build_object`, which fixes key order alphabetically — a convenience, not a requirement,
since the bytes are signed as-is):


| Field             | Source                                     | Consumed by                                                   |
| ----------------- | ------------------------------------------ | ------------------------------------------------------------- |
| `installation_id` | `ai_internal.installation_keys` active row | ABO `orders`; platform enroll path equality check             |
| `kid`             | active key row                             | ABO `orders`; platform enroll                                 |
| `public_key`      | active key row, base64url                  | ABO PoP verification; platform enroll                         |
| `plan`            | RPC argument, validated non-empty          | ABO catalogue check (cached `GET /v1/plans`); platform enroll → `entitlement.plan` |
| `org_id`          | clinic `organizations.id`                  | enroll metadata                                               |
| `display_name`    | clinic org name                            | enroll metadata                                               |
| `region`          | app setting / RPC default                  | enroll metadata                                               |
| `nonce`           | `gen_random_uuid()`                        | single-use freshness at order creation                        |
| `issued_at`       | `clock_timestamp()`                        | the AI Billing Orchestrator rejects payloads older than 24 h  |


Billing verifies the signature with the `public_key` **inside the payload** — at order time the
platform does not know the clinic yet, so this is self-signed proof of possession, not
authentication against a registry. That is sufficient because of how the chain closes: the paid
order binds money to `(installation_id, kid, public_key)`; the purchase proof carries the same
triple; platform enroll registers exactly that key; and from then on every AAT must verify
against it. An attacker who substitutes their own keypair has bought AI service for an
installation only they can mint tokens for — payment redirection gains nothing.

### 5.3 `POST /v1/orders` (AI Billing Orchestrator)

Unauthenticated in the HTTP sense — the PoP signature **is** the authorization. Rate-limited per
source IP at the platform edge (Cloudflare rate-limiting rule, same mechanism family as the
ai-platform `[env.*.ratelimits]` bindings).

**Request:**

```json
{ "order_payload": "<string>", "signature": "<base64url>" }
```

**Verification order:** JSON parse → required fields → payload age (`issued_at` within 24 h) →
`public_key` decodes to 32 bytes → `crypto.subtle.verify` over exact payload bytes → plan exists
in the platform catalogue (cached `GET /v1/plans` fetch, §4.1.6) → no live order for
`installation_id` (partial unique index, §4.1).

**Then:** insert `orders` (`status = pending`; `installation_id` / `kid` / `public_key` stored as
the as-purchased identity snapshot, §4.1.2; poll token generated — 256-bit random, stored as
SHA-256 hex) → adapter `create_checkout(order, price)` with the catalogue's current price for the
plan → store returned refs in `provider_refs` → update `checkout_url`.

**Success** `201`**:**

```json
{
  "order_id": "<uuid>",
  "status": "pending",
  "checkout_url": "https://…",
  "checkout_expires_at": "<ISO>",
  "poll_token": "<256-bit random, base64url>"
}
```

`poll_token` is returned **once**, here, and never again (only its hash is stored).

**Errors:** `400 invalid_payload` (shape/age/key), `400 invalid_signature`,
`404 plan_not_found`, `409 order_exists` (a live order already exists for this installation —
the response includes that order's `order_id` so a restarted client can resume, but **not** a
new poll token), `502 provider_error`, `502 catalogue_unavailable` (the platform catalogue fetch
failed — retryable; §4.1.6).

### 5.4 `GET /v1/orders/{order_id}` (AI Billing Orchestrator)

Polled by Flutter during purchase and renewal. Auth: `Authorization: Bearer <poll_token>`,
compared as SHA-256 hex against `poll_token_hash` (timing-safe string compare, same helper
family as `timingSafeEqualString` in `control/auth.ts`). An unknown order **or** a wrong token
returns the same `404` — order existence is not enumerable.

**Success** `200`**:**

```json
{
  "order_id": "<uuid>",
  "status": "pending | paid | provisioned | past_due | refunded | chargeback | expired | cancelled",
  "plan": "standard",
  "period_start": "<ISO|null>",
  "period_end": "<ISO|null>",
  "grace_until": "<ISO|null>",
  "checkout_url": "<string|null>",
  "checkout_expires_at": "<ISO|null>"
}
```

`checkout_url` is non-null while payable: initially, and again from `period_end − grace_days`
until terminal state (the renewal checkout, §6.3). No provider identifiers, no amounts beyond what the
clinic already knows — the response is provider-agnostic by construction.

`POST /v1/orders/{order_id}/renewal-checkout` — the self-service plan-change and on-demand
renewal path. Auth: the same poll-token Bearer rule as the GET, with the same uniform `404`.
Body `{ "plan": "<plan name>" }`. Valid while the order is `provisioned` or `past_due`.
Validates the plan against the platform catalogue (cached `GET /v1/plans` fetch, §4.1.6), runs
the adapter `create_checkout` for that plan's
current catalogue price, stores the new refs in `provider_refs`, and replaces `checkout_url` /
`checkout_expires_at` on the order. The new plan takes effect when the renewal is paid and
`renew` applies it (§6.4).

**Key-rotation re-validation.** Before opening the checkout, the AI Billing Orchestrator
re-validates the order's key material against the platform through an authenticated read
(orchestrator-scoped `quota-inspect` / `support-lookup`, §5.6): the `kid` / `public_key` in the
order's as-purchased snapshot (§4.1.2) must still be the installation's active enrolled key. If
the clinic has rotated keys since the order was created, the order **must be re-created** — the
endpoint fails with `409 key_rotated` and the clinic starts a fresh order with a newly signed
payload (§5.3), because the purchase proof and enroll bind the as-purchased key material and a
renewal cannot re-bind them. The order clock's pre-issued renewal checkouts (§11.1) run the
same check before calling the adapter.

Errors: `400 invalid_payload`, `404 plan_not_found`,
`409 illegal_state` (terminal orders), `409 key_rotated` (clinic rotated keys — fresh order
required), `502 provider_error`, `502 catalogue_unavailable`.
When the order's current plan has been retired, this endpoint is the **only** renewal checkout
path — the order clock does not pre-issue a URL for non-sellable plans (§6.6).

### 5.5 `POST /v1/webhooks/{provider}` (AI Billing Orchestrator)

The only provider-shaped surface in the system, and it is owned entirely by the adapter.

**Verification order (Paymob):** extract `hmac` query parameter → parse body → recompute
HMAC-SHA512 over the documented 20-field concatenation of `body.obj` (booleans as literal
`true`/`false`, no separators) keyed by `PAYMOB_HMAC_SECRET` → timing-safe hex compare →
idempotency lookup on `(provider, provider_event_id)`: already present → return `200` with no
re-processing, regardless of the event's age → resolve order via `provider_refs`
(`obj.order.id` / transaction id) → insert `webhook_events` → map to canonical event →
transition the order (§6.1) → enqueue outbox rows.

The idempotency table is the authoritative replay guard; there is **no timestamp rejection
gate**. A replayed authentic payload is either already processed (duplicate → `200`) or a
legitimate event whose first delivery never completed — processing it is correct. A time-based
rejection would lose exactly those legitimate redeliveries, which arrive with the provider's
original timestamp long after the first attempt. `obj.created_at` is recorded on the
`webhook_events` row for observability only.

Failures before the idempotency insert return `400`; the provider retries. Failures after it are
retried by the outbox mechanism, not by the provider. The endpoint always responds `200`
to a well-formed, authentic duplicate.

After the D1 batch commits (order transition, purchase proof, outbox row), the handler sends a
Cloudflare Queue message carrying the new row's `outbox_id` — provisioning starts in seconds,
and the HTTP response to the provider is returned without awaiting the consumer. If the consumer
attempt fails, the queue retries with managed backoff; exhausted retries dead-letter and the row
is marked `failed` (§11.1).

The **redirect URL** (`redirection_url` on the intention) is UX only — its query parameters are
not trusted for order state (Paymob's own guidance: the callback is authoritative). Flutter
never sees it; the clinic owner simply closes the browser tab and the app's polling observes the
webhook's effect.

### 5.6 CAT — Control Action Token

Replaces the operator bearer on **every** control route — the bearer is removed, not scoped
(§8.1). Compact JWS, sent as
`Authorization: CAT <token>`.

**Header:** `{ "alg": "EdDSA", "kid": "<control_operator.key_id>" }`

**Claims:**


| Claim         | Value                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------- |
| `iss`         | `operator_id` (e.g. `orchestrator`, or a human's id)                                     |
| `aud`         | `"ai-platform-control"`                                                                  |
| `iat` / `exp` | Unix seconds; `exp − iat ≤ 120` enforced                                                 |
| `jti`         | UUID; single-use (§4.2 `control_cat_jti`)                                                |
| `act`         | The control action: `enroll`                                                             |
| `tgt`         | Target installation id for installation-scoped actions; `""` otherwise                   |
| `bh`          | Base64url SHA-256 of the raw request body bytes (empty-string hash for body-less routes) |


**Verification order** (new CAT `OperatorAuth` factory, §8.1): three-segment structure →
`alg` pin → `kid` → `control_operator` row (not revoked) → Ed25519 signature → `aud` →
`iat`/`exp` with 60 s skew and max-lifetime check (mirrors `MAX_AAT_LIFETIME_SECONDS`) →
`act` equals the route's action **and** is in the row's `allowed_actions` → `tgt` equals the
path installation id where applicable → `bh` equals SHA-256 of the raw body (the auth layer
reads `request.clone()` so handlers still parse the body normally) → `jti` insert-if-absent
(conflict → `401`). Any failure → `401 { "error": "unauthorized" }` — the control plane keeps
its no-403 convention.

The orchestrator's key holds exactly `["enroll","entitle","renew","entitlement-suspend","quota-inspect","support-lookup"]`.
Human keys hold their roles' subsets. **No key holds both a grant action and the purchase proof
signing key's job** — the two-signature rule is enforced by key custody, not by code
convention.

### 5.7 Purchase Proof

Minted by the AI Billing Orchestrator purchase module when money moves (or a comp order is issued); verified by the platform's `enroll` and
**consumed** only by `entitle` / `renew` / `override`. `enroll` never consumes the `jti`: it
grants nothing (the entitlement it creates stays `pending` with zero quotas), and its replay is
already blocked by `409 already_enrolled` and the purchase proof's installation binding — so the
provision flow can present the same purchase proof to `enroll` and then to `entitle`, which claims
the `jti`. Compact JWS, carried in the control request body as `{ "purchase_proof": "<token>" }`.

**Header:** `{ "alg": "EdDSA", "kid": "bill-<n>" }`

**Claims:**


| Claim                         | Value                                                                                    |
| ----------------------------- | ---------------------------------------------------------------------------------------- |
| `iss`                         | Billing issuer id (platform var `BILLING_ISSUER`, e.g. `"ai-billing-orchestrator"`)      |
| `aud`                         | `"ai-platform-control"`                                                                  |
| `jti`                         | `purchase_proof_id` (UUID) — replay key into the platform `purchase_proof` table         |
| `iat` / `exp`                 | `exp = iat + 72 h` — sized for outbox retry windows; single-use makes a long life safe   |
| `kind`                        | `purchase` \| `renewal` \| `comp`                                                        |
| `order_id`                    | Billing order UUID                                                                       |
| `installation_id`             | Bound installation                                                                       |
| `kid` / `public_key`          | Clinic key material from the order (enroll validates the body against these)             |
| `plan`                        | Plan name — resolved through the plan catalogue by the handler, never trusted as economics |
| `period_start` / `period_end` | ISO-8601 instants; `period_start < period_end`                                           |
| `amount_cents` / `currency`   | The price actually paid for this period (`0` for comp orders) — stored on the platform `purchase_proof` row at consumption so period-close invoicing prices the invoice from what was paid, never from a catalogue re-lookup (A17) |


**Platform verification (shared verifier module):** structure → `alg` pin → `kid` → public key
from `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` within its validity window → signature → `iss`/`aud` →
`exp`/`iat` with 60 s skew → `installation_id` equals the path id → action-specific checks:
`enroll` additionally requires body `kid`/`public_key`/`plan` equal to the claims; `entitle`
requires `kind ∈ {purchase, comp}` and entitlement `pending`; `renew` requires entitlement
`active` or `suspended`; `override` requires `kind = comp`. The `entitle` / `renew` / `override` batch then inserts
`purchase_proof` (jti …) — a conflict rolls the grant back with `409 purchase_proof_replayed`.

### 5.8 Provisioning Receipt

Minted by the platform inside `GET /v1/installation/status` when (and only when) the
installation and entitlement are both `active`. Compact JWS, transported by Flutter, verified by
the clinic's `set_ai_availability` RPC.

**Header:** `{ "alg": "EdDSA", "kid": "rcpt-<n>" }`

**Claims:**


| Claim               | Value                                                                            |
| ------------------- | -------------------------------------------------------------------------------- |
| `iss`               | `"ai-platform"`                                                                  |
| `aud`               | The `installation_id` — a receipt for clinic A cannot activate clinic B          |
| `iat` / `exp`       | `exp = iat + 15 min` — the receipt is a transport proof, not a stored credential |
| `status`            | `"active"` (receipts are never minted for any other state)                       |
| `plan`              | Current plan name (display only)                                                 |
| `period_end`        | Current paid period end                                                          |
| `valid_until`       | `period_end + grace_days` from the plan catalogue (§5.10) — the clinic-side self-expiry instant (§6.3) |
| `platform_base_url` | The Worker's origin — what the clinic stores and calls                           |


**Clinic verification** (`auth_internal.set_ai_availability`, §9.2): three segments → header
`alg = EdDSA` → `kid` found in `ai.platform_receipt_keys` and not revoked →
`pgsodium.crypto_sign_verify_detached` over the exact signing input (the
`verify_aat` pattern) → `iss` → `aud` equals the clinic's own `installation_id` →
`exp` not passed → `status = "active"`. Only then is `ai.availability` written.

### 5.9 Platform status and key endpoints

`GET /v1/installation/status` — AAT-authenticated, reusing `EnrolledKeyVerifier` exactly as
discovery and the journal GET do (`authenticateGetRequest` pattern, audience `"ai-platform"`,
60 s skew). Identity passes for an enrolled installation even while its entitlement is
`pending` or `suspended` — that is what makes pull-based activation and self-healing work.

Success `200`:

```json
{
  "installation_id": "<uuid>",
  "installation_status": "active",
  "entitlement_status": "pending | active | suspended",
  "plan": "standard",
  "period_end": "<ISO|null>",
  "receipt": "<compact JWS — present only when both statuses are active>"
}
```

Errors follow the taxonomy: `401 unauthenticated`, `403 installation_suspended`. Reads come
from the config cache (warm isolate: no D1 I/O, the A5 pattern); receipt signing is one
`crypto.subtle.sign` per call — no DO, no journal row.

`GET /v1/platform-keys` — unauthenticated, cacheable:

```json
{ "keys": [ { "kid": "rcpt-1", "kty": "OKP", "crv": "Ed25519", "x": "<base64url>", "valid_from": "<ISO>" } ] }
```

Served from the `PLATFORM_RECEIPT_PUBLIC_KEYS` var. Flutter fetches it during activation and
re-fetches once on `unknown kid` receipt-verification failure (§3.5).

### 5.10 `GET /v1/plans` (ai-platform)

The sellable-plan read path — served by the **platform**, not the AI Billing Orchestrator, because the
platform's `plan` catalogue is the single plan and pricing catalogue (platform amendment A17;
§4.1.6). Unauthenticated and cacheable, edge rate-limited; prices are not secrets — they are
displayed on the provider's hosted checkout page — so the endpoint needs no credential, mirroring
the `GET /v1/platform-keys` precedent (§5.9). Reads come from the config cache (warm isolate: no
D1 I/O, the A5 pattern).

**Success `200`:**

```json
{
  "plans": [
    {
      "plan": "standard",
      "display_name": "Standard",
      "description": "…",
      "price_cents": 150000,
      "currency": "EGP",
      "grace_days": 7
    }
  ]
}
```

- **Source:** `plan` rows with `status = 'active'`, served from the config cache — exactly the
  active rows, each with price and `grace_days` (pinned by the §4.1.6 contract test).
  `grace_days` is the single source for dunning timing on both sides: the ABO order clock
  (§11.1) reads it from this payload, and receipt minting computes
  `valid_until = period_end + grace_days` from the same value (§5.8).
- **Caching:** `Cache-Control: public, max-age=300`. A price change propagates to clients within
  minutes; open periods are never repriced (the paid amount is bound into the purchase proof,
  §5.7), so staleness can only delay a *new* price's visibility, never misquote an open period.
- The response is identical for every caller: no per-clinic data, no provider identifiers.

Two consumers: Flutter calls this when the purchase surface opens and when the renewal banner
renders plan selection (§10.1, §10.3) — plan names, prices, and display copy are never shipped in
the app; and the AI Billing Orchestrator purchase module fetches it server-side (cached, §4.1.6) to
validate and price `POST /v1/orders`, renewal checkouts, and comp orders.

