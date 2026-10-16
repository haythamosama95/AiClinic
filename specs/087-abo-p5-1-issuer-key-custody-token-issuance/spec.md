# Feature Specification: Issuer key custody, token issuance and the versioned RPC envelope

**Feature Branch**: `ai/087-abo-p5-1-issuer-key-custody-token-issuance`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P5.1 — Issuer key custody, token issuance and the versioned RPC envelope

## 1. Unit Contract

**Implements** — Read: 01 §7 row R-3 (spike); 02 §3.1 (rows K-1, K-2, "Removed" paragraph); 02 §3.2; 04 §2.1; 04 §3.1 (intro; rows `issue_ai_token`, `issue_billing_token`; "Removed" paragraph, the enroll part); 03 §4 rows `issuer_key`, `ai_token_issuance`, `app_settings`, `installation_keys`; 04 §7.1 row RPCs + 04 §7.2 (constants bullet); 02 §6 row K-2.

- R-3 spike → Vault + SQL signing, or the Edge Function signer fallback (OQ-4).
- `ai_internal.issuer_key` (≥ 2 `kid`s, status, validity, `secret_ref`).
- `issue_ai_token(p_contract_version)` (EdDSA, `kid`, 04 §2.1 claims, `org = current_org_id()`, role from membership, scopes as today, ≤ 600 s).
- `issue_billing_token(p_contract_version)` (administrator only, 300 s, `{token, abo_base_url, expires_at}`, 20 per user per 10 min).
- Internal feed-token minting (used by P5.2).
- `ai_token_issuance` with `aud` + org and per-audience limits.
- `app_settings` keys incl. `ai.contract_versions` + a contract test against the package vectors.
- `rpc_result.contract_version`.
- `CONTRACT_VERSION_UNSUPPORTED`.
- Drop `installation_keys`, the single-installation trigger and the enroll/rotate/revoke RPCs + `auth_internal` bodies.
- Signing-`kid` switch procedure.
- **Builds H-FS** (local Supabase + `wrangler dev` platform and ABO + Paymob stub + Node runner + CI job).

**Freezes** — The unit row states no Outputs / freezes line.

**Consumes** — P1.2: the tenant inventory; per-tenant `roles_permissions`; cross-tenant suite (re-run by P7.2). P3.2: AI-token verification rules; `tenant_binding` model (epoch); issuer-key methods. P4.1: ABO clinic-API envelope, auth and error rules; records conventions; alert engine; H-ABO.

**Open questions relied on** — OQ-4: "P5.1 stops and escalates if the spike fails; the fallback is used only with the owner's approval."

**Spikes** — R-3 (01 §7, rule S6): spike Vault plus signing in SQL versus a single-purpose Edge Function signer that holds no `service_role`. Fallback, under the OQ-4 default: stop and escalate if the spike fails; the Edge Function signer is used only with the owner's approval.

## Clarifications

### Session 2026-10-07

