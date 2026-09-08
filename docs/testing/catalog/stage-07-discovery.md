# Stage 07 — Discovery (GET /v1/capabilities)

Source files read: `ai-platform/src/discovery/index.ts`, `ai-platform/src/capability/index.ts`, `ai-platform/src/identity/index.ts`, `ai-platform/src/entitlement/index.ts`, `ai-platform/src/config-cache/index.ts`, `ai-platform/src/worker.ts`, `ai-platform/src/errors.ts`, `ai-platform/src/platform-vocabulary.ts`, `ai-platform/src/manifest/index.ts` (`hashManifest`), `ai-platform/src/reference.ts`, `ai-platform/src/trace.ts`, `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`, `ai-platform/migrations/20260731120000_platform_schema.sql`, `ai-platform/migrations/20260802100000_capability_grant_lifecycle.sql`, `ai-platform/migrations/20260803120000_token_contract.sql`, `ai-platform/migrations/20260807120000_kill_switch.sql`, orientation doc `docs/architecture/ai-platform/data-journey/09-stage-7-discovery.md`.

## Baseline journey B0 (referenced by most scenarios)

Unless a scenario says otherwise, "baseline" means the following real prior state, built through real operations in real order:

1. **Stage 3 happy path → enrolled installation.** D1 `installation` row: `installation_id = '3f6b2a90-4c1e-4d7a-9b2f-8e5c1a0d6f47'` (call it **I0**), `org_id = '8a1c4e62-9d3b-4f0a-a5e7-2b6d9c1f8034'`, `status = 'active'`, `region = 'eu'`. D1 `installation_key` row: `key_id = '01J9ZK3MQ8W2E7X4R6T0YHNBVP'` (call it **KID0**), `installation_id = I0`, `public_key` = base64url Ed25519 public key of the clinic keypair, `algorithm = 'EdDSA'`, `valid_from = '2026-08-01T00:00:00.000Z'`, `valid_until = NULL`, `revoked_at = NULL`.
2. **Stage 3/4 happy paths → active entitlement.** D1 `entitlement` row for I0: `plan = 'professional'`, `status = 'active'`, `allowed_capabilities = '["clinic.visit_summary"]'` (D1 column is TEXT holding JSON), non-zero quotas/budgets, current period. D1 `capability_grant` row: `scope = 'installation:3f6b2a90-4c1e-4d7a-9b2f-8e5c1a0d6f47'`, `capability_id = 'clinic.visit_summary'`, `capability_version = '1.0.0'`, `revoked_at = NULL`.
3. **Stage 6 AAT mint** via the test AAT-minting helper with full claim control (`mintAat(claims, privateKey)`), default claims: `iss = I0`, `aud = 'ai-platform'`, `sub = '5b2d7f14-6e8a-4c1b-93d0-7a4e2f6b9150'`, `org = '8a1c4e62-9d3b-4f0a-a5e7-2b6d9c1f8034'`, `branch = '2c7e9a41-1f5d-4b8c-a2e6-9d0b3c5f7128'`, `role = 'clinician'`, `scopes = ['ai.visit_summary']`, `jti = '01J9ZK5NRX4W8E2T6Y0QHMBVGD'`, `iat = now`, `exp = now + 300`, `ver = '1'`, header `{ alg: 'EdDSA', kid: KID0 }`, signed with the clinic private key. Call this token **AAT0**. D1 `token_contract` has the seeded row `ver = '1'`, `retired_at = NULL`.
4. The Worker registry is the production one: `clinic.visit_summary@1.0.0` only (`worker.ts` installs `manifests/published/clinic.visit_summary@1.0.0.json` at boot).

Error bodies below are produced by `buildErrorBody` and always have exactly the shape `{"code": "<taxonomy code>", "request_reference": "<XXXX-XXXX Crockford base32>", "trace_id": "<26-char ULID>", "retry_safe": <bool>}` with `Content-Type: application/json`; `request_reference`/`trace_id` are freshly generated per response and asserted by shape, not value. `retry_safe` is `true` for `unauthenticated` (retryable "After re-mint") and `false` for `installation_suspended` (retryable "No").

---

## 1. D1 reads (via config cache)

Discovery shares the isolate-scoped `ConfigCache` with `POST /v1/requests` and
`GET /v1/requests/{ref}`. Default TTL is `DEFAULT_CONFIG_CACHE_TTL_MS` (30 000 ms),
overridable at boot via the `CONFIG_CACHE_TTL_MS` wrangler var (`CACHE_TTL_MS` is a
deprecated alias). A prior request in the isolate can warm rows until TTL expiry.

| Cache kind | Key | Purpose |
| ---------- | --- | ------- |
| `installations` | `{installationId}` | Installation exists; lifecycle `status` |
| `keys` | `{kid}` | `installation_key` row — read during AAT verification only (`EnrolledKeyVerifier`) |
| `token_contracts` | `{ver}` | `token_contract` row — read during AAT verification only |
| `entitlements` | `{installationId}` | `status`, `allowed_capabilities`, `plan` |
| `grants` | `{installationId}/{capabilityId}` | Installation-scope version grant |
| `grants` | `plan:{plan}/{capabilityId}` | Plan-scope grant fallback when the installation grant misses |
| `grants` | `global/{capabilityId}/{version}` | Lifecycle overlay — one read per registry candidate in `discover()` |

`keys` and `token_contracts` are consulted before `discover()` runs; entitlement and
grant kinds are read inside `discover()`.

## 2. Failure paths

| Condition | HTTP | Taxonomy code | `retry_safe` |
| --------- | ---- | ------------- | ------------ |
| Missing / malformed / invalid AAT (all cases before a verified principal) | 401 | `unauthenticated` | `true` |
| Valid signature but `installation.status = 'suspended'` | 403 | `installation_suspended` | `false` |

Any other non-`active`, non-`suspended` installation status still maps to `401
unauthenticated` (S07-024). Suspended is the **only** non-401 auth failure on this
endpoint (S07-023).

## 3. Grant revocation semantics

The production D1 reader's grant SQL filters `revoked_at IS NULL`
(`config-cache/index.ts:L310-L312`, `L325-L327`). A revoked installation-scope grant
therefore surfaces to `discover()` as a **miss**, not as a live row with
`revoked_at` set. Consequences:

1. The `grant.revoked_at != null → "skip"` branch in `discover()` is unreachable via
   the production reader (annotated A-08 in `discovery/index.ts:L103-L105`).
2. Revoking an installation-scope grant does **not** remove the capability from discovery
   when a live plan-scope grant exists — the installation grant miss falls through to the
   plan grant (S07-034).

## 4. Filtering, ETag, and auth telemetry

