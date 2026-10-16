# Feature Specification: Capability deprecation and the overlap window

**Feature Branch**: `ai/048-j1-capability-deprecation`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `J1` — "Capability deprecation and the overlap window" (delivery plan §3.9, band J).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.9, row J1):

> §5.7, §12.4, A12

### Freezes

Contracts this slice establishes for the first time:

- **Deprecation announced through discovery with a successor before retirement is
  enforced**: when a capability version is marked deprecated, discovery surfaces that
  deprecation together with its successor; retirement is not enforced until after that
  announcement path has been used (§5.7; §12.4 Retire a capability).
- **The overlap window during which a deprecated version remains servable**: a
  deprecated capability version keeps serving for the configured overlap window; old
  clients that still pin that version continue to work for that defined period (§5.7;
  A12; §15 Open Decision 9 recommended default).
- **Retirement → `capability_retired`**: after the overlap window, retiring the version
  causes the same pinned request to return `capability_retired` so old clients prompt
  for an update instead of failing opaquely (§12.4 Retire a capability; A12).
- **Overlap window length default**: two client release cycles, minimum 90 days
  (§15 Open Decision 9; A12).
- **The lifecycle overlay as the durable record of a lifecycle transition**: deprecate and retire
  persist to the capability version's `global`-scope `capability_grant` row rather than to the
  manifest, and the effective lifecycle is the manifest's published value overridden by that overlay
  (§5.1; §7.3; §4.5 Capability availability).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (C1, B2). Changing any is out of scope by
definition:

- **From C1 (capability registry, resolver stage, and discovery endpoint)**: the
  **capability-registry lookup** (id + requested version → one immutable manifest
  honouring the client's pin); the **three resolver error conditions**
  (`capability_unknown`, `capability_retired`, `capability_disabled`); the rule that a
  **`deprecated` lifecycle state is not a rejection** (C1 serves it with no overlap
  window); and the **discovery** surface for an installation and plan (C1 Freezes). J1
  adds successor announcement through discovery and the overlap-window / retirement
  behaviour C1 explicitly deferred; it does not redefine registry lookup, the three
  taxonomy codes, manifest immutability, or kill-switch rejection (C1 Freezes; C1 Out
  of Scope naming J1 for window and successor announcement).
- **From B2 (control-plane enrollment and installation lifecycle)**: the **control-plane
  surface** separately authenticated by operator identity (not clinic identity), and the
  **control-audit rule** that every control-plane mutation is journaled with the
  operator identity as a `control_audit` row (B2 Freezes). J1 applies that audit rule to
  the deprecate / retire mutations that enact §12.4; it does not redefine enrollment,
  key rotation, suspend, resume, delete, or the `control_audit` shape (B2 Freezes).

### Open decisions relied on

- **Open Decision 9** (Capability version overlap window length): recommended default is
  two client release cycles, minimum 90 days (A12). J1 assumes that default as the
  configured overlap window length (§15 OD-9; A12; §5.7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capability deprecation and the overlap window (Priority: P1)

An operator deprecates a capability version and announces a successor through discovery
before retirement is enforced. During the configured overlap window, clients that still
pin the deprecated version keep being served. After retirement, the same pinned request
returns `capability_retired` so old clients prompt for an update instead of failing
opaquely. The retire mutation is journaled with the operator identity under the
control-plane audit rule B2 already froze.

**Why this priority**: J1 has `Needs: C1, B2` (delivery plan §3.9). C1 must already
resolve and discover capability versions (including recognising `deprecated` without a
window and emitting `capability_retired` for `retired`), and B2 must already provide the
operator-authenticated control plane and `control_audit` journaling. Band J defers this
behaviour until a client version exists in the field that a capability change could
break (delivery plan §3.9 Build when; DP-5).

**Independent Test**: Discovery announces deprecation with a successor before retirement
is enforced; a deprecated version keeps serving for the configured window; retirement
returns `capability_retired` so old clients prompt for an update (the slice's `Done when`
cell; delivery plan §2.2; DP-3).

**Acceptance Scenarios**:

1. **Given** an operator deprecates a capability version and names its successor,
   **When** discovery is fetched for an installation that is entitled to that capability,
   **Then** discovery marks the version as deprecated and includes its successor
   (§12.4; §5.7; delivery plan §3.11.8 J1).
2. **Given** a capability version that is deprecated and still inside the configured
   overlap window, and a client that pins that version, **When** the client submits a
   request for that pin, **Then** the deprecated version is still served (§5.7; A12;
   §12.4; delivery plan §3.11.8 J1).
3. **Given** the same capability version after it has been retired, and a client that
   still pins that version, **When** the client submits the same request, **Then** the
   platform returns `capability_retired` so the client can prompt for an app update
   (§12.4; A12; delivery plan §3.11.8 J1).
4. **Given** an operator retires a capability version, **When** the retire control-plane
   mutation completes, **Then** the retirement is journaled with that operator identity
   as a `control_audit` row (B2 Freezes applied to the §12.4 retire path; delivery plan
   §3.11.8 J1).

### Test plan

Layer names are from the testing-strategy table in §13.5. The slice's required layer is
**Integration** (delivery plan §3.11.8); the closest §13.5 layer is **Pipeline tests**
(stage ordering and guard rejection paths — retirement rejection at capability resolve).

| #   | Test                                                                                         | §13.5 layer    |
| --- | -------------------------------------------------------------------------------------------- | -------------- |
| 1   | Discovery marks a deprecated version with its successor                                      | Pipeline tests |
| 2   | A deprecated version still serves inside the overlap window                                  | Pipeline tests |
| 3   | After retirement the same pinned request returns `capability_retired`                        | Pipeline tests |
| 4   | Retirement is journaled with the operator identity (`control_audit`)                         | Pipeline tests |
| 5   | A lifecycle transition survives a cold isolate: discovery and resolve read it from the `capability_grant` overlay via the config cache, and the manifest is unchanged | Pipeline tests |
| 6   | Deprecate after retire is rejected; duplicate deprecate same successor is idempotent; different successor is rejected | Pipeline tests |
| 7   | Unauthenticated deprecate/retire → 401; retire gates `not_deprecated` / `overlap_window_active`; missing/unknown successor; unknown capability version | Pipeline tests |
| 8   | Discovery excludes retired; etag changes on deprecate/retire; deprecated still serves after `retire_after` before operator retire; published Identity used when overlay absent | Pipeline tests |

### Edge Cases

- **Error code this slice's retirement path emits**: `capability_retired` when a pinned
  version has been retired (§12.4). Unknown and kill-switch rejections remain C1's
  `capability_unknown` / `capability_disabled`; J1 does not redefine them (C1 Freezes).
- **Boundary: overlap window length**: the configured window is two client release
  cycles, minimum 90 days (§15 OD-9; A12). A deprecated version inside that window is
  served; retirement is the step that ends service for that pin (§5.7; §12.4).
- **Boundary: announcement before enforcement**: discovery must mark deprecated with a
  successor before retirement is enforced; retirement without that announcement path
  violates §5.7 (§5.7; §12.4).
- **Boundary: deprecate versus retire**: `deprecated` remains servable for the window;
  `retired` returns `capability_retired` (§5.7; §12.4; C1 Freezes for the taxonomy code).
- **Boundary: one-directional deprecate**: deprecate after retire is rejected (`already_retired`);
  a duplicate deprecate with the same successor is idempotent; a duplicate with a different
  successor is rejected (`already_deprecated`). Deprecate must not restart the overlap window.
- **Boundary: no auto-retire on the clock**: after `retire_after` has passed but before the
  operator `retire` mutation, a deprecated pin remains servable.
- **Boundary: registry validation**: deprecate/retire require the target version in the registry;
  deprecate requires a registered successor identity so discovery never announces an unknown
  successor.
- **Failure branch: opaque failure is forbidden on retirement**: retirement MUST return
  `capability_retired` rather than failing opaquely, so old clients can prompt for an
  update (§12.4).
- **Inherited prohibition: no per-request server-side state** for holding deprecation
  sessions or client-specific overlap clocks (§4.4, §9.7; delivery plan §6.4).
- **Inherited prohibition: guard rejection journaling**: a request rejected as
  `capability_retired` at capability resolve produces no `ai_request` journal row
  (§7.5; C1 / C3 invariant). Operator `control_audit` for the retire mutation is a
  control-plane write, not a request journal (B2 Freezes).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Deprecated capability versions MUST remain servable for a defined overlap
  window (A12) (§5.7).
- **FR-002**: Retirement of a capability version MUST be announced through discovery
  before it is enforced (§5.7).
- **FR-003**: Before retirement is enforced, the platform MUST mark the capability
  version deprecated in discovery with a successor (§12.4).
- **FR-004**: A deprecated capability version MUST keep serving through the overlap
  window (A12) (§12.4).
- **FR-005**: After the overlap window, the platform MUST retire the capability version,
  returning `capability_retired` so old clients prompt for an update instead of failing
  opaquely (§12.4).
- **FR-006**: Old clients MUST keep working against pinned capability versions for the
  defined overlap period (A12).
- **FR-007**: The configured capability-version overlap window length MUST be two client
  release cycles, minimum 90 days (§15 Open Decision 9; A12).
- **FR-008**: The retire control-plane mutation that enacts FR-005 MUST be journaled with
  the operator identity under B2's freeze that every control-plane mutation is journaled
  with the operator identity as a `control_audit` row (B2 Freezes; §12.4).
- **FR-009**: The deprecate and retire mutations MUST persist the new lifecycle state and successor
  onto the capability version's `global`-scope `capability_grant` lifecycle overlay in D1, and MUST
  NOT edit or republish the version's manifest; the effective lifecycle a resolver or discovery
  applies is the manifest's published value overridden by that overlay when one exists (§5.1; §7.3;
  §4.5 Capability availability).
- **FR-010**: Discovery and capability resolve MUST read that lifecycle overlay through the config
  cache alongside grants and kill switches, so a cold isolate reconstructs the current lifecycle
  state from D1 rather than from in-memory state (§6.1 stage 5; §7.3; C1 FR-006).

### Key Entities

This slice defines **no new entity**. It writes to two entities that already exist:

- **`capability_grant` (§7.3)** — the capability-availability row and the durable target for the
  deprecate / retire mutations. A lifecycle transition is written at `global` scope onto that row's
  lifecycle-overlay fields (lifecycle state, successor id, `deprecated_at`, `retire_after`); the
  overlay overrides the manifest's published `lifecycleState` / `successorId`, and the published
  manifest is never edited and never republished for a lifecycle change (§5.1; §7.3; §12.4 Retire a
  capability). Resolver and discovery read the current row through the config cache alongside grants
  and kill switches, so a cold isolate reconstructs lifecycle from D1 (§6.1 stage 5; §7.3).
  Because A5's shipped schema predates this amendment, J1 carries **one forward-only additive
  migration** adding those fields to `capability_grant` (§13.4 Migrations; delivery plan §3.9 band J
  note). It adds no table.
- **`control_audit` (§7.3; B2 Freezes)** — each deprecate / retire mutation is journaled with the
  operator identity, in the shape B2 froze.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Desktop clients update on the clinic's schedule, not the platform's;
  breaking a deployed client is a support incident, not a release (A12). The overlap
  window keeps clinic-scale installations working across slow desktop-release cadences
  without enterprise rollout machinery (constitution principle I).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker) —
  discovery / capability-resolve behaviour and the operator control-plane deprecate /
  retire path. It does not add Flutter UI or Supabase domain writes. Per the §14
  acknowledgement, the gateway is a non-primary, additive component: no domain logic, no
  business data, no write path into Supabase, always optional (§14, item 1).
