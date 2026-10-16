# Feature Specification: Token contract rotation with overlapping acceptance

**Feature Branch**: `ai/051-j4-token-contract-rotation`

**Created**: 2026-08-03

**Status**: Draft

**Input**: Slice `J4` — "Token contract rotation with overlapping acceptance" (delivery plan §3.9, band J).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

The slice's `Canonical` cell (delivery plan §3.9, row J4) reads:

> §5.7, §5.6

Expanded to:

> §5.7, §5.6, §4.5, §7.3

§4.5 and §7.3 are the control-plane and D1 surfaces **named by** the amended
Token contract sections: §5.6 places the accepted-`ver` set in the D1
`token_contract` record (§7.3), and the §5.7 Token contract row and transition
model state that both rotation edges are control-plane operator mutations
(§4.5). They are listed here for traceability of the Freezes below, in the same
way J1 listed §12.4 alongside §5.7.

### Freezes

Contracts this slice establishes for the first time:

- **The D1 `token_contract` accepted-`ver` set as the verifier's authority**:
  the accepted-`ver` set is a single platform-global `token_contract` record in
  D1 — one row per `ver`, with the accepted set being the rows that have no
  `retired_at` — holding **exactly one** value when stable and **at most two**
  during a rotation; the identity stage checks the token's `ver` against that
  set, read through the same config cache as installation keys and kill
  switches (§5.6 accepting side; §7.3 `token_contract`).
- **No `retire_after` and no hot-path TTL on the token contract**: the
  `token_contract` record carries no `retire_after` column and no TTL, and
  nothing auto-retires a `ver` on a clock — retirement is not scheduled (§5.7;
  §7.3 `token_contract`).
- **Control-plane begin-rotation and retire as the only writers**: begin a
  rotation (add a `ver` to the accepted set) and retire a `ver` (remove it) are
  the only two writers of the global `token_contract` record; begin-rotation
  inserts a row for the new `ver` and retire stamps `retired_at` on the old one;
  both are control-plane operator mutations that also write `control_audit`, and
  the request path never writes this record (§4.5 Token contract rotation; §7.3
  `token_contract`; §5.7 transition model).
- **Overlapping acceptance of two Token contract `ver` values during a rotation
  window**: the verifier accepts every `ver` in the accepted set, so while the
  set has two members both participating `ver` values verify; "during" and
  "after" are set membership, not clock states (§5.7 Token contract row and
  transition model; delivery plan §3.9 Done when).
- **Refusal of a retired or unknown `ver` as existing `unauthenticated`**: a
  token whose `ver` is not in the accepted set fails verification as
  `unauthenticated` (§5.4 error taxonomy); a contract the verifier no longer
  accepts is not a distinct error class, and **no new taxonomy code is added**
  for it (§5.6 accepting side; delivery plan §3.9 Done when; §3.11.8 J4).
- **Single mint from the clinic setting `ai.aat.ver`**: the issuer RPC reads its
  `ver` from the AI schema's settings row `ai.aat.ver` in
  `ai_internal.app_settings`, alongside `ai.aat.lifetime_minutes`, and mints
  **exactly one** `ver` per token — there is no dual-mint; a clinic is on the
  old contract or the new one, never both — and advancing that setting is an
  operator action on the clinic deployment, which the platform never reads or
  writes (§5.6 minting side; §1.3.1 as cited there).
- **Token-contract rotation without re-enrollment**: rotation is additive in
  exactly the way key rotation is — both contract versions are accepted during
  the window, `iss` and `kid` are untouched, and no clinic re-enrolls; `iss`
  plus `kid` continue to select the enrolled public key (§5.6; delivery plan
  §3.9 Done when).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (B1, B3). Changing any is out of scope
by definition:

- **From B1 (installation keystore and AAT issuer)**: the **installation
  keystore** (installation id and Ed25519 private signing key in a restricted
  schema); the **AAT issuer** that mints an `alg: EdDSA` compact JWS and
  populates every claim in §5.6 (including `ver`); **`scopes` derived
  server-side from RBAC** and never client-supplied; and **key-set rotation**
  that adds a key without invalidating tokens already in flight and without
  re-enrollment (B1 Done when; §5.6). J4 **advances** the minting `ver` through
  the clinic setting `ai.aat.ver` so a token under the new contract version
  carries every §5.6 claim and so contract-version rotation needs no
  re-enrollment; it does not redefine the keystore, the issuer, EdDSA signing,
  the signature, the claim set, or `scopes` derivation (B1 Done when; §5.6).
