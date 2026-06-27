---

description: "Task list for Simplified Slot Booking (011) feature implementation"
---

# Tasks: Simplified Slot Booking (011)

**Input**: Design documents from `/specs/011-simplified-slot-booking/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/simplified-booking-queries.md, contracts/simplified-booking-ui.md, quickstart.md

**Tests**: INCLUDED per plan.md Phase E and `quickstart.md` §4–5 — SQL tests for `get_simplified_booking_slots` and per-doctor overlap regression; Flutter unit tests for slot mapper and date clamp; widget tests for day strip, block grid, alternate-doctors dialog, summary card, and dual calendar entry points.

**Organization**: Tasks grouped by user story (US1–US5) per spec.md priorities. Foundational backend + domain layer blocks slot picker stories (US2–US4). US1 (settings UI) can proceed in parallel with foundational work after setup.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story label (US1–US5)
- Exact file paths included

## Path Conventions

- Flutter app: `frontend/lib/features/`, `frontend/test/`
- Supabase backend: `backend/supabase/migrations/`, `backend/tests/`
- Spec docs: `specs/011-simplified-slot-booking/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm baseline patterns and prepare test directories for new appointment widgets.

- [X] T001 Verify feature branch `ui/011-simplified-slot-booking` and create widget/unit test directories `frontend/test/widget/appointments/` and `frontend/test/unit/appointments/` if missing
- [X] T002 [P] Review `frontend/lib/features/appointments/presentation/widgets/appointment_booking_sheet.dart` for modal scrim, patient search, and doctor selector patterns to reuse in simplified flow
- [X] T003 [P] Review `frontend/lib/features/appointments/presentation/pages/appointment_calendar_page.dart` for header **Book Appointment** callback and slot-tap `_showBookingSheet` wiring

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Server-authoritative slot query RPC, per-doctor overlap restoration, and Flutter domain/repository layer for slot data.

**⚠️ CRITICAL**: US2, US3, and US4 cannot begin until this phase is complete.

- [X] T004 Restore per-doctor filter in `auth_internal.appointment_has_overlap` with migration comments documenting supersession of branch-wide uniqueness in `backend/supabase/migrations/20260627120000_simplified_slot_booking.sql`
- [X] T005 Implement `auth_internal.get_simplified_booking_slots` and public wrapper `get_simplified_booking_slots` (block generation, three availability states, `past` for today, date validation today..+90) in `backend/supabase/migrations/20260627120000_simplified_slot_booking.sql`
- [X] T006 [P] Add SQL tests for slot RPC states (`available`, `alternate_doctors_available`, `fully_unavailable`, `past`), per-doctor overlap (two doctors same time allowed; same doctor blocked), and date validation in `backend/tests/simplified_slot_booking.sql`
- [X] T007 [P] Update overlap regression expectations in `backend/tests/appointment_management_crud.sql` for per-doctor semantics
- [X] T008 [P] Add `SlotAvailabilityState` enum and `SimplifiedBookingSlot` model per data-model.md in `frontend/lib/features/appointments/domain/simplified_booking_slot.dart`
- [X] T009 Add `SimplifiedBookingDaySlots` response type and RPC JSON → domain mapper (state string mapping, `availableDoctorIds`) in `frontend/lib/features/appointments/domain/simplified_booking_slot.dart`
- [X] T010 Implement `getSimplifiedBookingSlots({branchId, localDate, preferredDoctorId})` calling `get_simplified_booking_slots` RPC in `frontend/lib/features/appointments/data/appointment_repository.dart`

**Checkpoint**: Migration applied, slot RPC tested, repository method returns parsed blocks — slot picker UI can begin.

---

## Phase 3: User Story 1 - Configure Default Appointment Duration (Priority: P1) 🎯 MVP

**Goal**: Administrators set branch-scoped default appointment duration in clinic setup; value persists via existing RPCs and drives block size in simplified booking.

**Independent Test**: Change default duration in settings (e.g. 15 min), save successfully, reopen settings and verify persisted value; invalid values show validation errors; users without permission see blocked UI.

### Implementation for User Story 1

