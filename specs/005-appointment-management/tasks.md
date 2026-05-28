# Tasks: Appointment Management

**Input**: Design documents from `/specs/005-appointment-management/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md; **V1-3** (`specs/004-patient-management`), **V1-2** (`specs/003-org-branch-management`), **V1-1** (`specs/002-auth-rbac`) complete

**Tests**: Included — spec defines acceptance criteria and test cases 1–14; constitution requires RLS/RPC verification (`backend/tests/`).

**Organization**: Tasks grouped by user story. Labels map to `spec.md` user stories (US1–US7).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in same phase)
- **[Story]**: User story label for traceability
- Include exact file paths in descriptions

## Path Conventions

- **Flutter**: `frontend/lib/`, `frontend/test/`
- **Supabase**: `backend/supabase/migrations/`, `backend/tests/`
- **Contracts**: `specs/005-appointment-management/contracts/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Appointments feature module layout, routes, and test workspace before migration/UI work

- [X] T001 Create appointments feature directories in `frontend/lib/features/appointments/data/`, `frontend/lib/features/appointments/domain/`, `frontend/lib/features/appointments/presentation/pages/`, `frontend/lib/features/appointments/presentation/providers/`, and `frontend/lib/features/appointments/presentation/widgets/`
- [X] T002 [P] Create test directories `frontend/test/unit/appointments/`, `frontend/test/widget/appointments/`, and `frontend/test/integration/appointments/`
- [X] T003 [P] Add appointment route constants in `frontend/lib/app/app_routes.dart` (`/appointments`, `/appointments/book`, `/appointments/walk-in`, `/appointments/queue`, `/appointments/schedule/:doctorId` plus path builders)
- [X] T004 [P] Add domain model stubs per `data-model.md` in `frontend/lib/features/appointments/domain/appointment_list_item.dart`, `appointment_detail.dart`, `appointment_type.dart`, and `appointment_status.dart`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: `appointments` migration, all appointment RPCs, settings helpers, backend verification, repository scaffold, permission keys, route guards — **blocks all user stories**

**⚠️ CRITICAL**: No user story phase work until this phase is complete

- [X] T005 Add migration `backend/supabase/migrations/20260526140000_appointment_management.sql` with `appointment_type` and `appointment_status` enums, `appointments` table, indexes, branch RLS (SELECT scoped; INSERT/UPDATE/DELETE denied), `auth_internal` helpers (overlap check, walk-in gap finder, duration resolver, doctor/patient asserts), and RPCs `get_appointment_settings`, `set_appointment_default_duration`, `create_appointment`, `reschedule_appointment`, `cancel_appointment`, `update_appointment_status`, `list_appointments` per `contracts/` and `data-model.md`
- [X] T006 [P] Add CRUD verification SQL in `backend/tests/appointment_management_crud.sql` (planned create, walk-in auto-slot, conflict, status transitions, reschedule, cancel, no-show, settings default, `NO_SLOT_AVAILABLE`)
- [X] T007 [P] Add RLS isolation SQL in `backend/tests/appointment_management_rls.sql` (cross-org and cross-branch denial)
- [X] T008 [P] Add test runner `backend/tests/run_appointment_management_tests.sh`
- [X] T009 [P] Extend `PermissionKeys` with `appointmentsCreate` and `appointmentsCancel` in `frontend/lib/features/auth/domain/permission_keys.dart`
- [X] T010 [P] Add `canAccessAppointments`, `canCreateAppointments`, and `canCancelAppointments` helpers in `frontend/lib/core/auth/permission_service.dart`
- [X] T011 Implement `AppointmentRepository` RPC wrappers in `frontend/lib/features/appointments/data/appointment_repository.dart` (`getSettings`, `createAppointment`, `listAppointments`, `updateStatus`, `reschedule`, `cancel`)
- [X] T012 [P] Add `DurationField` widget (minutes input, end-time preview) in `frontend/lib/features/appointments/presentation/widgets/duration_field.dart`
- [X] T013 Register appointment routes with `appointments.create` / `appointments.cancel` view guards in `frontend/lib/app/router.dart`
- [X] T014 [P] Add default appointment duration field on `OrganizationSettingsPage` calling `set_appointment_default_duration` in `frontend/lib/features/settings/presentation/pages/organization_settings_page.dart`

