# Tasks: Tenant scoping of shared state and the cross-tenant suite

**Input**: Design documents from `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/` (`AVAILABLE_DOCS`: `research.md`, `data-model.md`, `contracts/`). `quickstart.md` is written in Documentation after verification.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id in the spec Test plan, plus the two-org fixture Sequencing step 1 names. Test Layout names no extra test id. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: Files names no file that must exist before the tests. No Foundational phase (prerequisites are P1.1, already merged, listed in Consumes Binding). No Polish phase.

**Task count**: 38. Size L is 32–40 (rule S3). The count is the honest list: the fixture (Sequencing step 1), six E2E tests (steps 2–7), twenty-nine migration steps (steps 8–36), one verification task for steps 37–39, and `quickstart.md`. It is not padded upward.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/supabase/migrations/`, `backend/tests/`, `backend/tests/catalog/`
- **CI**: `.github/workflows/ci.yml` — this unit leaves the `backend-sql` job as it is
- **Spec Kit artifacts**: `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/`
- This unit's Files section names `backend/`. The new migration is `backend/supabase/migrations/20261002150000_tenant_scoping.sql`. The new suite is `backend/tests/cross_tenant_suite.sql`, registered with one `run_sql_test` line in `backend/tests/run_all_backend_tests.sh`. `backend/tests/catalog/run.sh` stays as it is. Historical migration files stay untouched. `public.current_org_id()` and `public.current_membership_role()` stay as P1.1 froze them.

---

## 3. Tests

**Purpose**: One failing test per E2E id, written before `20261002150000_tenant_scoping.sql` exists. Append to `backend/tests/cross_tenant_suite.sql` in id order T001 through T006, then register that file in T007. Story headings group the tasks. Ids follow Sequencing, so T006 (User Story 1) is appended after T005 (User Story 3).

### 3.1 User Story 2 - Per-tenant roles and permissions (Priority: P2)

**Independent Test**: E2E-P1.2-01 in harness H-BK.

- [X] T001 [US2] Write the two-org fixture in `backend/tests/cross_tenant_suite.sql` — produces the shared fixture, satisfies FR-009, proved by E2E-P1.2-01 through E2E-P1.2-06. Sequencing step 1. Create organisation A, organisation B, an administrator membership in each, and one user with a membership in both. Later calls use `SET ROLE authenticated` and `request.jwt.claims`, matching `backend/tests/membership_active_org.sql`. Leave `public.set_active_organization` as it is. This task adds no E2E assertion yet.

- [X] T002 [US2] Add the failing test `E2E-P1.2-01 — admin of A edits roles_permissions; B unchanged` to `backend/tests/cross_tenant_suite.sql` — produces the red test, satisfies FR-003, proved by E2E-P1.2-01. Depends on T001 (same file). Sequencing step 2. An administrator of A calls `public.update_role_permission(public.staff_role, text, boolean)` and `public.update_role_permissions(jsonb)`. B's permissions and B's `ai.%` grants stay unchanged. Observe the test fail: `roles_permissions` is still unscoped.

**Checkpoint**: E2E-P1.2-01 exists and fails.

### 3.2 User Story 1 - Tenant inventory keyed on the session organisation (Priority: P1)

**Independent Test**: E2E-P1.2-02, E2E-P1.2-03, and E2E-P1.2-05 in harness H-BK (`backend/tests/` on local Supabase).

- [X] T003 [US1] Add the failing test `E2E-P1.2-02 — user of A calls every tenant RPC with B's ids` to `backend/tests/cross_tenant_suite.sql` — produces the red test, satisfies FR-001 and FR-005, proved by E2E-P1.2-02. Depends on T002 (same file). Sequencing step 3. Call each **keyed** and **fix** function in `research.md` §7 with B's ids. The result is not found or empty. Foreign ids use the existing `error_code` `NOT_FOUND` or an empty result. B's rows stay unchanged. Observe the test fail: the **fix** functions are still open to B's ids.

