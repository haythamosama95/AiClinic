# Contract: Result envelope

**Unit**: P2.2 · **Requirements**: FR-001

Later units bind to this file. The validator is `validateResultEnvelope` in `packages/vendor-contracts/src/result-envelope.ts`, re-exported from `src/index.ts`.

## 1. Shape

```ts
export type ResultName =
  | "ok"
  | "applied"
  | "already_applied"
  | "conflict"
  | "rejected"
  | "transient"

export type TransientDetail =
  | "unavailable"
  | "unknown_kid"
  | "awaiting_transfer"
  | "transfer_pending"

export function validateResultEnvelope(
  value: unknown,
): { ok: true } | { ok: false }
```

The value is a JSON object with `contract_version`, `result`, `code`, and `detail`. `receipt` is required when `result` is `applied` or `already_applied`, and then it satisfies `contracts/receipt.md`. On the other result names, `receipt` may be absent.

| Field | Rule |
| --- | --- |
| `contract_version` | Integer |
| `result` | One of the six names |
| `code` | String |
| `detail` | String. When `result` is `transient`, one of the four transient details |
| `receipt` | Receipt object when `result` is `applied` or `already_applied` |

`ok` means the read succeeded. `applied` means a change was made now. `already_applied` means the same id with the same content hash was applied before and the original receipt is returned. `conflict` means the same id with a different content hash. `rejected` means validation failed and `code` says why. `transient` means nothing was changed.

## 2. Vector

`packages/vendor-contracts/vectors/result-envelope.json` holds one `applied` envelope whose `receipt` is the receipt vector. E2E-P2.2-06 validates that envelope in Node and in workerd.