**Checkpoint**: `supabase migration up` succeeds; `run_appointment_management_tests.sh` passes; appointment routes registered (pages may 404 until story phases)

---

## Phase 3: User Story 1 - Book a Planned Appointment (Priority: P1) 🎯 MVP

**Goal**: Book a planned appointment at the active branch with settings-based duration pre-fill, custom duration override, and conflict rejection

**Independent Test**: Sign in with `appointments.create` → book planned slot → appointment appears on calendar/queue when dated today; overlapping slot rejected

### Tests for User Story 1

- [X] T015 [P] [US1] Add planned create and conflict RPC tests in `backend/tests/appointment_management_crud.sql`
- [X] T016 [P] [US1] Add unit tests for `AppointmentRepository.createAppointment` (planned) in `frontend/test/unit/appointments/appointment_repository_create_planned_test.dart`
- [X] T017 [P] [US1] Add widget tests for booking form duration pre-fill and conflict error in `frontend/test/widget/appointments/appointment_booking_page_test.dart`

### Implementation for User Story 1

- [X] T018 [US1] Implement `AppointmentRepository.getAppointmentSettings` and `createAppointment` (`planned`) with `SCHEDULE_CONFLICT` handling per `contracts/appointment-mutations.md` in `frontend/lib/features/appointments/data/appointment_repository.dart`
- [X] T019 [US1] Implement `PatientPicker` reuse from `frontend/lib/features/patients/` and doctor selector widget in `frontend/lib/features/appointments/presentation/widgets/doctor_selector.dart`
- [X] T020 [US1] Implement `AppointmentBookingPage` (start time, duration pre-fill, custom override, validation, permission denied) in `frontend/lib/features/appointments/presentation/pages/appointment_booking_page.dart`
- [X] T021 [US1] Implement `ConflictErrorBanner` in `frontend/lib/features/appointments/presentation/widgets/conflict_error_banner.dart`
- [X] T022 [US1] Gate `/appointments/book` route to `appointments.create` in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 1–2, 7; acceptance criteria 1–3

---

## Phase 4: User Story 2 - Register a Walk-In (Priority: P1)

**Goal**: Register walk-in with auto-assigned slot in gap, status `checked_in`, queue order by `start_time`

**Independent Test**: Register walk-in with confirmed slots on calendar → auto time in gap → `checked_in` → appears in queue at assigned time

### Tests for User Story 2

- [X] T023 [P] [US2] Add walk-in auto-slot and `NO_SLOT_AVAILABLE` tests in `backend/tests/appointment_management_crud.sql`
- [X] T024 [P] [US2] Add unit tests for `AppointmentRepository.createAppointment` (`walk_in`) in `frontend/test/unit/appointments/appointment_repository_create_walkin_test.dart`
- [X] T025 [P] [US2] Add widget tests for walk-in form in `frontend/test/widget/appointments/walk_in_registration_page_test.dart`

### Implementation for User Story 2

- [X] T026 [US2] Extend `AppointmentRepository.createAppointment` for `walk_in` (ignore client start; surface assigned times) in `frontend/lib/features/appointments/data/appointment_repository.dart`
- [X] T027 [US2] Implement `WalkInRegistrationPage` (duration pre-fill/override, assigned slot display, no check-in button) in `frontend/lib/features/appointments/presentation/pages/walk_in_registration_page.dart`
- [X] T028 [US2] Gate `/appointments/walk-in` route to `appointments.create` in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 3, 11; acceptance criteria 4

---

## Phase 5: User Story 3 - View Calendar and Doctor Schedule (Priority: P1)

**Goal**: Daily/weekly branch calendar and doctor-filtered schedule with status/type indicators

