# Contract: Access JWT

**Unit**: P2.2 · **Requirements**: FR-010

Later units bind to this file. Verification lives in the shared package (rule S7). The algorithm and the `amr` finding are `research.md` section 3.

## 1. Module

`packages/vendor-contracts/src/access-jwt.ts`, re-exported from `src/index.ts`.

```ts
export type AccessCertsDocument = {
  issuer: string
  keys: Array<{
    kid: string
    kty: "RSA"
    alg: "RS256"
    n: string
    e: string
  }>
}

export function verifyAccessJwt(input: {
  jwt: string
  certs: AccessCertsDocument
  aud: string
  nowSeconds: number
}): Promise<{ ok: true; email: string } | { ok: false }>
```

The caller injects `certs`. This module does not fetch a certs URL. `nowSeconds` is the caller's current Unix time. Tests pass a fixed value. This unit adds no clock binding (rule V4; the test clock arrives in P3.1).

## 2. Checks

The JWT is compact serialization: header, payload, signature. The header `alg` is `RS256`. The header `kid` selects `certs.keys`. An unknown `kid` returns `{ ok: false }`. The matching JWK verifies the signature with `crypto.subtle` algorithm `RSASSA-PKCS1-v1_5` and hash `SHA-256`.

The payload `iss` equals `certs.issuer`. The payload `aud` equals `aud`, or is an array that contains `aud`. The payload `exp` is a number greater than `nowSeconds`. The payload `email` is a string, and a passing call returns that email.

A wrong `aud` tag, an expired token, or an unknown cert `kid` each return `{ ok: false }`. The module does not read `amr`.

## 3. Tests

E2E-P2.2-04 in `packages/vendor-contracts/test/access-jwt.test.ts` runs in Node and in workerd. The Access team key, minter, and certs document are `contracts/testkit.md`.
