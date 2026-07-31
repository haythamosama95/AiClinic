# Contract: AI Access Token (AAT) JWS Wire Shape (B1)

**Frozen by:** Slice B1 — Installation keystore and AAT issuer
**Implements:** §4.2.1, §5.6, §8.1 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (B3 verifier, B4 `jti` admission) **consume** this contract; the
no-rework rule applies (Delivery Plan §2.3). A later slice may **extend** (e.g. J4 overlapping `ver`
acceptance) but may not **rewrite** anything below.

**Pinned by contract tests:** `T07 all section 5.6 claims populated` (claim set),
`T05 previous-key AAT still verifies within validity window` and `T06 revoked key rejected`
(rotation and revocation semantics).

**Source of truth in code:** `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql`
(`auth_internal.issue_ai_token`, `auth_internal.verify_aat`, `auth_internal.base64url_encode`);
`backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql`
(enrollment and additive rotation).

---

## 1. Overview

An **AI Access Token (AAT)** is a compact, three-segment **JSON Web Signature (JWS)** minted by the
clinic's `auth_internal.issue_ai_token` `SECURITY DEFINER` RPC and presented by the Flutter client to
the AI gateway on every AI request. It is distinct from the clinic session JWT: the `aud` claim binds
the token to the AI platform audience so the two token kinds cannot be substituted for one another
(§5.6).

The AAT carries installation identity, tenant scope, actor attribution, and RBAC-derived AI capability
scopes. It deliberately omits patient identifiers, quota state, and provider/model hints (§5.6 deliberate
omissions). `scopes` are derived server-side from RBAC and are **never** client-supplied.

---

## 2. JWS wire encoding

The token is the concatenation of three base64url-encoded segments separated by ASCII period (`.`):

```text
<base64url(header)> . <base64url(payload)> . <base64url(signature)>
```

| Segment | Contents |
| --- | --- |
| Header | JSON object (§3) |
| Payload | JSON object (§4) |
| Signature | Ed25519 detached signature over the signing input (§6) |

**Base64url encoding** uses PostgreSQL `encode(bytes, 'base64')` followed by `translate(..., '+/', '-_')`
and stripping trailing `=` padding — the `auth_internal.base64url_encode` helper. Decoding reverses
this (`auth_internal.base64url_decode`). `pgjwt` is not used (§4.2.1).

The signing input is the UTF-8 byte sequence of the literal string
`{header_b64}.{payload_b64}` — the two encoded segments joined by `.`, with no trailing period before
the signature segment.

---

## 3. Header

The JWS header is a JSON object with exactly these members:

| Member | Type | Value | Notes |
| --- | --- | --- | --- |
| `alg` | string | `"EdDSA"` | **Non-negotiable.** A verifier that accepts any other algorithm — including `none` or an HMAC algorithm — is accepting a forgery (§5.6). |
| `kid` | string | Key identifier | Selects the installation signing key row (`ai_internal.installation_keys.kid`) that produced the signature. Together with payload `iss`, this selects the verification public key (§5.6; §4.2.1). |

No other header members are part of this contract. A compliant issuer emits only `alg` and `kid`.

Example:

```json
{"alg":"EdDSA","kid":"f47ac10b-58cc-4372-a567-0e02b2c3d479"}
```

---

## 4. Payload claims

Every claim listed in §5.6 is **required** on every minted AAT. Each MUST be present and non-null
(contract test T07).

| Claim | JSON type | Semantics | Source at issuance |
| --- | --- | --- | --- |
| `iss` | string | Installation id | `installation_keys.installation_id` of the signing key, as UUID text. Selects the enrolled installation for verification (§5.6). |
| `aud` | string | AI platform audience | Clinic config `ai.aat.audience` (default `"ai-platform"`). Prevents reuse of clinic session tokens and vice versa (§5.6). |
| `sub` | string | Actor: staff member id | `staff_members.id` of the authenticated caller, as UUID text. Attribution and per-actor rate limits (§5.6). |
| `org` | string | Organization (tenant) id | `organization_id` from `auth_internal.build_staff_claims`, as UUID text (§5.6). |
| `branch` | string | Branch id (tenant scope) | Primary active branch assignment for the staff member, as UUID text (§5.6). |
| `role` | string | Staff role | `staff_members.role` enum text (§5.6). |
| `scopes` | array of strings | Permitted AI capability scopes | RBAC-derived: every `permission_key` in the `ai.*` namespace granted to the caller's role via `roles_permissions` where `is_granted = true`. **Never** taken from a caller-supplied parameter; a `p_scopes` argument on the issuer RPC is ignored (§5.6; contract test T08). |
| `jti` | string | Unique token id | `gen_random_uuid()`, as UUID text. Used for replay rejection at gateway admission (B4); minted here, consumed later (§5.6). |
| `iat` | number | Issued-at time | Unix epoch seconds (`extract(epoch from now())::bigint`) at mint time (§5.6). |
| `exp` | number | Expiry time | `iat` plus the configured lifetime in seconds (`ai.aat.lifetime_minutes`, default 15). MUST satisfy `0 < exp − iat ≤ lifetime_seconds` (contract test T12). Short lifetime, minutes (§5.6). |
| `ver` | string | Token contract version | Clinic config `ai.aat.ver` (default `"1"`). Enables later rotation of the contract itself (§5.6; overlapping acceptance is J4). |

Numeric claims (`iat`, `exp`) are JSON numbers (not quoted strings).

Example payload (illustrative values):

```json
{
  "iss": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "aud": "ai-platform",
  "sub": "c1000000-0000-4000-8000-000000000001",
  "org": "d2000000-0000-4000-8000-000000000001",
  "branch": "e3000000-0000-4000-8000-000000000001",
  "role": "doctor",
  "scopes": ["ai.access"],
  "jti": "f4000000-0000-4000-8000-000000000001",
  "iat": 1720000000,
  "exp": 1720000900,
  "ver": "1"
}
```

