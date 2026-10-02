# Contract: Credential lifecycle

**Unit**: P3.1 · **Requirements**: FR-003, FR-006, FR-007, FR-008, FR-011, FR-013, FR-018

Later units bind to this file for register, revoke, and list results. The envelope is `{contract_version, result, code, detail}` with no `receipt` key. `detail` is a string. `code` is `""` on `ok`.

## 1. Row JSON

`detail` on register and revoke `ok` is `JSON.stringify` of the `operator_credential` row. Keys, in order: `credential_id`, `operator_email`, `public_key_cose`, `alg`, `status`, `activates_at`, `approved_by`, `revoked_by`. Null columns are JSON `null`. `public_key_cose` is the base64url text stored in D1. `activates_at` is ISO-8601 UTC.

## 2. `registerOperatorCredential`

Class HP, or bootstrap ( `contracts/class-table.md` ).

Bootstrap, only while the table is empty, with a valid Access JWT and no assertion:

- Insert `status` `pending`, `activates_at` 24 hours ahead of the clock, `approved_by` null, `revoked_by` null, `operator_email` the Access email.
- `result` `ok`. `detail` is the row JSON.
- Raise AL-13 kind `bootstrap` (`contracts/alert-body.md`).
- Write `control_audit` with `actor` the Access email and `assertion_sha256` null.

A later call with no assertion, once any row exists, is `assertion_required` and inserts nothing.

With a valid approving assertion:

- The signer must be `active` (promoted on this read when `activates_at` is at or before now, with no alert).
- New `credential_id`: insert `pending`, `approved_by` the Access email, `activates_at` 24 hours ahead. `result` `ok`. Raise AL-13 kind `register`.
- Same `credential_id` and the same `public_key_cose` bytes: `ok`, return the stored row, do not insert another row, do not raise another AL-13.
- Same `credential_id` and different bytes: `conflict`, code `public_key_cose_mismatch`, `detail` `""`.

Idempotent by `credential_id`.

## 3. `revokeOperatorCredential`

Class HP. The signer is `signer_credential_id`. The target is `credential_id`. They may be the same row.

- Target missing: `credential_not_found`. No status change.
- Target exists: set `status` `revoked` and `revoked_by` to the Access email. `ok` when this call changes it, and `ok` when it was already `revoked`. `detail` is the row JSON.
- Raise AL-13 kind `revoke` on a call that returns `ok`, including an already-revoked target.
- An HP call whose signer is `revoked` is `credential_revoked` and does not revoke anything else (FR-018).

Idempotent by target state.

## 4. Promotion

The signer read and `listOperatorCredentials` are the only `pending` → `active` writes. The condition is `activates_at` at or before the clock's now. The write raises no alert. A signer that is still `pending` is `credential_not_active`.

## 5. `listOperatorCredentials`

Class M. After promotion, `result` `ok`. `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each row with `status` `active`, ordered by `credential_id`. `receipt` is absent and `code` is `""`. `contract_version` is the negotiated version. No `control_audit` row.

## 6. Assertion checks

The platform builds nothing the caller can substitute. `operation.params` must equal the RPC input without `assertion` and without `operation`. Then `verifyAssertion` with `rpId` `WEBAUTHN_RP_ID`, `origin` `WEBAUTHN_ORIGIN`, and the signer's imported public key.

`issued_at` within 5 minutes of the clock is accepted. Six minutes is `assertion_expired`. `actor_email` must equal the Access email (`actor_email_mismatch`). The challenge hash is inserted into `assertion_used` only after those checks and the active-signer check. The hex digest is `control_audit.assertion_sha256`.
