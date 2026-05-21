# Tasks: Organization and Branch Management

**Input**: Design documents from `/specs/003-org-branch-management/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md; **V1-1** (`specs/002-auth-rbac`) complete

**Tests**: Included — spec defines acceptance criteria and test cases 1–13 (RLS, RPC validation, admin flows, branch switcher, permission reload).

**Organization**: Tasks grouped by user story. Labels map to `spec.md` user stories (US1–US6).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in same phase)
- **[Story]**: User story label for traceability
- Include exact file paths in descriptions

## Path Conventions

- **Flutter**: `frontend/lib/`, `frontend/test/`
- **Supabase**: `backend/supabase/migrations/`, `backend/tests/`
- **Contracts**: `specs/003-org-branch-management/contracts/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Settings admin module layout, routes, and test workspace before RPC/UI work

- [x] T001 Create settings admin directories in `frontend/lib/features/settings/data/`, `frontend/lib/features/settings/domain/`, `frontend/lib/features/settings/presentation/pages/`, and `frontend/lib/features/settings/presentation/widgets/`
- [x] T002 [P] Create test directories `frontend/test/unit/settings/`, `frontend/test/widget/settings/`, and `frontend/test/integration/settings/`
- [x] T003 [P] Add settings sub-route constants in `frontend/lib/app/app_routes.dart` (`/settings/organization`, `/settings/branches`, `/settings/branches/new`, `/settings/branches/:id/edit`, `/settings/staff`, `/settings/staff/new`, `/settings/staff/:id`, `/settings/staff/:id/reset-password`, `/settings/permissions`)
- [x] T004 [P] Add domain model stubs per `data-model.md` in `frontend/lib/features/settings/domain/organization_profile.dart`, `branch_list_item.dart`, `staff_list_item.dart`, and `permission_matrix_row.dart`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: V1-2 migration (branch code index + management RPCs), backend verification suite, repositories scaffold, auth context reload — **blocks all user stories**

**⚠️ CRITICAL**: No user story phase work until this phase is complete

- [x] T005 Add migration `backend/supabase/migrations/20260522100000_org_branch_management.sql` with partial unique index `branches_organization_code_unique`, `auth_internal.assert_owner_or_administrator()`, `auth_internal.assert_permission()`, and RPCs `update_organization`, `manage_create_branch`, `update_branch`, `set_branch_active`, `update_staff_member`, `set_staff_active`, `update_role_permission` per `contracts/`
- [x] T006 [P] Add CRUD verification SQL in `backend/tests/org_branch_management_crud.sql` (org update, branch lifecycle, `LAST_ACTIVE_BRANCH`, staff update/deactivate, permission toggle, owner-only matrix write)
- [x] T007 [P] Add RLS isolation SQL in `backend/tests/org_branch_management_rls.sql` (cross-org denial for management operations)
- [x] T008 [P] Add test runner `backend/tests/run_org_branch_management_tests.sh`
- [x] T009 [P] Implement `OrganizationRepository` RPC wrapper in `frontend/lib/features/settings/data/organization_repository.dart`
- [x] T010 [P] Implement `BranchRepository` in `frontend/lib/features/settings/data/branch_repository.dart`
- [x] T011 [P] Implement `StaffAdminRepository` in `frontend/lib/features/settings/data/staff_admin_repository.dart`
- [x] T012 [P] Implement `RolePermissionsRepository` in `frontend/lib/features/settings/data/role_permissions_repository.dart`
- [x] T013 Implement `AuthSessionNotifier.reloadContext()` (reload staff profile + permission cache) in `frontend/lib/features/auth/presentation/providers/auth_notifier.dart` and expose via `frontend/lib/shared/providers/auth_session_provider.dart`
- [x] T014 [P] Register settings sub-routes with owner/admin or permission guards in `frontend/lib/app/router.dart`
- [x] T015 [P] Extend `SettingsPage` as admin hub with navigation tiles in `frontend/lib/features/settings/presentation/pages/settings_page.dart`

**Checkpoint**: `supabase migration up` succeeds; `run_org_branch_management_tests.sh` passes; settings routes reachable when authenticated with setup complete

---

## Phase 3: User Story 1 - Maintain Organization Settings (Priority: P1) 🎯 MVP

**Goal**: Owner and administrator can view and update organization profile (name, logo, currency, timezone, settings summary)

**Independent Test**: Sign in as owner or administrator → Settings → Organization → save changes → reload confirms persistence; doctor role denied

