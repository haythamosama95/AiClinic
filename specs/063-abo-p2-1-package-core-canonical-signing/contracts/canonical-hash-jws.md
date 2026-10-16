# Contract: Canonical bytes, SHA-256 hex, and compact JWS

**Unit**: P2.1 · **Requirements**: FR-003, FR-004, FR-010

Later units bind to this file and to `packages/vendor-contracts/vectors/canonical.json` and `packages/vendor-contracts/vectors/jws.json`. P5.2 and P6.1 consume those vector files. P2.2 consumes `canonicalize`, `sha256Hex`, `signCompactJws`, and `verifyCompactJws`.

## 1. Module

`packages/vendor-contracts/src/canonical.ts` and `packages/vendor-contracts/src/jws.ts`, re-exported from `packages/vendor-contracts/src/index.ts`.

```ts
export function canonicalize(value: unknown): Uint8Array
export function sha256Hex(bytes: Uint8Array): Promise<string>
export function signCompactJws(input: {
  payload: Uint8Array
  privateKey: CryptoKey
  kid: string
}): Promise<string>
export function verifyCompactJws(input: {
  jws: string
  publicKey: CryptoKey
  kid: string
}): Promise<boolean>
```

`sha256Hex`, `signCompactJws`, and `verifyCompactJws` call WebCrypto `crypto.subtle`. Both workerd and Node provide that API (04 §1.1).

## 2. Canonical bytes

`canonicalize` returns the UTF-8 bytes of the JSON Canonicalization Scheme (RFC 8785) for `value`. It does not use `JSON.stringify` as the canonical form.

`value` is a JSON value: `null`, a boolean, a finite number, a string, an array of JSON values, or an object whose keys are strings and whose values are JSON values. Any other input throws `TypeError`.

`vectors/canonical.json` lists the fixture objects and the hex of their canonical bytes. The objects cover unsorted object keys, a nested object, an array, a string that RFC 8785 escapes, and a number in the RFC 8785 form. E2E-P2.1-01 asserts that Node and workerd each produce those bytes.

## 3. SHA-256 hex

`sha256Hex` returns the lowercase hex of SHA-256 over `bytes` (64 hex characters). Identifier functions in `contracts/identifiers.md` hash UTF-8 strings by encoding the string and calling `sha256Hex`.

## 4. Compact JWS

The serialization is the RFC 7515 compact serialization: base64url header, base64url payload, and base64url signature, joined by `.`. Base64url is RFC 4648 §5 with no padding.

The header object is `{ "alg": "EdDSA", "kid": "<kid>" }` canonicalised with `canonicalize`. `alg` sorts before `kid`.

The payload segment is the base64url of the canonical bytes the caller passes as `payload`. The signature is Ed25519 over the ASCII signing input `base64url(header) || "." || base64url(payload)`, via `crypto.subtle.sign` and `crypto.subtle.verify` with algorithm name `Ed25519`. The private key imports as PKCS#8 and the public key as raw 32 bytes, the forms both runtimes accept.

`verifyCompactJws` returns `true` only when the compact form has three segments, the header `alg` is `EdDSA`, the header `kid` equals the `kid` argument, and the signature verifies. A changed payload, a changed `kid`, a malformed compact string, or any other `alg` returns `false`. Those failures do not throw.

Ed25519 is deterministic (RFC 8032). `vectors/jws.json` stores one PKCS#8 private key, one raw public key, one `kid`, one payload object, the hex of its canonical bytes, and one compact JWS. E2E-P2.1-02 asserts that Node and workerd each reproduce that JWS and that `verifyCompactJws` accepts it, and that a changed payload or a changed `kid` returns `false`.
