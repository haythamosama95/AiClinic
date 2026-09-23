# Feature Specification: Catalogue price/display/`grace_days`, `credit_price` withdrawal, plan-delete fix (M1)

**Feature Branch**: `ai/061-m1-catalogue-grace-days`

**Created**: 2026-09-23

**Status**: Draft

**Input**: Slice `M1` — *Catalogue price/display/`grace_days` columns, `credit_price` withdrawal, plan-delete fix* (Delivery Plan §3.2, row M1).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice lives entirely inside the Cloudflare AI Gateway Worker
> (`ai-platform/`). Per A15's constitution check and the Operating Constraints
> amendment, the platform boundary — no domain logic, no clinic business data, no
> write path into Supabase — stands: the extended `plan` catalogue columns are
> platform D1 configuration, not clinic business data.

## Slice Contract

### Implements

`AP-ARCH A17 items 1–2, A15 item 4; ABO §4.1.6, §4.2, §5.10` (copied verbatim from the
slice's `Canonical` cell in §3.2 of
`docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md`).

### Freezes

This slice establishes:

- **A17 catalogue columns on `plan`.** Forward-only migration adds `price_cents`,
  `currency`, `display_name`, `description`, and
  `grace_days INTEGER NOT NULL DEFAULT 7` to the platform `plan` catalogue (AP-ARCH A17
  item 1; ABO §4.1.6; ABO §4.2 `plan` and `invoice` column additions; Delivery Plan
  §3.2 M1 Done when). `grace_days` initial catalogue default is 7 (A17 item 1; ABO
  §4.1.6; ABO §4.2). These columns are the schema shape later served by `GET /v1/plans`
  (ABO §5.10); this slice does not implement that endpoint.
- **`credit_price` withdrawal.** The `credit_price` table is dropped by the same
  forward-only migration; `src/control/credit-price.ts`, its route registration, and
  `CreditPriceActivatePayload` are deleted; no `credit_price` / `CreditPriceActivatePayload`
  / `credit-price` reference remains in `ai-platform/src/` (AP-ARCH A17 item 2; Delivery
  Plan §3.2 M1 Done when).
- **Plan CRUD carrying A17 fields.** Operator plan create/update round-trips the new
  price, display, and `grace_days` fields with the usual `control_audit` rows (A15 item 4
  as updated by A17; Delivery Plan §3.2 M1 Done when).
- **Plan delete that actually deletes.** `POST /control/plans/{name}/delete` removes the
  `plan` row and writes the `plan_delete` audit row (Delivery Plan §3.2 Code sync and M1
  Done when).

Later slices may extend these (M2 reshapes invoice / `purchase_proof`; P2 serves
`GET /v1/plans`) and may not rewrite the frozen column set or restore `credit_price`
(Delivery Plan §2.3; A17 item 2).

### Consumes

Contracts frozen by the slice in M1's `Needs` (`G1`). Changing any is out of scope by
definition, except where A17 item 2 explicitly withdraws `credit_price`:

- **From G1 — Plan catalogue and control-plane plan CRUD** (A15 item 4; Delivery Plan
  Band G / `specs/056-plan-catalogue`): the `plan` entity, operator-authenticated plan
  CRUD surface, `control_audit` journaling on catalogue mutations, config-cache serving
  of plans, and forward-only additive D1 migration discipline. M1 adds A17 columns to
  `plan` and extends plan CRUD payloads; it does not rewrite G1 economics columns
  (`credit_budget`, request-count guard, `max_cost_class`, soft threshold, capability
  set, status) or enroll/assign semantics.
- **A17-authorized withdrawal of G1's `credit_price`.** G1 created the versioned
  `credit_price` table and control surface; A17 item 2 removes that artifact before Band
  G completes. M1 executes that withdrawal; it does not redefine period-close pricing
  (M2).

### Open decisions relied on

None. Delivery Plan §3.13.3 lists no open question owned by M1. A17 items 1–2 and A15
item 4 (as updated by A17) are settled architecture; this slice transcribes them.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operator maintains A17 catalogue economics without `credit_price` (Priority: P1)

