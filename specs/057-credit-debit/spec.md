# Feature Specification: Declared-weight credit debit in admission (G2)

**Feature Branch**: `ai/057-g2-credit-debit`

**Created**: 2026-09-11

**Status**: Draft

**Input**: Slice `G2` — *Declared-weight credit debit in admission* (Delivery Plan §3.13, row G2).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice lives entirely inside the Cloudflare AI Gateway Worker
> (`ai-platform/`). Per A15's constitution check, the §14 boundary — no domain logic, no
> business data, no write path into Supabase — stands: credit debit, `credit_budget`
> admission, and period `creditsUsed` are platform Quota Durable Object accounting, not
> clinic business data.

## Slice Contract

### Implements

`§4.3.3, §5.1, §8.8, A15` (copied verbatim from the slice's `Canonical` cell in §3.13 of
`docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`).

### Freezes

This slice establishes, for the first time:

- **Declared-weight credit debit at stage 15.** The Quota Durable Object credit call
  debits the resolved manifest's declared `quota_weight` — the capability's declared
  price in AI credits per request, per leg for `conversational` — from the
  installation's monthly credit budget. The debit is a weight from the manifest; the
  request path never sees a price (A15; §5.1 Economics; §4.3.3).
- **Cancelled-request credit debit in full.** A cancelled request still debits the
  declared `quota_weight`, because the provider cost was incurred (A15).
- **Guard-rejection non-debit.** A guard rejection debits nothing because no request
  exists (A15).
- **Credit-budget admission.** The per-installation budget answered at admission is
  denominated in AI credits on a monthly period. Exhausted credit budget returns
  `quota_exhausted` with `{ reset_at }`; there is no overage (A15; §4.3.3; §8.8).
- **Credit-ratio soft threshold.** Crossing the entitlement's soft threshold on the
  credit ratio, with credit budget remaining, answers `{ allowed, degraded: true }` —
  the flag F4 already routes on — rather than refusing (A15; §4.3.3; §8.8).
- **Admission/credit field extension.** The entitlement snapshot gains `credit_budget`,
  the credit RPC gains a `credits` debit, and the period counters gain `creditsUsed`.
  Adding these fields is extension; no existing field changes meaning (A15; Delivery
  Plan §2.3). Token and cost counters remain and still settle actuals, now as
  reconciliation and billing evidence rather than admission (A15; §4.3.3).

Later slices may extend these (G3 reads current-period credits consumed from the Quota
DO) and may not rewrite them (Delivery Plan §2.3).

### Consumes

Contracts frozen by the slices in G2's `Needs` (`G1`, `B4`, `F4`). Changing any is out
of scope by definition:

- **From G1 — Plan catalogue and credit-denominated entitlement** (A15; G1 Freezes):
  the entitlement monthly credit-budget column, whose frozen admission snapshot name is
  `credit_budget`; the plan-populated economics including soft threshold; token and
  cost budgets already on the row, which keep their meanings. G2 debits `credit_budget`
  through the Quota DO; it does not create the column, assign plans, or maintain the
  catalogue.
- **From B4 — Quota Durable Object and admission stage** (§4.3.3; B4 Freezes): the
  per-installation Quota Durable Object; the stage-8 admission RPC that answers the
  four installation-scoped questions (`jti` freshness, idempotency novelty, remaining
  budget, concurrency headroom) in one Durable Object round trip; the separate stage-15
  credit RPC; the two-round-trip request-path I/O (admission then credit); the
  ephemeral store; and the capped fail-open grace policy. G2 extends the snapshot with
  `credit_budget`, the credit RPC with a `credits` debit, and the period counters with
  `creditsUsed`; it does not rewrite the four questions, the one-then-one round-trip
  budget, replay, idempotency, concurrency, or grace.
- **From F4 — Soft-threshold degraded routing** (§8.8; F4 Freezes): the admission
  outcome `{ allowed, degraded: true }` when remaining budget is not exhausted but the
  soft threshold has been crossed, and the routing that consumes that flag
  (`routing_tier = degraded`, `degraded_notice`). G2 sets `degraded` from the credit
  ratio; it does not rewrite F4's routing path, `routing_tier`, or `degraded_notice`.

### Open decisions relied on

None. Amendment A15 settled Open Decisions 2 and 15 as contract changes rather than as
§15 recommended defaults: the quota unit is the AI credit and the period is the
calendar month (OD-2), and a plan catalogue exists (OD-15 settled against its default)
(A15). Quota Durable Object unavailability remains B4 / Open Decision 3 (Consumes B4).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declared-weight credit debit in admission (Priority: P1)

