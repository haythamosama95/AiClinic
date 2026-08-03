# Feature Specification: Visits Page Redesign

**Feature Branch**: `ui/013-visits`

**Created**: 2026-06-28

**Status**: Draft

**Input**: User description: "The Visits page requires significant frontend and backend changes. The existing visit data model should be replaced with structured clinical documentation: Complaint, History, Examination, Diagnosis, Plan; vital signs; treatments from a searchable medication catalog; required investigations from a searchable catalog; and unchanged attachments. Doctors can add custom catalog entries when predefined items are unsuitable. This completely replaces the visits documentation page."

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

Outpatient clinics document each patient encounter during a visit. The current visit documentation model uses SOAP sections (Subjective, Objective, Assessment, Plan) and optional specialty-specific structured forms. Clinical staff have requested a documentation layout that matches how doctors naturally record encounters: chief complaint, history of present illness, physical examination findings, clinical diagnosis, and treatment plan — alongside vital signs, prescribed treatments, ordered investigations, and supporting file attachments.

This feature **replaces** the visit documentation experience and its underlying clinical data model while **preserving** visit lifecycle behavior from V1-5: visit creation from checked-in or in-progress appointments, one visit per appointment, branch-scoped records, visit completion that advances the linked appointment to completed, treatment plan line items, file attachments (PDF, DOCX, JPEG, PNG), patient visit history, and existing permission keys. All visits use **only** the new documentation and detail views; SOAP notes, specialty form schemas on visits, and all related frontend and backend code and storage are **fully removed** with no legacy display paths.

Primary users are **doctors** documenting encounters during consultations. **Lab staff** continue uploading attachments. **Administrators** and clinical staff with read access review completed visit records from patient profiles. The redesigned page must support rapid data entry during live consultations.

## Clarifications

### Session 2026-06-28

- Q: When a doctor adds a custom medication, investigation, or vital sign not found in the catalog, should that name be available for future visits in the searchable catalog? → A: **Optional prompt** — after entering a custom name, the doctor is asked whether to save it to the organization catalog for reuse on future visits; declining saves visit-line only. The frontend MUST normalize custom names before display and persistence (e.g., leading capital letter, trim whitespace, collapse repeated spaces) so custom entries match catalog entry formatting.
- Q: How should existing visits with legacy SOAP notes and specialty form data display on the new visit detail screen? → A: **New view only** — all visits use the new documentation and detail views exclusively; SOAP notes, specialty form data, and all related frontend and backend components are completely removed with no legacy sections, dual-read paths, or separate legacy screens.
- Q: Before SOAP storage is removed from the backend, what should happen to existing SOAP/specialty content already saved on visits? → A: **Discard** — legacy SOAP and specialty content is not migrated; legacy tables and data are dropped; visits documented before the redesign show empty new clinical note sections.
- Q: After a visit is completed/submitted, can doctors still edit the new clinical note, vital signs, treatments, and investigations? → A: **Editable after submit** — clinical note, vital signs, treatments, and investigations remain editable on completed visits, consistent with V1-5 treatment plan edit behavior and existing documentation edit permissions.
- Q: Existing V1-5 treatment plan lines use start/end dates; the new model uses free-text duration. What should happen to existing treatment data? → A: **Duration only** — treatment lines use a single free-text duration field; start date, end date, and all other legacy date fields are removed from frontend and backend. Existing rows are migrated by best-effort conversion from start/end dates into duration where possible; otherwise duration is left empty.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document Clinical Note Sections (Priority: P1)

As a doctor with visit documentation permission, I can record Complaint, History, Examination, Diagnosis, and Plan as free-text sections for an in-progress visit so the clinic maintains a structured clinical note aligned with common outpatient documentation practice.

**Why this priority**: The five clinical text sections are the core medical record content; without them the redesign delivers no clinical value.

**Independent Test**: Open an in-progress visit, enter text in one or more sections with contextual hints visible, save, leave, and return to verify content persisted and displays correctly on the visit detail view.