An operator maintains the platform plan catalogue after A17: each plan row carries
subscription price, display copy, and `grace_days`, and there is no separate
`credit_price` list or activate endpoint. Plan create and update round-trip the new
fields under the existing operator-authenticated control surface with `control_audit`
rows. Plan delete removes the catalogue row (fixing the G-era audit-only delete bug).
Unauthenticated callers are rejected. The public `GET /v1/plans` surface is not part of
this story (P2).

**Why this priority**: Delivery Plan DP-L3 and §3.2 sequence Band M first: live
`credit_price` contradicts the subscription model, and every later commercial band reads
the catalogue columns M1 lands. M1 is the sole P1 story for this Spec Kit feature
(ABO specify override: one slice = one user story).

**Independent Test**: A forward-only migration adds `price_cents` / `currency` /
`display_name` / `description` / `grace_days INTEGER NOT NULL DEFAULT 7` to `plan` and
drops `credit_price`, pinned by a schema snapshot test; `src/control/credit-price.ts`,
its route, and `CreditPriceActivatePayload` are deleted and no `credit_price` reference
remains in `src/`; plan CRUD carries the new fields with the usual `control_audit`
rows; `POST /control/plans/{name}/delete` actually deletes the row (Delivery Plan §3.2
M1 Done when).

**Acceptance Scenarios**:

1. **Given** an empty D1 database, **When** the M1 forward-only migration runs, **Then**
   it applies cleanly and the pinned schema snapshot includes
   `grace_days INTEGER NOT NULL DEFAULT 7` on `plan` and does not include `credit_price`
   (Delivery Plan §3.12.1 row M1 *Migration*; A17 items 1–2; ABO §4.2).
2. **Given** the existing pre-A17 catalogue (seeded `plan` rows and existing
   `credit_price` rows), **When** the M1 forward-only migration runs, **Then** it
   applies cleanly over that catalogue, existing `plan` rows are preserved with
   `grace_days` defaulted, `credit_price` is absent from the pinned snapshot, and there
   is no down migration (Delivery Plan §3.12.1 row M1 *Migration*; A17 item 2).
3. **Given** `ai-platform/src/` after M1, **When** a grep test scans for
   `credit_price`, `CreditPriceActivatePayload`, and `credit-price`, **Then** no
   reference remains and `src/control/credit-price.ts` is deleted with its route
   registration removed (Delivery Plan §3.12.1 row M1 *Code*; A17 item 2).
4. **Given** M1 has landed, **When** a client calls the withdrawn
   `POST /control/credit-price/activate` endpoint, **Then** the response is 404 — the
   route is unregistered (Delivery Plan §3.12.1 row M1 *Code*; A17 item 2).
5. **Given** valid operator credentials, **When** the operator creates or updates a
   plan carrying the new price/display/`grace_days` fields, **Then** the row
   round-trips those fields exactly and a `control_audit` row is written for the
   mutation (Delivery Plan §3.12.1 row M1 *Code*; A15 item 4 as updated by A17; A17
   item 1).
6. **Given** credentials that are not a valid operator credential, **When** plan
   create, update, or delete is attempted, **Then** the request is rejected and no
   catalogue or audit row is written (Delivery Plan §3.12.1 row M1 *Code*
   "non-operator rejected").
7. **Given** valid operator credentials and an existing plan, **When** the operator
   calls `POST /control/plans/{name}/delete`, **Then** the `plan` row is removed and a
   `plan_delete` `control_audit` row is written (Delivery Plan §3.12.1 row M1 *Bug
   fix*; Delivery Plan §3.2 Code sync).
8. **Given** valid operator credentials and an unknown plan name, **When** the
   operator calls `POST /control/plans/{name}/delete`, **Then** the response is 404 and
   no audit row is written (Delivery Plan §3.12.1 row M1 *Bug fix*).

### Test plan

Every named floor case below is required (Delivery Plan §3.11; DP-3). Layer designation
is that named in Delivery Plan §3.12.1 row **M1** (`SQL / migration + integration`).
Ids are the §3.12 slice id plus the prose groups in that row's Required cases cell.

