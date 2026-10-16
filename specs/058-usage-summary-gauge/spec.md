# Feature Specification: Usage summary endpoint and in-app gauge (G3)

**Feature Branch**: `ai/058-g3-usage-summary-gauge`

**Created**: 2026-09-11

**Status**: Draft

**Input**: Slice `G3` — *Usage summary endpoint and in-app gauge* (Delivery Plan §3.13, row G3).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice touches the Cloudflare AI Gateway Worker (`ai-platform/`)
> and the Flutter client (`frontend/`). Per A15's constitution check, the §14
> boundary — no domain logic, no business data, no write path into Supabase — stands:
> the usage-summary read is platform Quota DO counters and `usage_rollup`, not clinic
> business data, and the gauge is additive client UI.

## Slice Contract

### Implements

`§7.6, §4.1, A11, A15` (copied verbatim from the slice's `Canonical` cell in §3.13 of
`docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`).

### Freezes

This slice establishes, for the first time:

- **The usage-summary read endpoint.** A client-facing, installation-authenticated read
  that answers current-period credits consumed against budget — live from the Quota
  DO — and prior periods from `usage_rollup`'s quota-weight aggregate. Live and
  historical answers come from different places. This is a different audience from
  the existing operator-only
  quota inspect path; that operator endpoint stays operator-only (A15; §7.3; §7.6;
  Delivery Plan §3.13).
- **Credits-only usage response.** The endpoint answers credits consumed against
  budget. The response carries credits only: no provider prices, no token or cost
  actuals. No analytics dashboard is added (A15; Delivery Plan §3.12.10 row G3).
- **The in-app usage gauge.** The Flutter client renders current-period consumed
  versus budget as a simple gauge. The gauge is AI Feature Surface UI under §4.1:
  it contains no prompt text, model names, provider names, or AI business rules
  (A15; §4.1).
- **Gauge degraded-mode application.** A non-enrolled installation hides the gauge with
  no network probe. Platform unreachability of the gauge renders as a normal state,
  not an error dialog. No AI failure may block a clinical workflow (A11; §4.1
  degraded-mode states; Delivery Plan §3.13 Done when).

Later slices may extend these (V4 renders the same consumed-versus-budget read in
the viewer) and may not rewrite them (Delivery Plan §2.3).

### Consumes

Contracts frozen by the slices in G3's `Needs` (`G2`, `E4`). Changing any is out of
scope by definition:

- **From G2 — Declared-weight credit debit in admission** (A15; G2 Freezes): the
  Quota Durable Object's current-period credit counters — `creditsUsed` against
  entitlement snapshot `credit_budget` — which this slice reads live for the
  current period. G3 does not debit, admit, set `degraded`, or change token and cost
  actuals. Token and cost counters remain reconciliation evidence, not usage-summary
  payload.
- **From E4 — First AI feature surface and degraded mode** (§4.1 AI Feature Surfaces;
  A11; E4 Freezes): the AI Feature Surfaces component, the AI availability flag
  that hides AI affordances for a non-enrolled installation without probing the network,
  and the defined degraded mode (AI unavailable, quota exhausted, and
  offline/unreachable as distinct first-class UI states; unreachability is a normal
  state, not an error dialog; no AI failure blocks a clinical workflow). G3 extends
  that surface with a simple gauge and applies the same hide-without-probe and
  unreachability rules to it; it does not rewrite draft/accept/discard, provisional
  content rules, or request-reference display.

### Open decisions relied on

None. Amendment A15 settled Open Decisions 2 and 15 as contract changes rather than as
§15 recommended defaults: the quota unit is the AI credit and the period is the
calendar month (OD-2), and a plan catalogue exists (OD-15 settled against its default)
(A15). E4 already assumed Open Decision 8's recommended default (AI-enabled flag so
the client can hide affordances without probing); this slice consumes that via E4
and does not reopen it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Usage summary endpoint and in-app gauge (Priority: P1)

