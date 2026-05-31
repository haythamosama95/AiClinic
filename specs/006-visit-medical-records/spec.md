# Feature Specification: Visits and Medical Records

**Feature Branch**: `specs/006-visit-medical-records`

**Created**: 2026-05-31

**Status**: Draft

**Input**: User description: "Read V1-5 from docs/architecture/12-roadmap-phases.md…" Modified: visit creation from `checked_in`/`in_progress`; appointment `completed` on visit submit; attachments allow PDF, DOCX, and photos (JPEG/PNG).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

This feature delivers clinical visit documentation for a multi-branch clinic after authentication, organization administration, patient registration, and appointment scheduling exist. When an appointment is **checked in** or **in progress** (V1-4), clinical staff can open a **visit** that captures SOAP notes, specialty-specific structured data, treatment plans, and supporting documents (lab PDFs, Word reports, photos, scans, examination reports). When the visit is completed and submitted, the linked appointment automatically moves to **completed**. Doctors document encounters; lab staff attach results; administrators and doctors review visit history from the patient profile.

The primary beneficiaries are **doctors** who record clinical encounters, **lab staff** who upload examination documents, and **administrators** who oversee clinical records across branches. Billing (V1-6), shift planning (V1-7), and AI-assisted SOAP drafting (V2) depend on visits being created with accurate patient, doctor, branch, and appointment linkage, and appointments reaching `completed` only after clinical documentation is submitted.

V1-4 (`specs/005-appointment-management`) advances appointments through check-in and in progress but does not create visits or auto-complete appointments from visit submission. This feature introduces the visits domain: one visit per eligible appointment, branch-scoped records, SOAP documentation, treatment plans, file attachments, patient visit history, and the appointment completion handoff when a visit is submitted.

## Clarifications

### Session 2026-05-31

- Q: From which appointment statuses can a visit be created? → A: **`checked_in`** (when reception did not advance to in progress) or **`in_progress`** (the expected state). Appointments in `scheduled`, `confirmed`, `cancelled`, `no_show`, or already `completed` cannot start a visit.
- Q: When does the appointment become `completed`? → A: Automatically when the visit is **completed and submitted**—not as a prerequisite for visit creation. Manual appointment `in_progress` → `completed` via appointment status actions (V1-4) is superseded by this visit-completion workflow in V1-5.
- Q: What happens to appointment status when a visit is created from `checked_in`? → A: The linked appointment MUST advance to `in_progress` at visit creation (clinical encounter has started).
- Q: Which file types can be attached to a visit? → A: **PDF**, **DOCX** (Word documents), and **photos** (common image formats: JPEG and PNG). Other file types are rejected with a clear message listing allowed types.
- Q: How is lab staff attachment upload authorized? → A: New permission key **`visits.upload_attachment`** granted to `lab_staff`; users with `visits.create` or `visits.edit_soap` may also upload attachments.
- Q: What minimum content is required to submit a visit? → A: **At least one SOAP section** (Subjective, Objective, Assessment, or Plan) must contain text; treatment plans and attachments remain optional.
- Q: What happens when creating a visit from an appointment with no assigned doctor? → A: **Prompt doctor selection** at visit creation; the selected doctor is saved on **both the visit and the appointment**.
- Q: How are concurrent SOAP saves from two sessions handled? → A: **Optimistic concurrency** — stale saves are rejected with an error and refresh prompt; no silent last-write-wins overwrites.
- Q: Can lab staff download visit attachments? → A: Users with `visits.upload_attachment` may **download only attachments they uploaded**; clinical roles with `visits.create` or `visits.edit_soap` retain full attachment download access for the visit.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a Visit from a Checked-In or In-Progress Appointment (Priority: P1)

As a doctor or administrator with visit-create permission, I can start a visit from a **checked-in** or **in-progress** appointment so the clinic has a clinical record linked to the active encounter.

**Why this priority**: Visit creation is the entry point for all medical documentation; without it, SOAP, treatment plans, and attachments have no anchor.

**Independent Test**: Can be fully tested by using a checked-in or in-progress appointment, creating a visit, and verifying the visit appears with correct patient, doctor, branch, and appointment linkage; for `checked_in`, verify the appointment advances to `in_progress`.

**Acceptance Scenarios**:

1. **Given** an `in_progress` appointment with no existing visit and a user with `visits.create` at the appointment's branch, **When** they initiate visit creation, **Then** a visit is created with status `in_progress`, linked to the appointment, patient, doctor, and branch, and the user is guided to visit documentation.
2. **Given** a `checked_in` appointment with no existing visit and a user with `visits.create`, **When** they initiate visit creation, **Then** a visit is created, the linked appointment advances to `in_progress`, and the user is guided to visit documentation.
3. **Given** an appointment in `scheduled`, `confirmed`, `cancelled`, `no_show`, or `completed`, **When** the user attempts to create a visit, **Then** creation is rejected with a clear message explaining the appointment must be checked in or in progress.
4. **Given** an appointment that already has a visit, **When** the user attempts to create another visit, **Then** creation is rejected (one visit per appointment).
5. **Given** a user without `visits.create`, **When** they attempt to create a visit, **Then** the action is blocked at UI and server layers.
6. **Given** an appointment at a branch outside the user's assigned branches, **When** they attempt to create a visit, **Then** access is denied.
7. **Given** a `checked_in` or `in_progress` appointment with no `doctor_id` and a user with `visits.create`, **When** they initiate visit creation, **Then** they are prompted to select a doctor from eligible branch doctors before the visit is created; the selected doctor is stored on both the visit and the appointment.
8. **Given** an appointment that already has a `doctor_id`, **When** visit creation proceeds, **Then** no doctor re-selection is required unless the user explicitly changes it (out of scope for V1-5 unless planning adds edit).

---

### User Story 2 - Document a SOAP Note (Priority: P1)

As a doctor with SOAP edit permission, I can record Subjective, Objective, Assessment, and Plan sections for a visit so the clinic maintains structured clinical documentation.

**Why this priority**: SOAP notes are the core medical record for outpatient clinics.

**Independent Test**: Can be fully tested by opening an in-progress visit, entering all four SOAP sections, saving, leaving, and returning to verify content persisted.

**Acceptance Scenarios**:

1. **Given** an `in_progress` visit and a user with `visits.edit_soap`, **When** they enter text in S, O, A, and P fields and save, **Then** the SOAP note is stored and associated with the visit with audit tracking.
2. **Given** an existing SOAP note, **When** the user updates any section and saves, **Then** changes persist and audit records the modification.
3. **Given** a user without `visits.edit_soap`, **When** they attempt to save SOAP content, **Then** the action is blocked.
4. **Given** required SOAP sections are empty on first save, **When** the user saves with at least one section filled, **Then** partial save is allowed (doctors may complete documentation over time).
5. **Given** a visit at another branch outside the user's scope, **When** they attempt to edit SOAP, **Then** access is denied.

---

### User Story 3 - Complete Specialty Form Fields (Priority: P2)

As a doctor documenting a visit for a clinic that uses specialty-specific forms, I can fill additional structured fields defined by the clinic's specialty schema alongside the standard SOAP sections.

**Why this priority**: Specialty clinics (e.g., dermatology, pediatrics) need structured fields beyond generic SOAP; this is secondary to core SOAP but important for clinic fit.

**Independent Test**: Can be fully tested by configuring a sample specialty schema, opening a visit, rendering dynamic fields, saving values, and reloading to verify persistence in the visit's specialty data.

**Acceptance Scenarios**:

1. **Given** the clinic has an active specialty form schema and a user with `visits.edit_soap`, **When** they open the visit documentation screen, **Then** dynamic fields from the schema appear alongside SOAP sections with appropriate input types (text, number, select, checkbox, etc.).
2. **Given** the user fills specialty fields and saves, **When** they return to the visit, **Then** specialty values are restored correctly.
3. **Given** no specialty schema is configured for the clinic, **When** the user opens visit documentation, **Then** only standard SOAP sections are shown without error.
4. **Given** invalid values for schema constraints (required field empty, out-of-range number), **When** the user saves, **Then** field-level validation errors are shown and invalid data is not persisted.

---

### User Story 4 - Manage Treatment Plans Within a Visit (Priority: P2)

As a doctor with SOAP edit permission, I can add, edit, and remove treatment plan entries (medications and instructions) within a visit so follow-up care is recorded for the patient.

**Why this priority**: Treatment plans are standard clinical output; they extend SOAP but are independently useful for patient care continuity.

**Independent Test**: Can be fully tested by adding multiple treatment plan lines to a visit, editing one, removing another, and verifying the list reflects changes after save.

**Acceptance Scenarios**:

1. **Given** an in-progress visit and `visits.edit_soap`, **When** the user adds a treatment plan with medication name, dosage, frequency, start date, optional end date, and notes, **Then** the entry is saved and linked to the visit and patient.
2. **Given** existing treatment plan entries, **When** the user edits fields and saves, **Then** updates persist with audit tracking.
3. **Given** a treatment plan entry, **When** the user removes it (soft delete), **Then** it no longer appears in active visit views but remains recoverable per soft-delete policy.
4. **Given** a user without `visits.edit_soap`, **When** they attempt to modify treatment plans, **Then** the action is blocked.
5. **Given** missing required fields (medication name), **When** the user submits, **Then** validation errors are shown.

---

### User Story 5 - Upload and Download Visit Attachments (Priority: P2)

