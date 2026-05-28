# Implementation Plan: Appointment Management

**Branch**: `specs/005-appointment-management` | **Date**: 2026-05-24 | **Spec**: `specs/005-appointment-management/spec.md`

**Input**: Feature specification from `/specs/005-appointment-management/spec.md`

## Summary

Deliver V1-4 appointment scheduling: `appointments` table with branch-scoped RLS, secured RPCs for planned booking, phone-confirmation status (`confirmed`), reschedule, cancel/no-show, status lifecycle, default duration via `app_settings`, and Flutter `features/appointments` (calendar day/week, booking, today's queue with Realtime fallback, doctor schedule). Queue sorts by `start_time`; lifecycle is `scheduled` → `confirmed` → `checked_in` → `in_progress` → `completed`. Walk-in registration removed. Builds on V1-3 patients, V1-2 branch/staff/settings, V1-1 auth and `appointments.*` seeds. No visits, billing, shifts, or AI.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase local stack; PL/pgSQL in `auth_internal` + public RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK (incl. Realtime), Riverpod, GoRouter; V1-2 `AuthSessionNotifier`, `PermissionRepository`; V1-3 `PatientRepository` / patient picker; V1-0 shared widgets (calendar-oriented layouts, forms, dialogs)

**Storage**: `public.appointments` + enums `appointment_type`, `appointment_status`; indexes per architecture; `app_settings` key `appointment.default_duration_minutes`; `audit_log`

**Testing**: `backend/tests/appointment_management_crud.sql`, `appointment_management_rls.sql`, `run_appointment_management_tests.sh`; Flutter unit/widget/integration under `test/**/appointments/`

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile)

**Project Type**: Desktop client + Supabase PostgreSQL (migrations, RLS, RPC, Realtime); no custom API server; no AI

**Performance Goals**: Booking confirmation within 20s (SC-001); queue usable at 200 appointments/branch/day (NFR-002); conflict feedback interactive (NFR-003); 100% cross-org denial; Realtime queue update within 5s in 95% of trials when enabled (SC-008)

**Constraints**: Branch-scoped RLS; mutations via RPC only; planned booking only; duration 5–240 min with settings default + per-booking override; reschedule `scheduled` only; any `appointments.create` may advance status; `queue_number` unused; no visit on complete

**Scale/Scope**: 1 migration; 7 RPCs; ~6 Flutter pages; 2 contract docs; Realtime subscription on queue

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope fits small-to-mid-size multi-branch clinics
- [x] No microservices, queues, Kubernetes, or custom primary backend service
- [x] Flutter UI/orchestration; Supabase/PostgREST/Realtime; PostgreSQL owns mutations, validation, audit, RLS
- [x] Protected writes via `auth_internal` RPCs
- [x] Tenant isolation branch-scoped; permission keys; audit; soft delete pattern on table
- [x] No AI dependency

### Post-Design Re-Check

- [x] Conflict and status rules enforced only in PostgreSQL functions
- [x] Phone confirmation (`confirmed`) enforced server-side before check-in
- [x] Realtime is enhancement only; manual refresh when degraded
- [x] Settings default duration stored in `app_settings`, not hard-coded-only
- [x] No visit creation on `completed` (deferred V1-5)

## Project Structure

### Documentation (this feature)

```text
specs/005-appointment-management/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── appointment-mutations.md
│   └── appointment-queries.md
└── tasks.md              # /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260526140000_appointment_management.sql
└── tests/
    ├── appointment_management_crud.sql
    ├── appointment_management_rls.sql
    └── run_appointment_management_tests.sh

frontend/lib/
├── app/
│   ├── router.dart
│   └── app_routes.dart              # /appointments/*
├── core/auth/
│   └── permission_service.dart      # canAccessAppointments, canCreateAppointments, ...
├── features/
│   ├── auth/domain/permission_keys.dart  # + appointmentsCreate/Cancel
│   ├── patients/                    # patient picker reuse
│   └── appointments/
│       ├── data/
│       │   └── appointment_repository.dart
│       ├── domain/
│       │   ├── appointment_list_item.dart
│       │   ├── appointment_status.dart
│       │   └── appointment_type.dart
│       └── presentation/
│           ├── providers/
│           │   ├── appointment_queue_provider.dart   # Realtime + refresh
│           │   └── appointment_calendar_provider.dart
│           ├── pages/
│           │   ├── appointment_calendar_page.dart
│           │   ├── appointment_booking_page.dart
│           │   ├── walk_in_registration_page.dart
│           │   ├── appointment_queue_page.dart
│           │   └── doctor_schedule_page.dart
│           └── widgets/
│               ├── appointment_status_actions.dart
│               ├── duration_field.dart
│               └── conflict_error_banner.dart
└── features/settings/presentation/pages/
    └── organization_settings_page.dart   # default duration field

frontend/test/
├── unit/appointments/
├── widget/appointments/
└── integration/appointments/appointment_management_acceptance_test.dart
```

**Structure Decision**: Operational scheduling in `features/appointments` per `docs/architecture/07-frontend.md`; settings key edited via existing organization settings (V1-2). Shell nav when user has appointment view access.

## Implementation Phases (high level)

### Phase A — Backend: schema & RPCs

1. Migration: enums, `appointments` table, indexes, branch RLS (SELECT only; deny direct writes)
2. Helpers: overlap check, walk-in gap finder, resolve default duration, assert doctor/patient/branch
3. RPCs: `get_appointment_settings`, `set_appointment_default_duration`, `create_appointment`, `reschedule_appointment`, `cancel_appointment`, `update_appointment_status`, `list_appointments`
4. Grants + audit log entries per data-model.md

### Phase B — Backend verification

1. `appointment_management_crud.sql` — create, walk-in slot, conflict, status, reschedule, cancel, settings
2. `appointment_management_rls.sql` — cross-branch/org denial
3. `run_appointment_management_tests.sh`

### Phase C — Flutter appointments module

1. Extend `PermissionKeys` + `PermissionService`
2. `AppointmentRepository` wrapping RPCs
3. Routes and guards under `/appointments`
4. Calendar (day/week), booking form with duration pre-fill/override
5. Walk-in form + auto-slot result display
6. Today's queue + Realtime subscription + degraded refresh
7. Doctor schedule filter; status action bar; reschedule flow

### Phase D — Settings & shell

1. Default duration field on organization settings → `set_appointment_default_duration`
2. Shell nav link when `canAccessAppointments`
3. Patient picker integration from `features/patients`

### Phase E — Tests & docs

1. Unit/widget/integration per spec test cases 1–14
2. `quickstart.md` verification

## Complexity Tracking

No constitution violations requiring justification.

## Phase 0 & Phase 1 Artifacts

| Artifact                                          | Status               |
| ------------------------------------------------- | -------------------- |
| `research.md`                                     | Complete             |
| `data-model.md`                                   | Complete             |
| `contracts/appointment-mutations.md`              | Complete             |
| `contracts/appointment-queries.md`                | Complete             |
| `quickstart.md`                                   | Complete             |
| Agent context (`.cursor/rules/specify-rules.mdc`) | Updated to this plan |

**Next command**: `/speckit-tasks` to generate `tasks.md`.