**Role and scope.** `discover()` evaluates entitlement status, plan tier,
`allowed_capabilities`, grants, and lifecycle only. It does **not** filter by
`Access.allowedStaffRoles` or `Access.requiredCapabilityScope`; those gates live in
`assertPlanAllowance` on the invoke path (S07-041).

**ETag scope.** `computeDiscoveryEtag` hashes `{manifests: [<public projection>, …]}` only —
no installation, org, branch, or principal field participates (S07-050). Installations with
identical entitled lists share the same ETag; the empty-list ETag is a fixed constant
across all unentitled callers.

**Bare-`Bearer` log reasons.** `Authorization: Bearer` with no trailing space fails
`startsWith("Bearer ")` and logs `invalid_authorization_scheme` (S07-005 note). The scheme
prefix followed only by whitespace trims to an empty token and logs `empty_bearer_token`.
Both return `401 unauthenticated`.

---

## Scenario S07-001 — POST to /v1/capabilities is not routed (404 plain text)

| Field | Content |
|-------|---------|
| ID | S07-001 |
| Journey setup | Baseline B0 (state irrelevant; dispatch happens before auth). |
| Action | `POST /v1/capabilities` HTTP/1.1, `Authorization: Bearer <AAT0>`, `Content-Type: application/json`, body `{}` |
| Expected outcome | HTTP `404`. Body is the plain text `Not Found` (not JSON, no error taxonomy body). No `ETag`/`Cache-Control` headers. `worker.ts` matches `/v1/capabilities` only when `request.method === "GET"`; any other method falls through every route check to the terminal 404. |
| Side effects | No D1/DO/R2 reads or writes (the AAT is never verified — the route guard runs first). |
| Code reference | `ai-platform/src/worker.ts:L1342-L1346 — fetch (route guard)`; `ai-platform/src/worker.ts:L1440-L1444 — fetch (route_not_found 404)` |

## Scenario S07-002 — Near-miss path /v1/capabilities/ is not routed (404)

| Field | Content |
|-------|---------|
| ID | S07-002 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities/` (trailing slash) with `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `404`, plain text body `Not Found`. Dispatch compares `url.pathname === "/v1/capabilities"` exactly; the trailing-slash path matches no route. (Same for `HEAD /v1/capabilities` — method guard fails.) |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1342-L1346 — fetch (route guard)`; `ai-platform/src/worker.ts:L1440-L1444 — fetch (route_not_found 404)` |

## Scenario S07-003 — Missing Authorization header → 401 unauthenticated

| Field | Content |
|-------|---------|
| ID | S07-003 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities` with no `Authorization` header |
| Expected outcome | HTTP `401`. Body `{"code":"unauthenticated","request_reference":<ref>,"trace_id":<ulid>,"retry_safe":true}`. No `ETag`, no `Cache-Control`. Logs `discovery_auth_rejected` with `reason: "missing_authorization_header"`. |
| Side effects | No D1 reads (rejected before any config load). No writes. |
| Code reference | `ai-platform/src/discovery/index.ts:L42-L48 — handleDiscoveryRequest`; `ai-platform/src/discovery/index.ts:L24-L33 — unauthenticatedResponse` |

## Scenario S07-004 — Non-Bearer authorization scheme → 401 unauthenticated

| Field | Content |
|-------|---------|
| ID | S07-004 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, header `Authorization: Basic bm90LWFuLWFhdA==` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`, `retry_safe = true`. Log reason `invalid_authorization_scheme` with `authorization_scheme: "Basic"`. The check is the case-sensitive `header.startsWith("Bearer ")`. |
| Side effects | No D1 reads. No writes. |
| Code reference | `ai-platform/src/discovery/index.ts:L50-L57 — handleDiscoveryRequest (scheme check)` |

## Scenario S07-005 — Bearer scheme with empty token → 401 unauthenticated

| Field | Content |
|-------|---------|
| ID | S07-005 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, header `Authorization: Bearer    ` (scheme prefix followed only by spaces) |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. Log reason `empty_bearer_token`. The token is `header.slice(7).trim()`; whitespace-only trims to empty. (Note: the bare header `Authorization: Bearer` with no trailing space fails the earlier `startsWith("Bearer ")` check instead — same 401, log reason `invalid_authorization_scheme`.) |
| Side effects | No D1 reads. No writes. |
| Code reference | `ai-platform/src/discovery/index.ts:L59-L65 — handleDiscoveryRequest (empty token)` |

## Scenario S07-006 — Lowercase "bearer" scheme → 401 unauthenticated

| Field | Content |
|-------|---------|
| ID | S07-006 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, header `Authorization: bearer <AAT0>` (valid token, lowercase scheme) |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. Log reason `invalid_authorization_scheme`, `authorization_scheme: "bearer"`. Scheme matching is case-sensitive even though RFC 7235 schemes are case-insensitive — a production client sending lowercase is rejected. |
| Side effects | No D1 reads. No writes. |
| Code reference | `ai-platform/src/discovery/index.ts:L50-L57 — handleDiscoveryRequest (scheme check)` |

## Scenario S07-007 — Token is not three dot-separated segments → 401

| Field | Content |
|-------|---------|
| ID | S07-007 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer not-a-valid-token` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `token.split(".")` yields one segment; rejected before any decode. A guard rejection is recorded in the in-isolate rate-limit counters under bucket `unverified` (flushed by the scheduled job, not this request). |
| Side effects | No D1 reads/writes from this request. In-memory guard-rejection tally incremented (installation unattributed — bucket `unverified`). |
| Code reference | `ai-platform/src/identity/index.ts:L238-L245 — EnrolledKeyVerifier.verify (segment count)`; `ai-platform/src/identity/index.ts:L62-L68 — rejectUnauthenticated` |

## Scenario S07-008 — Undecodable / non-JSON JWT header segment → 401

| Field | Content |
|-------|---------|
| ID | S07-008 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer ###.e30.sig` (header segment is not base64url) — variant B: header segment base64url-decodes to `not json` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. Variant A fails `base64urlDecode`; variant B fails `parseJson`. Both reject before any claim or D1 work. |
| Side effects | Guard-rejection tally (`unverified`). No D1 reads. |
| Code reference | `ai-platform/src/identity/index.ts:L247-L254 — EnrolledKeyVerifier.verify (header decode/parse)` |

## Scenario S07-009 — JWT alg is not EdDSA → 401

| Field | Content |
|-------|---------|
| ID | S07-009 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <JWT with header {"alg":"HS256","kid":KID0} and otherwise well-formed payload/signature segments>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. Only `alg === "EdDSA"` is accepted; rejection happens before the `kid` lookup, so no key row is read. |
| Side effects | Guard-rejection tally (`unverified`). No D1 reads. |
| Code reference | `ai-platform/src/identity/index.ts:L257-L259 — EnrolledKeyVerifier.verify (alg check)` |

