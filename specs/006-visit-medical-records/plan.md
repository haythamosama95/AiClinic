# Implementation Plan: Visits and Medical Records

**Branch**: `specs/006-visit-medical-records` | **Date**: 2026-05-31 | **Spec**: `specs/006-visit-medical-records/spec.md`

**Input**: Feature specification from `/specs/006-visit-medical-records/spec.md`

## Summary

Deliver V1-5 clinical visit documentation: `visits`, `soap_notes`, `treatment_plans`, `visit_attachments` with branch-scoped RLS, secured RPCs for create/save/submit/attachment registration, private Supabase Storage bucket, and Flutter `features/visits` integrated with appointments and patient profile. Visit creation from `checked_in`/`in_progress` appointments; visit submit atomically completes the linked appointment; manual appointment `in_progress` → `completed` disabled. Attachments: PDF, DOCX, JPEG, PNG (25 MB). Lab staff get `visits.upload_attachment` with own-upload download only. Builds on V1-4 appointments, V1-3 patients, V1-2 branch/settings, V1-1 auth. No billing, shifts, or AI.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase local stack; PL/pgSQL in `auth_internal` + public RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK (Storage + RPC), Riverpod, GoRouter; V1-2 `AuthSessionNotifier`, `PermissionRepository`; V1-3 patient profile; V1-4 `AppointmentRepository`, status actions, queue/calendar

**Storage**: `public.visits`, `soap_notes`, `treatment_plans`, `visit_attachments`; enum `visit_status`; Supabase bucket `visit-attachments`; `app_settings` key `specialty.form_schema_json`; permission seed `visits.upload_attachment`

**Testing**: `backend/tests/visit_medical_records_crud.sql`, `visit_medical_records_rls.sql`, `run_visit_medical_records_tests.sh`; update appointment tests for visit-based completion; Flutter unit/widget/integration under `test/**/visits/`

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile)

**Project Type**: Desktop client + Supabase PostgreSQL (migrations, RLS, RPC, Storage); no custom API server; no AI

**Performance Goals**: Visit create to documentation screen within 15s (SC-001); SOAP save feels instantaneous (NFR-002); patient history to 500 visits with pagination (NFR-003); attachment upload progress to 25 MB (NFR-004)

**Constraints**: Branch-scoped RLS; mutations via RPC only; one visit per appointment; optimistic SOAP concurrency; visit submit couples appointment completion; defense in depth UI + RPC + RLS + storage policies

**Scale/Scope**: 1 migration (+ appointment RPC patch); ~12 RPCs; storage bucket + policies; ~5 Flutter pages/widgets; 2 contract docs; replace `PatientVisitsPlaceholder`; appointment UI transition change

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope fits small-to-mid-size multi-branch outpatient clinics
- [x] No microservices, queues, Kubernetes, or custom primary backend service
- [x] Flutter UI/orchestration; Supabase RPC/Storage; PostgreSQL owns mutations, validation, audit, RLS
- [x] Protected writes via `auth_internal` RPCs
- [x] Tenant isolation branch-scoped; permission keys; audit; soft delete on domain tables
- [x] No AI dependency; manual SOAP only

### Post-Design Re-Check

- [x] Visit–appointment completion enforced atomically in PostgreSQL (`complete_visit`)
- [x] Manual appointment complete blocked in `update_appointment_status`
- [x] Attachment authorization (including lab own-download) enforced in RPC + storage policies
- [x] SOAP optimistic concurrency prevents silent data loss
- [x] Specialty schema via existing `app_settings`, not new admin surface
- [x] No billing, shift, prescription, workflow, or AI schemas/screens

## Project Structure

### Documentation (this feature)

