
# Tasks: Patient Management

**Input**: Design documents from `/specs/004-patient-management/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md; **V1-2** (`specs/003-org-branch-management`) and **V1-1** (`specs/002-auth-rbac`) complete

**Tests**: Included — spec defines acceptance criteria and test cases 1–13; constitution requires RLS/RPC verification (`backend/tests/`).

**Organization**: Tasks grouped by user story. Labels map to `spec.md` user stories (US1–US5).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in same phase)
- **[Story]**: User story label for traceability
- Include exact file paths in descriptions

## Path Conventions

- **Flutter**: `frontend/lib/`, `frontend/test/`
- **Supabase**: `backend/supabase/migrations/`, `backend/tests/`
- **Contracts**: `specs/004-patient-management/contracts/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Patients feature module layout, routes, and test workspace before migration/UI work

- [x] T001 Create patients feature directories in `frontend/lib/features/patients/data/`, `frontend/lib/features/patients/domain/`, `frontend/lib/features/patients/presentation/pages/`, `frontend/lib/features/patients/presentation/providers/`, and `frontend/lib/features/patients/presentation/widgets/`
- [x] T002 [P] Create test directories `frontend/test/unit/patients/`, `frontend/test/widget/patients/`, and `frontend/test/integration/patients/`
- [x] T003 [P] Add patient route constants in `frontend/lib/app/app_routes.dart` (`/patients`, `/patients/new`, `/patients/:id`, `/patients/:id/edit` plus path builders)
- [x] T004 [P] Add domain model stubs per `data-model.md` in `frontend/lib/features/patients/domain/patient_list_item.dart`, `patient_detail.dart`, `patient_list_scope.dart`, and `duplicate_candidate.dart`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: `patients` migration, all patient RPCs, backend verification suite, repository scaffold, permission keys, route guards — **blocks all user stories**

**⚠️ CRITICAL**: No user story phase work until this phase is complete

- [x] T005 Add migration `backend/supabase/migrations/20260523140000_patient_management.sql` with `patient_gender` enum, `patients` table (`organization_id` denormalized), indexes, RLS (SELECT org-scoped; INSERT/UPDATE/DELETE denied), `auth_internal` helpers (phone normalize, duplicate finder, org patient assert), and RPCs `search_patients`, `get_patient`, `check_patient_duplicates`, `create_patient`, `update_patient`, `archive_patient` per `contracts/` and `data-model.md`
- [x] T006 [P] Add CRUD verification SQL in `backend/tests/patient_management_crud.sql` (register, search branch/org scope, name contains, phone prefix, national ID block, duplicate advisory, stale update, archive, cross-branch edit)
- [x] T007 [P] Add RLS isolation SQL in `backend/tests/patient_management_rls.sql` (cross-org denial for patient reads and RPCs)
- [x] T008 [P] Add test runner `backend/tests/run_patient_management_tests.sh`
- [x] T009 [P] Extend `PermissionKeys` with `patientsCreate`, `patientsEdit`, `patientsDelete` in `frontend/lib/features/auth/domain/permission_keys.dart`
- [x] T010 [P] Add `canViewPatients`, `canCreatePatients`, `canEditPatients`, `canDeletePatients` helpers in `frontend/lib/core/auth/permission_service.dart`
- [x] T011 Implement `PatientRepository` RPC wrappers in `frontend/lib/features/patients/data/patient_repository.dart` (`searchPatients`, `getPatient`, `checkDuplicates`, `createPatient`, `updatePatient`, `archivePatient`)
- [x] T012 [P] Implement `PatientListScopeNotifier` (default `thisBranch` on sign-in; session persistence until sign-out) in `frontend/lib/features/patients/presentation/providers/patient_list_scope_provider.dart`
- [x] T013 Register patient routes with `patients.view` / create / edit / delete guards in `frontend/lib/app/router.dart`