## Scenario S07-010 — JWT header missing kid → 401

| Field | Content |
|-------|---------|
| ID | S07-010 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <JWT with header {"alg":"EdDSA"} (no kid), valid payload, any 64-byte signature>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `kid` must be a non-empty string. |
| Side effects | Guard-rejection tally (`unverified`). No D1 reads. |
| Code reference | `ai-platform/src/identity/index.ts:L261-L263 — EnrolledKeyVerifier.verify (kid check)` |

## Scenario S07-011 — Payload missing required claims → 401

| Field | Content |
|-------|---------|
| ID | S07-011 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <JWT signed with clinic key, header {"alg":"EdDSA","kid":KID0}, payload {"iss":I0,"aud":"ai-platform","iat":now,"exp":now+300} — missing org/branch/role/scopes/jti/ver>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `parsePayloadClaims` requires string `iss/aud/sub/org/branch/role/jti/ver`, a string-array `scopes`, and numeric `iat/exp`; any miss rejects before D1 loads. (Pairwise variants to exercise: `scopes` as a string instead of array; `exp` as a string.) |
| Side effects | Guard-rejection tally (`unverified`). No D1 reads. |
| Code reference | `ai-platform/src/identity/index.ts:L104-L143 — parsePayloadClaims`; `ai-platform/src/identity/index.ts:L275-L278 — EnrolledKeyVerifier.verify` |

## Scenario S07-012 — Wrong audience claim → 401

| Field | Content |
|-------|---------|
| ID | S07-012 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <mintAat({...AAT0 claims, aud: "clinic-portal"})>` — properly signed, all other claims valid |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. Discovery verifies with `audience: "ai-platform"`; the `aud` check runs before any config-cache/D1 load, so a forged `iss` is never attributed (guard bucket stays `unverified`). |
| Side effects | Guard-rejection tally (`unverified`). No D1 reads. |
| Code reference | `ai-platform/src/identity/index.ts:L282-L284 — EnrolledKeyVerifier.verify (aud check)`; `ai-platform/src/discovery/index.ts:L70-L76 — handleDiscoveryRequest (verify context)` |

## Scenario S07-013 — Expired AAT (beyond 60 s clock skew) → 401

| Field | Content |
|-------|---------|
| ID | S07-013 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <mintAat({...AAT0 claims, iat: now-900, exp: now-120})>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `now > exp + 60` rejects. Boundary pairing: a token with `exp = now - 59` (inside the 60 s skew) passes this check and proceeds to key/signature verification. |
| Side effects | Guard-rejection tally (`unverified`). No D1 reads. |
| Code reference | `ai-platform/src/identity/index.ts:L286-L291 — EnrolledKeyVerifier.verify (expiry/skew check)` |

## Scenario S07-014 — AAT issued-at in the future (beyond skew) → 401

| Field | Content |
|-------|---------|
| ID | S07-014 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <mintAat({...AAT0 claims, iat: now+120, exp: now+420})>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `iat - 60 > now` rejects. Boundary pairing: `iat = now + 59` passes this check. |
| Side effects | Guard-rejection tally (`unverified`). No D1 reads. |
| Code reference | `ai-platform/src/identity/index.ts:L286-L291 — EnrolledKeyVerifier.verify (iat check)` |

## Scenario S07-015 — AAT lifetime exceeds 600 s maximum → 401

| Field | Content |
|-------|---------|
| ID | S07-015 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <mintAat({...AAT0 claims, iat: now, exp: now+601})>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `exp - iat > MAX_AAT_LIFETIME_SECONDS (600)` rejects even though the token is currently valid. Boundary pairing: `exp - iat = 600` exactly is accepted past this check. |
| Side effects | Guard-rejection tally (`unverified`). No D1 reads. |
| Code reference | `ai-platform/src/identity/index.ts:L293-L295 — EnrolledKeyVerifier.verify (lifetime cap)`; `ai-platform/src/identity/index.ts:L43 — MAX_AAT_LIFETIME_SECONDS` |

## Scenario S07-016 — Unknown installation (iss not in D1) → 401

| Field | Content |
|-------|---------|
| ID | S07-016 |
| Journey setup | Baseline B0, plus a second clinic keypair whose installation was never enrolled (no D1 `installation` row). |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <mintAat({...AAT0 claims, iss: "11111111-2222-4333-8444-555555555555"}, unknownKey)>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `loadConfig(cache, reader, "installations", iss)` throws `ConfigCacheMissError` (D1 `installation` SELECT returns no row) → reject. |
| Side effects | D1 read: `installation` (miss). Misses are not cached. Guard-rejection tally (`unverified` — attribution refused pre-signature). |
| Code reference | `ai-platform/src/identity/index.ts:L297-L304 — EnrolledKeyVerifier.verify (installation load)`; `ai-platform/src/config-cache/index.ts:L219-L224 — createD1ConfigReader (installations)` |

## Scenario S07-017 — Unknown kid (key not in D1) → 401

| Field | Content |
|-------|---------|
| ID | S07-017 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <mintAat(AAT0 claims, clinicKey) with header kid "01J9ZZZZZZZZZZZZZZZZZZZZ" — no such installation_key row>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `loadConfig(..., "keys", kid)` misses → reject. |
| Side effects | D1 reads: `installation` (hit), `installation_key` (miss). Guard-rejection tally (`unverified`). |
| Code reference | `ai-platform/src/identity/index.ts:L307-L315 — EnrolledKeyVerifier.verify (key load)`; `ai-platform/src/config-cache/index.ts:L225-L230 — createD1ConfigReader (keys)` |

## Scenario S07-018 — Revoked signing key → 401

| Field | Content |
|-------|---------|
| ID | S07-018 |
| Journey setup | Baseline B0, then Stage 3 key-revocation operation (or D1 `UPDATE installation_key SET revoked_at = '2026-09-05T00:00:00.000Z' WHERE key_id = KID0`) and a fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `keyRow.revoked_at != null` rejects before signature verification. |
| Side effects | D1 reads: `installation`, `installation_key`. No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L317-L319 — EnrolledKeyVerifier.verify (revoked key)` |

## Scenario S07-019 — Signing key outside its validity window → 401

