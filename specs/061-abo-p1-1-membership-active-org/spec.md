# Feature Specification: Membership, active organisation and current_org_id()

**Feature Branch**: `ai/061-abo-p1-1-membership-active-org`

**Created**: 2026-10-02

**Status**: Draft

**Input**: P1.1 — Membership, active organisation and `current_org_id()`

## 1. Unit Contract

**Implements** — Read: 01 §2 rows T-1, T-2, T-5; 01 §7 row R-1; 03 §1 (last row, Tenancy and membership); 03 §4 (first row, Tenancy); 02 §2 row TB-4; 02 §4.3 row Tenant isolation; 04 §2.1 (first paragraph).

- `membership (user_id, organization_id, role)`; backfill one membership per existing staff user (current org, current role).
- Active organisation per session: a per-user active-org record, plus an auth access-token hook that puts the `active_org` claim in the JWT; RPC `set_active_organization(p_organization_id)` (membership required).
- `current_org_id()`: active-org claim, valid only while a live membership exists (re-checked on every call; otherwise NULL, and definer RPCs raise). `current_membership_role()`.
- Re-point `public.jwt_organization_id()` to `current_org_id()`, so the existing dependents inherit the re-check.
- Billing authority = membership role `administrator` (T-2, I-1), never `roles_permissions`.
- Backend CI job: local Supabase, all migrations, `run_all_backend_tests.sh` + catalog harness (H-BK in CI).

**Freezes** — `current_org_id()` and `current_membership_role()` semantics (consumed by P1.2, P5.1, P5.2); migrations; backend CI job.

**Consumes** — None.

**Open questions relied on** — OQ-2 default, quoted: "out of scope; the active organisation is changed only through the `set_active_organization` RPC." The same item states that P1.1 sets the active-org claim from the user's sole membership at sign-in.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Staff membership backfill (Priority: P1)

A pre-existing staff user has exactly one membership after the migration. That membership matches the user's current organisation and current role.

**Why this priority**: This unit depends on no earlier unit. The active-organisation story needs that membership before sign-in can carry the organisation and before `set_active_organization` can require one.

**Independent Test**: E2E-P1.1-07 in harness H-BK (psql on local Supabase, `backend/tests/`).

**Acceptance Scenarios**:

1. **Given** the pre-existing staff users, **When** the backfill has run, **Then** every pre-existing staff user has exactly one membership matching that user's organisation and role.

### 2.2 User Story 2 - Active organisation for the session (Priority: P2)

A clinic member with one membership signs in, and the claim carries that organisation. A clinic member of organisations A and B calls `set_active_organization(B)` and refreshes. A call for an organisation the user does not belong to returns an error and leaves the claim unchanged.

**Why this priority**: It depends on the membership from User Story 1. The re-check story reads the active-org claim and `current_org_id()` this story establishes.

**Independent Test**: E2E-P1.1-01, E2E-P1.1-02, and E2E-P1.1-03 in harness H-BK.

**Acceptance Scenarios**:

1. **Given** a user with exactly one membership, **When** that user signs in, **Then** the claim carries that organisation and `current_org_id()` equals that organisation.
2. **Given** a user who is a member of organisations A and B, **When** that user calls `set_active_organization(B)` and refreshes, **Then** `current_org_id()` equals B and tenant RPCs return only B's rows.
3. **Given** a user with no membership in organisation C, **When** that user calls `set_active_organization(C)`, **Then** the call returns an error and the claim is unchanged.

### 2.3 User Story 3 - Membership re-check and role (Priority: P3)

A clinic member whose membership is removed while the JWT is still valid has no organisation: `current_org_id()` is NULL, RLS selects return no rows, and a definer RPC raises. A caller presenting a crafted JWT for an organisation with no membership is treated as having no organisation. `current_membership_role()` returns the membership role, `administrator` or `doctor`, and an edit to `roles_permissions` does not change it. The pre-existing backend suites still pass: they impersonate the legacy `organization_id` claim, which `current_org_id()` accepts when no `active_org` claim is present, and each impersonated fixture user receives the membership its claim names, so the membership re-check passes for them with no change to the suites' claims or assertions.

**Why this priority**: It depends on the active-org claim and `current_org_id()` from User Story 2. The regression line sits on this story.

**Independent Test**: E2E-P1.1-04, E2E-P1.1-05, E2E-P1.1-06, and E2E-P1.1-08 in harness H-BK.

**Acceptance Scenarios**:

1. **Given** a JWT that is still valid, **When** the membership it relied on is deleted, **Then** `current_org_id()` is NULL, RLS selects return 0 rows, and a definer RPC raises.
2. **Given** a crafted JWT that names an organisation the user has no membership in, **When** the backend resolves the organisation, **Then** it is treated as no organisation.
3. **Given** one membership with role `administrator` and one with role `doctor`, **When** `current_membership_role()` is called for each, **Then** it returns `administrator` and `doctor` respectively, and editing `roles_permissions` does not change it.
4. **Given** the pre-existing backend suites, **When** they run, **Then** every pre-existing backend suite passes with its impersonated claims and its assertions unchanged.

### 2.4 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P1.1-01 | H-BK | Custom access-token hook `public.get_custom_claims` (`[auth.hook.custom_access_token]` in `backend/supabase/config.toml`), then `current_org_id()` | A one-membership user signs in, the claim carries that organisation, and `current_org_id()` equals that organisation. | FR-003, FR-005 | User Story 2 |
| E2E-P1.1-02 | H-BK | PostgREST RPC `set_active_organization(p_organization_id)`, then `public.get_custom_claims` on refresh, then a tenant RPC that reads `public.jwt_organization_id()` | A user in organisations A and B calls `set_active_organization(B)` and refreshes; `current_org_id()` equals B, and tenant RPCs return only B's rows. | FR-004, FR-008 | User Story 2 |
| E2E-P1.1-03 | H-BK | PostgREST RPC `set_active_organization(p_organization_id)` | `set_active_organization(C)` without a membership returns an error, and the claim is unchanged. | FR-004 | User Story 2 |
| E2E-P1.1-04 | H-BK | `current_org_id()` under psql JWT impersonation; an RLS select whose policy calls `public.jwt_organization_id()`; a SECURITY DEFINER RPC keyed on `public.jwt_organization_id()` | Membership deleted while the JWT is still valid leaves `current_org_id()` NULL; RLS selects return 0 rows; a definer RPC raises. [SR-03] | FR-005, FR-008 | User Story 3 |
| E2E-P1.1-05 | H-BK | `current_org_id()` under psql impersonation with a crafted `request.jwt.claims` organisation | A crafted JWT with an organisation the user has no membership in is treated as no organisation. [A36 backend] | FR-005, FR-006 | User Story 3 |
| E2E-P1.1-06 | H-BK | `current_membership_role()` under psql JWT impersonation, after an edit to `public.roles_permissions` | `current_membership_role()` returns `administrator` for an administrator membership and `doctor` for a doctor membership; editing `roles_permissions` does not change it. [T-2] | FR-007 | User Story 3 |
| E2E-P1.1-07 | H-BK | psql read of `membership` after migrations on local Supabase | Every pre-existing staff user has exactly one membership matching that user's organisation and role. | FR-001, FR-002 | User Story 1 |
| E2E-P1.1-08 | H-BK | `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` on local Supabase | Every pre-existing backend suite passes with its impersonated claims and its assertions unchanged; fixture users hold the membership their `organization_id` claim names. | FR-009 | User Story 3 |

### 2.5 Edge Cases

