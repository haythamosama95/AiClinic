---

description: "Task list for Shift Management (V1-7) feature implementation"
---

# Tasks: Shift Management (V1-7)

**Input**: Design documents from `/specs/008-shift-management/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/shift-mutations.md, contracts/shift-queries.md, quickstart.md

**Tests**: INCLUDED. This feature is constitution-sensitive (Principle III backend authority, Principle IV defense-in-depth, audit, branch isolation, overlap validation) — backend SQL tests for RPC validation, RLS, and concurrency are mandatory per FR-017; Flutter widget/integration tests cover acceptance scenarios.

**Organization**: Tasks are grouped by user story (US1..US4) per spec.md priorities.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story label (US1..US4)
- Exact file paths included

## Path Conventions

- Backend: `backend/supabase/migrations/`, `backend/tests/`
- Frontend: `frontend/lib/features/shifts/`, `frontend/test/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffolding for the new shifts feature module.

- [X] T001 Create directory skeleton `frontend/lib/features/shifts/{data,domain,presentation/{pages,providers,widgets}}` and `frontend/test/{unit,widget,integration}/shifts/`
- [X] T002 [P] Create empty test harness file `backend/tests/run_shift_management_tests.sh` (executable; orchestrates `shift_management_crud.sql`, `shift_management_rls.sql`, `shift_management_concurrency.sql`)
- [X] T003 [P] Verify `calendar_view: 2.0.0` is present in `frontend/pubspec.yaml` (already used by appointments); run `flutter pub get` if lockfile stale

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema, helpers, RLS, read-path RPCs, and shared frontend wiring that EVERY user story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Backend foundation

- [X] T004 Create migration `backend/supabase/migrations/20260606180000_shift_management.sql` with tables `shifts` and `shift_assignments`, all CHECK constraints (`end_time > start_time`, notes length ≤ 500), indexes, and standard audit columns per `specs/008-shift-management/data-model.md`
- [X] T005 In the same migration, add RLS policies: branch-scoped SELECT on `shifts`/`shift_assignments`; deny all direct INSERT/UPDATE/DELETE; explicit `REVOKE INSERT, UPDATE, DELETE ON public.shifts, public.shift_assignments FROM PUBLIC, authenticated, anon`
- [X] T006 [P] In the same migration, add PL/pgSQL helpers in `auth_internal`: `get_org_today`, `assert_shift_branch_scope`, `assert_shifts_manage`, `assert_shift_mutable`, `assert_shift_staff_eligible`, `assert_no_staff_shift_overlap` per `specs/008-shift-management/research.md` D3–D4
- [X] T007 [P] In the same migration, add read-path RPCs `list_shifts` and `get_shift_detail` per `specs/008-shift-management/contracts/shift-queries.md` (branch assignment scope; no `shifts.manage` required; derived status; `is_read_only` flag)

### Frontend foundation

- [X] T008 [P] Extend `frontend/lib/core/auth/permission_service.dart` with `canManageShifts()` (checks `shifts.manage`) and `canViewShifts()` (branch assignment sufficient)
- [X] T009 [P] Add domain types under `frontend/lib/features/shifts/domain/`: `shift_status.dart`, `shift_calendar_mode.dart`, `shift_list_item.dart`, `shift_detail.dart`, `shift_assignment.dart`, `shift_overlap_conflict.dart`
- [X] T010 [P] Add `frontend/lib/features/shifts/data/shift_repository.dart` skeleton with `listShifts` and `getShiftDetail` RPC wrappers (backend-first reads per FR-022)
- [X] T011 [P] Register routes in `frontend/lib/app/router.dart` and `frontend/lib/app/app_routes.dart`: `/shifts/calendar`, `/shifts/new`, `/shifts/:id`; add **Shift** nav item to app shell (view gated by branch assignment; create/edit gated by `canManageShifts`)

### Foundational backend tests

- [X] T012 [P] Create `backend/tests/shift_management_rls.sql` covering: cross-branch read denial on shifts/assignments; cross-org denial; receptionist can `list_shifts`/`get_shift_detail` without `shifts.manage`; receptionist mutation RPC denial; administrator mutation allowed

**Checkpoint**: Foundation ready — user story implementation can now begin in parallel.

---

## Phase 3: User Story 1 - Create a Shift (Priority: P1) 🎯 MVP

**Goal**: An owner or administrator with `shifts.manage` can create a shift (with optional staff) for today or a future date at the active branch, with overlap and eligibility validation.