### Tests for User Story 1

- [x] T016 [P] [US1] Add unit tests for `OrganizationRepository` in `frontend/test/unit/settings/organization_repository_test.dart`
- [x] T017 [P] [US1] Add widget tests for organization settings states in `frontend/test/widget/settings/organization_settings_page_test.dart`

### Implementation for User Story 1

- [x] T018 [US1] Implement `OrganizationRepository.fetchProfile()` and `updateOrganization()` per `contracts/organization-management.md` in `frontend/lib/features/settings/data/organization_repository.dart`
- [x] T019 [US1] Implement `OrganizationSettingsPage` (loading, validation, save, permission denied) in `frontend/lib/features/settings/presentation/pages/organization_settings_page.dart`
- [x] T020 [US1] Gate organization settings route to `owner` and `administrator` roles in `frontend/lib/app/router.dart` and hub tile in `frontend/lib/features/settings/presentation/pages/settings_page.dart`

**Checkpoint**: Test case 1–2 from spec (org update; second org rejected at RPC if exposed)

---

## Phase 4: User Story 2 - Manage Branches (Priority: P1)

**Goal**: List, create, edit, deactivate, and reactivate branches; hard-block last active branch deactivation with edit shortcut

**Independent Test**: Create second branch, edit, deactivate (not last), reactivate; attempting to deactivate sole active branch shows block + edit navigation

### Tests for User Story 2

- [x] T021 [P] [US2] Add branch RPC tests for `LAST_ACTIVE_BRANCH` and code uniqueness in `backend/tests/org_branch_management_crud.sql`
- [x] T022 [P] [US2] Add unit tests for `BranchRepository` in `frontend/test/unit/settings/branch_repository_test.dart`
- [x] T023 [P] [US2] Add widget tests for branch list and form in `frontend/test/widget/settings/branch_list_page_test.dart` and `frontend/test/widget/settings/branch_form_page_test.dart`

### Implementation for User Story 2

