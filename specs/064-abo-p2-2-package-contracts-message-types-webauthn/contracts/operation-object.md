# Contract: Operation object and challenge

**Unit**: P2.2 · **Requirements**: FR-007

Later units bind to this file. The challenge is base64url(SHA-256(canonical operation object)).

## 1. Module

`packages/vendor-contracts/src/operation.ts`, re-exported from `src/index.ts`.

```ts
export function validateOperation(
  value: unknown,
): { ok: true } | { ok: false }

export function operationChallenge(operation: unknown): Promise<string>
```

`operationChallenge` calls `canonicalize`, then `sha256Hex`, decodes that hex to bytes, and base64url-encodes the bytes with `src/base64url.ts` (RFC 4648 §5, no padding). It does not add a digest function to `src/canonical.ts`.

## 2. Fields

| Field | Rule |
| --- | --- |
| `op` | String |
| `params` | JSON object. The method input, without the assertion. This contract does not list method names |
| `actor_email` | String |
| `issued_at` | String |
| `nonce` | String |
| `contract_version` | Integer |

P3.1 compares `actor_email` with the Access email and applies the 5-minute `issued_at` window. This unit's challenge uses the object as given.

## 3. Vector

`packages/vendor-contracts/vectors/operation.json` holds operation O (`{op, params, actor_email, issued_at, nonce, contract_version}`) and the challenge string. E2E-P2.2-01 uses O and an O′ that differs by one `params` value.
