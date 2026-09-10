# Feature Specification: Plan catalogue and credit-denominated entitlement (G1)

**Feature Branch**: `ai/056-g1-plan-catalogue`

**Created**: 2026-09-11

**Status**: Draft

**Input**: Slice `G1` — *Plan catalogue and credit-denominated entitlement* (Delivery Plan §3.13, row G1).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice lives entirely inside the Cloudflare AI Gateway Worker
> (`ai-platform/`). Per A15's constitution check, the §14 boundary — no domain logic, no
> business data, no write path into Supabase — stands: the catalogue, the versioned
> credit price list table, and the entitlement monthly credit-budget column are platform
> D1 records, not clinic business data.

## Slice Contract

### Implements

`§4.5, §7.3, §4.3.2, A15` (copied verbatim from the slice's `Canonical` cell in §3.13 of
`docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`).

### Freezes

This slice establishes, for the first time:

- **The plan catalogue.** A `plan` entity mapping a plan name to its monthly credit
  budget, request-count guard, `max_cost_class`, soft threshold, capability set, and
  status (A15; §7.3). Operator plan CRUD maintains that catalogue; every catalogue
  mutation is a control-plane mutation journaled with the operator identity (§4.5
  Entitlement management "maintain the plan catalogue (A15)").
- **The `credit_price` table.** The versioned credit price list entity with version,
  price per credit, currency, `active_from`, and `activated_by` (A15; §7.3). This slice
  creates the table by forward-only migration; activating a price-list version is G4.
- **The entitlement monthly credit-budget column.** The `entitlement` entity gains a
  monthly credit budget column; the frozen admission snapshot name for that field is
  `credit_budget` (A15; §7.3). Token and cost budgets already on the row keep their
  meanings (A15).
- **Plan-based entitlement assignment.** Entitlement assignment reads the catalogue;
  assigning a plan populates the plan's economics onto the installation's `entitlement`
  in one audited mutation and moves the row from `pending` to `active` (A15; §4.5; §7.3
  Entitlement status).
- **Plans as a config-cache kind.** Plans, and entitlements including the credit-budget
  column, are served through the A5 config cache with the warm/cold read pattern already
  frozen for other config kinds (§4.3.2; Delivery Plan §3.13 G1 Done when).

Later slices may extend these (G2 debits `credit_budget`; G4 activates `credit_price`
rows and writes `invoice`) and may not rewrite them (Delivery Plan §2.3).

### Consumes

Contracts frozen by the slices in G1's `Needs` (`A5`, `B2`). Changing any is out of
scope by definition:

- **From A5 — Context key vocabulary, D1 schema, and config cache** (§7.3; §4.3.2):
  forward-only additive D1 migrations, the schema snapshot, and the in-isolate config
  cache (short TTL, populated from D1 on a miss, zero I/O when warm, exactly one D1 read
  when cold) holding installations, keys, entitlements, grants, kill switches, and the
  active routing policy. G1 adds `plan` and `credit_price` tables and the entitlement
  monthly credit-budget column, and serves `plan` through that same cache; it does not
  rewrite existing entity shapes, the one-read/zero-I/O pattern, or cache ownership (the
  cache owns nothing; D1 remains the authority).