- [x] T024 [US2] Implement `BranchRepository` list/create/update/setActive per `contracts/branch-management.md` in `frontend/lib/features/settings/data/branch_repository.dart`
- [x] T025 [US2] Implement `BranchListPage` with active/inactive filters in `frontend/lib/features/settings/presentation/pages/branch_list_page.dart`
- [x] T026 [US2] Implement `BranchFormPage` create/edit in `frontend/lib/features/settings/presentation/pages/branch_form_page.dart`
- [x] T027 [US2] Implement last-active-branch blocked dialog with **Edit branch** action in `frontend/lib/features/settings/presentation/widgets/last_active_branch_blocked_dialog.dart`
- [x] T028 [US2] Gate branch management routes with `settings.manage_branches` in `frontend/lib/core/auth/permission_service.dart` and `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 3–4; acceptance criteria 3–4

---

## Phase 5: User Story 3 - Manage Staff and Branch Assignments (Priority: P1)

**Goal**: List, create, edit, deactivate, reactivate staff with branch assignments; password reset from staff detail; owner-creation rules preserved

**Independent Test**: Create receptionist with two branches and primary; deactivate and reactivate; administrator cannot create owner when owner exists

### Tests for User Story 3

- [x] T029 [P] [US3] Add staff lifecycle RPC tests in `backend/tests/org_branch_management_crud.sql`
- [x] T030 [P] [US3] Add unit tests for `StaffAdminRepository` in `frontend/test/unit/settings/staff_admin_repository_test.dart`
- [ ] T031 [P] [US3] Add widget tests for staff list/form in `frontend/test/widget/settings/staff_list_page_test.dart` and `frontend/test/widget/settings/staff_form_page_test.dart`

### Implementation for User Story 3

- [ ] T032 [US3] Implement `StaffAdminRepository` list/update/setActive and wire existing `create_staff_account` / `admin_reset_staff_password` in `frontend/lib/features/settings/data/staff_admin_repository.dart`
- [ ] T033 [US3] Implement `StaffListPage` in `frontend/lib/features/settings/presentation/pages/staff_list_page.dart`
- [ ] T034 [US3] Implement `StaffFormPage` (create + edit, branch multi-select, primary branch, owner-creation guard) in `frontend/lib/features/settings/presentation/pages/staff_form_page.dart`
- [ ] T035 [US3] Add staff password reset navigation from staff detail reusing `ProvisioningRepository` in `frontend/lib/features/settings/presentation/pages/staff_form_page.dart` and route `/settings/staff/:id/reset-password`
- [ ] T036 [US3] Gate staff routes with `settings.manage_staff` in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 5–7, 13 (inactive-branch-only assignments → blocked shell after sign-in)

---

## Phase 6: User Story 4 - Switch Active Branch in the Main Shell (Priority: P1)

**Goal**: Branch switcher in shell status bar; replaces AppBar placeholder selector as primary control

**Independent Test**: Multi-branch user switches branch without re-login; single-branch shows label only; no-assignment shows blocked state

### Tests for User Story 4

- [ ] T037 [P] [US4] Add widget tests for `ShellStatusBar` branch switching in `frontend/test/widget/settings/shell_status_bar_test.dart`
- [ ] T038 [P] [US4] Add integration test for branch context update in `frontend/test/integration/settings/branch_switcher_test.dart`

### Implementation for User Story 4

- [ ] T039 [US4] Implement `ShellStatusBar` (branch | user | connection) in `frontend/lib/features/settings/presentation/widgets/shell_status_bar.dart` per `contracts/branch-switcher-shell.md`
- [ ] T040 [US4] Integrate `ShellStatusBar` into `frontend/lib/features/auth/presentation/pages/auth_shell_page.dart` and remove or demote `ShellBranchSelector` from AppBar `actions`
- [ ] T041 [US4] Ensure `AuthSessionNotifier.setActiveBranch()` updates session state used by permission/branch scope in `frontend/lib/features/auth/presentation/providers/auth_notifier.dart`
- [ ] T042 [US4] Verify `staffAssignableBranchesProvider` in `frontend/lib/features/auth/presentation/providers/staff_assignable_branches_provider.dart` lists only active assigned branches

**Checkpoint**: Spec test case 5 (primary + switcher); acceptance criteria 7–8; NFR-005 perceived switch under 2s

---

## Phase 7: User Story 5 - Manage Role Permissions (Priority: P2)

**Goal**: Owner edits permission matrix; administrator view-only; server enforces grants immediately; client cache reloads on login/resume/post-save

**Independent Test**: Owner revokes grant → doctor RPC denied immediately; doctor UI updates after `reloadContext()` or re-login

### Tests for User Story 5

- [ ] T043 [P] [US5] Add permission matrix RPC tests (owner write, administrator denied) in `backend/tests/org_branch_management_crud.sql`
- [ ] T044 [P] [US5] Add unit tests for `RolePermissionsRepository` in `frontend/test/unit/settings/role_permissions_repository_test.dart`
- [ ] T045 [P] [US5] Add widget tests for view-only vs editable matrix in `frontend/test/widget/settings/role_permissions_page_test.dart`

### Implementation for User Story 5

- [ ] T046 [US5] Implement `RolePermissionsRepository` fetch matrix and `updateRolePermission` in `frontend/lib/features/settings/data/role_permissions_repository.dart`
- [ ] T047 [US5] Implement `RolePermissionsPage` (owner toggles, administrator read-only) in `frontend/lib/features/settings/presentation/pages/role_permissions_page.dart`
- [ ] T048 [US5] Call `reloadContext()` after successful matrix save and on app resume hook in `frontend/lib/features/auth/presentation/providers/auth_notifier.dart` or app lifecycle wrapper in `frontend/lib/app/app.dart`
- [ ] T049 [US5] Restrict permissions route to owner (edit) and administrator (view) in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 8–9; acceptance criteria 9–10; FR-011 server vs client timing

---

## Phase 8: User Story 6 - Retire V1-1 Minimal Administration Paths (Priority: P2)

**Goal**: Bootstrap-created data visible in management screens; steady-state settings supersede minimal provisioning entry points when setup complete

**Independent Test**: Tenant from V1-1 bootstrap → org/branch/staff visible in new lists; provisioning routes redirect or demote when not `setup_required`

### Tests for User Story 6

- [ ] T050 [P] [US6] Add integration test bootstrap data visible in settings lists in `frontend/test/integration/settings/bootstrap_data_migration_test.dart`

### Implementation for User Story 6

- [ ] T051 [US6] Redirect authenticated users from minimal `staff_create` / bootstrap-only paths to settings staff create when `setup_required` is false in `frontend/lib/app/router.dart`
- [ ] T052 [US6] Update `AuthShellPage` home actions to link Settings hub instead of standalone provisioning placeholder in `frontend/lib/features/auth/presentation/pages/auth_shell_page.dart`
- [ ] T053 [US6] Keep bootstrap wizard routes active only when `setup_required` is true in `frontend/lib/app/router.dart` and `frontend/lib/features/auth/presentation/pages/clinic_bootstrap_page.dart`

**Checkpoint**: Spec test case 12; acceptance criteria 12; user story 6 acceptance scenarios

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Quickstart validation, docs, regression, and constitution-sensitive verification

- [ ] T054 [P] Run full `specs/003-org-branch-management/quickstart.md` flow and document any gaps in `specs/003-org-branch-management/quickstart.md`
- [ ] T055 [P] Add integration test covering spec test cases 1–13 outline in `frontend/test/integration/settings/org_branch_management_acceptance_test.dart`
- [ ] T056 Run V1-1 regression: bootstrap, login, idle timeout, subscription non-blocking per `specs/002-auth-rbac/quickstart.md`
- [ ] T057 [P] Add admin settings section to `docs/setup/` linking organization, branch, staff, and permissions screens
- [ ] T058 Verify no soft-delete UI for branches/staff (FR-018a) via manual checklist in `specs/003-org-branch-management/spec.md` acceptance criteria
- [ ] T059 [P] Confirm `build_staff_claims` excludes inactive branches (no code change if already correct) and document in `specs/003-org-branch-management/research.md` Decision 5 verification note

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup + V1-1 complete — **blocks all user stories**
- **User Stories (Phases 3–8)**: Depend on Foundational
- **Polish (Phase 9)**: Depends on desired user stories being complete

### User Story Dependencies

| Story | Priority | Depends on             | Notes                                  |
| ----- | -------- | ---------------------- | -------------------------------------- |
| US1   | P1       | Foundational           | MVP — org settings                     |
| US2   | P1       | Foundational           | Branch pickers needed for US3          |
| US3   | P1       | Foundational, US2 (UI) | Staff assignments need active branches |
| US4   | P1       | Foundational           | Can parallel US2/US3 after T013        |
| US5   | P2       | Foundational           | Independent of US1–US4 UI              |
| US6   | P2       | US1, US2, US3, US4     | Integration cleanup                    |

### Recommended execution order (single developer)

1. Phase 1 → Phase 2
2. US1 (**MVP checkpoint**)
3. US2 → US3
4. US4
5. US5 → US6
6. Phase 9

### Parallel Opportunities

- Phase 1: T002, T003, T004 in parallel
- Phase 2: T006–T012, T014–T015 in parallel after T005
- Per story: all `[P]` test tasks before implementation tasks in that story
- US4 can start after T013 (reloadContext) while US2/US3 UI in progress (different files)

### Parallel Example: Foundational

```bash
# Sequential first:
T005 migration

