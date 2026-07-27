# Visits and Encounter Workspace

- Purpose: Document the visit lifecycle, clinical documentation model, and encounter workspace UI architecture.
- Read this when: implementing or reviewing visit documentation, patient safety editing, attachments, or encounter workspace behavior.
- Canonical for: visit/encounter domain tables, RPC contracts, workspace phases, save semantics, and frontend module layout.
- Usually paired with: `docs/architecture/05-database.md`, `docs/architecture/07-frontend.md`, `docs/architecture/09-security-rbac.md`, `docs/specs/013-visits/`, `docs/specs/014-visit-encounter-workspace/`.
- Not covered here: billing from visits (see `15-billing.md`), appointment booking rules, or AI SOAP summarization.

---

## Overview

Visit documentation evolved through three delivery phases:

| Phase | Spec | Scope |
| ----- | ---- | ----- |
| V1-5 base | `006-visit-medical-records` (superseded) | `visits`, `treatment_plans`, `visit_attachments`; legacy `soap_notes` |
| 013 redesign | `docs/specs/013-visits/` | Sectioned `visit_clinical_notes`, vitals, investigations, org catalogs |
| 014 workspace | `docs/specs/014-visit-encounter-workspace/` | Encounter shell, patient safety tables, guided stepper (expert accordion mode **not implemented**) |

The legacy `soap_notes` table was backfilled into `visit_clinical_notes` and dropped. Spec 014 P3 additions for coded diagnosis (`diagnosis_codes`, `visit_diagnosis_codes`) and structured plan (`visit_plan_details`) were **implemented then removed** in migrations `20260702120000` and `20260705120000`. Architecture and contracts must reflect the rolled-back state.

## Clinical Documentation Model

### Core Tables

| Table | Key Columns | Notes |
| ----- | ----------- | ----- |
| `visits` | `branch_id`, `appointment_id`, `patient_id`, `doctor_id`, `visit_date`, `status` | One visit per appointment workflow; status drives editability |
| `visit_clinical_notes` | `visit_id`, `complaint`, `history`, `examination`, `diagnosis`, `plan` | Replaces SOAP columns; one row per visit; optimistic concurrency via `updated_at` |
| `visit_vital_signs` | `visit_id`, `name`, `value`, `unit`, `recorded_at` | Catalog-backed via `predefined_vital_signs`; BMI derived client-side |
| `visit_investigations` | `visit_id`, `name`, `status`, `result`, `result_recorded_at` | Ordered/test status; result capture in encounter workspace |
| `treatment_plans` | `visit_id`, `patient_id`, `medication_name`, `dosage`, `frequency`, dates, `notes` | Doctor-authored prescriptions within visit |
| `visit_attachments` | `visit_id`, `file_path`, `file_type`, `label`, `uploaded_by` | Metadata row; binary in Storage bucket `visit-attachments` |

### Org Catalogs (013)

| Table | Purpose |
| ----- | ------- |
| `medications` | Autocomplete for treatment plans; `create_catalog_medication` saves new entries |
| `investigations` | Autocomplete for ordered tests |
| `predefined_vital_signs` | Standard vital names/units for branch org |

### Patient Safety (014, retained)

| Table | Purpose |
| ----- | ------- |
| `patient_allergies` | `substance`, `reaction`; org-scoped via patient |
| `patient_medications` | Current/home medications; editable in visit context |
| `patient_chronic_conditions` | Text-only chronic conditions (no coded ICD catalog) |

Safety records are patient-level but surfaced and edited from the encounter workspace safety rail. RPCs: `get_patient_safety_context`, allergy/medication/chronic-condition CRUD.

### Storage

- Bucket: `visit-attachments` (private, 25 MB, PDF/DOCX/JPEG/PNG).
- Path: `{organization_id}/{branch_id}/{visit_id}/{filename}`.
- Lifecycle: upload to Storage → `register_visit_attachment` RPC; `delete_visit_attachment` removes DB row and object; `get_visit_attachment_download` for signed access.
- Deferred upload: attachments selected in the UI are held in `VisitEncounterDraft` until save/submit.

## RPC Inventory (Visits Domain)

