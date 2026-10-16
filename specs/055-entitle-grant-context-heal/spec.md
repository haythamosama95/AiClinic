# Feature Specification: Entitle-and-grant operator path and live `context_required` self-heal (I4)

**Feature Branch**: `ai/055-i4-entitle-grant-context-heal`

**Created**: 2026-08-07

**Status**: Draft

**Input**: I4 — "Entitle-and-grant operator path and live `context_required` self-heal"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice is live composition: an operator-authenticated control action
> activates an enrolled installation's entitlement and capability grants so stages 3 and
> 8 can admit a real request, and the live E2 submit path hosts J2's `context_required`
> self-heal. The Cloudflare AI Gateway remains the additive, non-primary component
> acknowledged in §14 of `docs/architecture/ai-platform/01-ai-platform.md`: no domain
> logic, no business data, and no write path into Supabase. AI stays optional (A11).

## Slice Contract

### Implements

`§4.5, §7.3, §8.4, §5.2` (copied verbatim from the slice's `Canonical` cell in §3.10 of
`03-ai-platform-delivery-plan.md`).

### Freezes

**None.** Band I freezes no new contract (Delivery Plan §3.10; §2.3). I4 composes
contracts already frozen by B2, I3, and J2: it activates entitlement and capability-grant
rows the guard and admission already read, and hosts J2's self-heal on the live E2 submit
path I3 composed. Later slices may not rewrite those consumed contracts through this
slice.

What this slice *does* establish for the first time is **operable entitle-and-grant
wiring plus live self-heal hosting only**: an operator-authenticated Entitlement
management / Capability availability control action moves a pending enrollment to an
admissible installation (entitlement `active`, budget fields, and `capability_grant`
rows), and the live Flutter submit path runs J2's one-shot `context_required` recovery.
That is composition, not a plan catalogue, billing period close, usage-summary UI, or a
new self-heal contract (those remain Band G / J2 Freezes respectively).

### Consumes

Contracts frozen by the slices in I4's `Needs` (`B2`, `I3`, `J2`). Changing any is out of
scope by definition:

- **From B2 — Control-plane enrollment and installation lifecycle** (§4.5 Installation
  lifecycle; §8.1 via B2 Freezes): separately authenticated operator identity (not clinic
  identity), the five lifecycle actions, enroll write set
  (`installation` / `installation_key` / `entitlement` / `control_audit`), and the rule
  that every control-plane mutation journals `control_audit` with the operator identity.
  Enroll leaves `entitlement` `pending` with zeroed economics and an empty capability set
  so the row grants nothing until Entitlement management activates it (B2 Freezes /
  FR-005a; §4.5 "The line between the first two rows"; §7.3 Entitlement status). I4
  extends the same operator-authenticated control surface with Entitlement management /
  Capability availability activate-and-grant writes; it does not rewrite enroll, suspend,
  resume, rotate, delete, or operator-auth.
- **From I3 — Live client invoke on the first AI feature surface** (§4.1; §5.5; §5.4;
  §6.4; A11): production AAT mint and HTTPS submit composition on the E4 host, E3 key
  resolution, stable idempotency key, SSE to one terminal event, provisional/draft UX,
  degraded non-enrolled / unreachable behaviour, and consumption of I1/I2 live Worker
  paths. I4 hosts J2's self-heal on that live submit path; it does not reimplement mint,
  discovery filtering, Worker orchestration, or E4 UX contracts (I3 Freezes: none /
  composition only; I3 Out of Scope naming I4 for entitle-and-grant and self-heal).
- **From J2 — `context_required` self-healing round trip** (§8.4; §5.2 Self-healing): one
  automatic refresh → resolve named keys → resubmit **once** with the **same idempotency
  key** for `single_shot` only; a second `context_required` surfaces the request
  reference with no automatic third attempt; conversational capabilities never take this
  path (J2 Freezes). I4 hosts that behaviour on the live E2 submit path; it does not
  redefine the C2 `context_required` payload, the one-resubmission bound, or
  conversational exclusion.

