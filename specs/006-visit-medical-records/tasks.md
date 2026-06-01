# Tasks: Visits and Medical Records

**Input**: Design documents from `/specs/006-visit-medical-records/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md; **V1-4** (`specs/005-appointment-management`), **V1-3**, **V1-2**, **V1-1** complete

**Tests**: Included — spec defines acceptance criteria and test cases 1–16; constitution requires RLS/RPC verification (`backend/tests/`); FR-025 backend verification utilities.

**Organization**: Tasks grouped by user story. Labels map to `spec.md` user stories (US1–US6).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in same phase)
- **[Story]**: User story label for traceability
- Include exact file paths in descriptions

## Path Conventions

- **Flutter**: `frontend/lib/`, `frontend/test/`
- **Supabase**: `backend/supabase/migrations/`, `backend/tests/`
- **Contracts**: `specs/006-visit-medical-records/contracts/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Visits feature module layout, routes, and test workspace before migration/UI work

- [X] T001 Create visits feature directories in `frontend/lib/features/visits/data/`, `frontend/lib/features/visits/domain/`, `frontend/lib/features/visits/presentation/pages/`, `frontend/lib/features/visits/presentation/providers/`, and `frontend/lib/features/visits/presentation/widgets/`
- [X] T002 [P] Create test directories `frontend/test/unit/visits/`, `frontend/test/widget/visits/`, and `frontend/test/integration/visits/`
- [X] T003 [P] Add visit route constants in `frontend/lib/app/app_routes.dart` (`/visits/:visitId/document`, `/visits/:visitId/detail` plus path builders)
- [X] T004 [P] Add domain model stubs per `data-model.md` in `frontend/lib/features/visits/domain/visit_list_item.dart`, `visit_detail.dart`, `visit_status.dart`, `soap_note.dart`, `treatment_plan_item.dart`, and `visit_attachment_item.dart`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Visit domain migration, all RPCs, storage bucket, backend verification, repository scaffold, permission keys, route guards — **blocks all user stories**

**⚠️ CRITICAL**: No user story phase work until this phase is complete

- [X] T005 Add migration `backend/supabase/migrations/20260531180000_visit_medical_records.sql` with `visit_status` and `visit_attachment_file_type` enums, `visits`, `soap_notes`, `treatment_plans`, `visit_attachments` tables, indexes, partial unique on `appointment_id`, branch RLS (SELECT scoped; INSERT/UPDATE/DELETE denied), private `visit-attachments` storage bucket + policies, `visits.upload_attachment` permission seed, `auth_internal` helpers, and RPCs `create_visit`, `save_soap_note`, `complete_visit`, `create_treatment_plan`, `update_treatment_plan`, `archive_treatment_plan`, `register_visit_attachment`, `get_visit_attachment_download`, `get_visit`, `get_visit_by_appointment`, `list_patient_visits`, `get_specialty_form_schema` per `contracts/` and `data-model.md`; patch `update_appointment_status` to reject `in_progress` → `completed` with `VISIT_REQUIRED_FOR_COMPLETION`
- [X] T006 [P] Add CRUD verification SQL in `backend/tests/visit_medical_records_crud.sql` (create visit, SOAP save, complete visit, treatment plans, attachment register/download, appointment integration stubs)
- [X] T007 [P] Add RLS isolation SQL in `backend/tests/visit_medical_records_rls.sql` (cross-org, cross-branch denial, lab own-download rule)
- [X] T008 [P] Add test runner `backend/tests/run_visit_medical_records_tests.sh`
- [X] T009 [P] Update `backend/tests/appointment_management_crud.sql` completion scenarios to use `complete_visit` instead of `update_appointment_status(..., 'completed')` and add rejection test for manual complete
- [X] T010 [P] Wire `run_visit_medical_records_tests.sh` into `backend/tests/run_all_backend_tests.sh`
- [X] T011 [P] Extend `PermissionKeys` with `visitsCreate`, `visitsEditSoap`, and `visitsUploadAttachment` in `frontend/lib/features/auth/domain/permission_keys.dart`; update `RolePermissionSeed` for clinical roles and `labStaff`
- [X] T012 [P] Add `canCreateVisits`, `canEditVisitSoap`, `canUploadVisitAttachments`, and `canViewVisitClinicalDetail` helpers in `frontend/lib/core/auth/permission_service.dart`
- [X] T013 Implement `VisitRepository` RPC wrapper scaffold in `frontend/lib/features/visits/data/visit_repository.dart` (method stubs for all visit RPCs per `contracts/`)
- [X] T014 [P] Implement `VisitAttachmentService` scaffold (storage upload path builder, register/download method stubs) in `frontend/lib/features/visits/data/visit_attachment_service.dart`
- [X] T015 [P] Add visit RPC error message mapping in `frontend/lib/features/visits/presentation/visit_rpc_messages.dart` (`STALE_SOAP`, `APPOINTMENT_NOT_ELIGIBLE`, `VISIT_ALREADY_EXISTS`, `SOAP_REQUIRED_FOR_COMPLETE`, etc.)
- [X] T016 Register visit routes with `visits.create` / `visits.edit_soap` guards in `frontend/lib/app/router.dart`