```text
specs/006-visit-medical-records/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── visit-mutations.md
│   └── visit-queries.md
└── tasks.md              # /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260531180000_visit_medical_records.sql
└── tests/
    ├── visit_medical_records_crud.sql
    ├── visit_medical_records_rls.sql
    └── run_visit_medical_records_tests.sh

frontend/lib/
├── app/
│   ├── router.dart
│   └── app_routes.dart              # + /visits/*
├── core/auth/
│   └── permission_service.dart      # canCreateVisits, canEditVisitSoap, ...
├── features/
│   ├── auth/domain/permission_keys.dart  # + visitsCreate, visitsEditSoap, visitsUploadAttachment
│   ├── appointments/
│   │   ├── domain/appointment_status_transitions.dart  # remove in_progress→completed
│   │   └── presentation/widgets/
│   │       ├── appointment_status_actions.dart         # Create/Open visit actions
│   │       └── visit_create_dialog.dart                # doctor picker when needed
│   ├── patients/presentation/
│   │   ├── pages/patient_detail_page.dart              # integrate visit history
│   │   └── widgets/
│   │       ├── patient_visits_placeholder.dart         # remove/replace
│   │       └── patient_visit_history_section.dart
│   └── visits/
│       ├── data/
│       │   ├── visit_repository.dart
│       │   └── visit_attachment_service.dart           # storage upload + register RPC
│       ├── domain/
│       │   ├── visit_list_item.dart
│       │   ├── visit_detail.dart
│       │   ├── visit_status.dart
│       │   ├── soap_note.dart
│       │   ├── treatment_plan_item.dart
│       │   └── visit_attachment_item.dart
│       └── presentation/
│           ├── pages/
│           │   ├── visit_documentation_page.dart       # SOAP + specialty + plans + attachments
│           │   └── visit_detail_page.dart              # read-only/history drill-down
│           ├── providers/
│           │   └── visit_documentation_notifier.dart
│           └── widgets/
│               ├── soap_editor.dart
│               ├── specialty_form_fields.dart
│               ├── treatment_plan_list.dart
│               ├── visit_attachment_list.dart
│               └── visit_submit_dialog.dart

frontend/test/
├── unit/visits/
├── widget/visits/
└── integration/visits/visit_medical_records_acceptance_test.dart
```

**Structure Decision**: Visit clinical workflows in `features/visits` per architecture; appointment entry points stay in `features/appointments`; patient longitudinal view extends `features/patients` by replacing the V1-3 placeholder widget.

## Implementation Phases (high level)

### Phase A — Backend: schema, storage, RPCs

1. Migration: enums, visit domain tables, indexes, partial unique on `appointment_id`, branch RLS (SELECT only; deny direct writes)
2. Storage bucket `visit-attachments` with size/type limits and branch-scoped policies
3. Seed `visits.upload_attachment` for lab_staff + clinical roles
4. Helpers: assert visit branch scope, assert upload permission, validate attachment type/size, resolve visit_date from appointment, SOAP non-empty check
5. RPCs per `data-model.md` and `contracts/*`
6. Patch `update_appointment_status`: reject `in_progress` → `completed`
7. Grants + audit log entries

### Phase B — Backend verification

1. `visit_medical_records_crud.sql` — create, SOAP, complete, treatment plans, attachments, appointment integration
2. `visit_medical_records_rls.sql` — cross-branch/org denial, lab download rules
3. Update `appointment_management_crud.sql` completion scenarios to use `complete_visit`
4. `run_visit_medical_records_tests.sh`

### Phase C — Flutter visits module

1. Extend `PermissionKeys` + `PermissionService`
2. `VisitRepository` + `VisitAttachmentService`
3. Routes and guards under `/visits`
4. Visit documentation page (SOAP editor with stale conflict UX, specialty dynamic fields, treatment plans, attachments with progress)
5. Visit submit flow with confirmation dialog

### Phase D — Appointment & patient integration

1. Appointment status transitions: remove **Complete**; add **Create visit** / **Open visit**
2. Doctor selection dialog when appointment has no `doctor_id`
3. Replace `PatientVisitsPlaceholder` with paginated visit history + detail navigation
4. Permission-aware metadata vs clinical detail on patient profile

### Phase E — Tests & docs

1. Unit/widget/integration per spec test cases 1–16
2. `quickstart.md` operator verification

## Complexity Tracking

No constitution violations requiring justification.

## Phase 0 & Phase 1 Artifacts

| Artifact                                          | Status               |
| ------------------------------------------------- | -------------------- |
| `research.md`                                     | Complete             |
| `data-model.md`                                   | Complete             |
| `contracts/visit-mutations.md`                    | Complete             |
| `contracts/visit-queries.md`                      | Complete             |
| `quickstart.md`                                   | Complete             |
| Agent context (`.cursor/rules/specify-rules.mdc`) | Updated to this plan |

**Next command**: `/speckit-tasks` to generate `tasks.md`.