### Open decisions relied on

- **Open Decision 15** (recommended default): there is no plan catalogue initially.
  Enroll records the plan name only and leaves the row `pending`; an operator assigns the
  economics explicitly (§15 OD-15; §4.5 Entitlement management; Delivery Plan §4.1 Band G
  vs I4). Assumed because I4's Done when activates entitlement and grants without
  introducing a plan catalogue, billing period close, or usage-summary UI (those remain
  Band G).

No other §15 decision is assumed. Quota unit/period (OD-2) remains a product decision for
Band G; I4 only writes the budget fields admission already reads (§7.3 `entitlement` key
fields).

## Clarifications

### Session 2026-08-07

- Q: Should the operator entitle-and-grant path be one combined `/control/installations/{id}/…` action that writes entitlement economics, `capability_grant` row(s), and `control_audit` in a single mutation, or two distinct actions matching the separate §4.5 rows (Entitlement management, then Capability availability)? → A: One combined operator action (e.g. `/control/installations/{id}/entitle`) that activates entitlement budget fields, writes `capability_grant` row(s), and journals `control_audit` in one mutation `[implementation choice — no §citation]`
- Q: Where should production `ContextRequiredSelfHeal` (and its live `ManifestRefreshPort`) be wired onto the I3 host so the live E2 submit path hosts J2 self-heal? → A: Wire `ContextRequiredSelfHeal` inside `FirstAiFeatureSurface._invoke` (surface calls heal instead of raw `sdk.invoke`); inject production `ManifestRefreshPort` with the surface’s existing resolver `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Entitle-and-grant operator path and live `context_required` self-heal (Priority: P1)

An operator, authenticated separately from clinic identity, activates an enrolled
installation's entitlement (status `active`, quota/budget/period/soft-threshold /
`max_cost_class` fields admission already reads) and writes the installation's capability
grants so stages 3 and 8 can admit a real request — without a plan catalogue, billing
period close, or usage-summary UI. Independently on the client, the live E2 submit path
I3 composed hosts J2's `context_required` self-heal: when a stale `single_shot` manifest
yields `context_required`, the client refreshes the manifest, resolves the named keys,
and resubmits **once** with the same idempotency key; a second `context_required`
surfaces the request reference; conversational capabilities never take this path.

**Why this priority**: I4 has `Needs: B2, I3, J2` (Delivery Plan §3.10). B2 leaves
entitlement `pending` and empty so nothing is admitted until Entitlement management
activates it (§4.5; §7.3). I3 puts production mint/submit on the first surface but
explicitly deferred entitle-and-grant and live self-heal to I4. J2 froze the self-heal
behaviour; I4 hosts it on the live submit path so CP6 can ask whether an enrolled
installation is operable end to end (Delivery Plan §5 CP6).

**Independent Test**: An operator-authenticated control action activates an enrolled
installation's entitlement and capability grants (and the budget fields admission already
reads) so stages 3 and 8 can admit a real request — without introducing a plan catalogue,
billing period close, or usage-summary UI (those remain Band G); the E2 submit path hosts
J2's `context_required` self-heal so a stale manifest refreshes, resolves the named keys,
and resubmits **once** with the same idempotency key (the slice's `Done when` cell;
Delivery Plan §2.2; DP-3).

**Acceptance Scenarios**:

1. **Given** an operator-authenticated caller and an enrolled installation whose
   `entitlement` is still `pending`, **When** the operator performs the Entitlement
   management / Capability availability activate-and-grant control action, **Then** the
   platform writes the entitlement fields admission already reads (status moved to
   `active`, quota/budget/period bounds/soft threshold/`max_cost_class` as assigned) and
   the corresponding `capability_grant` row(s), and writes a `control_audit` entry
   carrying the operator identity (§4.5 Entitlement management / Capability availability;
   §7.3 `entitlement` / `capability_grant` / `control_audit`; Delivery Plan §3.12.9 I4
   *Entitle*).
2. **Given** an enrolled installation whose entitlement remains `pending` (zeroed
   budgets, empty capability set), **When** a client request reaches entitlement /
   admission (stages 3 and 8), **Then** the request fails entitlement and is not admitted
   until the operator activate-and-grant path has run (§4.5 "enrolled and verifiable
   before it is entitled to anything"; §7.3 Entitlement status; Delivery Plan §3.12.9 I4
   *Entitle* "pending enroll still fails entitlement until activated").
3. **Given** credentials that are not operator identity, **When** any entitle-and-grant
   control action is attempted, **Then** the request is rejected and no entitlement or
   grant mutation is applied (§4.5 "separately authenticated (operator identity, not
   clinic identity)"; Delivery Plan §3.12.9 I4 *Entitle* "non-operator rejected").
4. **Given** the live E2 submit path on the I3-composed host and a `single_shot` client
   whose manifest cache is stale so a required key is missing, **When** the platform
   returns `context_required` with the missing-key manifest, **Then** the client refreshes
   its manifest, resolves the named keys, resubmits **once** with the **same idempotency
   key**, and the resubmission proceeds on the live path (§8.4; §5.2 Self-healing;
   Consumes J2; Delivery Plan §3.12.9 I4 *Self-heal*).
5. **Given** that live self-heal path has already performed its one automatic
   resubmission, **When** the platform returns `context_required` again for that action,
   **Then** the client stops automatic recovery and surfaces the request reference to the
   user (§8.4; Delivery Plan §3.12.9 I4 *Self-heal*).
6. **Given** a capability with `interaction_mode: conversational`, **When** a context gap
   arises during a turn, **Then** the live submit path never takes the §8.4
   `context_required` self-healing path (§8.4; §5.2 Negotiation; Delivery Plan §3.12.9 I4
   *Self-heal*).

### Test plan

The minimum test set is the I4 row of Delivery Plan §3.12.9 (layer: *Integration +
Flutter*). Tests join CI permanently (Delivery Plan §3.11). Layer names follow §13.5
(pipeline / Workers integration for control-plane writes; Flutter / client contract for
live self-heal).

| # | Named test | Layer | Asserts |
| --- | --- | --- | --- |
| T1 | `entitle_activate_writes_entitlement_grant_and_audit` | Integration | Operator activate/grant writes entitlement and `capability_grant` rows and a `control_audit` entry with operator identity (§3.12.9 I4 *Entitle*; §4.5; §7.3) |
| T2 | `entitle_sets_budget_fields_admission_reads` | Integration | Activate writes the budget fields admission already reads (period bounds, request quota, token/cost budget, soft threshold, `max_cost_class`, allowed capability set) and moves status to `active` (§7.3 `entitlement`; Done when; §4.5 Entitlement management) |
| T3 | `pending_enroll_fails_entitlement_until_activated` | Integration | Pending enroll still fails entitlement / is not admitted until activated (§3.12.9 I4 *Entitle*; §4.5; §7.3 Entitlement status) |
| T4 | `entitle_non_operator_rejected` | Integration | Non-operator credentials are rejected; no entitlement or grant row mutation (§3.12.9 I4 *Entitle*; §4.5) |
| T5 | `live_self_heal_refreshes_resolves_resubmits_once_same_key` | Flutter | Live submit path refreshes on first `context_required`, resolves named keys, resubmits once with the same idempotency key (§3.12.9 I4 *Self-heal*; §8.4; §5.2; Consumes J2) |
| T6 | `live_self_heal_second_context_required_surfaces_reference` | Flutter | Second `context_required` stops automatic recovery and surfaces the request reference (§3.12.9 I4 *Self-heal*; §8.4) |
| T7 | `live_self_heal_no_automatic_third_attempt` | Flutter | No automatic third attempt after the second `context_required` (§8.4; Consumes J2; §3.11 coverage of the one-resubmission bound) |
| T8 | `live_self_heal_conversational_never_takes_path` | Flutter | Conversational capabilities never take the §8.4 self-healing path on the live submit path (§3.12.9 I4 *Self-heal*; §8.4; §5.2) |

Coverage (Delivery Plan §3.11): happy path of entitle + grant + audit (T1–T2); pending
boundary and non-operator rejection (T3–T4); live self-heal happy path, second-reject
branch, no third attempt, and conversational exclusion (T5–T8); inherited Delivery Plan
§6.4 prohibitions listed under Out of Scope. This slice does not invent new §5.4 taxonomy
codes; entitle rejections use the existing operator-auth control-plane rejection shape
(Consumes B2); self-heal consumes `context_required` behaviour frozen by C2/J2.

### Edge Cases

- **Non-operator on entitle-and-grant**: rejected; no entitlement or `capability_grant`
  mutation and no successful `control_audit` of an applied change (§4.5; T4).
- **Pending entitlement**: status `pending` with zeroed budgets and empty capability set
  still fails entitlement until activated; enroll alone does not admit (§7.3 Entitlement
  status; §4.5; T3).
- **Entitlement status shape**: every column stays non-null; `pending` is zeroed
  economics and empty capability set, not absent values — activate writes one shape the
  guard already reads (§7.3 Entitlement status).
- **Capability grant scope**: grant/gate at `plan` or `installation` scope writes
  `capability_grant`; deprecate/retire at `global` scope remain neighbouring-slice work
  (J1 / existing capability-lifecycle), not I4's entitle-and-grant Done when (§4.5
  Capability availability; §7.3 `capability_grant`).
- **`context_required` (consumed, not redefined)**: typed data-carrying rejection with
  missing-key manifest; live client behaviour is refresh → resolve → resubmit once
  (§8.4; §5.2; Consumes J2/C2).
- **One automatic resubmission only**: first `context_required` may heal; second is a
  real defect surfaced with the request reference (§8.4; T5–T6).
- **No automatic third attempt**: after the second `context_required`, the live path
  must not loop (§8.4; T7).
- **Same idempotency key on resubmit**: self-heal MUST reuse the original action's key,
  not mint a new one (§8.4; Consumes J2/E2; T5).
- **`single_shot` only**: conversational capabilities MUST NOT enter this path on the
  live submit host (§8.4; §5.2; T8).
- **No plan catalogue / billing close / usage-summary UI**: assigning economics is an
  explicit operator action, not a catalogue-driven commercial surface (OD-15; Delivery
  Plan §4.1 Band G; Done when).
- **Inherited: no per-request server-side "healing session"** — recovery is
  client-driven from the typed rejection (§4.4, §9.7; Delivery Plan §6.4; §8.4).
- **Inherited: no prompt text, provider name, or model identifier in the Flutter
  client** while hosting self-heal on the live path (R-12; Delivery Plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The control plane MUST remain a small internal surface separate from the
  client-facing API and separately authenticated by operator identity, not clinic
  identity, for entitle-and-grant mutations. `(§4.5)`
- **FR-002**: An operator-authenticated Entitlement management action MUST be able to
  assign plan economics the admission path already reads — quota and budget, period
  bounds, soft threshold — and move the installation's `entitlement` from `pending` to
  `active` so stages 3 and 8 can admit a real request. `(§4.5 Entitlement management;
  §7.3 Entitlement status / key fields; Delivery Plan §3.10 Done when)`
- **FR-003**: An operator-authenticated Capability availability action MUST grant (and,
  where in scope for this activate path, revoke) capability versions for the installation
  or plan by writing `capability_grant` rows. `(§4.5 Capability availability; §7.3
  capability_grant; Delivery Plan §3.10 Done when)`
- **FR-004**: Every entitle-and-grant control-plane mutation MUST be journaled as a
  `control_audit` row carrying the operator identity. `(§4.5 "Every control-plane
  mutation is journaled with the operator identity"; §7.3 control_audit)`
- **FR-005**: An installation that is enrolled but still `pending` MUST remain
  verifiable and MUST NOT be entitled to anything until Entitlement management activates
  it; pending enroll MUST still fail entitlement until activated. `(§4.5 "The line
  between the first two rows"; §7.3 Entitlement status; Delivery Plan §3.12.9 I4)`
- **FR-006**: Any entitle-and-grant control action attempted without operator credentials
  MUST be rejected. `(§4.5; Delivery Plan §3.12.9 I4)`
- **FR-007**: I4 MUST NOT introduce a plan catalogue, billing period close, or
  usage-summary UI; those remain Band G. Operator assignment of economics is explicit
  (Open Decision 15 recommended default). `(§15 OD-15; Delivery Plan §3.10 Done when;
  §4.1 Band G)`
- **FR-008**: The live E2 submit path (hosted on the I3-composed Flutter surface) MUST
  host J2's `context_required` self-heal for `single_shot` capabilities: on
  `context_required`, refresh the manifest cache, resolve the named keys, and resubmit
  **once** with the **same idempotency key**. `(§8.4; §5.2 Self-healing; Consumes J2 /
  I3; Delivery Plan §3.10 Done when)`
- **FR-009**: Automatic self-healing on that live path MUST be bounded to one
  resubmission; a second `context_required` for that action MUST surface the request
  reference to the user with no automatic third attempt. `(§8.4; Consumes J2; Delivery
  Plan §3.12.9 I4)`
- **FR-010**: Conversational capabilities MUST NEVER take the §8.4 `context_required`
  self-healing path on the live submit path. `(§8.4; §5.2 Negotiation; Delivery Plan
  §3.12.9 I4)`

### Key Entities

Not applicable — this slice defines no new entities. It writes into `entitlement`,
`capability_grant`, and `control_audit` shapes already present in the §7.3 D1 logical
model (frozen by A5; extended on enroll by B2) and hosts client behaviour against the
existing `context_required` rejection. Field names and cardinalities are consumed
unchanged from §7.3.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Entitle-and-grant is an infrequent operator action that makes a
  clinic-scale installation admissible without a commercial catalogue or billing UI
  (OD-15; Band G deferred). Live self-heal keeps desktop release cadence survivable when
  a required context key is added (A12; §8.4). No hospital-scale entitlement marketplace
  or fleet self-heal orchestration is introduced (constitution principle I).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker control
  plane — Entitlement management / Capability availability activate-and-grant writes into
  platform D1) and **`frontend/`** (Flutter — host J2 self-heal on the live E2 submit
  path I3 composed). It does not touch `backend/` (Supabase) for entitlement writes; clinic
  context resolution for self-heal continues under caller RLS via E3. Per §14, the gateway
  is a non-primary, additive component: *no domain logic, no business data, no write path
  into Supabase, always optional.*