**Checkpoint**: `supabase migration up` succeeds; `run_visit_medical_records_tests.sh` passes; visit routes registered (pages may be placeholders until story phases)

---

## Phase 3: User Story 1 - Create a Visit from a Checked-In or In-Progress Appointment (Priority: P1) 🎯 MVP

**Goal**: Start a visit from eligible appointments with doctor selection when missing; advance `checked_in` → `in_progress`; navigate to documentation

**Independent Test**: Use checked-in or in-progress appointment → create visit → verify linkage and status; reject duplicate and ineligible statuses; doctor prompt when appointment has no doctor

### Tests for User Story 1

- [X] T017 [P] [US1] Add `create_visit` and `get_visit_by_appointment` tests (eligible statuses, duplicate rejection, doctor required, checked_in advance) in `backend/tests/visit_medical_records_crud.sql`
- [X] T018 [P] [US1] Add unit tests for `VisitRepository.createVisit` and `getVisitByAppointment` in `frontend/test/unit/visits/visit_repository_create_test.dart`
- [X] T019 [P] [US1] Add widget tests for doctor selection and eligibility errors in `frontend/test/widget/visits/visit_create_dialog_test.dart`

### Implementation for User Story 1

- [X] T020 [US1] Implement `VisitRepository.createVisit` and `getVisitByAppointment` per `contracts/visit-mutations.md` and `contracts/visit-queries.md` in `frontend/lib/features/visits/data/visit_repository.dart`
- [X] T021 [US1] Implement `VisitCreateDialog` with optional doctor picker (branch doctors) in `frontend/lib/features/appointments/presentation/widgets/visit_create_dialog.dart`
- [X] T022 [US1] Remove `in_progress` → `completed` from `forwardStatusTargetFor` in `frontend/lib/features/appointments/domain/appointment_status_transitions.dart`
- [X] T023 [US1] Replace **Complete** with **Create visit** / **Open visit** actions gated by `visits.create` in `frontend/lib/features/appointments/presentation/widgets/appointment_status_actions.dart`
- [X] T024 [US1] Wire visit create/open actions on `AppointmentQueuePage` and `AppointmentCalendarPage` in `frontend/lib/features/appointments/presentation/pages/appointment_queue_page.dart` and `appointment_calendar_page.dart`
- [X] T025 [US1] Implement `VisitDocumentationPage` shell (loads visit context, placeholder sections until later stories) in `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`
- [X] T026 [US1] Gate `/visits/:visitId/document` route to `visits.create` or `visits.edit_soap` in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 1–4, 2b, 14–15; acceptance criteria 1–2

---

## Phase 4: User Story 2 - Document a SOAP Note (Priority: P1)

**Goal**: Save S/O/A/P sections with partial save, optimistic concurrency, and audit-backed persistence

**Independent Test**: Open in-progress visit → enter SOAP → save → reload unchanged; stale save from second session rejected with refresh prompt

### Tests for User Story 2

- [X] T027 [P] [US2] Add `save_soap_note` tests including partial save and `STALE_SOAP` in `backend/tests/visit_medical_records_crud.sql`
- [X] T028 [P] [US2] Add unit tests for `VisitRepository.saveSoapNote` optimistic concurrency in `frontend/test/unit/visits/visit_repository_soap_test.dart`
- [X] T029 [P] [US2] Add widget tests for save states and stale conflict UX in `frontend/test/widget/visits/soap_editor_test.dart`

### Implementation for User Story 2