An enrolled installation reads current-period credits consumed against its monthly
credit budget from a usage-summary endpoint, sourced live from the Quota Durable
Object, and prior periods from `usage_rollup`'s quota-weight aggregate. The response is credits only. Clinic
staff see that current-period consumed-versus-budget as a simple gauge. A
non-enrolled installation never shows the gauge and does not probe the network for
it. If the platform is unreachable, the gauge path is a normal state, not an error
dialog, and non-AI clinic work continues.

**Why this priority**: G3's `Needs` are G2 (live current-period `creditsUsed` against
`credit_budget` on the Quota DO) and E4 (Flutter AI Feature Surfaces and degraded
mode). G1 and G2 are sequential; G3 and G4 may proceed in parallel once their `Needs`
are met. G3 is a read surface, not on the request-path latency budget (Delivery Plan
§3.13). The endpoint is installation-authenticated and client-facing — a different
audience from the control plane (Delivery Plan §3.13).

**Independent Test**: An authenticated installation reads current-period credits
consumed against budget (live from the Quota DO) and prior periods from
`usage_rollup`'s quota-weight aggregate; the response carries credits only; the Flutter client renders a
simple gauge, hides it for non-enrolled installations without probing, and renders
platform unreachability as a normal state (Delivery Plan §3.13 row G3 Done when;
DP-3).

**Acceptance Scenarios**:

1. **Given** an authenticated installation with current-period Quota DO credit
   counters, **When** it reads the usage-summary endpoint, **Then** the current-period
   answer is credits consumed against budget sourced live from the Quota DO
   (Delivery Plan §3.12.10 row G3 *Endpoint*; A15; §7.6).
2. **Given** an authenticated installation with prior-period `usage_rollup` rows,
   **When** it reads the usage-summary endpoint, **Then** prior periods are answered
   from `usage_rollup`'s quota-weight aggregate — not from the Quota DO and not by
   scanning `usage_event` (Delivery Plan §3.12.10 row G3
   *Endpoint*; A15; §7.3; §7.6).
3. **Given** a caller with no installation authentication, **When** it reads the
   usage-summary endpoint, **Then** the Worker returns taxonomy unauthorized
   (Delivery Plan §3.12.10 row G3 *Endpoint*).
4. **Given** an authenticated usage-summary read, **When** the response is returned,
   **Then** it carries credits only — no provider prices, no token or cost actuals
   (Delivery Plan §3.12.10 row G3 *Endpoint*; A15).
5. **Given** an enrolled, reachable installation, **When** the usage gauge is shown,
   **Then** it renders consumed versus budget (Delivery Plan §3.12.10 row G3
   *Client*; A15).
6. **Given** a non-enrolled installation, **When** the client would otherwise offer
   the usage gauge, **Then** the gauge is hidden and no network probe is made
   (Delivery Plan §3.12.10 row G3 *Client*; A11; §4.1).
7. **Given** an enrolled installation whose platform is unreachable, **When** the
   client would otherwise read the usage-summary endpoint, **Then** it renders a
   normal unreachable state, not an error dialog, and clinical work is not blocked
   (Delivery Plan §3.12.10 row G3 *Client*; A11).

---

### Test plan

Every named test is required (Delivery Plan §3.11; DP-3). Layer designations are
those named in Delivery Plan §3.12.10 row G3 (*Workers integration + Flutter widget
(spy)*).

