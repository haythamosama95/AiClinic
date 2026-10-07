# Data model: P5.1 issuer key custody and token issuance

Entities are the ones in spec §3.2. The migration is `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`. It does not edit `20260801120000_ai_keystore_schema.sql` or `20260905120300_fix_aat_lifetime_fallback.sql`.

## 1. `ai_internal.issuer_key`

New table in non-exposed `ai_internal`. RLS is on. The policy is deny-all. No grant to `anon`, `authenticated`, or `service_role`. Clinic roles reach it only through the definer functions in this plan.

| Column | Type | Notes |
| --- | --- | --- |
| `kid` | `text` primary key | `gen_random_uuid()::text` |
| `public_key` | `text` not null | Base64url of the raw 32-byte Ed25519 public key |
| `secret_ref` | `uuid` not null | `vault.secrets.id`. The private key is the base64 text stored by `vault.create_secret`. No plaintext key column |
| `status` | `text` not null | `signing`, `next`, or `retired` |
| `not_before` | `timestamptz` not null | Insert time |
| `not_after` | `timestamptz` not null | `not_before + interval '13 months'`, and later than `not_before` |

Exactly one row has `status = 'signing'` (partial unique index). At most one row has `status = 'next'` (partial unique index). `retired` no longer signs. The first insert is `signing`. A later insert is `next`.

`auth_internal.insert_issuer_kid()` generates the key pair, stores the secret in Vault, and inserts the row. `auth_internal.switch_issuer_signing_kid(p_kid text)` is the only writer that moves `next` to `signing` and the previous `signing` row to `retired`. It changes nothing unless that `kid` is `next`. Neither function is granted to clinic roles.

## 2. `ai_internal.ai_token_issuance`

`organization_id` is already present from P1.2. This migration adds `aud text`. Existing rows are backfilled to `ai-platform`, then the column is `NOT NULL`. The rate-limit count is per `actor_staff_id` and `aud`.

`installation_id` is dropped. Its only source was `ai_internal.installation_keys`, which this migration drops, and 03 §4 does not keep the column on the changed ledger. New AI and billing rows write `aud` and `organization_id`. The feed mint does not insert a ledger row.

Billing limit: rows with `aud = 'abo'` for that user in the last 10 minutes. The 21st mint returns `RATE_LIMITED` and inserts nothing.

## 3. `ai_internal.app_settings`

New keys. `ai.availability` stays until P5.2.

| Key | `value_json` |
| --- | --- |
| `ai.issuer_id` | `"issuer-test"` (the existing platform and ABO `ISSUER_ID`) |
| `ai.platform_base_url` | `"http://127.0.0.1:8787"` |
| `ai.abo_base_url` | `"http://127.0.0.1:8788"` |
| `ai.contract_versions` | One object per key of `CHANNEL_VERSIONS` in `packages/vendor-contracts/src/version.ts`. Each value is `{"current": <that constant>, "minimum": <current - 1>}`. At launch every current value is 1 and every minimum is 0 |

`backendRpc.current` is N for the issue RPCs. Accepted versions are N−1 and N.

## 4. `public.rpc_result`

Existing composite, extended with `contract_version integer` as the last attribute. `public.rpc_success` and `public.rpc_error` take that value (default null) and write it on the row. `issue_billing_token` sets it to the version the request used when the version is accepted, and to N when the version is missing or refused. `issue_ai_token` still returns `text`.

## 5. `installation_keys`

Dropped, with `ai_internal.enforce_single_installation`, the single-installation trigger, and `enroll_installation_keypair`, `rotate_installation_key`, and `revoke_installation_key` in `public` and `auth_internal`.

## 6. Tokens

Signed by the `signing` row. Header `{alg: EdDSA, kid, typ: JWT}`. `iss` is `ai.issuer_id`. `ver` is `"2"`. `jti` is a UUID.

| Token | `aud` | Lifetime `exp − iat` | Other claims |
| --- | --- | --- | --- |
| AI | `ai-platform` | 600 seconds | `sub` staff id, `org` from `current_org_id()`, `role` from `current_membership_role()`, `branch` the current primary branch, `scopes` the granted `ai.*` keys for that org and role |
| Billing | `abo` | 300 seconds | `sub` staff id, `org` from `current_org_id()`, `role` `administrator`, `branch` the current primary branch, no `scopes` |
| Feed | `ai-platform-feed` | 120 seconds | `sub` `backend-feed`. `org`, `role`, `branch`, and `scopes` are absent |
