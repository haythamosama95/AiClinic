# Research: Visits and Medical Records

## Decision 1: `auth_internal` + public RPC wrappers (`rpc_result`)

- **Decision**: Visit mutations and secured reads run in `auth_internal` (SECURITY DEFINER) with thin `public.*` INVOKER wrappers returning `public.rpc_result`.
- **Rationale**: Constitution III/IV; appointment–visit coupling, one-visit-per-appointment, SOAP optimistic concurrency, attachment authorization, and audit stay in PostgreSQL.
- **Alternatives considered**: Direct PostgREST writes (rejected). Edge Functions (rejected — cloud-only).

## Decision 2: Branch-scoped RLS on visit domain tables

- **Decision**: RLS on `visits`, `soap_notes`, `treatment_plans`, `visit_attachments` filters via visit `branch_id ∈ jwt branch_ids` within organization; SELECT allowed for operational reads; INSERT/UPDATE/DELETE denied on tables (RPC only).
- **Rationale**: Matches `appointments` branch isolation (`docs/architecture/05-database.md`); spec FR-006.
- **Alternatives considered**: Org-wide visit reads (rejected — contradicts branch-scoped clinical workflow).

## Decision 3: Visit lifecycle enum and one visit per appointment

- **Decision**: `visit_status` enum: `in_progress`, `completed`. Partial unique index on `visits(appointment_id) WHERE is_deleted = false`.
- **Rationale**: Spec FR-002/FR-004; architecture one-visit-per-appointment (spec clarifies creation from `checked_in`/`in_progress`, not after manual complete).
- **Alternatives considered**: Multiple visits per appointment (rejected). Include `cancelled` visit status (rejected — out of scope; appointment cancel/no-show handled in V1-4).

## Decision 4: Visit creation eligibility and appointment handoff

- **Decision**: `create_visit` accepts appointments in `checked_in` or `in_progress` only. From `checked_in`, atomically set appointment → `in_progress`. From `in_progress`, appointment unchanged. When appointment lacks `doctor_id`, require `p_doctor_id` and persist on **both** appointment and visit before insert.
- **Rationale**: Clarification session 2026-05-31; supersedes outdated roadmap wording about creating visits from completed appointments.
- **Alternatives considered**: Auto-create visit on check-in (rejected — FR-028). Create from `completed` (rejected).

## Decision 5: Appointment completion only via visit submit

- **Decision**: `complete_visit` atomically sets visit → `completed` and linked appointment → `completed` in one transaction after SOAP non-empty validation. `update_appointment_status` **rejects** `in_progress` → `completed` once V1-5 migration is applied.
- **Rationale**: Spec FR-004a/FR-004b; closes clinical loop; prevents reception bypass.
- **Alternatives considered**: Keep manual complete button (rejected). Complete appointment first then create visit (rejected — contradicts spec).

## Decision 6: SOAP optimistic concurrency

- **Decision**: `save_soap_note` requires `p_expected_updated_at` matching `soap_notes.updated_at` (or visit row if SOAP row not yet created — use visit `updated_at` until first SOAP insert). Mismatch returns `STALE_SOAP`.
- **Rationale**: Clarification session; mirrors `update_patient` pattern (`STALE_PATIENT`).
- **Alternatives considered**: Last-write-wins (rejected). Row-level locking only (rejected — poor UX across desktop sessions).

## Decision 7: Specialty form schema via `app_settings`

- **Decision**: Active schema stored at org scope: `app_settings` key `specialty.form_schema_json` (`branch_id IS NULL`). `get_specialty_form_schema()` RPC returns JSON or empty object. Validation in `save_soap_note` against schema when `specialty_form_json` is non-null.
- **Rationale**: Spec FR-011; avoids new admin UI in V1-5 MVP; reuses settings table from V1-2.
- **Alternatives considered**: Dedicated `specialty_schemas` table (rejected — YAGNI for V1-5). Hard-coded dermatology form (rejected — not clinic-fit).

## Decision 8: Treatment plan mutations in visit context

- **Decision**: RPCs `create_treatment_plan`, `update_treatment_plan`, `archive_treatment_plan` gated by `visits.edit_soap`; soft delete via standard audit columns; medication name required.
- **Rationale**: Spec FR-012/FR-013; consistent with patient/archive patterns.
- **Alternatives considered**: Embed treatment lines in SOAP JSON (rejected — architecture table exists).

## Decision 9: Supabase Storage bucket `visit-attachments`

