# Feature Specification: Tenant scoping of shared state and the cross-tenant suite

**Feature Branch**: `ai/062-abo-p1-2-tenant-scoping-cross-tenant-suite`

**Created**: 2026-10-02

**Status**: Draft

**Input**: P1.2 — Tenant scoping of shared state and the cross-tenant suite

## 1. Unit Contract

**Implements** — Read: 01 §2 rows T-1–T-3; 01 §7 row R-1 ("`organization_id` on all AI and billing state"); 02 §4.2 rows AD-2, AD-3; 04 §3.1 (intro paragraph only); 05 §8 row A36.

- An inventory (in `research.md`) of every tenant table, policy and definer RPC, with its org key; fix each to key on `current_org_id()`.
- `organization_id` + RLS on AI state lacking it (`ai_internal.ai_token_issuance`, AI acceptance records), and on any tenant table found without one.
- Per-tenant `roles_permissions` (organization_id column, policies, seed per org), so one tenant's admin cannot change another's AI scopes [T-2].
- Staff and branch assignment rows tied to org through membership.
- A two-org, two-admin cross-tenant suite in `backend/tests/`.

**Freezes** — the tenant inventory; per-tenant `roles_permissions`; cross-tenant suite (re-run by P7.2).

**Consumes** — `current_org_id()` and `current_membership_role()` semantics (consumed by P1.2, P5.1, P5.2); migrations; backend CI job.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Tenant inventory keyed on the session organisation (Priority: P1)

A clinic member of organisation A calls every tenant RPC in the inventory with organisation B's ids and reads every inventoried table. The RPCs answer not found or empty, B's rows stay unchanged, and the reads return zero B rows. The existing AI RPCs `record_ai_acceptance` and `issue_ai_token`, as today, write `organization_id = current_org_id()`.

**Why this priority**: This unit depends on P1.1's `current_org_id()` and `current_membership_role()`. User Stories 2, 3, and 4 depend on every tenant table, policy, and definer RPC keying on `current_org_id()`.

**Independent Test**: E2E-P1.2-02, E2E-P1.2-03, and E2E-P1.2-05 in harness H-BK (`backend/tests/` on local Supabase).

**Acceptance Scenarios**:

1. **Given** a user of organisation A and the tenant RPCs in the inventory, **When** that user calls every tenant RPC with organisation B's ids, **Then** the result is not found or empty, foreign ids return `not_found`, and B's rows are unchanged.
2. **Given** a user of organisation A, **When** that user reads every inventoried table through PostgREST, **Then** the reads return zero B rows.
3. **Given** the existing AI RPCs, **When** `record_ai_acceptance` and `issue_ai_token` run as today, **Then** they write `organization_id = current_org_id()`.

### 2.2 User Story 2 - Per-tenant roles and permissions (Priority: P2)

An administrator of organisation A edits `roles_permissions`. Organisation B's permissions and B's AI scopes stay unchanged. AI token scopes come from `roles_permissions`.

**Why this priority**: It depends on P1.1's `current_org_id()` and on User Story 1, which keys the policies on that helper. User Story 4's cross-tenant suite re-runs this scenario.

**Independent Test**: E2E-P1.2-01 in harness H-BK.

**Acceptance Scenarios**:

1. **Given** an administrator of organisation A and organisation B's permissions and AI scopes, **When** the administrator of A edits `roles_permissions`, **Then** B's permissions and B's AI scopes are unchanged.

### 2.3 User Story 3 - Staff and branches follow the active organisation (Priority: P3)

A clinic member with membership in two organisations switches the active organisation and sees only the active organisation's data, including staff and branches. Staff and branch assignment rows are tied to the organisation through membership.

**Why this priority**: It depends on P1.1's active-organisation semantics (`current_org_id()`) and on User Story 1, so the visible rows are the active organisation's. User Story 4's cross-tenant suite re-runs this scenario.

**Independent Test**: E2E-P1.2-04 in harness H-BK.

**Acceptance Scenarios**:

1. **Given** a user with membership in two organisations, **When** that user switches the active organisation, **Then** the user sees only the active organisation's data, including staff and branches.

### 2.4 User Story 4 - Cross-tenant suite (Priority: P4)