| Test name | Layer | Asserts |
| --- | --- | --- |
| `usage_summary_current_period_live_from_quota_do` | Workers integration | Authenticated installation: current-period credits consumed against budget sourced live from the Quota DO (Delivery Plan §3.12.10 G3 *Endpoint*; A15; §7.6) |
| `usage_summary_prior_periods_from_usage_rollup` | Workers integration | Prior periods answered from `usage_rollup`'s quota-weight aggregate, not from a `usage_event` scan (Delivery Plan §3.12.10 G3 *Endpoint*; A15; §7.3; §7.6) |
| `usage_rollup_carries_quota_weight_aggregate` | Workers integration | `usage_rollup` carries the quota-weight aggregate summed from the ledger's per-request `quota weight`; the existing count, token, and cost aggregates keep their meanings (§7.3; Delivery Plan §2.3; A15) |
| `usage_summary_live_and_historical_from_different_sources` | Workers integration (spy) | Live current-period answer is not served from `usage_rollup`; historical answer is not served from the Quota DO (§7.6 constraint; Delivery Plan §3.11 every named boundary) |
| `usage_summary_unauthenticated_taxonomy_unauthorized` | Workers integration | Unauthenticated caller → taxonomy unauthorized (Delivery Plan §3.12.10 G3 *Endpoint*; Delivery Plan §3.11 every error code) |
| `usage_summary_credits_only_no_prices_tokens_or_cost_actuals` | Workers integration | Response carries credits only — no provider prices, no token or cost actuals (Delivery Plan §3.12.10 G3 *Endpoint*; A15) |
| `gauge_renders_consumed_versus_budget` | Flutter widget | Enrolled and reachable: the gauge renders consumed versus budget (Delivery Plan §3.12.10 G3 *Client*; A15) |
| `gauge_non_enrolled_hides_with_no_network_probe` | Flutter widget (spy) | Non-enrolled: gauge hidden; network spy shows no probe (Delivery Plan §3.12.10 G3 *Client*; A11; §4.1) |
| `gauge_unreachable_is_normal_state_not_error_dialog` | Flutter widget (spy) | Platform unreachability → normal state, not an error dialog; clinical work not blocked (Delivery Plan §3.12.10 G3 *Client*; A11) |

Coverage (Delivery Plan §3.11): happy path of current-period live read, prior-period
rollup read, and enrolled gauge render; the only error code this slice can emit —
taxonomy unauthorized for an unauthenticated caller; every client branch the slice
states (enrolled reachable shows gauge, non-enrolled hides with no probe, unreachable
is a normal state); the §7.6 live-versus-historical source split; the §7.3
quota-weight aggregate extension on `usage_rollup`; credits-only
payload. Inherited §6.4 prohibitions: no prompt text, provider name, or model
identifier in the Flutter client (R-12 / §4.1); this read is not on the request path
and MUST NOT add a second Quota Durable Object round trip or a second R2 object per
request; no per-request server-side state. `quota_exhausted` remains G2 admission
and is not emitted by this read. Invoice generation remains G4. The operator quota
inspect endpoint remains operator-only and is not this slice.

### Edge Cases

- **Unauthenticated caller.** The only diagnostic this slice emits. Usage-summary
  read without installation authentication → taxonomy unauthorized (Delivery Plan
  §3.12.10 G3 *Endpoint*).
- **Non-enrolled installation.** Gauge hidden; no network probe. AI availability is
  already known client-side (Consumes E4). Clinical work continues (A11).
- **Platform unreachable / offline.** First-class normal state for the gauge, not
  an error dialog; does not block non-AI workflows (A11; Delivery Plan §3.12.10 G3
  *Client*).
- **Live versus historical sources.** Current-period credits consumed against budget
  come from the Quota DO. Prior periods come from `usage_rollup`'s quota-weight
  aggregate — the pre-aggregated sum of the ledger's per-request `quota weight`;
  the read never scans `usage_event`. The two answers
  deliberately come from different places (§7.3; §7.6).
- **Credits only.** The usage-summary response does not carry provider prices, token
  actuals, or cost actuals (A15; Delivery Plan §3.12.10 G3 *Endpoint*).
- **Quota position on the gauge.** Consumed versus budget is the usage surface,
  including when consumed meets budget. That is not an error dialog and does not
  hard-lock clinical work (A11; A15). Admission refusal on exhaustion remains G2.
- **Occasional read.** Usage summary is an occasional read, off the request-path
  latency budget (§7.6; Delivery Plan §3.13). It MUST NOT add request-path I/O.
- **Operator quota inspect.** The existing operator-only quota inspect path stays
  operator-only. This slice does not open it to installations (Delivery Plan §3.13).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A usage-summary read endpoint MUST answer current-period credits
  consumed against budget, live from the Quota DO, and history from `usage_rollup`.
  `(A15; §7.6)`