| ID | Layer | Asserts |
| --- | --- | --- |
| M1 — Migration | SQL / migration + integration | Migration applies cleanly to an empty database and over the existing catalogue; schema snapshot pinned including `grace_days DEFAULT 7`; `credit_price` absent from the snapshot (Delivery Plan §3.12.1 M1 *Migration*) |
| M1 — Code | SQL / migration + integration | No `credit_price` reference remains in `src/` (grep test); the deleted credit-price endpoint returns 404; plan CRUD round-trips the new fields with `control_audit` rows; non-operator rejected (Delivery Plan §3.12.1 M1 *Code*) |
| M1 — Bug fix | SQL / migration + integration | Delete removes the `plan` row and writes the audit row; deleting an unknown plan still 404s (Delivery Plan §3.12.1 M1 *Bug fix*) |

### Band verification (out of Spec Kit)

- Expanded matrix: Delivery Plan §3.2.1 (M1-V1…M1-V14 and Band M e2e/x-e2e rows that
  exercise M1). Implemented only via `/abo-verify` after Band M slices land — not as
  extra Spec Kit user stories or tasks.

### Edge Cases

- **Migration over existing catalogue:** existing `plan` rows survive; `grace_days`
  backfills via `DEFAULT 7`; dropping `credit_price` must not error; migration is
  forward-only (Delivery Plan §3.2 M1 Done when; §3.12.1 M1 *Migration*; A17 item 2).
- **Omitted `grace_days` on create:** schema default stores `7` (A17 item 1; ABO §4.2).
- **Explicit `grace_days = 0`:** stored as 0 — explicit value wins over default;
  zero-length grace is representable (boundary of the A17/`DEFAULT 7` column).
- **Invalid price/display/`grace_days` payloads** (negative `grace_days`, negative or
  non-integer `price_cents`, empty `currency`, empty `display_name`): rejected with
  `400` `invalid_payload`; no row written; no audit row (plan CRUD carrying A17 fields;
  Delivery Plan §3.2 M1 Done when).
- **Plan update of only A17 fields:** economics columns from G1 remain unchanged;
  `plan_update` audit row written.
- **Plan update/delete on unknown plan name:** `404` `plan_not_found`; no audit row.
- **Plan delete while `entitlement.plan` / `invoice.plan` still reference the name:**
  delete succeeds (no FK); referencing rows untouched — retirement-by-status is policy;
  delete is a catalogue operation (Delivery Plan §3.2; ABO §4.1.6 catalogue ownership).
- **Withdrawn credit-price activate after M1:** `404`; no `credit_price` table to write
  to (A17 item 2; §3.12.1 M1 *Code*).
- **Unauthenticated plan create/update/delete:** `401` `{"error":"unauthorized"}`; no
  rows written (§3.12.1 M1 *Code*).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A forward-only D1 migration in `ai-platform/migrations/` MUST add
  `price_cents`, `currency`, `display_name`, `description`, and
  `grace_days INTEGER NOT NULL DEFAULT 7` to the `plan` table (AP-ARCH A17 item 1; ABO
  §4.1.6; ABO §4.2; Delivery Plan §3.2 M1 Done when).
- **FR-002**: The same forward-only migration MUST drop the `credit_price` table
  (AP-ARCH A17 item 2; Delivery Plan §3.2 M1 Done when).
- **FR-003**: The schema snapshot test MUST pin the post-migration schema including
  the A17 `plan` columns and the absence of `credit_price` (Delivery Plan §3.2 M1 Done
  when; §3.12.1 M1 *Migration*).
- **FR-004**: The migration MUST apply cleanly both to an empty database and over the
  existing pre-A17 catalogue (seeded `plan` rows and existing `credit_price` rows), with
  no down migration (Delivery Plan §3.12.1 M1 *Migration*; A17 item 2).
- **FR-005**: `src/control/credit-price.ts`, its route registration/export, and
  `CreditPriceActivatePayload` MUST be deleted; no reference to `credit_price`,
  `CreditPriceActivatePayload`, or `credit-price` may remain in `ai-platform/src/`
  (AP-ARCH A17 item 2; Delivery Plan §3.2 M1 Done when; §3.12.1 M1 *Code*).
- **FR-006**: After M1, `POST /control/credit-price/activate` MUST return 404 because
  the route is unregistered (Delivery Plan §3.12.1 M1 *Code*; A17 item 2).
