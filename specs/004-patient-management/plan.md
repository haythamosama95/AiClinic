# Implementation Plan: Patient Management

**Branch**: `specs/004-patient-management` | **Date**: 2026-05-23 | **Spec**: `specs/004-patient-management/spec.md`

**Input**: Feature specification from `/specs/004-patient-management/spec.md`

## Summary

Deliver V1-3 patient registry: `patients` table with org denormalization, org-scoped RLS, secured RPCs for search (branch vs organization scope, name contains / phone prefix), registration at active branch, org-wide edit/archive, duplicate advisory + national ID hard block, optimistic update conflicts, and Flutter `features/patients` (list with scope toggle, register, detail, edit, archive). Builds on V1-2 active branch context and existing `patients.*` permission seeds. No appointments, visits, billing, or AI.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase local stack; PL/pgSQL in `auth_internal` + public RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK, Riverpod, GoRouter; V1-2 `AuthSessionNotifier` (active branch), `PermissionRepository` / `PermissionService`; V1-0 shared widgets (data table, forms, dialogs)

**Storage**: New `public.patients` + `patient_gender` enum; denormalized `organization_id`; indexes on `(branch_id, full_name)`, `(branch_id, phone)`, unique `(organization_id, national_id)`; existing `audit_log`, `branches`

**Testing**: `backend/tests/patient_management_crud.sql`, `patient_management_rls.sql`, `run_patient_management_tests.sh`; Flutter unit/widget/integration under `test/**/patients/`

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile)

**Project Type**: Desktop client + Supabase PostgreSQL (migrations, RLS, RPC); no custom API server; no AI

**Performance Goals**: Registration confirmation within 15s (SC-001); branch list usable at 500 patients/branch (NFR-002); search first page interactive under normal LAN (NFR-003); 100% cross-org denial in verification

**Constraints**: Org-wide read/mutate (except create at active branch); soft delete only; no restore UI; no visit/appointment data; scope toggle resets to “this branch only” each sign-in; mutations via RPC; `updated_at` optimistic lock on update

**Scale/Scope**: 1 migration; 6 RPCs; ~5 Flutter pages; 2 contract docs; extend `PermissionKeys` with create/edit/delete

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope fits small-to-mid-size multi-branch clinics
- [x] No microservices, queues, Kubernetes, or custom primary backend service
- [x] Flutter UI/orchestration; Supabase/PostgREST; PostgreSQL owns mutations, validation, audit, RLS
- [x] Protected writes via `auth_internal` RPCs
- [x] Tenant isolation via `organization_id`; permission keys; audit; soft delete for archive
- [x] No AI dependency

### Post-Design Re-Check

- [x] `organization_id` on `patients` preserves isolation without branch-assignment RLS on reads
- [x] National ID uniqueness enforced in DB index + RPC
- [x] Archive uses soft delete only; no hard DELETE for app roles
- [x] Duplicate flow is human-gated (acknowledge before create/update)
- [x] Manual operation when AI unavailable (N/A for this feature)

## Project Structure

### Documentation (this feature)

```text
specs/004-patient-management/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── patient-list-search.md
│   └── patient-mutations.md
└── tasks.md             # Phase 2 — /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260523140000_patient_management.sql
└── tests/
    ├── patient_management_crud.sql
    ├── patient_management_rls.sql
    └── run_patient_management_tests.sh

frontend/lib/
├── app/
│   ├── router.dart
│   └── app_routes.dart              # /patients/*
├── core/auth/
│   └── permission_service.dart      # canViewPatients, canCreatePatients, ...
├── features/
│   ├── auth/domain/permission_keys.dart  # + patientsCreate/Edit/Delete
│   └── patients/
│       ├── data/
│       │   └── patient_repository.dart
│       ├── domain/
│       │   ├── patient_list_item.dart
│       │   ├── patient_detail.dart
│       │   └── patient_list_scope.dart
│       └── presentation/
│           ├── providers/
│           ├── pages/
│           │   ├── patient_list_page.dart
│           │   ├── patient_registration_page.dart
│           │   ├── patient_detail_page.dart
│           │   └── patient_edit_page.dart
│           └── widgets/
│               ├── patient_scope_toggle.dart
│               ├── patient_search_field.dart
│               └── duplicate_candidates_dialog.dart
└── features/auth/presentation/pages/auth_shell_page.dart  # nav link to Patients

frontend/test/
├── unit/patients/
├── widget/patients/
└── integration/patients/patient_management_acceptance_test.dart
```

**Structure Decision**: Operational patient flows live in `features/patients` per architecture folder layout; admin remains in `features/settings`. Shell adds navigation entry gated by `patients.view`.

## Implementation Phases (high level)

### Phase A — Backend: schema & RPCs

1. Migration: `patient_gender` enum, `patients` table with audit columns + `organization_id`
2. Indexes + RLS (SELECT for authenticated org; INSERT/UPDATE/DELETE denied on table)
3. `auth_internal` helpers: normalize phone, assert patient in org, duplicate finder
4. RPCs: `search_patients`, `get_patient`, `check_patient_duplicates`, `create_patient`, `update_patient`, `archive_patient`
5. Grants: `GRANT EXECUTE` on public wrappers to `authenticated`
6. Audit log entries per data-model.md

### Phase B — Backend verification

1. `patient_management_crud.sql` — CRUD, duplicates, stale update, national ID block, scope search
2. `patient_management_rls.sql` — cross-org denial
3. `run_patient_management_tests.sh`

### Phase C — Flutter patients module

1. Extend `PermissionKeys` + `PermissionService` helpers
2. `PatientRepository` wrapping RPCs
3. Routes and route guards (`patients.view` / create / edit / delete)
4. List page: scope toggle, search, data table, pagination
5. Registration, detail (visits placeholder), edit, archive confirm
6. Duplicate and stale conflict dialogs

### Phase D — Shell integration

1. Add **Patients** nav from `AuthShellPage` when `patients.view`
2. Wire active branch into `search_patients` when scope = branch

### Phase E — Tests & docs

1. Unit/widget/integration tests per spec test cases 1–13
2. `quickstart.md` verification paths

## Complexity Tracking

No constitution violations requiring justification.

## Phase 0 & Phase 1 Artifacts

| Artifact                                          | Status               |
| ------------------------------------------------- | -------------------- |
| `research.md`                                     | Complete             |
| `data-model.md`                                   | Complete             |
| `contracts/*`                                     | Complete (2 files)   |
| `quickstart.md`                                   | Complete             |
| Agent context (`.cursor/rules/specify-rules.mdc`) | Updated to this plan |

**Next command**: `/speckit-tasks` to generate `tasks.md`.
