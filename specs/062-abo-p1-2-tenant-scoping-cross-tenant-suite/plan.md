# Implementation Plan: Tenant scoping of shared state and the cross-tenant suite

**Branch**: `ai/062-abo-p1-2-tenant-scoping-cross-tenant-suite` | **Date**: 2026-10-02 | **Spec**: `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/spec.md`

**Input**: Feature specification from `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/spec.md`

## 1. Summary

P1.2 keys every in-scope tenant table, policy, and definer RPC on `public.current_org_id()`, adds `organization_id` and RLS where that column is missing, makes `roles_permissions` per organisation, and ties staff and branch assignments to the active organisation through membership. It sits in phase P1, size L, depends on P1.1, and runs in parallel with P2, P3, and P4. The codebase is backend only.

The inventory is `research.md`. Objects that already compare the row's organisation to `public.jwt_organization_id()` are already keyed, because that function returns `public.current_org_id()`, and this unit does not rewrite them.

## 2. Technical Context

**Language/Version**: PostgreSQL SQL, applied as Supabase migrations under `backend/supabase/migrations/`

**Primary Dependencies**: `public.current_org_id()` and `public.current_membership_role()` from `backend/supabase/migrations/20261002120000_membership_active_org.sql`; existing migrations; the `backend-sql` CI job in `.github/workflows/ci.yml`

**Storage**: Supabase PostgreSQL

**Testing**: Harness H-BK. psql suites in `backend/tests/` on local Supabase, plus the existing catalog runner `backend/tests/catalog/run.sh`

**Target Platform**: Local Supabase for H-BK (the `backend-sql` job runs `supabase start` in `backend/`)

**Project Type**: Backend tenancy on the shared Supabase project. No Flutter, Worker, or package code

**Performance Goals**: Clinic-scale PostgREST reads and definer RPCs for a small-to-mid multi-branch clinic (spec §4.1). No separate throughput target

**Constraints**: One codebase (backend). Do not change `current_org_id()` or `current_membership_role()`. Do not edit existing migration files or the backend CI job. Installation keys and the single-installation trigger stay for P5.1. The availability flag stays for P5.2. Enrollment, `/control/entitle`, and entitlement, plan, and invoice tables on the platform stay until their owning units (rule S9). Soft-delete columns stay. Foreign ids keep the existing `NOT_FOUND` result or an empty read

**Scale/Scope**: Two organisations and two administrators in the cross-tenant suite, plus one dual-membership user. Size L (32–40 tasks). This plan's sequencing is 39 steps

## 3. Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-checked against `.specify/memory/constitution.md` (version 1.0.0) and against `docs/architecture/ai-billing-orchestration/02-abo-architecture-and-threat-model.md` §7. The same answers hold after the data model and the `roles_permissions` contract.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

Clinic fit is the spec's backend tenancy for a small-to-mid multi-branch clinic. The change is one new SQL migration and one SQL suite. PostgreSQL holds the org keys, the new columns, the policies, and the membership predicates. PostgREST remains the live entry: H-BK calls the public functions as `authenticated` with `request.jwt.claims`, which is how this harness reaches those RPCs. Existing branch predicates stay. Audit inserts stay. Soft-delete columns stay. `record_ai_acceptance` remains the human acceptance write. No AI component gains a database credential. Clinical reads do not depend on AI being up.

02 §7 is satisfied the same way: no new Worker, queue, or primary backend; clinic state stays in PostgreSQL; tenant isolation is the membership re-check in `current_org_id()` plus stores keyed by that value. No box is unticked. 02 §7 records no violation for this unit.

## 4. Project Structure

### 4.1 Documentation (this feature)

```text
specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/
├── plan.md
├── research.md          # tenant inventory (FR-001); Spikes is None
├── data-model.md
├── quickstart.md        # outline only; implement writes it after verification
├── contracts/
│   └── roles-permissions.md
└── tasks.md             # not created in this phase
```

`quickstart.md` sections, written in the implement phase after the suite is green:

1. What was implemented.
2. Files this unit adds or modifies.
3. The harness command for this unit's tests only: `psql` on local Supabase with `-f backend/tests/cross_tenant_suite.sql`. Not `run_all_backend_tests.sh` and not a combined count.
4. Entry point → module chain per E2E id (rule S8):
   - **E2E-P1.2-01**: `authenticated` session → `public.update_role_permission` and `public.update_role_permissions` → `auth_internal` bodies → `roles_permissions` for `current_org_id()` only.
   - **E2E-P1.2-02**: `authenticated` session → each **keyed** and **fix** function in `research.md` §7, called with B's ids → not found or empty, B's rows unchanged.
   - **E2E-P1.2-03**: `authenticated` session → `SELECT` of each tenant table in `research.md` §2 → zero rows of organisation B.
   - **E2E-P1.2-04**: `public.set_active_organization` → refreshed `request.jwt.claims` (`active_org` set to the chosen organisation, the P1.1 refresh) → `SELECT` `staff_members` and `staff_branch_assignments`.
   - **E2E-P1.2-05**: `public.record_ai_acceptance` → `auth_internal.record_ai_acceptance` writes `organization_id` from `jwt_organization_id()`; `public.issue_ai_token` → `auth_internal.issue_ai_token` writes `organization_id = current_org_id()`.
   - **E2E-P1.2-06**: `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` both exit 0. The catalog script is not edited.

### 4.2 Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20261002150000_tenant_scoping.sql
└── tests/
    ├── cross_tenant_suite.sql
    └── run_all_backend_tests.sh
```

**Structure Decision**: Backend only, matching the unit's codebase cell. New objects live in one migration newer than `20261002120000_membership_active_org.sql`. The suite is one psql file registered in the existing H-BK runner. The CI job and `backend/tests/catalog/run.sh` stay as they are.

## 5. Consumes Binding

| Consumes | Existing module | This unit |
| --- | --- | --- |
| `current_org_id()` semantics | `public.current_org_id()` in `backend/supabase/migrations/20261002120000_membership_active_org.sql` | Called. Not edited |
| `current_membership_role()` semantics | `public.current_membership_role()` in the same migration | Called for the `roles_permissions` administrator read and for AI scopes. Not edited |
| Migrations | `backend/supabase/migrations/` | Existing files stay. This unit adds `20261002150000_tenant_scoping.sql` |
| Backend CI job | `.github/workflows/ci.yml` job `backend-sql` (`supabase start`, then `backend/tests/run_all_backend_tests.sh`, then `backend/tests/catalog/run.sh`) | Not edited. The new suite is registered in the runner the job already calls |

## 6. Files

| File | Action | FR |
| --- | --- | --- |
| `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/plan.md` | Created | FR-001–FR-009 |
| `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/research.md` | Created | FR-001 |
| `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/data-model.md` | Created | FR-001, FR-002, FR-003, FR-004 |
| `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/contracts/roles-permissions.md` | Created | FR-003 |
| `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/quickstart.md` | Implement phase, after the suite is green | FR-001–FR-009 |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | Create | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `backend/tests/cross_tenant_suite.sql` | Create | FR-001, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |
| `backend/tests/run_all_backend_tests.sh` | Add one `run_sql_test` line for `cross_tenant_suite.sql` | FR-009 |

The migration's contents are the fixes in `research.md` §2–§5: per-tenant `roles_permissions` and its seed trigger; `ai_token_issuance.organization_id` and the `issue_ai_token` write and scope query; staff and assignment policies through membership; `organization_id` plus restrictive RLS and the insert trigger for each table in `research.md` §2.2; the restrictive policy on `public.invoices`; the branch-only row predicates in `research.md` §4.2. `CREATE OR REPLACE` of those functions lives in the new migration. Older migration files are not edited.

`auth_internal.record_ai_acceptance` is not replaced. E2E-P1.2-05 reads the row it writes and compares `organization_id` to `public.current_org_id()`.

## 7. Test Layout

Tests are written to fail before `20261002150000_tenant_scoping.sql` exists. Titles start with the E2E id. Harness H-BK: one psql file, `SET ROLE authenticated` and `request.jwt.claims` around each call, matching `backend/tests/membership_active_org.sql`.

| ID | File | Title | Assertion |
| --- | --- | --- | --- |
| E2E-P1.2-01 | `backend/tests/cross_tenant_suite.sql` | `E2E-P1.2-01 — admin of A edits roles_permissions; B unchanged` | Administrator of A calls `public.update_role_permission(public.staff_role, text, boolean)` and `public.update_role_permissions(jsonb)`. B's permissions and B's `ai.%` grants are unchanged |
| E2E-P1.2-02 | `backend/tests/cross_tenant_suite.sql` | `E2E-P1.2-02 — user of A calls every tenant RPC with B's ids` | Each **keyed** and **fix** function in `research.md` §7, with B's ids, returns not found or empty. Foreign ids use the existing `error_code` `NOT_FOUND` or an empty result. B's rows are unchanged |
| E2E-P1.2-03 | `backend/tests/cross_tenant_suite.sql` | `E2E-P1.2-03 — direct reads by A return zero B rows` | `SELECT` as A of every tenant table in `research.md` §2 returns zero rows of organisation B |
| E2E-P1.2-04 | `backend/tests/cross_tenant_suite.sql` | `E2E-P1.2-04 — dual-membership user sees only the active org` | `public.set_active_organization(p_organization_id)` succeeds, the test refreshes `request.jwt.claims` so `active_org` is that organisation, then `SELECT` on `staff_members` and `staff_branch_assignments` returns only the active organisation's rows |
| E2E-P1.2-05 | `backend/tests/cross_tenant_suite.sql` | `E2E-P1.2-05 — AI RPCs write organization_id = current_org_id()` | `public.record_ai_acceptance(text, text, jsonb)` and `public.issue_ai_token(text[])` write `organization_id = public.current_org_id()` |
| E2E-P1.2-06 | `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` | `E2E-P1.2-06 — all backend suites green` | Both commands exit 0. The catalog command is not modified. The runner includes `cross_tenant_suite.sql` |