- **Data Integrity & Security**: Control mutations are operator-authenticated and audited
  (`control_audit` with operator identity) (§4.5; §7.3). Entitlement and grant rows remain
  the sole authority the guard reads for stages 3/5/8; I4 does not bypass the guard.
  Self-heal resolves keys under the caller's own Supabase permissions and RLS (§5.2
  Authorization); the platform never pulls clinic data (§8.4 citing §1.3.1).
- **Failure Handling**: Pending entitlement fails closed for AI admission until
  activated; clinical work continues without AI (A11; constitution principle V). First
  `context_required` recovers once on the live path; a second surfaces the request
  reference rather than looping (§8.4). Control-plane or platform unavailability remains
  an additive degraded state, not a hard lock on clinic workflows (A11; §14).

## Out of Scope

Neighbouring slices and bands this one touches but does not finish:

- **Band G — Commercial surface**: plan catalogue, entitlement management *product* UI,
  usage-summary endpoint / in-app quota display, billing period close from `usage_event`,
  overage policies (Delivery Plan §4.1; Done when explicit exclusion).
- **B2 lifecycle actions**: enroll, suspend, resume, rotate, delete — consumed, not
  rewritten. I4 only adds Entitlement management / grant activation on that surface.
- **B3 / B4**: guard evaluation and Quota DO admission logic — I4 writes the rows they
  already read; it does not reimplement stages 3 or 8.