A two-org, two-admin cross-tenant suite in `backend/tests/` runs with the backend suites. All backend suites stay green.

**Why this priority**: It depends on P1.1's helpers and on User Stories 1–3, whose scenarios the suite carries. The regression line sits on this story.

**Independent Test**: E2E-P1.2-06 in harness H-BK.

**Acceptance Scenarios**:

1. **Given** the backend suites, including the two-org, two-admin cross-tenant suite, **When** they run, **Then** all backend suites are green.

### 2.5 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P1.2-01 | H-BK | PostgREST RPCs `public.update_role_permission(public.staff_role, text, boolean)` and `public.update_role_permissions(jsonb)` | An administrator of A edits `roles_permissions`; B's permissions and B's AI scopes are unchanged. [T-2] | FR-003 | User Story 2 |
| E2E-P1.2-02 | H-BK | PostgREST RPC: every tenant RPC in the inventory, called with B's ids | A user of A calls every tenant RPC in the inventory with B's ids; the result is not found or empty, foreign ids return `not_found`, and B's rows are unchanged. A function with no row id (for example `public.issue_ai_token`) may succeed; B's rows must be unchanged. [A36, SR-08] | FR-001, FR-005 | User Story 1 |
| E2E-P1.2-03 | H-BK | PostgREST read of every inventoried table | Direct PostgREST reads by A of every inventoried table return zero B rows. For `roles_permissions`, own-organisation rows visible under the FR-003 policy are not leaks; the count is of organisation B's rows. | FR-001, FR-006 | User Story 1 |
| E2E-P1.2-04 | H-BK | PostgREST RPC `public.set_active_organization(p_organization_id)`, then PostgREST reads of `staff_members` and `staff_branch_assignments` | A dual-membership user switches the active organisation and sees only the active organisation's data, including staff and branches. After the claims refresh, `public.jwt_branch_ids()` excludes the other organisation's branches. | FR-004, FR-007 | User Story 3 |
| E2E-P1.2-05 | H-BK | PostgREST RPCs `public.record_ai_acceptance(text, text, jsonb)` and `public.issue_ai_token(text[])` | `record_ai_acceptance` and `issue_ai_token`, as today, write `organization_id = current_org_id()`. | FR-002, FR-008 | User Story 1 |
| E2E-P1.2-06 | H-BK | `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` | All backend suites are green. | FR-009 | User Story 4 |

### 2.6 Edge Cases

- A user of A who calls every tenant RPC in the inventory with B's ids receives not found or empty. Foreign ids return `not_found`. B's rows are unchanged (E2E-P1.2-02, A36, AD-3, SR-08). The organisation comes from the session only, and every store keys by it (02 §4.2 AD-3; 05 §8 A36).
- Direct PostgREST reads by A of every inventoried table return zero B rows (E2E-P1.2-03).
- An administrator of A who edits `roles_permissions` leaves B's permissions and B's AI scopes unchanged. AI token scopes come from `roles_permissions` (E2E-P1.2-01, 01 §2 T-2).
- A dual-membership user who switches the active organisation sees only the active organisation's data, including staff and branches. Staff rows have no organisation of their own; staff and branch assignment rows are tied to the organisation through membership (E2E-P1.2-04, 01 §2 T-1).

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: An inventory in `research.md` records every tenant table, policy, and definer RPC, with its org key, and each is fixed to key on `current_org_id()`. The organisation comes from the session only, and every store keys by it. (02 §4.2 AD-3; 04 §3.1; 06 §4 P1.2)
- **FR-002**: `organization_id` is on all AI and billing state. AI state that lacks it — `ai_internal.ai_token_issuance` and AI acceptance records — and any tenant table found without one, have `organization_id` and RLS. (01 §7 R-1; 06 §4 P1.2)
- **FR-003**: `roles_permissions` is per-tenant: an `organization_id` column, policies, and a seed per organisation, so one tenant's administrator cannot change another's permissions or AI scopes. AI token scopes come from `roles_permissions`. (01 §2 T-2; 06 §4 P1.2)
- **FR-004**: Staff and branch assignment rows are tied to the organisation through membership. Staff rows have no organisation of their own. (01 §2 T-1; 06 §4 P1.2)
- **FR-005**: The ABO and RPCs take the tenant only from the session and answer `not_found` across tenants. A user of A who calls every tenant RPC in the inventory with B's ids receives not found or empty, and B's rows are unchanged. A function with no row id (for example `public.issue_ai_token`) is still invoked; it may succeed, and B's rows must be unchanged. (05 §8 A36; 02 §4.2 AD-3; 06 §4 P1.2)
- **FR-006**: Direct PostgREST reads by A of every inventoried table return zero B rows. For per-tenant `roles_permissions` (FR-003), rows of the session's own organisation that the SELECT policy grants — granted rows, or every row for an administrator — are the member's own data, not a cross-tenant leak; the assertion is zero rows of the other organisation. (02 §4.2 AD-3; 06 §4 P1.2)
- **FR-007**: A dual-membership user who switches the active organisation sees only the active organisation's data, including staff and branches. After the switch and the claims refresh, the `branch_ids` claim that `public.jwt_branch_ids()` reads contains only the active organisation's branches. (01 §2 T-1; 06 §4 P1.2)
- **FR-008**: Existing AI RPCs `record_ai_acceptance` and `issue_ai_token`, as today, write `organization_id = current_org_id()`. (01 §7 R-1; 06 §4 P1.2)
- **FR-009**: A two-org, two-admin cross-tenant suite in `backend/tests/` covers this unit's scenarios, and all backend suites stay green. (06 §4 P1.2)

