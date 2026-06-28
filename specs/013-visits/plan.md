# Implementation Plan: Visits Page Redesign (013)

**Branch**: `ui/013-visits` | **Date**: 2026-06-28 | **Spec**: `specs/013-visits/spec.md`

**Input**: Feature specification from `specs/013-visits/spec.md`

## Summary

Replace V1-5 SOAP/specialty visit documentation with a structured clinical note (Complaint, History, Examination, Diagnosis, Plan), org-scoped searchable catalogs (medications, investigations, predefined vital signs), visit child records (vital signs, investigations), and duration-only treatments with optional `medication_id` linkage. Drop `soap_notes` and specialty form usage entirely (no legacy UI, no data migration). Preserve V1-5 visit lifecycle, attachments, permissions (`visits.edit_soap`), post-submit editing, and optimistic concurrency. Flutter `features/visits` documentation and detail pages are fully replaced; attachments unchanged.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase; PL/pgSQL in `auth_internal` + public RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK (RPC + Storage), Riverpod, GoRouter; existing `VisitRepository`, `VisitAttachmentService`, `AppAutocomplete` / debounced search patterns from appointments/patients

**Storage**: New tables `visit_clinical_notes`, `medications`, `investigations`, `predefined_vital_signs`, `visit_vital_signs`, `visit_investigations`; extend `treatment_plans` (`medication_id`, duration-only); drop `soap_notes`; remove `get_specialty_form_schema` / specialty JSON paths; unchanged `visits`, `visit_attachments`, storage bucket `visit-attachments`

**Testing**: Update `backend/tests/visit_medical_records_crud.sql`, `visit_medical_records_rls.sql`, `run_visit_medical_records_tests.sh`; Flutter unit/widget tests under `frontend/test/**/visits/`; `dart analyze` on visits feature

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile)

**Project Type**: Desktop client + Supabase PostgreSQL (single migration, RLS, RPC, Storage); no custom API server; no AI

**Performance Goals**: Catalog search results visible within 300ms debounce under normal LAN (SC-002); documentation save feels instantaneous; `get_visit` remains single round-trip for detail screen

**Constraints**: Branch-scoped RLS; mutations via RPC only; one visit per appointment; optimistic concurrency on clinical note save; custom catalog names normalized client-side before save/prompt; optional save-to-org-catalog prompt (decline = visit-line only); SOAP/specialty data discarded; duration sole treatment time field; attachments behavior unchanged

**Scale/Scope**: 1 migration; ~8 new/updated RPC families; 3 catalog tables + 3 child tables + 1 clinical note table; remove ~6 Flutter SOAP/specialty files; add ~8 new widgets/domain types; 3 contract docs; replace documentation + detail UI

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Scope fits small-to-mid-size multi-branch outpatient clinics; hospital CPOE/order sets out of scope (spec Business Context)
- [x] No microservices, queues, Kubernetes, or custom primary backend service
- [x] Flutter UI/orchestration; Supabase RPC/Storage; PostgreSQL owns schema, validation, audit, RLS
- [x] Protected writes via `auth_internal` RPCs; catalog growth via optional doctor prompt, not admin UI
- [x] Tenant isolation org-scoped catalogs + branch-scoped visits; existing permission keys; audit; soft delete
- [x] No AI dependency; manual documentation only (Principle V)

### Post-Design Re-Check

- [x] Visit–appointment completion remains atomic in `complete_visit` with clinical-note non-empty check (replaces SOAP check)
- [x] Attachment authorization unchanged (RPC + storage policies)
- [x] Optimistic concurrency on `save_visit_documentation` (replaces `STALE_SOAP`)
- [x] Catalog search RPCs are read-only SELECT under RLS; catalog inserts gated by `visits.edit_soap` when doctor accepts prompt
- [x] No new custom backend service; no AI write paths
- [x] Legacy SOAP/specialty fully removed per clarified spec (no dual-read)

## Project Structure

### Documentation (this feature)

