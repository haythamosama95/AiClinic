# Routine credential rotation (02 §6)

Every credential rotates without an outage.

## Issuer key (K-2)

1. Generate the next `kid` as `ai_internal.issuer_key.status` `next` (03 §4).
2. Add its public key to the ABO's pinned `ISSUER_KEYS` (config deploy) and register it on the platform (HP).
3. Call `auth_internal.switch_issuer_signing_kid(p_kid)` once both accept it. That row becomes `signing`; the previous `signing` row becomes `retired`.
4. After 10 minutes (the longest token life), call `retireIssuerKey` (HP). It sets the old `kid` to `retiring`. That `kid` stays accepted until `not_after`.

## Platform key (K-3)

1. Add the next `kid` to the ABO's configuration first.
2. Then switch signing on the platform.

The receipt `signature` is the compact JWS in 04 §1.6. That receipt's `ledger_seq` is the `clinic_seq` of the `grant_applied` or `grant_voided` event, not a `grant_ledger` column.

## ABO grant key (K-4)

1. Register the next public key on the platform (`registerServiceKey`).
2. Switch the secret.
3. Revoke the old one (`revokeServiceKey` sets `status` `revoked`). There is no `retiring` status.

Each attempt signs with the current key, so pending grants need no rework (03 §2.8).

The ABO checks at isolate start, and hourly, that its signing `kid` is `active` and not expired (`listServiceKeys`, 04 §1.3). If not, it pauses `grant` and `reverse` work and raises AL-23 instead of sending envelopes that can only answer `transient`.

## Paymob HMAC (K-5)

1. Rotate in the Paymob dashboard.
2. Update the secret in the ABO.

Callbacks fail verification in between. Inquiry sweeps recover the payments (A23 path).

## Paymob keys (K-6)

1. Rotate in the Paymob dashboard.
2. Update the secrets in the ABO.

## Operator passkey (K-7)

1. Add a new credential (approved by an existing one, active after 24 hours).
2. Revoke the old credential.

## Access (K-8)

Session length: 1 hour.

## Audit-watcher token (K-10)

Rotate every 90 days.