**Acceptance Scenarios**:

1. **Given** an in-progress visit and a user with documentation edit permission, **When** they enter text in Complaint, History, Examination, Diagnosis, or Plan and save, **Then** the content is stored with the visit and associated audit tracking.
2. **Given** the visit documentation screen, **When** the user views empty fields, **Then** contextual hints guide entry: Complaint ("The patient's main reason for the visit."), Examination ("Physical examination findings."), Diagnosis ("Clinical assessment or diagnosis."), Plan ("Treatment plan, follow-up instructions, and patient advice.").
3. **Given** an existing clinical note, **When** the user updates any section and saves, **Then** changes persist; concurrent edits from another session are rejected with a clear refresh prompt (no silent overwrite).
4. **Given** a user without documentation edit permission, **When** they attempt to save clinical note content, **Then** the action is blocked at user interface and server layers.
5. **Given** a visit at a branch outside the user's scope, **When** they attempt to edit documentation, **Then** access is denied.

---

### User Story 2 - Record Vital Signs (Priority: P1)

As a doctor documenting a visit, I can add zero or more vital signs — selecting from predefined options or entering custom ones — each with a name, value, and optional unit, so physiological measurements are captured with the encounter.

**Why this priority**: Vital signs are recorded at nearly every consultation and are part of the minimum viable documentation workflow alongside clinical text.

**Independent Test**: Add multiple vital signs to a visit using both predefined and custom entries, save, reload, edit one entry, remove another, and verify the list reflects changes.

**Acceptance Scenarios**:

1. **Given** an in-progress visit, **When** the user adds a vital sign by selecting a predefined option (e.g., Blood Pressure, Heart Rate, Temperature, Respiratory Rate, Oxygen Saturation, Weight, Height), **Then** the name and default unit (when applicable) are prefilled and the user supplies the value before saving.
2. **Given** no suitable predefined vital sign, **When** the user enters a custom name, value, and unit, **Then** the name is normalized by the client to match catalog formatting, the entry is saved linked to the visit, and the user is optionally prompted to add the normalized name to the organization predefined vital signs catalog.
3. **Given** multiple vital sign entries on a visit, **When** the user views the documentation screen, **Then** all active entries are listed and can be edited or removed individually.
4. **Given** a visit with no vital signs, **When** the user saves other documentation, **Then** save succeeds without requiring vital signs.

---

### User Story 3 - Prescribe Treatments from Medication Catalog (Priority: P1)

As a doctor documenting a visit, I can add zero or more treatments by searching a medication catalog while typing, selecting a match, or entering a custom medication, and recording dose, frequency, duration, and an optional note for each line.

**Why this priority**: Prescribing treatments is a primary clinical output and must be as fast as free-text documentation during consultations.

**Independent Test**: Type partial medication names, select catalog results, add a custom medication, fill dose/frequency/duration for each line, save, and verify all treatment lines persist on reload.

**Acceptance Scenarios**:

1. **Given** an in-progress visit and a searchable medication catalog, **When** the user types in the medication field, **Then** matching catalog medications appear within interactive typing speed (results visible before the user pauses typing).
2. **Given** catalog search results, **When** the user selects a medication, **Then** the treatment line records the catalog medication and the user completes dose, frequency, duration, and optional note.
3. **Given** no catalog match, **When** the user enters a custom medication name and completes required treatment fields, **Then** the name is normalized by the client (capitalization, trimmed whitespace) to match catalog formatting, the custom treatment is saved linked to the visit, and the user is optionally prompted to add the normalized name to the organization medication catalog for future searches.
4. **Given** multiple treatment lines, **When** the user adds, edits, or removes lines, **Then** changes persist with audit tracking and appear on the visit detail view.
5. **Given** a treatment line missing required fields (medication name, dose, frequency, or duration), **When** the user attempts to save that line, **Then** field-level validation errors are shown.

---

### User Story 4 - Order Required Investigations (Priority: P2)