The fixture inside `cross_tenant_suite.sql` creates organisation A, organisation B, an administrator membership in each, and one user with a membership in both. It does not change `set_active_organization`.

## 8. Sequencing

Tests land first and are observed failing before the migration. 39 steps. Do not split a step.

1. Write the two-org fixture in `backend/tests/cross_tenant_suite.sql`.
2. Write E2E-P1.2-01 and observe it fail.
3. Write E2E-P1.2-02 and observe it fail.
4. Write E2E-P1.2-03 and observe it fail.
5. Write E2E-P1.2-04 and observe it fail.
6. Write E2E-P1.2-05 and observe it fail.
7. Register `cross_tenant_suite.sql` in `backend/tests/run_all_backend_tests.sh`. Observe that file failing. Do not edit `catalog/run.sh` or `.github/workflows/ci.yml`.
8. Add `roles_permissions.organization_id` and unique `(organization_id, role, permission_key)`.
9. Copy the pre-change matrix onto every existing organisation and remove the unscoped rows.
10. Add the `AFTER INSERT` seed trigger on `public.organizations` (default matrix, not another tenant's later edits).
11. Replace `roles_permissions_select`.
12. Scope `auth_internal.update_role_permission` to `current_org_id()`.
13. Scope `auth_internal.update_role_permissions` to `current_org_id()`.
14. Add `ai_token_issuance.organization_id`, backfill from membership, and replace the SELECT policy.
15. Make `auth_internal.issue_ai_token` write `organization_id` and the token `org` claim from `current_org_id()`.
16. Make `auth_internal.issue_ai_token` load `ai.%` scopes from `roles_permissions` for `current_org_id()` and `current_membership_role()`.
17. Replace `staff_members_select` and `staff_members_update` with the membership predicate.
18. Replace `staff_branch_assignments_select` with the membership predicate, keeping the setup-required arm only when `current_org_id()` is null.
19. `public.appointments`: column, backfill, restrictive policy.
20. `public.visits`: column, backfill, restrictive policy.
21. `public.visit_clinical_notes`: column, backfill, restrictive policy.
22. `public.visit_vital_signs`: column, backfill, restrictive policy.
23. `public.visit_investigations`: column, backfill, restrictive policy.
24. `public.visit_attachments`: column, backfill, restrictive policy.
25. `public.treatment_plans`: column, backfill, restrictive policy.
26. `public.invoice_items`: column, backfill, restrictive policy.
27. `public.payments`: column, backfill, restrictive policy.
28. `public.invoice_number_sequences`: column, backfill, restrictive policy. Existing deny-all policies stay.
29. `public.patient_allergies`: column, backfill, restrictive policy.
30. `public.patient_medications`: column, backfill, restrictive policy.
31. `public.patient_chronic_conditions`: column, backfill, restrictive policy.
32. `public.service_branches`: column, backfill, restrictive policy.
33. `public.shift_assignments`: column, backfill, restrictive policy.
34. Add restrictive policy `invoices_org` on `public.invoices`.
35. Add the shared `BEFORE INSERT` trigger that fills `organization_id` from the parent in `research.md` §2.2.
36. Add `organization_id = public.current_org_id()` to the row lookups in `research.md` §4.2 (`get_appointment`, `get_visit_by_appointment`, `list_invoices`, `list_patient_invoices`, `assert_invoice_branch_scope`, `lock_draft_invoice`, `lock_payable_invoice`).
37. Re-run `backend/tests/cross_tenant_suite.sql` and confirm E2E-P1.2-01 through E2E-P1.2-05 pass.
38. Re-run `backend/tests/run_all_backend_tests.sh` and confirm it exits 0.
39. Re-run `backend/tests/catalog/run.sh` and confirm it exits 0.

## 9. Complexity Tracking

No constitution violation. 02 §7 records none for this unit. Nothing is listed here.
