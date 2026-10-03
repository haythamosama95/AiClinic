# Contract: AI-token verification

**Unit**: P3.2 · **Requirements**: FR-004, FR-005, FR-006, FR-011, FR-012

Later units bind to this file for the issuer-token verifier that replaces `EnrolledKeyVerifier`. AI routes use audience `ai-platform`. A failed check on those routes is HTTP 401 with the existing `unauthenticated` taxonomy body. No new refusal code is added.

The token is a compact JWS. The header has `alg` `EdDSA` and `kid`. Claims used here are `iss`, `aud`, `org`, `jti`, `iat`, `exp`, and `ver`. `iss` is `ISSUER_ID`, the Worker var, not the installation id.

## 1. Check order

These checks run before `org` is resolved and before any `installation` or `tenant_binding` write:

1. The compact JWS parses, `alg` is `EdDSA`, and `kid` is a non-empty string. `kid` is not rewritten with `toCanonicalUuid`.
2. `aud` equals the route audience. `abo` and `ai-platform-feed` fail on an AI route.
3. Clock skew is the existing comparison: `iat - clockSkewSeconds > now` or `now > exp + clockSkewSeconds`, with `clockSkewSeconds` 60.
4. `exp - iat` is greater than 600. The existing `MAX_AAT_LIFETIME_SECONDS` bound is that check. 601 fails.
5. `token_contract` for `ver` is missing or `retired_at` is set. Version `1` is retired. Version `2` is current. A `ver` of `"1"` fails here.

Then, still before a binding write:

6. `issuer_key` for `kid` is loaded through the config cache. A miss, a `revoked` row, a status other than `active` or `retiring`, or a now outside `not_before` ≤ now < `not_after` fails.
7. `iss` equals `ISSUER_ID`.
8. The Ed25519 signature over the compact-JWS signing input verifies with the stored `public_key`.

Only a token that passes 1–8 is valid. The first valid token for an unknown `org` may then insert. A failure in 1–8 inserts nothing.

## 2. Cache

`issuer_key` and `tenant_binding` are read through the config cache. The verify path passes the platform clock into that read, so a test-clock advance of one TTL expires the entry. The TTL is the existing `CONFIG_CACHE_TTL_MS`. Development is 100 ms. Production and staging are 30000 ms. Both are at most 30 s. Coverage is not a cache kind. The `installation_key` kind `keys` is removed. The `plan` and `entitlement` readers stay.

A revoked `kid` is still accepted while the cached `issuer_key` row is inside its TTL, and rejected after that TTL.

## 3. Principal and replay

`Principal.installationId` comes from the binding. `organizationId` comes from `org`. `jti`, `iat`, `exp`, and `ver` stay on the principal. Replay stays the existing Durable Object `jti` replay. This unit does not add a replay table and does not change `src/quota-do/index.ts`.

The existing installation status check stays after the binding is resolved: `suspended` is `installation_suspended`, and any other status other than `active` is `unauthenticated`. The row this unit inserts is `active`.