- [ ] T011 [P] [US1] Create `AppointmentDurationSettingsSection` with numeric duration field, branch scope label, and save action in `frontend/lib/features/settings/presentation/widgets/appointment_duration_settings_section.dart`
- [ ] T012 [US1] Wire `AppointmentRepository.getSettings` / `setDefaultDuration` with permission gate matching `set_appointment_default_duration` grants in `frontend/lib/features/settings/presentation/widgets/appointment_duration_settings_section.dart`
- [ ] T013 [US1] Add client validation (≥ `min_duration_minutes`, empty/invalid feedback, preserve previous value on failure) in `frontend/lib/features/settings/presentation/widgets/appointment_duration_settings_section.dart`
- [ ] T014 [US1] Embed `AppointmentDurationSettingsSection` in clinic setup tab (branch settings card or dedicated row) in `frontend/lib/features/settings/presentation/widgets/clinic_setup_settings_tab.dart` and/or `frontend/lib/features/settings/presentation/widgets/branch_settings_section.dart`

**Checkpoint**: US1 independently testable via settings UI — duration save/load works without simplified booking flow.

---

## Phase 4: User Story 2 - Select Date and Time via Simplified Slot Picker (Priority: P1)

**Goal**: Compact day strip (centered selection, 90-day cap) and time block grid with three availability states, alternate-doctors dialog, and show-more expand.

**Independent Test**: Open step two with patient/doctor context, verify day strip centers today, navigate within 90 days, grid shows blocks at default duration intervals, available blocks select, alternate blocks open doctor list, fully unavailable/past blocks are no-op.

### Tests for User Story 2

- [ ] T015 [P] [US2] Add unit tests for RPC state mapping and local-date clamp (today..today+90) in `frontend/test/unit/appointments/simplified_booking_slot_test.dart`

### Implementation for User Story 2

- [ ] T016 [P] [US2] Implement `SimplifiedDayStrip` with centered selected day, chevron navigation, and `[today, today+90]` clamp per contracts in `frontend/lib/features/appointments/presentation/widgets/simplified_day_strip.dart`
- [ ] T017 [P] [US2] Implement `SimplifiedTimeBlockGrid` with four visual states (available, alternate, fully unavailable, selected) and tap routing per state in `frontend/lib/features/appointments/presentation/widgets/simplified_time_block_grid.dart`
- [ ] T018 [P] [US2] Implement `AlternateDoctorsDialog` listing doctors filtered to `availableDoctorIds` with time message and dismiss behavior in `frontend/lib/features/appointments/presentation/widgets/alternate_doctors_dialog.dart`
- [ ] T019 [US2] Add inline **Show more slots** expand control with available-block count subtitle in `frontend/lib/features/appointments/presentation/widgets/simplified_time_block_grid.dart`
- [ ] T020 [US2] Add `Semantics` labels for day cells and time blocks (state-aware) in `frontend/lib/features/appointments/presentation/widgets/simplified_day_strip.dart` and `frontend/lib/features/appointments/presentation/widgets/simplified_time_block_grid.dart`

### Tests for User Story 2 (widgets)

- [ ] T021 [P] [US2] Add widget tests for day strip centering, 90-day clamp, and chevron navigation in `frontend/test/widget/appointments/simplified_day_strip_test.dart`
- [ ] T022 [P] [US2] Add widget tests for block grid states, selection highlight, and show-more expand in `frontend/test/widget/appointments/simplified_time_block_grid_test.dart`
- [ ] T023 [P] [US2] Add widget tests for alternate-doctors dialog doctor list and dismiss in `frontend/test/widget/appointments/alternate_doctors_dialog_test.dart`

**Checkpoint**: US2 picker widgets independently demonstrable with mock slot data.

---

## Phase 5: User Story 3 - View Selected Slot Summary and Complete Booking (Priority: P1)

**Goal**: Bottom summary card shows selected date/time range and effective doctor; confirm creates planned appointment with default duration; conflict refreshes grid.

**Independent Test**: Select slot, verify summary card content (weekday, date, time range, doctor); confirm disabled without selection; submit creates appointment; `SCHEDULE_CONFLICT` shows error and refreshes availability.

### Implementation for User Story 3

- [ ] T024 [P] [US3] Implement `SimplifiedSlotSummaryCard` with mint/teal styling, formatted date/time range, doctor name, and disabled confirm when no selection in `frontend/lib/features/appointments/presentation/widgets/simplified_slot_summary_card.dart`
- [ ] T025 [US3] Wire confirm action to `AppointmentRepository.createAppointment` using `effectiveDoctorId`, selected slot start, and frozen `defaultDurationMinutes` (no override) in `frontend/lib/features/appointments/presentation/widgets/simplified_slot_summary_card.dart`
- [ ] T026 [US3] Handle `SCHEDULE_CONFLICT` and other RPC failures with user-visible messaging and slot grid refresh callback in `frontend/lib/features/appointments/presentation/widgets/simplified_slot_summary_card.dart`
- [ ] T027 [US3] Add confirm blocking when parent reports slot load failure; accept `slotsAvailable` / `onRetry` props for step-two host wiring (FR-014) in `frontend/lib/features/appointments/presentation/widgets/simplified_slot_summary_card.dart`

