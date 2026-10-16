# Feature Specification: Staged rollout and canary cohorts

**Feature Branch**: `ai/050-j3-staged-rollout-canary`

**Created**: 2026-08-03

**Status**: Draft

**Input**: Slice `J3` — "Staged rollout and canary cohorts" (delivery plan §3.9, band J).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.9, row J3):

> §12.4, §4.5, §13.4

### Freezes

Contracts this slice establishes for the first time:

- **Named-cohort activation for a capability build, prompt artifact, or routing
  policy version**: a new capability build, prompt artifact, or routing policy
  version MAY be activated for a named cohort so that cohort receives the new
  build while other cohorts continue to receive the previous one (§12.4 Change a
  prompt / Add a capability / Add a provider; §13.4 Promotion; delivery plan
  §3.9 Done when).
- **Promotion across cohorts**: promotion moves all cohorts onto the activated
  version so the staged split ends (§12.4 Change a prompt; delivery plan §3.11.8
  J3).
- **Rollback by deploy for prompt (and capability-build) rollbacks**: a prompt
  change is rolled back by deploying the previous build; staged cohort deploy,
  promote, and rollback-by-deploy are the containment path after the eval suite
  has gated the change (§12.4 Change a prompt; delivery plan §3.9 Done when).
- **Routing-policy canary and roll back on the control plane**: publishing a new
  versioned routing policy, canarying it, and rolling it back are control-plane
  Routing policy functions, separately authenticated by operator identity
  (§4.5 Routing policy row; §4.5 "Every control-plane mutation is journaled with
  the operator identity").
- **Every activation is a `control_audit` row with the operator identity**: each
  cohort activation, promotion, or rollback mutation is journaled with the
  operator identity as a `control_audit` row (B2 Freezes applied to §4.5 Routing
  policy / cohort activation; delivery plan §3.9 Done when; §3.11.8 J3).
- **Journal records which version served under cohort split**: after activation,
  each request's journal continues to record the serving version (prompt version
  on the journal row per §12.4 Change a prompt; D1 Freezes) so the effect of the
  change is measurable afterwards (delivery plan §3.11.8 J3).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (B2, D1, D2, F1). Changing any is out of
scope by definition:

- **From B2 (control-plane enrollment and installation lifecycle)**: the
  **control-plane surface** separately authenticated by operator identity (not
  clinic identity), and the **control-audit rule** that every control-plane
  mutation is journaled with the operator identity as a `control_audit` row (B2
  Freezes). J3 extends that surface with Routing policy publish / canary / roll
  back and cohort activation / promote mutations; it does not redefine enroll,
  suspend, resume, rotate, delete, or the `control_audit` shape (B2 Freezes; B2
  Out of Scope naming routing policy canary / roll back).
- **From D1 (prompt registry and composer)**: the **prompt registry contract** —
  immutable prompt artifacts deployed with the Worker and pinned by the capability
  manifest; a prompt change is a new capability *build*, not an editable D1 row;
  the resolved prompt version is what the journal records (D1 Freezes; §12.4
  Change a prompt; §13.4 Configuration). J3 activates / promotes / rolls back
  those builds by cohort deploy; it does not store prompt text in D1, invent an
  editable-prompt path, or redefine composition (D1 Freezes; §13.4).
- **From D2 (provider port, fake adapter, and routing policy)**: the
  **routing-policy-as-data contract** — a versioned routing policy stored as data
  that yields an ordered candidate chain; the router reads the active policy and
  records the selection reason (D2 Freezes). J3 activates a new policy version for
  a cohort, promotes, or rolls back; it does not redefine the port, fake adapter,
  chain selection rules, or consult provider history when building the chain (D2
  Freezes; D2 Out of Scope naming J3 for policy activation).
- **From F1 (eval suite harness and first capability eval)**: the **capability
  eval harness** that gates prompt / capability changes in CI — golden cases block
  a regressing prompt change before staged deploy (F1 Freezes; §12.4 Change a
  prompt). J3 activates only after that gate; it does not redefine golden cases,
  score recording, or scheduled live smoke (F1 Freezes; F1 Out of Scope naming J3
  for cohort activation after evals).

### Open decisions relied on

None. This slice assumes no §15 recommended default beyond what F1 already froze
for the eval half of the prompt-change bar; §12.4, §4.5, and §13.4 fully specify
cohort activation, promote, rollback-by-deploy for prompts, and control-plane
routing-policy canary / roll back with `control_audit`.