| Field | Content |
|-------|---------|
| ID | S07-019 |
| Journey setup | Baseline B0, then D1 `UPDATE installation_key SET valid_until = '2026-09-01T00:00:00.000Z' WHERE key_id = KID0` (window already closed) and a fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `isKeyWithinValidityWindow` enforces `valid_from <= now < COALESCE(valid_until, +inf)`. Boundary pairing: `now` exactly equal to `valid_until` rejects (`nowMs >= validUntilMs`); a future `valid_from` rejects symmetrically. |
| Side effects | D1 reads: `installation`, `installation_key`. No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L321-L323 — EnrolledKeyVerifier.verify`; `ai-platform/src/identity/index.ts:L212-L233 — isKeyWithinValidityWindow` |

## Scenario S07-020 — kid belongs to a different installation → 401

| Field | Content |
|-------|---------|
| ID | S07-020 |
| Journey setup | Baseline B0 plus a second enrolled installation I1 (`installation_id = '7d4f1b83-2a6c-4e59-b8d1-3c9e0f5a2467'`, status active) with its own key KID1. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <mintAat({...AAT0 claims, iss: I0}, I0's key) but header kid = KID1>` — token names I0 but points at I1's key |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. Key selection is bound by `iss` AND `kid`: `keyRow.installation_id !== payload.iss` rejects before signature verification, so a cross-installation key confusion attack fails closed. |
| Side effects | D1 reads: `installation` (I0), `installation_key` (KID1). No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L325-L328 — EnrolledKeyVerifier.verify (key ownership binding)` |

## Scenario S07-021 — Stored key material unimportable → 401

| Field | Content |
|-------|---------|
| ID | S07-021 |
| Journey setup | Baseline B0, then [SEED] `UPDATE installation_key SET public_key = 'not-base64url!!!' WHERE key_id = KID0` — justified: enrollment validates key material, so this state is only reachable through operator error or corruption; no production operation creates it. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `importEd25519PublicKey` returns null (no `jwk` column value; `public_key` fails base64url decode) → reject. |
| Side effects | D1 reads: `installation`, `installation_key`. No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L335-L338 — EnrolledKeyVerifier.verify (key import)`; `ai-platform/src/identity/index.ts:L161-L209 — importEd25519PublicKey` |

## Scenario S07-022 — Invalid Ed25519 signature → 401

| Field | Content |
|-------|---------|
| ID | S07-022 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0 with the final segment replaced by a valid base64url encoding of 64 zero bytes>` — well-formed token, real kid, wrong signature |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `crypto.subtle.verify` over `<headerB64>.<payloadB64>` returns false. All config loads (installation, key) succeeded; only the cryptographic check fails. |
| Side effects | D1 reads: `installation`, `installation_key`. Guard-rejection tally (`unverified` — signature never verified, so no attribution). No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L340-L350 — EnrolledKeyVerifier.verify (signature verify)` |

## Scenario S07-023 — Suspended installation → 403 installation_suspended

| Field | Content |
|-------|---------|
| ID | S07-023 |
| Journey setup | Baseline B0, then Stage 3/4 suspend operation (or D1 `UPDATE installation SET status = 'suspended' WHERE installation_id = I0`) and a fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `403`. Body `{"code":"installation_suspended","request_reference":<ref>,"trace_id":<ulid>,"retry_safe":false}`. The signature verifies first (attribution is safe), then `installation.status === "suspended"` maps to the distinct taxonomy code. Discovery logs `discovery_auth_rejected` with `reason: "installation_suspended"`. This is the only non-401 auth outcome on this endpoint. |
| Side effects | D1 reads: `installation`, `installation_key`. Guard-rejection tally attributed to I0 with `error_code: "installation_suspended"`. No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L356-L358 — EnrolledKeyVerifier.verify (suspended)`; `ai-platform/src/discovery/index.ts:L78-L94 — handleDiscoveryRequest (verify failure mapping)`; `ai-platform/src/errors.ts:L34-L40 — TAXONOMY (installation_suspended → 403)` |

## Scenario S07-024 — Installation in a non-active, non-suspended status → 401

| Field | Content |
|-------|---------|
| ID | S07-024 |
| Journey setup | Stage 3 enroll happy path but stop before activation (or D1 `UPDATE installation SET status = 'pending' WHERE installation_id = I0`); key row present and valid; fresh config cache. Mint AAT0 normally. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"` (not 403). Lifecycle fails closed: only `status = 'active'` authenticates; any other non-`suspended` status (e.g. `pending`, `deleted`) is a plain `unauthenticated`, now attributed to I0 in the guard tally because the signature verified. |
| Side effects | D1 reads: `installation`, `installation_key`. Guard-rejection tally (I0, `unauthenticated`). No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L359-L361 — EnrolledKeyVerifier.verify (fail-closed lifecycle)` |

## Scenario S07-025 — Unknown token contract version (ver) → 401

| Field | Content |
|-------|---------|
| ID | S07-025 |
| Journey setup | Baseline B0. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <mintAat({...AAT0 claims, ver: "2"})>` — no `token_contract` row for `ver = '2'` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `loadConfig(..., "token_contracts", "2")` misses → reject. Note ordering: the contract check runs after signature verification and the installation-status check. |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract` (miss). Guard-rejection tally (I0, `unauthenticated`). No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L363-L371 — EnrolledKeyVerifier.verify (contract load)`; `ai-platform/src/config-cache/index.ts:L232-L237 — createD1ConfigReader (token_contracts)` |

## Scenario S07-026 — Retired token contract version → 401

| Field | Content |
|-------|---------|
| ID | S07-026 |
| Journey setup | Baseline B0, then the Stage 3/4 contract-retirement operation (or D1 `UPDATE token_contract SET retired_at = '2026-09-05T00:00:00.000Z' WHERE ver = '1'`) and a fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `401`, body `code = "unauthenticated"`. `contractRow.retired_at != null` rejects — a retired AAT contract version invalidates every token minted under it, regardless of signature validity. |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`. Guard-rejection tally (I0, `unauthenticated`). No writes. |
| Code reference | `ai-platform/src/identity/index.ts:L373-L375 — EnrolledKeyVerifier.verify (retired contract)` |

## Scenario S07-027 — No entitlement row → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-027 |
| Journey setup | Baseline B0 minus Stage 4: installation enrolled and active, key valid, but the entitlement row was never created (delete it if the enroll flow created a pending sentinel). Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`. Headers: `Content-Type: application/json`, `Cache-Control: private, must-revalidate`, `ETag: "<64-char lowercase hex>"` — the SHA-256 of the canonical JSON `{"manifests":[]}`, deterministic across calls and installations. Body exactly `{"manifests":[]}`. `discover()` treats an entitlement miss as the empty state (`reason: "entitlement_miss"`); it is not an error. |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`, `entitlement` (miss). No writes of any kind. |
| Code reference | `ai-platform/src/capability/index.ts:L646-L665 — discover (entitlement miss)`; `ai-platform/src/capability/index.ts:L869-L896 — buildDiscoveryResponse` |

## Scenario S07-028 — Entitlement not active (pending) → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-028 |
| Journey setup | Baseline B0 but entitlement left at the Stage 3 enroll sentinel: `status = 'pending'`, `allowed_capabilities = '[]'`. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`, empty-list ETag, `Cache-Control: private, must-revalidate`. Identity passed (this is not a 401); `discover()` short-circuits on `entitlement.status !== "active"` (`reason: "entitlement_inactive"`). |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`, `entitlement`. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L668-L676 — discover (entitlement inactive)` |