- **Data Integrity & Security**: Deprecate / retire mutations are control-plane actions
  authenticated by operator identity, persisted on the `global`-scope `capability_grant` lifecycle
  overlay, and journaled on `control_audit` (B2 Freezes; §4.5; §7.3). Manifest immutability is
  preserved: no published manifest or its content hash changes (§5.1).
  Request-path retirement rejection uses the existing `capability_retired` taxonomy code
  (C1 Freezes) and does not invent a second audit path for guard rejections.
- **Failure Handling**: After retirement, pinned requests degrade to
  `capability_retired` with a client prompt-for-update outcome rather than an opaque
  failure (§12.4). Platform or AI unavailability remains additive: clinical work
  continues without AI affordances (constitution principle V; A11).

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **C1** — capability registry lookup, the three resolver taxonomy codes, kill-switch
  rejection, and baseline discovery of granted manifests. Consumed; J1 only adds
  successor announcement and the overlap-window / retirement behaviour C1 deferred.
- **B2** — installation lifecycle enroll / rotate / suspend / resume / delete. Consumed
  for the control-plane auth and `control_audit` rule; those five lifecycle actions are
  not redefined.
- **J2** — `context_required` self-healing round trip.
- **J3** — staged rollout and canary cohorts (promotion / rollback / cohort activation
  audit).
- **J4** — token contract rotation with overlapping `ver` acceptance.
- **Flutter client update UX** beyond returning `capability_retired` so existing client
  taxonomy handling can prompt for an app update (§12.4). No new Flutter surface in this
  slice.

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

- **SC-001**: Discovery marks a deprecated capability version with its successor before
  retirement is enforced (asserted by test 1; Done when).
- **SC-002**: A client pin to a deprecated version inside the configured overlap window
  is still served (asserted by test 2; Done when).
- **SC-003**: After retirement, the same pinned request returns `capability_retired`
  (asserted by test 3; Done when).
- **SC-004**: The retire mutation writes a `control_audit` row carrying the operator
  identity (asserted by test 4; delivery plan §3.11.8 J1).
- **SC-005**: A deprecation or retirement persisted by the control plane is still observed by
  discovery and capability resolve after a cold isolate reload, and no manifest content or hash
  changed (asserted by test 5; §5.1; §7.3).

## Assumptions

- C1 and B2 are complete on the integration line this slice branches from (`Needs: C1,
  B2`).
- Manifest identity already carries the **published** lifecycle state and successor id from earlier
  contract slices (C1 / A4); J1 does not redefine those fields and does not edit them. Lifecycle
  *evolution* after publication is the `capability_grant` control-plane overlay (§5.1; §7.3), which
  is the only durable write target this slice uses besides `control_audit`.
- The `capability_grant` entity itself is A5's and is not redefined; J1 only adds its lifecycle
  fields by additive forward-only migration and writes them from the control plane (§7.3; §13.4).
- Open Decision 9's recommended default (two client release cycles, minimum 90 days) is
  the configured overlap window unless the architecture document amends it (§15 OD-9).
- Spec Kit's `create-new-feature.sh --dry-run` allocates against `docs/specs/` and does
  not parse `ai/<NNN>-*` branches, so the number was confirmed from `specs/` (highest
  `047-conversation-evals`) and applied as **048**.
- Client-side "prompt for app update" behaviour on `capability_retired` is already the
  taxonomy's intended client action; this slice's Done when is satisfied by returning
  that code after retirement (§12.4), not by shipping a new Flutter update screen.