### Tests for User Story 3

- [ ] T028 [P] [US3] Add widget tests for summary card content, disabled confirm, and enabled confirm with selection in `frontend/test/widget/appointments/simplified_slot_summary_card_test.dart`

**Checkpoint**: US3 summary + create path testable when embedded in step two host.

---

## Phase 6: User Story 4 - Use Simplified Booking as Step Two of the Booking Procedure (Priority: P1)

**Goal**: Two-step modal from calendar header — step one (patient + doctor), step two (slot picker + summary); back navigation clears slot; doctor change reloads grid.

**Independent Test**: Tap **Book Appointment** header button, complete step one, advance to step two picker, finish booking without calendar; incomplete step one blocked; back from step two clears selection; changing doctor in step one refreshes grid.

### Implementation for User Story 4

- [ ] T029 [P] [US4] Add `SimplifiedBookingSession` in-memory state model (patient, preferred/effective doctor, selected date/slot, frozen duration) in `frontend/lib/features/appointments/domain/simplified_booking_session.dart`
- [ ] T030 [P] [US4] Implement `SimplifiedBookingStepOne` reusing patient search and `AppointmentDoctorSelector` with validation in `frontend/lib/features/appointments/presentation/widgets/simplified_booking_step_one.dart`
- [ ] T031 [US4] Implement `SimplifiedBookingStepTwo` hosting day strip, block grid, alternate dialog orchestration, summary card, slot RPC load on date/doctor change, and degraded/retry UI when slot RPC fails (FR-014) in `frontend/lib/features/appointments/presentation/widgets/simplified_booking_step_two.dart`
- [ ] T032 [US4] Implement `SimplifiedBookingFlow.show` modal shell (scrim, step indicator, back from step two clears slot, step navigation) in `frontend/lib/features/appointments/presentation/widgets/simplified_booking_flow.dart`
- [ ] T033 [US4] Wire calendar header **Book Appointment** to `SimplifiedBookingFlow.show` with `canCreateAppointments` gate in `frontend/lib/features/appointments/presentation/pages/appointment_calendar_page.dart`
- [ ] T034 [US4] Load `defaultDurationMinutes` from `getSettings` at step-two open and omit duration override controls throughout flow in `frontend/lib/features/appointments/presentation/widgets/simplified_booking_flow.dart`

### Tests for User Story 4

- [ ] T035 [P] [US4] Add widget/integration test for header-button two-step booking (step one → step two → confirm) in `frontend/test/widget/appointments/simplified_booking_flow_test.dart`

**Checkpoint**: Full simplified two-step booking path works from calendar header.

---

## Phase 7: User Story 5 - Calendar Booking Remains Available (Priority: P2)

**Goal**: Calendar slot tap continues to open legacy `AppointmentBookingSheet`; dual entry points produce equivalent appointment records with appropriate duration rules per path.

**Independent Test**: Tap empty calendar slot → legacy sheet opens with duration override; header button → simplified flow; no regression in calendar booking tests.

### Implementation for User Story 5

- [ ] T036 [US5] Verify `_showBookingSheet` / `AppointmentBookingSheet.show` on calendar slot tap is unchanged and not redirected to simplified flow in `frontend/lib/features/appointments/presentation/pages/appointment_calendar_page.dart`

### Tests for User Story 5

- [ ] T037 [P] [US5] Add widget test asserting header **Book Appointment** opens `SimplifiedBookingFlow` while slot tap opens `AppointmentBookingSheet` in `frontend/test/widget/appointments/appointment_calendar_booking_test.dart`

**Checkpoint**: US5 regression verified — existing calendar booking path intact.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: End-to-end verification, repository test coverage, and quickstart validation.

