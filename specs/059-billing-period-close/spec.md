# Feature Specification: Billing period close and invoice generation (G4)

**Feature Branch**: `ai/059-g4-billing-period-close`

**Created**: 2026-09-11

**Status**: Draft

**Input**: Slice `G4` — *Billing period close and invoice generation* (Delivery Plan §3.13, row G4).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice lives entirely inside the Cloudflare AI Gateway Worker
> (`ai-platform/`). Per A15's constitution check, the §14 boundary — no domain logic, no
> business data, no write path into Supabase — stands: period close is a scheduled job
> in the existing Worker, and invoices and the versioned credit price list are platform
> D1 records, not clinic business data.

## Slice Contract

### Implements

`§7.3, §4.5, §12.3, A15` (copied verbatim from the slice's `Canonical` cell in §3.13 of
`docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`).

### Freezes

This slice establishes, for the first time:

- **The `invoice` entity.** One issued invoice per installation per period: installation,
  period, credits consumed, credit price list version, total, status, `issued_at`
  (§7.3; A15). Forward-only migration creates the table; this slice is the first writer.
- **Scheduled billing period close.** A scheduled job in the existing Worker freezes
  the calendar month's `usage_rollup` and writes exactly one immutable `invoice` per
  active installation, priced through the `credit_price` version active for that
  period (A15; §4.5 Billing; Delivery Plan §3.13). The version active for a period is
  the latest `credit_price` row whose `active_from` is at or before the period start;
  if no such row exists, close issues no invoice for that period (A15 item 5; §7.3).
  The close is a new scheduled job; it
  is not a change to F3's `src/rollup/` production job (Delivery Plan §3.13).
- **Price-list activation.** Activating a new `credit_price` version is an audited
  operator control-plane mutation that writes `version`, price per credit, `currency`,
  `active_from`, and `activated_by`, and journals `control_audit` with the operator
  identity. A new version never reprices a closed period (A15; §4.5; §7.3).
- **Invoice evidence.** An invoice resolves to its `usage_rollup` rows for that
  installation and period; any such row (the invoice line) traces through
  `usage_event` request id to request references. Payment collection remains outside:
  the platform issues the invoice document and does not integrate a payment provider
  (A15; §12.3 Billing; §4.5 Billing).

Later slices may extend these (V4 renders the invoice list and detail; Band L collects
payment outside this platform) and may not rewrite them (Delivery Plan §2.3).

### Consumes

Contracts frozen by the slices in G4's `Needs` (`G1`, `F3`). Changing any is out of
scope by definition:

- **From G1 — Plan catalogue and credit-denominated entitlement** (A15; §7.3; §4.5):
  the `credit_price` table (version, price per credit, currency, `active_from`,
  `activated_by`) created empty of activation behaviour; operator-authenticated
  Entitlement management and `control_audit` journaling; entitlement status
  `pending` / `active` / `suspended`; the monthly credit budget column. G4 activates
  `credit_price` versions and writes `invoice`; it does not rewrite the catalogue, the
  credit-budget column, plan assignment, or G1's config-cache kinds.
- **From F3 — Support lookup, retention, usage rollups, and journal dashboards**
  (§7.3 `usage_rollup` / `usage_event`; Delivery Plan §3.13): the scheduled
  `usage_rollup` production job in `src/rollup/` that aggregates `usage_event` into
  per installation/period/capability rows (dimensions, counts, quota weight, tokens,
  cost) with idempotent re-run. G4 consumes that output as the frozen evidence for
  close; it does not change rollup production, reconciliation, retention, or support
  lookup.

### Open decisions relied on

None. Amendment A15 settled Open Decisions 2 and 15 as contract changes rather than as
§15 recommended defaults: the quota unit is the AI credit and the period is the
calendar month (OD-2), and invoice generation moved inside the platform, reversing the
billing row of §12.3 (A15). This slice transcribes those settlements.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Billing period close and invoice generation (Priority: P1)