**Independent Test**: Seed appointments → calendar day/week views → doctor filter shows only that doctor's rows; cancelled/no-show visually distinct

### Tests for User Story 3

- [X] T029 [P] [US3] Add `list_appointments` range and doctor filter tests in `backend/tests/appointment_management_crud.sql`
- [X] T030 [P] [US3] Add unit tests for `AppointmentRepository.listAppointments` in `frontend/test/unit/appointments/appointment_repository_list_test.dart`
- [X] T031 [P] [US3] Add widget tests for calendar and schedule pages in `frontend/test/widget/appointments/appointment_calendar_page_test.dart`

### Implementation for User Story 3

- [X] T032 [US3] Implement `AppointmentRepository.listAppointments` per `contracts/appointment-queries.md` in `frontend/lib/features/appointments/data/appointment_repository.dart`
- [X] T033 [US3] Implement `AppointmentCalendarProvider` (day/week mode, active branch, org TZ date bounds) in `frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart`
- [X] T034 [US3] Implement `AppointmentCalendarPage` in `frontend/lib/features/appointments/presentation/pages/appointment_calendar_page.dart`
- [X] T035 [US3] Implement `DoctorSchedulePage` (doctor filter) in `frontend/lib/features/appointments/presentation/pages/doctor_schedule_page.dart`
- [X] T036 [US3] Gate `/appointments` and `/appointments/schedule/:doctorId` to appointment view access in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test case 10; acceptance criteria 9

---

## Phase 6: User Story 4 - Manage Today's Queue (Priority: P1)

**Goal**: Today's queue sorted by `start_time` with Realtime updates and manual refresh fallback

**Independent Test**: Open queue → sorted by time → second session status change updates view (or refresh shows change)

### Tests for User Story 4

- [ ] T037 [P] [US4] Add today-boundary `list_appointments` sort-order tests in `backend/tests/appointment_management_crud.sql`
- [ ] T038 [P] [US4] Add unit tests for `AppointmentQueueProvider` in `frontend/test/unit/appointments/appointment_queue_provider_test.dart`
- [ ] T039 [P] [US4] Add widget tests for queue live/degraded states in `frontend/test/widget/appointments/appointment_queue_page_test.dart`

### Implementation for User Story 4

- [ ] T040 [US4] Implement `AppointmentQueueProvider` with `list_appointments` today filter, `start_time` sort, Supabase Realtime subscription, and manual refresh in `frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart`
- [ ] T041 [US4] Implement `AppointmentQueuePage` (loading, empty, live connected, degraded banner) in `frontend/lib/features/appointments/presentation/pages/appointment_queue_page.dart`
- [ ] T042 [US4] Gate `/appointments/queue` route to appointment view access in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 8–9; acceptance criteria 5; SC-005, SC-008

---

## Phase 7: User Story 5 - Check In and Progress Appointment Status (Priority: P1)

**Goal**: Forward status transitions (`scheduled` → `checked_in` → `in_progress` → `completed`); reception may act on any doctor's appointment

**Independent Test**: Step planned appointment through full lifecycle; invalid skip rejected; reception completes another doctor's appointment

### Tests for User Story 5

- [ ] T043 [P] [US5] Add `update_appointment_status` transition matrix tests in `backend/tests/appointment_management_crud.sql`
- [ ] T044 [P] [US5] Add unit tests for `AppointmentRepository.updateAppointmentStatus` in `frontend/test/unit/appointments/appointment_repository_status_test.dart`
- [ ] T045 [P] [US5] Add widget tests for `AppointmentStatusActions` in `frontend/test/widget/appointments/appointment_status_actions_test.dart`

### Implementation for User Story 5

- [ ] T046 [US5] Implement `AppointmentRepository.updateAppointmentStatus` with `INVALID_TRANSITION` handling in `frontend/lib/features/appointments/data/appointment_repository.dart`
- [ ] T047 [US5] Implement `AppointmentStatusActions` (check-in hidden for walk-in at `checked_in`, start, complete) in `frontend/lib/features/appointments/presentation/widgets/appointment_status_actions.dart`
- [ ] T048 [US5] Wire status actions on `AppointmentQueuePage` and `AppointmentCalendarPage` in `frontend/lib/features/appointments/presentation/pages/appointment_queue_page.dart` and `appointment_calendar_page.dart`

