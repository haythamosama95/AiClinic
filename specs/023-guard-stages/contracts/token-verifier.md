# Contract: TokenVerifier port and enrolled-key verification (B3)

**Frozen by:** Slice B3 — Guard stages: identity, rate limiting, entitlement and kill switches
**Implements:** §4.3.2, §4.2.1, §5.6 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices **B4** (admission — verifies nothing itself but consumes the
principal), **J4** (token-contract rotation — adds a second accepted `ver` value) **consume** this
contract; the no-rework rule applies (Delivery Plan §2.3). A later slice may **extend** (e.g. J4
overlapping `ver` acceptance; the OIDC/JWKS strategy as a second impl) but may not **rewrite**
anything below.

**Source of truth in code:** `ai-platform/src/identity/index.ts` (`TokenVerifier`, `VerifyContext`,
`VerifyResult`, `Principal`, `EnrolledKeyVerifier`).

**Traces to:** spec FR-001–FR-005, FR-013, FR-014; Clarification Q2 (config-cache read path) and
Q3 (port shape).

---

## 1. Overview

The identity stage (§6.1 stage 2) verifies the AAT through a **port** with two strategies; only the
enrolled-installation-key strategy is built in B3 (§4.3.2). The port is a single-method interface so
that swapping the implementation (the enrolled-key verifier for the OIDC/JWKS verifier reserved for
Tier 3, or a test fake) changes no outcome — the property pinned by the
`verifier_swap_changes_no_outcome` test.

Verification uses WebCrypto `Ed25519` `importKey` (JWK or raw) and `verify` (§4.2.1). `alg` is pinned
to `EdDSA`; a verifier that accepts anything else — in particular `none` or an HMAC algorithm — is
accepting a forgery (§5.6).

---

## 2. Port shape

```ts
export interface TokenVerifier {
  verify(token: string, ctx: VerifyContext): Promise<VerifyResult>;
}
```

One method. No `verifySignature` / `checkAudience` / `checkExpiry` / `checkSkew` split — the caller
folds the result, never the control flow. The OIDC/JWKS strategy (Tier 3) is a second
implementation of this same interface.

---

## 3. VerifyContext

The context the caller supplies. Every field is answerable from the cited sections or from a
consumed slice's frozen contract; B3 invents none.

| Field | Type | Source |
| --- | --- | --- |
| `audience` | `string` | The AI platform audience the platform expects (§5.6 `aud`; the value B1's issuer writes, mirrored from clinic config `ai.aat.audience`, default `ai-platform`). |
| `clockSkewSeconds` | `number` | The configured clock-skew tolerance (§4.3.2). A config-cache property frozen by A5; B3 reads it, never chooses it. |
| `now` | `number` | Unix epoch seconds at the call (injectable so tests fix the instant). |
| `cache` | `ConfigCache` | The shared A5 config cache. |
| `reader` | `D1Reader` | The A5 D1 reader port; identity calls `loadConfig(cache, reader, "installations", iss)` and `loadConfig(cache, reader, "keys", kid)` on a miss (Clarification Q2). |

---

## 4. VerifyResult

A discriminated union. The caller (and the pipeline orchestrator after it) folds the result; no
exception is thrown for a rejection.

```ts
export type VerifyResult =
  | { ok: true; principal: Principal }
  | { ok: false; code: "unauthenticated" | "installation_suspended" };
```

`code` is a member of the §5.4 taxonomy the identity stage can emit (spec `### Edge Cases`): only
`unauthenticated` (bad signature, wrong `alg`, wrong audience, expired, out-of-skew, unknown issuer)
and `installation_suspended` (§6.1 stage 2). No other code is emitted by this stage. The HTTP
translation is the protocol adapter's (A6), not identity's.

---

## 5. Principal

The immutable request principal (§4.3.2) — frozen in `request-principal.md`. Every later stage reads
it; none may mutate it (`principal_immutable_to_later_stage`).

---

## 6. Enrolled-key strategy algorithm

The `EnrolledKeyVerifier` implements `TokenVerifier` and MUST, in order:

1. Split the token into three base64url segments; reject `unauthenticated` if any is missing or the
   shape is not exactly three segments.
2. Base64url-decode and JSON-parse the header; reject `unauthenticated` if it fails.
3. Require `header.alg === "EdDSA"`; reject `unauthenticated` otherwise (§5.6 — `none` and HMAC are
   forgeries). No other `alg` is accepted (the architecture is explicit, not preferential).
4. Require a non-null `header.kid`; reject `unauthenticated` otherwise (§4.3.2 key selection).
5. Base64url-decode and JSON-parse the payload; reject `unauthenticated` if it fails. Every §5.6
   claim is required by the B1 contract (`iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`,
   `jti`, `iat`, `exp`, `ver`); a missing claim is `unauthenticated` — B3 verifies the contract, it
   does not redefine it.
6. `loadConfig(cache, reader, "installations", payload.iss)`; on `ConfigCacheMissError` reject
   `unauthenticated` (unknown issuer, §4.3.2).
7. If the installation record's `status` is `suspended`, reject `installation_suspended` (§6.1 stage
   2; B2 `installation.status` contract). If `status !== "active"` for any other reason (including
   `deleted`), reject `unauthenticated` — fail closed on lifecycle.
