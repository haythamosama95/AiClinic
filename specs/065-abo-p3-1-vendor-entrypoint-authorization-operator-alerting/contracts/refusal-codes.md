# Contract: Auth refusal codes

**Unit**: P3.1 · **Requirements**: FR-002, FR-016, FR-017

Later units bind to this file for the codes this unit introduces. The result object is the frozen P2.2 envelope. `receipt` is omitted on every code below. `detail` is `""` unless a row says otherwise. `code` on `ok` is `""`.

## 1. Version gate

`negotiate(CHANNEL_VERSIONS.vendorEntrypoint, requested)` with the channel current version `1`. A missing `contract_version`, a non-integer, or `2` is rejected. The refusal envelope uses `contract_version` `1` because the request did not present an accepted version. An accepted request (`1`, or `0` as N−1) echoes the negotiated version on every later result, including `rejected`.

| Condition | `result` | `code` | Writes |
| --- | --- | --- | --- |
| `contract_version` missing, not an integer, or `2` | `rejected` | `contract_version_unsupported` | Nothing. Runs before `verifyAccessJwt`. |

## 2. Access JWT

`verifyAccessJwt` against the team certs, issuer `https://${ACCESS_TEAM_DOMAIN}`, `aud` `ACCESS_AUD`, and `nowSeconds` from the clock module. The package returns no code. `unauthenticated` is the entrypoint code (02 §3.3).

| Condition | `result` | `code` | Writes |
| --- | --- | --- | --- |
| `access_jwt` missing, verify returns `{ ok: false }`, or the certs document cannot be loaded | `rejected` | `unauthenticated` | Nothing, including no `control_audit` row. |

This applies to `registerOperatorCredential` (including bootstrap) and `revokeOperatorCredential`. This unit has no class H method. `listOperatorCredentials` does not take `access_jwt`.

## 3. Assertion and credential

Checked only after the Access JWT succeeds. These write `control_audit` and do not insert `assertion_used`, except `assertion_used` itself, which is the duplicate primary key.

| Condition | `result` | `code` |
| --- | --- | --- |
| Non-bootstrap HP call omits `assertion`, including a second registration while the table is not empty | `rejected` | `assertion_required` |
| `issued_at` is more than 5 minutes from now | `rejected` | `assertion_expired` |
| `actor_email` ≠ Access email | `rejected` | `actor_email_mismatch` |
| Signer `status` is `pending` and `activates_at` is after now | `rejected` | `credential_not_active` |
| Signer `status` is `revoked` | `rejected` | `credential_revoked` |
| Challenge hash is already in `assertion_used` | `rejected` | `assertion_used` |
| Revoke `credential_id` is not in `operator_credential` | `rejected` | `credential_not_found` |
| Register stores the same `credential_id` with a different `public_key_cose` | `conflict` | `public_key_cose_mismatch` |

`public_key_cose_mismatch` uses `detail` `""`. `conflict` does not include `receipt`.

`verifyAssertion` returning `{ ok: false }` for `rpId`, origin, `type`, flags, challenge, or signature is `rejected` with code `assertion_invalid` and writes `control_audit` only. The E2E set does not target that code; the WebAuthn rules in 04 §1.5 still apply.