**Checkpoint**: Spec test cases 4, 6; acceptance criteria 6–7

---

## Phase 8: User Story 6 - Reschedule a Planned Appointment (Priority: P2)

**Goal**: Reschedule `scheduled` planned appointments with conflict detection; reject wrong status

**Independent Test**: Reschedule to free slot succeeds; overlap rejected; cannot reschedule after check-in

### Tests for User Story 6

- [ ] T049 [P] [US6] Add `reschedule_appointment` tests in `backend/tests/appointment_management_crud.sql`
- [ ] T050 [P] [US6] Add unit tests for `AppointmentRepository.rescheduleAppointment` in `frontend/test/unit/appointments/appointment_repository_reschedule_test.dart`
- [ ] T051 [P] [US6] Add widget tests for reschedule flow in `frontend/test/widget/appointments/appointment_reschedule_dialog_test.dart`

### Implementation for User Story 6

- [ ] T052 [US6] Implement `AppointmentRepository.rescheduleAppointment` in `frontend/lib/features/appointments/data/appointment_repository.dart`
- [ ] T053 [US6] Implement `AppointmentRescheduleDialog` in `frontend/lib/features/appointments/presentation/widgets/appointment_reschedule_dialog.dart`
- [ ] T054 [US6] Add reschedule entry from calendar/queue for `scheduled` planned rows in `frontend/lib/features/appointments/presentation/widgets/appointment_status_actions.dart`

**Checkpoint**: Spec test case 12; acceptance criteria 11

---

## Phase 9: User Story 7 - Cancel or Mark No-Show (Priority: P2)

**Goal**: Cancel and no-show with confirmation; free slots for rebooking

**Independent Test**: Cancel scheduled appointment → slot reusable; no-show from `scheduled`/`checked_in`; completed cannot cancel

### Tests for User Story 7

- [ ] T055 [P] [US7] Add `cancel_appointment` and no-show tests in `backend/tests/appointment_management_crud.sql`
- [ ] T056 [P] [US7] Add unit tests for `AppointmentRepository.cancelAppointment` in `frontend/test/unit/appointments/appointment_repository_cancel_test.dart`
- [ ] T057 [P] [US7] Add widget tests for cancel confirm dialog in `frontend/test/widget/appointments/appointment_cancel_dialog_test.dart`

### Implementation for User Story 7

- [ ] T058 [US7] Implement `AppointmentRepository.cancelAppointment` and no-show via `updateAppointmentStatus` in `frontend/lib/features/appointments/data/appointment_repository.dart`
- [ ] T059 [US7] Implement `AppointmentCancelDialog` (cancel reason optional, no-show action) in `frontend/lib/features/appointments/presentation/widgets/appointment_cancel_dialog.dart`
- [ ] T060 [US7] Wire cancel/no-show on queue and calendar rows gated by `appointments.cancel` in `frontend/lib/features/appointments/presentation/widgets/appointment_status_actions.dart`

**Checkpoint**: Spec test cases 5–6; acceptance criteria 8

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Shell navigation, end-to-end acceptance, quickstart validation, regression

