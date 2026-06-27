# Implementation Plan: Simplified Slot Booking

**Branch**: `ui/011-simplified-slot-booking` | **Date**: 2026-06-27 | **Spec**: `specs/011-simplified-slot-booking/spec.md`

**Input**: Feature specification from `specs/011-simplified-slot-booking/spec.md`

## Summary

Deliver a **two-step planned booking** flow launched from the appointments calendar **Book Appointment** header button: step one collects patient and preferred doctor; step two shows a simplified date/time picker (centered day strip, duration-sized block grid, three availability states, bottom summary card). Calendar slot tap keeps the existing `AppointmentBookingSheet`.

Add **default appointment duration** settings UI (backend RPCs already exist) and a new **`get_simplified_booking_slots`** query RPC that returns server-authoritative block states for a branch/day/preferred doctor. Restore **per-doctor** overlap in `appointment_has_overlap` so alternate-doctor booking at the same clock time is valid (supersedes branch-wide slot uniqueness from `20260528150500`; required by clarified UX). No AI; calendar booking unchanged.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase; PL/pgSQL in `auth_internal` + public RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK, Riverpod, GoRouter; V1-4 `AppointmentRepository`, `get_appointment_settings`, `create_appointment`; V1-3 patient picker; V1-2 staff/doctor list, branch working schedule; existing `AppCard` / design tokens for picker chrome

**Storage**: Existing `app_settings` (`appointment.default_duration_minutes`); `appointments` table (read for slot occupancy); `branches.working_schedule`; no new tables

**Testing**: `backend/tests/` SQL additions for `get_simplified_booking_slots` + per-doctor overlap regression; Flutter unit tests for slot classification mapper; widget tests for day strip, block grid states, alternate-doctor dialog, summary card; integration test for header-button two-step booking

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile)

**Project Type**: Flutter `features/appointments` + one PostgreSQL migration + settings UI field; no custom API server; no AI

**Performance Goals**: Step-two grid renders within 500ms after day change for typical branch (≤10 doctors, ≤40 blocks/day) on clinic hardware; slot RPC returns within 300ms for single-day query

**Constraints**: Bookable range today–90 days; default duration only in simplified flow (no override); `appointments.create` permission; branch-scoped; degraded retry when slot RPC fails; AI N/A

**Scale/Scope**: 1 migration; 1 new query RPC; settings UI section; ~8 new Flutter widgets/files; 2 contract docs; header button wiring only (no queue entry)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope fits small-to-mid-size multi-branch clinics; self-service portals out of scope
- [x] No microservices, queues, Kubernetes, or custom primary backend service
- [x] Flutter UI/orchestration; Supabase RPC; PostgreSQL owns slot classification, overlap rules, settings validation
- [x] Protected writes via existing `create_appointment` RPC; new read-only slot query RPC
- [x] Tenant/branch isolation; `appointments.create` + settings permissions; audit on create/settings unchanged
- [x] No AI dependency; booking works offline-degraded with retry

### Post-Design Re-Check

- [x] Block availability states computed in PostgreSQL (`get_simplified_booking_slots`) — not client source of truth
- [x] Per-doctor overlap restoration documented with test migration (aligns clarified alternate-doctor UX; simpler than branch-wide + broken alternates)
- [x] Calendar slot-tap path untouched (`AppointmentBookingSheet`)
- [x] Settings default duration uses existing `set_appointment_default_duration` RPC
- [x] No new tables; soft-delete and audit patterns preserved

## Project Structure

### Documentation (this feature)

```text
specs/011-simplified-slot-booking/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── simplified-booking-queries.md
│   └── simplified-booking-ui.md
└── tasks.md              # /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260627120000_simplified_slot_booking.sql   # per-doctor overlap + get_simplified_booking_slots
└── tests/
    ├── simplified_slot_booking.sql
    └── (updates to appointment_management_crud.sql overlap cases)

frontend/lib/features/
├── appointments/
│   ├── data/
│   │   └── appointment_repository.dart              # + getSimplifiedBookingSlots
│   ├── domain/
│   │   ├── simplified_booking_slot.dart           # block + SlotAvailabilityState enum
│   │   └── simplified_booking_session.dart          # step state
│   └── presentation/
│       ├── pages/ or widgets/
│       │   ├── simplified_booking_flow.dart         # two-step modal/sheet shell
│       │   ├── simplified_booking_step_one.dart     # patient + doctor
│       │   └── simplified_booking_step_two.dart     # hosts picker + summary
│       └── widgets/
│           ├── simplified_day_strip.dart
│           ├── simplified_time_block_grid.dart
│           ├── simplified_slot_summary_card.dart
│           └── alternate_doctors_dialog.dart
│       └── pages/
│           └── appointment_calendar_page.dart       # wire header Book Appointment → flow
├── settings/
│   └── presentation/widgets/
│       └── appointment_duration_settings_section.dart  # default duration UI

frontend/test/
├── unit/appointments/simplified_booking_slot_test.dart
└── widget/appointments/simplified_booking_*_test.dart
```

**Structure Decision**: Feature code lives in `features/appointments` per `docs/architecture/07-frontend.md`. Settings field in `features/settings` clinic setup tab (branch-scoped duration). Backend changes are one migration extending V1-4 appointment RPCs.

## Implementation Phases (high level)

### Phase A — Backend: overlap + slot query

1. Migration: restore per-doctor filter in `auth_internal.appointment_has_overlap`; update conflict comments/tests
2. Implement `auth_internal.get_simplified_booking_slots` + public wrapper `get_simplified_booking_slots`
3. Grant EXECUTE to `authenticated`; add SQL tests for three states + 90-day date validation on caller side

### Phase B — Settings UI

1. `AppointmentDurationSettingsSection` on clinic setup (branch selector or active branch context)
2. Wire `AppointmentRepository.getSettings` / `setDefaultDuration`
3. Permission gate matching `set_appointment_default_duration` grants

### Phase C — Flutter simplified booking UI

1. Domain models for slots and session state
2. `SimplifiedDayStrip`, `SimplifiedTimeBlockGrid`, `SimplifiedSlotSummaryCard`, `AlternateDoctorsDialog`
3. `SimplifiedBookingFlow` two-step shell (step one reuses patient search + doctor selector patterns from booking sheet)
4. Repository method calling `get_simplified_booking_slots` on day/doctor change

### Phase D — Calendar integration

1. `appointment_calendar_page.dart`: header **Book Appointment** → `SimplifiedBookingFlow.show`
2. Preserve `_showBookingSheet` on calendar slot tap
3. On confirm → `createAppointment` with default duration (no override fields)

### Phase E — Tests & verification

1. Backend SQL + Flutter widget/unit tests per contracts
2. Execute `quickstart.md`

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Per-doctor overlap replaces branch-wide hotfix | Clarified UX requires booking alternate doctor at same clock time when preferred doctor is busy | Branch-wide uniqueness makes alternate-doctors state unreachable for appointment conflicts; prompts would always be false positives |

## Phase 0 & Phase 1 Artifacts

| Artifact | Status |
| -------- | ------ |
| `research.md` | Complete |
| `data-model.md` | Complete |
| `contracts/simplified-booking-queries.md` | Complete |
| `contracts/simplified-booking-ui.md` | Complete |
| `quickstart.md` | Complete |
| Agent context (`.cursor/rules/specify-rules.mdc`) | Updated |

**Next command**: `/speckit-tasks` to generate `tasks.md`.
