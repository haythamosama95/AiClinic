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
by `anon` and `authenticated`, that rotation is additive, that a previously-signed token
still verifies inside its validity window, that a revoked key is rejected, and that the
issuer RPC populates every §5.6 claim, derives `scopes` from RBAC independent of any
caller-supplied value, rejects an absent or expired session, records an issuance row,
and trips its own rate limit. No deployment or demo is required (delivery plan DP-1,
DP-3).

**Acceptance Scenarios**:

*Keystore*

1. **Given** the installation keystore exists in a restricted schema, **When** a session
   using the `anon` role attempts to read it, **Then** the read is denied.
2. **Given** the installation keystore exists in a restricted schema, **When** a session
   using the `authenticated` role attempts to read it, **Then** the read is denied.
3. **Given** the installation keystore exists, **When** the token-issuing function reads
   it, **Then** the read succeeds.
4. **Given** an installation has a current signing key, **When** rotation adds a new key,
   **Then** the previous key remains present and is not removed.
5. **Given** rotation has added a new key while an AAT signed by the previous key is
   still within its validity window, **When** that AAT is verified, **Then** it still
   verifies.
6. **Given** a signing key has been revoked, **When** an AAT signed by that revoked key
   is verified, **Then** it is rejected.

*Issuer*

7. **Given** an authenticated, valid staff session, **When** the issuer RPC runs, **Then**
   every claim listed in the §5.6 table is populated (`iss`, `aud`, `sub`, `org`,
   `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`).
8. **Given** a caller attempts to supply `scopes` to the issuer RPC, **When** the RPC
   mints the AAT, **Then** `scopes` are derived from the RBAC tables and the
   caller-supplied value has no effect on the issued token.
9. **Given** the caller's session is absent or expired, **When** the issuer RPC is
   invoked, **Then** it is rejected.
10. **Given** a successful issuance, **When** the RPC completes, **Then** an issuance row
    is written.
11. **Given** the issuer RPC is called within its rate-limit window beyond the allowed
    count, **When** a further call is attempted, **Then** the rate limit trips and the
    call is rejected.
12. **Given** a successful issuance, **When** the `exp` claim is inspected, **Then** it is
    within the configured number of minutes of `iat`.

### Test plan

The layer for every case below is **SQL / RLS**, as named in the slice's row in delivery
plan §3.11.2. Coverage follows delivery plan §3.10 (behavioural, including every error
path and every inherited prohibition the slice can emit).

Named tests:

- `T01 keystore anon read denied` — layer: SQL / RLS
- `T02 keystore authenticated read denied` — layer: SQL / RLS
- `T03 issuing function reads keystore successfully` — layer: SQL / RLS
- `T04 rotation adds key without removing previous` — layer: SQL / RLS
- `T05 previous-key AAT still verifies within validity window` — layer: SQL / RLS
- `T06 revoked key rejected` — layer: SQL / RLS
- `T07 all section 5.6 claims populated` (asserts each of `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver` is present and non-null on one minted AAT) — layer: SQL / RLS
- `T08 scopes derived from RBAC and unaffected by caller-supplied scopes` — layer: SQL / RLS
- `T09 expired or absent session rejected` — layer: SQL / RLS
- `T10 issuance row written` — layer: SQL / RLS
- `T11 issuer rate limit trips` — layer: SQL / RLS
- `T12 exp within configured minutes` — layer: SQL / RLS

### Edge Cases

- **Keystore access boundary**: the only role that may read the private signing key is
  the token-issuing function; `anon` and `authenticated` are denied (§4.2 "Installation
  keystore" row). Any other role that could read the key would break the trust model.
- **Rotation boundary**: rotation is additive — it adds a key without removing the
  previous one, so AATs signed under the previous key continue to verify inside their
  `exp` window (§4.2 notes "Rotation is a supported operation"; B1 `Done when` cell).
  Revoking a key is a distinct, reject-after operation (§3.11.2 B1 row).
- **`scopes` tampering boundary**: the issuer MUST derive `scopes` from RBAC and MUST
  NOT honour a `scopes` value supplied by the caller, so a compromised client cannot
  elevate its own AI capability set (§5.6 `scopes` row; §4.2 "resolve … AI capability
  scopes from the RBAC tables").
- **Session validity boundary**: an absent or expired session is rejected before any
  AAT is minted (§8.1 enrolment trust direction; §4.2 "Verify the caller's session").
- **Rate limit boundary**: the issuer RPC is itself rate-limited, so a compromised
  client cannot mint AATs without bound (§4.2 "Rate-limited itself"). Crossing the
  limit is a terminal rejection for that call.
- **Token lifetime boundary**: `exp` is within the configured minutes of `iat` (§5.6
  `iat, exp` row — "Short lifetime, minutes"). The slice uses the configured minutes;
  it invents no new value.
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
  one, so that AATs already signed by the previous key continue to verify inside their
  validity window (§4.2 "Installation keystore" notes; B1 `Done when` cell).
- **FR-003**: A revoked signing key MUST be rejected during AAT verification (§3.11.2
  B1 row).
- **FR-004**: The AI token issuer RPC MUST verify the caller's session and reject an
  absent or expired session (§4.2 "AI token issuer RPC" row; §8.1 trust bootstrap).
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
- **FR-013**: The issuer RPC MUST be itself rate-limited, so a compromised client
  cannot mint tokens without bound (§4.2 "AI token issuer RPC" row; B1 `Done when`
  cell).
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
- **SC-003**: An automated test proves the issuing function reads the keystore
  successfully (delivery plan §3.11.2 B1 row).
- **SC-004**: An automated test proves rotation adds a key without removing the previous
  one and that an AAT signed by the previous key still verifies within its validity
  window (delivery plan §3.11.2 B1 row; B1 `Done when` cell).
- **SC-005**: An automated test proves a revoked signing key is rejected (delivery plan
  §3.11.2 B1 row).
- **SC-006**: An automated test proves the issuer RPC populates every claim in the §5.6
  table (delivery plan §3.11.2 B1 row).
- **SC-007**: An automated test proves `scopes` are derived from RBAC and are
  unaffected by a caller attempting to supply them (delivery plan §3.11.2 B1 row).
- **SC-008**: An automated test proves an expired or absent session is rejected
  (delivery plan §3.11.2 B1 row).
- **SC-009**: An automated test proves an issuance row is written on a successful mint
  (delivery plan §3.11.2 B1 row).
- **SC-010**: An automated test proves the issuer RPC's own rate limit trips beyond the
  allowed count (delivery plan §3.11.2 B1 row).
- **SC-011**: An automated test proves `exp` is within the configured minutes of `iat`
  (delivery plan §3.11.2 B1 row).

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