8. `loadConfig(cache, reader, "keys", header.kid)`; on `ConfigCacheMissError` reject
   `unauthenticated` (unknown `kid`). If the key row is revoked (`revoked_at` non-null in the
   consumed B1/A5 row shape) reject `unauthenticated` (§4.2.1). If
   `keyRow.installation_id !== payload.iss`, reject `unauthenticated` — the key is selected by
   **`iss` and `kid`** together (§4.3.2; prevents cross-installation impersonation).
9. Require `payload.aud === ctx.audience`; reject `unauthenticated` otherwise (§4.3.2 audience).
   *(Implementation may evaluate audience and skew before the D1 loads — pure claim checks first.)*
10. Require `payload.iat - ctx.clockSkewSeconds <= ctx.now <= payload.exp + ctx.clockSkewSeconds`;
    a token outside the skew window is rejected `unauthenticated`; a not-yet-valid **or expired**
    token inside the window is accepted (§4.3.2 clock-skew tolerance;
    `identity_accepts_notyetvalid_inside_skew`, `identity_accepts_expired_inside_skew`).
11. Import the enrolled public key as a WebCrypto `Ed25519` key (JWK `{"kty":"OKP","crv":"Ed25519",
    "x":…}` per B1 §7, or raw 32 bytes) and call `crypto.subtle.verify("EdDSA", key, signature,
    signingInput)` where `signingInput` is the UTF-8 bytes of `header_b64.payload_b64` (B1 §2).
    Reject `unauthenticated` if verification returns false (bad signature).
12. Check the token's `ver` against the accepted-`ver` set via
    `loadConfig(cache, reader, "token_contracts", payload.ver)` (§5.6; J4 extension). Miss or
    `retired_at != null` → `unauthenticated`. Overlapping acceptance of two active `ver` values is
    J4's concern; B3/identity performs the membership check.
13. Construct and return the immutable `Principal` from the verified payload claims. `scopes` come
    from the verified token (B1 derives them server-side from RBAC; B3 does not re-derive and never
    accepts a caller-supplied `scopes` — §5.6). Guard rejections from this stage MUST call
    `recordGuardRejection` (FR-011; §4.3.12).

`jti` replay rejection is **not** in this algorithm — it is B4's, inside the single Quota DO round
trip (§4.3.2 "Replay rejection is not part of this stage's own I/O"; spec FR-014). B3 does not
pre-check, short-circuit, or contact the DO.

---

## 7. I/O budget

On a cold isolate, identity performs the same single same-region D1 read on a miss that A5
froze — one for `installations`, one for `keys`, and (via the J4 extension) one for
`token_contracts`, each via `loadConfig`. On a warm isolate all return from memory with zero
`reader.read` calls (A5 `T-A5-18`). Audience and skew are pure claim checks and SHOULD run before
those loads so obviously-dead tokens never touch the cache.

---

## 8. Consumers

| Slice | What it binds from this contract |
| --- | --- |
| **B4** (admission) | Consumes the `Principal` the verifier produces; never re-verifies the token. The `jti` is on the principal for the admission-stage replay check. |
| **J4** (token-contract rotation) | Adds a second accepted `ver` value during the rotation window; may extend the `VerifyContext` or the algorithm's `ver` handling, never rewrite the `alg` pin or the claim set. |
| **Later pipeline stages** (C1, C2, D1, …) | Read the immutable `Principal`; never mutate it. |

---

## 9. Out of scope for this contract

| Behaviour | Owner | Reason |
| --- | --- | --- |
| `jti` replay rejection | B4 | §4.3.3 — rides the single Quota DO round trip |
| Idempotency-key novelty | B4 | §4.3.3 — same round trip |
| `ver` overlap acceptance | J4 | §5.7; delivery plan §3.9 row J4 |
| OIDC / JWKS strategy | Tier 3 | §4.3.2 — reserved, not built |
| HTTP status translation | A6 | §4.3.1; §5.4 HTTP column is the adapter's |
| Issuance, signing, claim derivation | B1 | §4.2.1; §5.6 — B3 verifies, never mints |