## Scenario S07-029 — Active entitlement with empty allowed_capabilities → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-029 |
| Journey setup | Baseline B0, but the Stage 4 entitle payload carried `allowed_capabilities: []` (D1 `'[]'`). Entitle rejects `grants: []` with 400 `invalid_payload` (S04-040), so the payload includes a dummy installation-scope grant that is never consulted — `allowed_capabilities: []` short-circuits the registry loop before grant evaluation. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`. The registry loop skips `clinic.visit_summary` because `allowedCapabilities.includes(capabilityId)` is false; grants are never consulted. |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`, `entitlement`. No grant reads (loop skips before grant evaluation). No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L689-L702 — discover (allowed_capabilities filter)`; `ai-platform/src/capability/index.ts:L144-L161 — parseAllowedCapabilities` |

## Scenario S07-030 — Malformed allowed_capabilities JSON → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-030 |
| Journey setup | Baseline B0, then [SEED] `UPDATE entitlement SET allowed_capabilities = 'not json' WHERE installation_id = I0` — justified: the entitle control route writes well-formed JSON; a corrupt value simulates operator error / manual D1 edit. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`. `parseAllowedCapabilities` fails closed: unparseable JSON string → `[]` → every capability filtered out. (Pairwise variants with the same outcome: a JSON array containing a non-string, e.g. `'[1]'`; a JSON non-array, e.g. `'{"a":1}'`.) |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`, `entitlement`. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L144-L161 — parseAllowedCapabilities (fail-closed parse)` |

## Scenario S07-031 — Capability not in allowed_capabilities → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-031 |
| Journey setup | Baseline B0, but Stage 4 entitled with `allowed_capabilities = '["clinic.patient_triage"]'` (a capability this Worker does not publish) and no grants. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`. The only registry entry (`clinic.visit_summary`) is not in the allowed list; conversely the allowed-but-unpublished id never appears because discovery iterates the registry, not the entitlement. |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`, `entitlement`. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L693-L702 — discover (registry iteration + allowed filter)` |

## Scenario S07-032 — Plan tier below the manifest minimum → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-032 |
| Journey setup | Baseline B0, but Stage 4 entitled with `plan = 'starter'` (the manifest's `Access.minimumPlanTier` is `'standard'`). Grant row present. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`. `planTierMeetsMinimum('starter', 'standard')` is false (rank 0 < rank 1), so the candidate is skipped before grant evaluation. Boundary pairing: `plan = 'standard'` (exact minimum) lists the capability; `professional`/`enterprise` also pass. |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`, `entitlement`. No grant reads. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L704-L711 — discover (plan-tier filter)`; `ai-platform/src/platform-vocabulary.ts:L87-L93 — planTierMeetsMinimum` |

## Scenario S07-033 — Installation-scope grant revoked, no plan grant → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-033 |
| Journey setup | Baseline B0, then the Stage 4 grant-revocation operation (D1 `UPDATE capability_grant SET revoked_at = '2026-09-05T00:00:00.000Z' WHERE scope = 'installation:3f6b2a90-4c1e-4d7a-9b2f-8e5c1a0d6f47' AND capability_id = 'clinic.visit_summary'`). No `plan:professional` grant exists. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`. Mechanism worth pinning: the D1 reader's installation-grant SQL filters `revoked_at IS NULL`, so the revoked row surfaces as a **miss**, the plan-grant fallback misses too, and the candidate is skipped. |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`, `entitlement`, `capability_grant` (installation scope — miss; plan scope — miss). No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L722-L747 — discover (grant evaluation)`; `ai-platform/src/config-cache/index.ts:L319-L332 — createD1ConfigReader (installation grant SQL)` |

## Scenario S07-034 — Installation-scope grant revoked but plan-scope grant exists → capability still listed

| Field | Content |
|-------|---------|
| ID | S07-034 |
| Journey setup | Baseline B0, plus a plan-scope grant (`scope = 'plan:professional'`, `capability_id = 'clinic.visit_summary'`, `capability_version = '1.0.0'`, `revoked_at = NULL`), then revoke the installation-scope grant as in S07-033. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body lists `clinic.visit_summary@1.0.0` exactly as in the happy path. This is the code-derived behavior, not the intuitive one: because the reader's SQL excludes revoked rows, the revoked installation grant is indistinguishable from "missing", the plan-grant fallback succeeds, and the capability remains advertised. The `grant.revoked_at != null → "skip"` branch in `discover()` is unreachable through the production D1 reader (§3). |
| Side effects | D1 reads: standard set plus both grant queries. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L722-L747 — discover (grant evaluation)`; `ai-platform/src/config-cache/index.ts:L319-L332 — createD1ConfigReader (revoked rows filtered by SQL)` |

## Scenario S07-035 — Installation grant pinned to a different version → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-035 |
| Journey setup | Baseline B0, but the Stage 4 grant row has `capability_version = '2.0.0'` while the registry holds `clinic.visit_summary@1.0.0`. No plan grant. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`. The grant row is live (not revoked) but `manifest.Identity.version !== grant.capability_version` → skip. A version-pinned grant does not advertise other versions of the same capability. |
| Side effects | D1 reads: standard set plus installation grant (hit). No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L727-L733 — discover (grant version mismatch)` |

## Scenario S07-036 — Plan-scope grant only (no installation grant) → capability listed

