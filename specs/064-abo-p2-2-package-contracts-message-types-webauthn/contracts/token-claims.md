# Contract: AI, billing, and feed token claims

**Unit**: P2.2 · **Requirements**: FR-011

Later units bind to this file. These tokens are compact JWTs. Their header is `{alg: "EdDSA", kid, typ: "JWT"}`, which is the 04 §2.1 header.

The frozen P2.1 JWS header is `{alg: "EdDSA", kid}` only (`specs/063-abo-p2-1-package-core-canonical-signing/contracts/canonical-hash-jws.md`). `signCompactJws` emits that header. This module builds the 04 §2.1 header with `canonicalize` and signs it with WebCrypto Ed25519. It leaves `src/jws.ts` unchanged. Grant and receipt signatures stay on `signCompactJws` / `verifyCompactJws`.

## 1. Module

`packages/vendor-contracts/src/token-claims.ts`, re-exported from `src/index.ts`.

```ts
export type TokenAudience = "ai-platform" | "abo" | "ai-platform-feed"

export function validateTokenClaims(input: {
  jwt: string
  audience: TokenAudience
  issuerId: string
  publicKey: CryptoKey
  kid: string
}): Promise<{ ok: true } | { ok: false }>
```

`issuerId` is the backend issuer id (`ai.issuer_id`) the caller passes. This package does not read the database and does not call `current_org_id()`.

## 2. Header and common claims

The header bytes equal `canonicalize({ alg: "EdDSA", kid, typ: "JWT" })`, and `kid` equals the argument. The signature is Ed25519 over the ASCII signing input `base64url(header) || "." || base64url(payload)`, checked with `crypto.subtle.verify` and `{ name: "Ed25519" }`.

| Claim | Rule |
| --- | --- |
| `iss` | Equals `issuerId` |
| `ver` | The string `"2"` |
| `aud` | Equals `audience` |
| `jti` | String, UUID `8-4-4-4-12` lowercase hex |
| `iat`, `exp` | Numbers. `exp - iat` is within the audience maximum below |

## 3. Audience claims

| Claim | AI `ai-platform` | Billing `abo` | Feed `ai-platform-feed` |
| --- | --- | --- | --- |
| `sub` | String | String | The string `backend-feed` |
| `org` | String | String | Absent |
| `role` | String | The string `administrator` | Absent |
| `branch` | String | String | Absent |
| `scopes` | Array of strings, each starting with `ai.` | Absent | Absent |
| `exp - iat` | ≤ 600 | ≤ 300 | ≤ 120 |

Absent means the payload has no such key. A feed token whose payload has an `org` key fails. A billing token whose `exp - iat` is greater than 300 fails.

## 4. Vector

`packages/vendor-contracts/vectors/token-claims.json` holds one unsigned payload for each audience. E2E-P2.2-07 mints signed tokens with the testkit issuer and checks the billing lifetime and the feed `org` rejection in Node and in workerd.