- [X] T004 [US1] Add the failing test `E2E-P1.2-03 — direct reads by A return zero B rows` to `backend/tests/cross_tenant_suite.sql` — produces the red test, satisfies FR-001 and FR-006, proved by E2E-P1.2-03. Depends on T003 (same file). Sequencing step 4. `SELECT` as A of every tenant table in `research.md` §2 returns zero rows of organisation B. Observe the test fail: inventoried tables still return B's rows.

- [X] T006 [US1] Add the failing test `E2E-P1.2-05 — AI RPCs write organization_id = current_org_id()` to `backend/tests/cross_tenant_suite.sql` — produces the red test, satisfies FR-002 and FR-008, proved by E2E-P1.2-05. Depends on T005 (same file). Sequencing step 6. Append this test after T005 even though this heading also holds T003 and T004. `public.record_ai_acceptance(text, text, jsonb)` and `public.issue_ai_token(text[])` write `organization_id = public.current_org_id()`. `auth_internal.record_ai_acceptance` stays as it is; the test reads the row it writes. Observe the test fail: `issue_ai_token` does not yet write `organization_id` from `current_org_id()`.

**Checkpoint**: E2E-P1.2-02, E2E-P1.2-03, and E2E-P1.2-05 exist and fail. E2E-P1.2-05 is appended after T005.

### 3.3 User Story 3 - Staff and branches follow the active organisation (Priority: P3)

**Independent Test**: E2E-P1.2-04 in harness H-BK.

- [X] T005 [US3] Add the failing test `E2E-P1.2-04 — dual-membership user sees only the active org` to `backend/tests/cross_tenant_suite.sql` — produces the red test, satisfies FR-004 and FR-007, proved by E2E-P1.2-04. Depends on T004 (same file). Sequencing step 5. `public.set_active_organization(p_organization_id)` succeeds, the test refreshes `request.jwt.claims` so `active_org` is that organisation (the P1.1 refresh), then `SELECT` on `staff_members` and `staff_branch_assignments` returns only the active organisation's rows. Leave `public.set_active_organization` as it is. Observe the test fail: staff and assignment policies are not yet the membership predicate.

**Checkpoint**: E2E-P1.2-04 exists and fails.

### 3.4 User Story 4 - Cross-tenant suite (Priority: P4)

**Independent Test**: E2E-P1.2-06 in harness H-BK.

- [X] T007 [US4] Register `cross_tenant_suite.sql` in `backend/tests/run_all_backend_tests.sh` with one `run_sql_test` line — produces the runner entry for `E2E-P1.2-06 — all backend suites green`, satisfies FR-009, proved by E2E-P1.2-06. Depends on T006. Sequencing step 7. Observe `backend/tests/run_all_backend_tests.sh` fail because the new suite's tests fail. Leave `backend/tests/catalog/run.sh` and `.github/workflows/ci.yml` as they are.

**Checkpoint**: E2E-P1.2-06 is registered and `backend/tests/run_all_backend_tests.sh` fails.

---

## 4. Implementation

**Purpose**: Sequencing steps 8–36, each one task, appended to `backend/supabase/migrations/20261002150000_tenant_scoping.sql`. Sections follow that order. User Story 2 is steps 8–13. User Story 1 is steps 14–16 and, after User Story 3, steps 19–36. User Story 3 is steps 17–18. Follow `research.md` §2–§5, `data-model.md`, and `contracts/roles-permissions.md`. `CREATE OR REPLACE` of the named functions lives in this migration. Objects that already compare the row's organisation to `public.jwt_organization_id()` are already keyed, because that function returns `public.current_org_id()`, and those objects stay as they are. `auth_internal.record_ai_acceptance` stays as it is. Older migration files stay untouched. Soft-delete columns, existing branch predicates, and audit inserts stay.

### 4.1 User Story 2 - Per-tenant roles and permissions (Priority: P2)

**Independent Test**: E2E-P1.2-01 in harness H-BK.

#### 4.1.1 User Story 2 - Per-tenant roles and permissions (part 1)