As lab staff or clinical staff, I can upload PDF documents, Word documents (DOCX), or photos to a visit and download existing attachments so lab results, examination reports, and clinical images are stored with the clinical record.

**Why this priority**: Lab PDFs, written reports, and clinical photos are essential supporting documentation; upload is a frequent lab-staff and clinical workflow.

**Independent Test**: Can be fully tested by uploading one file of each allowed type (PDF, DOCX, JPEG or PNG photo) to a visit, verifying each appears in the attachment list with label, file type, and uploader, downloading each, and confirming content integrity.

**Acceptance Scenarios**:

1. **Given** an existing visit and an authorized uploader (user with `visits.upload_attachment`, `visits.create`, or `visits.edit_soap`), **When** they upload a PDF, DOCX, or photo (JPEG or PNG) with an optional label, **Then** the file is stored securely and a visit attachment record is created with file type, path reference, label, and uploader identity.
2. **Given** uploaded attachments on a visit, **When** an authorized user selects download, **Then** the original file is retrieved successfully with correct type.
2b. **Given** a lab staff user with `visits.upload_attachment` who uploaded an attachment, **When** they download that attachment, **Then** download succeeds.
2c. **Given** a lab staff user with `visits.upload_attachment` only, **When** they attempt to download an attachment uploaded by another user, **Then** download is denied.
3. **Given** a file type outside the allowed set (not PDF, DOCX, JPEG, or PNG), **When** the user attempts upload, **Then** upload is rejected with a clear message listing allowed types (PDF, DOCX, photos).
4. **Given** a file exceeding the maximum allowed size, **When** the user attempts upload, **Then** upload is rejected with size guidance.
5. **Given** a user without attachment upload authorization, **When** they attempt upload, **Then** the action is blocked.
6. **Given** storage or network failure during upload, **When** the upload fails, **Then** the user sees an error and no orphan attachment record is left in an inconsistent state.
7. **Given** multiple attachments of different allowed types on one visit, **When** the user views the attachment list, **Then** each entry shows file type (or icon/label) so PDF, DOCX, and photos are distinguishable.

---

### User Story 6 - Submit Visit and View Patient Visit History (Priority: P1)

As clinical staff, I can submit a completed visit when documentation is finished—which automatically completes the linked appointment—and view a chronological visit history on the patient profile so care continuity is visible across encounters.

**Why this priority**: Submitting the visit closes the clinical loop and correctly completes the appointment; visit history on the patient profile is the primary longitudinal view.

**Independent Test**: Can be fully tested by submitting a visit, verifying the linked appointment becomes `completed`, opening the patient profile, and verifying the visit appears in history with date, doctor, status, and summary metadata; users with clinical permissions can open full detail.

**Acceptance Scenarios**:

1. **Given** an `in_progress` visit linked to an `in_progress` appointment and a user with `visits.edit_soap`, **When** they submit the visit as complete with at least one non-empty SOAP section, **Then** the visit status becomes `completed`, the linked appointment status becomes `completed`, both changes are audited, and the visit appears in patient visit history.
1b. **Given** an `in_progress` visit with all SOAP sections empty, **When** the user attempts to submit, **Then** submit is rejected with a clear message that at least one SOAP section is required; visit and appointment remain `in_progress`.
2. **Given** a visit submitted as complete, **When** reception views the appointment, **Then** it shows `completed` and cannot be checked in or started again.
3. **Given** a user with `patients.view`, **When** they open visit history on the patient profile, **Then** they see a chronological list of non-deleted visits with visit date, doctor name, status, and branch (metadata only; SOAP content hidden unless they have clinical visit permissions).
4. **Given** a user with `visits.edit_soap` or `visits.create`, **When** they select a visit from history, **Then** they can open full visit detail including SOAP, specialty data, treatment plans, and attachments.
5. **Given** a user without clinical visit permissions, **When** they view visit history, **Then** they see list metadata but cannot open SOAP or download attachments.
6. **Given** visits at multiple branches within the organization, **When** a user with org-wide patient access views history, **Then** visits from all accessible branches for that patient are shown (subject to branch assignment rules).

---

### Edge Cases