```text
specs/013-visits/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── visit-mutations.md
│   ├── visit-queries.md
│   └── catalog-queries.md
└── tasks.md              # /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260628140000_visit_documentation_redesign.sql
└── tests/
    ├── visit_medical_records_crud.sql      # update for new model
    ├── visit_medical_records_rls.sql
    └── run_visit_medical_records_tests.sh

frontend/lib/features/visits/
├── application/
│   └── visit_rpc_messages.dart             # + new error codes
├── data/
│   ├── visit_repository.dart               # new RPC wrappers
│   └── visit_attachment_service.dart       # unchanged
├── domain/
│   ├── visit_clinical_note.dart            # new
│   ├── visit_vital_sign.dart               # new
│   ├── visit_investigation.dart            # new
│   ├── catalog_item.dart                   # new (medication/investigation/vital sign)
│   ├── catalog_name_normalizer.dart        # new
│   ├── treatment_plan_item.dart            # drop start/end dates
│   ├── visit_detail.dart                   # new shape
│   └── [remove] soap_note.dart, specialty_form_schema.dart
└── presentation/
    ├── pages/
    │   ├── visit_documentation_page.dart   # full replace
    │   └── visit_detail_page.dart          # full replace
    ├── providers/
    │   ├── visit_documentation_notifier.dart
    │   └── [remove] specialty_form_schema_provider.dart
    └── widgets/
        ├── clinical_note_editor.dart       # new (5 sections + hints)
        ├── vital_sign_list.dart            # new
        ├── investigation_list.dart         # new
        ├── catalog_autocomplete_field.dart # new (debounced search + custom)
        ├── save_to_catalog_dialog.dart     # new
        ├── treatment_plan_list.dart        # rework (catalog + duration)
        ├── treatment_plan_display.dart     # rework
        ├── visit_attachment_list.dart      # unchanged
        ├── visit_submit_dialog.dart        # update validation copy
        └── [remove] soap_editor.dart, specialty_form_fields.dart,
            specialty_form_read_only_section.dart

frontend/test/
├── unit/visits/
└── widget/visits/
```

**Structure Decision**: All visit clinical changes stay in `features/visits` per V1-5 layout. Catalog search reuses appointment patient-search debounce pattern (300ms). Name normalization lives in `domain/catalog_name_normalizer.dart` (pure Dart, unit-tested). No `core/ui` changes required beyond existing `AppTextField` / `AppAutocomplete` usage.

## Implementation Phases (high level)

### Phase A — Backend migration

1. Create `visit_clinical_notes`, catalog tables, `visit_vital_signs`, `visit_investigations`
2. Seed dev medications, investigations, predefined vital signs per org bootstrap pattern
3. Alter `treatment_plans`: add `medication_id`; migrate `start_date`/`end_date` → `duration` text; drop date columns + CHECK
4. Drop `soap_notes`; remove specialty form settings usage from visit RPCs
5. Implement `save_visit_documentation`, catalog search/create RPCs, vital sign/investigation CRUD RPCs
6. Update `get_visit`, `complete_visit`, treatment plan RPCs (duration required, medication_id optional)
7. Drop `save_soap_note`, `get_specialty_form_schema` public wrappers
8. Update RLS policies for new tables; deny direct writes

### Phase B — Backend verification

1. Rewrite SOAP tests → clinical note tests; drop specialty JSON cases
2. Add catalog search, custom catalog create, vital sign/investigation CRUD cases
3. Verify `SOAP_REQUIRED` → `DOCUMENTATION_REQUIRED` on complete
4. Verify date columns gone; duration migration on fixture data
5. RLS cross-branch denial for new tables

### Phase C — Flutter visits module

1. Domain models + repository RPC wrappers
2. `CatalogNameNormalizer` + unit tests
3. `CatalogAutocompleteField` with debounced `search_medications` / `search_investigations`
4. `SaveToCatalogDialog` after custom entry save
5. Replace `VisitDocumentationPage` layout (clinical sections → vital signs → treatments → investigations → attachments)
6. Update `VisitDetailPage` read layout
7. Remove SOAP/specialty files and imports
8. Update notifier save/submit flows (`save_visit_documentation`, `STALE_DOCUMENTATION`)

### Phase D — Regression & polish

1. Appointment create/open visit flows unchanged
2. Patient visit history metadata unchanged
3. Attachment upload/download regression
4. `dart analyze` + targeted `flutter test test/**/visits/`

## Complexity Tracking

No constitution violations. Full SOAP removal with data discard is an explicit product decision documented in spec clarifications; simpler than dual-read legacy paths.