An operator activates a versioned credit price list. A scheduled close at the end of a
calendar month freezes that period's `usage_rollup` and, for each installation whose
entitlement is `active`, writes exactly one immutable `invoice` priced through the
`credit_price` version active for that period. A period with no consumed credits issues
no invoice. Running close again does not add or change invoices. Activating a later
price-list version does not change invoices already issued. Each invoice's rollup rows
are the lines, and each line traces to request references. The platform does not call a
payment provider.

**Why this priority**: G4's `Needs` are G1 (the empty `credit_price` table and
operator-audited control plane) and F3 (`src/rollup/` output). G1 and G2 are
sequential; G3 and G4 may proceed in parallel once their `Needs` are met. G4 is a
scheduled job and a control-plane mutation, not on the request path's latency budget
(Delivery Plan §3.13). It does not pull G3's usage-summary gauge.

**Independent Test**: A scheduled close freezes the period's `usage_rollup` and
writes exactly one immutable `invoice` per active installation, priced through the
`credit_price` version active for that period; re-runs are idempotent; zero-consumption
periods issue no invoice; price-list activation is an audited operator mutation that
never reprices a closed period; every invoice line traces to request references; no
payment-provider integration exists (Delivery Plan §3.13 row G4 Done when; DP-3).

**Acceptance Scenarios**:

1. **Given** an `active` installation, a calendar-month period with consumed credits
   on `usage_rollup`, and a `credit_price` version active for that period, **When** the
   scheduled period close runs, **Then** it writes exactly one immutable `invoice` row
   for that installation, carrying credits consumed, that credit price list version,
   total, status, and `issued_at`, priced through that version (Delivery Plan §3.12.10
   row G4 *Close*; A15; §7.3; §4.5 Billing).
2. **Given** two `active` installations with consumption in the same period, **When**
   close runs, **Then** it writes exactly one `invoice` per active installation and none
   that combine installations (Delivery Plan §3.12.10 row G4 *Close*; §7.3 Growth
   "One per installation per month").
3. **Given** a period that close has already invoiced, **When** close runs again,
   **Then** the re-run is idempotent: no second `invoice` row, and the existing row is
   unchanged (Delivery Plan §3.12.10 row G4 *Close*; §7.3; A15 immutable invoice).
4. **Given** an `active` installation whose period has zero consumed credits, **When**
   close runs, **Then** it issues no `invoice` for that installation (Delivery Plan
   §3.12.10 row G4 *Close*; A15; §4.5 Billing "from the usage ledger").
5. **Given** operator credentials and a new credit price list version, **When** the
   operator activates that version, **Then** a `credit_price` row is written with
   version, price per credit, currency, `active_from`, and `activated_by`, and a
   `control_audit` row carries the operator identity (Delivery Plan §3.12.10 row G4
   *Price list*; §4.5; §7.3).
6. **Given** credentials that are not operator identity, **When** price-list
   activation is attempted, **Then** the request is rejected and no `credit_price` or
   `control_audit` row is written (§4.5 "separately authenticated … operator identity, not
   clinic identity").
7. **Given** a period already closed with invoices priced through version *V*,
   **When** an operator activates a new `credit_price` version, **Then** the closed
   period's invoices keep version *V* and their totals; the new version does not
   reprice them (Delivery Plan §3.12.10 row G4 *Price list*; A15; §7.3).
8. **Given** an issued `invoice`, **When** its evidence is resolved, **Then** it
   resolves to that installation and period's `usage_rollup` rows (Delivery Plan
   §3.12.10 row G4 *Evidence*; §7.3).
9. **Given** an invoice's `usage_rollup` row (a line, dimensioned per capability),
   **When** it is traced through `usage_event`, **Then** each contributing ledger row's
   request id resolves to a request reference on `ai_request` (Delivery Plan
   §3.12.10 row G4 *Evidence*; §7.3; A15 billing evidence).
10. **Given** period close and price-list activation, **When** either runs, **Then**
    no payment-provider call is made (Delivery Plan §3.12.10 row G4 *Evidence*; A15;
    §12.3 Billing; §4.5 "payment collection remains external").