- [X] T008 [US2] Create `backend/supabase/migrations/20261002150000_tenant_scoping.sql` with `roles_permissions.organization_id` and unique `(organization_id, role, permission_key)` — produces the per-tenant key, satisfies FR-003, proved by E2E-P1.2-01. Depends on T001–T007 (those tests are already failing). Sequencing step 8. Column and uniqueness follow `contracts/roles-permissions.md` and `data-model.md`.

- [X] T009 [US2] Append the matrix copy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces one copy of the pre-change matrix on every existing organisation, with the unscoped rows removed, satisfies FR-003, proved by E2E-P1.2-01. Depends on T008 (same file). Sequencing step 9.

- [X] T010 [US2] Append the `AFTER INSERT` seed trigger on `public.organizations` to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces the per-organisation default matrix, satisfies FR-003, proved by E2E-P1.2-01. Depends on T009 (same file). Sequencing step 10. The trigger seeds the default matrix. It does not copy another tenant's later edits.

- [X] T011 [US2] Append `CREATE OR REPLACE` of `roles_permissions_select` to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces the per-tenant select policy, satisfies FR-003, proved by E2E-P1.2-01. Depends on T010 (same file). Sequencing step 11. The policy follows `contracts/roles-permissions.md`.

- [X] T012 [US2] Append `CREATE OR REPLACE` of `auth_internal.update_role_permission` to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces the per-tenant single-row update, satisfies FR-003, proved by E2E-P1.2-01. Depends on T011 (same file). Sequencing step 12. Scope the body to `current_org_id()`. Leave `public.current_org_id()` and `public.current_membership_role()` as they are.

#### 4.1.2 User Story 2 - Per-tenant roles and permissions (part 2)

- [X] T013 [US2] Append `CREATE OR REPLACE` of `auth_internal.update_role_permissions` to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces the per-tenant bulk update, satisfies FR-003, proved by E2E-P1.2-01. Depends on T012 (same file). Sequencing step 13. Scope the body to `current_org_id()`.

**Checkpoint**: E2E-P1.2-01 passes.

### 4.2 User Story 1 - Tenant inventory keyed on the session organisation (Priority: P1)

**Independent Test**: E2E-P1.2-02, E2E-P1.2-03, and E2E-P1.2-05 in harness H-BK (`backend/tests/` on local Supabase).

#### 4.2.1 User Story 1 - Tenant inventory keyed on the session organisation (part 1)

- [X] T014 [US1] Append `ai_token_issuance.organization_id`, the membership backfill, and the replaced SELECT policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces org-scoped token issuance, satisfies FR-002 and FR-008, proved by E2E-P1.2-05. Depends on T013 (same file). Sequencing step 14. Follow `data-model.md`.

- [X] T015 [US1] Append `CREATE OR REPLACE` of `auth_internal.issue_ai_token` so it writes `organization_id` and the token `org` claim from `current_org_id()` to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that write, satisfies FR-002 and FR-008, proved by E2E-P1.2-05. Depends on T014 (same file). Sequencing step 15. Leave `auth_internal.record_ai_acceptance` as it is.

- [X] T016 [US1] Append the `auth_internal.issue_ai_token` scope load to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces `ai.%` scopes from `roles_permissions` for `current_org_id()` and `current_membership_role()`, satisfies FR-003 and FR-008, proved by E2E-P1.2-01 and E2E-P1.2-05. Depends on T015 (same file). Sequencing step 16. Leave `public.current_membership_role()` as it is.

**Checkpoint**: E2E-P1.2-05 passes. E2E-P1.2-02 and E2E-P1.2-03 stay failing until T036. Sequencing steps 17–18 are User Story 3 and come next.

### 4.3 User Story 3 - Staff and branches follow the active organisation (Priority: P3)

**Independent Test**: E2E-P1.2-04 in harness H-BK.

- [X] T017 [US3] Append `CREATE OR REPLACE` of `staff_members_select` and `staff_members_update` to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces the membership predicate on staff rows, satisfies FR-004 and FR-007, proved by E2E-P1.2-04. Depends on T016 (same file). Sequencing step 17. Staff rows have no organisation of their own. The policies tie staff to the organisation through membership.

