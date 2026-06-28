---
description: "Task list for Visits Page Redesign (014)"
---

# Tasks: Visits Page Redesign (014)

**Input**: Design documents from `/specs/013-visits/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Backend SQL test updates are included per plan.md Phase B. Flutter unit test for `CatalogNameNormalizer` included per quickstart.md. No TDD-first test tasks per story unless noted.

**Organization**: Tasks grouped by user story for independent implementation and testing. Backend migration (Phase 2) blocks all Flutter user story work.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story label (US1–US6) on story-phase tasks only
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/supabase/migrations/`, `backend/tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the feature migration and verify branch context

- [X] T001 Create migration scaffold `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql` with header comments referencing `specs/013-visits/plan.md` `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql` with header comments referencing `specs/013-visits/plan.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database schema, RPCs, RLS, seeds, and backend verification — MUST complete before any Flutter user story

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Create `visit_clinical_notes` table (five text columns, 10k char CHECKs, audit columns, 1:1 `visit_id` UNIQUE) with RLS deny-direct-writes in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T003 [P] Create org catalog tables `medications`, `investigations`, `predefined_vital_signs` with unique `(organization_id, lower(trim(name)))` partial indexes and RLS in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T004 [P] Create `visit_vital_signs` and `visit_investigations` child tables with denormalized names, nullable catalog FKs, and RLS in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T005 Alter `treatment_plans`: add `medication_id` FK, migrate `start_date`/`end_date` → `duration`, drop date columns and end-after-start CHECK in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T006 Drop `soap_notes` table and remove specialty form JSON usage from visit-related functions in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T007 Implement `auth_internal.save_visit_documentation` with optimistic concurrency (`STALE_DOCUMENTATION`), partial save, and public wrapper in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T008 [P] Implement catalog RPCs (`search_medications`, `search_investigations`, `list_predefined_vital_signs`, `create_catalog_medication`, `create_catalog_investigation`, `create_predefined_vital_sign`) per `specs/013-visits/contracts/catalog-queries.md` in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T009 [P] Implement vital sign CRUD RPCs (`create_visit_vital_sign`, `update_visit_vital_sign`, `archive_visit_vital_sign`) per `specs/013-visits/contracts/visit-mutations.md` in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T010 [P] Implement investigation CRUD RPCs (`create_visit_investigation`, `update_visit_investigation`, `archive_visit_investigation`) per `specs/013-visits/contracts/visit-mutations.md` in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T011 Update `get_visit` to return `documentation`, `vital_signs`, `investigations` payload (remove `soap`/`specialty_form_json`) per `specs/013-visits/contracts/visit-queries.md` in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T012 Update `complete_visit` to require at least one non-empty clinical section (`DOCUMENTATION_REQUIRED_FOR_COMPLETE`) in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T013 Update `create_treatment_plan` and `update_treatment_plan` for required `p_duration`, optional `p_medication_id`, no date params (`DURATION_REQUIRED`) in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T014 Drop public wrappers `save_soap_note` and `get_specialty_form_schema`; grant EXECUTE on new RPCs in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T015 Seed dev medications (≥10), investigations (≥10), and predefined vital signs (BP, HR, Temp, RR, SpO2, Weight, Height) idempotently per org in `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`
- [X] T016 Rewrite clinical note, catalog, vital sign, investigation, duration migration, and `DOCUMENTATION_REQUIRED_FOR_COMPLETE` cases in `backend/tests/visit_medical_records_crud.sql`
- [X] T017 Update cross-branch denial RLS cases for new tables in `backend/tests/visit_medical_records_rls.sql`
- [X] T018 Run `backend/tests/run_visit_medical_records_tests.sh` and fix migration/RPC issues until all tests pass
- [X] T019 Update `VisitDetail` domain model and `visit_row_parsing.dart` for new `get_visit` payload shape in `frontend/lib/features/visits/domain/visit_detail.dart` and `frontend/lib/features/visits/domain/visit_row_parsing.dart`
- [X] T020 Update `getVisit` RPC wrapper to parse documentation, vital signs, and investigations in `frontend/lib/features/visits/data/visit_repository.dart`

**Checkpoint**: Foundation ready — backend migration applied and tests green; `get_visit` parsing ready for Flutter stories

---

## Phase 3: User Story 1 - Document Clinical Note Sections (Priority: P1) 🎯 MVP

**Goal**: Doctors can record Complaint, History, Examination, Diagnosis, and Plan with contextual hints, explicit save, and optimistic concurrency

**Independent Test**: Open an in-progress visit, enter text in one or more sections with hints visible, save, leave, and return to verify content persisted on documentation and detail views