11. **Given** close pricing consumed credits, **When** the invoice total is written,
    **Then** it is priced through `credit_price` and not through the bundled token-rate
    pricing artifact that normalizes provider-reported tokens into ledger cost units
    (A15 item 5; Delivery Plan §3.13).
12. **Given** several `credit_price` versions whose `active_from` all fall at or before
    the period start, **When** the scheduled close prices that period, **Then** the
    invoice carries the latest such version — the one with the greatest `active_from`
    at or before the period start (A15 item 5; §7.3).
13. **Given** a version *V* active for the current unclosed period, **When** an
    operator activates a new version with an `active_from` inside that period, **Then**
    the new version does not apply to that period: close still prices it through *V*,
    and the new version applies only to periods whose start is at or after its
    `active_from` (A15 item 5; §7.3).
14. **Given** an `active` installation with consumption in a period and no
    `credit_price` row whose `active_from` is at or before the period start, **When**
    close runs, **Then** it issues no `invoice` for that period — the same outcome
    shape as a zero-consumption period — and invents no default price or currency
    (A15 item 5; §7.3).

### Test plan

Every named test is required (Delivery Plan §3.11; DP-3). Layer designations are those
named in Delivery Plan §3.12.10 row G4 (*Scheduled job + integration*).

| Test name | Layer | Asserts |
| --- | --- | --- |
| `close_one_invoice_per_active_installation` | Scheduled job | Period close writes exactly one immutable `invoice` per `active` installation, priced through the `credit_price` version active for that period (Delivery Plan §3.12.10 G4 *Close*; A15; §7.3; §4.5) |
| `close_one_invoice_each_of_two_active_installations` | Scheduled job | Two `active` installations with consumption each receive exactly one `invoice` for the period (Delivery Plan §3.12.10 G4 *Close*; §7.3) |
| `close_rerun_idempotent` | Scheduled job | A second close of the same period writes no additional `invoice` and does not mutate the existing row (Delivery Plan §3.12.10 G4 *Close*; A15; §7.3) |
| `close_zero_consumption_no_invoice` | Scheduled job | A zero-consumption period issues no `invoice` (Delivery Plan §3.12.10 G4 *Close*; A15; §4.5) |
| `close_freezes_usage_rollup_without_rewriting_rows` | Scheduled job | Close freezes the period's `usage_rollup` as invoice evidence and does not rewrite F3 rollup rows (A15; Delivery Plan §3.13 "not a rollup change") |
| `price_list_activation_audited` | Integration | Activating a new price-list version writes `credit_price` (`version`, price per credit, currency, `active_from`, `activated_by`) and `control_audit` with the operator identity (Delivery Plan §3.12.10 G4 *Price list*; §4.5; §7.3) |
| `price_list_activation_non_operator_rejected` | Integration | Non-operator credentials are rejected; no `credit_price` or `control_audit` write (§4.5) |
| `price_list_activation_never_reprices_closed_period` | Integration | Activating a new version leaves a closed period's `invoice` credit price list version and total unchanged (Delivery Plan §3.12.10 G4 *Price list*; A15) |
| `invoice_resolves_to_usage_rollup` | Integration | An invoice resolves to its `usage_rollup` rows for that installation and period (Delivery Plan §3.12.10 G4 *Evidence*; §7.3) |
| `invoice_line_traces_to_request_references` | Integration | Any invoice line (`usage_rollup` row) traces through `usage_event` request id to request references (Delivery Plan §3.12.10 G4 *Evidence*; §7.3; A15) |
| `no_payment_provider_call` | Integration (spy) | Close and price-list activation make no payment-provider call (Delivery Plan §3.12.10 G4 *Evidence*; A15; §12.3) |
| `invoice_prices_through_credit_price_not_token_rate_artifact` | Integration (spy) | Invoice pricing uses `credit_price`, not the bundled token-rate artifact (`src/pricing/`) (A15 item 5; Delivery Plan §3.13) |
| `close_prices_through_latest_version_active_at_period_start` | Scheduled job | With several versions whose `active_from` is at or before the period start, the invoice carries the latest such version (A15 item 5; §7.3) |
| `mid_period_activation_does_not_apply_to_current_period` | Scheduled job | A version activated with `active_from` inside the current unclosed period does not price that period; close uses the latest version with `active_from` at or before the period start (A15 item 5; §7.3) |
| `close_no_applicable_price_list_no_invoice` | Scheduled job | With no `credit_price` row whose `active_from` is at or before the period start, close issues no `invoice` and invents no default price or currency (A15 item 5; §7.3) |