- **FR-002**: Live current-period counters MUST come from the Quota DO and historical
  answers MUST come from `usage_rollup`. Those answers MUST come from different
  places. `(§7.6)`
- **FR-003**: The Flutter client MUST render the usage surface as a simple gauge of
  consumed versus budget. No analytics dashboard MUST be added. `(A15; §4.1)`
- **FR-004**: The usage-summary response MUST carry credits only. It MUST NOT carry
  provider prices, token actuals, or cost actuals. `(A15)`
- **FR-005**: The usage-summary read MUST serve the Flutter client's usage gauge.
  `(A15; §4.1)`
- **FR-006**: The usage-summary endpoint MUST NOT answer an unauthenticated caller.
  `(A15; §4.1)`
- **FR-007**: None of the client components this slice adds or extends MUST contain
  prompt text, model names, provider names, or AI business rules. `(§4.1)`
- **FR-008**: A non-enrolled installation MUST hide the usage gauge entirely and MUST
  NOT probe the network for it. `(A11; §4.1)`
- **FR-009**: Platform unreachability of the usage gauge MUST render as a normal
  state rather than an error dialog. `(A11)`
- **FR-010**: No AI failure, including usage-summary unreachability, MUST block a
  clinical workflow. `(A11)`
- **FR-011**: The usage-summary read MUST NOT write clinic business data and MUST NOT
  open a write path into Supabase. `(A15)`
- **FR-012**: Usage summary MUST be an occasional read, not an every-request path.
  `(§7.6)`
- **FR-013**: Prior-period credits MUST come from `usage_rollup`'s quota-weight
  aggregate — the pre-aggregated sum of `usage_event`'s per-request `quota weight`.
  This slice MUST extend `usage_rollup` with that aggregate and extend the F3
  rollup aggregation to sum the ledger's `quota weight`, as Delivery Plan §2.3
  extension: a field is added and no existing rollup field (dimensions, counts,
  tokens, cost) changes meaning. The usage-summary read MUST NOT scan
  `usage_event`, MUST NOT source history from the Quota DO, and MUST NOT introduce
  a new table. `(§7.3; §7.6; Delivery Plan §2.3; A15)`

### Key Entities

- **Usage-summary response**: The credits-only read this slice freezes: current-period
  credits consumed against budget from the Quota DO, and prior periods from
  `usage_rollup`'s quota-weight aggregate. It is not a D1 entity and introduces no
  table; the slice extends the existing `usage_rollup` row with the quota-weight
  aggregate — a column added under Delivery Plan §2.3, not a new table.
  `(A15; §7.3; §7.6; Delivery Plan §2.3)`

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: A small-to-mid multi-branch clinic sees current-period credits
  consumed against its monthly budget as a simple gauge, in the platform's own
  credit unit, without an analytics dashboard or a payment-provider integration
  (A15; constitution principle I). The gauge hides when the installation is not
  enrolled and does not interrupt non-AI work when the platform is unreachable
  (A11; constitution principle V).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker:
  the usage-summary read endpoint) and **`frontend/`** (Flutter: the simple gauge
  and its degraded-mode application). It does not touch `backend/` (Supabase).
  The gateway is the non-primary, additive component A15's constitution check
  restates: no domain logic, no business data, no write path into Supabase (A15).
- **Data Integrity & Security**: Current-period credits are read live from the
  per-installation Quota Durable Object G2 already accounts; prior periods are read
  from `usage_rollup`'s quota-weight aggregate. The endpoint is installation-authenticated; unauthenticated
  callers are rejected. The operator quota inspect path stays operator-only. No
  clinic table is written. Credits only: no provider price appears in this response
  (A15).
- **Failure Handling**: Unauthenticated reads return taxonomy unauthorized. A
  non-enrolled installation hides the gauge with no probe. Platform unreachability
  is a normal state, not an error dialog, and does not block clinical workflows
  (A11). This slice does not add retry, caching, a second request-path Durable
  Object round trip, or per-request state.

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **G2 — Declared-weight credit debit in admission**: stage-15 debit, `quota_exhausted`
  admission, credit-ratio `degraded` flag. G3 reads `creditsUsed` / `credit_budget`;
  it does not admit or debit.