**Independent Test**: Per spec US1 — sign in with `shifts.manage`, create an incomplete shift for a future date, verify unassigned state; assign staff and confirm active state; verify adjacent shifts allowed and overlapping shifts rejected.

### Tests for User Story 1

- [X] T013 [P] [US1] In `backend/tests/shift_management_crud.sql`, add scenarios: create incomplete shift (zero staff); create active shift with staff; reject `end_time <= start_time`; reject ineligible staff; reject overlap with conflict payload; allow adjacent touching shifts; reject past `shift_date`; allow times outside branch working hours; audit `shift.create`
- [X] T014 [P] [US1] Add `frontend/test/integration/shifts/create_shift_test.dart` covering US1 acceptance scenarios 1, 2, 3, 4, 5, 7, 8, 9

### Implementation for User Story 1

- [X] T015 [P] [US1] Add `create_shift` RPC in `backend/supabase/migrations/20260606180000_shift_management.sql` per `specs/008-shift-management/contracts/shift-mutations.md` (atomic shift + optional assignments; overlap only when staff provided; audit log)
- [X] T016 [P] [US1] Implement `ShiftRepository.createShift` in `frontend/lib/features/shifts/data/shift_repository.dart`
- [X] T017 [P] [US1] Implement `frontend/lib/features/shifts/presentation/widgets/shift_form_fields.dart` (date picker min=today org TZ, start/end time, notes with 500-char guard)
- [X] T018 [P] [US1] Implement `frontend/lib/features/shifts/presentation/widgets/shift_staff_multi_select.dart` reusing V1-2 staff list filtered to active branch-assigned staff
- [X] T019 [US1] Implement `frontend/lib/features/shifts/presentation/widgets/shift_conflict_banner.dart` parsing `shift_overlap` payload (staff name + conflicting time range)
- [X] T020 [US1] Implement `frontend/lib/features/shifts/presentation/pages/shift_create_page.dart` wiring form, staff multi-select, conflict banner, and success navigation to shift detail or calendar

**Checkpoint**: User Story 1 is fully functional — managers can create shifts with validation feedback.

---

## Phase 4: User Story 2 - View Branch Shift Calendar (Priority: P1)

**Goal**: Any branch-assigned staff member can view the branch shift calendar in weekly or monthly mode; users without `shifts.manage` see read-only UI.

**Independent Test**: Per spec US2 — sign in as receptionist, open shift calendar, verify branch-scoped shifts read-only; sign in as administrator and confirm same data with create actions available.

### Tests for User Story 2

- [X] T021 [P] [US2] In `backend/tests/shift_management_crud.sql`, add scenarios: `list_shifts` date-range filtering; cancelled shifts excluded; incomplete shifts return `is_unassigned=true`; `get_shift_detail` returns `is_read_only` correctly for non-manager and past-date shifts
- [X] T022 [P] [US2] Add `frontend/test/integration/shifts/shift_calendar_test.dart` covering US2 acceptance scenarios 1, 2, 3, 4, 5, 6, 7

### Implementation for User Story 2

- [X] T023 [P] [US2] Implement `frontend/lib/features/shifts/presentation/providers/shift_calendar_provider.dart` (week/month bounds, backend-first fetch, active-branch reload on `authSessionProvider` change per edge case)
- [X] T024 [P] [US2] Implement `frontend/lib/features/shifts/presentation/widgets/shift_event_tile.dart` and `shift_status_badge.dart` (time range, assignee summary, Unassigned indicator)
- [X] T025 [US2] Implement `frontend/lib/features/shifts/presentation/pages/shift_calendar_page.dart` with `WeekView<ShiftListItem>` (period navigation, empty/error/permission-denied states, create button gated by `canManageShifts`)
- [X] T026 [US2] Extend `shift_calendar_page.dart` with `MonthView<ShiftListItem>` toggle and `frontend/lib/features/shifts/presentation/widgets/shift_month_day_sheet.dart` for day-detail popover when multiple shifts on a day
- [X] T027 [US2] Implement `frontend/lib/features/shifts/presentation/pages/shift_detail_page.dart` read-only baseline (loading, active, incomplete, permission-denied, past-date read-only banner; no mutation controls when `is_read_only`)

**Checkpoint**: User Stories 1+2 deliver the MVP — managers create shifts; all branch staff view the calendar.

---

## Phase 5: User Story 3 - Manage Staff Assignments on an Existing Shift (Priority: P2)

**Goal**: An owner or administrator can add or remove staff assignments on an existing future/today shift without recreating it; removing the last assignee transitions to incomplete.

**Independent Test**: Per spec US3 — create shift with one staff, add second, remove one, verify overlap rules on add, remove last assignee and confirm incomplete/unassigned state.

