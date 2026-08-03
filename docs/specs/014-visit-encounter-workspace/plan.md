# Implementation Plan: Visit Encounter Workspace (014)

**Branch**: `014-visit-encounter-workspace` | **Date**: 2026-06-30 | **Spec**: `docs/specs/014-visit-encounter-workspace/spec.md`

**Input**: Feature specification from `docs/specs/014-visit-encounter-workspace/spec.md`

## Summary

Redesign the feature-013 visit documentation/detail pages into a clinically-sequenced **encounter workspace**. Re-cut existing 013 content along five encounter phases (Context → Subjective → Objective → Assessment → Plan) plus a Review step, splitting the monolithic clinical-note card (Complaint/History → Subjective, Examination → Objective beside Vital signs, Diagnosis → Assessment, Plan → Plan beside Treatments/Investigations/Attachments). Surface the encounter metadata already present on the visit (date/time, doctor, status, type) in a header, and add a **persistent, read-only patient-safety surface** (allergies · current meds · chronic conditions · last vitals) visible on every phase including prescribing. Default to a **non-linear stepper workspace** (freely clickable steps, completion/validation badges, sticky save/nav footer, Review-as-detail) with an **expert single-page accordion mode**. Add structured enrichments: patient-level safety records, an org-scoped coded-diagnosis catalog, structured Plan outputs (follow-up, instructions, referral, certificate-as-data), derived BMI, pain score, vitals measurement timestamp, and investigation-result capture.

The feature is **presentational + additive**: visit lifecycle, permissions (`visits.edit_soap`), optimistic concurrency, branch scope, and attachments are unchanged from V1-5/013. Delivery is priority-sequenced inside this one feature: **P1** (US1–US3, frontend-only on the 013 schema), **P2** (US4–US5 workspace/modes, frontend-only), **P3** (US6–US8, one additive backend migration + new RPCs + `get_visit` payload extension).

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase; PL/pgSQL in `auth_internal` schema with `public` RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK (RPC + Storage), Riverpod, GoRouter; existing visits feature (`VisitRepository`, `AppRpcInvoker`, `CatalogAutocompleteField`, `CatalogNameNormalizer`, `SaveToCatalogDialog`, `visit_documentation_notifier`), `core/ui` design system (`AppButton`, `AppAlert`, `AppToast`, spacing tokens), patient providers (`VisitPatientBasicInfoCard` / patient detail)

**Storage**: P1/P2 reuse existing 013 tables only (no schema change). P3 adds one migration: patient-level `patient_allergies`, `patient_medications`, `patient_chronic_conditions`; org catalog `diagnosis_codes`; visit-level `visit_diagnosis_codes`, `visit_plan_details` (1:1); ALTER `visit_vital_signs` (+`measured_at`), `visit_investigations` (+`result`, `result_recorded_at`, `result_recorded_by`). All follow shared audit/soft-delete conventions. No table is dropped.

**Testing**: New SQL CRUD + RLS tests under `backend/tests/` (extend the visit medical-records test runner) for P3 RPCs; Flutter widget/unit tests under `frontend/test/**/visits/` for the workspace shell, step-completion logic, regrouping, safety surface, expert mode, BMI derivation, and new domain models/normalizers; `dart analyze` on the visits feature

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile); responsive collapse for narrow windows

**Project Type**: Desktop client + Supabase PostgreSQL (single additive migration for P3, RLS, RPC, no Storage change); no custom API server; no AI

**Performance Goals**: Catalog/diagnosis/safety searches visible within the existing 300ms debounce under normal LAN (SC re-use from 013); active-phase canvas renders ~1/5 of prior fields (SC-001); `get_visit` remains a single round-trip even with the additive payload; safety surface present on 100% of phases (SC-002); quick follow-up reaches Plan in one navigation action (SC-004)

**Constraints**: Branch-scoped RLS; mutations via RPC only; optimistic concurrency on clinical note and on `visit_plan_details`; patient-level safety records scoped via patient → org/branch; coded-diagnosis reuses 013 catalog-search/normalize/save-to-catalog machinery (no new interaction patterns); certificate issuance is data-only (no document generation); BMI derived client-side (never stored); no lifecycle change; no AI dependency; online-only save semantics (no offline drafts)