As a doctor documenting a visit, I can add zero or more required investigations by searching an investigations catalog while typing, selecting a match, or entering a custom investigation name, with an optional note per investigation.

**Why this priority**: Ordering labs and imaging is common but secondary to clinical note and treatment entry; it extends the documentation model without blocking core note capture.

**Independent Test**: Search investigations catalog, add catalog and custom investigations with notes, save, reload, and verify persistence.

**Acceptance Scenarios**:

1. **Given** an in-progress visit and a searchable investigations catalog, **When** the user types in the investigation field, **Then** matching catalog investigations appear with fast filtering while typing.
2. **Given** a selected catalog investigation, **When** the user optionally adds a note and saves, **Then** the investigation line is stored linked to the visit.
3. **Given** no catalog match, **When** the user enters a custom investigation name, **Then** the name is normalized by the client to match catalog formatting, the custom investigation is saved linked to the visit, and the user is optionally prompted to add the normalized name to the organization investigations catalog.
4. **Given** multiple investigation lines, **When** the user edits or removes a line, **Then** changes persist and inactive lines no longer appear in active visit views.

---

### User Story 5 - Complete Visit with Unchanged Attachments (Priority: P2)

As clinical or lab staff, I can continue uploading, listing, and downloading visit attachments (PDF, DOCX, JPEG, PNG) and submit a visit when documentation requirements are met, so supporting documents and visit completion workflows remain reliable.

**Why this priority**: Attachments and visit submission are established V1-5 capabilities that must not regress during the documentation model migration.

**Independent Test**: Upload allowed attachment types, download attachments per existing permission rules, complete a visit with at least one clinical text section filled, and verify the linked appointment advances to completed.

**Acceptance Scenarios**:

1. **Given** an in-progress visit with at least one clinical text section containing content, **When** the user submits the visit, **Then** the visit status becomes completed and the linked appointment advances to completed per V1-5 rules.
2. **Given** all five clinical text sections are empty, **When** the user attempts to submit, **Then** submission is rejected with a clear message that at least one clinical section must contain content.
3. **Given** existing attachment upload and download permission rules from V1-5, **When** staff upload or download attachments on a visit, **Then** behavior, allowed file types, and authorization rules are unchanged.
4. **Given** a completed visit and a user with documentation edit permission, **When** they open visit documentation or detail, **Then** clinical note sections, vital signs, treatments, and investigations remain editable (not read-only), consistent with V1-5 post-submit treatment plan behavior.

---

### User Story 6 - View Visit Documentation on Detail Screen (Priority: P2)

As staff with clinical read access, I can view a completed or in-progress visit's full documentation — clinical sections, vital signs, treatments, investigations, and attachments — on the visit detail screen so I can review the encounter record.

**Why this priority**: Read access is essential for care continuity and administrative oversight after documentation is captured.

**Independent Test**: Open visit detail for a visit with populated documentation; verify all sections render correctly; on completed visits with edit permission, verify documentation sections remain editable.

**Acceptance Scenarios**:

1. **Given** a visit with saved documentation, **When** an authorized user opens visit detail, **Then** Complaint, History, Examination, Diagnosis, Plan, vital signs, treatments, investigations, and attachments are displayed in a scannable layout.
2. **Given** a completed visit and a user with documentation edit permission, **When** they open visit detail or documentation, **Then** clinical note sections, vital signs, treatments, and investigations are editable; attachments follow existing V1-5 upload/download rules.
3. **Given** a visit with empty optional collections (no vital signs, treatments, or investigations), **When** visit detail loads, **Then** empty sections are handled gracefully without error.
4. **Given** a user without clinical read permission for the visit's branch, **When** they attempt to open visit detail, **Then** access is denied.
5. **Given** a user without documentation edit permission, **When** they view a completed visit, **Then** clinical note sections, vital signs, treatments, and investigations display read-only.

---

### Edge Cases