- Q: Where do the new issuer objects, the issue RPC bodies, and the feed mint live? → A: One new migration under `backend/supabase/migrations/` with a fresh timestamp. Do not edit `20260801120000_ai_keystore_schema.sql` or `20260905120300_fix_aat_lifetime_fallback.sql`. `issue_ai_token` and `issue_billing_token` stay `SECURITY DEFINER` in `public` and delegate to `auth_internal`. The feed mint is an `auth_internal` definer with no public grant and no `p_contract_version`. The plan names that function in Files. Inserting a `next` kid uses the same `auth_internal` privilege, not a new public RPC. `[implementation choice — no §citation]`
- Q: How does the H-FS runner complete E2E-P5.1-06 and start the stack? → A: Clinic calls stay supabase-js. Inserting the next kid and calling `auth_internal.switch_issuer_signing_kid` use a direct Postgres connection as the database owner, after the public key is pinned and registered. `registerIssuerKey` is the consumed HP method: a harness-only worker in `e2e/fullstack/` holds the service binding to `VendorEntrypoint`, and the assertion comes from `packages/vendor-contracts`. No product HTTP route. `ISSUER_KEYS` is the local ABO wrangler config; the runner restarts ABO `wrangler dev` after the pin. The Paymob process is the existing `abo/test/stubs/paymob/` stub, not a second stub. The test does not sleep 10 minutes and does not call `retireIssuerKey`. The V7 full-stack job runs `e2e/fullstack/`; these scenarios are not part of the backend SQL job. `[implementation choice — no §citation]`
- Q: How do the contract test and the feed mint get asserted without a new E2E id? → A: E2E-P5.1-09 reads `packages/vendor-contracts/src/version.ts` at run time and passes those values into psql. The committed test does not copy the constants. E2E-P5.1-07, still H-BK, also mints one feed token as the database owner and checks `aud`, `sub`, absent `org`, and lifetime at most 120 seconds, and checks that a clinic role cannot call the mint or `switch_issuer_signing_kid`. It does not call the platform feed. No new E2E id. `[implementation choice — no §citation]`
- Q: How does E2E-P5.1-06's `registerIssuerKey` succeed on local `wrangler dev` when Access certs are fetched from `https://${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs` and a new operator credential stays `pending` for 24 hours? → A: The H-FS runner starts the platform with wrangler's programmatic local worker (`startWorker`), the same local workerd as `wrangler dev`, and passes `dev.mockFetch` so only that certs GET is answered. The certs document and the Access JWT come from `packages/vendor-contracts` testkit `createAccessTeam`, with wall-clock `iat` and `exp`. The signer is not created by `registerOperatorCredential`. The runner inserts one `operator_credential` row in the local platform D1 with `status = 'active'`, `activates_at` at or before wall-clock now, and `operator_email`, `alg`, and `public_key_cose` matching the Access JWT email and the key that signs the assertion. `issued_at` is wall-clock now. `TEST_CLOCK` is not set on any wrangler env. Platform source and the 24-hour pending insert stay as they are. The ABO process stays CLI `wrangler dev`. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1)

The shared backend holds the issuer key set (K-2): Ed25519, at least two `kid`s, each valid for 13 months, overlapping. Private key material is a Vault reference (`secret_ref`), reached only through definer RPCs in the non-exposed `ai_internal` schema. A clinic member cannot read it, and no plaintext key column remains. The operator generates the next `kid`, pins its public key in the ABO `ISSUER_KEYS` configuration, registers it on the platform, and switches signing once both accept it. This unit builds the full-stack harness those checks run in.

**Why this priority**: AI tokens, billing tokens, and the later feed mint are signed by this key set. The token stories depend on custody, on the signing `kid`, and on the harness.

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** a clinic role and the issuer-key store, **When** that role tries to read private key material, **Then** the read is denied and no plaintext key column remains. (E2E-P5.1-07) [T-4]
2. **Given** a new signing `kid` registered on the platform and pinned in the ABO, **When** signing switches to that `kid`, **Then** new tokens are accepted everywhere, old tokens stay valid until expiry, and the binding is unchanged. (E2E-P5.1-06) [A13, A25]

### 2.2 User Story 2 - AI token for the active organisation (Priority: P2)

A clinic member with an AI scope calls `issue_ai_token(1)`. The token is a compact JWS, `alg = EdDSA`, header `kid` and `typ = JWT`, `ver = "2"`, audience `ai-platform`, lifetime at most 600 seconds. `org` is `current_org_id()`. The local platform accepts it on `GET /v1/capabilities`, and that first valid token creates org A's binding. After the member's active organisation is org B, a new token's `org` is B. A billing token presented to the platform, and this AI token presented to the ABO, are each rejected with 401.

**Why this priority**: Clinic AI calls need an issuer token whose organisation is the session's active organisation. Audience separation depends on the `aud` this mint writes.

**Independent Test**: E2E-P5.1-01 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** an org A member, **When** they call `issue_ai_token(1)`, **Then** the local platform accepts the token on `/v1/capabilities` and A's binding is created. (E2E-P5.1-01)
2. **Given** the member's active organisation is switched to org B, **When** they call `issue_ai_token`, **Then** the token `org` is B. (E2E-P5.1-08) [SR-03]
3. **Given** a billing token and an AI token, **When** the billing token is presented to the platform and the AI token is presented to the ABO, **Then** each service responds 401. (E2E-P5.1-03) [02 §3.2 audience separation]

### 2.3 User Story 3 - Administrator billing token (Priority: P3)