- **Decision**: Private bucket `visit-attachments`. Object path: `{organization_id}/{branch_id}/{visit_id}/{uuid}_{filename}`. Max size **25 MB** per file. Allowed types: PDF, DOCX, JPEG, PNG (validated by MIME + extension in RPC).
- **Rationale**: Spec FR-015/FR-017; architecture Storage API; 25 MB default from spec assumptions.
- **Alternatives considered**: Store files in PostgreSQL bytea (rejected). Public bucket (rejected — PHI).

## Decision 10: Two-phase attachment upload

- **Decision**: Flutter uploads bytes via `supabase.storage.from('visit-attachments').upload()` using storage policies that require visit branch scope + upload permission; then calls `register_visit_attachment` to create metadata and audit. On RPC failure after upload, client deletes orphan object (best effort); RPC validates path prefix matches visit org/branch/id.
- **Rationale**: Keeps large blobs out of RPC payloads; metadata stays authoritative in PostgreSQL.
- **Alternatives considered**: RPC accepts base64 (rejected — size/performance). Upload-only via RPC without storage (rejected — not Supabase pattern).

## Decision 11: Attachment download authorization

- **Decision**: `get_visit_attachment_download(p_attachment_id)` validates: caller has `visits.create` OR `visits.edit_soap` for visit branch, **OR** has `visits.upload_attachment` AND `uploaded_by = jwt_staff_member_id()`. Returns signed URL (or storage path + short-lived token per SDK).
- **Rationale**: Spec FR-016 lab-staff own-upload rule; centralizes download gate beyond storage policy alone.
- **Alternatives considered**: Storage policy only (rejected — hard to express uploader match cleanly). SOAP read for download (rejected — lab staff must not need SOAP permission).

## Decision 12: Permission seed extension `visits.upload_attachment`

- **Decision**: New permission key in migration seed: granted to `lab_staff`, `owner`, `administrator`, `doctor`. Clinical upload also allowed via `visits.create` / `visits.edit_soap` without requiring upload key.
- **Rationale**: Spec FR-016; V1-1 seed already has `visits.create`/`visits.edit_soap` for clinical roles.
- **Alternatives considered**: Reuse `patients.view` for lab upload (rejected — too broad).

## Decision 13: Flutter module `features/visits`

- **Decision**: New feature module with routes under `/visits/*` (documentation screen, detail) plus patient profile integration replacing `PatientVisitsPlaceholder`. Appointment queue/calendar gains **Create visit** / **Open visit** actions when eligible.
- **Rationale**: `docs/architecture/07-frontend.md` feature-first layout; spec FR-018/FR-019.
- **Alternatives considered**: Embed all visit UI inside appointments (rejected — visit history lives on patient profile).

## Decision 14: Appointment UI transition change (V1-5)

- **Decision**: Remove `in_progress` → `completed` forward action from `AppointmentStatusActions` / `forwardStatusTargetFor`; show **Create visit** / **Open visit** instead when user has `visits.create`. Completed state reached only after visit submit.
- **Rationale**: Spec FR-004b; aligns desk staff UX with clinical workflow.
- **Alternatives considered**: Keep Complete button calling blocked RPC (rejected — confusing UX).

## Decision 15: Patient visit history pagination

- **Decision**: `list_patient_visits(p_patient_id, p_limit default 50, p_offset default 0)` ordered by `visit_date DESC`, `created_at DESC`. Metadata-only fields in list response; full detail via `get_visit`.
- **Rationale**: NFR-003 up to 500 visits; spec FR-019/FR-020.
- **Alternatives considered**: Load all visits (rejected — scale). Single RPC returning SOAP in list (rejected — permission leak risk).

## Decision 16: PermissionKeys and PermissionService extension

- **Decision**: Add `visitsCreate`, `visitsEditSoap`, `visitsUploadAttachment` to `PermissionKeys`; helpers `canCreateVisits`, `canEditVisitSoap`, `canUploadVisitAttachments`, `canViewVisitClinicalDetail`.
- **Rationale**: Matches V1-4 appointment permission pattern; defense in depth at UI.
- **Alternatives considered**: Literal strings (rejected).

## Decision 17: Backend verification suite

- **Decision**: SQL harness `visit_medical_records_crud.sql`, `visit_medical_records_rls.sql`, `run_visit_medical_records_tests.sh`; update appointment tests to complete visits via `complete_visit` instead of `update_appointment_status(..., 'completed')`.
- **Rationale**: Spec FR-025; regression safety for appointment integration change.
- **Alternatives considered**: Flutter-only tests (rejected — insufficient for RLS/RPC).
