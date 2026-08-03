# Feature Specification: Installation keystore and AAT issuer

**Feature Branch**: `021-b1-installation-keystore-aat-issuer`

**Created**: 2026-07-31

**Status**: Draft

**Input**: Slice `B1` — "Installation keystore and AAT issuer" (delivery plan §3.3, row B1).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Verbatim from the `Canonical` cell of slice B1 (delivery plan §3.3):

- `§4.2`
- `§8.1`
- `§5.6`

### Freezes

This slice establishes the following contracts for the first time. Later slices may
extend them and may not rewrite them (delivery plan §2.3):

- The **installation keystore** shape: the installation id and its private signing key
  held in a restricted schema, readable only by the token-issuing function (§4.2 table
  row "Installation keystore"; §8.1 step "generate installation keypair / store private
  key in restricted schema").
- The **AAT issuer RPC** contract: it verifies the caller's session, derives tenant /
  actor / AI-capability scope claims from RBAC, mints a short-lived signed AAT, records
  issuance, and is itself rate-limited (§4.2 table row "AI token issuer RPC").
- The **token claim set** in the §5.6 table (`iss`, `aud`, `sub`, `org`, `branch`,
  `role`, `scopes`, `jti`, `iat`, `exp`, `ver`), including the deliberate omissions
  (no patient identifiers, no quota state, no provider/model hints) (§5.6).
- The rule that `scopes` are **derived server-side from RBAC and never
  client-supplied** (§5.6 `scopes` row; §4.2 "resolve tenant/actor claims and AI
  capability scopes from the RBAC tables").

### Consumes

B1 has **no prerequisite slices** (`Needs` cell is empty in delivery plan §3.3). The
B1 row's `Done when` and the §3.11.2 row do not assert any dependence on a contract
frozen by another AI-platform slice.

This slice relies on an **external** dependency recorded in delivery plan §7: "Supabase
RBAC tables stable enough to derive AI capability scopes" blocks B1, because `scopes`
are derived server-side from RBAC and never supplied by the client. That table set is
part of the existing clinic backend, not a frozen AI-platform contract, so it is not a
`Consumes` entry under the §2.3 no-rework rule.

### Open decisions relied on

None. No §15 recommended default is needed to satisfy the B1 `Done when` cell. Token
lifetime ("minutes") and issuer rate limiting are named directly in §5.6 and §4.2, not
deferred to §15.

## Clarifications

### Session 2026-07-31

- Q: What asymmetric signing algorithm should the installation keypair use for AATs? → A: ES256 (ECDSA P-256, JWKS `EC` key) `[implementation choice — no §citation]`
- Q: Where should the installation keystore and issuer RPC live inside the Supabase layout? → A: Keystore in a new `ai_internal` schema; issuer RPC in `auth_internal` as `SECURITY DEFINER` `[implementation choice — no §citation]`
- Q: How should the T05/T06 SQL/RLS tests produce and verify an AAT? → A: SQL/RLS-only — PL/pgSQL verifier function in `auth_internal` + SQL-generated ES256 fixtures, minting via the real issuer RPC `[implementation choice — no §citation]`

> **Architecture override:** §4.2.1 later fixed `pgsodium` Ed25519 / `alg: EdDSA`. Plan and
> implementation follow EdDSA, not the ES256 clarification bullets above.

### Session 2026-08-03 (B1 review resolution)

- Q: How does the operator obtain the public key for §8.1 platform enroll? → A: `enroll` /
  `rotate` `rpc_success` data includes `public_jwk` (`{kty:"OKP",crv:"Ed25519",x,kid}`) plus
  `kid` and `installation_id`.
- Q: How is the issuer rate limit serialized? → A: `pg_advisory_xact_lock` per actor before
  count+insert.
- Q: How is the current signing key chosen? → A: Scoped to the clinic singleton
  `installation_id` (`enforce_single_installation` trigger); `ORDER BY valid_from DESC, kid DESC`;
  inserts use `clock_timestamp()`.
- Q: Does clinic `verify_aat` check `exp`? → A: No — returns `false` on malformed input / `iss`
  mismatch; expiry is B3. T05 means previous key still verifies after additive rotation.
- Q: What error convention does the issuer use? → A: Bare `RAISE EXCEPTION '<CODE>'` (codes in
  `contracts/aat-token.md` §9); keypair routines keep `rpc_result`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Installation keystore and AAT issuer (Priority: P1)

An operator enrols a clinic installation once; the clinic's Supabase stores the
installation id and a private signing key in a restricted schema, and an RPC mints a
short-lived, audience-scoped AI Access Token (AAT) for an authenticated staff member by
deriving every claim in §5.6 from the session and the RBAC tables, recording the
issuance, and rate-limiting itself. Later, an operator may rotate the signing key
without invalidating AATs already in flight, and may revoke a key.

**Why this priority**: B1 has no prerequisite slices (`Needs` cell empty), so it sits at
the head of band B's trust bootstrap. The platform "cannot validate a clinic's Supabase
JWT without per-clinic trust material" (§2.1/F2 background); the keystore and issuer are
what first establish that the clinic — not the platform — vouches for a clinician's
identity. Every later identity, entitlement, and admission slice (B3, B4) consumes the
AAT this slice mints, so the token contract must be frozen early (delivery plan DP-2,
DP-4).

**Independent Test**: An automated SQL/RLS test suite asserts the keystore is unreadable
by `anon` and `authenticated`, that enroll/rotate return `public_jwk`, that rotation is
additive, that a previously-signed token still verifies after rotation (clinic
`verify_aat` does not check `exp`), that a revoked key is rejected, that malformed /
`iss`-mismatched tokens return `false`, and that the issuer RPC populates every §5.6
claim (header `alg`/`kid`, claim correctness, deliberate omissions), derives `scopes`
from RBAC independent of any caller-supplied value, rejects with exact error codes for
absent/expired session and other gates, records an issuance row, and trips its
per-actor rate limit under an advisory lock. No deployment or demo is required
(delivery plan DP-1, DP-3).

**Acceptance Scenarios**:

*Keystore*

1. **Given** the installation keystore exists in a restricted schema, **When** a session
   using the `anon` role attempts to read it, **Then** the read is denied.
2. **Given** the installation keystore exists in a restricted schema, **When** a session
   using the `authenticated` role attempts to read it, **Then** the read is denied.
3. **Given** the installation keystore exists, **When** an administrator enrolls via the
   keypair RPC, **Then** the `SECURITY DEFINER` path reaches the keystore and
   `rpc_success` data includes `kid`, `installation_id`, and `public_jwk`
   (`kty`/`crv`/`x`/`kid`).
4. **Given** an installation has a current signing key, **When** rotation adds a new key,
   **Then** the previous key remains present and is not removed, and rotate returns
   `public_jwk` for the new key.
5. **Given** rotation has added a new key while an AAT signed by the previous key remains
   unrevoked, **When** that AAT is verified with clinic `verify_aat`, **Then** it still
   verifies (expiry is enforced by B3, not the clinic self-test).
6. **Given** a signing key has been revoked, **When** an AAT signed by that revoked key
   is verified, **Then** it is rejected (`false`).
6a. **Given** a token with a malformed signature segment or a payload `iss` that does not
    match the key row's `installation_id`, **When** `verify_aat` runs, **Then** it returns
    `false` without throwing.
6b. **Given** a non-administrator session, **When** enroll / rotate / revoke is called,
    **Then** the call is rejected with `FORBIDDEN`.

*Issuer*

7. **Given** an authenticated, valid staff session, **When** the issuer RPC runs, **Then**
   every claim listed in the §5.6 table is populated (`iss`, `aud`, `sub`, `org`,
   `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`) with correct sources, the JWS
   header has `alg: EdDSA` and a non-null `kid`, and deliberate omissions are absent.
8. **Given** a caller attempts to supply `scopes` to the issuer RPC, **When** the RPC
   mints the AAT, **Then** `scopes` are derived from the RBAC tables and the
   caller-supplied value has no effect on the issued token.
9. **Given** the caller's session is absent or expired, **When** the issuer RPC is
   invoked, **Then** it raises `UNAUTHENTICATED` or `SESSION_EXPIRED` respectively.
10. **Given** a successful issuance, **When** the RPC completes, **Then** an issuance row
    is written.
11. **Given** the issuer RPC is called within its rate-limit window beyond the allowed
    count for one actor, **When** a further call is attempted, **Then** it raises
    `RATE_LIMITED`; a different actor can still mint.
12. **Given** a successful issuance, **When** the `exp` claim is inspected, **Then** it is
    within the configured number of minutes of `iat`.
13. **Given** issuer preconditions fail (no staff, no branch, not enrolled, no `ai.*`
    grants), **When** the issuer runs, **Then** it raises the matching bare code
    (`STAFF_NOT_FOUND`, `BRANCH_NOT_FOUND`, `INSTALLATION_NOT_ENROLLED`,
    `AI_ACCESS_DENIED`).

### Test plan

The layer for every case below is **SQL / RLS**, as named in the slice's row in delivery
plan §3.11.2. Coverage follows delivery plan §3.10 (behavioural, including every error
path and every inherited prohibition the slice can emit).

Named tests (numbering is per suite):

*Keystore suite* (`ai_keystore_rls.sql` — T01–T10):

- `T01 keystore anon read denied` — layer: SQL / RLS
- `T02 keystore authenticated read denied` — layer: SQL / RLS
- `T03 enroll returns public_jwk and reaches keystore` — layer: SQL / RLS
- `T04 rotation adds key without removing previous; rotate returns public_jwk` — layer: SQL / RLS
- `T05 previous-key AAT still verifies after additive rotation` (clinic `verify_aat` does **not** check `exp`; expiry is B3) — layer: SQL / RLS
- `T05b post-rotation mint header kid equals rotate result kid` — layer: SQL / RLS
- `T05c verify_aat malformed signature returns false (no throw)` — layer: SQL / RLS
- `T05d verify_aat iss mismatch returns false` — layer: SQL / RLS
- `T06 revoked key rejected` — layer: SQL / RLS
- `T07 non-admin FORBIDDEN on enroll/rotate/revoke` — layer: SQL / RLS
- `T08 revoke empty kid → INVALID_INPUT` — layer: SQL / RLS
- `T09 revoke unknown kid → KEY_NOT_FOUND` — layer: SQL / RLS
- `T10 rotate before enroll → INSTALLATION_NOT_ENROLLED` — layer: SQL / RLS

*Issuer suite* (`ai_token_issuer.sql` — T07–T16):

- `T07 all section 5.6 claims populated` (correct `aud`/`sub`/`iss`, unique `jti`, RBAC scopes equality) — layer: SQL / RLS
- `T07b header alg EdDSA and kid present` — layer: SQL / RLS
- `T08 scopes derived from RBAC and unaffected by caller-supplied scopes` — layer: SQL / RLS
- `T08b deliberate omissions absent from payload` — layer: SQL / RLS
- `T09 expired or absent session rejected` (`UNAUTHENTICATED` / `SESSION_EXPIRED`) — layer: SQL / RLS
- `T10 issuance row written` — layer: SQL / RLS
- `T11 issuer rate limit trips` (exact `RATE_LIMITED`; other actor still mints; advisory lock) — layer: SQL / RLS
- `T12 exp within configured minutes` — layer: SQL / RLS
- `T13 STAFF_NOT_FOUND` — layer: SQL / RLS
- `T14 BRANCH_NOT_FOUND` — layer: SQL / RLS
- `T15 INSTALLATION_NOT_ENROLLED` — layer: SQL / RLS
- `T16 AI_ACCESS_DENIED` — layer: SQL / RLS

Suites restore settings / `ROLLBACK` where applicable so mutated config and fixture rows do not
leak across runs.

### Edge Cases

- **Keystore access boundary**: the only role that may read the private signing key is
  the token-issuing function; `anon` and `authenticated` are denied (§4.2 "Installation
  keystore" row). Any other role that could read the key would break the trust model.
- **Rotation boundary**: rotation is additive — it adds a key without removing the
  previous one, so AATs signed under the previous key continue to verify at the clinic
  self-test while unrevoked (§4.2 notes "Rotation is a supported operation"; B1
  `Done when` cell). Clinic `verify_aat` does not evaluate `exp` (B3 does). Revoking a
  key is a distinct, reject-after operation (§3.11.2 B1 row).
- **`scopes` tampering boundary**: the issuer MUST derive `scopes` from RBAC and MUST
  NOT honour a `scopes` value supplied by the caller, so a compromised client cannot
  elevate its own AI capability set (§5.6 `scopes` row; §4.2 "resolve … AI capability
  scopes from the RBAC tables").
- **Session validity boundary**: an absent or expired session is rejected before any
  AAT is minted (§8.1 enrolment trust direction; §4.2 "Verify the caller's session")
  with exact codes `UNAUTHENTICATED` / `SESSION_EXPIRED`.
- **Rate limit boundary**: the issuer RPC is itself rate-limited per actor under a
  transaction advisory lock, so a compromised client cannot mint AATs without bound
  (§4.2 "Rate-limited itself"). Crossing the limit raises `RATE_LIMITED`.
- **Token lifetime boundary**: `exp` is within the configured minutes of `iat` (§5.6
  `iat, exp` row — "Short lifetime, minutes"). The slice uses the configured minutes;
  it invents no new value. Gateway enforcement of `exp` is B3.
- **Public-key handoff**: enroll/rotate MUST return `public_jwk` so the §8.1 operator
  can complete platform enrollment without reading the restricted keystore.
- **Deliberate omissions**: the AAT carries no patient identifiers, no quota state, and
  no provider/model hints (§5.6 "Deliberate omissions"). Any code path that would add
  one is out of scope and a drift.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The installation keystore MUST hold the installation id and the private
  signing key in a restricted schema that is unreadable by the `anon` and
  `authenticated` roles, with only the token-issuing function permitted to read it
  (§4.2 "Installation keystore" row).
- **FR-002**: Key rotation MUST add a new signing key without removing the previous
  one, so that AATs already signed by the previous key continue to verify at the clinic
  self-test while the previous key is unrevoked (§4.2 "Installation keystore" notes;
  B1 `Done when` cell). Clinic `verify_aat` MUST NOT check `exp` (B3 owns expiry).
- **FR-002a**: Enroll and rotate MUST return `public_jwk` (`kty`/`crv`/`x`/`kid`) together
  with `kid` and `installation_id` in `rpc_success` data for the §8.1 operator handoff.
- **FR-002b**: Signing-key selection MUST be scoped to the clinic singleton
  `installation_id`, ordered by `valid_from DESC, kid DESC`, with inserts stamped by
  `clock_timestamp()`; a second distinct `installation_id` MUST be rejected
  (`enforce_single_installation`).
- **FR-003**: A revoked signing key MUST be rejected during AAT verification (§3.11.2
  B1 row). `verify_aat` MUST return `false` (not throw) on malformed signatures and MUST
  bind payload `iss` to the key row's `installation_id`.
- **FR-004**: The AI token issuer RPC MUST verify the caller's session and reject an
  absent or expired session with `UNAUTHENTICATED` / `SESSION_EXPIRED` (§4.2 "AI token
  issuer RPC" row; §8.1 trust bootstrap).
- **FR-005**: The issuer RPC MUST resolve tenant and actor claims (`iss`, `sub`, `org`,
  `branch`, `role`) and AI capability `scopes` from the RBAC tables (§4.2 "AI token
  issuer RPC" row).
- **FR-006**: The issuer RPC MUST mint a short-lived, signed AAT that populates every
  claim in the §5.6 table — `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`,
  `jti`, `iat`, `exp`, `ver` — and omits patient identifiers, quota state, and
  provider/model hints (§5.6).
- **FR-007**: `scopes` MUST be derived server-side from RBAC and MUST never be
  client-supplied, such that a caller attempting to supply `scopes` has no effect on the
  issued token (§5.6 `scopes` row).
- **FR-008**: The `aud` claim MUST be the AI platform audience, preventing reuse of a
  clinic session token as an AAT and vice versa (§5.6 `aud` row).
- **FR-009**: `jti` MUST be a unique token id (§5.6 `jti` row).
- **FR-010**: `exp` MUST be set within the configured number of minutes of `iat`
  (§5.6 `iat, exp` row).
- **FR-011**: `ver` MUST carry the token contract version, enabling later rotation of
  the contract itself (§5.6 `ver` row).
- **FR-012**: The issuer RPC MUST record the issuance (§4.2 "AI token issuer RPC" row;
  B1 `Done when` cell).
- **FR-013**: The issuer RPC MUST be itself rate-limited per actor, taking
  `pg_advisory_xact_lock` before count+insert, raising `RATE_LIMITED` over the ceiling
  (§4.2 "AI token issuer RPC" row; B1 `Done when` cell).
- **FR-013a**: Issuer failures use bare `RAISE EXCEPTION '<CODE>'` with the codes listed
  in `contracts/aat-token.md` §9; keypair routines keep `rpc_result`.
- **FR-014**: The clinic database MUST gain no knowledge of prompts, providers,
  quotas, or AI request state from this slice — only the two AI-shaped facts "I can
  mint tokens for the AI platform" and (separately, via another RPC) "a human accepted
  AI output here" (§4.2 boundary note).

### Key Entities *(include if feature involves data)*

- **Installation keystore** (restricted schema): holds the installation id and the
  private signing key(s) for an enrolled clinic. Rotation is additive; a key may be
  revoked. Only the token-issuing function reads it (§4.2; §8.1).
- **Issuance record**: written by the issuer RPC when an AAT is minted; records that an
  issuance occurred (§4.2 "records issuance"; B1 `Done when` cell). Field shapes beyond
  what §4.2 and §5.6 name are not specified by the cited sections and are not invented
  here.

The concrete table and column names are not named by the cited sections of
`17-ai-platform.md`; this slice MUST follow the established `public` wrapper →
`auth_internal` `SECURITY DEFINER` pattern (§4.2 header "every addition follows the
established `public` wrapper → `auth_internal` `SECURITY DEFINER` pattern (F4)") and
the repository's shared schema conventions, rather than inventing names.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: This slice serves small-to-mid-size multi-branch clinics by folding
  AI trust into the existing clinic Supabase and its per-clinic GoTrue identity (F2),
  rather than introducing a second identity provider. No microservices, queues, or
  Kubernetes are added (constitution I; §14 row I).

- **Layer Placement**: This slice touches **`backend/` (Supabase)** only. It implements
  the §4.2 clinic-backend components — the installation keystore and the AI token issuer
  RPC — and the §8.1 clinic-side enrollment bootstrap step that generates and stores the
  keypair. It does not touch `ai-platform/` (the Cloudflare Worker) or `frontend/`
  (Flutter). The gateway is acknowledged in §14 as a new, non-primary, additive
  deployable ("no domain logic, no business data, no write path into Supabase, always
  optional"); B1 is the *clinic-side* counterpart that lets the gateway trust a clinic
  in one direction only (§8.1 note: "Trust now exists in one direction only: the
  platform can verify this clinic's tokens"), so the §14 non-primary, additive
  acknowledgement applies to the *platform*. This slice on its own has no write path
  into the platform and adds nothing to `ai-platform/`.

- **Data Integrity & Security**: The signing key lives in a restricted schema with
  `anon`/`authenticated` denied by RLS and only the issuing function able to read it
  (§4.2). Domain integrity, transactional correctness, and the source of truth for who
  may mint AATs live in PostgreSQL (constitution III). `scopes` are derived server-side
  from RBAC and never client-supplied (§5.6), enforcing defense in depth (constitution
  IV). Issuance is recorded for auditability (constitution IV).

- **Failure Handling**: An absent or expired session is rejected, and the issuer's own
  rate limit trips on abuse (§4.2; §5.6). These are local rejections of the token
  request; they are not AI-feature degradations. The constitution V rule that
  subscription/availability must never hard-lock clinical work is not engaged by B1 —
  an AAT issuance failure means the AI feature cannot be used, it does not block clinic
  work, because AI is strictly additive (§14 row I "Desktop-first" resolution).

## Out of Scope

Per delivery plan §2.4 this slice states its exclusions explicitly.

- **Control-plane enrollment and the installation lifecycle** — that is slice B2
  (delivery plan §3.3 row B2: `Needs A5`). B1 stores the keypair and mints AATs; it does
  not implement operator-authenticated enroll/suspend/resume/rotate/delete writing
  `installation`, `installation_key`, `entitlement`, and `control_audit`. The §8.1
  sequence's *platform-side* writes (create `installation` + `installation_key` +
  `entitlement` + `control_audit` in D1) belong to B2, not B1.
- **Guard identity stage, rate-limiting stage, entitlement, and kill switches** — that
  is slice B3 (delivery plan §3.3 row B3: `Needs A5, B1, B2`). B1 freezes the AAT claim
  contract; B3 is what verifies it.
- **The Quota Durable Object and admission stage** — slice B4 (§3.3 row B4). Replay
  rejection of `jti` happens at admission (B4), not at issuance, even though `jti` is
  minted here (§5.6 `jti` row; §4.3.3).
- **Token contract rotation behaviour** (overlapping `ver` acceptance) — slice J4
  (delivery plan §3.9 row J4). B1 carries the `ver` claim so J4 can later use it; B1
  does not implement the rotation window.
- **Context provider RPCs, the AI acceptance recording RPC, and the AI availability
  flag** — the other §4.2 clinic-backend components. They are separate slices: context
  RPCs and the availability flag land with E3/B2-era work, and the acceptance recording
  RPC is F2 (delivery plan §7, §4.2 table). B1 implements only the keystore and the
  issuer.
- **Reading prompt text, providers, models, quotas, or AI request state into the clinic
  database** — explicitly out of scope by the §4.2 boundary note.

Prohibitions copied from delivery plan §6.4 that this slice must not violate:

- Add a mechanism from §9.14 because it looks prudent (R-20).
- Put prompt text, a provider name, or a model identifier anywhere in the Flutter
  client (R-12) — E1 owns that guard; B1 touches no client code anyway.
- Add a second round trip to the Quota Durable Object, or a second R2 object per request
  (§7.5, §13.6) — not applicable to B1, which performs no DO or R2 work, and is stated
  here for completeness as a §6.4 prohibition.
- Journal a guard rejection as a request, or write a D1 row per stream chunk (§7.5) —
  not applicable to B1 (no gateway journal here).
- Introduce per-request server-side state of any kind (§4.4, §9.7) — the issuer is a
  request-scoped RPC; B1 introduces no persistent per-request state.
- Assemble a final result from stream chunks on the client, or make provisional content
  committable (§6.4, A5) — not applicable to B1; no streaming in this slice.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An automated SQL/RLS test proves `anon` cannot read the installation
  keystore (delivery plan §3.11.2 B1 row).
- **SC-002**: An automated SQL/RLS test proves `authenticated` cannot read the
  installation keystore (delivery plan §3.11.2 B1 row).
- **SC-003**: An automated test proves enroll reaches the keystore and returns
  `public_jwk` (delivery plan §3.11.2 B1 row; §8.1 handoff).
- **SC-004**: An automated test proves rotation adds a key without removing the previous
  one and that an AAT signed by the previous key still verifies after rotation (clinic
  self-test; expiry is B3) (delivery plan §3.11.2 B1 row; B1 `Done when` cell).
- **SC-005**: An automated test proves a revoked signing key is rejected (delivery plan
  §3.11.2 B1 row).
- **SC-005a**: An automated test proves `verify_aat` returns `false` on malformed
  signature and on payload `iss` mismatch.
- **SC-006**: An automated test proves the issuer RPC populates every claim in the §5.6
  table with correct sources and `alg: EdDSA` header (delivery plan §3.11.2 B1 row).
- **SC-007**: An automated test proves `scopes` are derived from RBAC and are
  unaffected by a caller attempting to supply them (delivery plan §3.11.2 B1 row).
- **SC-008**: An automated test proves an expired or absent session is rejected with
  `SESSION_EXPIRED` / `UNAUTHENTICATED` (delivery plan §3.11.2 B1 row).
- **SC-009**: An automated test proves an issuance row is written on a successful mint
  (delivery plan §3.11.2 B1 row).
- **SC-010**: An automated test proves the issuer RPC's own per-actor rate limit trips
  with `RATE_LIMITED` beyond the allowed count (delivery plan §3.11.2 B1 row).
- **SC-011**: An automated test proves `exp` is within the configured minutes of `iat`
  (delivery plan §3.11.2 B1 row).
- **SC-012**: Automated tests prove the remaining issuer bare codes (`STAFF_NOT_FOUND`,
  `BRANCH_NOT_FOUND`, `INSTALLATION_NOT_ENROLLED`, `AI_ACCESS_DENIED`) and keypair
  admin/error paths (`FORBIDDEN`, `INVALID_INPUT`, `KEY_NOT_FOUND`,
  `INSTALLATION_NOT_ENROLLED` on rotate-before-enroll).

## Assumptions

- The Supabase RBAC tables are stable enough to derive AI capability scopes, per the
  external dependency recorded in delivery plan §7 ("Blocks B1"). B1 derives `scopes`
  from those tables and does not redefine the RBAC model.
- The clinic backend's existing conventions apply: additions follow the `public`
  wrapper → `auth_internal` `SECURITY DEFINER` pattern (§4.2 header, citing F4), and
  the repository's shared schema conventions for IDs, timestamps, audit fields, and
  soft deletion (constitution III). B1 names no table or column the cited sections do
  not name.
- The configured number of minutes for the AAT lifetime and the issuer rate-limit
  thresholds come from configuration the clinic backend already supports or that this
  slice wires as config (§5.6 `iat, exp` row; §4.2 "Rate-limited itself"). The cited
  sections name "minutes" and "rate-limited" without giving numeric values; this slice
  treats any specific number as configuration, not as a value invented by the spec.
- Enrolment of an installation (the operator-driven §8.1 routine that generates the
  keypair and stores the private key) is in scope for this slice only to the extent the
  B1 `Done when` cell names it — storing the id and private signing key in the restricted
  schema and supporting additive rotation. The platform-side enrollment writes and
  entitlement creation are out of scope (B2).