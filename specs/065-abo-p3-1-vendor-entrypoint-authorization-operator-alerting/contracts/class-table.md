# Contract: Method dispatch and class table

**Unit**: P3.1 · **Requirements**: FR-001, FR-004, FR-005

Later units bind to this file. They may add a method row. They do not change the three rows below (rule S7).

## 1. Entrypoint

`VendorEntrypoint` extends `WorkerEntrypoint` and is a named export of `ai-platform/src/worker.ts`, defined in `ai-platform/src/vendor/entrypoint.ts`. The ABO calls it over a service binding. No `fetch` branch dispatches to the class. `workers_dev` and `preview_urls` are false.

H-AP binds it as Miniflare `serviceBindings.VENDOR` with `entrypoint: "VendorEntrypoint"` on the current worker. Tests call `env.VENDOR.<method>(args)`.

## 2. Class table

This unit's table has these rows and no others. Class H methods stay with later units.

| Method | Class | Arguments beyond the class rules |
| --- | --- | --- |
| `registerOperatorCredential` | HP, or bootstrap | `credential_id`, `attestation`. Bootstrap: the table is empty and `assertion` is absent. Otherwise `signer_credential_id`, `assertion`, and `operation`. |
| `revokeOperatorCredential` | HP | `credential_id`, `signer_credential_id`, `assertion`, `operation`. |
| `listOperatorCredentials` | M | None. The only argument is `contract_version`. |

Class M is the service binding. `listOperatorCredentials` does not take an ABO signature.

Class HP takes `access_jwt` and, except bootstrap, `assertion`. `access_jwt` is required on bootstrap as well. The bootstrap exception is the missing approving assertion only (02 §3.3).

## 3. Argument encoding

Binary fields are base64url strings so the RPC argument is JSON-compatible. The entrypoint decodes them into the consumed `Assertion` and attestation types.

`attestation`: `{ alg: "ES256" | "EdDSA", public_key: "<base64url>" }`.

`assertion`: `{ alg, authenticator_data, client_data_json, signature }`, each binary field base64url.

`operation`: `{ op, params, actor_email, issued_at, nonce, contract_version }` as `validateOperation` defines it. `op` is the method name. `params` is the method input without `assertion` and without `operation`:

- Register: `{ contract_version, access_jwt, credential_id, attestation, signer_credential_id }`.
- Revoke: `{ contract_version, access_jwt, credential_id, signer_credential_id }`.

`issued_at` is ISO-8601 UTC. The entrypoint rejects the call when `operation` does not match the RPC arguments, `op`, or `contract_version`.

`signer_credential_id` names the active credential whose stored public key verifies the assertion. The consumed `Assertion` type and the testkit authenticator data do not carry a credential id.

## 4. Dispatch order

1. `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, contract_version)`. Failure returns before authentication and before any write (`contracts/refusal-codes.md`).
2. Class HP: `verifyAccessJwt`. Failure writes nothing.
3. Class HP, non-bootstrap: assertion, freshness, actor, signer credential.
4. Method effect.
5. `control_audit` for a class HP call that passed step 2, including when step 3 or 4 rejects.

`listOperatorCredentials` stops after step 1, then reads credentials. It does not write `control_audit`.