# Then parallel:
T006 org_branch_management_crud.sql
T007 org_branch_management_rls.sql
T009 OrganizationRepository
T010 BranchRepository
T011 StaffAdminRepository
T012 RolePermissionsRepository
```

### Parallel Example: User Story 2

```bash
T021 branch crud SQL additions
T022 branch_repository_test.dart
T024 BranchRepository implementation
T025 BranchListPage
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Complete Phase 1 and Phase 2
2. Complete US1 (organization settings)
3. **STOP and VALIDATE**: quickstart §3 steps 2 (organization save); owner and administrator allowed, doctor denied

### Incremental delivery

1. **Foundation**: Phase 1 + Phase 2
2. **MVP**: + US1
3. **Branches**: + US2
4. **Staff**: + US3
5. **Daily ops**: + US4 (branch switcher)
6. **Security tuning**: + US5 (permission matrix)
7. **UX cleanup**: + US6
8. **Polish**: Phase 9

### Parallel team strategy

- **Developer A**: Phase 2 migration + backend tests (T005–T008)
- **Developer B**: Phase 2 Flutter scaffold + US1 (T009–T020)
- After Foundational: **C** → US2, **D** → US3, **E** → US4/US5

---

## Notes

- Builds on `backend/supabase/migrations/*auth_rbac*` — do not break bootstrap RPCs
- Organization auth: **role** check (owner/administrator), not `settings.manage_organization`
- `LAST_ACTIVE_BRANCH` must surface edit shortcut (FR-003a)
- Permission matrix: server immediate, client cache on reload (FR-011)
- No soft-delete UI (FR-018a); use `is_active` deactivate only
- Single organization per installation unchanged
- Preserve constitution: RPC/RLS authority in PostgreSQL; Flutter permission cache is UX-only