Coverage (Delivery Plan §3.11): happy path of close, activation, evidence, and
pricing; the only rejection this slice's Canonical sections name — non-operator
credentials on the price-list activation mutation (§4.5); zero-consumption and
idempotent re-run branches; price-version resolution — latest `active_from` at or
before the period start, mid-period activation not applying to the current unclosed
period, and no applicable version issuing no invoice (A15 item 5); closed-period
reprice prohibition; `credit_price` versus
token-rate-artifact boundary (A15 item 5). This slice emits no new diagnostic code.
Inherited §6.4 prohibitions are out of scope and are not implemented.

### Edge Cases

- **Non-operator credentials** on price-list activation are rejected; the control plane
  is separately authenticated by operator identity, not clinic identity (§4.5). This
  slice emits no new diagnostic code for that rejection; it uses B2/G1's existing
  operator-auth rejection (Consumes G1).
- **Zero-consumption period**: an `active` installation with no consumed credits for
  the calendar month receives no `invoice` (Delivery Plan §3.12.10 G4 *Close*; A15
  invoice generation from the usage ledger).
- **Idempotent re-run**: a second close of an already-closed period does not insert a
  second `invoice` and does not change credits consumed, credit price list version,
  total, status, or `issued_at` (A15 immutable; §7.3 one per installation per period).
- **Closed period and a new price list**: activating a later `credit_price` version
  never reprices invoices already issued for a closed period (Delivery Plan §3.12.10
  G4 *Price list*; A15).
- **Several versions in or before the period**: the version active for the period is
  the latest `credit_price` row whose `active_from` is at or before the period start
  (A15 item 5; §7.3).
- **Mid-period activation**: a version activated with an `active_from` inside the
  current unclosed period does not apply to that period; close prices it through the
  latest version with `active_from` at or before the period start. An operator who
  wants a new price to apply to a period sets `active_from` at or before that
  period's start (A15 item 5).
- **No applicable price list**: if no `credit_price` row has `active_from` at or
  before the period start, close cannot price the period and issues no `invoice` —
  the same outcome shape as a zero-consumption period. No default price or currency
  is invented, and this slice emits no new diagnostic code for it (A15 item 5).
- **Pending or suspended entitlement**: close writes invoices for `active`
  installations (Delivery Plan §3.13 G4 Done when; §7.3 Entitlement status). Pending
  rows have zeroed economics (Consumes G1) and therefore zero consumption.
- **Period close is scheduled**, not an Entitlement management mutation. It is not
  operator-authenticated HTTP; it is a scheduled job in the existing Worker (A15).
- **No payment-provider call** on close or on activation (A15; §12.3; §4.5). There is
  no payment-provider error path because no call exists.
- **`credit_price` versus token-rate artifact**: invoice totals answer "what does the
  clinic pay per credit"; `src/pricing/` remains the bundled token-rate artifact that
  answers "what did this request cost us" and is unchanged (A15 item 5).
- **Invoice `status`** is persisted as named in §7.3; this slice does not invent an
  enumerated set for it (same discipline G1 used for `plan` status).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The control plane MUST remain a small internal surface separate from the
  client-facing API and separately authenticated by operator identity, not clinic
  identity, for price-list activation. `(§4.5)`
- **FR-002**: Control-plane Billing in this slice MUST perform period close and invoice
  generation from the usage ledger and the versioned credit price list; payment
  collection MUST remain external. `(§4.5 Billing; A15; §12.3 Billing)`