- [X] T018 [US3] Append `CREATE OR REPLACE` of `staff_branch_assignments_select` to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces the membership predicate on assignment rows, satisfies FR-004 and FR-007, proved by E2E-P1.2-04. Depends on T017 (same file). Sequencing step 18. Keep the setup-required arm only when `current_org_id()` is null.

**Checkpoint**: E2E-P1.2-04 passes.

### 4.4 User Story 1 - Tenant inventory keyed on the session organisation (Priority: P1)

**Independent Test**: E2E-P1.2-02, E2E-P1.2-03, and E2E-P1.2-05 in harness H-BK (`backend/tests/` on local Supabase).

Sequencing returns to User Story 1 at step 19. Each table task adds `organization_id`, the backfill, and a restrictive policy, as `data-model.md` and `research.md` §2.2 describe.

#### 4.4.1 User Story 1 - Tenant inventory keyed on the session organisation (part 2)

- [X] T019 [US1] Append `public.appointments` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T018 (same file). Sequencing step 19.

- [X] T020 [US1] Append `public.visits` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T019 (same file). Sequencing step 20.

- [X] T021 [US1] Append `public.visit_clinical_notes` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T020 (same file). Sequencing step 21.

- [X] T022 [US1] Append `public.visit_vital_signs` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T021 (same file). Sequencing step 22.

- [X] T023 [US1] Append `public.visit_investigations` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T022 (same file). Sequencing step 23.

#### 4.4.2 User Story 1 - Tenant inventory keyed on the session organisation (part 3)

- [X] T024 [US1] Append `public.visit_attachments` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T023 (same file). Sequencing step 24.

- [X] T025 [US1] Append `public.treatment_plans` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T024 (same file). Sequencing step 25.

- [X] T026 [US1] Append `public.invoice_items` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T025 (same file). Sequencing step 26.

- [X] T027 [US1] Append `public.payments` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T026 (same file). Sequencing step 27.

- [X] T028 [US1] Append `public.invoice_number_sequences` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T027 (same file). Sequencing step 28. Existing deny-all policies stay.

#### 4.4.3 User Story 1 - Tenant inventory keyed on the session organisation (part 4)

- [X] T029 [US1] Append `public.patient_allergies` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T028 (same file). Sequencing step 29.

- [X] T030 [US1] Append `public.patient_medications` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T029 (same file). Sequencing step 30.

- [X] T031 [US1] Append `public.patient_chronic_conditions` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T030 (same file). Sequencing step 31.

- [X] T032 [US1] Append `public.service_branches` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T031 (same file). Sequencing step 32.

- [X] T033 [US1] Append `public.shift_assignments` column, backfill, and restrictive policy to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that table's org key, satisfies FR-001, FR-002, and FR-006, proved by E2E-P1.2-03. Depends on T032 (same file). Sequencing step 33.

#### 4.4.4 User Story 1 - Tenant inventory keyed on the session organisation (part 5)

- [X] T034 [US1] Append restrictive policy `invoices_org` on `public.invoices` to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces that org policy, satisfies FR-001 and FR-006, proved by E2E-P1.2-03. Depends on T033 (same file). Sequencing step 34.

- [X] T035 [US1] Append the shared `BEFORE INSERT` trigger to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces `organization_id` filled from the parent, satisfies FR-001 and FR-002, proved by E2E-P1.2-03. Depends on T034 (same file). Sequencing step 35. The parent for each table is `research.md` §2.2.

- [X] T036 [US1] Append `organization_id = public.current_org_id()` on the row lookups in `research.md` §4.2 to `backend/supabase/migrations/20261002150000_tenant_scoping.sql` — produces those scoped lookups, satisfies FR-001 and FR-005, proved by E2E-P1.2-02. Depends on T035 (same file). Sequencing step 36. `CREATE OR REPLACE` `get_appointment`, `get_visit_by_appointment`, `list_invoices`, `list_patient_invoices`, `assert_invoice_branch_scope`, `lock_draft_invoice`, and `lock_payable_invoice`. Existing branch predicates stay.