### Implementation for User Story 1

- [X] T021 [P] [US1] Create `VisitClinicalNote` domain model in `frontend/lib/features/visits/domain/visit_clinical_note.dart`
- [X] T022 [P] [US1] Add `STALE_DOCUMENTATION` and `DOCUMENTATION_REQUIRED_FOR_COMPLETE` error mappings in `frontend/lib/features/visits/application/visit_rpc_messages.dart`
- [X] T023 [US1] Add `saveVisitDocumentation` RPC wrapper with `p_expected_updated_at` in `frontend/lib/features/visits/data/visit_repository.dart`
- [X] T024 [US1] Create `ClinicalNoteEditor` widget (five sections, hints for Complaint/Examination/Diagnosis/Plan) in `frontend/lib/features/visits/presentation/widgets/clinical_note_editor.dart`
- [X] T025 [US1] Update `VisitDocumentationNotifier` for clinical note load/save and stale-refresh handling in `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`
- [X] T026 [US1] Integrate `ClinicalNoteEditor` and Save action into `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`
- [X] T027 [US1] Gate clinical note edit/save by `visits.edit_soap` and branch scope in `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`

**Checkpoint**: User Story 1 fully functional — clinical note save, concurrency error, and permission gating work independently

---

## Phase 4: User Story 2 - Record Vital Signs (Priority: P1)

**Goal**: Doctors can add, edit, and remove vital signs using predefined options or custom normalized names with optional save-to-catalog prompt

**Independent Test**: Add multiple vital signs (predefined + custom), save, reload, edit one, remove another; verify list reflects changes

### Implementation for User Story 2

- [ ] T028 [P] [US2] Create `VisitVitalSign` domain model in `frontend/lib/features/visits/domain/visit_vital_sign.dart`
- [ ] T029 [P] [US2] Create shared `CatalogItem` domain model in `frontend/lib/features/visits/domain/catalog_item.dart`
- [ ] T030 [P] [US2] Implement `CatalogNameNormalizer.normalize` (trim, collapse spaces, capitalize first char) in `frontend/lib/features/visits/domain/catalog_name_normalizer.dart`
- [ ] T031 [P] [US2] Add unit tests for `CatalogNameNormalizer` in `frontend/test/unit/visits/catalog_name_normalizer_test.dart`
- [ ] T032 [US2] Add `listPredefinedVitalSigns`, vital sign create/update/archive, and `createPredefinedVitalSign` RPC wrappers in `frontend/lib/features/visits/data/visit_repository.dart`
- [ ] T033 [US2] Create `SaveToCatalogDialog` for optional org catalog save in `frontend/lib/features/visits/presentation/widgets/save_to_catalog_dialog.dart`
- [ ] T034 [US2] Create `VitalSignList` widget (predefined picker, custom entry, edit/remove) in `frontend/lib/features/visits/presentation/widgets/vital_sign_list.dart`
- [ ] T035 [US2] Integrate vital signs section and save-to-catalog flow into `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart` and `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`

**Checkpoint**: User Stories 1 and 2 work independently — vital signs CRUD with normalization and catalog prompt

---

## Phase 5: User Story 3 - Prescribe Treatments from Medication Catalog (Priority: P1)

**Goal**: Doctors can search medications while typing, select catalog items or enter custom names, and record dose/frequency/duration/note per treatment line

**Independent Test**: Type partial medication names, select catalog results, add custom medication, fill required fields, save, reload, and verify treatment lines persist

### Implementation for User Story 3

- [ ] T036 [P] [US3] Update `TreatmentPlanItem` domain model: add `medicationId`, remove start/end dates in `frontend/lib/features/visits/domain/treatment_plan_item.dart`
- [ ] T037 [US3] Add `searchMedications`, `createCatalogMedication`, and updated treatment plan create/update/archive RPC wrappers in `frontend/lib/features/visits/data/visit_repository.dart`
- [ ] T038 [US3] Create `CatalogAutocompleteField` with 300ms debounced search and free-text commit in `frontend/lib/features/visits/presentation/widgets/catalog_autocomplete_field.dart`
- [ ] T039 [US3] Rework `TreatmentPlanList` for medication autocomplete, duration-only, field validation, and save-to-catalog prompt in `frontend/lib/features/visits/presentation/widgets/treatment_plan_list.dart`
- [ ] T040 [US3] Integrate treatments section into `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart` and `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`

**Checkpoint**: User Stories 1–3 work — full treatment prescribing with catalog search and duration-only model

---

## Phase 6: User Story 4 - Order Required Investigations (Priority: P2)