- [X] T061 Add **Appointments** navigation hub on `AuthShellPage` gated by `canAccessAppointments` in `frontend/lib/features/auth/presentation/pages/auth_shell_page.dart`
- [ ] T062 [P] Integration acceptance for spec test cases 1–14 is split across `frontend/test/integration/appointments/appointment_booking_us1_test.dart`, `appointments_phase1_setup_test.dart`, and `walk_in_registration_us2_test.dart`; extend or add coverage for remaining cases (calendar, queue, status transitions) when US3–US5 land
- [ ] T063 [P] Add permission guard widget tests (no appointment access without grants) in `frontend/test/widget/appointments/appointment_permission_guards_test.dart`
- [ ] T064 Run `specs/005-appointment-management/quickstart.md` verification and document operator notes
- [ ] T065 [P] Regression smoke: patients and settings flows unchanged (`frontend/test/integration/patients/patient_management_acceptance_test.dart` targeted subset)
- [ ] T066 [P] Verify `docs/architecture/12-roadmap-phases.md` V1-4 references remain accurate after implementation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup + V1-1/V1-2/V1-3 complete — **blocks all user stories**
- **User Stories (Phases 3–9)**: Depend on Foundational
- **Polish (Phase 10)**: Depends on Phases 3–9 (minimum Phases 3–7 for meaningful E2E)

### User Story Dependencies

| Story | Priority | Depends on             | Notes                                              |
| ----- | -------- | ---------------------- | -------------------------------------------------- |
| US1   | P1       | Foundational           | MVP — planned booking                              |
| US2   | P1       | Foundational           | Walk-in; shares `create_appointment` RPC           |
| US3   | P1       | Foundational           | Calendar/schedule; benefits from US1/US2 seed data |
| US4   | P1       | Foundational, US3 (UI) | Queue; reuses list + calendar navigation           |
| US5   | P1       | Foundational, US1/US2  | Status actions on queue/calendar surfaces          |
| US6   | P2       | Foundational, US1      | Reschedule `scheduled` planned only                |
| US7   | P2       | Foundational, US5 (UI) | Cancel/no-show on shared status action widget      |

### Recommended execution order (single developer)

1. Phase 1 → Phase 2
2. US1 (**MVP checkpoint** — planned booking)
3. US2 → US3 → US4 → US5
4. US6 → US7
5. Phase 10

### Parallel Opportunities

- Phase 1: T002, T003, T004 in parallel
- Phase 2: T006–T010, T012, T014 in parallel after T005
- Per story: all `[P]` test tasks before implementation tasks in that story
- US3 calendar (T032–T035) can parallel US2 walk-in UI (T026–T027) after Foundational if two developers

### Parallel Example: Foundational

```bash
# Sequential first:
T005 migration

# Then parallel:
T006 appointment_management_crud.sql
T007 appointment_management_rls.sql
T009 permission_keys.dart
T010 permission_service.dart
T012 duration_field.dart
T014 organization_settings_page.dart
```

### Parallel Example: User Story 1

```bash
T015 planned create SQL tests
T016 appointment_repository_create_planned_test.dart
T019 doctor_selector.dart
T021 conflict_error_banner.dart
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1 and Phase 2
2. Complete US1 (planned booking)
3. **STOP and VALIDATE**: quickstart §3 book flow; conflict rejection; duration pre-fill from settings

### Incremental delivery

1. **Foundation**: Phase 1 + Phase 2
2. **MVP**: + US1 (planned book)
3. **Walk-in**: + US2
4. **Visibility**: + US3 (calendar/schedule)
5. **Desk queue**: + US4 (queue + Realtime)
6. **Clinical flow**: + US5 (status)
7. **Changes**: + US6 (reschedule) + US7 (cancel/no-show)
8. **Polish**: Phase 10 (shell nav + acceptance)

### Parallel team strategy

- **Developer A**: Phase 2 migration + backend tests (T005–T008)
- **Developer B**: Phase 2 Flutter scaffold + US1 (T009–T022)
- After Foundational: **C** → US2–US3, **D** → US4–US5, **E** → US6–US7 + Phase 10

---

## Notes

- Builds on `patients` and org/branch migrations — do not break patient or settings RPCs
- Branch-scoped RLS on `appointments` (unlike org-wide `patients`)
- Walk-ins enter as `checked_in`; planned enter as `scheduled`; queue sorts by `start_time` only
- `queue_number` column unused in V1-4 (always NULL)
- No visit creation on `completed` (V1-5)
- Preserve constitution: RPC/RLS authority in PostgreSQL; Realtime is UX enhancement only
