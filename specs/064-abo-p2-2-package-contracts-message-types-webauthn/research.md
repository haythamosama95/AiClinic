# Research: P2.2 R-5

**Unit**: P2.2 · **Requirement**: FR-009

Rule S6 places this spike in the plan phase. The R-5 mitigation cell in 01 §7 says "Spike" and names no alternate fallback.

## 1. Questions

This unit records two outcomes (spec **Spikes**, FR-009):

1. WebAuthn ES256 DER-to-raw conversion on WebCrypto, in Node and in workerd.
2. Whether the Access `amr` claim is meaningful for `Cf-Access-Jwt-Assertion`.

P3.1 also takes Access `amr` and service-binding caller identity. Disabling `workers.dev` and preview URLs stays with that later reading of R-5.

## 2. ES256 DER to raw

WebCrypto `crypto.subtle.sign` / `crypto.subtle.verify` for `{ name: "ECDSA", hash: "SHA-256" }` on P-256 uses the raw `r || s` signature (32 bytes each). A WebAuthn ES256 assertion carries the DER encoding of those two integers. `crypto.subtle.verify` rejects that DER encoding. Verification converts DER to raw, then verifies.

The conversion used here:

- The DER value is a short-form `SEQUENCE` (`0x30`) of two `INTEGER`s (`0x02`).
- Each integer drops a single leading `0x00` when that padding byte is present, then is left-padded to 32 bytes.
- The raw signature is `r || s` (64 bytes).

Round-trip check: sign with WebCrypto, encode that raw signature as DER, decode it, and require the raw bytes to match.

| Runtime | Result |
| --- | --- |
| Node v20.19.1 | Raw length 64, DER length 72, round trip exact. Verify raw: true. Verify DER directly: false. Verify after conversion: true. |
| workerd via `packages/vendor-contracts` workers pool (Vitest 3.2.7) | The same three results: round trip exact, DER rejected, converted raw accepted. The pool requested compatibility date `2026-05-03` and the installed runtime reported a fallback to `2025-09-06`. The conversion still verified on that runtime. |

Ed25519 assertion signatures stay raw 64-byte values. `crypto.subtle.verify` with `{ name: "Ed25519" }` already verifies those bytes in this package (P2.1 JWS). RSASSA-PKCS1-v1_5 with SHA-256, 2048-bit keys, also signed and verified in both runtimes. Access tokens use that algorithm (section 3).

## 3. Access `amr`

The Cloudflare application token is the `Cf-Access-Jwt-Assertion` this unit verifies (02 §3.3, FR-010). Its documented payload fields are `aud`, `email`, `exp`, `iat`, `nbf`, `iss`, `type`, `identity_nonce`, `sub`, and `country`. That payload does not include `amr`. The documented signature algorithm is RS256. The documented header is `{ alg: "RS256", kid, typ: "JWT" }`.

`amr` is an optional, identity-provider-supplied hint in other Access material. It is not a field of the application token this unit checks, and it is not the WebAuthn user-verification flag (04 §1.5, FR-008). This unit's Access verifier yields the email after the team certificate, issuer, `aud` tag, and expiry checks. It does not read `amr`.

## 4. Outcome

| Item | Outcome |
| --- | --- |
| ES256 DER → raw | Succeeds in Node and in the workers pool. The plan verifies ES256 by converting DER to raw and calling WebCrypto ECDSA P-256 SHA-256. EdDSA stays raw Ed25519. |
| Access `amr` | Not meaningful for this unit. The documented application token has no `amr` claim. FR-010 does not consult it. |
| Fallback | The mitigation cell names none. The ES256 conversion succeeded, so the plan adopts no fallback. |

## 5. Plan consequence

`src/webauthn.ts` implements the conversion from section 2. `src/access-jwt.ts` verifies RS256 against the injected team certs document and does not read `amr`. No alternate algorithm, library, or Edge Function is added.