- What happens when catalog search returns no results while typing? The user can continue with a custom medication, investigation, or vital sign name without leaving the documentation flow; the client normalizes the typed name before save.
- What happens when the doctor declines adding a custom entry to the org catalog? Only the visit line retains the normalized custom name; future visits do not surface it in catalog search.
- What happens when the doctor accepts adding a custom entry to the org catalog? The normalized name is persisted to the organization catalog and becomes searchable on future visits within that organization.
- What happens when the doctor enters a custom name with irregular casing or extra spaces (e.g., "  amoxicillin ")? The client trims whitespace, applies leading capitalization, and collapses internal repeated spaces before display, save, and any catalog prompt — matching the visual style of catalog entries.
- What happens when the user adds duplicate catalog medications or investigations on the same visit? Duplicate lines are allowed unless business rules later restrict them; each line is independently editable and removable.
- What happens when predefined vital sign default units differ from what the clinician needs? The user can override the unit on save.
- What happens when AI-assisted drafting is unavailable? Documentation remains fully manual; no AI dependency is introduced by this feature. Future AI assistance (V2) is out of scope.
- What happens when network or backend connectivity is degraded? The client shows clear save errors; unsaved local edits are not presented as persisted. Users must retry when connectivity returns. Offline draft persistence is out of scope unless covered by a separate feature.
- What happens when a user lacks tenant-scoped or branch-scoped permission? All documentation reads and writes are denied at user interface and server layers with no data leakage across branches.
- What happens to existing visits with SOAP notes and specialty form data? Legacy SOAP and specialty content is **not migrated**. Legacy tables and stored content are dropped as part of this feature. Visits documented before the redesign display empty new clinical note sections; vital signs, treatments, investigations, and attachments from V1-5 remain visible where they exist.
- What happens when treatment duration is expressed in varied formats (e.g., "7 days", "2 weeks")? Free-text duration is accepted; strict format validation is not required. Start and end dates are not supported.
- What happens to existing treatment lines with start/end dates? Dates are removed; duration is populated by best-effort conversion from the date pair where possible, otherwise left empty.
- What happens when a user edits documentation on a completed visit? Edits are allowed for users with documentation edit permission; changes persist with audit tracking and optimistic concurrency, matching V1-5 post-submit treatment plan behavior. Users without edit permission see read-only content.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST replace visit clinical documentation storage with five free-text fields per visit: Complaint, History, Examination, Diagnosis, and Plan. Each field MUST accept up to 10,000 characters.
- **FR-002**: The visit documentation user interface MUST display contextual hints for Complaint, Examination, Diagnosis, and Plan as specified in the feature description; History represents history of present illness without an additional mandated hint.
- **FR-003**: The system MUST support zero or more vital signs per visit. Each vital sign MUST include name, value, and optional unit.
- **FR-004**: The system MUST provide organization-scoped predefined vital signs (including Blood Pressure, Heart Rate, Temperature, Respiratory Rate, Oxygen Saturation, Weight, and Height as development samples) while allowing custom vital signs when no predefined option fits. After entering a custom vital sign name, the system MUST prompt the doctor whether to save the normalized name to the organization catalog for future reuse; declining MUST save visit-line only.
- **FR-005**: The system MUST support zero or more treatments per visit. Each treatment MUST include medication, dose, frequency, duration (free text), and optional note. Start date, end date, and any other legacy treatment date fields MUST NOT be retained.
- **FR-006**: Treatments MUST be selectable from a searchable organization-scoped medication catalog with fast filtering while typing; custom medications MUST be allowed when no catalog match is suitable. After entering a custom medication name, the system MUST prompt the doctor whether to save the normalized name to the organization catalog for future reuse; declining MUST save visit-line only.
- **FR-006a**: The visit documentation client MUST normalize custom medication, investigation, and vital sign names before display and persistence: trim leading/trailing whitespace, capitalize the first character, collapse repeated internal spaces, and apply any other lightweight text sanity rules needed so custom entries visually match catalog entries.
- **FR-007**: The system MUST support zero or more required investigations per visit. Each investigation MUST include a name and optional note.
- **FR-008**: Investigations MUST be selectable from a searchable organization-scoped investigations catalog with fast filtering while typing; custom investigations MUST be allowed when no catalog match is suitable. After entering a custom investigation name, the system MUST prompt the doctor whether to save the normalized name to the organization catalog for future reuse; declining MUST save visit-line only.
- **FR-009**: Visit attachments MUST remain functionally unchanged from V1-5: allowed file types (PDF, DOCX, JPEG, PNG), upload/download authorization, storage, and user interface behavior.
- **FR-010**: The system MUST seed sample medications, investigations, and predefined vital signs for development and demonstration environments.
- **FR-011**: Visit submission MUST require at least one clinical text section (Complaint, History, Examination, Diagnosis, or Plan) to contain non-empty content; vital signs, treatments, investigations, and attachments remain optional for submission.
- **FR-012**: The system MUST completely remove SOAP note storage, specialty form schema usage on visits, `save_soap_note` and related RPCs, specialty form rendering, and all legacy visit documentation UI from frontend and backend. Visit detail and documentation screens MUST expose only the new clinical note model with no legacy SOAP or specialty views or dual-read code paths. Legacy SOAP and specialty **data** MUST NOT be migrated; existing content in legacy tables is discarded when those tables are dropped.
- **FR-013**: Clinical documentation saves MUST enforce branch-scoped and permission-gated access consistent with existing visit edit permissions; stale concurrent saves MUST be rejected with a user-visible error (optimistic concurrency).
- **FR-014**: Catalog search for medications and investigations MUST return relevant matches as the user types without requiring a separate search action.
- **FR-015**: The visit documentation page MUST allow adding, editing, and removing multiple vital signs, treatments, and investigations within a single visit session with a layout optimized for rapid consultation data entry.
- **FR-016**: Visit creation, one-visit-per-appointment rule, visit completion handoff to appointment status, patient visit history listing, and backend-first data loading for visit screens MUST continue to follow V1-5 behavior unless explicitly superseded by a requirement in this spec.
- **FR-017**: Clinical note sections, vital signs, treatments, and investigations MUST remain editable on completed visits for users with documentation edit permission, consistent with V1-5 post-submit treatment plan editing. Users without edit permission MUST see these sections read-only.
- **FR-018**: The treatment data model MUST use duration as the sole time-related field. Legacy start date and end date columns, user interface inputs, and API parameters MUST be removed. A one-time migration MUST convert existing start/end date pairs into a duration string where both dates exist; otherwise duration is left empty.