- **FR-003**: Every control-plane mutation in this slice — including activating a
  `credit_price` version — MUST be journaled as a `control_audit` row carrying the
  operator identity (`operator`, `action`, `target`, before/after pointer, `at`).
  `(§4.5; §7.3 control_audit)`
- **FR-004**: Price-list activation attempted without operator credentials MUST be
  rejected, with no `credit_price` or `control_audit` write. `(§4.5)`
- **FR-005**: The quota unit MUST remain the AI credit and the invoiced period MUST be
  the calendar month. `(A15)`
- **FR-006**: A scheduled period close MUST freeze that calendar month's
  `usage_rollup`. The close MUST be a new scheduled job in the existing Worker and MUST
  NOT change F3's `src/rollup/` production job or rewrite rollup rows. `(A15; §4.5
  Billing; Delivery Plan §3.13)`
- **FR-007**: Period close MUST write exactly one immutable `invoice` per installation
  whose entitlement status is `active`, for that period. `(A15; §7.3; §7.3
  Entitlement status; Delivery Plan §3.13 G4 Done when)`
- **FR-008**: That `invoice` MUST be priced through the `credit_price` version active
  for that period. `(A15; §7.3; Delivery Plan §3.13 G4 Done when)`
- **FR-009**: An `invoice` row MUST carry installation, period, credits consumed,
  credit price list version, total, status, and `issued_at`. `(§7.3; A15)`
- **FR-010**: Credits consumed on the `invoice` MUST be the consumed credits evidenced by
  that installation and period's `usage_rollup` quota weight. Actual tokens and cost on
  the ledger remain billing evidence and MUST NOT determine the invoice debit.
  `(A15; §7.3)`
- **FR-011**: A re-run of period close for a period that already has its `invoice`
  row(s) MUST be idempotent: it MUST NOT write a second row per active installation and
  MUST NOT mutate an existing `invoice`. `(A15; §7.3 Growth "One per installation per
  month"; Delivery Plan §3.13 G4 Done when)`
- **FR-012**: A period with zero consumed credits MUST issue no `invoice` for that
  installation. `(A15; §4.5 Billing "from the usage ledger"; Delivery Plan §3.13 G4
  Done when)`
- **FR-013**: Activating a new price-list version MUST write a `credit_price` row with
  version, price per credit, currency, `active_from`, and `activated_by`. `(§7.3; A15;
  Delivery Plan §3.13 G4 Done when)`
- **FR-014**: Activating a new price-list version MUST NOT reprice a closed period's
  invoices (credit price list version and total stay as issued). `(A15; Delivery Plan
  §3.13 G4 Done when)`
- **FR-015**: An invoice MUST resolve to its `usage_rollup` rows for that installation
  and period. `(§7.3; Delivery Plan §3.12.10 G4 Evidence)`
- **FR-016**: Any invoice line — a `usage_rollup` row for that installation and period
  — MUST be traceable through `usage_event` (installation, period, request id, quota
  weight) to request references on `ai_request`. `(§7.3; A15; Delivery Plan §3.12.10
  G4 Evidence)`
- **FR-017**: `credit_price` MUST answer "what does the clinic pay per credit" and MUST
  NOT be the bundled token-rate pricing artifact that answers "what did this request
  cost us". Invoice generation MUST price through `credit_price` and MUST NOT use that
  token-rate artifact. `(A15)`
- **FR-018**: The request path MUST never see a price. The price list MUST live in the
  control plane, where invoices are issued. `(A15)`
- **FR-019**: The platform MUST issue the invoice document and MUST NOT integrate a
  payment provider. No payment-provider call exists. `(A15; §12.3 Billing; §4.5
  Billing)`
- **FR-020**: Forward-only additive D1 migration MUST create the `invoice` entity.
  `(§7.3; A15)`
- **FR-021**: No new deployable MUST be introduced: period close is a scheduled job in
  the existing Worker; the price list and invoices are D1 tables. Invoices are the
  platform's own commercial records, not clinic business data, and MUST NOT write into
  Supabase. `(A15)`
- **FR-022**: This slice MUST NOT implement usage-summary gauge behaviour, credit
  debit, overage, self-service enrollment, or payment collection. `(A15; Delivery Plan
  §3.13)`
- **FR-023**: The `credit_price` version active for a calendar-month period MUST be
  the latest `credit_price` row whose `active_from` is at or before the period start.
  A version whose `active_from` falls inside or after the period MUST NOT apply to
  that period. `(A15 item 5; §7.3)`
- **FR-024**: If no `credit_price` row has `active_from` at or before the period
  start, period close MUST NOT price that period and MUST issue no `invoice` for it —
  the same outcome shape as a zero-consumption period. No default price or currency
  MUST be invented. `(A15 item 5; §7.3)`
- **FR-025**: Activating a new price-list version with an `active_from` inside the
  current unclosed period MUST NOT change which version prices that period at close;
  the invoice carries the latest version with `active_from` at or before the period
  start. `(A15 item 5; §7.3)`

### Key Entities

- **`invoice`**: One issued invoice per installation per period. Key fields:
  installation, period, credits consumed, credit price list version, total, status,
  `issued_at`. Growth: one per installation per month. Retention: long — billing evidence.
  `(§7.3; A15)`
- **`credit_price`** (activated): The versioned credit price list created by G1. Key
  fields: version, price per credit, currency, `active_from`, `activated_by`. Growth:
  a handful of rows ever. Retention: full history. This slice is the first writer that
  activates a version. The version active for a period is the latest row with
  `active_from` at or before the period start (A15 item 5). `(§7.3; A15)`
- **`usage_rollup`** (consumed, not rewritten): Pre-aggregated per
  installation/period/capability. Key fields: dimensions, counts, quota weight, tokens,
  cost. Close freezes a period's rows as invoice evidence. `(§7.3; Consumes F3)`
- **`usage_event`** (consumed): Append-only quota/billing ledger. Key fields:
  installation, period, request id, quota weight, tokens, cost, recorded_at. Invoice
  lines trace through request id to request references. `(§7.3; A15)`
- **`control_audit`**: Control-plane mutations. Key fields: operator, action, target,
  before/after pointer, at. This slice writes the price-list activation action.
  `(§7.3; §4.5)`

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Platform-issued monthly invoices from declared credit prices serve
  small-to-mid multi-branch clinics. There is no payment-provider integration, no
  self-service enrollment, and no hospital-scale billing engine (A15; constitution
  principle I). Credits, not money, are the request-path unit; the price list lives in
  the control plane (A15).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker): D1
  `invoice` migration, the scheduled period-close job, and the operator price-list
  activation mutation. It does not touch `backend/` (Supabase) or `frontend/`
  (Flutter). The gateway is the non-primary, additive component A15's constitution check
  restates: no domain logic, no business data, no write path into Supabase. Period
  close is a scheduled job in the existing Worker; invoices are the platform's own
  commercial records (A15).
