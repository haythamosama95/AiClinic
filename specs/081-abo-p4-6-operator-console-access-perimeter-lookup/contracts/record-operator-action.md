# Contract: `recordOperatorAction`

**Unit**: P4.6 · **Requirements**: FR-007

Frozen for later ABO-verified actions. Class H on `VendorEntrypoint`. The ABO calls it only after this unit’s `operator_action` insert has committed. Retry parked work and cancel an open checkout are the callers in this unit. Cancel uses this call as its only platform call.

## 1. Call

Argument object:

| Field | Rule |
| --- | --- |
| `contract_version` | The vendor entrypoint channel. Checked first, the same way every `VendorEntrypoint` method already checks it. Missing or unsupported is `rejected` with `contract_version_unsupported` and writes nothing. |
| `access_jwt` | The operator’s Access JWT. |
| `action` | Copied from `operator_action.action`. |
| `subject` | Copied from `operator_action.subject`. |
| `action_id` | Copied from `operator_action.action_id`. |

`action`, `subject`, and `action_id` are non-empty strings. If any of them is missing after the version check and a verified Access JWT, the result is `rejected` with `code` `bad_request` and the method writes nothing.

There is no `assertion` and no `receipt`.

## 2. Access JWT

Verification is the existing `verifyHpAccess` path (`verifyAccessJwt` against the Access team certificates, `aud`, and expiry). A missing, expired, or wrong-`aud` token is `rejected` with `code` `unauthenticated`, empty `detail`, and no inserted row. A token that fails the issuer check takes that same path.

## 3. Success

`result` is `ok`. `code` is `""`. `detail` is `""`. The envelope has no `receipt`.

The method inserts one `control_audit` row and leaves every other platform table unchanged:

| Column | Value |
| --- | --- |
| `actor` | The Access email from the verified JWT. |
| `operator_id` | That same email. |
| `action` | The `action` argument. |
| `target` | The `action_id` argument. |
| `assertion_sha256` | Null. |

`before_pointer` and `after_pointer` stay null. The insert uses the existing `writeEntrypointAudit` helper.

## 4. Idempotency

The same `action_id` again is `ok` and inserts no second row. The match is `control_audit.target` equal to that `action_id`. `code`, `detail`, and `receipt` match §3.

## 5. What this method does not do

It does not change `inspectCoverage`, `suspend`, `resume`, or any other frozen method. A platform-verified action still writes `control_audit` inside its own class-H or class-HP call. This method is the write for an action the ABO has already verified.