**Checkpoint**: `supabase migration up` succeeds; `run_patient_management_tests.sh` passes; patient routes registered (pages may 404 until story phases)

---

## Phase 3: User Story 1 - Register a New Patient (Priority: P1) 🎯 MVP

**Goal**: Register a patient at the active branch with validation, duplicate advisory, and national ID hard block

**Independent Test**: Sign in with `patients.create` → `/patients/new` → submit valid registration → patient retrievable via `get_patient`; duplicate phone shows warning then proceed; duplicate national ID blocked

### Tests for User Story 1

- [x] T014 [P] [US1] Add create/duplicate/national-id RPC tests in `backend/tests/patient_management_crud.sql`
- [x] T015 [P] [US1] Add unit tests for `PatientRepository.createPatient` and `checkDuplicates` in `frontend/test/unit/patients/patient_repository_create_test.dart`
- [x] T016 [P] [US1] Add widget tests for registration form states in `frontend/test/widget/patients/patient_registration_page_test.dart`

### Implementation for User Story 1

- [x] T017 [US1] Implement `PatientRepository.createPatient` and `checkPatientDuplicates` with `DUPLICATE_WARNING` and `NATIONAL_ID_EXISTS` handling per `contracts/patient-mutations.md` in `frontend/lib/features/patients/data/patient_repository.dart`
- [x] T018 [US1] Implement `DuplicateCandidatesDialog` in `frontend/lib/features/patients/presentation/widgets/duplicate_candidates_dialog.dart`
- [x] T019 [US1] Implement `PatientRegistrationPage` (validation, duplicate flow, permission denied) in `frontend/lib/features/patients/presentation/pages/patient_registration_page.dart`
- [x] T020 [US1] Gate `/patients/new` route to `patients.create` in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 1–3; acceptance criteria 1–2, 7–8

---

## Phase 4: User Story 2 - Find and List Patients (Priority: P1)

**Goal**: Paginated patient list with scope toggle (this branch / all branches), unified search (name contains min 3, phone prefix min 2), and empty states

**Independent Test**: Seed patients at two branches → default list shows active branch only → toggle all branches → search by name and phone → archived patients excluded

### Tests for User Story 2

- [x] T021 [P] [US2] Add `search_patients` scope and min-length tests in `backend/tests/patient_management_crud.sql`
- [x] T022 [P] [US2] Add unit tests for `PatientRepository.searchPatients` in `frontend/test/unit/patients/patient_repository_search_test.dart`
- [x] T023 [P] [US2] Add widget tests for list scope toggle and search in `frontend/test/widget/patients/patient_list_page_test.dart`

### Implementation for User Story 2

- [x] T024 [US2] Implement `PatientRepository.searchPatients` with scope `branch` | `organization` per `contracts/patient-list-search.md` in `frontend/lib/features/patients/data/patient_repository.dart`
- [x] T025 [US2] Implement `PatientScopeToggle` in `frontend/lib/features/patients/presentation/widgets/patient_scope_toggle.dart`
- [x] T026 [US2] Implement `PatientSearchField` (debounce, min-length guidance, digit vs name detection) in `frontend/lib/features/patients/presentation/widgets/patient_search_field.dart`
- [x] T027 [US2] Implement `PatientListPage` (pagination, branch column when org scope, register FAB) in `frontend/lib/features/patients/presentation/pages/patient_list_page.dart`
- [x] T028 [US2] Wire `PatientListPage` to `PatientListScopeNotifier` and active branch from `frontend/lib/shared/providers/auth_session_provider.dart`
- [x] T029 [US2] Gate `/patients` route to `patients.view` in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 4–5, 12; acceptance criteria 3–4

---

## Phase 5: User Story 3 - View Patient Profile (Priority: P1)

**Goal**: Patient detail with profile fields, registering branch, audit summary, and visits placeholder (no visit data)

**Independent Test**: Open patient from list → all profile fields visible → medical history shows notes + visits placeholder only; archived patient denied