The operator of the gateway sees each admitted request settle against the
installation's monthly credit budget at the capability's declared `quota_weight`. A
conversational leg is one debit of that weight. A cancelled request still costs the
declared weight. A request the guard refuses costs nothing and leaves no journal row.
When the monthly credit budget is gone, admission answers `quota_exhausted` with
`reset_at` and does not lock any non-AI clinic work. When usage crosses the soft
threshold on the credit ratio but credit budget remains, admission allows the request
with the `degraded` flag F4 already routes on. Token and cost counters continue to
record actual (including partial) usage for reconciliation. The request still makes
exactly two Durable Object round trips.

**Why this priority**: G2's `Needs` are G1 (the `credit_budget` column and plan
economics), B4 (the frozen Quota DO admission and credit RPCs), and F4 (routing on the
`degraded` flag). G1 and G2 are sequential: G2 cannot debit a monthly credit budget
that does not yet exist. G2 **extends** B4's frozen admission — snapshot
`credit_budget`, credit RPC `credits`, period `creditsUsed` — which Delivery Plan §2.3
permits because adding a field is extension and no existing field changes meaning.
Token and cost counters remain for reconciliation. G2 rides the existing two Durable
Object round trips; it does not add request-path I/O (Delivery Plan §3.13).

**Independent Test**: The stage-15 credit call debits the manifest's declared
`quota_weight` (per leg for `conversational`), cancelled requests debit in full, guard
rejections debit nothing; admission answers credit-budget exhaustion with
`quota_exhausted` and crosses the soft threshold on the credit ratio into the
`degraded` flag; token and cost counters settle actuals unchanged; the two-round-trip
and no-journal-on-rejection invariants hold (Delivery Plan §3.13 row G2 Done when;
DP-3).

**Acceptance Scenarios**:

1. **Given** an admitted request whose resolved manifest declares `quota_weight` W,
   **When** the stage-15 credit call runs after the call completes, **Then** settlement
   debits exactly W from the installation's monthly credit budget (`creditsUsed`
   increases by W) (Delivery Plan §3.12.10 row G2 *Debit*; A15; §4.3.3; §5.1).
2. **Given** a `conversational` capability whose manifest declares `quota_weight` W,
   **When** each of two legs is independently credited, **Then** each leg debits W
   (`creditsUsed` increases by 2W, not by a single conversation-level debit)
   (Delivery Plan §3.12.10 row G2 *Debit*; A15; §5.1).
3. **Given** a request that is cancelled after the provider call has begun, **When**
   the stage-15 credit call runs, **Then** the declared `quota_weight` is debited in
   full (Delivery Plan §3.12.10 row G2 *Debit*; A15).
4. **Given** a request the guard rejects, **When** the rejection is returned, **Then**
   no credit debit occurs and no journal row is written (Delivery Plan §3.12.10 row G2
   *Debit*; A15).
5. **Given** an installation whose monthly credit budget is exhausted, **When**
   admission asks whether budget remains, **Then** the Quota DO answers no and the
   client receives `quota_exhausted` with `{ reset_at }`; non-AI workflows remain
   usable (Delivery Plan §3.12.10 row G2 *Admission*; §8.8; A15).
6. **Given** an installation whose credit ratio has crossed the entitlement's soft
   threshold and whose credit budget is not exhausted, **When** admission runs,
   **Then** the Quota DO answers `{ allowed, degraded: true }` — the flag F4 routes on
   — and the request is not refused (Delivery Plan §3.12.10 row G2 *Admission*; §8.8;
   §4.3.3; A15).
7. **Given** a completed or cancelled request with provider-reported token and cost
   actuals, **When** the stage-15 credit call runs, **Then** the token and cost
   counters settle those actuals unchanged, including partial usage on cancel, and
   those actuals do not determine the credit debit (Delivery Plan §3.12.10 row G2
   *Invariants*; A15; §4.3.3).
8. **Given** an admitted request that later reaches stage 15, **When** admission and
   credit have both run, **Then** the request made exactly two Durable Object round
   trips and the credit RPC's new `credits` field does not change the meaning of any
   existing field (Delivery Plan §3.12.10 row G2 *Invariants*; A15; §4.3.3; Delivery
   Plan §2.3).

### Test plan

Every named test is required (Delivery Plan §3.11; DP-3). Layer designations are those
named in Delivery Plan §3.12.10 row G2 (*DO unit + integration (spy)*).

