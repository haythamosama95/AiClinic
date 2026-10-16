# Contract: Receipt

**Unit**: P2.2 · **Requirements**: FR-004

Later units bind to this file. The platform key (02 K-3) signs the canonical receipt with the signature field removed. Signing and verification call `signCompactJws` and `verifyCompactJws`.

## 1. Module

`packages/vendor-contracts/src/receipt.ts`, re-exported from `src/index.ts`.

```ts
export function validateReceipt(
  value: unknown,
): { ok: true } | { ok: false }

export function receiptSigningBytes(receipt: unknown): Uint8Array

export function verifyReceiptSignature(input: {
  receipt: unknown
  publicKey: CryptoKey
}): Promise<boolean>
```

`receiptSigningBytes` is `canonicalize` of the receipt object with `signature` omitted. `verifyReceiptSignature` calls `verifyCompactJws` with that payload, `receipt.signature`, `receipt.kid`, and the public key.

## 2. Fields

Exactly one of `grant_id` or `reversal_id` is present.

| Field | Rule |
| --- | --- |
| `contract_version` | Integer |
| `grant_id` or `reversal_id` | 64 lowercase hex characters |
| `installation_id` | String, UUID `8-4-4-4-12` lowercase hex |
| `org_id` | String, UUID `8-4-4-4-12` lowercase hex |
| `result` | String |
| `term_ids` | Array of strings |
| `applied_at` | String |
| `ledger_seq` | Integer |
| `envelope_sha256` | 64 lowercase hex characters |
| `kid` | String. Equals the `kid` inside the compact JWS header |
| `signature` | Compact JWS string |

## 3. Vector

`packages/vendor-contracts/vectors/receipt.json` holds one receipt object. E2E-P2.2-06 checks that `verifyReceiptSignature` accepts the testkit platform signature, and that a changed `term_ids` array makes verification fail. The same test wraps the receipt in an `applied` result envelope (`contracts/result-envelope.md`).