- **G4 — Billing period close and invoice generation**: scheduled close, `invoice`
  rows, `credit_price` activation. G3 reads `usage_rollup`; it does not freeze a
  period or issue invoices.
- **G1 — Plan catalogue and credit-denominated entitlement**: plan CRUD, assignment,
  `credit_budget` persistence. G3 does not assign plans or change budgets.
- **E4 — First AI feature surface and degraded mode**: draft/accept/discard,
  provisional content, request-reference display. G3 extends the surface with a
  gauge and reuses degraded mode; it does not rewrite those contracts.
- **F3 — Support lookup, retention, usage rollups**: the scheduled job's cadence,
  retention, purge, and reconciliation. G3 extends the rollup row and its
  aggregation with the quota-weight sum — a field added, no existing field's
  meaning changed (Delivery Plan §2.3) — and reads the rollup; it does not
  otherwise change the scheduled job.
- **Quota DO as a history source**: historical answers never come from the Quota DO;
  its live counters are current-period only (§7.6).
- **V4 — Viewer commercial surface**: the viewer's per-installation credit gauge
  against this endpoint. Out of this slice.
- **Operator `GET /control/installations/:id/quota`**: stays operator-only. G3 may
  reuse its Durable Object inspect path internally; it MUST NOT expose that
  operator route to installations (Delivery Plan §3.13).
- **Payment collection, self-service enrollment, analytics dashboards** (A15 items
  5–6).
- **Capability request path** (`POST /v1/requests`, admission, credit, streaming).

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

- **SC-001**: An authenticated installation reads current-period credits consumed
  against budget live from the Quota DO, and prior periods from `usage_rollup`'s
  quota-weight aggregate,
  with live and historical answers from different places (asserted by
  `usage_summary_current_period_live_from_quota_do`,
  `usage_summary_prior_periods_from_usage_rollup`,
  `usage_rollup_carries_quota_weight_aggregate`, and
  `usage_summary_live_and_historical_from_different_sources`).
- **SC-002**: An unauthenticated caller receives taxonomy unauthorized (asserted by
  `usage_summary_unauthenticated_taxonomy_unauthorized`).
- **SC-003**: The usage-summary response carries credits only — no provider prices,
  no token or cost actuals (asserted by
  `usage_summary_credits_only_no_prices_tokens_or_cost_actuals`).
- **SC-004**: The Flutter client renders consumed versus budget as a simple gauge
  when enrolled and reachable (asserted by `gauge_renders_consumed_versus_budget`).
- **SC-005**: A non-enrolled installation hides the gauge with no network probe, and
  platform unreachability renders as a normal state rather than an error dialog
  (asserted by `gauge_non_enrolled_hides_with_no_network_probe` and
  `gauge_unreachable_is_normal_state_not_error_dialog`).

## Assumptions

- G2 has frozen Quota DO period counters `creditsUsed` against snapshot
  `credit_budget`. G3 reads those live for the current period and does not debit.
- F3 already produces `usage_rollup` from `usage_event`, and the ledger already
  records `quota weight` per request (A15; §7.3). G3's `Needs` are G2 and E4; the
  rollup table is an earlier-band store this slice reads and extends — with the
  quota-weight aggregate only, as Delivery Plan §2.3 extension — and does not
  otherwise rewrite.
- E4 has frozen the AI availability flag and degraded-mode UI. G3 applies those
  contracts to the gauge and does not re-implement enrollment storage.
- The existing operator-only quota inspect path may be reused internally as a
  Durable Object inspect implementation; the route and its operator audience stay
  as they are (Delivery Plan §3.13).
- The architecture names the usage-summary read by its sources and credits-only
  semantics, not by an HTTP path or JSON field list. Plan-time contracts may name
  the wire without rewriting those semantics or G2's counter names.
- A15 settled the quota unit (AI credit) and calendar month. This slice does not
  reopen OD-2.
- Nothing here ships until the whole product does (DP-1). Independently testable
  means provable by an automated test (DP-3).