| Test name | Layer | Asserts |
| --- | --- | --- |
| `credit_debits_declared_quota_weight` | DO unit | Stage-15 settlement debits exactly the manifest's declared `quota_weight` (Delivery Plan §3.12.10 G2 *Debit*; A15; §4.3.3; §5.1) |
| `conversational_leg_debits_per_leg` | DO unit | A conversational leg debits `quota_weight` per leg; two credited legs debit twice W (Delivery Plan §3.12.10 G2 *Debit*; A15; §5.1) |
| `cancelled_request_debits_full_declared_weight` | DO unit | A cancelled request debits the full declared `quota_weight` (Delivery Plan §3.12.10 G2 *Debit*; A15) |
| `guard_rejection_debits_nothing_and_writes_no_journal_row` | Integration (spy) | A guard rejection debits nothing and writes no journal row; credit is not invoked (Delivery Plan §3.12.10 G2 *Debit*; A15) |
| `credit_budget_exhausted_quota_exhausted_with_reset_at` | DO unit | Exhausted credit budget → `quota_exhausted` with `{ reset_at }`; no overage; additive AI is refused, nothing hard-locks (Delivery Plan §3.12.10 G2 *Admission*; §8.8; A15; §4.3.3) |
| `credit_ratio_soft_threshold_sets_degraded_flag` | DO unit | Crossing the soft threshold on the credit ratio with budget remaining sets `{ allowed, degraded: true }` (Delivery Plan §3.12.10 G2 *Admission*; §8.8; §4.3.3; A15) |
| `below_credit_soft_threshold_not_degraded` | DO unit | Credit ratio below the soft threshold with budget remaining answers allowed without `degraded` (§8.8 else-normal; Delivery Plan §3.11 every branch) |
| `token_and_cost_counters_settle_actuals_unchanged` | DO unit | Token and cost counters settle provider-reported actuals unchanged, including partial usage on cancel; they do not determine the credit debit (Delivery Plan §3.12.10 G2 *Invariants*; A15; §4.3.3) |
| `exactly_two_durable_object_round_trips_per_request` | Integration (spy) | Admitted request: exactly two Quota DO round trips (admission + credit); no third trip (Delivery Plan §3.12.10 G2 *Invariants*; §4.3.3; Delivery Plan §6.4) |
| `credit_rpc_gains_fields_without_changing_existing_meanings` | DO unit | Credit RPC gains `credits`; period counters gain `creditsUsed`; entitlement snapshot gains `credit_budget`; existing token, cost, and other credit-RPC fields keep their meanings (Delivery Plan §3.12.10 G2 *Invariants*; A15; Delivery Plan §2.3) |

Coverage (Delivery Plan §3.11): happy path of declared-weight debit, per-leg
conversational debit, and below-threshold allow; the only error code this slice can
emit — `quota_exhausted` — with `{ reset_at }`; every §8.8 budget branch this slice
owns (exhausted, soft-threshold crossed, normal); cancelled full-weight debit; guard
rejection non-debit and no journal row; token/cost actuals including partial; two
round trips and field-extension without rework. Inherited §6.4 prohibitions asserted
by the spy round-trip and no-journal cases. `rate_limited` remains B3 and is not
emitted here.

### Edge Cases

- **`quota_exhausted`.** The only diagnostic this slice emits. Period credit budget
  consumed → `quota_exhausted` with `{ reset_at }`. There is no overage. An operator
  raises the budget (G1 Entitlement management, not this slice). Nothing hard-locks:
  the additive AI feature is refused and says so; non-AI workflows remain fully usable
  (§8.8; A15; §4.3.3).
- **Soft threshold crossed, credit budget remaining.** Admission allows with
  `{ degraded: true }`. This slice sets the flag; it does not refuse, and it does not
  implement F4's `routing_tier` / `degraded_notice` path (§8.8; §4.3.3; A15).
- **Below the credit-ratio soft threshold, budget remaining.** Normal allow; `degraded`
  is not set (§8.8).
- **Cancelled request.** Credits debit the full declared `quota_weight`; token and
  cost counters still settle partial actuals (A15; §4.3.3).
- **Guard rejection (including credit-budget exhaustion at admission).** Debits
  nothing; writes no journal row; does not invoke the credit RPC. Exhaustion at
  admission is this case for credits: there is no request to settle (A15).
- **Conversational leg.** `quota_weight` is per request, per leg for
  `conversational`. Each credited leg debits W; a conversation is not a single debit
  (§5.1; A15).
- **Token and cost counters.** They settle actuals unchanged and do not determine the
  debit or the admission remaining-budget / soft-threshold decisions (A15; §4.3.3).