- **From B3 (guard stages: identity, rate limiting, entitlement and kill
  switches)**: the **token verifier port** that verifies signature (WebCrypto
  `Ed25519`, `alg` pinned to `EdDSA`), audience, expiry, and clock skew, and
  that leaves the request principal immutable to later stages (B3 Done when;
  §5.6). J4 **extends** the verifier with an accepted-`ver` check against the D1
  `token_contract` set — read through the same config cache B3 already uses for
  installation keys and kill switches — so both `ver` values verify while the
  set has two members and a `ver` outside the set is refused as
  `unauthenticated`; it does not redefine signature, audience, expiry, skew,
  rate limiting, entitlement, or kill-switch evaluation (B3 Done when; §5.6;
  §7.3).

### Open decisions relied on

None. §5.6, §5.7, §4.5, and §7.3 fully specify the Token contract claim set
(including `ver`), the accepted-`ver` set and its D1 shape, the two
control-plane transitions, and the compatibility promise of overlapping
acceptance during rotation; no §15 recommended default is assumed for this
slice. §5.7 cites OD-9 only to explain why the token contract deliberately
*differs* from capability overlap, so this slice depends on no OD-9 default.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Token contract rotation with overlapping acceptance (Priority: P1)

When the Token contract must change, an operator begins a rotation through the
control plane: a new `ver` is added to the platform-global `token_contract`
accepted set in D1 while the prior `ver` is kept, so the set holds two values and
the verifier accepts tokens carrying either of them (§5.7; §4.5; §7.3). During
that window the operator advances the clinic setting `ai.aat.ver` per deployment,
at whatever pace suits; each clinic flips from the prior `ver` to the new one on
its own, minting exactly one `ver` per token (§5.6; §5.7). When every clinic has
advanced and the last old token has expired, the operator retires the prior
`ver`: the row is stamped `retired_at`, the set returns to one value, and tokens
carrying the retired `ver` are refused as `unauthenticated` (§5.7; §5.6; §7.3).
Tokens minted under the new contract still carry every §5.6 claim, and the
installation stays enrolled — rotation does not require re-enrollment — because
`iss` plus `kid` continue to select the enrolled public key (§5.6).

**Why this priority**: J4 has `Needs: B1, B3` (delivery plan §3.9). B1 must already
mint AATs that populate every §5.6 claim (including `ver`) from the installation
keystore, and B3 must already verify those tokens through the identity stage.
Band J defers the overlapping-acceptance *behaviour* until the token contract
needs its first change (delivery plan §3.9 Build when; DP-5).

**Independent Test**: Two `ver` values are accepted simultaneously during a
rotation window; tokens of the retired version are refused after it; rotation
requires no re-enrollment (the slice's `Done when` cell; delivery plan §2.2;
DP-3).

**Acceptance Scenarios**:

1. **Given** a begin-rotation control-plane mutation has added a new `ver` to the
   `token_contract` accepted set while keeping the prior one, so the set has two
   members, **When** an AAT carrying the prior `ver` and an AAT carrying the new
   `ver` are each presented to the verifier, **Then** both tokens verify
   (delivery plan §3.11.8 J4; §5.7; §4.5).
2. **Given** a retire control-plane mutation has stamped `retired_at` on the
   prior `ver` so the accepted set has returned to one member, **When** an AAT
   carrying the retired `ver` is presented to the verifier, **Then** the token
   is refused as `unauthenticated` with no new taxonomy code (delivery plan
   §3.11.8 J4; §5.7; §5.6; §7.3).
3. **Given** the clinic setting `ai.aat.ver` has been advanced to the new Token
   contract version, **When** the issuer RPC mints an AAT, **Then** the token
   carries exactly that one `ver` and every claim in the §5.6 table
   (`iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`,
   `ver`) (delivery plan §3.11.8 J4; §5.6).
