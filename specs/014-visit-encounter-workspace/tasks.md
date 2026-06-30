# Tasks: Visit Encounter Workspace (014)

**Input**: Design documents from `/specs/014-visit-encounter-workspace/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included per plan.md Technical Context — backend SQL CRUD/RLS suites for P3 RPCs; Flutter unit/widget tests for BMI, step badges, regrouping, safety rail, and workspace modes. No TDD ordering required.

**Organization**: Tasks grouped by user story (P1 → P2 → P3) for independent, priority-sequenced delivery.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story label (US1–US8) on story-phase tasks only

## Path Conventions

- **Flutter**: `frontend/lib/features/visits/`, `frontend/test/`
- **Backend**: `backend/supabase/migrations/`, `backend/tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare test scaffolding and confirm 013 foundation before encounter workspace work

- [X] T001 Create visit encounter workspace test directories `frontend/test/unit/visits/` and `frontend/test/widget/visits/`
- [X] T002 [P] Confirm 013 visit routes and permission gating unchanged in `frontend/lib/app/router.dart` and `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Domain primitives required by all user stories — MUST complete before US1–US8

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Create `EncounterPhase` enum, ordering, and completion model in `frontend/lib/features/visits/domain/encounter_phase.dart`
- [X] T004 [P] Create pure BMI derivation helpers in `frontend/lib/features/visits/domain/bmi.dart`
- [X] T005 [P] Add BMI unit tests in `frontend/test/unit/visits/bmi_test.dart`

**Checkpoint**: Foundation ready — user story implementation can begin (P1 stories first)

---

## Phase 3: User Story 1 — Surface Encounter Metadata in a Visit Header (Priority: P1) 🎯 MVP

**Goal**: Display visit date/time, attending doctor, status, and visit type (when present) in a persistent header on documentation and detail screens

**Independent Test**: Open in-progress and completed visits; confirm header values match the underlying `VisitDetail` record; confirm access denial for users without branch clinical read permission

### Implementation for User Story 1

- [X] T006 [P] [US1] Create `encounter_header.dart` widget reading `VisitDetail` metadata in `frontend/lib/features/visits/presentation/widgets/encounter_header.dart`
- [X] T007 [US1] Mount `EncounterHeader` at the top of `frontend/lib/features/visits/presentation/pages/visit_documentation_page.dart`
- [X] T008 [US1] Mount `EncounterHeader` at the top of `frontend/lib/features/visits/presentation/pages/visit_detail_page.dart`

**Checkpoint**: US1 independently testable — header visible on both screens without other redesign changes

---

## Phase 4: User Story 2 — Regroup Documentation into Five Encounter Phases (Priority: P1)

**Goal**: Re-host all existing 013 content under Context, Subjective, Objective, Assessment, and Plan; split the monolithic clinical-note card; co-locate Examination↔Vitals and Plan↔Treatments/Investigations/Attachments

**Independent Test**: Open a visit with populated 013 data; confirm every field appears under exactly one phase, none lost or duplicated; saves use existing 013 RPCs and optimistic concurrency

### Implementation for User Story 2

- [X] T009 [P] [US2] Create Context phase shell (visit type, patient snapshot) in `frontend/lib/features/visits/presentation/widgets/encounter_phase_context.dart`
- [X] T010 [P] [US2] Create Subjective phase wrapping Complaint + History sections from `clinical_note_editor.dart` in `frontend/lib/features/visits/presentation/widgets/encounter_phase_subjective.dart`
- [X] T011 [P] [US2] Create Objective phase co-locating `vital_sign_list.dart` and Examination section plus BMI chip in `frontend/lib/features/visits/presentation/widgets/encounter_phase_objective.dart`
- [X] T012 [P] [US2] Create Assessment phase with Diagnosis section in `frontend/lib/features/visits/presentation/widgets/encounter_phase_assessment.dart`
- [X] T013 [P] [US2] Create Plan phase co-locating Plan prose, `treatment_plan_list.dart`, `investigation_list.dart`, and `visit_attachment_list.dart` in `frontend/lib/features/visits/presentation/widgets/encounter_phase_plan.dart`
- [X] T014 [US2] Replace `visit_documentation_page.dart` body with five phase canvases (single-page layout acceptable before US4 stepper)
- [X] T015 [US2] Recompose `visit_detail_page.dart` body with the same five-phase read-only grouping (collapsible groups per FR-009)
- [X] T016 [P] [US2] Add widget test asserting all 013 fields reachable under exactly one phase in `frontend/test/widget/visits/encounter_phase_regrouping_test.dart`

**Checkpoint**: US2 independently testable — regrouped layout with header (US1) and no stepper required

---

## Phase 5: User Story 3 — Persistent Patient-Safety Context While Documenting (Priority: P1)

**Goal**: Show a persistent, read-only safety surface on every phase including Plan; degrade gracefully to free-text alerts/empty state when no structured data exists (P1)

**Independent Test**: Navigate every documentation phase including Plan; confirm safety rail visible, read-only, and non-blocking; confirm degraded alerts line when no structured data

### Implementation for User Story 3

- [X] T017 [P] [US3] Create `patient_safety_rail.dart` with degraded alerts/empty-state sections in `frontend/lib/features/visits/presentation/widgets/patient_safety_rail.dart`
- [X] T018 [US3] Mount `PatientSafetyRail` persistently across all phase canvases in documentation and detail views
- [X] T019 [P] [US3] Add widget test confirming safety rail presence on every phase in `frontend/test/widget/visits/patient_safety_rail_test.dart`

**Checkpoint**: P1 MVP complete (US1 + US2 + US3) — shippable frontend-only slice per quickstart.md P1 validation

---

## Phase 6: User Story 4 — Non-Linear Stepper Workspace with Review & Submit (Priority: P2)

**Goal**: Default guided workspace with step rail, active-phase-only canvas, completion badges, sticky save/nav footer, and Review step that doubles as detail view

**Independent Test**: Confirm only active phase renders in center; jump Context→Plan non-linearly; badges show empty/has-content/error; Review shows summary + edit links + submit enforcing ≥1 clinical section rule

### Implementation for User Story 4

- [X] T020 [P] [US4] Create `encounter_step_provider.dart` deriving empty/hasContent/error badges from `VisitDetail` + draft in `frontend/lib/features/visits/presentation/providers/encounter_step_provider.dart`
- [X] T021 [P] [US4] Create `encounter_workspace_shell.dart` three-region layout with responsive collapse in `frontend/lib/features/visits/presentation/widgets/encounter_workspace_shell.dart`
- [X] T022 [P] [US4] Create `encounter_step_rail.dart` with non-linear step navigation and badges in `frontend/lib/features/visits/presentation/widgets/encounter_step_rail.dart`
- [X] T023 [P] [US4] Create `encounter_sticky_footer.dart` reusing per-section save status in `frontend/lib/features/visits/presentation/widgets/encounter_sticky_footer.dart`
- [X] T024 [P] [US4] Create `encounter_review.dart` read-only summary with per-section edit links and submit in `frontend/lib/features/visits/presentation/widgets/encounter_review.dart`
- [X] T025 [US4] Wire `visit_documentation_page.dart` body through `EncounterWorkspaceShell` (guided mode default)
- [X] T026 [US4] Wire `visit_detail_page.dart` body to `EncounterReview` read-only view
- [X] T027 [P] [US4] Add widget tests for workspace shell, non-linear navigation, and step badges in `frontend/test/widget/visits/encounter_workspace_test.dart`
- [X] T028 [P] [US4] Add unit tests for `encounter_step_provider.dart` badge logic in `frontend/test/unit/visits/encounter_step_provider_test.dart`

**Checkpoint**: US4 independently testable — full stepper workspace with P1 content and safety rail

---

## Phase 7: User Story 5 — Expert Single-Page Mode (Priority: P2)

**Goal**: Toggle between guided stepper and expert accordion mode; preserve in-progress content and save state across toggles

**Independent Test**: Toggle modes mid-edit; document and submit in expert mode; confirm same data appears in guided stepper

### Implementation for User Story 5

- [X] T029 [P] [US5] Create `workspace_mode_provider.dart` with guided default and best-effort local persistence in `frontend/lib/features/visits/presentation/providers/workspace_mode_provider.dart`
- [X] T030 [P] [US5] Create `expert_mode_accordion.dart` rendering five collapsible phase sections in `frontend/lib/features/visits/presentation/widgets/expert_mode_accordion.dart`
- [X] T031 [US5] Integrate guided/expert toggle into `encounter_workspace_shell.dart` preserving draft and save state (FR-019)
- [X] T032 [P] [US5] Add widget test for mode toggle data preservation in `frontend/test/widget/visits/expert_mode_test.dart`

**Checkpoint**: P2 complete (US4 + US5) — shippable frontend-only workspace per quickstart.md P2 validation

---

## Phase 8: User Story 6 — Structured Patient Safety Records (Priority: P3)

**Goal**: Patient-level allergies, current medications, and chronic conditions editable from Context phase; structured data powers the safety rail across future visits

**Independent Test**: Add safety records on one visit; open a different visit for the same patient and confirm records appear in the rail without re-entry; stale concurrent writes rejected

### Backend for User Story 6

- [X] T033 [US6] Create additive migration with `patient_allergies`, `patient_medications`, `patient_chronic_conditions` tables, RLS, and indexes in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [X] T034 [US6] Implement `get_patient_safety_context` and patient safety CRUD RPCs (`create/update/archive_patient_allergy`, medication, chronic_condition) per `contracts/patient-safety.md` in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [X] T035 [P] [US6] Add patient safety CRUD SQL tests in `backend/tests/visit_encounter_workspace_crud.sql`
- [X] T036 [P] [US6] Add patient safety cross-branch/cross-org RLS denial tests in `backend/tests/visit_encounter_workspace_rls.sql`

### Frontend for User Story 6

- [X] T037 [P] [US6] Create `patient_safety.dart` domain models in `frontend/lib/features/visits/domain/patient_safety.dart`
- [X] T038 [P] [US6] Create `patient_safety_provider.dart` calling `get_patient_safety_context` in `frontend/lib/features/visits/presentation/providers/patient_safety_provider.dart`
- [X] T039 [US6] Add patient safety CRUD repository wrappers in `frontend/lib/features/visits/data/visit_repository.dart`
- [X] T040 [US6] Add allergy, current-medication, and chronic-condition editors to `encounter_phase_context.dart` reusing `catalog_autocomplete_field.dart` and `save_to_catalog_dialog.dart`
- [X] T041 [US6] Upgrade `patient_safety_rail.dart` to render structured allergies/meds/conditions and last prior-visit vitals from `patient_safety_provider.dart`

**Checkpoint**: US6 independently testable — structured safety records persist and surface across visits

---

## Phase 9: User Story 7 — Structured Diagnosis Codes and Structured Plan Outputs (Priority: P3)

**Goal**: Org-scoped coded diagnosis alongside free-text Assessment; structured follow-up, instructions, referral, and certificate-as-data in Plan phase

**Independent Test**: Attach coded diagnosis; set all plan outputs; reload and confirm persistence on detail/Review view; free-text-only diagnosis never blocked

### Backend for User Story 7

- [X] T042 [US7] Add `diagnosis_codes`, `visit_diagnosis_codes`, `visit_plan_details` tables and idempotent diagnosis-code seeds to `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [X] T043 [US7] Implement `search_diagnosis_codes`, `create_catalog_diagnosis_code`, `create_visit_diagnosis_code`, `archive_visit_diagnosis_code` per `contracts/diagnosis-catalog.md` in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [X] T044 [US7] Implement `save_visit_plan_details` with `STALE_PLAN_DETAILS` optimistic concurrency per `contracts/visit-plan-and-objective.md` in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [X] T045 [US7] Extend `auth_internal.get_visit` with additive `diagnosis_codes` and `plan_details` keys per `contracts/get-visit-extensions.md` in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [X] T046 [P] [US7] Add diagnosis catalog and plan-details CRUD tests in `backend/tests/visit_encounter_workspace_crud.sql`