| Field | Content |
|-------|---------|
| ID | S07-036 |
| Journey setup | Baseline B0, except Stage 4 granted at plan scope only: no `installation:…` grant row; one `capability_grant` row with `scope = 'plan:professional'`, `capability_id = 'clinic.visit_summary'`, `capability_version = '1.0.0'`, `revoked_at = NULL`. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body identical in shape to the happy path (S07-042): one manifest, `Identity.capabilityId = "clinic.visit_summary"`. The installation-grant miss falls through to `loadMatchingGrant("plan:professional/clinic.visit_summary", "1.0.0")` → granted. |
| Side effects | D1 reads: standard set plus installation grant (miss) and plan grant (hit). No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L734-L744 — discover (plan-grant fallback)`; `ai-platform/src/capability/index.ts:L183-L207 — loadMatchingGrant` |

## Scenario S07-037 — No grant at either scope → 200 with empty list

| Field | Content |
|-------|---------|
| ID | S07-037 |
| Journey setup | Baseline B0, except Stage 4 entitled with `allowed_capabilities = ["clinic.visit_summary"]`. Entitle rejects `grants: []` with 400 `invalid_payload` (S04-040), so the payload carries a dummy unpublished-capability installation grant; both `clinic.visit_summary` grant lookups miss (installation miss → plan miss → skip). Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`. Entitlement alone does not advertise; both grant lookups miss → skip. |
| Side effects | D1 reads: standard set plus both grant queries (misses). No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L715-L749 — discover (grant gate)` |

## Scenario S07-038 — Lifecycle overlay marks the capability retired → excluded

| Field | Content |
|-------|---------|
| ID | S07-038 |
| Journey setup | Baseline B0, then the Stage 4/control-plane retire operation, which writes a global lifecycle row: `capability_grant` with `scope = 'global'`, `capability_id = 'clinic.visit_summary'`, `capability_version = '1.0.0'`, `lifecycle_state = 'retired'`, `retire_after` set (columns from migration `20260802100000`). Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body `{"manifests":[]}`. The overlay (`grants` key `global/clinic.visit_summary/1.0.0`) overrides the published `lifecycleState: "active"`; `effective.lifecycleState === "retired"` → excluded. Retired capabilities are never listed, even for installations still holding grants. |
| Side effects | D1 reads: standard set plus installation grant and the global lifecycle row. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L754-L758 — discover (retired exclusion)`; `ai-platform/src/capability/index.ts:L88-L116 — loadLifecycleOverlay`; `ai-platform/src/capability/index.ts:L63-L85 — effectiveLifecycle` |

## Scenario S07-039 — Lifecycle overlay marks the capability deprecated → listed as deprecated with successor

| Field | Content |
|-------|---------|
| ID | S07-039 |
| Journey setup | Baseline B0, then the control-plane deprecate operation: global lifecycle row `scope = 'global'`, `capability_id = 'clinic.visit_summary'`, `capability_version = '1.0.0'`, `lifecycle_state = 'deprecated'`, `successor_id = 'clinic.visit_summary'`, `deprecated_at = '2026-09-01T00:00:00.000Z'`. Fresh config cache. Pairwise arm: [SEED] `UPDATE capability_grant SET lifecycle_state = 'sunset' WHERE scope = 'global' AND capability_id = 'clinic.visit_summary' AND capability_version = '1.0.0'` on that successor overlay — justified: there is no control-plane sunset route; `lifecycle_state` has no CHECK constraint. Fresh config cache again. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` after deprecate, then the same GET after the sunset seed. |
| Expected outcome | HTTP `200`. After deprecate, the single manifest's `Identity.lifecycleState = "deprecated"` and `Identity.successorId = "clinic.visit_summary"` (overlay values win over the published `"active"`/`null`); all other projection fields unchanged. Deprecated remains listed through the OD-9 overlap window. After the sunset seed: HTTP `200`, body `{"manifests":[]}`, empty-list ETag — only `active` and `deprecated` pass the lifecycle filter; `lifecycle_state = 'sunset'` is excluded. |
| Side effects | D1 reads: standard set plus installation grant and global lifecycle row. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L760-L766 — discover (lifecycle filter)`; `ai-platform/src/capability/index.ts:L119-L138 — manifestWithEffectiveIdentity` |

## Scenario S07-040 — Active kill switch does not remove the capability from discovery

| Field | Content |
|-------|---------|
| ID | S07-040 |
| Journey setup | Baseline B0, then the real kill-switch arm: `POST /control/kill-switches/arm` with body `{"scope":"capability","target":"clinic.visit_summary"}` (C-17). Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` |
| Expected outcome | HTTP `200`, body lists `clinic.visit_summary` exactly as the happy path. `discover()` never loads `kill_switches` — advertising killed capabilities is intentional; the same token invoking the capability (Stage 8) would get `503 capability_disabled`. |
| Side effects | D1 reads: standard set plus grants. No `kill_switch` read from this request. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L690-L691 — discover (kill switches intentionally not applied)` |

## Scenario S07-041 — Discovery does not filter by staff role or token scopes

| Field | Content |
|-------|---------|
| ID | S07-041 |
| Journey setup | Baseline B0, but Stage 6 mints the AAT with `role = 'receptionist'` (not in the manifest's `Access.allowedStaffRoles = ["administrator","clinician","nurse"]`) and `scopes = []` (missing the manifest's `Access.requiredCapabilityScope = "ai.visit_summary"`). |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <that AAT>` |
| Expected outcome | HTTP `200`, body lists `clinic.visit_summary` exactly as the happy path. `discover()` evaluates entitlement status, plan tier, allowed capabilities, grants, and lifecycle only; `requiredCapabilityScope` and `allowedStaffRoles` are enforced by `assertPlanAllowance`, which runs on the invoke path (`resolve()`), not on discovery. A receptionist sees the capability here but would be refused at invoke with `403 forbidden_capability` (Stage 8). |
| Side effects | D1 reads: standard set plus grants. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L638-L782 — discover (no role/scope checks)`; contrast `ai-platform/src/capability/index.ts:L255-L272 — assertPlanAllowance (resolve-only scope/role gates)` |

## Scenario S07-042 — Entitled happy path: full public projection, ETag, Cache-Control