An administrator calls `issue_billing_token(1)` and receives `{token, abo_base_url, expires_at}`. The token audience is `abo`, the lifetime is at most 300 seconds, and `role` is `administrator`. The local ABO accepts it on `GET /v1/offers`. A doctor receives `FORBIDDEN_ROLE`. The 21st billing token for that user inside 10 minutes receives `RATE_LIMITED`.

**Why this priority**: Billing calls need a short-lived administrator token. Staff must not mint one. The mint limit is per audience, so this story stands on the issue RPC alone.

**Independent Test**: E2E-P5.1-02 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** an administrator, **When** they call `issue_billing_token(1)`, **Then** the local ABO accepts the token on `/v1/offers` and `rpc_result.contract_version` is 1, the version the request used. **Given** a doctor, **When** they call `issue_billing_token`, **Then** the result is `FORBIDDEN_ROLE`. (E2E-P5.1-02, 04 §7.2, 06 §3 V5) [FR-10, AD-2]
2. **Given** a user who has received 20 billing tokens in 10 minutes, **When** they request the 21st, **Then** the result is `RATE_LIMITED`. (E2E-P5.1-05)

### 2.4 User Story 4 - RPC contract version (Priority: P4)

The desktop passes `p_contract_version` to the issue RPCs. At launch the backend RPC channel version is 1. Version 1 is accepted. `issue_billing_token` returns `rpc_result` extended with `contract_version`. `issue_ai_token` still returns the token text; the token `ver` claim states its version. Version 2 causes `issue_ai_token` to raise `CONTRACT_VERSION_UNSUPPORTED`. A missing version, or a version outside N and N−1, receives that same refusal with `accepted_versions`, before authentication and before any write. `ai.contract_versions` equals the package constants.

**Why this priority**: The issue RPCs in the earlier stories are the callers of this check. The refusal path is independently testable on the RPC.

**Independent Test**: E2E-P5.1-09 in harness H-BK. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** `issue_ai_token` called with version 2, **When** the RPC runs, **Then** it raises `CONTRACT_VERSION_UNSUPPORTED`. Every RPC result carries `contract_version`. A missing version, or a version outside N and N−1, receives that refusal with `accepted_versions` before authentication and before any write, and nothing is written. (E2E-P5.1-04, 04 §7.1 row RPCs, 04 §7.2, 06 §3 V5)
2. **Given** `ai.contract_versions` and the package constants, **When** the contract test compares them, **Then** they are equal. (E2E-P5.1-09)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P5.1-01 | H-FS | H-FS Node runner (`e2e/fullstack/`, supabase-js) calls PostgREST `public.issue_ai_token(1)`, then `GET /v1/capabilities` on the platform worker (`ai-platform/src/worker.ts`) | Org A member: `issue_ai_token(1)` → accepted by the local platform `/v1/capabilities`; A's binding created. | FR-004 | User Story 2 |
| E2E-P5.1-02 | H-FS | H-FS Node runner calls PostgREST `public.issue_billing_token(1)`, then `GET /v1/offers` on the ABO worker (`abo/src/worker.ts`). The doctor call is the same RPC. | Administrator: `issue_billing_token(1)` → accepted by the local ABO `/v1/offers`, and `rpc_result.contract_version` is 1 (echoed). Doctor → `FORBIDDEN_ROLE`. [FR-10, AD-2] | FR-005, FR-009 | User Story 3 |
| E2E-P5.1-03 | H-FS | H-FS Node runner presents the billing token to platform `GET /v1/capabilities` and the AI token to ABO `GET /v1/offers` | Billing token at the platform → 401; AI token at the ABO → 401. [02 §3.2 audience separation] | FR-006 | User Story 2 |
| E2E-P5.1-04 | H-BK | psql / PostgREST `public.issue_ai_token` with version 2, and with `p_contract_version` omitted; `public.issue_billing_token` result row | Version 2 → `CONTRACT_VERSION_UNSUPPORTED` (raised by `issue_ai_token`); every RPC result carries `contract_version`. A missing version gets the same refusal with `accepted_versions`, before authentication and before any write. | FR-009 | User Story 4 |
| E2E-P5.1-05 | H-BK | psql / PostgREST `public.issue_billing_token` repeated for one user | 21st billing token in 10 min → `RATE_LIMITED`. | FR-005, FR-007 | User Story 3 |
| E2E-P5.1-06 | H-FS | H-FS runner: platform `startWorker` with `dev.mockFetch` on the Access certs URL only; local platform D1 signer row already `active`; consumed `VendorEntrypoint.registerIssuerKey`; ABO `ISSUER_KEYS` pin; then `public.issue_ai_token` / `public.issue_billing_token` and `GET /v1/capabilities` plus `GET /v1/offers` for the new and the still-unexpired tokens | A13/A25: new signing `kid` registered on the platform and pinned in the ABO → new tokens accepted everywhere; old tokens valid until expiry; binding unchanged. | FR-010 | User Story 1 |
| E2E-P5.1-07 | H-BK | psql as a clinic role against `ai_internal` issuer-key storage, and a catalog check that no plaintext private-key column remains (`backend/tests/`, including `ai_keystore_rls.sql`) | No clinic role can read private key material; no plaintext key column remains. [T-4] | FR-002, FR-003 | User Story 1 |
| E2E-P5.1-08 | H-BK | PostgREST `public.set_active_organization` then `public.issue_ai_token` | Membership switched to org B → token `org` = B. [SR-03] | FR-004 | User Story 2 |
| E2E-P5.1-09 | H-BK | psql contract test of `ai_internal.app_settings` key `ai.contract_versions` against `packages/vendor-contracts` constants (`src/version.ts`) | `ai.contract_versions` equals the package constants (contract test). | FR-008 | User Story 4 |