4. **Given** an already-enrolled installation, **When** the Token contract is
   rotated to a new `ver` with overlapping acceptance, **Then** the installation
   remains enrolled and continues to mint and verify without re-enrollment
   (`iss` plus `kid` still select the enrolled public key) (delivery plan
   §3.11.8 J4; §5.6).

### Test plan

Layer from delivery plan §3.11.8 J4: **Unit + SQL**. Named tests:

1. **`both_ver_values_verify_during_rotation_window`** (Unit) — with the
   `token_contract` accepted set holding two members, both participating `ver`
   values verify (§5.7; §5.6; §3.11.8 J4).
2. **`retired_ver_refused_as_unauthenticated`** (Unit) — once the retired `ver`
   is no longer in the accepted set, a token carrying it is refused as
   `unauthenticated`, with no new taxonomy code emitted (§5.6; §5.7; §3.11.8
   J4).
3. **`unknown_ver_refused_as_unauthenticated`** (Unit) — a token whose `ver` was
   never in the accepted set is refused as `unauthenticated` on the same path
   (§5.6 accepting side).
4. **`accepted_set_is_one_when_stable_and_two_mid_rotation`** (SQL) — the
   accepted set (rows with no `retired_at`) holds exactly one `ver` when stable
   and at most two during a rotation (§5.6; §5.7; §7.3).
5. **`begin_rotation_adds_ver_and_keeps_prior`** (SQL) — the control-plane
   begin-rotation mutation inserts a row for the new `ver`, leaves the prior
   `ver` accepted, and writes `control_audit` (§5.7 transition model; §4.5;
   §7.3).
6. **`retire_stamps_retired_at_and_returns_set_to_one`** (SQL) — the
   control-plane retire mutation stamps `retired_at` on the retired `ver`,
   returns the accepted set to one member, and writes `control_audit` (§5.7
   transition model; §4.5; §7.3).
7. **`request_path_never_writes_token_contract`** (Unit) — no request-path code
   writes the `token_contract` record and nothing auto-retires a `ver` (§5.7;
   §7.3).
8. **`new_contract_token_carries_every_claim`** (SQL) — a token minted under the
   new contract populates every §5.6 claim (§5.6; §3.11.8 J4).
9. **`issuer_mints_single_ver_from_ai_aat_ver`** (SQL) — the issuer reads `ver`
   from `ai.aat.ver` in `ai_internal.app_settings` and mints exactly one `ver`
   per token, with no dual-mint (§5.6 minting side).
10. **`rotation_requires_no_re_enrollment`** (Unit + SQL) — after contract
    rotation, the same enrolled installation mints and verifies without a
    re-enrollment step; `iss` plus `kid` still select the enrolled public key
    (§5.6; §3.11.8 J4).

### Edge Cases

- **During the rotation window (accepted set has two members)**: tokens of
  either participating `ver` verify; refusal of one of those two while the set
  has two members is a failure of the overlapping-acceptance promise (§5.7).
- **After retirement (accepted set has returned to one member)**: a token whose
  `ver` is the retired value is refused as `unauthenticated`; no new
  error-taxonomy code is added for it, because a contract the verifier no longer
  accepts is not a distinct error class from any other unacceptable claim (§5.6
  accepting side; §5.4 as cited there; delivery plan §3.11.8 J4).
- **A `ver` that was never accepted**: a token whose `ver` is not in the set for
  any reason fails verification as `unauthenticated` on the same path — the rule
  is set membership, not a retired-versus-unknown distinction (§5.6 accepting
  side).
- **"During" and "after" are set membership, not clock states**: the verifier is
  in overlap exactly while the accepted set has two members, and a `ver` is
  retired exactly when an operator has removed it (§5.7 transition model).
- **No timed auto-retire**: the `token_contract` record carries no
  `retire_after` and no TTL; a timed retirement on the hot path would create a
  way for the platform to start refusing valid clinics on a clock (R-20; §5.7;
  §7.3).
- **The request path never writes `token_contract`**: begin-rotation and retire
  are the only writers, both control-plane operator mutations that also write
  `control_audit` (§4.5; §7.3; §5.7).
- **No dual-mint**: a clinic is on the old contract or the new one, never both;
  the issuer mints exactly one `ver` per token, read from `ai.aat.ver` (§5.6
  minting side).
