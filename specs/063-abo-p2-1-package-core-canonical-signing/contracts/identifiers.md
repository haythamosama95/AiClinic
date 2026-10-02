# Contract: Identifiers and references

**Unit**: P2.1 · **Requirements**: FR-005, FR-006, FR-007, FR-010, FR-012

Later units bind to this file and to `packages/vendor-contracts/vectors/identifiers.json`. The formulas are 03 §7. `‖` is concatenation of the UTF-8 strings named in each formula.

## 1. Module

`packages/vendor-contracts/src/identifiers.ts`, re-exported from `packages/vendor-contracts/src/index.ts`.

```ts
export function ulid(timestampMs: number, random80: Uint8Array): string
export function subscriptionRef(orgId: string): Promise<string>
export function paymentId(providerId: string, providerTransactionRef: string): Promise<string>
export function grantIdPaid(paymentIdValue: string): Promise<string>
export function grantIdComp(operatorActionId: string): Promise<string>
export function grantIdTransfer(transferId: string, n: number): Promise<string>
export function coverageEventId(installationId: string, clinicSeq: number): string
export function humanRef(kind: "CK" | "PAY" | "REV" | "GR", recordId: string): string
```

The hash functions encode the concatenated string as UTF-8 and return `sha256Hex` from `contracts/canonical-hash-jws.md`.

## 2. Crockford base-32

The alphabet is `0123456789ABCDEFGHJKMNPQRSTVWXYZ`.

A byte string is encoded MSB first. The bit length is padded with zero bits at the end to a multiple of 5. SHA-256 is 256 bits, so the encoding is 52 characters. The leading 8 characters are the first 40 bits.

## 3. ULID

`ulid` is a 26-character Crockford ULID: a 48-bit millisecond timestamp and 80 random bits. `random80.byteLength` is 10. `timestampMs` is a non-negative integer that fits in 48 bits.

`vectors/identifiers.json` includes one pair `(timestampMs, random80 hex)` and the 26-character result.

## 4. Formulas

| Function | Result |
| --- | --- |
| `subscriptionRef(orgId)` | `AIC-` plus the leading 8 Crockford characters of SHA-256(`"sub-ref:"` ‖ `orgId`) |
| `paymentId(providerId, providerTransactionRef)` | SHA-256 hex of `"payment:"` ‖ `providerId` ‖ `":"` ‖ `providerTransactionRef` |
| `grantIdPaid(paymentIdValue)` | SHA-256 hex of `"grant:paid:"` ‖ `paymentIdValue` |
| `grantIdComp(operatorActionId)` | SHA-256 hex of `"grant:comp:"` ‖ `operatorActionId` |
| `grantIdTransfer(transferId, n)` | SHA-256 hex of `"grant:transfer:"` ‖ `transferId` ‖ `":"` ‖ the base-10 digits of `n` |
| `coverageEventId(installationId, clinicSeq)` | `installationId` ‖ `":"` ‖ the base-10 digits of `clinicSeq` |
| `humanRef(kind, recordId)` | `kind` ‖ `"-"` ‖ the trailing 8 characters of `recordId` |

`orgId` is the backend tenant UUID string, passed through unchanged. `installationId` is the platform clinic UUID string. `n` and `clinicSeq` are non-negative integers. `recordId` is a ULID from `ulid`; the trailing 8 characters are already Crockford and carry the random bits (03 §7).

## 5. Vectors

`vectors/identifiers.json` records the inputs and the results for `subscriptionRef`, `paymentId`, `grantIdPaid`, `grantIdComp`, `grantIdTransfer`, `coverageEventId`, `humanRef`, and one `ulid`.

E2E-P2.1-03 asserts two of those results in Node and in workerd: `subscriptionRef` of the fixture `org_id` equals the vector, and `grantIdPaid` of the fixture `payment_id` equals the vector. The fixture `payment_id` is itself the `paymentId` result stored in the same file, so `grantIdPaid(paymentId)` equals SHA-256 hex of `"grant:paid:"` ‖ that `payment_id`.