- [X] T030 [US2] Implement `VisitRepository.saveSoapNote` with `p_expected_updated_at` handling per `contracts/visit-mutations.md` in `frontend/lib/features/visits/data/visit_repository.dart`
- [X] T031 [US2] Implement `VisitDocumentationNotifier` (load SOAP, track `updated_at`, save, stale refresh) in `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`
- [X] T032 [US2] Implement `SoapEditor` widget (S/O/A/P fields, saving/saved/stale states) in `frontend/lib/features/visits/presentation/widgets/soap_editor.dart`
- [X] T033 [US2] Integrate `SoapEditor` into `VisitDocumentationPage` gated by `visits.edit_soap` in `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`

**Checkpoint**: Spec test cases 5–6, 6b; acceptance criteria 3

---

## Phase 5: User Story 6 - Submit Visit and View Patient Visit History (Priority: P1)

**Goal**: Submit visit to complete linked appointment; paginated visit history on patient profile with permission-aware detail access

**Independent Test**: Submit visit with one SOAP section → visit and appointment `completed`; empty SOAP submit rejected; patient profile shows history metadata loaded from a fresh backend fetch (not stale local state); clinical roles open full detail

### Tests for User Story 6

- [X] T034 [P] [US6] Add `complete_visit`, `list_patient_visits`, and empty-SOAP rejection tests in `backend/tests/visit_medical_records_crud.sql`
- [X] T035 [P] [US6] Add manual appointment complete rejection test in `backend/tests/appointment_management_crud.sql`
- [X] T036 [P] [US6] Add unit tests for `VisitRepository.completeVisit`, `listPatientVisits`, and `getVisit` permission subsets in `frontend/test/unit/visits/visit_repository_complete_history_test.dart`
- [X] T037 [P] [US6] Add widget tests for `VisitSubmitDialog` in `frontend/test/widget/visits/visit_submit_dialog_test.dart`
- [X] T038 [P] [US6] Add widget tests for `PatientVisitHistorySection` metadata vs detail gating in `frontend/test/widget/visits/patient_visit_history_section_test.dart`

### Implementation for User Story 6

- [X] T039 [US6] Implement `VisitRepository.completeVisit`, `listPatientVisits`, and `getVisit` in `frontend/lib/features/visits/data/visit_repository.dart`
- [X] T040 [US6] Implement `VisitSubmitDialog` (confirm, submitting, success, SOAP-required error) in `frontend/lib/features/visits/presentation/widgets/visit_submit_dialog.dart`
- [X] T041 [US6] Wire submit action on `VisitDocumentationPage` in `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`
- [X] T042 [US6] Implement `PatientVisitHistorySection` with pagination and backend-first refresh on open/view in `frontend/lib/features/patients/presentation/widgets/patient_visit_history_section.dart`
- [X] T043 [US6] Replace `PatientVisitsPlaceholder` with `PatientVisitHistorySection` in `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`
- [X] T044 [US6] Implement `VisitDetailPage` (read-only clinical view from history) with backend-first fetch before rendering in `frontend/lib/features/visits/presentation/pages/visit_detail_page.dart`
- [X] T045 [US6] Gate `/visits/:visitId/detail` route to clinical visit permissions in `frontend/lib/app/router.dart`

**Checkpoint**: Spec test cases 11–13, 11b; acceptance criteria 7–8; SC-006, SC-008

---

## Phase 6: User Story 3 - Complete Specialty Form Fields (Priority: P2)

**Goal**: Render dynamic specialty fields from org JSON schema alongside SOAP; validate and persist in `specialty_form_json`

**Independent Test**: Seed schema in `app_settings` → fields render → save values → reload; no schema shows SOAP only; invalid values rejected

### Tests for User Story 3

- [X] T046 [P] [US3] Add `get_specialty_form_schema` and specialty JSON validation tests in `backend/tests/visit_medical_records_crud.sql`
- [X] T047 [P] [US3] Add unit tests for specialty schema load and save in `frontend/test/unit/visits/visit_repository_specialty_test.dart`
- [X] T048 [P] [US3] Add widget tests for dynamic field rendering and validation errors in `frontend/test/widget/visits/specialty_form_fields_test.dart`

### Implementation for User Story 3

- [X] T049 [US3] Implement `VisitRepository.getSpecialtyFormSchema` in `frontend/lib/features/visits/data/visit_repository.dart`
- [X] T050 [US3] Implement `SpecialtyFormFields` widget (text/number/select/checkbox from JSON schema) in `frontend/lib/features/visits/presentation/widgets/specialty_form_fields.dart`
- [X] T051 [US3] Integrate specialty fields into `VisitDocumentationNotifier` and `VisitDocumentationPage` in `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` and `visit_documentation_page.dart`