- Attempt to create visit from `scheduled`, `confirmed`, `cancelled`, `no_show`, or already `completed` appointment: rejected with clear messaging.
- Visit created from `checked_in`: appointment advances to `in_progress` at visit creation.
- Visit creation from appointment with no `doctor_id`: user MUST select a doctor from eligible branch doctors; selection persisted on visit and appointment before visit record is created.
- Attempt to create visit without selecting doctor when appointment has no `doctor_id`: rejected with clear prompt to select doctor.
- Submit visit with all SOAP sections empty: rejected; at least one SOAP section must contain text (treatment plans and attachments optional).
- Visit submit when linked appointment is no longer `in_progress` (e.g., cancelled concurrently): rejected with clear error; visit remains `in_progress`.
- Manual appointment `in_progress` → `completed` via appointment status UI (V1-4): disabled or unavailable in V1-5; appointment completion MUST occur through visit submission.
- SOAP edit on completed visit: allowed for users with `visits.edit_soap` (corrections before billing) unless policy locks completed visits—V1 allows edit on completed visits with audit trail.
- Concurrent SOAP saves from two sessions: optimistic concurrency using visit/SOAP `updated_at` (or equivalent version); stale save rejected with refresh prompt—no silent last-write-wins data loss.
- Specialty schema changes after data saved: existing visits retain saved values; new schema version applies to new edits per planning rules.
- Upload of disallowed file type (e.g., spreadsheet, video, executable): rejected with message listing PDF, DOCX, and photos as allowed types.
- Attachment upload interrupted mid-transfer: no partial attachment record; user can retry.
- Storage service unavailable: upload/download fail with clear error; SOAP and treatment plan saves unaffected.
- AI services are not part of this feature; AI unavailability must not block any visit workflow.
- Receptionist without `visits.create` can check in and start appointments (V1-4) but cannot create visits, edit SOAP, or complete appointments via visit submission; they may view visit history metadata via `patients.view`.
- Lab staff with `visits.upload_attachment` only: may upload and download **their own** attachments; cannot download attachments uploaded by others or access SOAP content.
- Patient archived after visit created: visit remains readable for authorized users; new visits cannot be created for archived patients' new appointments if patient is archived before visit creation.
- Cross-organization visit access: always denied in verification scenarios.
- Permission grant changes follow V1-2 rules: client cache updates on auth-context reload; server enforces current grants immediately.
- Billing, prescriptions, workflow automation, and AI SOAP summarization are out of scope for V1-5.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST introduce visit records with fields aligned to architecture: `branch_id`, `appointment_id`, `patient_id`, `doctor_id`, `visit_date`, `status`, plus standard audit columns.
- **FR-002**: The system MUST enforce **one visit per appointment**; duplicate visit creation for the same appointment MUST be rejected.
- **FR-003**: The system MUST allow visit creation only when the linked appointment status is `checked_in` or `in_progress`.
- **FR-003a**: When visit creation succeeds from a `checked_in` appointment, the system MUST advance the linked appointment to `in_progress`.
- **FR-004**: The system MUST set initial visit status to `in_progress` on creation and support transition to `completed` when clinical staff submit the visit.
- **FR-004a**: When a visit is submitted as complete, the system MUST automatically set the linked appointment status to `completed` in the same secured operation (or equivalent atomic sequence).
- **FR-004b**: The system MUST NOT allow manual appointment `in_progress` → `completed` transitions via appointment status actions once V1-5 is active; appointment completion MUST occur through visit submission.
- **FR-004c**: The system MUST reject visit submit when all SOAP sections (Subjective, Objective, Assessment, Plan) are empty; at least one section MUST contain non-whitespace text. Treatment plans and attachments are NOT required for submit.
- **FR-005**: The system MUST copy `patient_id`, `doctor_id`, and `branch_id` from the linked appointment at visit creation when present; `visit_date` MUST reflect the appointment's clinical date.
- **FR-005a**: When the linked appointment has no `doctor_id`, the system MUST require the user to select a doctor from eligible branch doctors during visit creation; the selected doctor MUST be saved on **both** the visit and the appointment before the visit is created.
- **FR-006**: The system MUST enforce branch-scoped isolation for visit reads and writes via data-layer policies limited to the user's assigned branches within their organization.
- **FR-007**: The system MUST enforce permission key `visits.create` for visit creation at UI and server layers.
- **FR-008**: The system MUST enforce permission key `visits.edit_soap` for SOAP note save, treatment plan mutations, and marking visits complete at UI and server layers.
- **FR-009**: The system MUST introduce SOAP note storage with `subjective`, `objective`, `assessment`, `plan`, and `specialty_form_json` linked one-to-one with a visit.
- **FR-010**: The system MUST provide a structured SOAP editor with distinct S, O, A, and P sections and save capability that persists partial documentation.
- **FR-010a**: SOAP save MUST use optimistic concurrency (caller supplies expected `updated_at` or version); if the record changed since load, save MUST be rejected with a stale-data error and the client MUST prompt refresh before retry.
- **FR-011**: The system MUST support specialty-specific dynamic forms driven by a JSON schema configured for the clinic, storing responses in `specialty_form_json`.
- **FR-012**: The system MUST introduce treatment plan records linked to visit and patient with fields: medication name, dosage, frequency, start date, optional end date, and notes.
- **FR-013**: The system MUST support creating, updating, and soft-deleting treatment plan entries within a visit context for users with `visits.edit_soap`.
- **FR-014**: The system MUST introduce visit attachment records with file path reference, file type, label, uploader identity, and visit linkage.
- **FR-015**: The system MUST support upload and download of visit attachments in these types only: **PDF**, **DOCX**, and **photos** (JPEG and PNG). All other file types MUST be rejected with a message listing allowed types.
- **FR-016**: The system MUST enforce permission key `visits.upload_attachment` for attachment upload; `lab_staff` MUST receive this key in the V1-5 permission seed extension. Users with `visits.create` or `visits.edit_soap` MAY also upload without requiring `visits.upload_attachment`. Download MUST require `visits.create` or `visits.edit_soap` for any attachment on the visit, **except** users with `visits.upload_attachment` MAY download attachments they personally uploaded (`uploaded_by` matches caller).
- **FR-017**: The system MUST store attachment files in secure object storage scoped to the organization/branch with access enforced consistently with visit permissions.
- **FR-018**: The system MUST provide visit creation from the appointment context (`checked_in` or `in_progress` appointment → create visit → navigate to documentation).
- **FR-019**: The system MUST display visit history on the patient profile ordered by visit date descending (most recent first).
- **FR-020**: The system MUST show visit list metadata (date, doctor, status, branch) to users with `patients.view`; full SOAP, treatment plan, and attachment detail MUST require `visits.create` or `visits.edit_soap` (or owner/administrator full access).
- **FR-021**: The system MUST implement visit creation, SOAP save, treatment plan mutations, visit completion, and attachment metadata registration through secured server-side functions with permission, branch, and validation checks—not unguarded direct client writes for protected operations.
- **FR-022**: The system MUST apply doctor-specific access rules for SOAP mutations: users with `visits.edit_soap` at the visit's branch MAY edit SOAP for any visit at that branch (administrator/doctor workflow); RLS MUST prevent cross-branch SOAP access.
- **FR-023**: The system MUST record visit create, SOAP save, treatment plan changes, visit completion, and attachment upload events in the audit log with actor, action, target, and meaningful payload.
- **FR-024**: The system MUST create database indexes supporting visit lookups by patient and by branch/date per architecture.
- **FR-025**: The system MUST include backend verification utilities that validate visit creation rules, one-visit-per-appointment constraint, branch isolation, and attachment storage integration.
- **FR-026**: The system MUST derive requirements from the architecture documents listed under Required Architecture Docs and treat `specs/operations/visits.spec.md` as an external reference until authored.
- **FR-027**: The system MUST NOT deliver billing, invoice generation, shift management, prescription printing, workflow automation, or AI-assisted documentation as part of this feature.
- **FR-028**: The system MUST NOT auto-create visits when appointments are checked in or started; visit creation remains an explicit user action in V1-5.
- **FR-029**: The system MUST integrate with appointment status: visit submission completes the appointment; visit creation from `checked_in` advances the appointment to `in_progress`. Other patient, organization, branch, appointment booking, or staff management behavior changes only where visit screens integrate with patient profile, appointment queue/context, and active branch from prior features.