- **Data Integrity & Security**: Price-list activation is operator-authenticated and
  audited (`control_audit` with operator identity; `credit_price.activated_by`)
  (§4.5; §7.3). Invoices are immutable once issued; a later price-list version does not
  reprice a closed period (A15). Close consumes F3 `usage_rollup` and does not rewrite
  it. No clinic table is written.
- **Failure Handling**: Close and activation are off the request hot path (Delivery
  Plan §3.13). Control-plane or scheduler unavailability does not hard-lock clinic
  workflows; AI remains additive and the worst allowed operational mode is read-only
  with existing data preserved (A15 "Nothing hard-locks (constitution principle V)").
  This slice does not add retry, a second cache, per-request state, or a payment
  provider.

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **G1 — Plan catalogue and credit-denominated entitlement**: catalogue CRUD, plan
  assignment, `credit_price` table creation. G4 activates versions; it does not rewrite
  the table shape or the catalogue.
- **G2 — Declared-weight credit debit in admission**: stage-15 debit, `quota_exhausted`,
  soft-threshold `degraded`. G4 prices already-consumed credits; it does not debit.
- **G3 — Usage summary endpoint and in-app gauge**: installation-authenticated
  consumed-versus-budget read and Flutter gauge. G3 and G4 may proceed in parallel;
  G4 does not pull gauge work (Delivery Plan §3.13).
