# Data Model: P2.2 message types

**Unit**: P2.2

This unit defines no tables and no PostgreSQL objects (spec §4.1). The entities below are package values. Wire fields and validators are in `contracts/`.

## 1. Result envelope

`{contract_version, result, code, detail, receipt?}`. `result` is `ok`, `applied`, `already_applied`, `conflict`, `rejected`, or `transient`. For `transient`, `detail` is `unavailable`, `unknown_kid`, `awaiting_transfer`, or `transfer_pending`. `applied` and `already_applied` carry `receipt`. (FR-001, `contracts/result-envelope.md`)

## 2. Grant envelope

The 04 §1.4 field table, as FR-002 states it. `contract_version` is an integer. `grant_id` is hex SHA-256 produced by the consumed identifier functions. `placement` `queue` is the launch value; `immediate` and `replace` fail with `placement_not_supported`. (FR-002, FR-003, `contracts/grant-envelope.md`)

## 3. Operation object

`{op, params, actor_email, issued_at, nonce, contract_version}`. `params` is the method input without the assertion. The challenge is base64url(SHA-256(canonical operation object)). (FR-007, `contracts/operation-object.md`)

## 4. Receipt

`{contract_version, grant_id or reversal_id, installation_id, org_id, result, term_ids, applied_at, ledger_seq, envelope_sha256, kid, signature}`. The platform key signs the canonical receipt without `signature`. (FR-004, `contracts/receipt.md`)

## 5. Coverage snapshot

The FR-005 fields. `band` is `ok`, `75`, `90`, or `exhausted`. `reason`, when present, is `none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, or `transfer_pending`. `state` is a string. This unit's Read list does not include 03 §5.7, so the model does not add a `state` enumeration. The snapshot has no prices, payment references, or provider ids. (FR-005, `contracts/coverage-snapshot.md`)

## 6. Feed event

`{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`. `snapshot` is the coverage snapshot. `kind` is a string. The defining sentence does not enumerate it, so this model does not add kind values. (FR-006, `contracts/feed-event.md`)

## 7. Token claims

AI, billing, and feed claims in FR-011. Header `{alg: EdDSA, kid, typ: JWT}`. `iss` is the backend issuer id passed into the validator. `ver` is `"2"`. (FR-011, `contracts/token-claims.md`)

## 8. Values that are not stored entities

WebAuthn assertions, registration attestations, and Access JWTs are verification inputs. Their wire shapes are `contracts/webauthn.md` and `contracts/access-jwt.md`. The testkit that builds them is `contracts/testkit.md`.