**Checkpoint**: Spec test case 7; acceptance criteria 3 (specialty JSON)

---

## Phase 7: User Story 4 - Manage Treatment Plans Within a Visit (Priority: P2)

**Goal**: Allow full visit editing (not SOAP-only) including treatment plans after submit/completion, with SOAP read-only-on-save UX that can return to edit mode

**Independent Test**: Save SOAP and verify it renders as read-only text with an explicit edit action; return to editor and resave; add/edit/remove treatment plans on an already submitted/completed visit opened from patient details; patient view and visit view both fetch latest data from backend first; changes persist after reload

### Tests for User Story 4

- [X] T052 [P] [US4] Add treatment plan create/update/archive tests in `backend/tests/visit_medical_records_crud.sql`
- [X] T053 [P] [US4] Add unit tests for treatment plan RPC wrappers in `frontend/test/unit/visits/visit_repository_treatment_plan_test.dart`
- [X] T054 [P] [US4] Add widget tests for add/edit/remove flows plus submitted/completed-visit edit enablement in `frontend/test/widget/visits/treatment_plan_list_test.dart`

### Implementation for User Story 4

- [X] T055 [US4] Implement `createTreatmentPlan`, `updateTreatmentPlan`, and `archiveTreatmentPlan` in `frontend/lib/features/visits/data/visit_repository.dart`
- [X] T056 [US4] Implement `TreatmentPlanList` widget (list, add form, edit, remove confirm) with support for editing submitted/completed visits in `frontend/lib/features/visits/presentation/widgets/treatment_plan_list.dart`
- [X] T057 [US4] Integrate treatment plans and full visit editing into `VisitDocumentationPage` gated by `visits.edit_soap` in `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`
- [X] T071 [US4] Update `SoapEditor` and `VisitDocumentationNotifier` so SOAP shows read-only text immediately after save, with an Edit action that restores the original editor widget in `frontend/lib/features/visits/presentation/widgets/soap_editor.dart` and `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`
- [X] T072 [US4] Enable opening submitted/completed visits from patient details in editable mode when user has `visits.edit_soap` in `frontend/lib/features/patients/presentation/widgets/patient_visit_history_section.dart` and `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`
- [X] T073 [US4] Ensure patient-detail visit history and visit documentation/detail pages trigger backend-first reload (`listPatientVisits`/`getVisit`) when opened so UI always starts from latest persisted data in `frontend/lib/features/patients/presentation/widgets/patient_visit_history_section.dart`, `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`, and `frontend/lib/features/visits/presentation/pages/visit_detail_page.dart`

**Checkpoint**: Spec test case 8; acceptance criteria 4

---

## Phase 8: User Story 5 - Upload and Download Visit Attachments (Priority: P2)

**Goal**: Upload PDF/DOCX/photos with progress; download with clinical full access or lab own-upload only

**Independent Test**: Upload one file of each allowed type → list shows metadata → download succeeds; disallowed type/size rejected; lab staff downloads own upload only

### Tests for User Story 5

- [X] T058 [P] [US5] Add attachment register, type/size rejection, and download authorization tests in `backend/tests/visit_medical_records_crud.sql`
- [X] T059 [P] [US5] Add lab staff cross-uploader download denial test in `backend/tests/visit_medical_records_rls.sql`
- [X] T060 [P] [US5] Add unit tests for `VisitAttachmentService` upload/register/download in `frontend/test/unit/visits/visit_attachment_service_test.dart`
- [X] T061 [P] [US5] Add widget tests for upload progress and error states in `frontend/test/widget/visits/visit_attachment_list_test.dart`

### Implementation for User Story 5

- [X] T062 [US5] Implement storage upload, `registerVisitAttachment`, and `getVisitAttachmentDownload` in `frontend/lib/features/visits/data/visit_attachment_service.dart`
- [X] T063 [US5] Implement `VisitAttachmentList` widget (list, upload picker, progress, download, type/size errors) in `frontend/lib/features/visits/presentation/widgets/visit_attachment_list.dart`
- [X] T064 [US5] Integrate attachments into `VisitDocumentationPage` with upload permission gating in `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`

**Checkpoint**: Spec test cases 9–10, 9b; acceptance criteria 5–6; SC-005

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: End-to-end acceptance, quickstart validation, regression, permission matrix alignment

