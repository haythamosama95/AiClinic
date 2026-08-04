# Feature Specification: `context_required` self-healing round trip

**Feature Branch**: `ai/049-j2-context-required-self-healing`

**Created**: 2026-08-03

**Status**: Draft

**Input**: Slice `J2` — "`context_required` self-healing round trip" (delivery plan §3.9, band J).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.9, row J2):

> §8.4, §5.2

### Freezes

Contracts this slice establishes for the first time:

- **One automatic `context_required` self-healing round trip for `single_shot`
  capabilities**: when a client with a stale manifest cache submits without a required
  key, receives `context_required` with the missing-key manifest, refreshes its
  manifest cache, resolves the newly required keys, and resubmits **once** with the
  **same idempotency key**, the request proceeds through the normal pipeline on
  success (§8.4; §5.2 Self-healing).
- **The one-resubmission bound**: automatic self-healing is bounded to one
  resubmission. A second `context_required` on that action is treated as a real defect
  and is surfaced to the user with the request reference; there is no automatic third
  attempt (§8.4).
- **Conversational exclusion**: this self-healing path applies to `single_shot`
  capabilities only. Conversational capabilities never take this path; their distinct
  context-negotiation flow is out of scope here (§8.4; §5.2 Self-healing vs
  Negotiation; delivery plan §3.9).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (C2, E2, E3). Changing any is out of scope by
definition:

- **From C2 (context validator stage and cost pre-flight)**: the **`context_required`
  rejection payload** — the missing-key manifest (missing required keys with declared
  shapes, plus manifest version) that enables the client handshake (§8.4; C2 Freezes).
  J2 wires the client self-healing *behaviour* against that payload; it does not
  redefine validator rules, `context_invalid`, cost pre-flight, or the payload shape
  (C2 Freezes; delivery plan §3.4 C2 / DP-5).
- **From E2 (AI Client SDK)**: the **SDK submit path**, **stable client-generated
  idempotency key** for a single user action, **SSE / terminal-state surfacing**, and
  **request-reference retention** (E2 Freezes). E2 explicitly deferred automatic
  `context_required` refresh-and-resubmit to J2 and surfaces that code without
  auto-resubmitting (E2 Out of Scope / edge cases). J2 extends the SDK with the single
  named self-healing path §8.4 requires; it does not rewrite AAT acquire/cache, the
  `unauthenticated` re-mint path, general no-auto-retry for other taxonomy codes, or
  SSE framing (E2 Freezes; delivery plan §2.3).
- **From E3 (Context Resolver registry, first context RPC, and client contract test)**:
  the **generic key-list Context Resolver** that assembles a payload from named keys
  under the caller's RLS, with no capability-id branching (E3 Freezes; §5.2
  Authorization / Direction). J2 resolves the keys named by `context_required` through
  that Resolver; it does not redefine the registry API, screen-scoped cache, or
  provider RPCs (E3 Freezes; E3 Out of Scope naming J2).

### Open decisions relied on

None. This slice assumes no §15 recommended default; §8.4 and §5.2 fully specify the
self-healing bound and `single_shot`-only applicability.

## Clarifications

### Session 2026-08-03