### Non-Functional Requirements

- **NFR-001**: Visit documentation screens must use plain language suitable for doctors and lab staff.
- **NFR-002**: SOAP save and visit completion must feel instantaneous under normal local clinic network conditions (perceived interactive response).
- **NFR-003**: Patient visit history with up to 500 visits must remain navigable with pagination or lazy loading.
- **NFR-004**: Attachment upload must provide progress feedback for files up to the configured maximum size.
- **NFR-005**: Permission and scope checks must follow defense in depth: client gating, server function validation, and data-layer isolation.
- **NFR-006**: Save and upload failures due to connectivity or validation errors must not leave the user believing the change was saved.

### Required Architecture Docs

- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Visits & Medical Records`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Audit Trail`, permission keys for visits
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

### External Spec Dependencies

- `specs/operations/visits.spec.md` is referenced by the roadmap but is not yet present. This specification captures visit and medical record expectations for V1-5 until that shared operations spec is authored.
- `specs/005-appointment-management` is a hard prerequisite: checked-in and in-progress appointments, patient/doctor linkage, and branch context must exist. V1-5 extends appointment completion semantics as documented in Clarifications.
- `specs/004-patient-management` is a hard prerequisite: patient registry and patient profile views must exist.
- `specs/003-org-branch-management` and `specs/002-auth-rbac` are hard prerequisites: active branch, staff/doctor identities, permissions, and session management must exist.

### Data Model

- **Visit**: Branch-scoped clinical encounter linked one-to-one to an appointment, with patient, doctor, visit date, and lifecycle status (`in_progress`, `completed`).
- **SOAP Note**: Structured documentation (S/O/A/P) plus optional specialty JSON linked one-to-one to a visit.
- **Treatment Plan**: Medication and instruction line items linked to a visit and patient; soft-deletable.
- **Visit Attachment**: Metadata record pointing to a stored file (PDF, DOCX, or photo) with file type, label, and uploader; linked to a visit.
- **Specialty Form Schema** (configuration): JSON schema defining additional structured fields for the clinic's specialty; not patient data—drives UI rendering for `specialty_form_json`.
- **Appointment** (existing): Scheduling record in `checked_in` or `in_progress` that allows visit creation; transitions to `completed` when the linked visit is submitted.
- **Patient** (existing): Subject of care; visit history displayed on patient profile.

