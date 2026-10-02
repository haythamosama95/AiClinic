# Tenant scoping and cross-tenant suite

**Unit**: P1.2 · **Harness**: H-BK · **Verification**: T037 green

## 1. What was implemented

PostgreSQL on the existing Supabase project keys in-scope tenant state on `public.current_org_id()` (FR-001 through FR-009). P1.1 helpers `public.current_org_id()`, `public.current_membership_role()`, and `public.set_active_organization` are consumed, not edited.

- **Tenant tables and RLS.** Each child table in `research.md` §2.2 receives `organization_id`, a backfill from its parent, and a restrictive policy `organization_id = public.current_org_id()`. Existing permissive policies stay. `public.invoices` keeps its branch predicate and gains restrictive policy `invoices_org`. A shared `BEFORE INSERT` trigger fills `organization_id` from the parent named in `research.md` §2.2 (FR-001, FR-002, FR-006).
- **Definer RPC row lookups.** `CREATE OR REPLACE` on the **fix** functions in `research.md` §4.2 adds `organization_id = public.current_org_id()` to row loads: `get_appointment`, `get_visit_by_appointment`, `list_invoices`, `list_patient_invoices`, `assert_invoice_branch_scope`, `lock_draft_invoice`, and `lock_payable_invoice`. Existing branch predicates stay (FR-001, FR-005).
- **Per-tenant `roles_permissions`.** Column `organization_id`, unique `(organization_id, role, permission_key)`, copy of the pre-change matrix onto every existing organisation with unscoped rows removed, `AFTER INSERT` seed on `public.organizations`, SELECT scoped to `current_org_id()`, and `auth_internal.update_role_permission` / `auth_internal.update_role_permissions` bodies scoped to `current_org_id()` (FR-003).
- **AI token issuance.** `ai_internal.ai_token_issuance.organization_id`, membership backfill, org-scoped SELECT policy, and `auth_internal.issue_ai_token` writing `organization_id` and the token `org` claim from `current_org_id()` and loading `ai.%` scopes from `roles_permissions` for `current_org_id()` and `current_membership_role()`. `auth_internal.record_ai_acceptance` is not replaced; acceptance rows already stamp `organization_id` via `jwt_organization_id()` (FR-002, FR-008).
- **Staff and branch assignments.** `staff_members` SELECT/UPDATE and `staff_branch_assignments` SELECT require membership in `ai_internal.membership` for the active organisation. The setup-required own-row arm on assignments remains only when `current_org_id()` is null (FR-004, FR-007). `public.jwt_branch_ids()` intersects the claim with branches of `current_org_id()` so keyed RPCs and assignment reads respect the active org after a switch.
- **Cross-tenant suite.** `backend/tests/cross_tenant_suite.sql` holds the two-org fixture and E2E-P1.2-01 through E2E-P1.2-05. One `run_sql_test` line registers it in `backend/tests/run_all_backend_tests.sh`. E2E-P1.2-06 is the green run of the full backend runners (FR-009).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `backend/tests/cross_tenant_suite.sql` | FR-001, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |
| `backend/tests/run_all_backend_tests.sh` | FR-009 |
| `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/quickstart.md` | FR-001–FR-009 |

This unit does not edit earlier migration files, `.github/workflows/ci.yml`, or `backend/tests/catalog/run.sh`. Plan-phase artifacts (`research.md`, `data-model.md`, `contracts/`) stay as written in the plan phase. Full-suite regression is verification task T037, not this file.

## 3. Harness command

Harness H-BK, from the repository root, against local Supabase (`supabase start` in `backend/`):

```bash
psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/cross_tenant_suite.sql
```

That file asserts E2E-P1.2-01 through E2E-P1.2-05. It uses `SET ROLE authenticated` and `request.jwt.claims`, matching `backend/tests/membership_active_org.sql`.

## 4. How to inspect the change

Every scenario is asserted by H-BK. This file records harness commands and where the objects live.

- Migration `backend/supabase/migrations/20261002150000_tenant_scoping.sql`: sequencing steps 8–36 — per-tenant `roles_permissions` and seed trigger; `ai_token_issuance` and `auth_internal.issue_ai_token`; staff and assignment policies; `organization_id` columns, backfills, and restrictive policies on the §2.2 tables; `invoices_org`; the shared insert trigger; scoped row lookups in §4.2; and `public.jwt_branch_ids()` scoped to the active organisation.
- Suite `backend/tests/cross_tenant_suite.sql`: two-org fixture, session refresh helper, and one assertion block per E2E-P1.2-01 through E2E-P1.2-05.
- Runner registration: `run_sql_test "Cross-tenant suite" "cross_tenant_suite.sql"` in `backend/tests/run_all_backend_tests.sh`.
- Inventory reference: tenant tables in `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/research.md` §2; **keyed** and **fix** RPCs in §7.

## 5. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P1.2-01 | `authenticated` session → `public.update_role_permission` and `public.update_role_permissions` → `auth_internal` bodies → `roles_permissions` for `current_org_id()` only |
| E2E-P1.2-02 | `authenticated` session → each **keyed** and **fix** function in `research.md` §7, called with B's ids → not found or empty, B's rows unchanged |
| E2E-P1.2-03 | `authenticated` session → `SELECT` of each tenant table in `research.md` §2 → zero rows of organisation B |
| E2E-P1.2-04 | `public.set_active_organization` → refreshed `request.jwt.claims` (`active_org` set to the chosen organisation, the P1.1 refresh) → `SELECT` `staff_members` and `staff_branch_assignments` |
| E2E-P1.2-05 | `public.record_ai_acceptance` → `auth_internal.record_ai_acceptance` writes `organization_id` from `jwt_organization_id()`; `public.issue_ai_token` → `auth_internal.issue_ai_token` writes `organization_id = current_org_id()` |
| E2E-P1.2-06 | `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` both exit 0. The catalog script stays as it is |