- **The platform never reads or writes `ai.aat.ver`**: advancing the clinic's
  minting version is an operator action on the clinic deployment (§5.6 minting
  side; §1.3.1 as cited there).
- **New-contract mint missing any §5.6 claim**: a mint under the new `ver` that
  omits any of `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`,
  `iat`, `exp`, or `ver` fails the claim-completeness case (§5.6; §3.11.8 J4).
- **`scopes` remain server-derived**: under the new contract, `scopes` MUST still
  be derived server-side from RBAC and MUST NOT be client-supplied (§5.6).
- **Header `alg` remains non-negotiable**: rotation of `ver` does not relax the
  rule that the compact JWS header carries `alg: EdDSA` and that a verifier
  accepting anything other than `EdDSA` (including `none` or HMAC) is accepting
  a forgery (§5.6).
- **Deliberate omissions preserved**: rotated tokens still MUST NOT carry patient
  identifiers, quota state, or provider/model hints (§5.6).
- **Inherited prohibition: no mechanism from §9.14** added as a rotation aid
  (R-20; delivery plan §6.4).
- **Inherited prohibition: no per-request server-side state** introduced to hold
  rotation sessions (§4.4, §9.7; delivery plan §6.4).
- **Inherited prohibition: no second Quota Durable Object round trip and no
  second R2 object per request** as part of `ver` checking (§7.5, §13.6;
  delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The identity stage MUST check the token's `ver` against the
  **accepted-`ver` set**, a single platform-global `token_contract` record in
  D1, and MUST accept every `ver` in that set (§5.6 accepting side; §5.7 Token
  contract row; §7.3).
- **FR-002**: The accepted-`ver` set MUST hold **exactly one** value when stable
  and **at most two** during a rotation (§5.6 accepting side; §5.7 Token
  contract row).
- **FR-003**: The `token_contract` record MUST be one row per `ver` carrying the
  accepted `ver` value, `added_at`, `retired_at`, and `changed_by`, with the
  accepted set being the rows that have no `retired_at` (§7.3 `token_contract`).
- **FR-004**: The `token_contract` record MUST NOT carry a `retire_after` column
  or a TTL, and nothing MUST auto-retire a `ver` — retirement is not scheduled
  (§5.7; §7.3 `token_contract`).
- **FR-005**: Begin-rotation (add a `ver` to the accepted set) and retire
  (remove it) MUST be the only two writers of the global `token_contract`
  record, and the request path MUST NOT write it (§4.5 Token contract rotation;
  §7.3 `token_contract`).
- **FR-006**: Begin-rotation MUST insert a row for the new `ver` and keep the
  prior `ver` accepted, opening the overlap window from that write (§5.7
  transition model; §7.3 `token_contract`).
- **FR-007**: Retire MUST stamp `retired_at` on the retired `ver` so the
  accepted set returns to one value, closing the window with that write (§5.7
  transition model; §7.3 `token_contract`).
- **FR-008**: Both transitions MUST be control-plane operator mutations that
  also write `control_audit`, and MUST NOT be request-path clock trips (§4.5
  Token contract rotation; §5.7 Token contract row; §7.3 `token_contract`).
- **FR-009**: The verifier MUST read the live accepted set through the same
  config cache as installation keys and kill switches, so a cold isolate
  reconstructs it from D1 like every other volatile flag (§5.6 accepting side;
  §7.3 `token_contract`).
- **FR-010**: A token whose `ver` is not in the accepted set MUST fail
  verification as `unauthenticated`, and **no new error-taxonomy code** MUST be
  added for it (§5.6 accepting side; §5.4 as cited there; delivery plan §3.9
  Done when).
- **FR-011**: The issuer RPC MUST read its `ver` from the AI schema's settings
  row `ai.aat.ver` in `ai_internal.app_settings`, alongside
  `ai.aat.lifetime_minutes`, and MUST mint **exactly one** `ver` per token; there
  MUST be no dual-mint (§5.6 minting side).
- **FR-012**: The platform MUST NOT read or write the `ai.aat.ver` setting;
  advancing it is an operator action on the clinic deployment (§5.6 minting
  side; §1.3.1 as cited there).
- **FR-013**: A token minted under the new Token contract MUST carry every claim
  in the §5.6 table: `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`,
  `jti`, `iat`, `exp`, and `ver` (§5.6).
- **FR-014**: `scopes` MUST remain derived server-side from RBAC and MUST never
  be client-supplied, including under the new contract `ver` (§5.6).
- **FR-015**: Token contract rotation MUST NOT require clinic re-enrollment;
  `iss` plus `kid` MUST continue to select the enrolled public key so rotation
  remains a key-set / contract-version operation rather than a re-enrollment
  (§5.6).
- **FR-016**: The AAT MUST remain a compact JWS whose header carries `alg:
  EdDSA` and the `kid` of the installation key that signed it; `alg` MUST NOT
  become negotiable because of a `ver` rotation (§5.6).
- **FR-017**: Rotated tokens MUST preserve the deliberate omissions of the Token
  contract: no patient identifiers, no quota state, and no provider or model
  hints (§5.6).

### Key Entities

- **`token_contract`** (D1) — the platform-global set of accepted AAT `ver`
  values. Key fields: accepted `ver` value, `added_at`, `retired_at`,
  `changed_by`; one row per `ver`, and the accepted set is the rows with no
  `retired_at`. Growth: a handful of rows ever. Retention: full history
  (append-only). It is global rather than per-installation because `ver`
  versions the AAT claim contract itself, and D1 is its only authority (§7.3
  `token_contract`; §5.6).
- **`ai.aat.ver`** (clinic AI schema settings row in `ai_internal.app_settings`,
  alongside `ai.aat.lifetime_minutes`) — the single source the issuer RPC reads
  its minting `ver` from. This slice advances it as a control surface; it does
  not redefine the B1 keystore or issuer tables (§5.6 minting side).
- **`control_audit`** (D1) — consumed, not defined here: both begin-rotation and
  retire write it with the operator identity (§7.3; §4.5). B2 owns this entity.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Token-contract rotation with overlapping `ver` acceptance lets
  the platform change the AAT contract without forcing every clinic through
  re-enrollment, matching clinic-scale operations with limited IT capacity
  (constitution principle I; §5.6; §5.7).
- **Layer Placement**: This slice touches **`backend/`** (Supabase) — the
  `ai.aat.ver` settings row and the AAT issuer minting a single `ver` with every
  §5.6 claim — and **`ai-platform/`** (Cloudflare Worker) — the D1
  `token_contract` accepted-`ver` set, its two control-plane transitions, and
  the identity-stage check that accepts every `ver` in the set and refuses the
  rest as `unauthenticated`. It does not add Flutter AI surfaces. The gateway
  remains a non-primary, additive component: no domain logic, no business data,
  no write path into Supabase (§14; delivery plan §7.1).
- **Data Integrity & Security**: Installation keys stay in the restricted
  keystore B1 froze; `scopes` stay RBAC-derived; `alg` stays pinned to `EdDSA`;
  deliberate omissions (no patient identifiers, no quota state, no provider or
  model hints) stay in force under the new `ver` (§5.6). The accepted-`ver` set
  is writable only by two audited control-plane operator mutations, never by the
  request path, and its rows are append-only history so "which contract versions
  were accepted when, and who changed that" is answerable without a second store
  (§4.5; §7.3). No soft-delete or dual-write surface is introduced.
- **Failure Handling**: A token whose `ver` is not in the accepted set is
  refused by verification as `unauthenticated`; clinical work continues without
  depending on AI (constitution principle V). Platform unavailability remains
  additive: AI is optional relative to clinic workflows.

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **B1** — installation keystore schema, Ed25519 key generation, issuer rate
  limit, issuance recording, and key-set rotation that adds a signing key.
  Consumed for minting and enrollment identity; those surfaces are not
  redefined.
- **B3** — signature, audience, expiry, and clock-skew verification; rate
  limiting; entitlement and kill switches; replay rejection (already B4).
  Consumed for the verifier port and identity stage; those checks are not
  redefined beyond overlapping `ver` acceptance and retired-`ver` refusal.
- **B2** — enroll, suspend, resume, rotate (installation key), delete, and
  `control_audit`. Token-contract `ver` rotation requires no re-enrollment and
  does not redefine B2 lifecycle actions; the two rotation mutations write
  `control_audit` as B2 defined it (§4.5; §7.3).
- **B4** — Quota Durable Object, `jti` freshness / replay rejection, idempotency,
  budget, concurrency. `jti` remains a §5.6 claim; replay behaviour stays B4.
- **J1** — capability deprecation overlap window and `capability_retired`.
- **J2** — `context_required` self-healing round trip.
- **J3** — staged rollout and canary cohorts.
- **A new error-taxonomy code for retired or unknown `ver`** — §5.6 states the
  refusal is the existing `unauthenticated` and that no new taxonomy code is
  added; this slice invents none.
- **Timed auto-retirement of a `ver`** — §5.7 and §7.3 state the record carries
  no `retire_after` and no TTL and that retirement is an operator mutation; this
  slice adds no clock, scheduler, or window duration (R-20).
- **Dual-mint** — §5.6 states the issuer mints exactly one `ver` per token; this
  slice does not add a clinic minting both contract versions.
- **Re-enrollment as part of contract rotation** — §5.6 states rotation is
  additive and no clinic re-enrolls.
- **Rewriting the B1 keystore / issuer / signature contract or the B3 verifier
  checks** — J4 advances the minting `ver` and extends the verifier with the
  accepted-`ver` check only.
- **`capability_grant` lifecycle fields** — `deprecated_at` / `retire_after` and
  the capability overlap window belong to J1; §5.7 cites them only to explain
  why the token contract deliberately differs.
- **Band G commercial surface** and **band K / §9.14 deferrals**.

Prohibitions (delivery plan §6.4), none of which this slice introduces:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request
  (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional
  content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An automated test proves both participating `ver` values verify
  while the accepted set has two members (asserted by test 1; Done when).
- **SC-002**: An automated test proves a `ver` no longer in the accepted set is
  refused as `unauthenticated` with no new taxonomy code, and the same holds for
  a `ver` never accepted (asserted by tests 2 and 3; Done when).
- **SC-003**: An automated test proves the accepted set holds exactly one `ver`
  when stable and at most two during a rotation (asserted by test 4).
- **SC-004**: An automated test proves begin-rotation adds the new `ver` while
  keeping the prior one, retire stamps `retired_at` and returns the set to one,
  and both write `control_audit` (asserted by tests 5 and 6).
- **SC-005**: An automated test proves the request path never writes
  `token_contract` and no `ver` is auto-retired (asserted by test 7).
- **SC-006**: An automated test proves a token minted under the new contract
  carries every §5.6 claim (asserted by test 8; Done when).
- **SC-007**: An automated test proves the issuer mints exactly one `ver`, read
  from `ai.aat.ver` (asserted by test 9).
- **SC-008**: An automated test proves Token contract rotation requires no
  re-enrollment for an already-enrolled installation (asserted by test 10; Done
  when).

## Assumptions

- B1 and B3 are complete on the integration line this slice branches from
  (`Needs: B1, B3`).
- B1 already freezes the keystore, the AAT issuer that populates every §5.6 claim
  (including `ver`), RBAC-derived `scopes`, and key-set rotation without
  re-enrollment; J4 advances the minting `ver` via `ai.aat.ver` without
  rewriting those contracts (B1 Done when; §5.6).
- B3 already freezes the token verifier port and identity-stage checks
  (signature, audience, expiry, skew) with an immutable principal; J4 extends
  verification with the accepted-`ver` set check without rewriting those checks
  (B3 Done when; §5.6).
- Spec Kit's `create-new-feature.sh --dry-run` allocates against `docs/specs/` and
  does not parse `ai/<NNN>-*` branches, so the number was confirmed from `specs/`
  (highest `050-staged-rollout-canary`) and applied as **051**.
- Build-when trigger ("the token contract needs its first change") is an
  ordering/trigger condition from delivery plan §3.9, not a product gate encoded
  as runtime configuration in this slice.
- The Token contract rotation window has no named length: §5.7 states that
  "during" and "after" are set membership rather than clock states, so tests
  establish them by the size of the accepted set without inventing a duration
  constant.
- The config cache that carries installation keys and kill switches already
  exists on the integration line; §5.6 and §7.3 state the accepted-`ver` set is
  read through that same cache and that a rotation takes effect within one cache
  TTL without a deploy, so this slice adds no cache of its own.