- `set_active_organization(C)` with no membership in C returns an error, and the claim is unchanged (E2E-P1.1-03).
- Membership deleted while the JWT is still valid: `current_org_id()` is NULL, RLS selects return 0 rows, and a definer RPC raises (E2E-P1.1-04, SR-03).
- A crafted JWT naming an organisation with no membership is treated as no organisation (E2E-P1.1-05, A36 backend).
- A user who belongs to organisations A and B, after `set_active_organization(B)` and a refresh, receives only B's rows from tenant RPCs (E2E-P1.1-02).
- Editing `roles_permissions` does not change `current_membership_role()` (E2E-P1.1-06, T-2).

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: Tenancy and membership are authoritative in the backend, have no copy, and are written by the backend. Membership is `(user, organization, role)`, recorded as `membership (user_id, organization_id, role)`. (03 §1 last row; 03 §4 Tenancy row; 01 §7 R-1)
- **FR-002**: Backfill creates one membership per existing staff user (current org, current role). The current organisation is the first organisation the claim takes today, because staff rows have no organisation of their own; the current role is the staff member's role. (01 §2 T-1; 01 §2 T-5)
- **FR-003**: Each session has one active organisation: a per-user active-org record, and the access-token hook `public.get_custom_claims` puts the `active_org` claim in the JWT, set from the user's sole membership at sign-in. (01 §7 R-1; 03 §4 Tenancy row; 06 §6 OQ-2)
- **FR-004**: `set_active_organization(p_organization_id)` requires a membership in that organisation. Without a membership the call returns an error and the claim is unchanged. After a successful call and a refresh, `current_org_id()` is the organisation passed in. The active organisation is changed only through this RPC. (06 §6 OQ-2)
- **FR-005**: `current_org_id()` returns the active-org claim only while a live membership in that organisation exists, and it re-checks membership on every call. Otherwise it returns NULL, and definer RPCs raise. A crafted JWT whose organisation has no membership is treated as no organisation. Definer RPCs are keyed on `current_org_id()`. The first tenant-isolation layer is this membership re-check. The active-org claim is `active_org`; a JWT that carries no `active_org` claim — a pre-retrofit token, or the pre-existing H-BK suites' psql impersonation, which sets only `organization_id` — falls back to the legacy `organization_id` claim. Whichever claim names the organisation, the membership re-check is unchanged: the organisation is returned only while a live membership `(sub, org)` exists. (01 §7 R-1; 03 §4 Tenancy row; 02 §2 TB-4; 02 §4.3 Tenant isolation; 06 §4 P1.1)
- **FR-006**: `org` always comes from `current_org_id()`, never from an argument. (04 §2.1)
- **FR-007**: `current_membership_role()` returns the membership role. The staff roles are `administrator`, `doctor`, `receptionist`, and `lab_staff`. Billing authority is the membership role `administrator`, and it does not depend on `roles_permissions`. Editing `roles_permissions` does not change `current_membership_role()`. (01 §2 T-2; 01 §2 T-5)
- **FR-008**: `public.jwt_organization_id()` is re-pointed to `current_org_id()`, so existing dependents inherit the membership re-check. RLS selects and tenant RPCs follow that function. (06 §2 S5; 02 §2 TB-4)
- **FR-009**: A backend CI job runs local Supabase, applies all migrations, and runs `backend/tests/run_all_backend_tests.sh` and the catalog harness `backend/tests/catalog/run.sh`. Every pre-existing backend suite stays green with its impersonated claims and its assertions unchanged. Those suites impersonate `request.jwt.claims` with `organization_id` and insert their fixture users after the backfill, so each such suite's fixture setup gains the membership row each impersonated fixture user needs — the fixture user, the organisation its claim names, and the fixture staff role — mirroring the backfill rule. A suite that deliberately impersonates a user with no fixture staff/membership row keeps asserting denial. (06 §3 V1 H-BK; 06 §3 V7; 06 §4 P1.1)

### 3.2 Key Entities

- **membership**: A row with `user_id`, `organization_id`, and `role`. A user may hold a membership in more than one organisation. The backend is the authority and the writer. There is no copy.
- **Active-org record**: One active organisation per user, the source of the session's `active_org` claim.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: Backend-only tenancy for a small-to-mid-size clinic. Staff belong to an organisation through membership, and the session carries that organisation (01 R-1, T-1). The row names no wiring exception. The codebase cell is backend.
- **Layer Placement**: PostgreSQL holds `membership`, the per-user active-org record, `current_org_id()`, `current_membership_role()`, and the re-pointed `public.jwt_organization_id()`. Supabase Auth invokes `public.get_custom_claims` to write the `active_org` claim. `set_active_organization` is a PostgREST RPC. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: The backend is the authority for tenancy and membership and writes that state; there is no copy (03 §1). `current_org_id()` re-checks a live membership on every call (02 §2 TB-4; 02 §4.3, tenant-isolation layer 1). RLS selects and definer RPCs follow `public.jwt_organization_id()`.
- **Failure Handling**: `set_active_organization` without a membership returns an error and leaves the claim unchanged. Membership deleted while the JWT is still valid, or a crafted JWT for an organisation with no membership, yields no organisation: `current_org_id()` is NULL, RLS selects return 0 rows, and a definer RPC raises (SR-03, A36 backend).

## 5. Out of Scope

per-tenant `roles_permissions` and the org audit of tables and RPCs (→ P1.2); token changes (→ P5.1); a desktop organisation switcher (not in the design, OQ-2).

- No material from the Do not read sections: 03 §2–§3, 04 §1, and 04 §5–§6 (vendor-side).
- No Consumes contract to rewrite. This unit depends on no earlier unit.
- No module that no test-plan row reaches.
- No removal of a transitional path a later unit owns (rule S9): enrollment, removed in P3.2; `/control/entitle`, which keeps test clinics admitted until P3.4; entitlement, plan, and invoice tables and all `/control/*` routes, removed in P3.10.
- No second codebase. The codebase cell is backend. Existing policies keep calling `public.jwt_organization_id()`; that function is re-pointed to `current_org_id()` (06 §2 S5).

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P1.1-01, E2E-P1.1-02, E2E-P1.1-03, E2E-P1.1-04, E2E-P1.1-05, E2E-P1.1-06, E2E-P1.1-07, and E2E-P1.1-08 pass in harness H-BK.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-2 default, quoted: "out of scope; the active organisation is changed only through the `set_active_organization` RPC." P1.1 sets the active-org claim from the user's sole membership at sign-in.
- Rule S9: enrollment remains until P3.2; `/control/entitle` remains until P3.4; entitlement, plan, and invoice tables and `/control/*` routes remain until P3.10.
