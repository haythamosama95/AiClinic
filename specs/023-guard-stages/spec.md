# Feature Specification: Guard stages: identity, rate limiting, entitlement and kill switches (B3)

**Feature Branch**: `ai/023-b3-guard-stages`

**Created**: 2026-07-31

**Status**: Draft

**Input**: Slice `B3` — "Guard stages: identity, rate limiting, entitlement and kill switches"
(delivery plan §3.3, row B3). Not a prose feature description; it is a row of the delivery plan, so
every requirement below cites a section of `docs/architecture/ai-platform/01-ai-platform.md`.

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Verbatim from the `Canonical` cell of slice B3 (delivery plan §3.3):

- `§4.3.2`
- `§4.2.1`
- `§5.6`
- `§4.3.3`
- `§4.3.4`
- `§4.3.12`
- `§7.5`
- `§6.1 stages 2–4`

### Freezes

This slice establishes, for the first time:

- **The token verifier port contract for the enrolled-key strategy.** Identity (§6.1 stage 2) verifies
  the AAT through the verifier port using WebCrypto `Ed25519`, with `alg` pinned to `EdDSA` so that
  `none` and any HMAC algorithm are rejected, and verifies audience, expiry, and clock skew
  (§4.3.2; §4.2.1; §5.6). The port has two strategies and only the enrolled-installation-key strategy
  is built now; the OIDC/JWKS strategy is reserved for Tier 3 (§4.3.2).
- **The immutable request principal.** A request that passes identity produces an immutable request
  principal — installation, organization, branch, actor, role, capability scopes — that every later
  stage reads and none may mutate (§4.3.2).
- **The guard-stage rejection discipline.** Rejections from stages 2–4 are counted in an in-isolate
  tally flushed periodically to bucketed `platform_counter` rows, never journaled as requests and
  never one row per event (§4.3.12; §7.5).
- **The config-cache read discipline for the entitlement and kill-switch stage.** AI-enablement, plan
  tier, capability grant, and all four kill-switch scopes are evaluated from the config cache with no
  D1 read on a warm isolate (§4.3.3; §4.3.4).

Later slices may extend these (e.g. add the OIDC verifier strategy, add the admission stage) and may
not rewrite them (delivery plan §2.3).

### Consumes

- Slice **A2** freezes the diagnostic envelope: the §5.4 error taxonomy (codes, HTTP mappings,
  retryability, quota-consumption flags) and the error body carrying request reference, trace id, and
  retry-safety (A2 `Freezes`; delivery plan §3.2 row A2). B3 emits the §5.4 codes the guard stages own
  and does not redefine the taxonomy, the HTTP column, or the body shape.
- Slice **A5** freezes the platform D1 logical model (every §7.3 entity) and the config cache: an
  in-isolate memory map, short TTL, populated from D1 on a miss, holding installations, keys,
  entitlements, grants, kill switches, and the active routing policy (A5 `Freezes`; delivery plan
  §3.2 row A5). B3 reads installation keys, status, entitlements, grants, and kill switches through
  that cache and does not redefine its shape, its TTL, or its entities.
- Slice **A6** freezes the protocol adapter surface: the idempotency key, trace id, and version pin
  headers, and the translation of the internal error taxonomy to HTTP status codes (A6 `Freezes`;
  delivery plan §3.2 row A6). B3 receives the parsed request and emits taxonomy codes; the HTTP
  translation is the adapter's, not B3's.
- Slice **B1** freezes the AAT token contract (§5.6) — every claim, the `alg: EdDSA` JWS header, the
  `kid`-selected enrolled public key, and the server-side `scopes` derivation — and the installation
  keystore (B1 `Freezes`; delivery plan §3.3 row B1). B3 verifies that contract and does not redefine
  any claim or the signing mechanism.
- Slice **B2** freezes the installation-lifecycle state and the `installation` / `installation_key`
  / `entitlement` entities written on enroll and modified by suspend/resume/rotate/delete (B2
  `Freezes`; delivery plan §3.3 row B2). B3 reads the lifecycle state (`installation_suspended` is a
  guard rejection) and does not redefine the lifecycle surface.

Changing any consumed contract is out of scope by definition (delivery plan §2.3). B3's `Needs` cell
lists A5, B1, B2; A2 and A6 are transitive prerequisites of those.