### Tests for User Story 3

- [x] T030 [P] [US3] Add `get_patient` and archived-denial tests in `backend/tests/patient_management_crud.sql`
- [x] T031 [P] [US3] Add unit tests for `PatientRepository.getPatient` in `frontend/test/unit/patients/patient_repository_get_test.dart`
- [x] T032 [P] [US3] Add widget tests for detail and visits placeholder in `frontend/test/widget/patients/patient_detail_page_test.dart`

### Implementation for User Story 3

- [x] T033 [US3] Implement `PatientRepository.getPatient` in `frontend/lib/features/patients/data/patient_repository.dart`
- [x] T034 [US3] Implement `PatientVisitsPlaceholder` in `frontend/lib/features/patients/presentation/widgets/patient_visits_placeholder.dart`
- [x] T035 [US3] Implement `PatientDetailPage` (loading, loaded, archived unavailable, permission denied) in `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`
- [x] T036 [US3] Add navigation from `PatientListPage` row tap to `/patients/:id` in `frontend/lib/features/patients/presentation/pages/patient_list_page.dart`

**Checkpoint**: Spec test case 5; acceptance criteria 5

---

## Phase 6: User Story 4 - Update Patient Information (Priority: P1)

**Goal**: Edit patient profile org-wide with duplicate advisory on identifier change, national ID conflict rejection, and optimistic stale-data handling

**Independent Test**: Edit patient registered at another branch → save succeeds → second session stale save rejected until reload

### Tests for User Story 4

- [x] T037 [P] [US4] Add `update_patient` stale conflict and cross-branch edit tests in `backend/tests/patient_management_crud.sql`
- [x] T038 [P] [US4] Add unit tests for `PatientRepository.updatePatient` in `frontend/test/unit/patients/patient_repository_update_test.dart`
- [x] T039 [P] [US4] Add widget tests for edit form and stale banner in `frontend/test/widget/patients/patient_edit_page_test.dart`

### Implementation for User Story 4

- [x] T040 [US4] Implement `PatientRepository.updatePatient` with `p_expected_updated_at` and `STALE_PATIENT` handling in `frontend/lib/features/patients/data/patient_repository.dart`
- [x] T041 [US4] Implement `PatientEditPage` (duplicate dialog reuse, stale reload banner) in `frontend/lib/features/patients/presentation/pages/patient_edit_page.dart`
- [x] T042 [US4] Add **Edit** action on `PatientDetailPage` gated by `patients.edit` in `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`
- [x] T043 [US4] Gate `/patients/:id/edit` route to `patients.edit` in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 6–8; acceptance criteria 6–7

---

## Phase 7: User Story 5 - Archive a Patient (Priority: P2)

**Goal**: Archive patient with confirmation; removed from list/search; no restore UI

**Independent Test**: Archive patient from detail → absent from list and search → detail unavailable in normal flow

### Tests for User Story 5

- [x] T044 [P] [US5] Add `archive_patient` tests in `backend/tests/patient_management_crud.sql`
- [x] T045 [P] [US5] Add unit tests for `PatientRepository.archivePatient` in `frontend/test/unit/patients/patient_repository_archive_test.dart`
- [x] T046 [P] [US5] Add widget tests for archive confirm dialog in `frontend/test/widget/patients/patient_archive_dialog_test.dart`

### Implementation for User Story 5

- [x] T047 [US5] Implement `PatientRepository.archivePatient` in `frontend/lib/features/patients/data/patient_repository.dart`
- [x] T048 [US5] Implement archive confirmation dialog in `frontend/lib/features/patients/presentation/widgets/patient_archive_dialog.dart`
- [x] T049 [US5] Add **Archive** action on `PatientDetailPage` gated by `patients.delete` in `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`

**Checkpoint**: Spec test case 9; acceptance criteria 9–10

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Shell navigation, end-to-end acceptance, quickstart validation, regression