### Frontend for User Story 7

- [X] T047 [P] [US7] Create `visit_diagnosis_code.dart` and `visit_plan_details.dart` domain models in `frontend/lib/features/visits/domain/`
- [X] T048 [P] [US7] Create `diagnosis_autocomplete_field.dart` thin wrapper over `catalog_autocomplete_field.dart` in `frontend/lib/features/visits/presentation/widgets/diagnosis_autocomplete_field.dart`
- [X] T049 [US7] Extend `visit_detail.dart` and `visit_row_parsing.dart` to parse `diagnosis_codes` and `plan_details` defensively (absent → empty/null)
- [X] T050 [US7] Add diagnosis search/create and `save_visit_plan_details` wrappers in `frontend/lib/features/visits/data/visit_repository.dart`
- [X] T051 [US7] Extend `visit_documentation_notifier.dart` with plan-details and visit diagnosis-code save/archive flows
- [X] T052 [US7] Add `STALE_PLAN_DETAILS` error copy in `frontend/lib/features/visits/application/visit_rpc_messages.dart`
- [X] T053 [US7] Add coded-diagnosis UI to `encounter_phase_assessment.dart` (optional alongside free-text)
- [X] T054 [US7] Add structured plan output fields (follow-up, instructions, referral, certificate dates/reason) to `encounter_phase_plan.dart`
- [X] T055 [US7] Render structured diagnosis codes and plan outputs in `encounter_review.dart` and detail view