### Key Entities

- **Visit**: Clinical encounter linked to appointment, patient, doctor, and branch; status in progress or completed. Retains lifecycle from V1-5; documentation content model changes.
- **Clinical Note**: One set of five free-text sections (Complaint, History, Examination, Diagnosis, Plan) per visit with audit and concurrency metadata.
- **Predefined Vital Sign**: Organization-scoped catalog entry with name and optional default unit; referenced by visit vital sign lines or bypassed for custom entries.
- **Visit Vital Sign**: Measurement recorded during a visit: name, value, optional unit; optionally linked to a predefined vital sign.
- **Medication**: Organization-scoped catalog entry searchable during treatment entry; referenced by treatment lines or bypassed for custom medication names.
- **Treatment**: Medication line on a visit with dose, frequency, duration (free text, sole time-related field), and optional note; optionally linked to a catalog medication. Legacy start/end date fields are removed.
- **Investigation**: Organization-scoped catalog entry searchable during investigation ordering.
- **Visit Investigation**: Investigation ordered during a visit with name and optional note; optionally linked to a catalog investigation.
- **Visit Attachment**: Unchanged supporting file linked to a visit per V1-5.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch outpatient clinics where doctors document encounters quickly at the desktop during consultations. The five-section clinical note and inline vital signs, treatments, and investigations match common private-clinic workflows. Hospital-grade order sets, CPOE integrations, and enterprise medication formularies are out of scope.
- **Layer Placement**: **Flutter** owns the redesigned visit documentation and detail presentation, client-side validation, catalog search orchestration, and optimistic UI feedback. **Supabase** exposes authenticated RPC access, storage for attachments, and authorization enforcement. **PostgreSQL** owns the clinical note schema, catalog tables, child visit records, constraints, RLS policies, transactional saves, and visit completion logic. **AI service** is not involved in this feature; documentation is manual entry only.
- **Data Integrity & Security**: All documentation and catalog writes MUST be branch-scoped via visit linkage and enforced with RLS plus RPC validation. Organization-scoped catalogs MUST be tenant-isolated. Catalog references on visit lines MUST remain valid or gracefully support denormalized custom names when catalog entries are archived. Audit fields and soft deletion MUST follow shared schema conventions. Existing visit permission keys (e.g., create, edit documentation, upload attachment) MUST gate actions; no broadening of clinical access is implied.
- **Failure Handling**: When the backend is unavailable, saves and catalog searches fail with clear errors; the UI MUST NOT imply success. Attachment flows degrade per existing V1-5 behavior. AI unavailability has no effect because this feature does not depend on AI. When catalog search times out, the user can still enter custom names to continue documentation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Doctors can complete a full visit documentation session — clinical sections, at least one vital sign, one treatment, and one investigation — in under 5 minutes on a reference desktop workflow without using legacy SOAP or specialty form screens.
- **SC-002**: Medication and investigation catalog searches return filtered results before the user pauses typing in 95% of interactions under normal clinic network conditions.
- **SC-003**: 100% of visit attachment upload, list, and download scenarios that passed V1-5 acceptance continue to pass after the redesign with no change to allowed file types or permission behavior.
- **SC-004**: At least 90% of doctors completing a moderated usability session report the new documentation layout as "efficient" or better for rapid consultation entry compared to the prior SOAP-based page.
- **SC-005**: Zero regression in visit completion rules: visits cannot be submitted with all clinical text sections empty, and successful submission still advances the linked appointment to completed.
- **SC-006**: Authorized users can view all documentation elements on visit detail for completed visits with populated data in a single screen flow using only the new documentation layout.