- **Two Durable Object round trips.** Admission then credit. No third trip for
  credits, replay, or the degraded decision (A15; §4.3.3; Delivery Plan §6.4; F4
  already froze no second trip for the degraded decision).
- **No price on the request path.** The debit is the manifest weight. No provider
  price appears in the Worker (A15).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The per-installation budget MUST be denominated in AI credits on a
  monthly period. `(§4.3.3; A15)`
- **FR-002**: Settlement MUST debit the capability's declared `quota_weight`, while
  the token and cost counters remain as reconciliation and billing evidence. `(§4.3.3;
  A15)`
- **FR-003**: The Quota Durable Object MUST answer whether credit budget remains
  before the provider call and MUST be credited after the call completes. `(§4.3.3)`
- **FR-004**: The manifest `quota_weight` MUST be the capability's declared price in
  AI credits per request — per leg for `conversational` — and MUST be the unit of the
  per-installation monthly budget. `(§5.1 Economics; A15)`
- **FR-005**: The stage-15 settlement MUST debit the declared `quota_weight` from the
  installation's monthly credit budget. Actual tokens and cost MUST remain journaled
  as billing evidence and reconciliation input and MUST NOT determine the debit.
  `(A15)`
- **FR-006**: A cancelled request MUST still debit the declared `quota_weight`.
  `(A15)`
- **FR-007**: A guard rejection MUST debit nothing, because no request exists, and
  MUST write no journal row. `(A15)`
- **FR-008**: Exhausted monthly credit budget MUST return `quota_exhausted` with
  `{ reset_at }`. There MUST be no overage. `(§8.8; A15)`
- **FR-009**: Crossing the entitlement's soft threshold on the credit ratio, with
  credit budget remaining, MUST answer `{ allowed, degraded: true }` rather than
  refuse. The `degraded` flag MUST be the flag F4 routes on. `(§8.8; §4.3.3; A15)`
- **FR-010**: Quota exhaustion MUST never hard-lock anything: it MUST disable an
  additive feature and say so. A soft threshold MUST downgrade via `degraded` instead
  of refusing outright. `(§4.3.3; A15; §8.8)`
- **FR-011**: Token and cost counters MUST settle actuals unchanged, including
  partial usage from a cancelled request. `(A15; §4.3.3)`
- **FR-012**: The entitlement snapshot MUST gain `credit_budget`, the credit RPC MUST
  gain a `credits` debit, and the period counters MUST gain `creditsUsed`. Existing
  fields MUST keep their meanings. `(A15)`
- **FR-013**: An admitted request MUST make exactly two Durable Object round trips —
  one admission before the provider call and one credit after. G2 MUST NOT add a
  round trip. `(§4.3.3; A15)`
- **FR-014**: The request path MUST never see a price. The debit MUST be the
  manifest's `quota_weight`. No provider price MUST appear in the Worker. `(A15)`
- **FR-015**: Rate limiting and the token-denominated cost ceiling MUST stay separate
  from credit quota. G2 MUST NOT fold either into the credit debit or the credit
  remaining-budget answer. `(§4.3.3; A15)`

### Key Entities

- **Entitlement snapshot `credit_budget`**: The installation's monthly credit budget
  as held by the Quota Durable Object for admission. G1 persists the column; this
  slice first puts it on the admission snapshot. `(A15)`
- **Credit RPC `credits`**: The declared-weight debit applied at stage 15. It does
  not change the meaning of the token and cost actuals the same call already settles.
  `(A15)`
- **Period counter `creditsUsed`**: Credits consumed in the current monthly period.
  Token and cost counters remain alongside it for reconciliation. `(A15; §4.3.3)`
- **Manifest `quota_weight`**: Economics-group declared price in AI credits per
  request, per leg for `conversational`. Consumed by the entitlement/quota path;
  never a discovery wire field. `(§5.1; A15)`

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Declared per-capability credit prices let a small-to-mid
  multi-branch clinic predict what pressing a button costs, without coupling the
  commercial contract to provider pricing (A15). There is no overage, no
  hospital-scale marketplace, and no payment-provider integration (A15; constitution
  principle I).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker): the
  Quota Durable Object, the stage-8 admission remaining-budget answer, and the
  stage-15 credit call. It does not touch `backend/` (Supabase) or `frontend/`
  (Flutter). The gateway is the non-primary, additive component A15's constitution
  check restates: no domain logic, no business data, no write path into Supabase
  (A15).
- **Data Integrity & Security**: Serialized credit accounting stays inside the
  per-installation Quota Durable Object (§4.3.3). `credit_budget` is read from the
  entitlement snapshot G1 already serves through the config cache; this slice does
  not write clinic tables. Token and cost counters remain the reconciliation ledger
  input (A15).