**Checkpoint**: US7 independently testable — coded diagnosis and plan outputs persist and display on Review

---

## Phase 10: User Story 8 — Objective Enrichments (Priority: P3)

**Goal**: Vitals measurement timestamp, pain score via predefined vital sign, investigation result capture on later visits; BMI already derived in US2

**Independent Test**: Record pain score and vital `measured_at`; on a follow-up visit record a result against a prior investigation; confirm BMI auto-derives when Height + Weight present

### Backend for User Story 8

- [ ] T056 [US8] ALTER `visit_vital_signs` (+`measured_at`) and `visit_investigations` (+`result`, `result_recorded_at`, `result_recorded_by`) in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [ ] T057 [US8] Extend `create_visit_vital_sign` and `update_visit_vital_sign` with optional `p_measured_at` in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [ ] T058 [US8] Implement `record_investigation_result` RPC per `contracts/visit-plan-and-objective.md` in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [ ] T059 [US8] Seed idempotent "Pain Score" predefined vital sign per organization in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [ ] T060 [US8] Extend `get_visit` vital_signs and investigations payloads with `measured_at` / `result` / `result_recorded_at` in `backend/supabase/migrations/20260701120000_visit_encounter_workspace.sql`
- [ ] T061 [P] [US8] Add vital `measured_at` and investigation result CRUD tests in `backend/tests/visit_encounter_workspace_crud.sql`