**Scale/Scope**: 1 additive migration (P3 only); ~6 new tables + 2 ALTERs; ~12 new/updated RPC families; `get_visit` payload extension; ~10–15 new Flutter widgets (workspace shell, step rail, 5 phase canvases + review, safety rail, encounter header, expert accordion, sticky footer), ~6 new domain models, repository additions; replace the two visit pages' bodies while preserving all 013 child widgets

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope fits small-to-mid-size multi-branch clinics; hospital CPOE/order-sets, enterprise formularies, and licensed external terminologies are explicitly out of scope (spec Business Context + Assumptions)
- [x] Simple operational model preserved: no microservices, queues, Kubernetes, or custom primary backend service; redesign is Flutter presentation + one additive Postgres migration
- [x] Layer ownership explicit: Flutter owns presentation/navigation/BMI derivation/orchestration; Supabase exposes RPC/Storage/authz; PostgreSQL owns schema, validation, RLS, audit, transactional saves; AI not involved
- [x] Protected writes via `auth_internal` SECURITY DEFINER RPCs + `public` wrappers; reads RLS-scoped; catalog growth via the existing optional doctor save-to-catalog prompt, not an admin UI
- [x] Security: authenticated, tenant-scoped (`jwt_organization_id()`), branch-scoped (`assert_visit_branch_scope` / patient org+branch), permission-gated (`visits.edit_soap`); audit_log entries; soft delete on all new tables
- [x] No AI dependency; documentation, workspace, and safety surface fully manual (Principle V); degrades to clear errors offline

### Post-Design Re-Check

- [x] Visit lifecycle, `complete_visit` clinical-note non-empty check, and appointment handoff unchanged (no new lifecycle; submission rule reused at Review)
- [x] Attachment authorization and behavior unchanged (re-presented under Plan phase only)
- [x] Optimistic concurrency reused for clinical note; added analogously for `visit_plan_details` (`STALE_PLAN_DETAILS`); patient safety records use per-row `updated_at` checks
- [x] New catalog (`diagnosis_codes`) search is read-only SELECT under org RLS; inserts gated by `visits.edit_soap` via the save-to-catalog path
- [x] No new custom backend service; no AI write paths; no hard deletes; no broadened clinical access (all new ops gated by existing `visits.edit_soap`)
- [x] Additive only: no 013 table dropped, no 013 RPC removed; `get_visit` payload extended (new keys, existing keys unchanged) so 013 clients keep working

No constitution violations — Complexity Tracking is omitted.

## Project Structure

### Documentation (this feature)

```text
`docs/specs/014-visit-encounter-workspace/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── patient-safety.md
│   ├── diagnosis-catalog.md
│   ├── visit-plan-and-objective.md
│   └── get-visit-extensions.md
├── checklists/
│   └── requirements.md  # from /speckit-specify
└── tasks.md             # /speckit-tasks (NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260701NNNNNN_visit_encounter_workspace.sql   # P3 only: additive tables, ALTERs, RPCs, get_visit extension, seeds
└── tests/
    ├── visit_encounter_workspace_crud.sql             # new: safety records, diagnosis codes, plan details, results
    ├── visit_encounter_workspace_rls.sql              # new: cross-branch / cross-org denial for new tables
    └── run_visit_medical_records_tests.sh             # extend runner to include the above

frontend/lib/features/visits/
├── domain/
│   ├── encounter_phase.dart            # new: phase enum + ordering + completion model
│   ├── patient_safety.dart             # new: allergy / current med / chronic condition models
│   ├── visit_diagnosis_code.dart       # new
│   ├── visit_plan_details.dart         # new: follow-up, instructions, referral, certificate (data only)
│   ├── bmi.dart                        # new: pure derivation from height/weight vitals
│   ├── visit_detail.dart               # extend: + safety, diagnosis codes, plan details, vital measured_at, investigation result
│   ├── visit_vital_sign.dart           # extend: + measuredAt
│   └── visit_investigation.dart        # extend: + result, resultRecordedAt
├── data/
│   └── visit_repository.dart           # add: patient-safety CRUD, diagnosis search/create, plan-details upsert, record-result wrappers
├── application/
│   └── visit_rpc_messages.dart         # add: STALE_PLAN_DETAILS and new error copy
└── presentation/
    ├── pages/
    │   ├── visit_documentation_page.dart   # replace body with workspace shell (modes), keep route/permission gating
    │   └── visit_detail_page.dart          # replace body with five-phase read view (== Review)
    ├── providers/
    │   ├── workspace_mode_provider.dart    # new: guided (stepper) vs expert; remembered per user (best-effort)
    │   ├── encounter_step_provider.dart    # new: active step + completion/validation derivation
    │   ├── patient_safety_provider.dart    # new: patient-level safety context (P3 read)
    │   └── visit_documentation_notifier.dart  # extend: plan-details + diagnosis + result save flows
    └── widgets/
        ├── encounter_header.dart           # new (US1)
        ├── encounter_workspace_shell.dart  # new: 3-region layout + responsive collapse (US4)
        ├── encounter_step_rail.dart        # new: steps + badges (US4)
        ├── encounter_sticky_footer.dart    # new: save status + Prev/Next (US4)
        ├── patient_safety_rail.dart        # new: persistent read-only surface + degraded alerts line (US3/US6)
        ├── encounter_phase_context.dart    # new: visit type + safety record editors (US6)
        ├── encounter_phase_subjective.dart # new: Complaint + History (wraps ClinicalNoteEditor sections)
        ├── encounter_phase_objective.dart  # new: Vital signs + Examination + BMI chip + results (US8)
        ├── encounter_phase_assessment.dart # new: coded diagnosis + free-text diagnosis (US7)
        ├── encounter_phase_plan.dart       # new: Treatments + Investigations + plan outputs + Attachments (US7)
        ├── encounter_review.dart           # new: read-only summary + per-section edit links + submit (US4)
        ├── expert_mode_accordion.dart      # new: five phases as collapsible sections (US5)
        ├── diagnosis_autocomplete_field.dart  # new thin wrapper over CatalogAutocompleteField
        └── [reuse unchanged] clinical_note_editor.dart, vital_sign_list.dart,
            treatment_plan_list.dart, investigation_list.dart, visit_attachment_list.dart,
            catalog_autocomplete_field.dart, save_to_catalog_dialog.dart, visit_submit_dialog.dart