### 3.2 Key Entities

- **Tenant inventory**: The `research.md` record of every tenant table, policy, and definer RPC, with its org key.
- **`roles_permissions`**: Per-tenant permission matrix with an `organization_id` column, policies, and a seed per organisation. AI token scopes come from it.
- **`ai_internal.ai_token_issuance`**: AI token issuance state. It carries `organization_id` and RLS.
- **AI acceptance records**: AI acceptance state that lacks `organization_id`. They carry `organization_id` and RLS.
- **`staff_members` and `staff_branch_assignments`**: Staff and branch assignment rows tied to the organisation through membership.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: Backend tenancy for a small-to-mid-size multi-branch clinic. Staff rows are tied to the organisation through membership (01 §2 T-1), and every store keys by the session organisation (02 §4.2 AD-3). The row names no wiring exception. The codebase cell is backend.
- **Layer Placement**: PostgreSQL holds the tenant inventory's org keys, `organization_id` and RLS on AI state and on any tenant table found without one, per-tenant `roles_permissions`, and the membership tie for `staff_members` and `staff_branch_assignments`. Supabase PostgREST is the live entry for the RPCs and table reads. `current_org_id()` and `current_membership_role()` are consumed unchanged. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: Definer RPCs and policies key on `current_org_id()` (04 §3.1; 02 §4.2 AD-3). `roles_permissions` is seeded per organisation (01 §2 T-2). AI state that lacks `organization_id` gains that column and RLS (01 §7 R-1).
- **Failure Handling**: A cross-tenant RPC call returns not found or empty, and foreign ids return `not_found`, with the other organisation's rows unchanged (05 §8 A36; 02 §4.2 AD-3). A cross-tenant PostgREST read returns zero rows of the other organisation. An edit to `roles_permissions` leaves the other organisation's permissions and AI scopes unchanged (01 §2 T-2).

## 5. Out of Scope

installation keys and the single-installation trigger (→ P5.1); availability flag (→ P5.2).

- No material from the Do not read sections: 04 §3.2–§3.3 (status RPCs, P5.2).
- No rewrite of a Consumes contract: `current_org_id()` and `current_membership_role()` semantics (consumed by P1.2, P5.1, P5.2); migrations; backend CI job.
- No module that no test-plan row reaches.
- No removal of a transitional path a later unit owns (rule S9): enrollment, removed in P3.2; `/control/entitle`, which keeps test clinics admitted until P3.4; entitlement, plan, and invoice tables and all `/control/*` routes, removed in P3.10.
- No second codebase. The codebase cell is backend.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P1.2-01, E2E-P1.2-02, E2E-P1.2-03, E2E-P1.2-04, E2E-P1.2-05, and E2E-P1.2-06 pass in harness H-BK.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- Rule S9: enrollment remains until P3.2; `/control/entitle` remains until P3.4; entitlement, plan, and invoice tables and `/control/*` routes remain until P3.10.