- [ ] T065 [P] Add integration acceptance covering spec test cases 1–16 in `frontend/test/integration/visits/visit_medical_records_acceptance_test.dart`
- [ ] T066 [P] Add permission guard widget tests (no visit create/SOAP without grants) in `frontend/test/widget/visits/visit_permission_guards_test.dart`
- [ ] T067 Update `AppointmentStatusActions` widget tests for removed Complete action in `frontend/test/widget/appointments/appointment_status_actions_test.dart`
- [ ] T068 Run `specs/006-visit-medical-records/quickstart.md` verification and document operator notes
- [ ] T069 [P] Regression smoke: patients and appointments flows unchanged (`frontend/test/integration/patients/patient_management_acceptance_test.dart` and `frontend/test/integration/appointments/appointment_management_acceptance_test.dart` targeted subsets)
- [ ] T070 [P] Verify `docs/architecture/12-roadmap-phases.md` V1-5 scope wording aligns with visit-from-checked-in/in-progress (not completed appointment)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup + V1-1/V1-2/V1-3/V1-4 complete — **blocks all user stories**
- **User Stories (Phases 3–8)**: Depend on Foundational
- **Polish (Phase 9)**: Depends on Phases 3–8 (minimum Phases 3–5 for meaningful E2E)

### User Story Dependencies

| Story | Priority | Depends on             | Notes                                            |
| ----- | -------- | ---------------------- | ------------------------------------------------ |
| US1   | P1       | Foundational           | MVP — visit creation from appointment            |
| US2   | P1       | Foundational, US1 (UI) | SOAP on documentation page opened by US1         |
| US6   | P1       | Foundational, US2      | Submit requires at least one SOAP section saved  |
| US3   | P2       | Foundational, US2      | Specialty fields extend SOAP save on same page   |
| US4   | P2       | Foundational, US2      | Treatment plans on same documentation page       |
| US5   | P2       | Foundational, US1      | Attachments on visit; independent of SOAP submit |

### Recommended execution order (single developer)

1. Phase 1 → Phase 2
2. US1 (**MVP checkpoint** — create visit from appointment)
3. US2 → US6 (clinical close loop + patient history)
4. US3 → US4 → US5 (documentation enrichments)
5. Phase 9

### Parallel Opportunities

- Phase 1: T002, T003, T004 in parallel
- Phase 2: T006–T012, T014–T015 in parallel after T005
- Per story: all `[P]` test tasks before implementation tasks in that story
- US3, US4, US5 can proceed in parallel after US2 if staffed separately (same page — coordinate merges)

### Parallel Example: Foundational

```bash
# Sequential first:
T005 migration

# Then parallel:
T006 visit_medical_records_crud.sql
T007 visit_medical_records_rls.sql
T009 appointment_management_crud.sql updates
T011 permission_keys.dart
T012 permission_service.dart
T014 visit_attachment_service.dart scaffold
```

### Parallel Example: User Story 1

```bash
T017 create_visit SQL tests
T018 visit_repository_create_test.dart
T019 visit_create_dialog_test.dart
T021 visit_create_dialog.dart
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1 and Phase 2
2. Complete US1 (visit creation from eligible appointment)
3. **STOP and VALIDATE**: quickstart §3 steps 1–4; duplicate and ineligible rejection; doctor selection

### Incremental delivery

1. **Foundation**: Phase 1 + Phase 2
2. **MVP**: + US1 (create visit)
3. **Documentation core**: + US2 (SOAP save)
4. **Clinical close loop**: + US6 (submit + patient history)
5. **Rich documentation**: + US3 (specialty) + US4 (treatment plans) + US5 (attachments)
6. **Polish**: Phase 9 (acceptance + regression)

### Parallel team strategy

- **Developer A**: Phase 2 migration + backend tests (T005–T010)
- **Developer B**: Phase 2 Flutter scaffold + US1 (T011–T026)
- After US2: **C** → US6 history/submit, **D** → US3/US4, **E** → US5 attachments + Phase 9

---

## Notes

- Builds on V1-4 appointments — patch `update_appointment_status`; do not break booking/queue flows
- Appointment completion **only** via `complete_visit`; remove desk **Complete** button in US1
- `PatientVisitsPlaceholder` replaced in US6; do not delete file until US6 wires replacement
- Branch-scoped RLS on all visit domain tables
- Attachment allowed types: PDF, DOCX, JPEG, PNG; max 25 MB per file
- Lab staff: `visits.upload_attachment` only; download own uploads via `uploaded_by` match
- Preserve constitution: RPC/RLS/storage policy authority in PostgreSQL; Flutter gates UX only
- No billing, shifts, prescriptions, workflow automation, or AI in this feature