- Q: Where should the §8.4 `context_required` self-healing orchestration live under the Flutter AI client library? → A: Sibling module under `frontend/lib/core/ai/` composing SDK + Resolver + refresh; `AiClientSdk` stays transport-only `[implementation choice — no §citation]`
- Q: How should the C2 `context_required` missing-key manifest reach the self-healing path after the HTTP 422? → A: Extend `PlatformHttpException` with optional C2 fields (`missing_keys`, `shapes`, `manifest_version`, `manifest_capability_id`) when `code` is `context_required` `[implementation choice — no §citation]`
- Q: How should the FR-003 manifest-cache refresh step be owned under the Flutter AI client? → A: Injectable `ManifestRefreshPort` that the heal helper calls once; tests spy the call; production wires to C1 discovery revalidation `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - `context_required` self-healing round trip (Priority: P1)

A Flutter client whose cached capability manifest is stale relative to the platform
submits a `single_shot` request missing a newly required context key. The platform
rejects with `context_required` carrying the missing-key manifest. The client refreshes
its manifest cache, resolves the named keys through the Context Resolver, and
resubmits **once** with the same idempotency key. On success the request continues
through the normal pipeline. If a second `context_required` arrives for that action,
the client stops, surfaces the request reference to the user, and does not attempt a
third automatic resubmission. Conversational capabilities never enter this path.

**Why this priority**: J2 has `Needs: C2, E2, E3` (delivery plan §3.9). C2 must already
emit `context_required` with the missing-key manifest; E2 must already submit with a
stable idempotency key and surface terminal taxonomy outcomes; E3 must already resolve
named keys into a context payload. Band J defers this client behaviour until a client's
manifest cache can be stale relative to the platform (delivery plan §3.9 Build when;
DP-5).

**Independent Test**: A client receiving `context_required` refreshes its manifest,
resolves the named keys, and resubmits **once** with the same idempotency key; a second
`context_required` surfaces to the user with the request reference (the slice's
`Done when` cell; delivery plan §2.2; DP-3).

**Acceptance Scenarios**:

1. **Given** a `single_shot` client whose manifest cache is stale so a required key is
   missing from the submitted context, **When** the platform returns `context_required`
   with the missing-key manifest, **Then** the client refreshes its manifest cache,
   resolves the named keys, resubmits **once** with the **same idempotency key**, and
   the resubmission succeeds through the normal pipeline (§8.4; §5.2 Self-healing;
   delivery plan §3.11.8 J2).
2. **Given** the same self-healing path has already performed its one automatic
   resubmission, **When** the platform returns `context_required` again for that
   action, **Then** the client stops automatic recovery and surfaces the request
   reference to the user (§8.4; delivery plan §3.11.8 J2).
3. **Given** a second `context_required` has already stopped the self-healing path,
   **When** no further user action has been taken, **Then** the client performs **no
   automatic third attempt** (§8.4; delivery plan §3.11.8 J2).
4. **Given** a capability with `interaction_mode: conversational`, **When** a context
   gap arises during a turn, **Then** the client never takes the §8.4
   `context_required` self-healing path (conversational negotiation remains out of
   scope for this slice) (§8.4; §5.2 Negotiation; delivery plan §3.9; §3.11.8 J2).

### Test plan

Layer names are from the testing-strategy table in §13.5. The slice's required layer is
**Flutter integration** (delivery plan §3.11.8). The suite runs in the Flutter test
suite against the AI Client SDK and Context Resolver; the closest §13.5 client-side
layers are **Client contract tests** (Flutter suite against live/fetched manifests and
key resolution) exercised together with SDK integration behaviour.

| #   | Test                                                                                                                      | §13.5 layer / delivery layer                          |
| --- | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| 1   | Stale client receiving `context_required` refreshes, resolves, resubmits once with the same idempotency key, and succeeds | Flutter integration (Client contract tests / SDK)     |
| 2   | A second `context_required` stops automatic recovery and surfaces the request reference                                   | Flutter integration (Client contract tests / SDK)     |
| 3   | No automatic third attempt after the second `context_required`                                                            | Flutter integration (Client contract tests / SDK)     |
| 4   | Conversational capabilities never take the §8.4 self-healing path                                                         | Flutter integration (Client contract tests / SDK)     |

### Edge Cases

- **Error code this slice consumes (does not redefine)**: `context_required` — typed,
  data-carrying rejection with the missing-key manifest; client behaviour is resolve
  and resubmit once (§8.4; §5.2 Self-healing; C2 Freezes for the payload).
- **Boundary: one automatic resubmission only**: the first `context_required` may
  trigger refresh → resolve → resubmit with the same idempotency key; a second
  `context_required` for that action is a real defect and must surface to the user with
  the request reference (§8.4).
- **Boundary: no automatic third attempt**: after the second `context_required`, the
  client must not loop (§8.4; delivery plan §3.11.8 J2).
- **Boundary: same idempotency key on resubmit**: the self-healing resubmission MUST
  reuse the original action's idempotency key, not mint a new one (§8.4; E2 Freezes for
  key stability across the action).
- **Boundary: `single_shot` only**: conversational capabilities MUST NOT enter this
  path; §5.2 Negotiation / §8.10 remain out of scope (§8.4; §5.2; delivery plan §3.9).
- **Failure branch: second `context_required` is user-visible**: the request reference
  MUST be shown so support can look the defect up; silent swallow or opaque failure is
  forbidden (§8.4).
- **Inherited prohibition: no per-request server-side state** holding a "healing
  session" on the gateway — recovery is entirely client-driven from the typed rejection
  (§4.4, §9.7; delivery plan §6.4; §8.4 sequence).
- **Inherited prohibition: no prompt text, provider name, or model identifier in the
  Flutter client** while implementing the refresh/resolve/resubmit path (R-12; delivery
  plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Self-healing for missing required context MUST apply to `single_shot`
  capabilities only (§8.4; §5.2 Self-healing).
- **FR-002**: When a client submits without a required key because its manifest cache is
  stale, the platform's `context_required` rejection (missing keys + shapes, manifest
  version) MUST drive client recovery rather than a hard opaque failure (§8.4; §5.2
  Self-healing; C2 Freezes).
- **FR-003**: On receiving `context_required`, the client MUST refresh its manifest
  cache (§8.4).
- **FR-004**: After refreshing, the client MUST resolve the newly required keys named by
  the missing-key manifest through the existing Context Resolver (§8.4; §5.2 Direction /
  Authorization; E3 Freezes).
- **FR-005**: The client MUST resubmit **once** with the **same idempotency key** after
  resolving those keys (§8.4; E2 Freezes).
- **FR-006**: Automatic self-healing MUST be bounded to one resubmission; a second
  `context_required` for that action MUST surface to the user with the request reference
  (§8.4).
- **FR-007**: After a second `context_required`, the client MUST NOT attempt a third
  automatic resubmission (§8.4; delivery plan §3.11.8 J2).
- **FR-008**: Conversational capabilities MUST NEVER take the §8.4
  `context_required` self-healing path (§8.4; §5.2 Negotiation; delivery plan §3.9).

### Key Entities

Not applicable — this slice defines no entities.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Desktop clients cache manifests and update on clinic cadence; a stale
  cache must recover in one round trip so clinic staff are not blocked by opaque context
  failures when the platform has added a required key (A12; §8.4). No enterprise client
  fleet management is introduced (constitution principle I).
- **Layer Placement**: This slice touches **`frontend/`** (Flutter) — the AI Client SDK
  self-healing path and its use of the Context Resolver. It does not add gateway stages,
  D1 entities, or Supabase domain RPCs; those remain C2 / E3. The gateway remains a
  non-primary, additive component where it already emits `context_required` (C2); this
  slice does not expand that role (§14, item 1).
- **Data Integrity & Security**: Key resolution continues under the caller's own
  Supabase permissions and RLS via E3's ordinary read path; the platform does not pull
  clinic data (§5.2 Direction / Authorization; §8.4). No new dual-write or soft-delete
  surface is introduced.
- **Failure Handling**: First `context_required` recovers automatically once; a second
  surfaces the request reference for support rather than looping or failing opaquely
  (§8.4). Conversational flows are excluded. Platform or AI unavailability remains
  additive: clinical work continues without AI affordances (constitution principle V).

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **C2** — context validator, `context_required` / `context_invalid` emission, cost
  pre-flight. Consumed for the rejection payload only; validator and pre-flight are not
  redefined.
- **E2** — AAT acquire/cache, general taxonomy no-auto-retry (other than the named
  `context_required` self-heal this slice freezes), SSE consumption, cancel, last-N
  references. Consumed; not rewritten.
- **E3** — Context Resolver registry API, first context provider RPC, client contract
  test that every declared key is resolvable. Consumed for resolve-by-key-list; not
  redefined.
- **E4** — First AI feature surface, provisional-draft UX, degraded mode for
  non-enrollment / unreachability (beyond surfacing the request reference on the second
  `context_required`).
- **H1 / H2 / H3 / §8.10** — conversational `context_requested` negotiation, transcript
  handling, and chat surface. Explicitly excluded by §8.4 and delivery plan §3.9.
- **J1** — capability deprecation and overlap window.
- **J3** — staged rollout and canary cohorts.
- **J4** — token contract rotation with overlapping `ver` acceptance.
- **Platform-side fetching of missing clinic context** — impossible and undesirable
  (§8.4 citing §1.3.1 / §9.4); not introduced here.

Prohibitions (delivery plan §6.4), none of which this slice introduces:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional
  content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A stale `single_shot` client that receives `context_required` refreshes,
  resolves the named keys, resubmits once with the same idempotency key, and succeeds
  (asserted by test 1; Done when).
- **SC-002**: A second `context_required` for that action stops automatic recovery and
  surfaces the request reference to the user (asserted by test 2; Done when).
- **SC-003**: No automatic third attempt occurs after the second `context_required`
  (asserted by test 3; delivery plan §3.11.8 J2).
- **SC-004**: Conversational capabilities never take the §8.4 self-healing path
  (asserted by test 4; delivery plan §3.9 / §3.11.8 J2).

## Assumptions

- C2, E2, and E3 are complete on the integration line this slice branches from
  (`Needs: C2, E2, E3`).
- C2 already freezes and emits the `context_required` missing-key manifest payload; J2
  does not change that payload (C2 Freezes; DP-5).
- E2 already submits with a stable idempotency key and surfaces `context_required`
  without auto-resubmitting; J2 adds only the deferred self-healing behaviour (E2 Freezes /
  Out of Scope).
- E3 already resolves a key list into a context payload under caller RLS with no
  capability branching (E3 Freezes).
- Spec Kit's `create-new-feature.sh --dry-run` allocates against `docs/specs/` and does
  not parse `ai/<NNN>-*` branches, so the number was confirmed from `specs/` (highest
  `048-capability-deprecation`) and applied as **049**.
- Build-when trigger ("a client's manifest cache can be stale relative to the platform")
  is an ordering/trigger condition from delivery plan §3.9, not a product gate encoded
  as runtime configuration in this slice.