frontend/test/
├── unit/visits/        # bmi derivation, step-completion logic, new model parsing/normalization
└── widget/visits/      # workspace shell, regrouping coverage, safety rail presence per phase, expert mode toggle
```

**Structure Decision**: All work stays in `features/visits` for cohesion, even though safety records are patient-level (they are surfaced/edited only from the visit's Context phase; the patient linkage lives in the new tables, not in a new feature module). The existing 013 child widgets (clinical note editor, vital/treatment/investigation lists, attachments, catalog autocomplete, save-to-catalog dialog) are **reused unchanged** and merely re-hosted under the new phase canvases. The two visit pages keep their routes, providers, and permission gating; only their `body` composition changes. P1/P2 introduce **no** backend change; P3 adds exactly one additive migration that extends `get_visit` without altering existing keys.

## Implementation Phases (high level)

### Phase P1 — Regrouping, header, safety affordance (frontend only, US1–US3)

1. `encounter_phase.dart` enum + ordering; `bmi.dart` pure derivation (+ unit tests)
2. `encounter_header.dart` from existing `VisitDetail` metadata (US1)
3. Re-host 013 widgets under five phase canvases; split clinical note sections across Subjective/Objective/Assessment/Plan; co-locate Examination↔Vitals and Plan↔Treatments/Investigations/Attachments (US2)
4. `patient_safety_rail.dart` with degraded free-text "alerts"/empty state (no structured data yet) shown on every phase (US3, FR-010/011/012)
5. Derived BMI chip in Objective (US8 partial / FR-025); detail view recomposed into the same five groups (FR-009)

### Phase P2 — Workspace + modes (frontend only, US4–US5)

1. `encounter_workspace_shell.dart` 3-region layout (steps · canvas · safety rail) with responsive collapse (FR-020)
2. `encounter_step_rail.dart` with empty/has-content/error badges from `encounter_step_provider.dart`; non-linear navigation (FR-014/015/016)
3. `encounter_sticky_footer.dart` reusing existing per-section save + optimistic concurrency status (FR-017)
4. `encounter_review.dart` = read-only summary + per-section edit links + submit, enforcing existing ≥1-clinical-section rule (FR-018); detail page uses the same view
5. `expert_mode_accordion.dart` + `workspace_mode_provider.dart` toggle preserving in-progress content/save state (FR-019)

### Phase P3 — Structured data (one additive migration + RPCs + frontend, US6–US8)

1. Migration: create patient-safety tables, `diagnosis_codes` catalog, `visit_diagnosis_codes`, `visit_plan_details`; ALTER vital signs (`measured_at`) and investigations (result columns); seed sample diagnosis codes + "Pain Score" predefined vital sign per org (idempotent)
2. RPCs (`auth_internal` + `public` wrappers, `visits.edit_soap`-gated, audit-logged): patient safety CRUD ×3; `search_diagnosis_codes` + `create_catalog_diagnosis_code`; visit diagnosis-code line create/archive; `save_visit_plan_details` (1:1 upsert, optimistic concurrency, `STALE_PLAN_DETAILS`); `record_investigation_result`; extend `update_visit_vital_sign` with `measured_at`; `get_patient_safety_context` (allergies/meds/conditions + last prior-visit vitals for FR-013)
3. Extend `auth_internal.get_visit` payload with `diagnosis_codes`, `plan_details`, vital `measured_at`, investigation `result`/`result_recorded_at` (existing keys unchanged)
4. Frontend: new domain models + `VisitDetail` extension parsing; repository wrappers; Context-phase safety editors (reusing catalog machinery); Assessment coded-diagnosis field; Plan structured outputs; Objective results + pain-score (predefined vital sign) + measurement time; safety rail upgraded from degraded alerts to structured data
5. Backend tests (CRUD + RLS) and Flutter tests for the new flows

### Phase P4 — Regression & polish

1. Verify 013 fields all reachable/editable, none lost/duplicated (SC-005); submission rules unchanged
2. Attachment upload/download regression (SC-008); appointment/visit-history flows unchanged
3. `dart analyze` + targeted `flutter test test/**/visits/`; backend test runner green