**Checkpoint**: E2E-P1.2-02 and E2E-P1.2-03 pass. E2E-P1.2-05 already passes from T016.

---

## 5. Verification

**Purpose**: This unit's H-BK suite passes, then every earlier suite is still green (rule S2). P1.1 and the pre-existing backend suites run inside the two H-BK commands below.

- [X] T037 Run harness H-BK on local Supabase and confirm it is green — produces the green run, satisfies FR-009, SC-001, and SC-002, proved by E2E-P1.2-01 through E2E-P1.2-06. Depends on T001–T036. Sequencing steps 37–39. Re-run `backend/tests/cross_tenant_suite.sql` and confirm E2E-P1.2-01 through E2E-P1.2-05 pass. Re-run `backend/tests/run_all_backend_tests.sh` and confirm it exits 0. Re-run `backend/tests/catalog/run.sh` and confirm it exits 0. `backend/tests/catalog/run.sh` stays as it is. Those two runner commands are the regression: they include this unit's suite and every earlier backend suite, including P1.1. A full-product `npm test` is not this command.

  Escalation resolution (2026-10-02; see `plan.md` §8): T008–T036 are not reopened. If E2E-P1.2-01 through E2E-P1.2-05 do not all pass on a clean local DB (`supabase db reset --no-seed`, then `psql -f backend/tests/cross_tenant_suite.sql`), this task's agent may make the following corrections, and only these, until the suite is green. No spec behaviour change and no new product scope.

  1. Correct `backend/supabase/migrations/20261002150000_tenant_scoping.sql`. This explicitly includes one `CREATE OR REPLACE` that scopes the `branch_ids` claim to the active organisation — in `auth_internal.build_staff_claims`, or as an intersection in `public.jwt_branch_ids()` — so that after `public.set_active_organization` and the claims refresh, `public.jwt_branch_ids()` excludes the other organisation's branches (FR-007, E2E-P1.2-04) and the branch-guarded **keyed** RPCs answer not found or empty with B's ids (FR-005, E2E-P1.2-02). It also includes any further correction to the migration's own bodies (for example the **fix** row lookups of Sequencing step 36) needed for E2E-P1.2-01 through E2E-P1.2-05. `public.current_org_id()`, `public.current_membership_role()`, `public.set_active_organization`, `public.get_custom_claims`, and `auth_internal.sync_active_organization` stay as P1.1 froze them. Earlier migration files stay untouched.
  2. Align two assertions in `backend/tests/cross_tenant_suite.sql` with the spec, without weakening any other assertion: the E2E-P1.2-03 `roles_permissions` leak check counts only rows of organisation B (FR-006; own-organisation rows visible under the FR-003 policy are not leaks), and the E2E-P1.2-02 `public.issue_ai_token` call captures the function's `text` result instead of assigning it to a `public.rpc_result` variable (FR-005; a no-row-id function may succeed, and B's rows must be unchanged).

---

## 6. Documentation

**Purpose**: Written after T037 is green (rule S8). The plan leaves `quickstart.md` for implement. `research.md`, `data-model.md`, and `contracts/` stay plan-phase artifacts.

