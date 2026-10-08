# Compromise response (02 §6 emergency revocation)

A compromised credential is revoked in minutes (SR-11). Use the 02 §6 emergency revocation for that credential.

## Issuer key (K-2)

1. Call `revokeIssuerKey` (HP). It sets the `kid` to `revoked`. Tokens for that `kid` are rejected within one config-cache TTL (≤ 30 s).
2. Remove it from the ABO's pins by config deploy (minutes).

Alert 30 days before `not_after` (A25).

## Platform key (K-3)

Same sequence as routine rotation, done at once. The old `kid` is removed from the ABO's configuration.

## ABO grant key (K-4)

1. Revoke on the platform (HP). Envelopes under the revoked `kid` are `rejected`.
2. Deploy the new secret. Parked rows are retried, re-signed with the new key.

An unknown `kid` answers `transient`, so grants retry until a new key's registration is visible (04 §1.4).

## Paymob HMAC (K-5)

Same as routine rotation.

## Paymob keys (K-6)

Same as routine rotation. Pending work retries.

## Operator passkey (K-7)

Any active credential revokes another at once. List and void grants by credential and window.

## Access (K-8)

Revoke sessions in Access.

## Audit-watcher token (K-10)

Revoke in Cloudflare.