- **F3 — `src/rollup/` production, reconciliation, retention, support lookup**:
  consumed as input; close is a new scheduled job, not a rollup change (Delivery Plan
  §3.13).
- **V4 — Viewer commercial surface**: invoice list and detail rendering over G4's
  output; not this slice.
- **Band L / payment collection / self-service enrollment**: A15 and §12.3 leave
  payment collection outside the platform; §12.5 keeps self-service enrollment blocked
  on that. This slice issues the invoice document only.
- **Bundled token-rate artifact (`src/pricing/`)** : unchanged; it is not the A15
  `credit_price` list (A15 item 5; Delivery Plan §3.13).
- **Flutter client**: no invoice UI in this slice.
- **Request path / Quota DO / two-round-trip budget**: G4 is not on the request path
  (Delivery Plan §3.13).

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

- **SC-001**: Scheduled period close writes exactly one immutable `invoice` per `active`
  installation, priced through the `credit_price` version active for that period — the
  latest version whose `active_from` is at or before the period start
  (asserted by `close_one_invoice_per_active_installation`,
  `close_one_invoice_each_of_two_active_installations`,
  `close_prices_through_latest_version_active_at_period_start`, and
  `mid_period_activation_does_not_apply_to_current_period`).
- **SC-002**: A re-run of close is idempotent; a zero-consumption period issues no
  invoice; a period with no applicable price-list version issues no invoice (asserted
  by `close_rerun_idempotent`, `close_zero_consumption_no_invoice`, and
  `close_no_applicable_price_list_no_invoice`).
- **SC-003**: Activating a new price-list version writes `control_audit` with the
  operator identity; non-operator credentials are rejected; a closed period is not
  repriced (asserted by `price_list_activation_audited`,
  `price_list_activation_non_operator_rejected`,
  `price_list_activation_never_reprices_closed_period`).
- **SC-004**: An invoice resolves to its `usage_rollup` rows and any line traces to
  request references (asserted by `invoice_resolves_to_usage_rollup` and
  `invoice_line_traces_to_request_references`).
- **SC-005**: No payment-provider call exists; invoice pricing uses `credit_price` and
  not the bundled token-rate artifact (asserted by `no_payment_provider_call` and
  `invoice_prices_through_credit_price_not_token_rate_artifact`).
- **SC-006**: Close freezes the period's `usage_rollup` without rewriting F3 rollup rows
  (asserted by `close_freezes_usage_rollup_without_rewriting_rows`).

## Assumptions

- G1's `credit_price` table, operator-auth surface, `control_audit` writes, and
  entitlement status `pending` / `active` / `suspended` are present. G4 is the first
  writer that activates a price-list version (A15 item 5; Delivery Plan §3.13 G4).
- F3's scheduled `src/rollup/` job is present and produces `usage_rollup` from
  `usage_event`. G4 attaches a new scheduled close job and does not change rollup
  production, reconciliation, or retention (Delivery Plan §3.13).
- `usage_rollup` carries quota weight as named in §7.3; credits consumed on the invoice
  are that aggregate. G3's usage-summary gauge is out of scope even if that column is
  already present from parallel Band G work.
- Invoice `status` is persisted as named in §7.3; this slice does not invent an
  enumerated set for it.
- The close job's calendar-month period is A15's settled period; this slice does not
  invent a cron expression, a freeze column on `usage_rollup`, or an `invoice_line`
  table.
- Payment collection, Paymob, and the AI Billing Orchestrator are outside this
  platform (A15; §12.3; §12.5). This slice spies that no payment-provider call exists.