- **FR-007**: The `plan` catalogue MUST remain the only plan and pricing catalogue:
  subscription price (`price_cents`, `currency`), display copy (`display_name`,
  `description`), and `grace_days` live only on platform `plan` rows — not in an ABO
  local plan/price table (AP-ARCH A17 item 1; A15 item 4 as updated by A17; ABO
  §4.1.6).
- **FR-008**: `grace_days` MUST be the single timing source column on the catalogue for
  dunning/grace (initial default 7), shaped so later `GET /v1/plans` (ABO §5.10) and
  receipt `valid_until = period_end + grace_days` readers share one value (AP-ARCH A17
  item 1; ABO §4.1.6; ABO §4.2; ABO §5.10). This slice does not implement those readers.
- **FR-009**: Operator plan create and update MUST accept and persist the A17 fields
  (`price_cents`, `currency`, `display_name`, `description`, `grace_days`) and MUST
  write the usual `control_audit` rows for those mutations (A15 item 4 as updated by
  A17; Delivery Plan §3.2 M1 Done when; §3.12.1 M1 *Code*).
- **FR-010**: Omitting `grace_days` on plan create MUST store `7` via the schema
  default; an explicit `grace_days` value including `0` MUST be stored as given (A17
  item 1; ABO §4.2 `DEFAULT 7`).
- **FR-011**: Plan create/update with negative `grace_days`, negative or non-integer
  `price_cents`, empty `currency`, or empty `display_name` MUST fail with
  `400` `invalid_payload`, write no row, and write no audit row (Delivery Plan §3.2 M1
  Done when — plan CRUD carries the new fields under existing control validation).
- **FR-012**: Plan update that changes only price/display/`grace_days` MUST leave G1
  economics columns unchanged and MUST write a `plan_update` audit row (Consumes G1;
  Delivery Plan §3.2 M1 Done when).
- **FR-013**: `POST /control/plans/{name}/delete` MUST delete the `plan` row and write
  a `plan_delete` `control_audit` row when the plan exists (Delivery Plan §3.2 Code sync
  and M1 Done when; §3.12.1 M1 *Bug fix*).
- **FR-014**: Plan delete or update on an unknown plan name MUST return
  `404` `plan_not_found` with no audit row (Delivery Plan §3.12.1 M1 *Bug fix*).
- **FR-015**: Plan delete MUST succeed even when `entitlement.plan` or `invoice.plan`
  still reference the name (no FK); referencing rows MUST remain untouched (Delivery
  Plan §3.2; catalogue operation vs retirement-by-status).
- **FR-016**: Plan create, update, and delete without a valid operator credential MUST
  return `401` `{"error":"unauthorized"}` and write no rows (Delivery Plan §3.12.1 M1
  *Code*).
- **FR-017**: This slice MUST NOT implement `GET /v1/plans`, period-close repricing,
  `purchase_proof` DDL, or invoice reshape — those are P2 / M2 (ABO §5.10 served by P2;
  A17 item 3 / ABO §4.2 invoice linkage owned by M2; Delivery Plan §3.2).

### Key Entities

- **`plan` (platform D1)**: Commercial catalogue row. G1 economics fields retained; this
  slice adds `price_cents`, `currency`, `display_name`, `description`, and
  `grace_days INTEGER NOT NULL DEFAULT 7` (A17 item 1; ABO §4.1.6; ABO §4.2).
- **`credit_price` (platform D1)**: Withdrawn. Table dropped; control activate path and
  payload type removed (A17 item 2).
- **`control_audit`**: Existing control-plane audit journal; plan create/update/delete
  continue to write action rows (`plan_create` / `plan_update` / `plan_delete`) in the
  same batch as the catalogue mutation (A15 item 4 / G1 pattern; Delivery Plan §3.2 M1
  Done when).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Extends the vendor AI platform's small plan catalogue so clinics later
  see a single subscription price and grace timeline, without adding clinic-side tables
  or enterprise billing infrastructure (Constitution I; Operating Constraints
  vendor-side control services).
- **Layer Placement**: All work is in `ai-platform/` (D1 migration + control-plane plan
  CRUD / credit-price removal). No changes in `ai-billing-orchestrator/`, `backend/`, or
  `frontend/` in this slice.