### Tests for User Story 3

- [X] T028 [P] [US3] In `backend/tests/shift_management_crud.sql`, add scenarios: add eligible staff; reject duplicate assignment; reject overlap on add; remove one of many; remove last assignee → incomplete (not blocked); reject assignment on cancelled shift; reject assignment on past-date shift; audit `shift.assignment.add`/`shift.assignment.remove`
- [X] T029 [P] [US3] Add `frontend/test/integration/shifts/shift_assignment_test.dart` covering US3 acceptance scenarios 1, 2, 3, 4, 5

### Implementation for User Story 3

- [X] T030 [P] [US3] Add `modify_shift_assignments` RPC in `backend/supabase/migrations/20260606180000_shift_management.sql` per `specs/008-shift-management/contracts/shift-mutations.md` (atomic add/remove arrays; stale check; overlap on add only)
- [X] T031 [P] [US3] Implement `ShiftRepository.modifyAssignments` in `frontend/lib/features/shifts/data/shift_repository.dart`
- [X] T032 [US3] Implement `frontend/lib/features/shifts/presentation/providers/shift_detail_notifier.dart` with optimistic-concurrency handling (`stale_shift` → refresh prompt)
- [X] T033 [US3] Extend `frontend/lib/features/shifts/presentation/pages/shift_detail_page.dart` with assignment panel: add via `shift_staff_multi_select`, per-assignee remove with confirm, conflict banner on overlap, incomplete/Unassigned state after last removal

**Checkpoint**: User Story 3 is independently functional — assignment changes without recreating shifts.

---

## Phase 6: User Story 4 - Edit or Cancel an Existing Shift (Priority: P2)

**Goal**: An owner or administrator can update shift date/time/notes or soft-cancel a shift; cancelled and past-date shifts are immutable.

**Independent Test**: Per spec US4 — edit end time, verify overlap rejection preserves prior values, cancel shift and confirm removal from default calendar, verify past-date edit/cancel rejected.

### Tests for User Story 4

- [ ] T034 [P] [US4] In `backend/tests/shift_management_crud.sql`, add scenarios: update date/time/notes; reject update causing overlap; reject update moving `shift_date` to past; cancel future shift (soft-delete); reject edit/cancel on cancelled shift; reject edit/cancel on past-date shift; audit `shift.update`/`shift.cancel`
- [ ] T035 [P] [US4] Create `backend/tests/shift_management_concurrency.sql` simulating concurrent `update_shift` with mismatched `p_expected_updated_at` — second txn rejected with `stale_shift`
- [ ] T036 [P] [US4] Add `frontend/test/integration/shifts/shift_edit_cancel_test.dart` covering US4 acceptance scenarios 1, 2, 3, 4, 5, 6

### Implementation for User Story 4

- [ ] T037 [P] [US4] Add `update_shift` and `cancel_shift` RPCs in `backend/supabase/migrations/20260606180000_shift_management.sql` per `specs/008-shift-management/contracts/shift-mutations.md`
- [ ] T038 [P] [US4] Implement `ShiftRepository.updateShift` and `cancelShift` in `frontend/lib/features/shifts/data/shift_repository.dart`
- [ ] T039 [US4] Extend `shift_detail_page.dart` with edit mode reusing `shift_form_fields.dart` (date/time/notes update; overlap and past-date error display)
- [ ] T040 [US4] Implement `frontend/lib/features/shifts/presentation/widgets/cancel_shift_dialog.dart` with confirmation; on success navigate back to calendar excluding cancelled shift
- [ ] T041 [US4] Wire `stale_shift` refresh UX across edit, assignment, and cancel flows in `shift_detail_notifier.dart`

**Checkpoint**: All four user stories are independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Cross-story hardening, performance, and operator verification.

- [ ] T042 [P] Ensure `shift_calendar_provider.dart` clears cached items and refetches on active-branch switch (no cross-branch data bleed)
- [ ] T043 [P] Add connection-error and validation-failure states across `shift_create_page.dart` and `shift_detail_page.dart` without optimistic persistence (NFR-005)
- [ ] T044 [P] Add unit tests in `frontend/test/unit/shifts/shift_repository_test.dart` and `frontend/test/widget/shifts/shift_conflict_banner_test.dart` for overlap payload parsing and read-only gating
- [ ] T045 Run `backend/tests/run_shift_management_tests.sh` and fix any failures
- [ ] T046 Execute `specs/008-shift-management/quickstart.md` operator walkthrough end-to-end and record pass/fail per step
- [ ] T047 Review constitution compliance: overlap/past-date/permission rules enforced only in PostgreSQL; no direct table writes; audit log on all mutations; no AI dependency

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — **BLOCKS all user stories**
- **User Stories (Phase 3–6)**: All depend on Foundational completion
  - US1 and US2 are both P1 and can proceed in parallel after Phase 2 (US2 read-path RPCs are in Foundational)
  - US3 depends on US1 (`create_shift` exists) and US2 (`shift_detail_page` baseline) for practical testing
  - US4 depends on US1 (shifts exist to edit) and US2 (detail page shell); extends US3 assignment panel without breaking it
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