### Open decisions relied on

- **Open Decision 3** — *Behaviour when the Quota DO is unavailable.* Recommended default: "Fail open
  with a capped grace allowance and reconciliation." B3 relies on the admission stage (B4) owning that
  behaviour; B3 does not itself contact the Quota DO and does not implement fail-open grace. The
  recommended default is assumed only insofar as B3 stays out of the admission stage entirely (§15 #3;
  §4.3.3).
- No other §15 decision is assumed. Replay/idempotency grace (Open Decision 3) is B4's concern, not
  B3's (delivery plan §3.3 row B3 "Replay rejection is explicitly out of scope here — it belongs to
  B4").

## Clarifications

### Session 2026-07-31

- Q: How are the guard stages 2–4 organised under `ai-platform/src/`? → A: Sibling modules
  `src/identity/` (verifier port + principal), `src/entitlement/` (entitlement + kill-switch
  evaluation), `src/rate-limit/` (composite-key limiter + counter flush) `[implementation choice — no §citation]`
- Q: How does identity read the installation's enrolled public key and status? → A: Through A5's
  shared `ConfigCache` via `loadConfig(cache, reader, "installations"|"keys", …)`, reusing the A5
  `D1Reader` spy seam; no identity-local reader `[implementation choice — no §citation]`
- Q: How is the `TokenVerifier` port shaped so `verifier_swap_changes_no_outcome` can substitute an
  impl? → A: `verify(token, ctx): Promise<VerifyResult>` with
  `VerifyResult = {ok:true; principal:Principal} | {ok:false; code:TaxonomyCode}`; OIDC is a second
  impl of the same interface `[implementation choice — no §citation]`