**Goal**: Doctors can search investigations while typing, select catalog items or enter custom names, with optional note per line

**Independent Test**: Search investigations catalog, add catalog and custom investigations with notes, save, reload, and verify persistence

### Implementation for User Story 4

- [ ] T041 [P] [US4] Create `VisitInvestigation` domain model in `frontend/lib/features/visits/domain/visit_investigation.dart`
- [ ] T042 [US4] Add `searchInvestigations`, investigation create/update/archive, and `createCatalogInvestigation` RPC wrappers in `frontend/lib/features/visits/data/visit_repository.dart`
- [ ] T043 [US4] Create `InvestigationList` widget with autocomplete, note field, and save-to-catalog prompt in `frontend/lib/features/visits/presentation/widgets/investigation_list.dart`
- [ ] T044 [US4] Integrate investigations section into `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart` and `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart`

**Checkpoint**: User Story 4 independently testable — investigation ordering with catalog search

---

## Phase 7: User Story 5 - Complete Visit with Unchanged Attachments (Priority: P2)

**Goal**: Visit submission requires at least one clinical section; attachments and completion handoff behave as V1-5; post-submit documentation remains editable

**Independent Test**: Upload allowed attachment types, complete visit with at least one clinical section filled, verify appointment advances to completed; attempt submit with all sections empty and verify rejection

### Implementation for User Story 5

- [ ] T045 [US5] Update `VisitSubmitDialog` copy and validation for `DOCUMENTATION_REQUIRED_FOR_COMPLETE` in `frontend/lib/features/visits/presentation/widgets/visit_submit_dialog.dart`
- [ ] T046 [US5] Update complete-visit flow in `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` for new error code and post-submit edit allowance
- [ ] T047 [US5] Verify attachment upload/list/download unchanged in `frontend/lib/features/visits/data/visit_attachment_service.dart` and `frontend/lib/features/visits/presentation/widgets/visit_attachment_list.dart`
- [ ] T048 [US5] Confirm attachment regression cases pass in `backend/tests/visit_medical_records_crud.sql` after documentation redesign

**Checkpoint**: Visit completion and attachments verified — no regression from V1-5

---

## Phase 8: User Story 6 - View Visit Documentation on Detail Screen (Priority: P2)

**Goal**: Staff can view all documentation elements on visit detail in a scannable layout; edit permission enables inline editing; read-only for users without `visits.edit_soap`

**Independent Test**: Open visit detail for a populated visit; verify all sections render; on completed visit with edit permission, verify sections remain editable; without edit permission, verify read-only

### Implementation for User Story 6

- [ ] T049 [US6] Replace `VisitDetailPage` layout for clinical note, vital signs, treatments, investigations, and attachments in `frontend/lib/features/visits/presentation/pages/visit_detail_page.dart`
- [ ] T050 [US6] Rework `TreatmentPlanDisplay` for duration-only display (no dates) in `frontend/lib/features/visits/presentation/widgets/treatment_plan_display.dart`
- [ ] T051 [US6] Update read-only vs editable gating by permission on detail page in `frontend/lib/features/visits/presentation/providers/visit_detail_provider.dart`
- [ ] T052 [US6] Update `VisitDetailActions` for post-submit documentation edit navigation in `frontend/lib/features/visits/presentation/widgets/visit_detail_actions.dart`
- [ ] T053 [US6] Handle empty optional collections gracefully (no vital signs/treatments/investigations) in `frontend/lib/features/visits/presentation/pages/visit_detail_page.dart`

**Checkpoint**: Full read and edit experience on visit detail for new documentation model

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Remove legacy SOAP/specialty code, fix references, run automated checks, validate quickstart

- [ ] T054 [P] Delete `frontend/lib/features/visits/domain/soap_note.dart` and `frontend/lib/features/visits/domain/specialty_form_schema.dart`
- [ ] T055 [P] Delete `frontend/lib/features/visits/presentation/widgets/soap_editor.dart`, `specialty_form_fields.dart`, `specialty_form_read_only_section.dart`, and `frontend/lib/features/visits/presentation/providers/specialty_form_schema_provider.dart`
- [ ] T056 Remove all SOAP/specialty imports and dead code across `frontend/lib/features/visits/`
- [ ] T057 Finalize documentation page layout order: clinical sections → vital signs → treatments → investigations → attachments in `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`
- [ ] T058 [P] Run `dart analyze lib/features/visits` and fix analyzer issues
- [ ] T059 [P] Run `flutter test test/unit/visits/` and `flutter test test/widget/visits/` and fix failures
- [ ] T060 Execute manual regression from `specs/013-visits/quickstart.md` (appointment create/open visit, patient visit history metadata, catalog search SC-002)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — **BLOCKS all user stories**
- **User Stories (Phases 3–8)**: All depend on Foundational completion
  - P1 stories (US1, US2, US3) should complete before or in parallel with P2 stories
  - US5 depends on US1 (complete validation); US6 depends on US1–US4 (display all sections)
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