### 2.6 Edge Cases

- A clinic role cannot read private key material. `issuer_key` stores `secret_ref`, not a plaintext private key. `installation_keys` and its plaintext `secret_key` are gone. (E2E-P5.1-07, 03 §4, 02 §3.1 Removed) [T-4]
- After the signing `kid` switches, new tokens are accepted on the platform and the ABO, old tokens stay valid until expiry, and the tenant binding is unchanged. (E2E-P5.1-06, 02 §6 row K-2) [A13, A25]
- A billing token at the platform and an AI token at the ABO each receive 401. (E2E-P5.1-03, 02 §3.2)
- A doctor calling `issue_billing_token` receives `FORBIDDEN_ROLE`. (E2E-P5.1-02, 04 §3.1) [FR-10, AD-2]
- The 21st billing token for one user inside 10 minutes receives `RATE_LIMITED`. The limit applies per audience. (E2E-P5.1-05, 04 §3.1, 03 §4)
- Membership switched to org B yields a token whose `org` is B, taken from `current_org_id()`. (E2E-P5.1-08, 04 §2.1) [SR-03]
- Version 2 on `issue_ai_token` raises `CONTRACT_VERSION_UNSUPPORTED`. A missing version, or a version outside N and N−1, receives that refusal with `accepted_versions`. The check runs before authentication and before any write. At launch N is 1. Every `rpc_result` carries `contract_version`. (E2E-P5.1-04, 04 §3.1, 04 §7.1, 04 §7.2, 06 §3 V5)
- The feed token is minted inside the backend for the later pull: audience `ai-platform-feed`, `sub = backend-feed`, `org` absent, lifetime at most 120 seconds. This unit does not run the pull. (02 §3.2, 04 §2.1, Implements)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The R-3 spike implements issuer signing as Vault plus signing in SQL. If that spike fails, P5.1 stops and escalates. The single-purpose Edge Function signer, which holds no `service_role`, is used only with the owner's approval. (01 §7 row R-3, 06 §6 OQ-4, Implements)
- **FR-002**: `ai_internal.issuer_key` is new in the non-exposed `ai_internal` schema and is reached only through definer RPCs. Fields are `kid`, `public_key`, `secret_ref` (Vault id, or signer reference per R-3), `status`, `not_before`, and `not_after`. The issuer key set is Ed25519 with at least two `kid`s, 13 months per key, overlapping. No clinic role can read private key material, and no plaintext key column remains. (03 §4, 02 §3.1 row K-2, E2E-P5.1-07) [T-4]
- **FR-003**: `ai_internal.installation_keys` and its single-installation trigger are dropped. `enroll_installation_keypair`, `rotate_installation_key`, and `revoke_installation_key`, and their `auth_internal` bodies, are dropped. (03 §4 row `installation_keys`, 04 §3.1 Removed paragraph, 02 §3.1 Removed paragraph)
- **FR-004**: `issue_ai_token(p_contract_version)` is a `SECURITY DEFINER` RPC in `public`, delegating to `auth_internal`, for members with an AI scope. It returns the AI token as `text`, the same return shape as today, plus the version argument. The unversioned signature is dropped. The token header is `{alg: EdDSA, kid, typ: JWT}`. Claims follow 04 §2.1: `iss` is the backend issuer id from `ai.issuer_id`; `ver = "2"`; `aud = ai-platform`; `sub` is the staff member id; `org` is `current_org_id()` and is never taken from an argument; `role` is the membership role; `branch` is the current branch; `scopes` are the granted `ai.*` permission keys for that role, as today (`20260905120300_fix_aat_lifetime_fallback.sql:115-124`); `exp − iat` is at most 600 seconds; `jti` is a UUID. A member whose active organisation is switched to org B receives a token whose `org` is B. (04 §2.1, 04 §3.1 row `issue_ai_token`, 02 §3.2 AI row, E2E-P5.1-01, E2E-P5.1-08)
- **FR-005**: `issue_billing_token(p_contract_version)` is a `SECURITY DEFINER` RPC in `public` for membership role `administrator` only. It returns `{token, abo_base_url, expires_at}` in `rpc_result`. The billing token uses the 04 §2.1 billing column: `aud = abo`, `role = administrator`, `org` from `current_org_id()`, `branch` the current branch, no `scopes`, lifetime at most 300 seconds. `abo_base_url` comes from `ai.abo_base_url`. A doctor receives `FORBIDDEN_ROLE`. The 21st billing token for one user in 10 minutes receives `RATE_LIMITED` (20 per user per 10 minutes). (04 §3.1 row `issue_billing_token`, 04 §2.1, 02 §3.2 Billing row, E2E-P5.1-02, E2E-P5.1-05)
- **FR-006**: Minted audiences stay separated. An AI token has `aud = ai-platform`. A billing token has `aud = abo`. A billing token presented to the local platform receives 401. An AI token presented to the local ABO receives 401. Verifier rules stay the consumed P3.2 and P4.1 contracts. (02 §3.2, E2E-P5.1-03)
- **FR-007**: `ai_internal.ai_token_issuance` gains `aud` and `organization_id`. The rate limit applies per audience. (03 §4 row `ai_token_issuance`, Implements, E2E-P5.1-05)
- **FR-008**: `ai_internal.app_settings` gains `ai.platform_base_url`, `ai.abo_base_url`, `ai.issuer_id`, and `ai.contract_versions`. `ai.contract_versions` is the current and minimum version per channel the backend sends or accepts. A contract test fails if that copy differs from the `packages/vendor-contracts` constants. (03 §4 row `app_settings`, 04 §7.2 constants bullet, E2E-P5.1-09)
- **FR-009**: The issue RPCs take `p_contract_version integer` as the first argument. `rpc_result` is extended with `contract_version`. `issue_ai_token` keeps returning `text`; the token `ver` claim states its version. The backend RPC channel accepts current N and previous N−1 and answers in the version the request used. At launch N is 1. A missing version, or a version outside N and N−1, including version 2, is `CONTRACT_VERSION_UNSUPPORTED` with `accepted_versions`. `issue_ai_token` raises that error. The check runs before authentication and before any write, so nothing changes. Every `rpc_result` carries `contract_version`. (04 §3.1 intro, 04 §7.1 row RPCs, 04 §7.2, 06 §3 V5, E2E-P5.1-04)
- **FR-010**: The signing-`kid` switch follows 02 §6 row K-2. Generate the next `kid`; add its public key to the ABO's pinned `ISSUER_KEYS` (config deploy) and register it on the platform (HP, consumed issuer-key method); switch signing once both accept it. After 10 minutes (the longest token life) `retireIssuerKey` (HP) sets the old `kid` to `retiring`, and that `kid` stays accepted until `not_after`. New tokens are then accepted on the platform and the ABO; old tokens stay valid until expiry; the binding is unchanged. (02 §6 row K-2, E2E-P5.1-06)
- **FR-011**: The backend mints the feed token with K-2 for the pull job P5.2 runs. Header and `ver = "2"` match the other tokens. `aud = ai-platform-feed`, `sub = backend-feed`, `org` is absent, `role` and `branch` and `scopes` are absent, and `exp − iat` is at most 120 seconds. `jti` is a UUID. (02 §3.2 Feed row, 04 §2.1 Feed column, Implements)
- **FR-012**: This unit builds harness H-FS: `supabase start`, local workerd for the platform and the ABO, the Paymob stub server, and a Node scenario runner in top-level `e2e/fullstack/` with its own `package.json` and a `file:` dependency on `packages/vendor-contracts`. The ABO process is CLI `wrangler dev`. The platform process is wrangler's programmatic local worker (`startWorker`), the same local workerd as `wrangler dev`, with `dev.mockFetch` answering only `GET https://${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`. E2E-P5.1-06 inserts its signer into that local platform D1 as `status = 'active'` with `activates_at` at or before wall-clock now, and does not set `TEST_CLOCK`. The runner uses supabase-js as real test users. A full-stack CI job runs that harness. (06 §3 V1 row H-FS, 06 §3 V7, Implements, rule S3 wiring exception)