### Frontend for User Story 8

- [ ] T062 [P] [US8] Extend `visit_vital_sign.dart` with `measuredAt` and `visit_investigation.dart` with `result`/`resultRecordedAt` in `frontend/lib/features/visits/domain/`
- [ ] T063 [US8] Extend `visit_repository.dart` and vital/investigation list widgets for `measured_at` capture and `record_investigation_result`
- [ ] T064 [US8] Add pain-score entry (predefined vital sign), measurement-time picker, and investigation result capture UI to `encounter_phase_objective.dart`
- [ ] T065 [US8] Display investigation results and vital `measured_at` on `encounter_review.dart` and detail view

**Checkpoint**: P3 complete — all structured enrichments functional per quickstart.md P3 validation

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: Regression, test runner integration, and constitution compliance verification

- [ ] T066 Extend `backend/tests/run_visit_medical_records_tests.sh` to include `visit_encounter_workspace_crud.sql` and `visit_encounter_workspace_rls.sql`
- [ ] T067 [P] Run `dart analyze` on `frontend/lib/features/visits/` and fix any new issues
- [ ] T068 [P] Run `flutter test test/unit/visits test/widget/visits` and resolve failures
- [ ] T069 Run `backend/tests/run_visit_medical_records_tests.sh` and resolve failures
- [ ] T070 Verify SC-005 (100% 013 fields reachable, none duplicated), SC-008 (attachment regression), and submission rules unchanged per `specs/014-visit-encounter-workspace/quickstart.md`
- [ ] T071 Verify responsive collapse: step rail and safety rail collapse on narrow windows without hiding active phase or safety affordance (FR-020) in `encounter_workspace_shell.dart`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — **BLOCKS all user stories**
- **US1–US3 (Phases 3–5, P1)**: Depend on Foundational; sequential US1 → US2 → US3 recommended; **no backend change**
- **US4–US5 (Phases 6–7, P2)**: Depend on US2 (phase canvases) and US3 (safety rail); **no backend change**
- **US6–US8 (Phases 8–10, P3)**: Depend on P1/P2 presentation shell; share one migration file — execute backend tasks T033–T034 before T042–T060 in order within the migration
- **Polish (Phase 11)**: Depends on all desired user stories complete

