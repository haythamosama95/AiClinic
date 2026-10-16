# Contract: Receipt production

**Unit**: P3.3 · **Requirements**: FR-005

Later units bind to this file for how the platform produces a receipt. Field rules stay `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/receipt.md`. This unit does not change `validateReceipt`, `receiptSigningBytes`, or `verifyReceiptSignature`.

## 1. Key

`PLATFORM_SIGNING_KEY` is a Worker var. The local stand-in, used in development, staging, production wrangler vars, and both vitest binding sets, is this JSON text:

```json
{"kid":"platform-test","pkcs8":"MC4CAQAwBQYDK2VwBCIEIN2ndQQArm1dlsCuHaGGaUB8nnqfj7W2HaVbj_JJA9Lk","public_key":"GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0"}
```

`pkcs8` is base64url of the PKCS8 Ed25519 private key, imported with `crypto.subtle.importKey("pkcs8", …, { name: "Ed25519" }, false, ["sign"])`. `public_key` is base64url of the raw 32-byte public key. `kid` is the receipt `kid` and the compact JWS header `kid`. Deploy replaces this stand-in. The value is not a second binding.

## 2. Fields

`{contract_version, grant_id, installation_id, org_id, result, term_ids, applied_at, ledger_seq, envelope_sha256, kid, signature}`

This unit writes `grant_id`, not `reversal_id`.

| Field | Rule |
| --- | --- |
| `contract_version` | The negotiated `CHANNEL_VERSIONS.vendorEntrypoint` of the grant call |
| `grant_id` | The envelope `grant_id` |
| `installation_id` | The binding's installation id |
| `org_id` | The envelope `org_id` |
| `result` | `applied`. An `already_applied` answer returns this same object, so the inner `result` stays `applied` |
| `term_ids` | Array of the term id this grant created. One element for a paid term grant |
| `applied_at` | UTC ISO-8601 grant time from the platform clock |
| `ledger_seq` | The integer `clinic_seq` of the `grant_applied` event. Not a `grant_ledger` column |
| `envelope_sha256` | Hex SHA-256 of the canonical grant envelope |
| `kid` | `kid` from `PLATFORM_SIGNING_KEY` |
| `signature` | Compact JWS from section 3 |

## 3. Signing

The unsigned object is the receipt without `signature`. `result` inside the receipt is `applied`.

`signCompactJws` signs `receiptSigningBytes(unsigned)` with the imported private key and `kid`. The returned compact JWS is `signature`. The DO stores that object on `grant.receipt`. The alarm copies it onto `grant_ledger.receipt` and into the R2 line.

`applied` and `already_applied` include this object as the envelope `receipt`. Every other grant result omits `receipt`.

`registerServiceKey`, `revokeServiceKey`, `listServiceKeys`, `publishPlanVersion`, `retirePlanVersion`, `getCoverage`, `listGrants`, and `readCoverageEvents` return `ok` and omit `receipt`.

## 4. Test

E2E-P3.3-01 calls `verifyReceiptSignature` with the `public_key` from `PLATFORM_SIGNING_KEY`. Production code does not import `vendor-contracts/testkit`.