- **J1 / capability deprecate & retire**: global-scope lifecycle overlay mutations already
  exist on neighbouring paths; I4's Done when is activate-and-grant for an enrolled
  installation, not deprecation windows.
- **J3 / J4**: staged rollout cohorts and token-contract rotation.
- **I1 / I2**: Worker `POST /v1/requests` orchestration and discovery HTTP / config
  readers — consumed via I3; not reimplemented. Do not reimplement I2 discovery
  filtering.
- **I3 live host UX**: provisional draft, degraded non-enrolled / unreachable, production
  mint/submit composition — consumed; I4 only hosts self-heal on that submit path.
- **C2 validator / pre-flight**: `context_required` / `context_invalid` emission —
  consumed via J2; not redefined.
- **H-band / §8.10**: conversational `context_requested` negotiation.
- **Kill switches, routing policy publish/canary, support lookup, operational
  dashboards**: other §4.5 rows not named by I4's Done when.

Prohibitions inherited from delivery plan §6.4, copied verbatim:

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

- **SC-001**: An operator-authenticated activate-and-grant writes entitlement and
  `capability_grant` rows plus a `control_audit` entry carrying the operator identity
  (asserted by T1; Done when; §4.5; §7.3).
- **SC-002**: Activate populates the budget fields admission already reads and moves
  entitlement status to `active` so stages 3 and 8 can admit a real request (asserted by
  T2; Done when).