- **Data Integrity & Security**: Forward-only D1 migration; schema snapshot pin;
  operator-authenticated control mutations with `control_audit`; no clinic Postgres
  writes; no shared bearer introduced (Delivery Plan §5.3 / §8.1).
- **Failure Handling**: Invalid catalogue payloads reject with no write; unknown plan
  names 404; unauthenticated control calls 401. AI request-path availability is
  unaffected — this slice does not touch the gateway request path. Public catalogue
  read (`GET /v1/plans`) remains a later slice (P2); until then, consumers do not yet
  depend on the new columns over HTTP.

### Codebases touched

- `ai-platform/` — yes (migration, control plan CRUD, credit-price withdrawal, schema
  snapshot).
- `ai-billing-orchestrator/` — no.
- `backend/` — no.
- `frontend/` — no.

## Out of Scope

- **Neighbouring slices:** M2 (period-close repricing, `purchase_proof` table, invoice
  reshape, superseding `specs/059-billing-period-close`); M3 (data-journey docs 16/18);
  P2 (`GET /v1/plans` and AP-ARCH §13.4 registration); Band N/O/Q/R/S/T/U work.
- **Band verification rows** in Delivery Plan §3.2.1 (M1-V*, M-E*, M-X*) — handled by
  `/abo-verify`, not as Spec Kit tasks.
- **Delivery Plan §5 prohibitions** (AP §6.4 adopted) plus ABO-specific §5.3 items:
  - No shared bearer or standing unattributed credential (§8.1, §11.2).
  - No plan/price/entitlement-mirror/usage table in the ABO (§4.1.6).
  - No provider identifier across the adapter boundary (§7.1).
  - No order state or provider data in clinic Postgres (§9.5).
  - Plus AP gateway prohibitions when touching `ai-platform/` (R-12, R-20, §7.5, etc.):
    this slice must not put money or provider prices on the request path; catalogue
    price columns are control-plane / D1 configuration only (A17 item 1; A6 preserved).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Schema snapshot after M1 shows `plan` with `price_cents`, `currency`,
  `display_name`, `description`, and `grace_days INTEGER NOT NULL DEFAULT 7`, and shows
  no `credit_price` table (Delivery Plan §3.2 M1 Done when).
- **SC-002**: Automated grep over `ai-platform/src/` finds zero references to
  `credit_price`, `CreditPriceActivatePayload`, or `credit-price`;
  `src/control/credit-price.ts` is absent (Delivery Plan §3.2 M1 Done when).
- **SC-003**: Plan create/update with A17 fields returns success, persists every field,
  and writes the corresponding `control_audit` row in the same batch (Delivery Plan
  §3.2 M1 Done when; §3.12.1 M1 *Code*).
- **SC-004**: `POST /control/plans/{name}/delete` on an existing plan leaves no `plan`
  row and writes `plan_delete` audit; unknown plan still 404s (Delivery Plan §3.2 M1
  Done when; §3.12.1 M1 *Bug fix*).
- **SC-005**: Withdrawn `POST /control/credit-price/activate` returns 404; non-operator
  plan CRUD returns 401 with no writes (Delivery Plan §3.12.1 M1 *Code*).

## Assumptions

- Band G1 (`specs/056-plan-catalogue`) is present: `plan` table, operator plan CRUD
  surface, and `control_audit` journaling exist for M1 to extend (Delivery Plan §3.2
  Needs: G1; Code sync).
- Pre-A17 `credit_price` table, `src/control/credit-price.ts`, route registration, and
  `CreditPriceActivatePayload` exist in the tree to be withdrawn (Delivery Plan §3.2
  Code sync; A17 item 2).
- Operator authentication for `/control/*` plan routes remains the G1-era credential
  model until Band N replaces it; M1 does not introduce CAT or remove the shared bearer
  (Needs G1 only; Band N is parallel and out of scope).
- Implementing `GET /v1/plans` (ABO §5.10) is deferred to P2; M1 only lands the columns
  that endpoint will serve.
- Period-close, `purchase_proof`, and invoice reshape remain M2; M1's withdrawal of
  `credit_price` may leave period-close temporarily unable to price until M2 lands —
  accepted by Delivery Plan §3.2 sequencing (M1 then M2).