No new core tenancy tables are required beyond visits, soap_notes, treatment_plans, visit_attachments, and their policies, indexes, storage bucket, and functions.

### RPC Functions

Exact names follow architecture; required capabilities:

- **Create visit**: Validate `visits.create`, appointment exists and is `checked_in` or `in_progress`, no existing visit for appointment, branch scope; if appointment is `checked_in`, advance to `in_progress`; if appointment has no `doctor_id`, require and persist doctor selection on appointment and visit; create visit with `in_progress` status; audit log.
- **Save SOAP note**: Validate `visits.edit_soap`, visit exists and branch scope; optimistic concurrency check on expected `updated_at`; create or update SOAP sections and specialty JSON; audit log.
- **Complete visit (submit)**: Validate `visits.edit_soap`, visit is `in_progress`, linked appointment is `in_progress`, at least one SOAP section non-empty; set visit status `completed` and appointment status `completed`; audit log both (may be combined with final SOAP save in planning).
- **Treatment plan mutations**: Validate `visits.edit_soap`, visit scope; create/update/soft-delete treatment plan rows; audit log.
- **Register attachment**: Validate `visits.upload_attachment` (or `visits.create` / `visits.edit_soap`), visit scope, allowed file type (PDF, DOCX, JPEG, PNG) and size; create attachment metadata after successful storage upload; audit log.

List/query capabilities for visit history by patient and visit detail by id are required (direct read via policies or list function per planning).

### Visit Status Rules

| From          | Allowed to  | Permission         |
| ------------- | ----------- | ------------------ |
| `in_progress` | `completed` | `visits.edit_soap` |
| `completed`   | (none)      | —                  |

SOAP and treatment plan edits on `completed` visits are allowed in V1-5 with audit trail (corrections before billing). Editing a completed visit does not revert the linked appointment from `completed`.

### Appointment Integration Rules

| Event                           | Appointment before | Appointment after         | Visit status        |
| ------------------------------- | ------------------ | ------------------------- | ------------------- |
| Create visit from `checked_in`  | `checked_in`       | `in_progress`             | `in_progress` (new) |
| Create visit from `in_progress` | `in_progress`      | `in_progress` (unchanged) | `in_progress` (new) |
| Submit visit complete           | `in_progress`      | `completed`               | `completed`         |

Manual appointment `in_progress` → `completed` without visit submission is not available in V1-5.

### RLS Policies

Policies on visit domain tables MUST enforce:

- Authenticated access only.
- Branch isolation: visit `branch_id` must be in the user's JWT `branch_ids` within their organization.
- SOAP-specific rules: mutations restricted to users with appropriate visit permissions at the visit's branch.
- Exclusion of soft-deleted rows from normal operational queries.
- No cross-tenant reads or writes in verification scenarios.
- Direct INSERT/UPDATE/DELETE on domain tables denied; mutations via secured functions only.

### API Contracts

- Create visit from checked-in or in-progress appointment.
- Save SOAP note (create/update).
- Submit visit complete (visit + appointment completion).
- Treatment plan create, update, soft-delete within visit.
- Upload visit attachment (PDF, DOCX, or photo — storage + metadata registration).
- Download visit attachment.
- List visits for patient (history).
- Get visit detail (SOAP, treatment plans, attachments).

Billing, shift, and AI APIs remain out of scope.

### UI States

- **Visit Create (from appointment) - Available (`checked_in`/`in_progress`) / Doctor selection required (no appointment doctor) / Appointment not eligible / Visit already exists / Submitting / Success / Permission Denied / Error**
- **SOAP Editor - Empty / Partial / Saving / Saved / Stale conflict (refresh prompt) / Validation Error / Permission Denied / Read-only (no clinical permission)**
- **Specialty Form - Schema loaded / No schema / Validation Error / Saved**
- **Treatment Plans - List / Add form / Edit / Remove confirm / Empty / Permission Denied**
- **Attachments - List / Uploading / Upload success / Upload error (type/size/network) / Download / Permission Denied**
- **Visit Submit Complete - Confirm / Submitting / Success (visit + appointment completed) / Error**
- **Patient Visit History - Loading / List / Empty / Detail open / Permission Denied (detail) / Error**

Navigation integrates with appointment queue and in-progress context, patient profile from patient management, and active branch from V1-2.

### Validation Rules