| Field | Content |
|-------|---------|
| ID | S07-042 |
| Journey setup | Baseline B0 exactly. Fresh config cache. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>`. No body, no other headers. |
| Expected outcome | HTTP `200`. Headers: `Content-Type: application/json`, `Cache-Control: private, must-revalidate`, `ETag: "<64-char lowercase hex>"` (quoted on the wire). Body has exactly one top-level key, `manifests`, an array of one object equal to the public projection of `clinic.visit_summary@1.0.0`: `Identity: {capabilityId: "clinic.visit_summary", version: "1.0.0", title: "Visit summary", lifecycleState: "active", successorId: null}`; `Interaction: {interactionMode: "single_shot"}`; `Input: {userIntentShape: "plain_text", priorTurnShape: null, sizeLimits: {maxChars: 8000}, allowedLanguages: ["en"]}`; `"Context requirements": [{key: "visit.chief_complaint@v1", required: true, shapeRef: "visit.chief_complaint@v1", maxSize: 4096}]`; `Output: {mode: "prose", outputSchemaRef: null}` (no `businessValidationRuleRefs`, no `repairPolicy`); `Governance: {acceptanceMode: "advisory_display"}` (no `retentionClass`, no `evalSuiteRef`). Absent groups: `Access`, `Prompt binding`, `Routing`, `Economics`; no top-level `interactionMode`. The ETag is the SHA-256 hex of the canonical JSON of `{manifests: [<public projection>]}` — computed over the projection only, so internal-field edits never change it. |
| Side effects | D1 reads: `installation`, `installation_key`, `token_contract`, `entitlement`, `capability_grant` (installation scope), `capability_grant` (global lifecycle overlay — miss is normal). All six rows cached in the isolate `ConfigCache` for 30 s. No writes to D1/DO/R2; `ai_request` count unchanged. |
| Code reference | `ai-platform/src/discovery/index.ts:L96-L117 — handleDiscoveryRequest (success path)`; `ai-platform/src/capability/index.ts:L638-L782 — discover`; `ai-platform/src/capability/index.ts:L467-L481 — toPublicManifest`; `ai-platform/src/capability/index.ts:L629-L635 — computeDiscoveryEtag`; `ai-platform/src/capability/index.ts:L869-L896 — buildDiscoveryResponse` |

## Scenario S07-043 — Conditional GET with matching If-None-Match → 304 empty body

| Field | Content |
|-------|---------|
| ID | S07-043 |
| Journey setup | S07-042 completed; capture its `ETag` response header as ETAG0 (e.g. `"9f2c…"`). |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>`, `If-None-Match: <ETAG0>` (the exact quoted value) |
| Expected outcome | HTTP `304`. Body empty (zero bytes — no JSON, no `manifests` key). Headers: `ETag: <ETAG0>` (same quoted value) and `Cache-Control: private, must-revalidate`; no `Content-Type` header. The handler still ran full auth + `discover()`; only the response body is elided. |
| Side effects | Same D1 reads as S07-042 (served from the warm isolate cache). No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L876-L886 — buildDiscoveryResponse (304 branch)`; `ai-platform/src/capability/index.ts:L852-L867 — ifNoneMatchMatches` |

## Scenario S07-044 — Conditional GET with weak validator W/"etag" → 304

| Field | Content |
|-------|---------|
| ID | S07-044 |
| Journey setup | S07-042 completed; ETAG0 captured. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>`, `If-None-Match: W/<ETAG0>` (weak-comparison prefix on the same quoted tag) |
| Expected outcome | HTTP `304`, empty body, `ETag: <ETAG0>`, `Cache-Control: private, must-revalidate`. `opaqueTagEquals` strips the optional `W/` prefix and surrounding quotes before comparing (RFC 7232 weak comparison). |
| Side effects | Same as S07-043. |
| Code reference | `ai-platform/src/capability/index.ts:L841-L850 — opaqueTagEquals` |

## Scenario S07-045 — Conditional GET with a list of tags, one matching → 304

| Field | Content |
|-------|---------|
| ID | S07-045 |
| Journey setup | S07-042 completed; ETAG0 captured. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>`, `If-None-Match: "stale-tag-from-older-poll", <ETAG0>` |
| Expected outcome | HTTP `304`, empty body, `ETag: <ETAG0>`. The header is split on commas; any one token matching the current raw etag suffices. |
| Side effects | Same as S07-043. |
| Code reference | `ai-platform/src/capability/index.ts:L852-L867 — ifNoneMatchMatches (list form)` |

## Scenario S07-046 — Conditional GET with If-None-Match: * → 304

| Field | Content |
|-------|---------|
| ID | S07-046 |
| Journey setup | S07-042 completed. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>`, `If-None-Match: *` |
| Expected outcome | HTTP `304`, empty body, current `ETag` and `Cache-Control` headers. The trimmed literal `*` matches unconditionally — including, pairwise, when the entitled list is empty (a `*` against the empty-list ETag also returns 304). |
| Side effects | Same as S07-043. |
| Code reference | `ai-platform/src/capability/index.ts:L856-L859 — ifNoneMatchMatches (star)` |

## Scenario S07-047 — Conditional GET with a stale (non-matching) tag → 200 full body

| Field | Content |
|-------|---------|
| ID | S07-047 |
| Journey setup | S07-042 completed. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>`, `If-None-Match: "stale-etag-not-current"` |
| Expected outcome | HTTP `200` with the full `{"manifests":[…]}` body, current `ETag`, `Cache-Control: private, must-revalidate`, `Content-Type: application/json`. A mismatch revalidates the whole list. |
| Side effects | Same reads as S07-042. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L888-L895 — buildDiscoveryResponse (200 branch)` |

## Scenario S07-048 — Malformed If-None-Match value → 200 full body

| Field | Content |
|-------|---------|
| ID | S07-048 |
| Journey setup | S07-042 completed. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer <AAT0>`, `If-None-Match: garbage%%%not-an-etag` |
| Expected outcome | HTTP `200` with the full body. There is no header-validation error path: an unparseable value is just an opaque token that never equals the raw etag, so it falls through to the 200 branch. (Pairwise variant: an empty `If-None-Match:` header value — trims to `""`, matches nothing, 200.) |
| Side effects | Same reads as S07-042. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L852-L867 — ifNoneMatchMatches (no match)`; `ai-platform/src/capability/index.ts:L888-L895 — buildDiscoveryResponse (200 branch)` |

## Scenario S07-049 — If-None-Match is never evaluated when auth fails → 401

| Field | Content |
|-------|---------|
| ID | S07-049 |
| Journey setup | S07-042 completed; ETAG0 captured. |
| Action | `GET /v1/capabilities`, `Authorization: Bearer not-a-valid-token`, `If-None-Match: <ETAG0>` |
| Expected outcome | HTTP `401` with the `unauthenticated` error body — never 304. Blocker order: `handleDiscoveryRequest` verifies the AAT before `buildDiscoveryResponse` (which owns the conditional logic) is reached. Error responses carry no `ETag`/`Cache-Control`. |
| Side effects | No D1 reads (token fails segment parsing). Guard-rejection tally (`unverified`). |
| Code reference | `ai-platform/src/discovery/index.ts:L42-L94 — handleDiscoveryRequest (auth before response build)` |

## Scenario S07-050 — ETag is content-derived, not installation-derived

| Field | Content |
|-------|---------|
| ID | S07-050 |
| Journey setup | Baseline B0, plus a second installation I1 (`7d4f1b83-2a6c-4e59-b8d1-3c9e0f5a2467`) taken through the same Stage 3/4 happy paths with identical plan (`professional`), `allowed_capabilities = ["clinic.visit_summary"]`, and an equivalent grant. Mint AAT1 for I1 (Stage 6). |
| Action | `GET /v1/capabilities` with `Authorization: Bearer <AAT0>`; then `GET /v1/capabilities` with `Authorization: Bearer <AAT1>` |
| Expected outcome | Both HTTP `200` with byte-identical bodies and **identical `ETag` values** — the hash input is `{manifests: […]}` only, with no installation, org, or principal field. Practical consequence: a 304 validator obtained under one installation is valid for any installation with the same entitled list. Pairwise: the empty-list ETag from S07-027/S07-028 is likewise identical across unentitled installations. |
| Side effects | Standard reads for both installations. No writes. |
| Code reference | `ai-platform/src/capability/index.ts:L629-L635 — computeDiscoveryEtag`; `ai-platform/src/capability/index.ts:L440-L442 — manifestToHashInput` |