## Clarifications

### Session 2026-08-03

- Q: Where should J3’s control-plane mutations (routing-policy publish / canary / roll back, and cohort activate / promote) live under `ai-platform/src/`? → A: Extend the existing B2 control-plane module(s) with Routing policy publish / canary / roll back and cohort activate / promote handlers; shared operator-auth and `control_audit` write path `[implementation choice — no §citation]`
- Q: Where should request-path selection of which version serves an installation under a cohort split live under `ai-platform/src/`? → A: Cohort-aware reads inside the existing D2 router and C1 capability resolver — each continues to return the active policy / granted build for that installation; no new pipeline stage `[implementation choice — no §citation]`
- Q: Should the pipeline tests for prompt / capability-build cohort activation and the tests for routing-policy canary share one harness, or stay in separate suites? → A: Separate pipeline test modules: one for prompt / capability-build cohort activate / promote / rollback-by-deploy; one for routing-policy publish / canary / roll back; optional shared `control_audit` assert helper `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Staged rollout and canary cohorts (Priority: P1)

An operator activates a new capability build, prompt artifact, or routing policy
version for a named cohort so that cohort receives the new build while others
still receive the previous one; promotes so all cohorts move to the new version;
or rolls back (for prompts, by deploying the previous build; for routing policy,
via the control-plane roll-back function). Every such activation is a
`control_audit` row carrying the operator identity. Under the cohort split, the
journal records which version served each request so the change's effect remains
measurable.

**Why this priority**: J3 has `Needs: B2, D1, D2, F1` (delivery plan §3.9). B2 must
already provide the operator-authenticated control plane and `control_audit`
journaling; D1 must already pin immutable prompt artifacts and surface prompt
version for the journal; D2 must already select from a versioned routing policy
as data; F1 must already gate prompt regressions in CI. Band J defers this
behaviour until a prompt, capability version, or routing policy has an audience
that can be split (delivery plan §3.9 Build when; DP-5).

**Independent Test**: A new capability build, prompt artifact, or routing policy
version is activated for a named cohort, promoted, or rolled back by deploy;
every activation is a `control_audit` row with the operator identity (the slice's
`Done when` cell; delivery plan §2.2; DP-3).

**Acceptance Scenarios**:

1. **Given** a new capability build, prompt artifact, or routing policy version
   activated for a named cohort while other cohorts remain on the previous
   version, **When** installations in each cohort submit requests, **Then** the
   named cohort receives the new build and the others receive the previous one
   (§12.4; §13.4 Promotion; delivery plan §3.11.8 J3).
2. **Given** a staged cohort activation that has not yet been promoted, **When**
   an operator promotes the activation, **Then** all cohorts move to the activated
   version (§12.4 Change a prompt; delivery plan §3.11.8 J3).
3. **Given** a staged activation of a prompt artifact (or capability build)
   that must be undone, **When** an operator rolls back by deploying the previous
   build, **Then** the previous build is restored for the affected cohorts
   (§12.4 Change a prompt; delivery plan §3.9 Done when; §3.11.8 J3).
4. **Given** an operator performs a cohort activation, promotion, routing-policy
   canary, or roll back, **When** the control-plane mutation completes, **Then**
   every activation is journaled with that operator identity as a `control_audit`
   row (B2 Freezes; §4.5; delivery plan §3.9 Done when; §3.11.8 J3).
5. **Given** a cohort split in which different cohorts are served different
   versions, **When** requests complete and are journaled, **Then** the journal
   records which version served each request (§12.4 Change a prompt — prompt
   version on the journal row; D1 Freezes; delivery plan §3.11.8 J3).

### Test plan

Layer names are from the testing-strategy table in §13.5. The slice's required
layer is **Integration** (delivery plan §3.11.8); the closest §13.5 layer is
**Pipeline tests** (stage ordering / active policy and build selection under
cohort activation).

| #   | Test                                                                                      | §13.5 layer    |
| --- | ----------------------------------------------------------------------------------------- | -------------- |
| 1   | A cohort receives the new build while others receive the previous one                     | Pipeline tests |
| 2   | Promotion moves all cohorts                                                               | Pipeline tests |
| 3   | Rollback restores the previous build                                                      | Pipeline tests |
| 4   | Every activation writes a `control_audit` row with the operator identity                  | Pipeline tests |
| 5   | The journal records which version served each request under the cohort split              | Pipeline tests |

### Edge Cases

- **Error codes this slice emits**: none on the request path. J3 does not add a
  taxonomy code; request rejection codes remain those frozen by earlier slices.
  Non-operator credentials on control-plane mutations remain rejected under B2's
  operator-auth rule (B2 Freezes; §4.5).
- **Boundary: named cohort vs others**: activation for a named cohort MUST leave
  non-cohort installations on the previous build until promotion (§12.4; §13.4
  Promotion; delivery plan §3.11.8 J3).
- **Boundary: promotion ends the split**: after promotion, all cohorts receive the
  activated version — no residual canary split (§12.4; delivery plan §3.11.8 J3).
- **Boundary: prompt rollback is by deploy**: rolling back a prompt change MUST
  deploy the previous build; J3 MUST NOT introduce a runtime prompt activation
  pointer that would make prompt rollback independent of deploy (§12.4 Change a
  prompt; §13.4 Configuration — prompts are deployed artifacts; delivery plan
  §3.9 Done when).
- **Boundary: routing policy canary / roll back are control-plane mutations**:
  publishing, canarying, and rolling back a versioned routing policy MUST go
  through the operator-authenticated control plane and MUST write `control_audit`
  (§4.5 Routing policy row; §4.5 audit rule).
- **Boundary: eval gate before staged prompt deploy**: a prompt change that fails
  the F1 eval suite MUST NOT be activated for a cohort (§12.4 Change a prompt; F1
  Freezes).
- **Failure branch: unaudited activation is forbidden**: an activation, promotion,
  canary, or roll back without a `control_audit` row carrying the operator
  identity violates §4.5 (§4.5; delivery plan §3.9 Done when).
- **Inherited prohibition: no mechanism from §9.14** — including a runtime prompt
  activation pointer added because it looks prudent — MUST NOT be introduced
  (R-20; delivery plan §6.4).
- **Inherited prohibition: no prompt text, provider name, or model identifier in
  the Flutter client** while implementing cohort activation (R-12; delivery plan
  §6.4).
- **Inherited prohibition: no per-request server-side state** for holding canary
  sessions (§4.4, §9.7; delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A new capability build, prompt artifact, or routing policy version
  MUST be activatable for a named cohort so that cohort receives the new build
  while others receive the previous one (§12.4; §13.4 Promotion).
- **FR-002**: Promotion MUST move all cohorts onto the activated version
  (§12.4 Change a prompt; delivery plan §3.11.8 J3).
- **FR-003**: A prompt change MUST be roll-backable by deploying the previous
  build after staged cohort deploy (§12.4 Change a prompt).
- **FR-004**: The control plane MUST support publishing a new versioned routing
  policy (non-serving), canarying it, promoting it to global active, and rolling
  it back (§4.5 Routing policy row).
- **FR-005**: Every cohort activation, promotion, routing-policy canary, and roll
  back MUST be journaled with the operator identity as a `control_audit` row
  (§4.5; B2 Freezes; delivery plan §3.9 Done when).
- **FR-006**: Under a cohort split, the journal MUST record which version served
  each request so the effect of the change is measurable afterwards (§12.4 Change
  a prompt; D1 Freezes for prompt version on the journal row).
- **FR-007**: Capability or context-key contract changes MUST be reviewed as
  contract changes, deployed, then activated by cohort (§13.4 Promotion).
- **FR-008**: Prompt artifacts, manifests, and schemas MUST remain deployed
  artifacts; only genuinely volatile policy (including routing policy version and
  capability grants used for cohort grants) MAY be data in D1 (§13.4
  Configuration).
- **FR-009**: A prompt change MUST be blocked by the F1 eval suite on regression
  before it is deployed to a staged cohort (§12.4 Change a prompt; F1 Freezes).
- **FR-010**: Granting a new capability whose context keys already exist MUST be
  possible to a cohort without a client release (§12.4 Add a capability whose
  context keys already exist).
- **FR-011**: Promoting a provider by policy version MUST be possible with a
  canary cohort and MUST NOT require a pipeline, capability, or client change
  (§12.4 Add a provider).

### Key Entities

Not applicable — this slice defines no entities. It activates and audits existing
`routing_policy`, `capability_grant`, and `control_audit` surfaces and deployed
prompt / capability builds frozen by A5, B2, D1, and D2.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Staged cohort activation lets operators contain a prompt,
  capability, or routing change to a named audience before promotion, matching
  clinic-scale incident containment without enterprise fleet management or a
  second architecture (constitution principle I; §12.4; §13.4 Promotion).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker) —
  control-plane Routing policy canary / roll back and cohort activation /
  promote mutations, plus deploy-time staged builds for prompt / capability
  artifacts — and does not add Flutter AI surfaces or Supabase domain RPCs. The
  gateway remains a non-primary, additive component: no domain logic, no business
  data, no write path into Supabase (§14, item 1).
- **Data Integrity & Security**: Control-plane mutations remain operator-
  authenticated and every activation writes `control_audit` with the operator
  identity (§4.5; B2 Freezes). Prompt text stays out of D1; volatile policy for
  routing-policy version and capability grants stays in D1 as §13.4 already
  allows. No soft-delete or dual-write surface is introduced.
- **Failure Handling**: A bad prompt or policy version is contained by cohort
  canary and undone by rollback (prompt: previous build deploy; routing policy:
  control-plane roll back) rather than hard-locking clinical work (§12.4; §4.5).
  Platform or AI unavailability remains additive: clinical work continues without
  AI affordances (constitution principle V).

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **B2** — installation lifecycle enroll / suspend / resume / rotate / delete.
  Consumed for operator auth and `control_audit`; those five actions are not
  redefined.
- **D1** — prompt registry, composer, pin-by-hash build gate. Consumed for
  immutable deployed artifacts and journaled prompt version; composition is not
  redefined.
- **D2** — provider port, fake adapter, routing-policy *selection* chain.
  Consumed for versioned policy-as-data; chain filtering and the fake adapter are
  not redefined.
- **F1** — eval harness, golden cases, scheduled live smoke. Consumed as the
  regression gate before staged prompt deploy; harness internals are not
  redefined.
- **J1** — capability deprecation overlap window and `capability_retired`.
- **J2** — `context_required` self-healing round trip.
- **J4** — token contract rotation with overlapping `ver` acceptance.
- **D7 / Add a provider adapter work** — implementing a second provider adapter
  and fixture suite remains D7; J3 only freezes canary / promote of a policy
  version that already registers a target (§12.4 Add a provider recipe's canary
  clause only).
- **Runtime prompt activation pointer** — rollback and canary of prompts without
  a deploy (§9.14). Explicitly not introduced; prompt rollback remains by deploy
  (§12.4; delivery plan §6.4 / R-20).
- **Band G commercial surface** — plan catalogue, entitlement economics UI,
  billing period close.
- **Health-based provider routing** and other §9.14 / band K deferrals.

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

- **SC-001**: An automated test proves a named cohort receives the new build while
  others receive the previous one (asserted by test 1; Done when).
- **SC-002**: An automated test proves promotion moves all cohorts onto the
  activated version (asserted by test 2; Done when).
- **SC-003**: An automated test proves rollback restores the previous build
  (asserted by test 3; Done when).
- **SC-004**: An automated test proves every activation writes a `control_audit`
  row carrying the operator identity (asserted by test 4; Done when).
- **SC-005**: An automated test proves the journal records which version served
  each request under the cohort split (asserted by test 5; §12.4; Done when).

## Assumptions

- B2, D1, D2, and F1 are complete on the integration line this slice branches from
  (`Needs: B2, D1, D2, F1`).
- B2 already freezes operator-authenticated control-plane mutations and
  `control_audit` with operator identity; J3 extends that rule to Routing policy
  and cohort activation mutations without changing the audit row shape (B2
  Freezes; DP-5).
- D1 already freezes immutable deployed prompt artifacts and surfaces prompt
  version for the journal; J3 does not change pin-by-hash or store prompt text in
  D1 (D1 Freezes; §13.4).
- D2 already freezes versioned routing-policy-as-data and active-policy selection;
  J3 activates versions for cohorts and does not rewrite chain selection (D2
  Freezes).
- F1 already freezes the CI eval gate that blocks regressing prompt changes; J3
  assumes that gate has passed before staged prompt deploy (F1 Freezes; §12.4).
- Spec Kit's `create-new-feature.sh --dry-run` allocates against `docs/specs/` and
  does not parse `ai/<NNN>-*` branches, so the number was confirmed from `specs/`
  (highest `049-context-required-self-healing`) and applied as **050**.
- Build-when trigger ("a prompt, capability version, or routing policy has an
  audience that can be split") is an ordering/trigger condition from delivery plan
  §3.9, not a product gate encoded as runtime configuration in this slice.