- [X] T038 Create `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, satisfies FR-001 through FR-009, proved by E2E-P1.2-01 through E2E-P1.2-06. Depends on T037. Sections: (1) what was implemented — tenant tables, policies, and definer RPCs keyed on `current_org_id()`; `organization_id` and RLS on AI state and on the tenant tables Sequencing names; per-tenant `roles_permissions` and its seed; staff and branch assignments tied through membership; the cross-tenant suite; (2) files this unit adds or modifies — `backend/supabase/migrations/20261002150000_tenant_scoping.sql`, `backend/tests/cross_tenant_suite.sql`, the one `run_sql_test` line in `backend/tests/run_all_backend_tests.sh`, and this quickstart; no earlier-unit files, no combined counts, and no full-suite regression (that is T037); (3) harness command for this unit's tests only — `psql` on local Supabase with `-f backend/tests/cross_tenant_suite.sql`; (4) how to inspect the change; (5) the entry point → module chain per E2E id below. Every scenario is asserted by H-BK, so this file records harness commands only.

| ID | Chain |
| --- | --- |
| E2E-P1.2-01 | `authenticated` session → `public.update_role_permission` and `public.update_role_permissions` → `auth_internal` bodies → `roles_permissions` for `current_org_id()` only |
| E2E-P1.2-02 | `authenticated` session → each **keyed** and **fix** function in `research.md` §7, called with B's ids → not found or empty, B's rows unchanged |
| E2E-P1.2-03 | `authenticated` session → `SELECT` of each tenant table in `research.md` §2 → zero rows of organisation B |
| E2E-P1.2-04 | `public.set_active_organization` → refreshed `request.jwt.claims` (`active_org` set to the chosen organisation, the P1.1 refresh) → `SELECT` `staff_members` and `staff_branch_assignments` |
| E2E-P1.2-05 | `public.record_ai_acceptance` → `auth_internal.record_ai_acceptance` writes `organization_id` from `jwt_organization_id()`; `public.issue_ai_token` → `auth_internal.issue_ai_token` writes `organization_id = current_org_id()` |
| E2E-P1.2-06 | `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` both exit 0. The catalog script stays as it is |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T007)**: Start immediately. No Setup phase. T001 creates `backend/tests/cross_tenant_suite.sql`. T002–T006 append to that file in id order. T007 registers it. Sequencing steps 1–7 are observed failing before any migration task. T006 is listed under User Story 1 and is written after T005.
- **Implementation (T008–T036)**: After T001–T007 exist and fail. Order is Sequencing: roles and permissions (T008–T013), AI token issuance (T014–T016), staff and assignments (T017–T018), then the remaining tenant tables, `invoices_org`, the insert trigger, and the row lookups (T019–T036). All of these append to one migration file.
- **Verification (T037)**: After every implementation task. Covers Sequencing steps 37–39.
- **Documentation (T038)**: After T037 is green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: Tests T003, T004, and T006 are written in the T001–T007 run and do not wait for the migration. T003 and T004 append after T002. T006 appends after T005. Implementation T014–T016 waits on T013. Implementation T019–T036 waits on T018. `current_org_id()` is the P1.1 helper this unit calls.
- **User Story 2 (P2)**: T001 and T002 are the first tasks, because Sequencing writes the fixture and E2E-P1.2-01 before the other tests. Implementation T008–T013 is the first migration work and waits until T001–T007 are failing. E2E-P1.2-01 passes at T013.
- **User Story 3 (P3)**: Test T005 appends after T004 and does not wait for T014. Implementation T017–T018 waits on T016 and finishes before T019. E2E-P1.2-04 passes at T018.
- **User Story 4 (P4)**: T007 registers the suite after T006 and observes the runner failing. The green run of both H-BK commands is T037, after T008–T036. User Story 4 has no migration task.

### 7.3 Parallel Opportunities

No task is `[P]`. T001–T006 append to `backend/tests/cross_tenant_suite.sql`. T008–T036 append to `backend/supabase/migrations/20261002150000_tenant_scoping.sql`. T007 edits `backend/tests/run_all_backend_tests.sh` and Sequencing places it after T006. A pair from another story stays sequential for the same reason: Sequencing is a single order, and the two files are shared. T037 and T038 are single tasks.

User Story 1's E2E-P1.2-02 and E2E-P1.2-03 are the same-story pair. They share one file, so they run one after the other:

```bash
# Same story, same file. Sequencing step 3, then step 4. Not launched together.
Task: "T003 [US1] Add the failing test E2E-P1.2-02 in backend/tests/cross_tenant_suite.sql"
Task: "T004 [US1] Add the failing test E2E-P1.2-03 in backend/tests/cross_tenant_suite.sql"
```