| Story | Priority | Depends on                | Independently testable after |
| ----- | -------- | ------------------------- | ---------------------------- |
| US1   | P1       | Phase 2                   | Phase 3 checkpoint           |
| US2   | P1       | Phase 2                   | Phase 4 checkpoint           |
| US3   | P2       | US1 + US2 detail baseline | Phase 5 checkpoint           |
| US4   | P2       | US1 + US2 detail baseline | Phase 6 checkpoint           |

### Within Each User Story

- Backend SQL tests SHOULD be written before or alongside RPC implementation
- Domain types and repository methods before pages/widgets
- Core RPC before Flutter mutation UI
- Story checkpoint before moving to next priority

### Parallel Opportunities

- Phase 1: T002, T003 in parallel
- Phase 2: T006, T007, T008, T009, T010, T011, T012 in parallel after T004–T005 land
- US1: T013, T014, T015, T016, T017, T018 in parallel; then T019–T020 sequential
- US2: T021, T022, T023, T024 in parallel; then T025–T027 sequential
- US3: T028, T029, T030, T031 in parallel; then T032–T033 sequential
- US4: T034, T035, T036, T037, T038 in parallel; then T039–T041 sequential
- Polish: T042, T043, T044 in parallel

---

## Parallel Example: User Story 1

```bash
# Backend + frontend can proceed simultaneously once Foundational is done:
Task: "Add create_shift RPC in backend/supabase/migrations/20260606180000_shift_management.sql"
Task: "Implement ShiftRepository.createShift in frontend/lib/features/shifts/data/shift_repository.dart"
Task: "Implement shift_form_fields.dart and shift_staff_multi_select.dart widgets"

# Tests in parallel:
Task: "Add create scenarios in backend/tests/shift_management_crud.sql"
Task: "Add frontend/test/integration/shifts/create_shift_test.dart"
```

---

## Parallel Example: User Story 2

```bash
# Calendar scaffolding in parallel:
Task: "Implement shift_calendar_provider.dart"
Task: "Implement shift_event_tile.dart and shift_status_badge.dart"
Task: "Add list/detail scenarios in backend/tests/shift_management_crud.sql"

# Then assemble shift_calendar_page.dart (depends on provider + tiles)
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1 (Setup)
2. Complete Phase 2 (Foundational) — schema + RLS + read RPCs + frontend wiring
3. Complete Phase 3 (US1) — create shifts end-to-end
4. Complete Phase 4 (US2) — calendar views + read-only access for all branch staff
5. **Validate**: administrator can plan coverage; receptionist can view who is on duty. This is the minimum operationally viable shift slice.

### Incremental Delivery

1. MVP (US1+US2) → demo to clinic staff
2. Add Phase 5 (US3) → daily assignment adjustments without recreating shifts
3. Add Phase 6 (US4) → corrections and cancellations
4. Phase 7 polish → operator quickstart sign-off

### Parallel Team Strategy

After Foundational completes:

- **Developer A**: US1 (create flow + backend create RPC)
- **Developer B**: US2 (calendar + read-only detail)
- Then either developer can take US3 (assignments) or US4 (edit/cancel) once detail page baseline exists

---

## Notes

- `shifts.manage` permission seed already exists in V1-1 (`backend/supabase/migrations/20260516100400_auth_rbac_seed.sql`) — no new permission keys in this feature
- All mutation RPCs MUST write `audit_log` rows per FR-015; reviewer SHOULD spot-check payload shape during code review
- Overlap formula MUST use strict intersection: `existing_start < new_end AND existing_end > new_start` (adjacent touching allowed)
- Past-date gate MUST use organization timezone via `get_org_today` — never client-only
- Backend-first fetch (FR-022) is mandatory for calendar and shift detail before rendering actionable controls
- Shift times MUST NOT be validated against branch `working_schedule`
- Stop at any checkpoint to validate the corresponding user story in isolation
- Preserve layer boundaries: no domain authority in Flutter; no AI in V1-7