## Assumptions

- V1-5 visit lifecycle, permissions, attachments, treatment plan infrastructure, and patient visit history remain the foundation; this feature changes the documentation content model and visit page user experience.
- Existing `visits.edit_soap` (or equivalent documentation edit permission) applies to the new clinical note and related child records unless a follow-up permission rename is planned separately.
- Character limit of 10,000 per clinical text section matches prior SOAP section limits and is sufficient for outpatient notes.
- Treatment uses a single free-text **duration** field only; legacy start/end date fields are removed from schema, API, and UI. Existing treatment rows are migrated to duration where dates allow inference.
- Organization-scoped catalogs are shared across branches within an organization; branch-specific medication or investigation lists are out of scope.
- Sample catalog seed data is sufficient for development; clinics may grow catalogs organically when doctors accept optional save-to-catalog prompts for custom entries. Dedicated admin catalog management UI remains out of scope unless added in a follow-up feature.
- Custom catalog names are client-normalized (capitalization, whitespace trimming) before persistence and catalog prompts so they match existing catalog entry presentation.
- No legacy SOAP or specialty documentation UI or backend paths remain after this feature ships; visit screens are new-model only.
- Historical SOAP and specialty text is intentionally discarded (no one-time migration); clinics accept that pre-redesign visit clinical narrative content will not carry forward.
- Completed visits remain documentation-editable for authorized users, matching prior V1-5 treatment plan post-submit behavior.
- Searchable dropdowns filter client-side or via lightweight backend search; sub-second perceived response is the target under normal conditions.
- Mobile-specific visit documentation layouts are out of scope; desktop-first rapid entry is the primary design target per constitution.
