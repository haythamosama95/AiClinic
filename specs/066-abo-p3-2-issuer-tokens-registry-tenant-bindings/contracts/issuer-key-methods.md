# Contract: Issuer-key methods

**Unit**: P3.2 · **Requirements**: FR-002, FR-003, FR-018, FR-019, FR-020, FR-021

Later units bind to this file for `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`, and `listIssuerKeys`. The result object is the existing envelope `{contract_version, result, code, detail}` with no extra key. These methods do not record a grant or a reversal, so `receipt` is absent. They do not return `applied` or `already_applied`.

Class HP methods take `access_jwt` and `assertion` through the existing entrypoint checks. Class M takes neither. `contract_version` is checked first, before authentication and before any write.

## 1. `registerIssuerKey` (HP)

Input beyond `contract_version`: `kid`, `public_key`, `not_before`, `not_after`.

`public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. The stored value is that string, unchanged. `issuer` is `ISSUER_ID`. `registered_by` is the Access email. `assertion_sha256` is the assertion challenge hash. Inserted `status` is `active`. This call does not set `retiring`.

| `result` | `code` | `detail` | When |
| --- | --- | --- | --- |
| `ok` | `""` | JSON text of the `issuer_key` row | Insert, or the same `kid` already stored with the same `public_key`. A same-key replay does not insert another row and does not change `status`. |
| `conflict` | `public_key_mismatch` | `""` | That `kid` is stored with a different `public_key`. |
| `rejected` | `public_key_invalid` | `""` | `public_key` is not that encoding. |

Row JSON keys, in this order: `kid`, `issuer`, `public_key`, `status`, `not_before`, `not_after`, `registered_by`, `assertion_sha256`.

On `ok`, the platform raises AL-13. The email `text` is JSON with keys `code` (`"AL-13"`), `kid`, and `operation` (the decoded operation object from the existing HP check). `subject` is `AL-13`. The alert key is `AL-13:issuer_key:<kid>:register`. Repeat is once: a later `ok` for the same key does not send a second email after the row is `sent`. This object does not add keys to the credential AL-13 body.

## 2. `retireIssuerKey` (HP)

Input beyond `contract_version`: `kid`. This is the only writer of `retiring`.

| `result` | `code` | `detail` | When |
| --- | --- | --- | --- |
| `ok` | `""` | JSON text of the `issuer_key` row | `status` moves from `active` to `retiring`, or it is already `retiring`. |
| `rejected` | `kid_not_found` | `""` | No row for `kid`. |
| `rejected` | `kid_revoked` | `""` | The row is `revoked`. It stays `revoked`. |

Tokens for a retiring `kid` stay accepted until `not_after`. On `ok`, AL-13 uses the same body shape as register, with alert key `AL-13:issuer_key:<kid>:retire`.

## 3. `revokeIssuerKey` (HP)

Input beyond `contract_version`: `kid`. It sets `revoked`. It does not set `retiring`.

| `result` | `code` | `detail` | When |
| --- | --- | --- | --- |
| `ok` | `""` | JSON text of the `issuer_key` row | `status` becomes `revoked`, or it is already `revoked`. |
| `rejected` | `kid_not_found` | `""` | No row for `kid`. |

On `ok`, AL-13 uses the same body shape, with alert key `AL-13:issuer_key:<kid>:revoke`.

## 4. `listIssuerKeys` (M)

No input beyond `contract_version`. `result` is `ok`, `code` is `""`, `receipt` is absent. `detail` is the JSON text of an array of `{kid, public_key, status, not_before, not_after}` for each row with `status` `active` or `retiring`, ordered by `kid` ascending. `public_key` is the stored base64url string. `status` and the validity times are in the list and are not themselves a pin mismatch. Revoked rows are omitted. This method does not raise AL-13.