| Story | Priority | Depends On | Independent Test |
| ----- | -------- | ---------- | ---------------- |
| US1 Clinical note | P1 | Foundational | Save/reload five sections with hints |
| US2 Vital signs | P1 | Foundational, US1 (shared page) | Add/edit/remove predefined + custom vital signs |
| US3 Treatments | P1 | Foundational, US2 (`CatalogNameNormalizer`, `SaveToCatalogDialog`) | Medication search, custom entry, duration validation |
| US4 Investigations | P2 | Foundational, US3 (`CatalogAutocompleteField`) | Investigation search and custom entry |
| US5 Complete + attachments | P2 | US1 (documentation required on submit) | Submit with/without content; attachment regression |
| US6 Visit detail view | P2 | US1–US4 (all sections to display) | Detail layout, read-only vs editable |

### Within Each User Story

- Domain models before repository wrappers
- Repository wrappers before widgets
- Widgets before page integration
- Notifier updates alongside page integration

### Parallel Opportunities

- **Phase 2**: T003, T004, T008, T009, T010 can run in parallel (different migration sections — coordinate single file merges)
- **Phase 3**: T021, T022 in parallel
- **Phase 4**: T028, T029, T030, T031 in parallel
- **Phase 5**: T036 parallel with early T037 prep
- **Phase 6**: T041 parallel before T042
- **Phase 9**: T054, T055, T058, T059 in parallel
- **Cross-story**: After Foundational, backend-heavy verification (T018) can overlap with Flutter US1 start (T019–T020 then US1)

---

## Parallel Example: User Story 2

```bash
# Launch domain + normalizer work together:
Task T028: "Create VisitVitalSign domain model in frontend/lib/features/visits/domain/visit_vital_sign.dart"
Task T029: "Create CatalogItem domain model in frontend/lib/features/visits/domain/catalog_item.dart"
Task T030: "Implement CatalogNameNormalizer in frontend/lib/features/visits/domain/catalog_name_normalizer.dart"
Task T031: "Add unit tests in frontend/test/unit/visits/catalog_name_normalizer_test.dart"

# Then sequential integration:
Task T034: "Create VitalSignList widget"
Task T035: "Integrate into visit_documentation_page.dart and notifier"
```

---

## Parallel Example: Foundational Backend

```bash
# After T002 (clinical notes table), launch catalog + child tables in parallel:
Task T003: "Create org catalog tables in migration"
Task T004: "Create visit_vital_signs and visit_investigations in migration"

# After base tables, launch RPC groups in parallel:
Task T008: "Catalog search/create RPCs"
Task T009: "Vital sign CRUD RPCs"
Task T010: "Investigation CRUD RPCs"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002–T020) — **critical blocker**
3. Complete Phase 3: User Story 1 (T021–T027)
4. **STOP and VALIDATE**: Clinical note save, concurrency, permissions on documentation page
5. Demo MVP before vital signs/treatments

### Incremental Delivery

1. Setup + Foundational → backend ready, `get_visit` parsing in Flutter
2. US1 → clinical note MVP
3. US2 → vital signs
4. US3 → treatments (core consultation workflow complete for P1)
5. US4 → investigations
6. US5 → submit + attachment regression
7. US6 → detail screen read/edit
8. Polish → remove legacy, analyze, test, quickstart validation

### Parallel Team Strategy

With multiple developers after Foundational (T018 green):

- **Developer A**: US1 + US6 detail layout (clinical note display)
- **Developer B**: US2 vital signs + shared `SaveToCatalogDialog`
- **Developer C**: US3 treatments + `CatalogAutocompleteField` (then US4 investigations)
- **Any**: US5 submit/attachments once US1 lands
- **Final**: Polish phase together (T054–T060)

---

## Notes

- All mutations via RPC only; no direct table writes from Flutter
- Keep `visits.edit_soap` permission key for all documentation mutations (research R9)
- Custom names normalized client-side before save and catalog prompt (FR-006a)
- Legacy SOAP/specialty data intentionally discarded — no dual-read paths
- Treatment lines use `duration` text only; no start/end dates in UI or API
- Attachment behavior must remain unchanged from V1-5 (FR-009)
- Debounce catalog search 300ms per research R8 and SC-002