- Visit creation requires appointment in `checked_in` or `in_progress` within user's branch scope.
- When appointment has no `doctor_id`, doctor selection from eligible branch doctors is required before visit creation completes.
- SOAP sections accept text up to schema-defined maximum lengths.
- Specialty form fields validate against configured JSON schema (required fields, types, ranges).
- Treatment plan requires medication name; dosage, frequency, dates, and notes optional unless schema mandates.
- Attachment uploads: allowed types PDF, DOCX, JPEG, and PNG only; maximum file size defined in planning (e.g., 25 MB default per file).
- Attachment label optional with reasonable length limit.
- Visit completion allowed only from `in_progress` status and only when at least one SOAP section contains non-whitespace text.

### AI Hooks

This feature introduces no AI-assisted workflow. SOAP documentation remains fully manual. AI SOAP summarizer (V2) must not be required for any V1-5 acceptance scenario; when AI is added later, all AI-generated clinical content requires doctor approval per product principles.

### Audit Requirements

- Visit create MUST write audit log entry.
- SOAP save MUST write audit log entry with meaningful change indication.
- Treatment plan create, update, and soft-delete MUST write audit log entries.
- Visit submit complete MUST write audit log entries for both visit completion and linked appointment status change to `completed`.
- Attachment upload MUST write audit log entry with file metadata (not file content).
- Routine visit history reads are not individually audited unless architecture mandates access logging later.

### Acceptance Criteria

1. User with `visits.create` can create a visit from a `checked_in` or `in_progress` appointment; duplicate visits and ineligible appointment statuses are rejected; `checked_in` appointments advance to `in_progress` on visit create.
2. User without `visits.create` cannot create visits.
3. User with `visits.edit_soap` can save SOAP sections and specialty JSON; user without it cannot.
4. User with `visits.edit_soap` can add, edit, and remove treatment plan entries.
5. Authorized user can upload PDF, DOCX, and photo attachments and download them; disallowed types and oversize files are rejected.
6. Lab staff with `visits.upload_attachment` (without `visits.edit_soap`) can upload attachments and download their own uploads; cannot download others' attachments or access SOAP.
7. User with `patients.view` sees visit history metadata on patient profile; full detail requires clinical visit permissions.
8. Visit submit transitions visit to `completed` and linked appointment to `completed` with audit entries; submit with all SOAP sections empty is rejected.
9. Backend verification utilities demonstrate one-visit-per-appointment, eligible-status enforcement, branch isolation, and cross-organization denial.
10. No billing, shift, prescription, workflow automation, or AI workflow is required to pass this feature.

### Test Cases

1. Create visit from `in_progress` appointment; verify linkage and visit `in_progress` status.
2. Create visit from `checked_in` appointment; verify visit created and appointment advanced to `in_progress`.
2b. Create visit from appointment with no `doctor_id`; verify doctor selection prompt, doctor saved on visit and appointment.
3. Attempt visit from `scheduled` appointment; verify rejection.
4. Attempt second visit for same appointment; verify rejection.
5. Save SOAP all sections; reload and verify persistence.
6. Save partial SOAP; verify allowed.
6b. Simulate concurrent SOAP save from two sessions; verify stale save rejected with refresh prompt.
7. Configure specialty schema; fill and save dynamic fields; verify persistence.
8. Add, edit, remove treatment plan entries; verify list and audit.
9. Upload PDF, DOCX, and photo attachments; download each and verify integrity.
9b. Lab staff downloads own upload succeeds; download of another user's attachment denied.
10. Attempt disallowed file type (e.g., executable or spreadsheet); verify rejection with allowed-types message.
11. Submit visit complete with at least one SOAP section filled; verify visit `completed`, linked appointment `completed`, and patient history entry.
11b. Attempt submit with all SOAP sections empty; verify rejection and both remain `in_progress`.
12. View visit history as receptionist (`patients.view` only); verify metadata visible, SOAP hidden.
13. View visit detail as doctor; verify full access.
14. Attempt visit creation without permission; verify denial.
15. Cross-branch visit access attempt; verify denial.
16. Run backend verification utilities for creation rules, appointment integration, isolation, and attachment integration.

### Implementation Constraints

- MUST build on completed `specs/002-auth-rbac`, `specs/003-org-branch-management`, `specs/004-patient-management`, and `specs/005-appointment-management`.
- Domain validation and authorization source of truth for mutations MUST live in database functions and policies—not solely in client logic.
- MUST use architecture schema conventions; hard delete is not used for visit domain records.
- MUST NOT implement billing, shift, prescription, workflow automation, or AI schemas or screens in this feature.
- Cloud-only deployment enhancements are out of scope unless already supported by the local deployment path from V1-0.

### Key Entities *(include if feature involves data)*