### 3.2 Key Entities

- **`ai_internal.issuer_key`**: Issuer public key, `secret_ref`, `status`, and validity window. At least two `kid`s.
- **`ai_internal.ai_token_issuance`**: Issuance record extended with `aud` and `organization_id`. Rate limit is per audience.
- **`ai_internal.app_settings`**: Gains `ai.platform_base_url`, `ai.abo_base_url`, `ai.issuer_id`, and `ai.contract_versions`.
- **`public.rpc_result`**: Existing envelope extended with `contract_version`.
- **`installation_keys`**: Dropped, with the single-installation trigger and the enroll, rotate, and revoke RPCs.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: backend (+ `e2e/fullstack/` harness). Wiring exception (rule S3): the full-stack harness. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic member mints an AI token for the active organisation. An administrator mints a short-lived billing token for that same organisation. The issuer key set is shared custody for those clinic tokens, with overlapping `kid`s so rotation does not cut off a clinic session.
- **Layer Placement**: Key custody, token claims, rate limits, and the version check live in PostgreSQL, reached through Supabase RPCs. The Flutter app is outside this unit. The platform and the ABO stay consumed verifiers. The H-FS runner is the named harness, not a second product service.
- **Data Integrity & Security**: Issuer records stay in non-exposed `ai_internal` and are reached only through `SECURITY DEFINER` RPCs. `org` comes from `current_org_id()`. Billing mint requires membership role `administrator`. Private key material is `secret_ref` only. Clinic roles cannot read it. The version check runs before authentication and before any write. Issuance is recorded with `aud` and organisation. (03 §4, 04 §2.1, 04 §3.1, 04 §7.2)
- **Failure Handling**: A doctor receives `FORBIDDEN_ROLE`. The 21st billing token in 10 minutes receives `RATE_LIMITED`. A missing or unsupported RPC version receives `CONTRACT_VERSION_UNSUPPORTED` before any write. A token presented to the wrong service receives 401 from that service. If Vault plus SQL signing fails the spike, the unit stops and escalates. (04 §3.1, 02 §3.2, 04 §7.2, 06 §6 OQ-4)