- **Failure Handling**: Credit-budget exhaustion returns `quota_exhausted` with
  `{ reset_at }` and never hard-locks clinical work (§8.8; A15; constitution
  principle V). Soft-threshold pressure sets `degraded` rather than refusing
  (§4.3.3; §8.8). Quota Durable Object unavailability remains B4's capped fail-open
  grace (Consumes B4). This slice does not add retry, a second Durable Object round
  trip, or per-request state.

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **G1 — Plan catalogue and credit-denominated entitlement**: plan CRUD, plan-based
  assignment, `credit_price` table, config-cache serving of `credit_budget`. G2
  debits the budget G1 persisted; it does not create or assign it.
- **G3 — Usage summary endpoint and in-app gauge**: installation-authenticated
  consumed-versus-budget read and Flutter gauge. G2 freezes `creditsUsed` for G3 to
  read; it does not expose a usage endpoint.
- **G4 — Billing period close and invoice generation**: scheduled close, `invoice`
  rows, price-list activation. Token and cost actuals this slice still settles are
  reconciliation input for later billing evidence, not invoices.
- **F4 — Soft-threshold degraded routing**: `routing_tier`, degraded target chain,
  `degraded_notice`. G2 sets the `degraded` flag from the credit ratio; F4 already
  routes on it.
- **B4 — Quota Durable Object admission mechanics**: `jti`, idempotency, concurrency,
  ephemeral expiry, fail-open grace. Extended, not rewritten.
- **B3 — Rate limiting**: composite keys, `rate_limited`, `{ retry_after }`. §8.8
  names that branch; it is not this slice.
- **C2 — Token-denominated cost ceiling / `request_too_large`**: local pre-flight
  remains tokens-to-tokens (A15; §4.3.3).
- **C3 — Journal writer**: G2 asserts the inherited no-journal-on-rejection
  invariant; it does not rewrite `ai_request` / `usage_event`.
- **H3 — Conversational journaling and client chat**: per-leg debit uses the existing
  one-request credit call; this slice introduces no conversation entity and no
  per-request state.
- **Payment collection, self-service enrollment, analytics dashboards** (A15 items
  5–6).

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

- **SC-001**: Stage-15 settlement debits exactly the manifest's declared
  `quota_weight`; a conversational leg debits per leg (asserted by
  `credit_debits_declared_quota_weight` and `conversational_leg_debits_per_leg`).
- **SC-002**: A cancelled request debits the full declared weight; a guard rejection
  debits nothing and writes no journal row (asserted by
  `cancelled_request_debits_full_declared_weight` and
  `guard_rejection_debits_nothing_and_writes_no_journal_row`).
- **SC-003**: Exhausted credit budget returns `quota_exhausted` with `{ reset_at }`;
  crossing the soft threshold on the credit ratio sets `{ degraded: true }` with
  budget remaining; below the threshold does not (asserted by
  `credit_budget_exhausted_quota_exhausted_with_reset_at`,
  `credit_ratio_soft_threshold_sets_degraded_flag`, and
  `below_credit_soft_threshold_not_degraded`).
- **SC-004**: Token and cost counters settle actuals unchanged, including partial
  usage on cancel (asserted by `token_and_cost_counters_settle_actuals_unchanged`).
- **SC-005**: An admitted request makes exactly two Durable Object round trips, and
  the credit RPC gains fields without changing the meaning of any existing field
  (asserted by `exactly_two_durable_object_round_trips_per_request` and
  `credit_rpc_gains_fields_without_changing_existing_meanings`).

## Assumptions

- G1 has persisted the entitlement monthly credit-budget column as snapshot
  `credit_budget` and serves it through the config cache with the A5 warm/cold
  pattern. G2 reads that snapshot; it does not migrate D1.
- B4's Quota Durable Object, stage-8 admission RPC, and stage-15 credit RPC are the
  surfaces extended here. Token and cost counters already settle actuals on that
  credit call.
- F4 already routes on `{ degraded: true }`. G2 changes only which ratio sets the
  flag (the credit ratio), not the routing contract.
- Manifest Economics already include `quota_weight` (§5.1; A4). G2 consumes the
  resolved manifest's declared weight and does not change the manifest schema.
- A `conversational` leg is one independently admitted request, so one stage-15
  credit call. Per-leg debit does not require a conversation entity.
- Open Decision 3 (Quota DO unavailability) remains B4's capped fail-open grace.
  This slice does not reopen it.
- Nothing here ships until the whole product does (DP-1). Independently testable
  means provable by an automated test (DP-3).