- [ ] T050 Add **Patients** navigation entry on `AuthShellPage` gated by `patients.view` in `frontend/lib/features/auth/presentation/pages/auth_shell_page.dart`
- [ ] T051 [P] Add integration acceptance test for spec test cases 1–13 in `frontend/test/integration/patients/patient_management_acceptance_test.dart`
- [ ] T052 [P] Add `lab_staff` view-only widget test in `frontend/test/widget/patients/patient_permission_guards_test.dart`
- [ ] T053 Run `quickstart.md` verification and document any operator notes in `specs/004-patient-management/quickstart.md`
- [ ] T054 [P] Regression smoke: settings admin and branch switcher unchanged (`frontend/test/integration/settings/org_branch_management_acceptance_test.dart` or targeted subset)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup + V1-1/V1-2 complete — **blocks all user stories**
- **User Stories (Phases 3–7)**: Depend on Foundational
- **Polish (Phase 8)**: Depends on Phases 3–7 (minimum Phases 3–6 for meaningful E2E)

### User Story Dependencies

| Story | Priority | Depends on             | Notes                                     |
| ----- | -------- | ---------------------- | ----------------------------------------- |
| US1   | P1       | Foundational           | MVP — registration; route `/patients/new` |
| US2   | P1       | Foundational           | List/search; primary navigation hub       |
| US3   | P1       | Foundational, US2 (UI) | Detail reached from list                  |
| US4   | P1       | Foundational, US3 (UI) | Edit from detail                          |
| US5   | P2       | Foundational, US3 (UI) | Archive from detail                       |

### Recommended execution order (single developer)

1. Phase 1 → Phase 2
2. US1 (**MVP checkpoint** — register via `/patients/new`)
3. US2 → US3 → US4 → US5
4. Phase 8

### Parallel Opportunities

- Phase 1: T002, T003, T004 in parallel
- Phase 2: T006–T012 in parallel after T005
- Per story: all `[P]` test tasks before implementation tasks in that story
- US4 backend tests (T037) can run while US2 UI (T025–T027) in progress (different files)

### Parallel Example: Foundational

```bash
# Sequential first:
T005 migration

# Then parallel:
T006 patient_management_crud.sql
T007 patient_management_rls.sql
T009 permission_keys.dart
T010 permission_service.dart
T012 patient_list_scope_provider.dart
```

### Parallel Example: User Story 2

```bash
T021 search_patients SQL tests
T022 patient_repository_search_test.dart
T025 PatientScopeToggle
T026 PatientSearchField
T027 PatientListPage
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1 and Phase 2
2. Complete US1 (patient registration)
3. **STOP and VALIDATE**: quickstart §3 register flow; national ID block; duplicate warning

### Incremental delivery

1. **Foundation**: Phase 1 + Phase 2
2. **MVP**: + US1 (register)
3. **Discovery**: + US2 (list/search)
4. **Profile**: + US3 (detail)
5. **Maintenance**: + US4 (edit)
6. **Hygiene**: + US5 (archive)
7. **Polish**: Phase 8 (shell nav + acceptance)

### Parallel team strategy

- **Developer A**: Phase 2 migration + backend tests (T005–T008)
- **Developer B**: Phase 2 Flutter scaffold + US1 (T009–T020)
- After Foundational: **C** → US2, **D** → US3–US4, **E** → US5 + Phase 8

---

## Notes

- Builds on `backend/supabase/migrations/*auth_rbac*` and `20260522100000_org_branch_management.sql` — do not break bootstrap or settings RPCs
- `organization_id` on `patients` is set at create from registering branch (research Decision 5)
- Org-wide edit/archive; create only at active branch in JWT `branch_ids`
- Scope toggle resets to **this branch only** each sign-in (not persisted across sessions)
- No restore UI for archived patients; no appointment/visit/billing schemas in this feature
- Preserve constitution: RPC/RLS authority in PostgreSQL; Flutter permission cache is UX-only
