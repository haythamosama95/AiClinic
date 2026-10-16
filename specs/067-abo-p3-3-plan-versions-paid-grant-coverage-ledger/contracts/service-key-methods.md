# Contract: Service-key methods

**Unit**: P3.3 · **Requirements**: FR-004

Later units bind to this file for `registerServiceKey`, `revokeServiceKey`, and `listServiceKeys`. The result is the envelope `{contract_version, result, code, detail}` with no extra key. These methods do not record a grant or a reversal. `receipt` is absent. They do not return `applied` or `already_applied`.

`registerServiceKey` and `revokeServiceKey` are class HP. They use the existing Access JWT and WebAuthn assertion checks. `listServiceKeys` is class M: the service binding is the evidence, with no Access JWT and no ABO signature.

`contract_version` is checked first, with `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, …)`, before authentication and before any write.

## 1. `registerServiceKey` (HP)

Input beyond `contract_version`, `access_jwt`, and `assertion`: `kid`, `public_key`, `not_before`, `not_after`.

`public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. The stored value is that string. `service` is `abo`. `registered_by` is the Access email. `assertion_sha256` is the assertion challenge hash. Inserted `status` is `active`.

| `result` | `code` | `detail` | When |
| --- | --- | --- | --- |
| `ok` | `""` | JSON text of the `service_key` row | Insert, or the same `kid` already stored with the same `public_key`. A same-key replay does not insert another row and does not change `status` or the stored validity. |
| `conflict` | `public_key_mismatch` | `""` | That `kid` is stored with a different `public_key`. The stored row is unchanged. |
| `rejected` | `public_key_invalid` | `""` | `public_key` is not that encoding. |

Row JSON keys, in this order: `kid`, `service`, `public_key`, `status`, `not_before`, `not_after`, `registered_by`, `assertion_sha256`.

On `ok`, the platform raises AL-13 once. The email `text` is JSON `{code: "AL-13", kid, operation}`. `operation` is the decoded HP operation. `subject` is `AL-13`. The alert key is `AL-13:service_key:<kid>:register`. A later `ok` for that key does not send a second email after the row is `sent`. This object does not add keys to the credential AL-13 body or the issuer-key AL-13 body.

## 2. `revokeServiceKey` (HP)

Input beyond `contract_version`, `access_jwt`, and `assertion`: `kid`. This is the only writer of `revoked`.

| `result` | `code` | `detail` | When |
| --- | --- | --- | --- |
| `ok` | `""` | JSON text of the `service_key` row | `status` becomes `revoked`, or it is already `revoked`. |
| `rejected` | `kid_not_found` | `""` | No row for `kid`. |

On `ok`, AL-13 uses the same body shape, with alert key `AL-13:service_key:<kid>:revoke`. Repeat is once.

## 3. `listServiceKeys` (M)

No input beyond `contract_version`. `result` is `ok`, `code` is `""`, `receipt` is absent. `detail` is the JSON text of an array of `{kid, status, not_before, not_after}` for every `service_key` row, including `revoked`, ordered by `kid` ascending. This method does not raise AL-13.