- [ ] T038 [P] Extend `AppointmentRepository` unit tests for `getSimplifiedBookingSlots` parsing and error surfacing in `frontend/test/unit/appointments/appointment_repository_test.dart`
- [ ] T039 Run `./backend/tests/run_all_backend_tests.sh` and fix any failures from overlap migration
- [ ] T040 Run `flutter test test/unit/appointments/simplified_booking_slot_test.dart` and `flutter test test/widget/appointments/` per quickstart.md
- [ ] T041 Execute manual verification checklist in `specs/011-simplified-slot-booking/quickstart.md` §3–5 (settings, simplified booking, alternate doctors, calendar path unchanged)
- [ ] T042 [P] Review constitution alignment: server-authoritative slots, per-doctor overlap, no AI dependency, layer boundaries in `specs/011-simplified-slot-booking/plan.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — **BLOCKS US2, US3, US4**
- **US1 (Phase 3)**: Can start after Setup — parallel with Foundational (uses existing settings RPCs)
- **US2 (Phase 4)**: Depends on Foundational (T004–T010)
- **US3 (Phase 5)**: Depends on US2 widgets (T016–T020); summary can scaffold in parallel with late US2
- **US4 (Phase 6)**: Depends on US2 + US3; integrates settings duration from US1
- **US5 (Phase 7)**: Depends on US4 header wiring (T033) for dual-entry regression test
- **Polish (Phase 8)**: Depends on all desired user stories

### User Story Dependencies

| Story | Priority | Depends On | Independent Test |
| ----- | -------- | ---------- | ---------------- |
| US1 | P1 | Setup only | Settings save/load and validation |
| US2 | P1 | Foundational | Day strip + grid with mock slots |
| US3 | P1 | US2 widgets | Summary card + create with mock session |
| US4 | P1 | US1 duration concept, US2, US3 | Full header-button two-step flow |
| US5 | P2 | US4 header wiring | Calendar slot tap → legacy sheet |

### Within Each User Story

- Tests marked [P] within a story can run in parallel
- Domain models before repository consumers
- Picker widgets before step-two host
- Step hosts before flow shell
- Flow shell before calendar integration

### Parallel Opportunities

- **Phase 1**: T002 and T003 in parallel
- **Phase 2**: T006, T007, T008 in parallel after T004–T005; T010 after T008–T009
- **Phase 3 + Phase 2**: US1 (T011–T014) can run alongside Foundational backend tasks
- **Phase 4**: T015, T016, T017, T018 in parallel; T021–T023 in parallel after widgets
- **Phase 6**: T029 and T030 in parallel before T031–T032

---

## Parallel Example: User Story 2

```bash
# Launch picker widgets together (after Foundational):
Task T016: SimplifiedDayStrip in simplified_day_strip.dart
Task T017: SimplifiedTimeBlockGrid in simplified_time_block_grid.dart
Task T018: AlternateDoctorsDialog in alternate_doctors_dialog.dart

# Launch widget tests together (after widgets):
Task T021: simplified_day_strip_test.dart
Task T022: simplified_time_block_grid_test.dart
Task T023: alternate_doctors_dialog_test.dart
```

---

## Parallel Example: Foundational + US1

```bash
# Developer A — backend:
Task T004–T007: migration + SQL tests

# Developer B — Flutter domain + US1 settings:
Task T008–T010: domain models + repository
Task T011–T014: AppointmentDurationSettingsSection (parallel with migration)
```

---

## Implementation Strategy

### MVP First (US1 + Foundational + US2 core)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL)
3. Complete Phase 3: US1 — settings UI
4. Complete Phase 4: US2 — day strip + block grid (minimum viable picker)
5. **STOP and VALIDATE**: Settings duration affects block size when wired to step two

### Incremental Delivery

1. Setup + Foundational + US1 → default duration configurable
2. Add US2 → slot picker widgets with server data
3. Add US3 → summary card + booking confirmation
4. Add US4 → full two-step flow from calendar header
5. Add US5 → regression guard for calendar path
6. Polish → full test suite + quickstart

### Parallel Team Strategy

1. Team completes Setup together
2. Once Setup done:
   - Developer A: Foundational backend (T004–T007)
   - Developer B: US1 settings UI (T011–T014)
   - Developer C: Domain + repository (T008–T010)
3. After Foundational: split US2 widgets (T016–T018) across developers
4. US3–US4 sequential integration; US5 regression last

---

## Notes

- Calendar slot tap MUST remain on `AppointmentBookingSheet` — do not redirect in US4 work
- Simplified flow uses default duration only — no per-booking override UI
- Slot availability is server-authoritative via `get_simplified_booking_slots`; Flutter maps states only
- Per-doctor overlap migration is required for alternate-doctors UX — do not skip T004
- `effectiveDoctorId` may differ from step-one preferred doctor after alternate dialog
- Bookable range: today through 90 days ahead inclusive
- Preserve existing permission keys: `appointments.create` for booking, settings grants for duration
