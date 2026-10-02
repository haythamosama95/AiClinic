# Contract: WebAuthn assertion and registration attestation

**Unit**: P2.2 · **Requirements**: FR-008, FR-009

Later units bind to this file. The ES256 conversion is `research.md` section 2. Registration attestation parsing reads the credential algorithm and the public key. It does not add an attestation field list.

## 1. Module

`packages/vendor-contracts/src/webauthn.ts`, re-exported from `src/index.ts`.

```ts
export function verifyAssertion(input: {
  assertion: Assertion
  operation: unknown
  rpId: string
  origin: string
  publicKey: CryptoKey
}): Promise<{ ok: true } | { ok: false }>

export function parseRegistrationAttestation(
  attestation: { alg: string; publicKey: Uint8Array },
): Promise<{ ok: true; alg: "ES256" | "EdDSA"; publicKey: CryptoKey } | { ok: false }>
```

`origin` is the string `https://ops.<vendor-domain>` the caller passes. `rpId` is the console hostname the caller passes. This package does not embed a vendor domain.

P3.1 owns the `operator_credential` lookup, the 24-hour activation delay, the 5-minute freshness window, and the `assertion_used` insert. `verifyAssertion` takes the public key the caller supplies.

## 2. Assertion

```ts
export type Assertion = {
  alg: string
  authenticatorData: Uint8Array
  clientDataJSON: Uint8Array
  signature: Uint8Array
}
```

`authenticatorData` begins with 32 bytes of SHA-256(rpId) and then one flags byte. The flags byte uses bit 0 (`0x01`) as user presence and bit 2 (`0x04`) as user verification. `clientDataJSON` is UTF-8 JSON `{type, challenge, origin}`.

`verifyAssertion` accepts the assertion only when all of these hold:

- `clientDataJSON.type` is `webauthn.get`
- `clientDataJSON.challenge` equals `operationChallenge(operation)`
- `clientDataJSON.origin` equals `origin`
- the first 32 bytes of `authenticatorData` equal the raw SHA-256 of `rpId` (`sha256Hex`, then hex-decoded)
- the flags byte has user presence and user verification both set
- the signature verifies over `authenticatorData` concatenated with the raw SHA-256 of `clientDataJSON`. Both SHA-256 values in this module (`rpId` and `clientDataJSON`) are `sha256Hex` decoded from hex

`alg` `ES256` means `signature` is DER. The module converts it to raw `r || s` (`research.md` section 2) and calls `crypto.subtle.verify` with `{ name: "ECDSA", hash: "SHA-256" }` and the P-256 public key. `alg` `EdDSA` means `signature` is raw Ed25519, verified with `{ name: "Ed25519" }`. Any other `alg` returns `{ ok: false }`.

A testkit assertion over operation O verifies. The same assertion against an operation whose `params` differ in one value returns `{ ok: false }`. A cleared user-verification flag, a different origin, or a different `rpId` each return `{ ok: false }`.

## 3. Registration attestation

`parseRegistrationAttestation` accepts `alg` `ES256` or `EdDSA`.

| `alg` | `publicKey` bytes | Import |
| --- | --- | --- |
| `ES256` | SPKI | `{ name: "ECDSA", namedCurve: "P-256" }` |
| `EdDSA` | Raw 32-byte Ed25519 | `{ name: "Ed25519" }` |

Any other `alg`, or bytes that do not import, returns `{ ok: false }`. The attestation object has those two fields and no further catalogue.

## 4. Tests

E2E-P2.2-01, E2E-P2.2-02, and E2E-P2.2-03 in `packages/vendor-contracts/test/webauthn.test.ts` run in Node and in workerd. The software authenticator that builds the assertion and the attestation is `contracts/testkit.md`.