- **SC-003**: A pending enrollment still fails entitlement until activated (asserted by
  T3; Delivery Plan §3.12.9 I4).
- **SC-004**: Non-operator entitle-and-grant attempts are rejected (asserted by T4;
  Delivery Plan §3.12.9 I4).
- **SC-005**: The live submit path refreshes on first `context_required`, resolves named
  keys, and resubmits once with the same idempotency key (asserted by T5; Done when;
  §8.4).
- **SC-006**: A second `context_required` on that live path surfaces the request
  reference with no automatic third attempt, and conversational capabilities never take
  the path (asserted by T6–T8; §8.4; Delivery Plan §3.12.9 I4).
- **SC-007**: No plan catalogue, billing period close, or usage-summary UI is introduced
  by this slice (asserted by Out of Scope / FR-007; Done when; OD-15; Band G).

## Assumptions

- B2, I3, and J2 are complete on the integration line this slice branches from
  (`Needs: B2, I3, J2`); current `ai/master` includes I1–I3 at `d958566d`.
- B2 already leaves `entitlement` `pending` with zeroed economics on enroll; I4 supplies
  the Entitlement management / grant activation B2 deferred (§4.5; B2 Out of Scope).
- J2 already freezes the self-heal behaviour (including the Flutter heal helper); I4 hosts
  it on the live E2 submit path rather than redefining the bound (J2 Freezes; I3 Out of
  Scope).
- Spec Kit's `create-new-feature.sh --dry-run` allocates against `docs/specs/` and does
  not parse `ai/<NNN>-*` branches, so the number was confirmed from `specs/` (highest
  `054-live-client-invoke`) and applied as **055**.
- Unrelated local dirty (`.cursor/skills/ai-platform-workflow/SKILL.md`,
  `docs/specs/019-home-haytham-desktop/`) is ignored and not part of this slice.