- **Visit**: Branch-scoped clinical encounter linked one-to-one to an appointment; created while appointment is `checked_in` or `in_progress`.
- **SOAP Note**: Structured S/O/A/P documentation plus specialty JSON for a visit.
- **Treatment Plan**: Medication and care instruction line item for a patient within a visit.
- **Visit Attachment**: File metadata (PDF, DOCX, or photo) linked to a visit.
- **Appointment** (existing): Scheduling record that becomes eligible for visit creation at `checked_in` or `in_progress` and reaches `completed` when the linked visit is submitted.
- **Patient** (existing): Subject of care; visit history anchor on patient profile.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch outpatient clinics where doctors start visits from checked-in or in-progress appointments, document encounters, submit visits to complete appointments, and lab staff attach PDF, DOCX, and photo results. Hospital inpatient charts, e-prescribing with drug interaction checks, external lab integrations, and enterprise EMR exchange are out of scope.
- **Layer Placement**: The desktop client owns visit creation flow from eligible appointments, SOAP and specialty form editors, treatment plan UI, visit submit action, attachment upload/download presentation, patient visit history, permission-aware controls, and validation messaging. The backend platform owns secured create/save/submit functions, appointment status integration on visit submit, object storage for visit attachments, and audit writes. The database layer owns visit domain schemas, branch isolation policies, one-visit-per-appointment constraint, appointment–visit status coupling, indexes, and verification utilities. The AI layer remains absent in V1-5.
- **Data Integrity & Security**: Mutations use audit conventions; row-level policies preserve branch isolation within the organization; permission keys gate operations; one visit per appointment is enforced server-side; visit submit atomically completes the linked appointment; defense in depth applies across UI, secured functions, storage policies, and database policies.
- **Failure Handling**: Save and upload failures surface clear errors without false success; visit history shows last known good data with connectivity messaging when degraded; storage unavailability blocks uploads/downloads but allows SOAP saves; AI unavailability does not affect visit workflows; subscription state does not block core clinical documentation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 95% of test runs, authorized users create a visit from a checked-in or in-progress appointment and reach the documentation screen within 15 seconds under normal local clinic network conditions.
- **SC-002**: In 100% of visit creation test scenarios, appointments outside `checked_in`/`in_progress` and duplicate visits for the same appointment are rejected; `checked_in` appointments advance to `in_progress` on visit create.
- **SC-003**: In 100% of SOAP save test scenarios, authorized users persist documentation and retrieve it unchanged on reload.
- **SC-004**: In 100% of permission test scenarios, users without `visits.create` cannot create visits and users without `visits.edit_soap` cannot save SOAP or treatment plans.
- **SC-005**: In 100% of attachment test scenarios, valid PDF, DOCX, and photo uploads succeed and disallowed types or oversize files are rejected with clear errors.
- **SC-006**: In 100% of patient history test scenarios, users with `patients.view` see visit list metadata and users without clinical permissions cannot access SOAP content.
- **SC-007**: In 100% of backend verification scenarios, cross-organization visit access is blocked.
- **SC-008**: Doctors can complete a full visit workflow (create from in-progress appointment → SOAP → treatment plan → attachment → submit) in under 10 minutes in usability testing with representative sample data; linked appointment shows `completed` after submit.

## Assumptions

- `specs/002-auth-rbac`, `specs/003-org-branch-management`, `specs/004-patient-management`, and `specs/005-appointment-management` are implemented.
- Permission keys `visits.create` and `visits.edit_soap` are seeded for owner, administrator, and doctor roles per V1-1; receptionist does not receive visit keys by default.
- V1-5 adds permission key **`visits.upload_attachment`** seeded for `lab_staff`; owner, administrator, and doctor roles receive it as part of the V1-5 seed extension (clinical staff may upload via `visits.create` / `visits.edit_soap` without requiring the upload key). Lab staff may download only attachments they uploaded; full visit attachment download requires `visits.create` or `visits.edit_soap`.
- V1-4 does not auto-create visits; clinical staff explicitly create visits in V1-5 from `checked_in` or `in_progress` appointments.
- Appointment `completed` status in V1-5 is driven by visit submission, superseding manual `in_progress` → `completed` appointment status actions from V1-4.
- Visit attachment allowed types in V1-5 are PDF, DOCX, and photos (JPEG and PNG); this spec supersedes narrower PDF-only wording in earlier product overview for lab/examination scope.
- Default maximum attachment upload size is 25 MB per file unless planning defines otherwise.
- Specialty form schema configuration UI may be minimal in V1-5 (e.g., seeded or settings JSON); full schema admin UI can be deferred if one active schema per organization suffices for MVP.
- Treatment plans do not auto-create follow-up appointments or reminders; doctors schedule follow-ups manually (per product overview).
- `specs/operations/visits.spec.md` will be authored later; this feature spec is authoritative for V1-5 until that shared spec exists.
- AI remains optional and non-blocking for all visit and documentation flows in V1-5.