| Public Wrapper | Purpose |
| -------------- | ------- |
| `create_visit` | From `checked_in` or `in_progress` appointment |
| `get_visit`, `get_visit_by_appointment`, `list_patient_visits` | Read paths |
| `save_visit_documentation` | Sectioned clinical note with optimistic concurrency (`STALE_*` on conflict) |
| `complete_visit` | Submit encounter; completes linked appointment |
| `create_treatment_plan`, `update_treatment_plan`, `archive_treatment_plan` | Treatment CRUD |
| Vital sign CRUD | `create_visit_vital_sign`, `update_visit_vital_sign`, `archive_visit_vital_sign` |
| Investigation CRUD | `create_visit_investigation`, `update_visit_investigation`, `archive_visit_investigation`, `record_investigation_result` |
| Catalog search/create | `search_medications`, `search_investigations`, `list_predefined_vital_signs`, `create_catalog_medication`, `create_catalog_investigation`, `create_predefined_vital_sign` |
| Attachment RPCs | `register_visit_attachment`, `delete_visit_attachment`, `get_visit_attachment_download`, `list_patient_visit_attachments` |
| Patient safety | `get_patient_safety_context`, `create_patient_allergy`/`update_patient_allergy`/`archive_patient_allergy`, `create_patient_medication`/`update_patient_medication`/`archive_patient_medication`, `create_patient_chronic_condition`/`update_patient_chronic_condition`/`archive_patient_chronic_condition` |
| `create_invoice_from_visit` | Cross-domain: starts a billing invoice from a visit (see `15-billing.md`) |

## Permissions

| Permission | Typical grantees | Use |
| ---------- | ---------------- | --- |
| `visits.create` | doctor, receptionist | Start visit from appointment |
| `visits.edit_soap` | doctor | Edit documentation, vitals, investigations, safety in active encounter |
| `visits.upload_attachment` | doctor, lab_staff | Register attachments |

RLS: branch-scoped SELECT; mutations via SECURITY DEFINER RPCs only.

## Save Semantics

**Online-only.** Clinical saves require an active Supabase connection. There is no offline draft queue or local persistence of visit documentation across app restarts.

- **Optimistic concurrency**: `save_visit_documentation` accepts `p_expected_updated_at`; stale writes return `STALE_DOCUMENTATION` (or equivalent).
- **Deferred child mutations**: Vitals, investigations, treatment plans, and attachments accumulate in `VisitEncounterDraft` until explicit save or visit submit.
- **Completed visits**: Read-only by default; explicit edit mode re-enables documentation RPCs where permitted.

This contradicts a general "offline-first" product stance. Tier 1/2 daily ops work without internet for reads when LAN is up, but **all clinical writes require LAN reachability to Supabase**.

## Frontend Architecture

### Module Layout

```
frontend/lib/features/visits/
├── data/           # VisitRepositoryImpl, VisitAttachmentService
├── domain/         # DTOs, EncounterPhase, VisitEncounterDraft, BMI
├── application/    # visit_rpc_messages.dart, visit_launch_service.dart
└── presentation/
    ├── pages/      # visit_documentation_page, visit_detail_page
    ├── providers/  # visit_documentation_notifier, encounter_step_provider, patient_safety_provider
    └── widgets/    # phase canvases, safety rail, catalog autocomplete, save-status badge
```

`VisitDocumentationNotifier` (~1400 lines) holds draft state and coordinates persistence — an intentional deviation from strict use-case-only presentation layer.

### Encounter Workspace Shell

`EncounterWorkspaceShell` composes:

- **Stepper header** (`EncounterStepperHeader`) — phase progress and completion badges
- **Phase canvases** — `EncounterPhaseSubjective`, `EncounterPhaseObjective`, `EncounterPhasePlan`, `EncounterReview`
- **Patient safety rail** — allergies, medications, chronic conditions
- **Save status** — `VisitDocumentationSaveStatusBadge` surfaces save lifecycle and stale-conflict resolution
- **Sticky footer** — save, submit, attachment actions

`EncounterPhase` enum maps UI phases to clinical sections. Context/background (patient demographics, appointment metadata) renders in the joined header, not as an editable phase.

### Routes

| Path | Page | Permission |
| ---- | ---- | ---------- |
| `/visits/:visitId/document` | `VisitDocumentationPage` | `visits.edit_soap` or `visits.create` |
| `/visits/:visitId/detail` | `VisitDetailPage` | `visits.create` (read history) |

Redirect logic: `AuthRouteGuard.visitRouteRedirect`.

### Workflow

```
Appointment (checked_in / in_progress)
    → create_visit (explicit action)
    → /visits/:id/document
    → document phases (Subjective → Objective → Plan → Review)
    → save_visit_documentation (per-section or batch via persistence layer)
    → complete_visit (submit)
    → visit status completed; appointment completed
    → /visits/:id/detail (read-only history)
```

## Testing

- Backend: `backend/tests/visit_medical_records_*.sql`, `visit_encounter_workspace_*.sql` via `run_visit_medical_records_tests.sh`.
- Frontend: 30+ widget tests under `frontend/test/widget/visits/` (workspace modes, deferred attachments, submit dialog, completed-visit edit).