## Scenario S07-051 — Grant revoked in D1 but isolate cache still warm → stale listing within TTL

| Field | Content |
|-------|---------|
| ID | S07-051 |
| Journey setup | S07-042 completed against a `handleDiscoveryRequest` invoked with an explicit `new ConfigCache(30000)` (the production default TTL), warming `entitlements`/`grants` for I0. Then revoke the installation grant directly in D1 (as in S07-033) **without** clearing the cache. |
| Action | Within 30 s of the warm-up: `GET /v1/capabilities`, `Authorization: Bearer <AAT0>` (same injected cache instance) |
| Expected outcome | HTTP `200`, body **still lists** `clinic.visit_summary` — the cached grant row is served until `now > expiresAt`. After TTL expiry (or isolate eviction), the same request returns `{"manifests":[]}`. This is the documented 30 s staleness window: discovery, `POST /v1/requests`, and `GET /v1/requests/{ref}` share `isolateConfigCache` in production. |
| Side effects | Second request performs no D1 reads for the cached kinds. No writes. |
| Code reference | `ai-platform/src/config-cache/index.ts:L89-L103 — ConfigCache.consult (TTL)`; `ai-platform/src/config-cache/index.ts:L153 — isolateConfigCache`; `ai-platform/src/config-cache/index.ts:L388-L413 — loadConfig`; `ai-platform/src/discovery/index.ts:L36-L40 — handleDiscoveryRequest (injectable cache)` |

## Scenario S07-052 — Entitle after a cached pending entitlement → still empty within TTL, listed after expiry

| Field | Content |
|-------|---------|
| ID | S07-052 |
| Journey setup | S07-028 state (entitlement `pending`, `allowed_capabilities = '[]'`) queried once with an explicit `new ConfigCache(30000)` so the pending row is cached. Then run the real Stage 4 entitle operation (D1 now has `status = 'active'`, `allowed_capabilities = ["clinic.visit_summary"]`, plus the installation grant). Do not clear the cache. |
| Action | (a) Immediately: `GET /v1/capabilities`, `Authorization: Bearer <AAT0>`. (b) After `cache.clear()`: repeat the identical request. |
| Expected outcome | (a) HTTP `200`, body `{"manifests":[]}` — entitle writes D1 and does not bust the isolate cache, so the stale pending entitlement still yields the empty list. (b) HTTP `200`, body lists `clinic.visit_summary` with a content ETag different from the empty-list ETag. |
| Side effects | (a) No D1 read for `entitlement` (cache hit). (b) Full read set repopulates the cache. No writes from discovery itself. |
| Code reference | `ai-platform/src/config-cache/index.ts:L89-L115 — ConfigCache.consult/remember`; `ai-platform/src/capability/index.ts:L668-L676 — discover (entitlement inactive)` |

---

## Doc-drift observations

1. **D1-reads table incomplete — fixed (D-22).** §1 now lists `keys`, `token_contracts`, installation/plan/global `grants` shapes, and notes which reads happen in verification vs `discover()`.
2. **Failure-paths section incomplete — fixed (D-22).** §2 documents both `401 unauthenticated` and `403 installation_suspended` (S07-023).
3. **Revocation semantics undocumented — fixed (D-22).** §3 documents the `revoked_at IS NULL` reader filter, plan-grant fallback after installation revocation (S07-034), and the unreachable `discover()` skip branch (A-08).
4. **TTL constant naming — fixed (D-22).** §1 names `DEFAULT_CONFIG_CACHE_TTL_MS` and notes `CACHE_TTL_MS` is deprecated.
5. **`Authorization: Bearer` probe classification — fixed (D-22).** §4 distinguishes bare `Bearer` (`invalid_authorization_scheme`) from whitespace-only token (`empty_bearer_token`).
6. **Role/scope non-filtering — fixed (D-22).** §4 states explicitly that discovery ignores `Access.allowedStaffRoles` and `Access.requiredCapabilityScope` (S07-041).
7. **ETag scope unstated — fixed (D-22).** §4 states the ETag hash input contains no per-installation field (S07-050).
8. **Consistent (no drift):** 304 semantics and header set (orientation doc §4.2), public-projection field list and absent internal groups (§4.1), POST → 404 (§6.3.2), kill switches not applied on discovery (§1, §6.3.8), `private, must-revalidate` on both 200 and 304, deprecated-listed/retired-never-listed (§4.1) — all match the code as written.

## Non-automatable notes

1. **Multi-isolate cache behavior.** The production sharing of `isolateConfigCache` across `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/requests/{ref}` (and its reset on isolate eviction) cannot be exercised under `@cloudflare/vitest-pool-workers`, which runs a single isolate. The single-isolate staleness window itself **is** automatable: `handleDiscoveryRequest` accepts an injectable `ConfigCache` (`discovery/index.ts:L39`), so tests construct `new ConfigCache(30_000)`, warm it, mutate D1, and re-request (S07-051, S07-052).
2. **Boot-time `CONFIG_CACHE_TTL_MS` wiring.** `configureIsolateConfigCache(resolveConfigCacheTtl_ms(...))` runs once at module load from wrangler `[vars]` (`worker.ts:L147-L149`); per-test variation of the isolate cache TTL is not possible through the worker entrypoint. Tests vary TTL on their own injected `ConfigCache` instead.
3. **Defensive branch: non-string `entitlement.plan`.** The `typeof plan !== "string"` empty-list branch in `discover()` (`capability/index.ts:L678-L687`) is unreachable through real D1 migrations — `entitlement.plan` is `TEXT NOT NULL` (`20260731120000_platform_schema.sql:L26`). Reaching it would require a stubbed `D1Reader`, which violates the production-faithful principle; recorded here for branch-coverage completeness only.
4. **Defensive branch: non-string registry `capabilityId`/`version`.** The `continue` guard in the discovery registry loop (`capability/index.ts:L696-L698`) is unreachable with the real registry — `createCapabilityRegistry` throws at install time unless both are strings (`capability/index.ts:L505-L510`). Not scenario-able without a hand-built invalid registry.
5. **Real wall-clock 30 s waits.** Waiting out the actual TTL in a test is possible but wasteful; the honest analogue is `cache.clear()` (the documented test seam, `config-cache/index.ts:L137-L144`) or a `new ConfigCache(0)`. Live 31 s waits remain a manual probe concern (doc §6.3.4/§6.3.7), not an automated-test one.