- **From B2 — Control-plane enrollment and installation lifecycle** (§4.5): separately
  authenticated operator identity (not clinic identity), the five installation-lifecycle
  actions, the enroll write set (`installation` / `installation_key` / `entitlement` /
  `control_audit`), and the rule that every control-plane mutation journals
  `control_audit` with the operator identity. Enroll still writes the plan name only and
  leaves the entitlement `pending` with zeroed economics (A15; §4.5 "The line between
  the first two rows"). G1 extends the same operator-authenticated surface with plan
  CRUD and plan-based entitlement assignment; it does not rewrite enroll, suspend,
  resume, rotate, delete, or operator-auth.

### Open decisions relied on

None. Amendment A15 settled Open Decisions 2 and 15 as contract changes rather than as
§15 recommended defaults: the quota unit is the AI credit and the period is the calendar
month (OD-2), and a plan catalogue exists (OD-15 settled against its default) (A15).
This slice transcribes those settlements.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Plan catalogue and credit-denominated entitlement (Priority: P1)

An operator maintains a small plan catalogue and assigns a named plan to an enrolled
installation. Assignment reads the catalogue and writes every catalogue economics field
onto that installation's `entitlement` in one audited mutation, moving the row from
`pending` to `active`. An explicit per-installation override of a plan value is a
separate Entitlement management mutation and is recorded as such. Plans and entitlements
are read through the config cache with the A5 warm/cold pattern. The `credit_price`
table exists so a later billing close can price consumed credits; this slice does not
activate price-list versions or issue invoices.

**Why this priority**: G1's `Needs` are A5 (D1 schema and config cache) and B2
(operator-authenticated control plane and the pending entitlement row). G1 and G2 are
sequential; G1's migrations are greenfield; G2 cannot debit a monthly credit budget that
does not yet exist. Band G may start as soon as those `Needs` are met and runs in
parallel with later bands. G1 extends I4's entitle path with plan-catalogue assignment
without pulling G2 debit, G3 usage gauge, or G4 period close (Delivery Plan §3.13).

**Independent Test**: Forward-only migrations create `plan`, `credit_price`, and the
`entitlement` monthly credit-budget column, pinned by a schema snapshot test; operator
plan CRUD and plan-based entitlement assignment are audited control-plane mutations;
assignment from a plan populates every economics field in one mutation; plans and
entitlements are served through the config cache with the A5 warm/cold read pattern
(Delivery Plan §3.13 row G1 Done when; DP-3).

**Acceptance Scenarios**:

1. **Given** an empty database, **When** the forward-only migrations run, **Then** they
   apply cleanly, the schema snapshot matches, and the schema includes `plan`,
   `credit_price`, and the `entitlement` monthly credit-budget column (Delivery Plan
   §3.12.10 row G1 *Catalogue*; §7.3; A15).
2. **Given** operator credentials, **When** the operator creates a plan, **Then** a
   `plan` row is written and a `control_audit` row carries the operator identity
   (Delivery Plan §3.12.10 row G1 *Catalogue*; §4.5; §7.3 `control_audit`).
3. **Given** operator credentials and an existing plan, **When** the operator updates
   that plan, **Then** the `plan` row changes and a `control_audit` row carries the
   operator identity (Delivery Plan §3.12.10 row G1 *Catalogue*; §4.5; §7.3
   `control_audit`).
4. **Given** operator credentials and an existing plan, **When** the operator deletes
   that plan, **Then** the mutation is journaled as a `control_audit` row carrying the
   operator identity (Delivery Plan §3.12.10 row G1 *Catalogue*; §4.5; §7.3
   `control_audit`).
5. **Given** credentials that are not operator identity, **When** any plan CRUD
   mutation is attempted, **Then** the request is rejected and no `plan` or
   `control_audit` row is written (§4.5 "separately authenticated … operator identity,
   not clinic identity"; Delivery Plan §3.12.10 row G1 *Catalogue* "non-operator
   rejected").
6. **Given** operator credentials, a catalogue `plan`, and an enrolled installation
   whose `entitlement` is `pending`, **When** the operator assigns that plan, **Then**
   the entitlement's monthly credit budget, request-count guard, `max_cost_class`, soft
   threshold, and capability set are populated from the plan in one mutation, status
   becomes `active`, and a `control_audit` row carries the operator identity (A15;
   §4.5 Entitlement management "Assign plan"; §7.3 Entitlement status; Delivery Plan
   §3.12.10 row G1 *Assignment*).
7. **Given** an installation already assigned a plan, **When** the operator explicitly
   overrides one plan value on that installation (Entitlement management "set quota and
   budget" / "set period bounds and soft threshold"), **Then** the mutation is journaled
   as that override, distinct from plan assignment (§4.5; Delivery Plan §3.12.10 row G1
   *Assignment* "an explicit per-installation override of a plan value is recorded as
   such").
8. **Given** credentials that are not operator identity, **When** plan-based entitlement
   assignment or a per-installation override is attempted, **Then** the request is
   rejected (§4.5; Delivery Plan §3.12.10 row G1 *Catalogue* "non-operator rejected",
   applied to assignment as an Entitlement management mutation).
9. **Given** a cold isolate, **When** it serves a `plan` or an `entitlement` through the
   config cache, **Then** it performs exactly one D1 read (Delivery Plan §3.12.10 row G1
   *Cache*; §4.3.2).
10. **Given** a warm isolate whose config cache is populated, **When** it serves a
    `plan` or an `entitlement`, **Then** it performs zero I/O (Delivery Plan §3.12.10
    row G1 *Cache*; §4.3.2).

### Test plan

Every named test is required (Delivery Plan §3.11; DP-3). Layer designations are those
named in Delivery Plan §3.12.10 row G1 (*SQL / migration + integration*).

| Test name | Layer | Asserts |
| --- | --- | --- |
| `migrations_apply_cleanly_empty_database` | SQL / migration | Forward-only migrations apply cleanly to an empty database (Delivery Plan §3.12.10 G1 *Catalogue*; A5 migration discipline consumed) |
| `schema_snapshot_matches` | SQL / migration | Schema snapshot matches after migration and includes `plan`, `credit_price`, and the `entitlement` monthly credit-budget column (Delivery Plan §3.12.10 G1 *Catalogue*; §7.3; A15) |
| `plan_create_audit` | Integration | Create-plan mutation writes a `plan` row and a `control_audit` row carrying the operator identity (Delivery Plan §3.12.10 G1 *Catalogue*; §4.5; §7.3) |
| `plan_update_audit` | Integration | Update-plan mutation writes `control_audit` carrying the operator identity (Delivery Plan §3.12.10 G1 *Catalogue*; §4.5; §7.3) |
| `plan_delete_audit` | Integration | Delete-plan mutation writes `control_audit` carrying the operator identity (Delivery Plan §3.12.10 G1 *Catalogue*; §4.5; §7.3) |
| `plan_crud_non_operator_rejected` | Integration | Non-operator credentials are rejected on every plan CRUD mutation; no catalogue or audit write (Delivery Plan §3.12.10 G1 *Catalogue*; §4.5) |
| `assign_plan_populates_economics_one_audited_mutation` | Integration | Assigning a plan populates monthly credit budget, request-count guard, `max_cost_class`, soft threshold, and capability set in one mutation, moves status to `active`, and journals `control_audit` with the operator identity (Delivery Plan §3.12.10 G1 *Assignment*; A15; §4.5; §7.3) |
| `per_installation_override_recorded_as_such` | Integration | An explicit per-installation override of a plan value is journaled as that override, distinct from plan assignment (Delivery Plan §3.12.10 G1 *Assignment*; §4.5) |
| `assignment_non_operator_rejected` | Integration | Non-operator credentials are rejected on assign-plan and on override; no entitlement or audit write (§4.5; Delivery Plan §3.12.10 G1) |
| `config_cache_plan_cold_one_d1_read` | Integration | Serving a plan from a cold isolate performs exactly one D1 read (Delivery Plan §3.12.10 G1 *Cache*; §4.3.2) |
| `config_cache_plan_warm_zero_io` | Integration | Serving a plan from a warm isolate performs zero I/O (Delivery Plan §3.12.10 G1 *Cache*; §4.3.2) |
| `config_cache_entitlement_cold_one_d1_read` | Integration | Serving an entitlement (including the monthly credit-budget column) from a cold isolate performs exactly one D1 read (Delivery Plan §3.12.10 G1 *Cache*; §4.3.2; A15) |
| `config_cache_entitlement_warm_zero_io` | Integration | Serving an entitlement from a warm isolate performs zero I/O (Delivery Plan §3.12.10 G1 *Cache*; §4.3.2) |

Coverage (Delivery Plan §3.11): happy path of catalogue create/update/delete, plan
assignment, override, and cache reads; the only rejection this slice's Canonical
sections name — non-operator credentials on control-plane mutations (§4.5); assignment
moves `pending` → `active` (§7.3); enroll remains plan-name-only and `pending` (A15;
consumed B2, not rewritten). Inherited §6.4 prohibitions are out of scope and are not
implemented.

### Edge Cases

- **Non-operator credentials** on plan CRUD, plan assignment, or per-installation
  override are rejected; the control plane is separately authenticated by operator
  identity, not clinic identity (§4.5). This slice emits no new diagnostic code for that
  rejection; it uses B2's existing operator-auth rejection (Consumes B2).
- **Pending entitlement** remains `pending` with zeroed budgets — including a zeroed
  monthly credit budget — and an empty capability set until assignment; every column
  stays non-null (§7.3 Entitlement status; A15). Enroll still writes the plan name only
  (A15; Consumes B2).
- **Plan assignment** reads the catalogue and copies the plan's monthly credit budget,
  request-count guard, `max_cost_class`, soft threshold, and capability set in one
  mutation (A15; §7.3). It does not debit credits, issue `quota_exhausted`, or change
  token/cost counter meanings (those are G2).
- **Explicit override** of a plan value is Entitlement management "set quota and budget"
  / "set period bounds and soft threshold", journaled distinctly from "Assign plan"
  (§4.5). This slice does not invent an override column on `entitlement`; the
  `control_audit` `action` and before/after pointer record it (§7.3 `control_audit`).
- **Config-cache miss** remains A5's typed failure, not an empty cache entry (Consumes
  A5). G1 does not change TTL, retry, or cache ownership (§4.3.2).
- **`credit_price` rows** are not activated by this slice. The table exists; price-list
  activation and invoice generation are G4 (A15 item 5; Delivery Plan §3.13 G4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The control plane MUST remain a small internal surface separate from the
  client-facing API and separately authenticated by operator identity, not clinic
  identity, for plan-catalogue maintenance and entitlement assignment. `(§4.5)`
- **FR-002**: Operator Entitlement management in this slice MUST maintain the plan
  catalogue, assign plan, set quota and budget, and set period bounds and soft
  threshold. `(§4.5 Entitlement management)`
- **FR-003**: Installation lifecycle MUST continue to own identity and trust material;
  Entitlement management MUST own everything economic. Enroll MUST still create the
  entitlement row empty and `pending`; every value that decides what a request may cost
  MUST be written by Entitlement management. `(§4.5 "The line between the first two
  rows"; A15)`
- **FR-004**: Enroll MUST still write the plan name only and leave the entitlement row
  `pending`. `(A15)`
- **FR-005**: Every control-plane mutation — including every plan CRUD mutation, plan
  assignment, and per-installation override — MUST be journaled as a `control_audit` row
  carrying the operator identity (`operator`, `action`, `target`, before/after pointer,
  `at`). `(§4.5; §7.3 control_audit)`
- **FR-006**: Any plan CRUD, plan-assignment, or override mutation attempted without
  operator credentials MUST be rejected. `(§4.5)`
- **FR-007**: Forward-only additive D1 migrations MUST create the `plan` entity, the
  `credit_price` entity, and the `entitlement` monthly credit-budget column, MUST apply
  cleanly to an empty database, and MUST be pinned by a schema snapshot test. `(§7.3;
  A15; Delivery Plan §3.13 G1 Done when)`
- **FR-008**: A `plan` row MUST carry plan name, monthly credit budget, request-count
  guard, `max_cost_class`, soft threshold, capability set, and status. `(§7.3; A15)`
- **FR-009**: A `credit_price` row MUST carry version, price per credit, currency,
  `active_from`, and `activated_by`. `(§7.3; A15)`
- **FR-010**: An `entitlement` row MUST carry installation id, plan, period bounds,
  request quota, token/cost budget, monthly credit budget, allowed capability set, soft
  threshold, `max_cost_class`, and status. `(§7.3)`
- **FR-011**: Entitlement status MUST take `pending`, `active`, or `suspended`. A row
  MUST be created `pending` by enroll with no economics set and MUST be moved to
  `active` by entitlement assignment. Every column MUST stay non-null throughout —
  `pending` MUST be expressed as zeroed budgets (including a zeroed monthly credit
  budget) and an empty capability set, not as absent values. `(§7.3 Entitlement status;
  A15)`
- **FR-012**: The quota unit MUST be the AI credit and the entitlement budget this slice
  persists MUST be the monthly credit budget. `(A15; §7.3)`
- **FR-013**: Operator plan create, update, and delete MUST maintain the plan catalogue
  as control-plane mutations. `(§4.5; A15 "A plan catalogue exists, and stays small.")`
- **FR-014**: Entitlement assignment MUST read the catalogue. `(A15)`
- **FR-015**: Assigning a plan MUST populate the installation's monthly credit budget,
  request-count guard, `max_cost_class`, soft threshold, and capability set from that
  plan in one mutation, and MUST journal that mutation. `(A15; §4.5; §7.3; Delivery Plan
  §3.12.10 G1 Assignment)`
- **FR-016**: An explicit per-installation setting of quota, budget, period bounds, or
  soft threshold MUST be an Entitlement management mutation distinct from assign-plan
  and MUST be recorded as such on `control_audit`. `(§4.5 Entitlement management; §7.3
  control_audit; Delivery Plan §3.12.10 G1 Assignment)`
- **FR-017**: Plans and entitlements MUST be served through the config cache: an
  in-isolate memory map with a short TTL, populated from D1 on a miss. A warm isolate
  MUST answer from memory with no I/O; a cold isolate MUST perform exactly one D1 read.
  `(§4.3.2; Delivery Plan §3.13 G1 Done when)`
- **FR-018**: The config cache MUST own nothing; D1 remains the authority for `plan`
  and `entitlement` rows. `(§4.3.2)`
- **FR-019**: The request path MUST never see a price. The `credit_price` list MUST live
  with the control plane. `(A15)`
- **FR-020**: `credit_price` MUST answer "what does the clinic pay per credit" and MUST
  NOT be the bundled token-rate pricing artifact that answers "what did this request
  cost us". `(A15)`
- **FR-021**: This slice MUST NOT implement overage, debit of `quota weight`,
  `quota_exhausted`, period close, invoice generation, or a usage-summary gauge. There
  is no overage in the commercial contract (A15); enforcement of exhaustion and soft-
  threshold routing on the credit ratio belong to G2, invoices to G4, and the gauge to
  G3. `(A15; Delivery Plan §3.13)`

### Key Entities

- **`plan`**: The commercial catalogue — what a named plan includes. Key fields: plan
  name, monthly credit budget, request-count guard, `max_cost_class`, soft threshold,
  capability set, status. Growth: a handful of rows. Retention: full history. `(§7.3;
  A15)`
- **`credit_price`**: The versioned credit price list. Key fields: version, price per
  credit, currency, `active_from`, `activated_by`. Growth: a handful of rows ever.
  Retention: full history. `(§7.3; A15)`
- **`entitlement`** (extended): What this installation may use and how much. This slice
  adds the monthly credit budget column (A15) to the fields A5/B2 already persist:
  installation id, plan, period bounds, request quota, token/cost budget, allowed
  capability set, soft threshold, `max_cost_class`, status. One current + history;
  history kept for billing disputes. Status: `pending` / `active` / `suspended`. `(§7.3;
  A15)`
- **`control_audit`**: Control-plane mutations. Key fields: operator, action, target,
  before/after pointer, at. Consumed from A5/B2; this slice writes additional actions
  for plan CRUD, assign-plan, and override. `(§7.3; §4.5)`

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: A small plan catalogue and per-installation assignment serve
  small-to-mid multi-branch clinics. The catalogue "stays small" (A15); there is no
  hospital-scale marketplace, self-service enrollment, or payment-provider integration
  (A15; constitution principle I).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker): D1
  migrations, Entitlement management control-plane mutations, and the config cache. It
  does not touch `backend/` (Supabase) or `frontend/` (Flutter). The gateway is the
  non-primary, additive component A15's constitution check restates: no domain logic, no
  business data, no write path into Supabase. Catalogue, price-list table, and invoices
  (when G4 lands) are the platform's own commercial records, not clinic business data
  (A15).
- **Data Integrity & Security**: Control mutations are operator-authenticated and
  audited (`control_audit` with operator identity) (§4.5; §7.3). Entitlement columns
  stay non-null in every status so the guard reads one shape (§7.3). The config cache
  owns nothing; D1 is the authority (§4.3.2). No clinic table is written.
- **Failure Handling**: Plan CRUD and assignment are operator-invoked, not on the
  request hot path (Delivery Plan §3.13: nothing here is on the request path's latency
  budget). Control-plane unavailability does not hard-lock clinic workflows; AI remains
  additive and the worst allowed operational mode is read-only with existing data
  preserved (A15 "Nothing hard-locks (constitution principle V)"). This slice does not
  add retry, a second cache, or per-request state.

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **G2 — Declared-weight credit debit in admission**: stage-15 debit of manifest
  `quota_weight`, cancelled-request debit, `quota_exhausted`, soft-threshold `degraded`
  flag, Quota DO `credits` / `creditsUsed` fields. G1 persists `credit_budget`; it does
  not debit it.
- **G3 — Usage summary endpoint and in-app gauge**: installation-authenticated
  consumed-versus-budget read and Flutter gauge.
- **G4 — Billing period close and invoice generation**: scheduled close, `invoice`
  entity, price-list activation (`activated_by` writes). G1 creates the `credit_price`
  table only.
- **I4 entitle-and-grant without a catalogue, and live `context_required` self-heal**:
  G1 extends entitlement assignment to read the catalogue (Delivery Plan §3.13); it does
  not reimplement I4 grant/revoke or self-heal.
- **B2 installation lifecycle**: enroll, suspend, resume, rotate, delete — consumed,
  not rewritten. Enroll remains plan-name-only and `pending` (A15).
- **B3 / B4 / F4**: guard evaluation, Quota DO admission, and soft-threshold routing
  behaviour — later slices read the fields G1 writes.
- **A5 entity set besides the additive `plan` / `credit_price` / credit-budget
  column**: no rewrite of `installation`, journal, or existing cache kinds' meanings.
- **`invoice` table**: named in §7.3 after A15; created and written by G4, not G1.
- **Payment collection, self-service enrollment, analytics dashboards** (A15 items 5–6).
- **Flutter client**: no catalogue UI in this slice (V4 drives G1 mutations later).

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

- **SC-001**: Forward-only migrations apply cleanly to an empty database and the schema
  snapshot matches, including `plan`, `credit_price`, and the `entitlement` monthly
  credit-budget column (asserted by `migrations_apply_cleanly_empty_database` and
  `schema_snapshot_matches`).
- **SC-002**: Each plan create, update, and delete writes a `control_audit` row carrying
  the operator identity; non-operator credentials are rejected (asserted by
  `plan_create_audit`, `plan_update_audit`, `plan_delete_audit`,
  `plan_crud_non_operator_rejected`).
- **SC-003**: Assigning a plan populates monthly credit budget, request-count guard,
  `max_cost_class`, soft threshold, and capability set in one audited mutation
  (asserted by `assign_plan_populates_economics_one_audited_mutation`).
- **SC-004**: An explicit per-installation override of a plan value is recorded as such
  (asserted by `per_installation_override_recorded_as_such`).
- **SC-005**: Plans and entitlements are served through the config cache with the A5
  read pattern — one D1 read cold, zero I/O warm (asserted by the four
  `config_cache_*` tests).

## Assumptions

- A5's forwarded-only migration chain, schema snapshot, and config-cache port are
  present; G1 appends migrations and extends cached kinds without rewriting A5's I/O
  contract.
- B2's operator-auth surface and enroll write set are present; G1 does not change
  enroll's plan-name-only, `pending`, zeroed-economics behaviour (A15). The new
  monthly credit-budget column is non-null and zero when `pending` (§7.3).
- I4 may already expose an entitle control action that writes admission budget fields
  without a catalogue. G1 extends Entitlement management so assignment reads the
  catalogue (Delivery Plan §3.13). I4 is not in `Needs`; changing I4's self-heal is
  out of scope.
- `credit_price` is created empty of activation behaviour; G4 is the first writer that
  activates a version (A15 item 5; Delivery Plan §3.13 G4).
- Plan `status` is persisted as named in §7.3; this slice does not invent an enumerated
  set of plan-status values beyond the field's existence.
- Token and cost budgets on `entitlement` remain for reconciliation and billing
  evidence; they are not replaced by the monthly credit budget (A15).
