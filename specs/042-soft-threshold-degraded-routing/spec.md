# Feature Specification: Soft-threshold degraded routing

**Feature Branch**: `ai/042-f4-soft-threshold-degraded-routing`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `F4` — "Soft-threshold degraded routing" (delivery plan §3.7, band F).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.7, row F4):

> §4.3.3, §8.8, §4.3.7

### Freezes

Contracts this slice establishes for the first time:

- The **soft-threshold admission outcome** — when remaining budget is not exhausted but
  the entitlement's soft threshold has been crossed, the Quota DO admission answer is
  `{ allowed, degraded: true }` (budget remaining, with the degraded flag set), not a
  refusal (§8.8; §4.3.3). Hard exhaustion remains `{ allowed: false }` /
  `quota_exhausted` as B4 already froze; F4 extends the admission answer with the
  soft-threshold branch B4 deferred (B4 Freezes; delivery plan §2.3).
- The **gateway-internal `routing_tier` signal** — when admission returns `degraded:
  true`, the gateway sets `routing_tier = degraded` on the in-memory request context
  (otherwise `standard`) and that value is what is persisted as
  `ai_request.routing_tier`; the tier is never accepted from the client (§4.3.7; §8.8).
- The **soft-threshold → degraded-tier routing path** — with `routing_tier = degraded`,
  the provider router matches `rules[].match.tiers` for the degraded tier and selects
  the capability's degraded target chain rather than refusing the request (§4.3.7;
  §8.8; delivery plan §3.7 Done when).
- The **client-visible `degraded_notice` boolean** — on the soft-threshold accept path
  the client receives only `accepted { degraded_notice }` (boolean); the client cannot
  send a tier or soft-threshold trigger (§4.3.7; §8.8).