- Q: How do spy integration tests observe no `ai_request` row + bucketed `platform_counter`, given
  B3 stops before stage 9? → A: Integration tests run under `vitest.workers.config.ts` against the
  real Miniflare `DB` binding (B2's setup) for `ai_request` absence + `platform_counter` bucketing;
  rate-limit and warm-isolate no-D1-read cases use A5's `ReaderSpy` against the injected `D1Reader`
  `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Guard stages: identity, rate limiting, entitlement and kill switches (Priority: P1)

A requesting component submits an AI request to the gateway, and the guard stages 2–4 decide whether
the caller is authentic, whether the installation is entitled to this capability, and whether the
caller is within burst limits — all before any paid work and with the cheapest, most certain
rejection first. Identity verifies the AAT through the token verifier port (WebCrypto `Ed25519`,
`alg: EdDSA` so `none` and HMAC tokens are rejected), plus audience, expiry, and clock skew, and
produces an immutable request principal that every later stage reads and none may mutate; a suspended
installation is rejected. Rate limiting enforces all three composite keys. Entitlement and the four
kill-switch scopes are evaluated from the config cache with no D1 read on a warm isolate. Rejecting
an abusive request stays cheap: rejections increment bucketed `platform_counter` rows and are never
journaled as requests.

**Why this priority**: B3 is sequenced after A5, B1, and B2 (its `Needs`) because identity verifies
the AAT contract B1 froze, reads installation keys through the config cache A5 froze, and rejects
suspended installations whose lifecycle B2 owns; and it precedes B4 because the admission stage's
single Quota Durable Object round trip (stage 8) runs after identity, entitlement, and rate limiting
have already produced an immutable principal and a cheap rejection (delivery plan §3.3 row B3
`Needs` = A5, B1, B2; §6.1 stage order — "The ordering principle is cheapest and most certain
rejection first").

**Independent Test**: Provably complete by automated unit and integration (spy) tests that assert
each rejection code, the immutability of the principal, the three composite rate-limit keys tripping
independently, rejections incrementing `platform_counter` without creating an `ai_request` row, and
the warm-isolate zero-D1-read invariant (delivery plan §2.2; DP-3; §3.11.2 row B3).

**Acceptance Scenarios**:

1. **Given** a request bearing a valid `EdDSA` AAT signed by the installation's enrolled key, **When**
   identity runs, **Then** the token verifies through the verifier port and an immutable request
   principal (installation, organization, branch, actor, role, capability scopes) is produced for every
   later stage (§4.3.2; §4.2.1; §5.6; delivery plan §3.11.2 row B3).
2. **Given** a token whose header `alg` is anything other than `EdDSA` (in particular `none` or an
   HMAC algorithm), **When** identity runs, **Then** the request is rejected as `unauthenticated`
   because a verifier that accepts anything other than `EdDSA` is accepting a forgery (§5.6; §4.2.1;
   delivery plan §3.3 row B3).
3. **Given** a token with a bad signature, **When** identity runs, **Then** the request is rejected
   `unauthenticated` (delivery plan §3.11.2 row B3; §5.4).
4. **Given** a token with the wrong audience, **When** identity runs, **Then** the request is rejected
   (delivery plan §3.11.2 row B3; §4.3.2 "enforces audience").
5. **Given** an expired token, **When** identity runs, **Then** the request is rejected
   (delivery plan §3.11.2 row B3; §4.3.2 "enforces … expiry").
6. **Given** a not-yet-valid token inside the configured clock-skew tolerance, **When** identity runs,
   **Then** it is accepted (delivery plan §3.11.2 row B3 "not-yet-valid inside skew … accepted";
   §4.3.2 "clock skew tolerance").
7. **Given** a token outside the clock-skew tolerance, **When** identity runs, **Then** it is rejected
   (delivery plan §3.11.2 row B3 "outside skew"; §4.3.2).
8. **Given** a token from an unknown issuer, **When** identity runs, **Then** the request is rejected
   (delivery plan §3.11.2 row B3 "unknown issuer"; §4.3.2 "The key is selected by `iss` and `kid`").
9. **Given** a request whose caller is a suspended installation, **When** the guard runs, **Then** the
   request is rejected `installation_suspended` (delivery plan §3.11.2 row B3; §5.4; §6.1 stage 2).
10. **Given** a request principal produced by identity, **When** any later stage attempts to mutate it,
    **Then** the principal is immutable and the mutation is not observable to subsequent stages
    (delivery plan §3.11.2 row B3 "The principal cannot be mutated by a later stage"; §4.3.2).
11. **Given** the verifier port has been swapped to a different implementation of the same contract,
    **When** identity runs against the same tokens, **Then** every outcome is unchanged (delivery plan
    §3.11.2 row B3 "Swapping the verifier implementation changes no outcome"; §4.3.2).
12. **Given** a request that overflows the burst limit on the `installation` composite key, **When**
    rate limiting runs, **Then** it is rejected `rate_limited` with a `retry_after`, the matching
    `platform_counter` row is incremented with the correct dimensions, and no `ai_request` row is
    created (delivery plan §3.11.2 row B3; §4.3.3; §5.4).
13. **Given** a request that overflows the burst limit on the `installation+actor` key, **When** rate
    limiting runs, **Then** it is rejected `rate_limited` independently of the other two keys
    (delivery plan §3.11.2 row B3 "one case per composite key tripping independently"; §4.3.3).
14. **Given** a request that overflows the burst limit on the `installation+capability` key, **When**
    rate limiting runs, **Then** it is rejected `rate_limited` independently of the other two keys
    (delivery plan §3.11.2 row B3; §4.3.3).
15. **Given** a rate-limit rejection, **When** the in-isolate tally is flushed, **Then** counters are
    written bucketed by dimension and time bucket, never one row per event, and never journaled as a
    request (delivery plan §3.11.2 row B3 "counters flush bucketed, never one row per event";
    §4.3.12; §7.5).
16. **Given** an installation that is not AI-enabled, **When** entitlement runs, **Then** the request
    is rejected `forbidden_capability` — the stage-3 code for a non-suspended but unentitled
    installation (delivery plan §3.11.2 row B3 "AI-disabled installation"; §6.1 stage 3; §4.3.3; §5.4).
17. **Given** an installation whose plan tier is too low for the requested capability, **When**
    entitlement runs, **Then** the request is rejected `forbidden_capability` (delivery plan §3.11.2
    row B3 "plan tier too low"; §4.3.4 "the installation's plan-level allowances"; §6.1 stage 3; §5.4).
18. **Given** an installation to which the capability is not granted, **When** entitlement runs,
    **Then** the request is rejected `forbidden_capability` (delivery plan §3.11.2 row B3 "capability
    not granted"; §4.3.4 "a capability may be entitlement-gated"; §6.1 stage 3; §5.4).
19. **Given** the global kill switch is active, **When** entitlement runs, **Then** the request is
    rejected `capability_disabled` (delivery plan §3.11.2 row B3 "one case per kill-switch scope
    (global, capability, installation, provider)"; §4.3.4; §5.4).
20. **Given** the capability-scoped kill switch is active, **When** entitlement runs, **Then** the
    request is rejected `capability_disabled` (delivery plan §3.11.2 row B3; §4.3.4 "enforces kill
    switches"; §5.4).
21. **Given** the installation-scoped kill switch is active, **When** entitlement runs, **Then** the
    request is rejected `capability_disabled` (delivery plan §3.11.2 row B3; §4.3.4; §5.4).
22. **Given** the provider-scoped kill switch is active, **When** entitlement runs, **Then** the
    request is rejected `capability_disabled` (delivery plan §3.11.2 row B3; §4.3.4; §5.4).
23. **Given** a warm isolate with the config cache populated, **When** entitlement and the four
    kill-switch scopes are evaluated, **Then** the stages perform no D1 read (delivery plan §3.11.2
    row B3 "warm isolate performs no D1 read"; §4.3.3; §4.3.2) — *spy on the D1 binding and assert zero reads*.
24. **Given** a cold isolate, **When** identity loads installation public keys and status, **Then**
    the config cache performs exactly the same single same-region D1 read on a miss that A5 froze, and
    no additional read is introduced by B3 (§4.3.2 "a cold one pays a single same-region D1 read";
    A5 `Consumes`).

### Test plan

Every named test runs in CI on every change (§13.5). The layer designation is the one named in the
slice's row of delivery plan §3.11.2 ("Unit + integration (spy)").

| Test name | Layer | Asserts |
| --- | --- | --- |
| `identity_valid_token_accepted` | Unit | A valid `EdDSA` AAT verifies through the verifier port and yields an immutable principal (§3.11.2 row B3; §4.3.2; §4.2.1; §5.6) |
| `identity_rejects_non_eddsa_alg` | Unit | A token whose `alg` is `none` or an HMAC algorithm is rejected `unauthenticated` (§3.11.2 row B3; §5.6; §4.2.1) |
| `identity_rejects_bad_signature` | Unit | A bad-signature token is rejected `unauthenticated` (§3.11.2 row B3; §5.4) |
| `identity_rejects_wrong_audience` | Unit | A wrong-`aud` token is rejected (§3.11.2 row B3; §4.3.2) |
| `identity_rejects_expired_token` | Unit | An expired token is rejected (§3.11.2 row B3; §4.3.2) |
| `identity_accepts_notyetvalid_inside_skew` | Unit | A not-yet-valid token inside the configured skew tolerance is accepted (§3.11.2 row B3; §4.3.2) |
| `identity_rejects_outside_skew` | Unit | A token outside the skew tolerance is rejected (§3.11.2 row B3; §4.3.2) |
| `identity_rejects_unknown_issuer` | Unit | A token from an unknown `iss`/`kid` is rejected (§3.11.2 row B3; §4.3.2) |
| `identity_rejects_suspended_installation` | Integration | A suspended installation is rejected `installation_suspended` (§3.11.2 row B3; §5.4; §6.1 stage 2) |
| `principal_immutable_to_later_stage` | Unit (spy) | A later stage cannot mutate the request principal (§3.11.2 row B3; §4.3.2) |
| `verifier_swap_changes_no_outcome` | Unit | Swapping the verifier implementation changes no observable outcome (§3.11.2 row B3; §4.3.2) |
| `rate_limit_installation_key_trips` | Integration (spy) | Overflow on the `installation` key rejects `rate_limited` with `retry_after` and increments `platform_counter` (§3.11.2 row B3; §4.3.3; §5.4) |
| `rate_limit_installation_actor_key_trips` | Integration (spy) | Overflow on the `installation+actor` key trips independently (§3.11.2 row B3; §4.3.3) |
| `rate_limit_installation_capability_key_trips` | Integration (spy) | Overflow on the `installation+capability` key trips independently (§3.11.2 row B3; §4.3.3) |
| `rate_limit_rejection_no_ai_request_row` | Integration (spy) | A rate-limit rejection creates no `ai_request` row (§3.11.2 row B3 "no `ai_request` row created on rejection"; §7.5; §6.1 stage 9) |
| `rate_limit_counters_flush_bucketed` | Integration (spy) | Counters flush bucketed by dimension and time bucket, never one row per event (§3.11.2 row B3; §4.3.12; §7.5) |
| `entitlement_ai_disabled_installation_rejected` | Integration | An AI-disabled installation is rejected (§3.11.2 row B3; §4.3.3; §6.1 stage 3) |
| `entitlement_plan_tier_too_low_rejected` | Integration | A too-low plan tier is rejected `forbidden_capability` (§3.11.2 row B3; §4.3.4; §5.4) |
| `entitlement_capability_not_granted_rejected` | Integration | A capability not granted to the installation is rejected `forbidden_capability` (§3.11.2 row B3; §4.3.4; §5.4) |
| `kill_switch_global_rejected` | Integration | The global kill switch rejects `capability_disabled` (§3.11.2 row B3 "one case per kill-switch scope (global, capability, installation, provider)"; §4.3.4; §5.4) |
| `kill_switch_capability_rejected` | Integration | The capability-scoped kill switch rejects `capability_disabled` (§3.11.2 row B3; §4.3.4; §5.4) |
| `kill_switch_installation_rejected` | Integration | The installation kill switch rejects `capability_disabled` (§3.11.2 row B3; §4.3.4; §5.4) |
| `kill_switch_provider_rejected` | Integration | The provider kill switch rejects `capability_disabled` (§3.11.2 row B3; §4.3.4; §5.4) |
| `entitlement_warm_isolate_no_d1_read` | Integration (spy) | A warm isolate performs zero D1 reads for entitlement and all four kill-switch scopes (§3.11.2 row B3; §4.3.3; §4.3.2) |

### Edge Cases

- **Every error code B3 can emit.** The guard stages 2–4 own these taxonomy codes: `unauthenticated`
  (HTTP 401, stage 2), `installation_suspended` (HTTP 403, stages 2 and 3), `forbidden_capability`
  (HTTP 403, stage 3), `rate_limited` (HTTP 429, stage 4, carrying `retry_after`), and
  `capability_disabled` (HTTP 503, the kill-switch rejection). The HTTP status is normative and is
  applied by the protocol adapter (A6), not by B3; B3 emits the taxonomy code, which is what clients
  branch on (§5.4; §4.3.1). No other code is emitted by stages 2–4.
- **`alg` not negotiable per token.** A token whose header `alg` is not `EdDSA` is a forgery and is
  rejected `unauthenticated`; accepting `none` or an HMAC algorithm is explicitly forbidden (§5.6;
  §4.2.1).
- **Clock-skew boundary.** A not-yet-valid token inside the configured skew tolerance is accepted; a
  token outside the tolerance is rejected. The tolerance value itself is a config-cache property frozen
  by A5; B3 enforces the boundary and does not invent the value (§4.3.2; A5 `Freezes`).
- **`scopes` never caller-supplied.** `scopes` are derived server-side from RBAC and are never supplied
  by the client; a caller attempting to supply them cannot affect the principal (§5.6; B1 `Freezes`).
  B3 reads them from the verified token and does not re-derive them.
- **Replay is out of scope.** `jti` replay rejection is explicitly out of scope for B3 and belongs to
  B4, where it is checked inside the single Quota Durable Object round trip and costs nothing extra
  (delivery plan §3.3 row B3; §4.3.2 "Replay rejection is not part of this stage's own I/O"; §4.3.3).
  B3 does not implement, pre-check, or short-circuit replay.
- **Suspended installation.** A suspended installation is rejected, and the rejection is a guard
  rejection — counted in `platform_counter`, never journaled as a request (§6.1 stage 2; §7.5;
  delivery plan §3.11.2 row B3).
- **Warm vs cold isolate.** On a warm isolate the entitlement and kill-switch evaluation performs no
  D1 read; on a cold isolate the config cache pays a single same-region D1 read on a miss (the
  invariant A5 froze). B3 introduces no additional read (§4.3.2; §4.3.3; A5 `Freezes`).
- **Verifier port substitution.** The port has two strategies and only the enrolled-key strategy is
  built now; the OIDC/JWKS strategy is reserved for Tier 3 and is not implemented (§4.3.2). Swapping the
  implementation must change no outcome (delivery plan §3.11.2 row B3).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Identity (§6.1 stage 2) MUST verify the AAT through the verifier port using WebCrypto
  `Ed25519`, with `alg` pinned to `EdDSA` so that `none` and any HMAC algorithm are rejected, and MUST
  verify audience, expiry, and clock-skew tolerance (§4.3.2; §4.2.1; §5.6; delivery plan §3.3 row B3).
- **FR-002**: The enrolled-key strategy MUST select the verification key by `iss` and `kid` against
  the installation's enrolled 32-byte public key read through the config cache, with no network call
  involved; the OIDC/JWKS strategy is reserved for Tier 3 and is not built (§4.3.2; §4.2.1).
- **FR-003**: Identity MUST reject an unauthentic, wrong-audience, expired, out-of-skew, or
  unknown-issuer token as `unauthenticated`, and MUST accept a not-yet-valid token that is inside the
  configured clock-skew tolerance (§4.3.2; §5.4; §5.6; delivery plan §3.11.2 row B3).
- **FR-004**: A request that passes identity MUST produce an immutable request principal —
  installation, organization, branch, actor, role, capability scopes — that every later stage reads
  and none may mutate (§4.3.2; delivery plan §3.11.2 row B3).
- **FR-005**: A suspended installation MUST be rejected as `installation_suspended` (§6.1 stage 2;
  §5.4; B2 `Freezes`; delivery plan §3.3 row B3).
- **FR-006**: Rate limiting (§6.1 stage 4) MUST enforce all three composite keys — `installation`,
  `installation+actor`, and `installation+capability` — using the Rate Limiting binding, approximate
  and eventually consistent by design (§4.3.3; delivery plan §3.3 row B3).
- **FR-007**: A rate-limit rejection MUST return `rate_limited` (HTTP 429) carrying `retry_after` and
  MUST consume no quota (§5.4; delivery plan §3.11.2 row B3).
- **FR-008**: Entitlement (§6.1 stage 3) MUST evaluate AI-enablement, plan tier, and capability grant
  for the installation against the manifest's plan-level allowances, rejecting a non-suspended but
  unentitled installation as `forbidden_capability` (the only stage-3 code other than
  `installation_suspended`) (§4.3.3; §4.3.4; §5.4; §6.1 stage 3; delivery plan §3.11.2 row B3).
- **FR-009**: The guard MUST enforce all four kill-switch scopes — global, per capability, per
  installation, per provider — from the config cache, rejecting a killed request as
  `capability_disabled` (§4.3.4; §5.4; delivery plan §3.3 row B3; delivery plan §3.11.2 row B3).
- **FR-010**: Entitlement and kill-switch evaluation MUST be answered from the config cache with no D1
  read on a warm isolate; a cold isolate pays only the single same-region D1 read on a miss that A5
  froze (§4.3.2; §4.3.3; A5 `Freezes`; delivery plan §3.11.2 row B3).
- **FR-011**: Guard rejections from stages 2–4 MUST be counted in an in-isolate tally flushed
  periodically to a small, bounded, low-cardinality `platform_counter` table keyed by dimension and
  time bucket, never one row per event (§4.3.12; §7.5; delivery plan §3.3 row B3; delivery plan
  §3.11.2 row B3).
- **FR-012**: Guard rejections MUST NOT be journaled as requests; no `ai_request` row is created on a
  guard rejection (the journal is written at stage 9, after the guard), so refusing abuse stays cheap
  (§6.1 stage 9; §7.5; delivery plan §3.11.2 row B3).
- **FR-013**: Stages 2–4 MUST run in the order identity → entitlement → rate limit, because the
  ordering principle is cheapest and most certain rejection first, and validating context before
  authenticating would let an unauthenticated caller consume CPU (§6.1; delivery plan §3.3 row B3
  "§6.1 stages 2–4").
- **FR-014**: Replay (`jti` freshness) and idempotency MUST NOT be implemented in B3; they are owned by
  the admission stage (B4) inside the single Quota Durable Object round trip (§4.3.2; §4.3.3; delivery
  plan §3.3 row B3 "Replay rejection is explicitly out of scope here — it belongs to B4").

### Key Entities *(include if feature involves data)*

Not applicable — this slice defines no entities. It reads `installation`, `installation_key`,
`entitlement`, grants, and kill switches through the config cache frozen by A5 (§7.3; A5 `Freezes`)
and writes only bucketed `platform_counter` rows whose shape is fixed by §4.3.12 / §7.5. Their
shapes and names are consumed unchanged.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: The guard is the cheap-rejection path that protects a clinic-scale tenant boundary
  (the installation) from abuse without enterprise machinery. At clinic scale the entire config set is a
  few kilobytes, so a warm isolate answers in nanoseconds and rejecting an abusive request is nearly
  free (§4.3.2; §14). No per-request state, no queues, no second metrics store are introduced
  (§4.3.12; §7.5).
- **Layer Placement**: This slice touches `ai-platform/` (the Cloudflare Worker guard) only. Identity
  verifies tokens held by the Worker, rate limiting uses the Worker's Rate Limiting binding, and
  entitlement/kill-switch reads are from the Worker's config cache over the platform's own D1. It does
  not touch `backend/` (Supabase) — the clinic-side signing and keystore belong to B1, and the
  installation lifecycle belongs to B2 — and it does not touch `frontend/` (Flutter). Per §14, the
  gateway is a non-primary, additive component: *"no domain logic, no business data, no write path into
  Supabase, always optional."* The guard never writes to the clinic database.
- **Data Integrity & Security**: Every request is authenticated, audience-scoped, and installation-scoped
  by a named, verifiable mechanism — an Ed25519 AAT signed in the clinic database and verified against
  an enrolled public key (§4.2.1; §14 "IV"). Defense in depth runs through token scopes, entitlement,
  capability gating, and kill switches (§4.3.2; §4.3.3; §4.3.4). Tenant isolation is enforced by
  installation-scoped tokens and installation-scoped composite rate-limit keys (§4.3.3; §14 "III.
  Tenant isolation"). The principal is immutable to later stages, so no downstream component can
  escalate scope (§4.3.2).
- **Failure Handling**: A guard rejection degrades to a typed, actionable error carrying the request
  reference, trace id, and retry-safety, never to an opaque failure (§5.4). Quota exhaustion is owned
  by B4 and the constitution principle V guarantee (never hard-lock) is implemented there; B3 owns
  only the rate-limit and entitlement/kill-switch rejections, which are advisory and never block
  clinical work (§14 "V"; delivery plan §3.7 row F4). The platform is strictly additive: an unreachable or refusing guard
  surfaces as "AI unavailable", and the client hides affordances (§14; A11).

## Out of Scope

- **Replay rejection and idempotency** (`jti` freshness, idempotency-key novelty) are explicitly out
  of scope and belong to B4's admission stage, where they ride along the single Quota Durable Object
  round trip (delivery plan §3.3 row B3; §4.3.2; §4.3.3).
- **Quota, concurrency, and cost ceiling.** The per-installation Quota Durable Object (budget
  remaining, concurrency headroom), the credit-after-call accounting, and the cost-ceiling pre-flight
  (§6.1 stage 7, `request_too_large`) are B4 and C2 respectively, not B3 (§4.3.3; §6.1 stages 7–8).
- **Capability manifest resolution.** Resolving `capability id + requested version` to an immutable
  manifest honouring the client's version pin, and the `capability_unknown` / `capability_retired`
  rejections, are slice C1 (§4.3.4; delivery plan §3.4 row C1). B3 evaluates only the kill-switch and
  entitlement-gate aspects of §4.3.4 that are read from the config cache; the manifest lookup itself
  is not built here.
- **Soft-threshold degraded routing** (crossing a soft quota threshold to downgrade to a cheaper
  model) is F4 (§4.3.3; delivery plan §3.7 row F4).
- **The OIDC / JWKS verifier strategy** is reserved for Tier 3 and is not built; only the
  enrolled-installation-key strategy is implemented (§4.3.2).
- **Token contract rotation with overlapping acceptance** (two `ver` values accepted) is J4
  (delivery plan §3.9 row J4).
- **Entitlement management** (assigning plan, quota, budget, capabilities, period bounds, soft
  threshold — i.e. writing the economics that B3 reads) is not implemented here; B2 only creates the
  `pending`, empty `entitlement` row on enroll, and assigning the economics is a later control-plane
  function (delivery plan §3.3 row B2; B2 `Freezes`).
- **HTTP status translation.** Mapping taxonomy codes to HTTP statuses is the protocol adapter's job
  (A6, §4.3.1; §5.4); B3 emits taxonomy codes and does not apply the HTTP column itself.

Prohibitions inherited from delivery plan §6.4, copied verbatim:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — not applicable
  here, as B3 touches neither the client nor prompts, but the prohibition is inherited.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A valid `EdDSA` AAT verifies through the verifier port and produces an immutable request
  principal that no later stage can mutate (delivery plan §3.3 row B3 "Done when"; §3.11.2 row B3;
  §4.3.2).
- **SC-002**: A token whose `alg` is not `EdDSA` (in particular `none` or an HMAC algorithm), and a
  token with a bad signature, wrong audience, expired, outside skew, or unknown issuer, is rejected
  `unauthenticated`; a not-yet-valid token inside the skew tolerance is accepted (delivery plan §3.3
  row B3; §3.11.2 row B3; §5.6; §4.3.2).
- **SC-003**: A suspended installation is rejected `installation_suspended` (delivery plan §3.3 row
  B3; §3.11.2 row B3; §5.4).
- **SC-004**: All three composite rate-limit keys (`installation`, `installation+actor`,
  `installation+capability`) trip independently, returning `rate_limited` with `retry_after`, and a
  rate-limit rejection creates no `ai_request` row (delivery plan §3.11.2 row B3; §4.3.3; §7.5).
- **SC-005**: AI-disablement, too-low plan tier, and an ungranted capability are rejected
  `forbidden_capability` (the only stage-3 code other than `installation_suspended`, which a
  non-suspended but unentitled installation is not); all four kill-switch scopes are rejected
  `capability_disabled` (delivery plan §3.11.2 row B3; §6.1 stage 3; §4.3.3; §4.3.4; §5.4).
- **SC-006**: Entitlement and all four kill-switch scopes are evaluated from the config cache with zero
  D1 reads on a warm isolate (delivery plan §3.11.2 row B3; §4.3.3; §4.3.2).
- **SC-007**: Guard rejections are counted in bucketed `platform_counter` rows and are never journaled
  as requests and never written as one row per event (delivery plan §3.3 row B3; §3.11.2 row B3;
  §4.3.12; §7.5).

## Assumptions

- The AAT token contract (§5.6), the `alg: EdDSA` JWS header, and the `kid`-selected enrolled public
  key are frozen by B1, and the clinic-side signing mechanism (§4.2.1) is fixed; B3 consumes the
  contract and defines neither the signing nor the claim set (B1 `Freezes`).
- The config cache — an in-isolate memory map with a short TTL, populated from D1 on a miss, holding
  installations, keys, entitlements, grants, kill switches, and the active routing policy — is frozen
  by A5; B3 reads through it and owns no cache of its own (A5 `Freezes`; §4.3.2).
- The installation lifecycle (`installation`, `installation_key`, `entitlement` rows and their
  suspend/resume/rotate/delete state) is owned by B2; B3 reads lifecycle status through the config
  cache and does not write it (B2 `Freezes`; delivery plan §3.3 row B2; §4.3.2).
- The diagnostic envelope — the §5.4 error taxonomy with its normative HTTP column, retryability, and
  quota-consumption flags, and the error body carrying request reference, trace id, and retry-safety —
  is frozen by A2, and the HTTP translation is applied by the protocol adapter A6; B3 emits taxonomy
  codes and relies on that envelope (A2 `Freezes`; A6 `Freezes`; §4.3.1; §5.4).
- The clock-skew tolerance is a config-cache property frozen by A5; B3 enforces the boundary against
  the configured value and does not choose or invent it (§4.3.2; A5 `Freezes`).
- The Rate Limiting binding is a Worker primitive whose composite-key interface is fixed by the
  platform; B3 uses it for the three named keys and adds no fourth key (§4.3.3).