## 5. Out of Scope

- Feed puller, projection, status RPCs, availability flag (→ P5.2).
- No Do-not-read material. The unit row names none.
- No rewrite of the consumed contracts: P1.2 tenant inventory, per-tenant `roles_permissions`, and cross-tenant suite; P3.2 AI-token verification, `tenant_binding` (epoch), and issuer-key methods; P4.1 ABO clinic-API envelope, auth and error rules, records conventions, alert engine, and H-ABO.
- No module this unit's E2E scenarios do not reach (rule S8). The P2.2 and package-half P2.1 exception does not apply. The feed mint is the K-2 issuance path in FR-011; the pull job that calls it belongs to P5.2.
- No S9 path owned by a later unit. `ai.availability` and the availability RPCs stay until P5.2. Platform `/control/*` removal stays with its owning unit.
- No second codebase beyond backend and the `e2e/fullstack/` harness named in the Codebase cell.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P5.1-01 through E2E-P5.1-09 are green in the harness named for each row in the test plan.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-4 default: P5.1 stops and escalates if the Vault plus SQL signing spike fails; the Edge Function signer fallback is used only with the owner's approval.
- Rule S9: the availability flag and the availability RPCs remain until P5.2, which also owns the feed puller, the coverage projection, and the status RPCs. This unit drops installation keys and the enroll, rotate, and revoke RPCs, which P5.1 owns.