- The **hard-exhaustion non-lockout outcome** — period quota or budget exhaustion
  returns `quota_exhausted` (with period reset — `{ reset_at }` per §8.8, carried by A2's
  frozen `period_reset` supplementary field — sourced from the entitlement snapshot's
  period end that B4's admission already reads), disables the
  additive AI feature and says so, and never hard-locks any clinical or non-AI workflow
  (§4.3.3; §8.8; constitution principle V; delivery plan §3.7 Done when).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (D2, B4). Changing any is out of scope by
definition:

- **From B4 (Quota Durable Object and admission)**: the **per-installation Quota Durable
  Object**, the **stage-8 admission RPC** that answers the four installation-scoped
  questions (including remaining budget) in exactly one Durable Object round trip, the
  **separate credit RPC**, the entitlement snapshot read through the config cache
  (including soft threshold), and hard **budget exhaustion → `quota_exhausted`**. F4
  extends the admission answer with the soft-threshold `{ degraded }` branch and does
  not rewrite admission's four questions, credit, ephemeral store, fail-open grace, or
  the one-round-trip budget (B4 Freezes; §4.3.3; §8.8).
- **From D2 (provider port, fake adapter, and routing policy)**: the
  **routing-policy-as-data contract** — versioned policy yielding an ordered candidate
  chain, including matching on `rules[].match.tiers` (`standard` / `degraded`),
  recording selection reason / `routing_decision`, and **stateless** routing that
  depends only on capability, policy, and this request. F4 supplies the soft-threshold
  `routing_tier` signal D2 already matches; it does not redefine policy document shape,
  cost-class selection, feature filtering, installation overrides, or the provider port
  (D2 Freezes; §4.3.7).

Transitive contracts F4 relies on without redefining them: A5's `entitlement` soft
threshold and its `ai_request.routing_tier` / `routing_decision` columns (§7.3; A5
data-model §2.6 — both nullable, gateway-written); C3's existing request-row journal
writer, which F4 extends by populating `ai_request.routing_tier` with the gateway-set
tier and does not otherwise rewrite (§7.3; C3 Freezes); A2's `quota_exhausted` taxonomy
code and its frozen supplementary field `period_reset`, which is the wire carrier for the
period reset the §8.8 diagram writes as `reset_at` (A2 Freezes; §8.8); A6's
accepted-event / error wire surface that carries `degraded_notice` and the
`quota_exhausted` period reset.

### Open decisions relied on

- **Open Decision 2** — *Quota period and unit: requests, tokens, or cost?* Recommended
  default: "Cost-based budget with a request-count guard; requests alone cannot bound
  spend (A6)." F4 compares usage against the entitlement soft threshold and budget that
  B4 already reads from the entitlement snapshot under this default; F4 does not choose
  a different unit (§15 #2; B4 Open decisions; §4.3.3).
- No other §15 decision is assumed. Soft-threshold *routing* behaviour is fully named in
  §4.3.3, §8.8, and §4.3.7; Quota DO unavailability remains B4 / Open Decision 3.

## Clarifications

### Session 2026-08-02

- Q: How should integration tests fixture “soft threshold crossed, budget remaining” (and the below-threshold / hard-exhaustion counterparts)? → A: Seed Quota DO counters / entitlement snapshot into the target region (below soft, at/above soft with budget left, hard-exhausted) before the request under test `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Soft-threshold degraded routing (Priority: P1)

As the AI Gateway Worker, when an installation's period usage crosses the entitlement
soft threshold but budget remains, admission allows the request with `degraded: true`,
the gateway sets `routing_tier = degraded`, the router matches the policy's degraded
tier, and the client is accepted with `degraded_notice` — the request is downgraded to
the cheaper degraded target chain rather than refused. When budget is fully exhausted,
admission returns `quota_exhausted` with period reset, the additive AI feature is
disabled with a clear reason (including the admin path for the operator), and no
clinical or non-AI workflow is hard-locked. Traffic that has not crossed the soft
threshold is admitted and routed on the standard tier unchanged.

**Why this priority**: F4 sits where it does because its `Needs` (D2, B4) are the point
at which the Quota DO can answer remaining budget and the router can already match a
degraded tier from policy — what remains is wiring the soft-threshold signal through
admission into `routing_tier` and honouring constitution principle V under quota
pressure (delivery plan §3.7; §4.3.3; §8.8).

**Independent Test**: Crossing a soft quota threshold downgrades routing to the
capability's degraded tier rather than refusing; exhaustion disables an additive feature
and says so, and never hard-locks anything (delivery plan §3.7 Done when).

**Acceptance Scenarios**:

1. **Given** an installation whose period usage has crossed the entitlement soft
   threshold but whose budget is not exhausted, and a routing policy with distinct
   standard and degraded target chains for the capability, **When** a request is
   admitted and routed, **Then** the Quota DO returns `{ allowed, degraded: true }`, the
   gateway sets `routing_tier = degraded`, the router selects the degraded-tier target
   chain, and the client receives `accepted { degraded_notice }` (boolean true) — the
   request is not refused. *(soft_threshold_selects_degraded_target)*
2. **Given** an installation whose period budget is exhausted, **When** a request is
   admitted, **Then** the gateway returns `quota_exhausted` with `{ reset_at }`, the
   additive AI feature is disabled with a clear reason and the admin path is available,
   and no clinical or non-AI workflow is hard-locked or blocked. *(hard_exhaustion_quota_exhausted_admin_path_no_lock)*
3. **Given** an installation whose period usage is below the soft threshold and whose
   budget remains, **When** a request is admitted and routed, **Then** admission allows
   without `degraded`, `routing_tier` is `standard`, the router selects the standard-tier
   chain, and the accepted event carries no soft-threshold degradation (below-threshold
   traffic is unaffected). *(below_threshold_traffic_unaffected)*

### Test plan

Layer from delivery plan §3.11.6 Band F row F4: **Integration**. Named cases (floor from
§3.11.6; coverage rule §3.10 applies):

| # | Test name | Layer | Asserts |
| --- | --- | --- | --- |
| 1 | `soft_threshold_selects_degraded_target` | Integration | Soft threshold crossed → `{ degraded: true }` → `routing_tier = degraded` → degraded target chain; `accepted { degraded_notice }`; not refused (§3.11.6 F4; §8.8; §4.3.7) |
| 2 | `hard_exhaustion_quota_exhausted_admin_path_no_lock` | Integration | Budget exhausted → `quota_exhausted` with `{ reset_at }`; additive feature disabled with clear reason / admin path; nothing hard-locked (§3.11.6 F4; §8.8; §4.3.3) |
| 3 | `below_threshold_traffic_unaffected` | Integration | Below soft threshold → standard tier / no degraded_notice; routing unchanged (§3.11.6 F4; §8.8) |
| 4 | `soft_threshold_tier_not_accepted_from_client` | Integration | Client-supplied tier / degraded trigger is ignored; only gateway-set `routing_tier` applies (§4.3.7; §8.8; §3.10 prohibition / branch) |
| 5 | `soft_threshold_persists_routing_tier` | Integration | Soft-threshold path persists `ai_request.routing_tier = degraded` (and standard otherwise) (§4.3.7; §3.10 happy path) |
| 6 | `soft_threshold_no_second_quota_do_round_trip` | Integration (spy) | Soft-threshold admission still uses exactly one Quota DO round trip — no second trip for the degraded decision (§8.8; delivery plan §6.4; §3.10 inherited prohibition) |
| 7 | `quota_exhausted_only_error_code_on_hard_exhaustion` | Integration | Hard exhaustion emits `quota_exhausted` and no other taxonomy code from this slice's soft/hard branches (§8.8; §3.10 every error code) |

---

### Edge Cases

- **Error codes this slice can emit.** Hard budget exhaustion emits `quota_exhausted`
  (§8.8; §6.1 stage 8 via B4). Soft-threshold crossing emits no error — the request is
  accepted with `degraded_notice`. Rate-limit denial (`rate_limited`) remains B3 and is
  out of scope even though it appears in the §8.8 diagram.
- **Soft threshold crossed, budget remaining.** Admission allows with `degraded: true`;
  gateway sets `routing_tier = degraded`; router matches degraded tier; client gets
  `degraded_notice` (§8.8; §4.3.7).
- **Budget exhausted (hard).** Refusal with `quota_exhausted { reset_at }`; AI affordance
  disabled with clear reason; all non-AI workflows remain fully usable — never a product
  hard-lock (§8.8; §4.3.3; A11 / constitution principle V).
- **Below soft threshold.** Normal allow path; `routing_tier = standard`; no
  `degraded_notice` (§8.8).
- **Client cannot trigger degradation.** `routing_tier` / soft-threshold is
  gateway-internal; the client may only *receive* `degraded_notice` and cannot send a
  tier (§4.3.7; §8.8).
- **No second Quota DO round trip.** Soft-threshold evaluation rides the existing
  stage-8 admission call; F4 must not add a second Durable Object round trip (delivery
  plan §6.4; B4 Freezes).
- **Router already knows tiers.** Empty or missing degraded-tier rules are a policy-data
  problem under D2's catch-all / first-match rules; F4 does not invent fallback targets
  outside the active routing policy (§4.3.7; Consumes D2).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Quota exhaustion MUST never hard-lock anything; it MUST disable an additive
  feature and say so (§4.3.3).
- **FR-002**: Crossing a soft quota threshold MUST be able to downgrade routing to a
  cheaper / degraded model instead of refusing the request outright (§4.3.3).
- **FR-003**: When period budget is exhausted, the Quota DO MUST answer no with period
  reset — the value being the period end already present on the entitlement snapshot the
  DO reads for the admission decision — and the gateway MUST return `quota_exhausted`
  carrying that reset (`{ reset_at }` in the §8.8 diagram; on the wire it is A2's frozen
  `quota_exhausted` supplementary field `period_reset`, which F4 populates rather than
  renames) (§8.8; A2 Freezes).
- **FR-004**: On hard exhaustion the AI affordance MUST be disabled with a clear reason,
  the admin path MUST be available to address quota state, and all non-AI workflows MUST
  remain fully usable (§8.8; delivery plan §3.7 Done when; §3.11.6 F4).
- **FR-005**: When the soft threshold is crossed but budget remains, the Quota DO MUST
  answer yes with `{ degraded: true }` (§8.8).
- **FR-006**: On soft-threshold allow, the gateway MUST set `routing_tier = degraded` on
  the   in-memory request context (otherwise `standard`) and MUST persist that value as
  `ai_request.routing_tier` through C3's existing request-row journal writer — the column
  is A5's (§7.3; A5 data-model §2.6); F4 introduces no schema change (§8.8; §4.3.7).
- **FR-007**: With `routing_tier = degraded`, the provider router MUST match
  `rules[].match.tiers` for the degraded tier and select the degraded target chain
  rather than refuse (§8.8; §4.3.7).
- **FR-008**: On the soft-threshold accept path the client MUST receive
  `accepted { degraded_notice }` (boolean); the client MUST NOT be able to send a tier
  or soft-threshold trigger — the degraded signal is internal, not a wire field the
  client supplies (§4.3.7; §8.8).
- **FR-009**: Soft-threshold evaluation MUST ride the existing single Quota DO admission
  round trip; F4 MUST NOT add a second Quota DO round trip per request (delivery plan
  §6.4; §8.8; B4 Freezes).
- **FR-010**: Below-threshold traffic MUST remain on the standard allow / standard-tier
  path and MUST NOT receive soft-threshold degradation (delivery plan §3.11.6 F4; §8.8).

### Key Entities

Not applicable — this slice defines no entities. It extends the B4 admission answer with
the soft-threshold `{ degraded }` branch and supplies the gateway `routing_tier` /
`degraded_notice` signal that D2's existing routing-policy and A5's
`ai_request.routing_tier` column already name. No migration belongs to this slice: the
`routing_tier` / `routing_decision` columns are part of A5's frozen §7.3 schema, and F4
only writes the tier through C3's existing journal writer.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Soft-threshold downgrade and hard-exhaustion disable-without-lock keep
  AI additive under quota pressure for small-to-mid multi-branch clinics; subscription
  limits never become a clinic hard-lock (constitution principle V; §4.3.3; §8.8).
- **Layer Placement**: Behaviour lives in `ai-platform/` (Cloudflare Worker) — Quota DO
  soft-threshold branch, gateway `routing_tier` / `degraded_notice` wiring, and
  integration with the D2 router. No Supabase domain writes and no Flutter prompt /
  provider / model identifiers. The gateway remains a non-primary, additive component:
  no domain logic, no business data, no write path into Supabase, always optional (§14
  acknowledgement).
- **Data Integrity & Security**: Soft threshold and budget are read from the existing
  entitlement snapshot (A5 / B4); `routing_tier` is gateway-set and journaled on
  `ai_request`; clients cannot inject tier. Hard exhaustion uses the frozen
  `quota_exhausted` taxonomy code (A2 / B4).
- **Failure Handling**: Soft threshold → degrade routing and notify; hard exhaustion →
  disable AI affordance with clear reason / admin path and leave all non-AI workflows
  usable; never hard-lock the product (§4.3.3; §8.8; constitution principle V).

## Out of Scope

- **B3 rate limiting** — `rate_limited` / burst denial on composite keys remains B3 even
  though it appears in the §8.8 sequence diagram; F4 owns only soft-threshold and hard
  exhaustion branches of that diagram.
- **B4 admission core** — the four admission questions, credit RPC, ephemeral store, and
  fail-open grace are frozen by B4; F4 only extends the allow path with `{ degraded }`
  and must not rewrite them.
- **D2 routing-policy document / port** — policy schema, cost-class min, feature
  filters, installation overrides, fake adapter, and classification stay D2; F4 only
  supplies `routing_tier`.
- **E4 client degraded-mode UX chrome** — first-class UI states for AI unavailable /
  quota exhausted / offline remain E4 / A11; F4 supplies the gateway outcomes those
  surfaces already expect (`quota_exhausted`, `degraded_notice`).
- **F5 load and cost tests** — metered footprint assertions are F5.
- **J3 staged routing-policy rollout** — cohort activation of a new policy version is J3.
- **Health-based provider routing / circuit breakers** — deliberate §9.14 deferrals;
  not added because they look prudent (R-20).
- Delivery plan §6.4 prohibitions this slice inherits and must not violate:
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

- **SC-001**: An automated integration test proves that crossing the soft threshold
  selects the degraded target chain and accepts with `degraded_notice` rather than
  refusing (delivery plan §3.7 Done when; §3.11.6 F4; T1).
- **SC-002**: An automated integration test proves hard exhaustion returns
  `quota_exhausted` with `{ reset_at }`, disables the additive feature with a clear
  reason / admin path, and does not hard-lock any non-AI workflow (delivery plan §3.7
  Done when; §3.11.6 F4; T2).
- **SC-003**: An automated integration test proves below-threshold traffic remains on
  the standard path with no soft-threshold degradation (delivery plan §3.11.6 F4; T3).
- **SC-004**: Automated tests prove the client cannot inject `routing_tier`, that
  `ai_request.routing_tier` is persisted from the gateway signal, that soft-threshold
  admission still uses exactly one Quota DO round trip, and that hard exhaustion emits
  only `quota_exhausted` from this slice's branches (T4–T7; §3.10; §4.3.7; §8.8).

## Assumptions

- D2 and B4 are complete on `ai/master`; F4 extends B4's admission allow path and
  supplies the soft-threshold signal D2's router already matches (delivery plan §3.7
  Needs; B4 / D2 Freezes).
- The entitlement soft threshold value is already present on the entitlement snapshot
  frozen by A5 and read by B4; F4 does not invent a numeric default for that field
  (§4.3.3; A5 / B4 Consumes).
- Open Decision 2's recommended default (cost-based budget with a request-count guard)
  remains in force for how period budget and soft threshold are interpreted (§15 #2).
- Protocol-adapter wire shapes for `accepted { degraded_notice }` and
  `quota_exhausted { reset_at }` are those named in §8.8 / §4.3.7 and frozen by A6 / A2;
  F4 does not invent additional client payload fields.
- The platform does not ship until the whole product does (DP-1); "independently
  testable" means provable by an automated integration suite, not demonstrable to a
  user (DP-3).
