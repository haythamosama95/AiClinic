# Contract: Grant envelope

**Unit**: P2.2 · **Requirements**: FR-002, FR-003

Later units bind to this file. Field rules are the 04 §1.4 field table (FR-002). Signature checks use the consumed JWS API (FR-003).

## 1. Module

`packages/vendor-contracts/src/grant-envelope.ts`, re-exported from `src/index.ts`.

```ts
export function validateGrantEnvelope(
  value: unknown,
): { ok: true } | { ok: false; code?: "placement_not_supported" }

export function grantEnvelopeHash(envelope: unknown): Promise<string>

export function verifyGrantSignature(input: {
  envelope: unknown
  jws: string
  publicKey: CryptoKey
  kid: string
}): Promise<boolean>
```

`grantEnvelopeHash` is `sha256Hex(canonicalize(envelope))` from `specs/063-abo-p2-1-package-core-canonical-signing/contracts/canonical-hash-jws.md`. Two calls on the same object return the same hex. `verifyGrantSignature` calls `verifyCompactJws` with that canonical payload. `signCompactJws` and `verifyCompactJws` stay as P2.1 froze them. The signature is the compact JWS argument; it is not a field of the envelope.

`grant_id` values in this unit's tests come from `grantIdPaid`, `grantIdComp`, or `grantIdTransfer`. `contract_version` in those tests is `CHANNEL_VERSIONS.vendorEntrypoint`. This unit does not call `negotiate` and does not emit `contract_version_unsupported`.

## 2. Fields

The object has the keys below. A missing required key, an extra key, or a wrong JSON type fails validation.

| Field | Rule |
| --- | --- |
| `contract_version` | Integer |
| `grant_id` | 64 lowercase hex characters |
| `org_id` | String, UUID `8-4-4-4-12` lowercase hex |
| `kind` | `term` or `term_adjustment` |
| `placement` | `queue`. `immediate` or `replace` returns `{ ok: false, code: "placement_not_supported" }` |
| `source` | Object `{kind, ref, operator_email, reason}` as in section 3 |
| `plan` | `{plan_id: string, plan_version: integer}` |
| `duration` | `{unit, count}` as in section 4 |
| `allowance_credits` | Integer ≥ 1 |
| `grace` | `{days: integer, cap_rule: string}`. When `source.kind` is `paid`, `days` ≤ 7 and `cap_rule` is `proportional` |
| `adjustment` | Present only when `kind` is `term_adjustment`. Object whose keys are a subset of `plan`, `add_allowance`, `extend_days`. `plan`, when present, matches the `plan` field. `add_allowance` and `extend_days`, when present, are integers |
| `paid_at` | Present only when `source.kind` is `paid`. String |
| `evidence` | `{content_sha256, approvals}`. `content_sha256` is 64 lowercase hex characters. `approvals` is an array of length ≥ 1 |
| `ceiling_override` | Optional. When the key is present, `approvals` has length ≥ 2. This contract does not add inner fields for the override |

Other field-rule failures return `{ ok: false }` with no `code`. `placement_not_supported` is the only named code.

## 3. Source

`source.kind` is `paid`, `complimentary`, or `transfer`. `ref` is a string. `operator_email` and `reason` are strings, and both are present unless `source.kind` is `paid`.

## 4. Duration

`count` is an integer. When `source.kind` is `paid`, `unit` is `month` and `count` is 1, 3, or 12. When `source.kind` is `complimentary`, `unit` is `month` or `day`. When `source.kind` is `transfer`, `unit` is a string and `count` is an integer. The field table states further duration rules for `paid` and `complimentary`.

## 5. Vector

`packages/vendor-contracts/vectors/grant-envelope.json` holds one `paid` `term` envelope and the hex from `grantEnvelopeHash`. E2E-P2.2-05 checks that hex is stable, that `verifyGrantSignature` accepts the testkit ABO signature, and that changing any field makes verification fail.