---

## 5. Deliberate omissions

The following MUST **not** appear in an AAT payload. Any issuer or client path that adds one is out of
scope and constitutes contract drift (§5.6 deliberate omissions; FR-006).

| Omitted category | Rationale |
| --- | --- |
| Patient identifiers | A token is not a resource grant to patient data. |
| Quota state | Owned by the platform; would be stale instantly. |
| Provider or model hints | The client has no say in routing or model selection. |

No claim name, nested object, or extension field carrying any of the above is permitted under this
contract version (`ver: "1"`).

---

## 6. Signing and verification

### 6.1 Keypair generation

During enrollment or rotation, the clinic database calls `pgsodium.crypto_sign_new_keypair()`, which
returns a 64-byte Ed25519 secret key and a 32-byte public key (§4.2.1). The enrollment role MUST hold
`pgsodium_keymaker`. The secret key is stored in `ai_internal.installation_keys.secret_key` and is
readable only by `SECURITY DEFINER` issuer and keypair routines — never by `anon` or `authenticated`
(§4.2).

### 6.2 Signing (clinic issuer)

```text
signature = pgsodium.crypto_sign_detached(
  convert_to(header_b64 || '.' || payload_b64, 'utf8'),
  secret_key
)
token     = header_b64 || '.' || payload_b64 || '.' || base64url(signature)
```

The issuer selects the **current** signing key: the non-revoked `installation_keys` row with the
latest `valid_from` for the installation.

### 6.3 Verification (clinic self-test)

`auth_internal.verify_aat(token)` implements the clinic-side verifier used by contract tests T05 and
T06:

1. Split the token into three segments; reject if any segment is missing.
2. Base64url-decode the header; require `alg = "EdDSA"` and a non-null `kid`.
3. Load `installation_keys` by `kid`; reject if not found, soft-deleted, or `revoked_at IS NOT NULL`
   (contract test T06).
4. Reconstruct the signing input `header_b64 || '.' || payload_b64`.
5. Return the result of `pgsodium.crypto_sign_verify_detached(signature, signing_input_bytes, public_key)`.

### 6.4 Verification (platform gateway — B3 consumer)

The gateway verifier port (B3) MUST verify the same JWS shape using WebCrypto `Ed25519` `importKey`
(JWK or raw 32-byte public key) and `verify` (§4.2.1). Key lookup is by `iss` (installation id) and
`kid` (header); no network call is required for the enrolled-installation-key strategy.

---

## 7. Public key format (JWK)

The 32-byte raw Ed25519 public key is published to the platform during enrollment and on rotation as a
JSON Web Key (§4.2.1):

| Member | Value |
| --- | --- |
| `kty` | `"OKP"` |
| `crv` | `"Ed25519"` |
| `x` | Base64url encoding of the raw 32-byte public key (same encoding rules as §2) |
| `kid` | The `installation_keys.kid` string that signed tokens carrying this key in the JWS header |

Example:

```json
{
  "kty": "OKP",
  "crv": "Ed25519",
  "x": "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo",
  "kid": "f47ac10b-58cc-4372-a567-0e02b2c3d479"
}
```

The JWKS-shaped representation is fixed so the platform config cache and the OIDC verifier port
(B3) share one key-import path (§4.2.1; §4.3.2).

---

## 8. Key rotation and revocation

### 8.1 Additive rotation

Key rotation is **additive** (§4.2; §8.1): `auth_internal.rotate_installation_key` inserts a new
`installation_keys` row with a fresh `kid` and keypair without removing or overwriting the previous
row. Both keys remain present; the previous key's `revoked_at` stays null until explicitly revoked.

During the overlap window:

- New tokens are signed with the key having the latest `valid_from` (the current signing key).
- Tokens already signed under a previous `kid` **continue to verify** until their `exp` claim passes,
  provided that key has not been revoked (contract test T05).

The platform accepts multiple active public keys per installation, selected by `kid` in the JWS header
(§8.1: "the platform accepts both keys during the overlap, so no clinic is offline for a rotation").

### 8.2 Revocation

`auth_internal.revoke_installation_key(p_kid)` sets `revoked_at` on the named key row. Verification
MUST reject any AAT whose header `kid` references a revoked key, regardless of `exp` (contract test
T06). Revocation is distinct from rotation: rotation adds a successor key; revocation terminates
trust in a specific key.

### 8.3 Key selection rule

| Operation | Selection rule |
| --- | --- |
| Signing (issuer) | Non-revoked key with greatest `valid_from` for the installation |
| Verifying (clinic or platform) | Exact match on header `kid` against enrolled key set for payload `iss`; key MUST NOT be revoked |

`iss` plus `kid` together select the verification public key. Rotation is therefore a key-set operation,
not a re-enrollment (§5.6).

---

## 9. Out of scope for this contract

The following behaviours are enforced by the issuer RPC and its tests but are **not** part of the
frozen wire shape consumed by B3/B4:

| Behaviour | Test | Notes |
| --- | --- | --- |
| Session validity gate | T09 | Absent or expired clinic session is rejected before minting |
| Issuance ledger row | T10 | One `ai_token_issuance` row per `jti` |
| Issuer rate limit | T11 | Per-actor mint ceiling within a configured window |
| Keystore RLS deny | T01–T03 | `anon`/`authenticated` cannot read signing keys |

B3 implements gateway-side expiry, audience, and scope checks on the wire claims defined in §4. B4
implements `jti` replay rejection at admission using the `jti` claim minted here.