### User Story Dependencies

| Story | Priority | Depends on | Backend? |
| ----- | -------- | ---------- | -------- |
| US1 | P1 | Foundational | No |
| US2 | P1 | US1 (header mounts first) | No |
| US3 | P1 | US2 (rail mounts on phase canvases) | No |
| US4 | P2 | US2, US3 | No |
| US5 | P2 | US4 (workspace shell) | No |
| US6 | P3 | US3 (rail upgrade), Context phase | Yes |
| US7 | P3 | US2 Assessment/Plan phases, US4 Review | Yes |
| US8 | P3 | US2 Objective phase | Yes |

### Within Each User Story

- Backend migration/RPCs before frontend repository integration (P3)
- Domain models before providers/widgets that consume them
- Phase canvas widgets before page-level wiring
- Story checkpoint before moving to next priority

### Parallel Opportunities

- **Phase 2**: T004 and T005 parallel after T003
- **US2**: T009–T013 (five phase widgets) fully parallel
- **US4**: T020–T024 (providers + shell widgets) parallel before T025 wiring
- **US6 backend**: T035 and T036 parallel after T034
- **US6 frontend**: T037 and T038 parallel before T039
- **US7**: T047 and T048 parallel; T053 and T054 parallel after notifier work
- **US8**: T062 parallel with backend T061 after migration applied
- **Polish**: T067 and T068 parallel

---

## Parallel Example: User Story 2

```bash
# Launch all five phase canvas widgets together:
Task T009: encounter_phase_context.dart
Task T010: encounter_phase_subjective.dart
Task T011: encounter_phase_objective.dart
Task T012: encounter_phase_assessment.dart
Task T013: encounter_phase_plan.dart

# Then wire pages sequentially:
Task T014: visit_documentation_page.dart
Task T015: visit_detail_page.dart
```

## Parallel Example: User Story 6 (P3)

```bash
# Backend tests in parallel after RPCs land:
Task T035: visit_encounter_workspace_crud.sql (safety section)
Task T036: visit_encounter_workspace_rls.sql

# Frontend models in parallel:
Task T037: patient_safety.dart
Task T038: patient_safety_provider.dart
```

---

## Implementation Strategy

### MVP First (P1: US1 + US2 + US3)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phases 3–5: US1 → US2 → US3
4. **STOP and VALIDATE** against quickstart.md P1 checklist
5. Deploy/demo — zero backend migration required

### Incremental Delivery

1. **P1 slice** (US1–US3): Header + regrouping + degraded safety rail → shippable calm layout
2. **P2 slice** (US4–US5): Stepper workspace + expert mode → full workspace UX
3. **P3 slice** (US6–US8): One additive migration + structured data → complete feature

### Parallel Team Strategy

With multiple developers after Foundational:

- **Developer A**: US1 → US2 phase widgets
- **Developer B**: US3 safety rail (after US2 canvases exist)
- After P1 checkpoint: **Developer A** US4 workspace shell; **Developer B** US5 expert mode
- After P2 checkpoint: **Developer A** US6 safety backend+frontend; **Developer B** US7 diagnosis/plan; **Developer C** US8 objective enrichments (coordinate on shared migration file)

---

## Notes

- Reuse 013 child widgets unchanged — only re-host under new phase canvases
- P3 uses a **single** migration file; backend tasks T033–T060 append to the same file in dependency order
- `get_patient_safety_context` is patient-scoped (separate from `get_visit` extension)
- BMI is client-derived only — never stored or sent to backend
- Certificate issuance records structured data only — no document generation
- Allergy records have substance + reaction only — **no severity field**
- Preserve layer boundaries: Flutter presentation/orchestration; PostgreSQL authority for schema, RLS, audit, transactional saves
