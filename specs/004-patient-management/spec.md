# Feature Specification: Patient Management

**Feature Branch**: `specs/004-patient-management`

**Created**: 2026-05-23

**Status**: Draft

**Input**: User description: "Read V1-3 from @docs/architecture/12-roadmap-phases.md and according to the best practices of speckit, create the fourth spec"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

This feature delivers patient registration and record management for a multi-branch clinic after authentication, organization/branch administration, and staff management exist. Reception and clinical staff need to register patients at a branch, find existing patients quickly (including across branches within the same clinic), view and update demographic and contact information, and archive patients who should no longer appear in day-to-day workflows—without appointment, visit, or billing modules.

The primary beneficiaries are receptionists who register and look up patients at the front desk, doctors and lab staff who need read access to patient profiles for upcoming clinical work, and administrators who oversee data quality across branches. Appointment scheduling (V1-4) and visit documentation (V1-5) depend on a trustworthy patient registry established here.

V1-2 (`specs/003-org-branch-management`) delivered organization settings, branch and staff management, the role-permission matrix, and the main-shell branch switcher. This feature introduces the `patients` domain: organization-wide visibility with a registering branch, permission-gated mutations, deduplication awareness at registration, and soft-delete archival consistent with platform conventions.

## Clarifications

### Session 2026-05-23

- Q: What does "medical history" on the patient detail page include in V1-3 before visits exist? → A: Profile summary (demographics, contact, notes) plus an empty or informational visits placeholder; no SOAP, treatment plans, or visit attachments until V1-5.
- Q: Who may register, edit, and archive patients? → A: Mutations require `patients.create`, `patients.edit`, and `patients.delete` respectively (typically receptionist and roles granted by the owner in the permission matrix); view requires `patients.view`.
- Q: How does cross-branch search relate to active branch? → A: List and quick search default to the active branch; an explicit org-wide search mode finds patients registered at any branch in the organization subject to `patients.view`.
- Q: What triggers deduplication warnings? → A: Before create (and optionally on edit), the system checks for likely duplicates using phone and national ID when provided, and name plus date of birth when both are present; matches are advisory unless policy blocks duplicate national ID within the organization.
- Q: Is patient archival reversible? → A: Archival sets soft-delete state (`is_deleted`); V1-3 UI provides archive with confirmation only—no restore UI; restoration remains a future admin or maintenance capability.
- Q: Can a patient be moved to another registering branch? → A: No in V1-3; `branch_id` is set at registration from active branch context and is not editable through patient management screens (corrections via future admin tooling if needed).
- Q: Do lab staff edit patients? → A: Lab staff may view patients when granted `patients.view`; create, edit, and archive follow the same permission keys as other roles unless the matrix grants them.
- Q: May staff edit or archive patients registered at branches they are not assigned to? → A: Yes — users with `patients.edit` or `patients.delete` may update or archive any non-archived patient in the organization (subject to permission keys and org RLS), regardless of registering branch or branch assignments; create remains tied to active branch.
- Q: How should branch and org-wide patient search match name and phone? → A: Phone uses prefix match (from the start of the stored number, minimum 2 digits/characters before search runs); full name uses case-insensitive contains match (substring anywhere in `full_name`, minimum 3 characters before search runs).
- Q: How do users switch between branch-scoped list and org-wide search? → A: A single patient list page with a scope control (e.g. “This branch only” / “All branches”) that switches list and search scope; the same search field and match rules apply in either mode.
- Q: How are concurrent edits to the same patient handled? → A: Optimistic conflict detection — update RPC compares `updated_at` (or equivalent version) to the value loaded when the form opened; if changed, save is rejected with a clear stale-data message and the user reloads before retrying.
- Q: What is the default patient list scope on first open after sign-in? → A: “This branch only” (active-branch registration scope) until the user switches to “All branches”; each new sign-in resets to this branch only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Register a New Patient (Priority: P1)

As a receptionist (or other role with patient-create permission), I can register a new patient at my active branch with validated demographic and contact fields so the clinic has a record before scheduling or clinical work.

**Why this priority**: Without registration, no downstream operational module can reference a patient.

**Independent Test**: Can be fully tested by signing in with create permission, completing registration at the active branch, and confirming the patient appears in the branch list and org-wide search.

**Acceptance Scenarios**:

1. **Given** a signed-in user with `patients.create` and an active branch, **When** they submit a valid registration form, **Then** a patient record is created with `branch_id` equal to the active branch, success is confirmed, and the patient appears in branch-scoped lists.
2. **Given** required fields are missing or invalid, **When** the user submits registration, **Then** field-level errors are shown and no record is created.
3. **Given** a likely duplicate exists (matching phone or national ID, or name plus date of birth per deduplication rules), **When** the user attempts to create, **Then** the system shows duplicate candidates and requires explicit confirmation to proceed or correction of identifiers.
4. **Given** a national ID already registered to another patient in the organization, **When** the user attempts to create with that national ID, **Then** creation is blocked with a clear message.
5. **Given** a user without `patients.create`, **When** they attempt registration, **Then** the action is blocked at UI and server layers.

---

### User Story 2 - Find and List Patients (Priority: P1)

As staff with patient-view permission, I can search and browse patients for my active branch and, when needed, across all branches in my organization so I can locate the right person quickly at the desk or in clinical prep.

**Why this priority**: Registration alone is insufficient without fast lookup during daily operations.

**Independent Test**: Can be fully tested by seeding patients at two branches, searching by name and phone from each branch context, and confirming org-wide search returns cross-branch matches while default list respects active branch.

**Acceptance Scenarios**:

1. **Given** a signed-in user with `patients.view` and an active branch, **When** they open the patient list for the first time after sign-in, **Then** the scope control defaults to “this branch only” and they see paginated patients registered at the active branch (non-archived), sortable by name, with search by name (contains, min 3 characters) and phone (prefix, min 2 characters).
2. **Given** the patient list scope control is set to all branches, **When** the user searches by name or phone using the same match rules, **Then** matching patients from any branch in the organization are returned with registering branch indicated.
3. **Given** the scope control is set to this branch only, **When** the user views the list without a search query, **Then** only patients registered at the active branch are shown.
4. **Given** no matching patients, **When** search completes, **Then** an empty state explains no results and offers registration when the user has create permission.
5. **Given** a user without `patients.view`, **When** they attempt to open the patient list, **Then** access is denied with clear messaging.
6. **Given** archived patients, **When** the user uses normal list or search, **Then** archived records do not appear.

---

### User Story 3 - View Patient Profile (Priority: P1)

As staff with patient-view permission, I can open a patient detail page to see profile information and notes so I can confirm identity and context before appointments or visits (in later phases).

**Why this priority**: Detail view is the hub for edit, archive, and future visit history.

**Independent Test**: Can be fully tested by opening a patient from the list and confirming all profile fields, registering branch, and visits placeholder display correctly.

**Acceptance Scenarios**:

1. **Given** a non-archived patient in the user's organization, **When** the user opens patient detail, **Then** they see full name, phone, date of birth, gender, national ID (if stored), notes, registering branch name, and audit summary (created/updated metadata readable to staff).
2. **Given** V1-3 scope, **When** the user views the medical history section, **Then** they see patient notes and an informational placeholder for visit history (no visit records until V1-5).
3. **Given** a patient outside the user's organization, **When** access is attempted via identifier, **Then** the request is denied without leaking existence.
4. **Given** an archived patient, **When** a user without elevated restore capability opens detail via direct link, **Then** access is denied or shows archived-not-available messaging per product policy.

---

### User Story 4 - Update Patient Information (Priority: P1)

As staff with patient-edit permission, I can update a patient's demographic and contact information and notes so records stay accurate over time.

**Why this priority**: Corrections and contact updates are daily front-desk work.

**Independent Test**: Can be fully tested by editing phone and notes, saving, and confirming persistence and audit; deduplication rules apply on national ID change.

**Acceptance Scenarios**:

1. **Given** a non-archived patient in the user's organization (including one registered at another branch) and `patients.edit`, **When** the user saves valid changes, **Then** updates persist, success is confirmed, and list/detail reflect new values.
2. **Given** invalid field values, **When** the user saves, **Then** validation errors prevent partial inconsistent state.
3. **Given** a national ID change that conflicts with another patient in the organization, **When** the user saves, **Then** the save is rejected with a clear message.
4. **Given** a user without `patients.edit`, **When** they attempt edit, **Then** the action is blocked.
5. **Given** deduplication check on edit, **When** phone or national ID matches another patient, **Then** the user receives a duplicate warning and must confirm or correct before save proceeds (except hard-blocked national ID conflict).
6. **Given** another user saved the same patient after this form was loaded, **When** the user submits an update, **Then** the save is rejected with a stale-data message and the user can reload the latest record and retry.

---

### User Story 5 - Archive a Patient (Priority: P2)

As staff with patient-delete permission, I can archive a patient with confirmation so inactive patients no longer appear in routine lists while retaining data for audit and future modules.

**Why this priority**: Archival is important for data hygiene but less frequent than register/search/edit.

**Independent Test**: Can be fully tested by archiving a patient, confirming disappearance from lists, and confirming the record cannot be edited through normal UI.

**Acceptance Scenarios**:

1. **Given** a non-archived patient in the user's organization (including one registered at another branch) and `patients.delete`, **When** the user confirms archival, **Then** the patient is soft-deleted, disappears from normal list/search, and an audit entry is recorded.
2. **Given** archival confirmation is cancelled, **When** the user dismisses the dialog, **Then** no change occurs.
3. **Given** a user without `patients.delete`, **When** they attempt archival, **Then** the action is blocked.
4. **Given** V1-3 scope, **When** a patient is archived, **Then** no in-app restore control is offered.

---

### Edge Cases

- Registration with only minimum required fields (full name) succeeds when optional fields are omitted; phone and national ID validation apply when provided.
- Org-wide search with very common name substrings must remain paginated and performant; empty and slow states show appropriate feedback.
- Search does not run until minimum query length is met (3 characters for name, 2 for phone); shorter input shows guidance without calling the server.
- User with `patients.view` at one branch can see org-wide search results for patients registered at branches they are not assigned to (organization visibility per architecture); branch-scoped default list still uses active branch.
- User with `patients.edit` or `patients.delete` may update or archive a patient registered at another branch in the same organization without switching active branch or holding an assignment to that branch.
- User switches active branch after opening patient list; when scope is “this branch only,” list refreshes to the new active branch; when scope is “all branches,” list remains org-wide but registering-branch labels stay accurate.
- Scope control selection persists for the session until sign-out; each new sign-in resets the default to “this branch only” (not the previous session’s scope).
- Backend unavailable during save must not show false success; lists show last known good data with connectivity messaging.
- AI services are not part of this feature; AI unavailability must not block any patient workflow.
- Archived patients must not appear in deduplication candidate lists for new registration.
- Cross-organization access attempts must remain blocked in all verification scenarios.
- Patient with future appointment or visit references (once those modules exist) is out of V1-3 scope; archival does not validate downstream dependencies in V1-3 (document assumption; planning may add guards when appointments ship).
- Permission grant changes follow V1-2 rules: client cache updates on auth-context reload; server enforces current grants immediately on RPC.
- Concurrent edits: second save while `updated_at` has advanced since form load is rejected; user reloads and retries (no silent overwrite, no field-level merge UI in V1-3).
- National ID field may be optional per clinic practice; when empty, deduplication relies on phone and name plus date of birth only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST introduce a `patients` store with fields aligned to architecture: registering `branch_id`, `full_name`, `phone`, `date_of_birth`, `gender`, `national_id`, `notes`, plus standard audit and soft-delete columns.
- **FR-002**: The system MUST set registering `branch_id` from the signed-in user's active branch at create time; branch reassignment is out of scope for V1-3.
- **FR-003**: The system MUST enforce organization isolation for all patient reads and writes via data-layer policies derived through branch organization membership.
- **FR-004**: The system MUST enforce permission keys `patients.view`, `patients.create`, `patients.edit`, and `patients.delete` at UI and server layers for view, register, update, and archive respectively.
- **FR-005**: The system MUST provide a patient list for the active branch with search (name, phone), pagination, and exclusion of archived records from normal views; name search uses case-insensitive contains on `full_name` (minimum 3 characters); phone search uses prefix match from the start of the stored phone value (minimum 2 characters).
- **FR-006**: The system MUST provide a scope control on the patient list page (e.g. “This branch only” / “All branches”) that switches list and search between active-branch registration scope and organization-wide scope, using the same name and phone match rules in both modes and showing registering branch on results when scope is all branches; default scope on first open after sign-in MUST be “this branch only,” resetting on each new sign-in.
- **FR-007**: The system MUST provide patient registration with client-side validation for required and formatted fields before server submission.
- **FR-008**: The system MUST provide patient detail showing profile fields, notes, registering branch, and a visits placeholder (no visit CRUD in V1-3).
- **FR-009**: The system MUST provide patient edit for authorized users with the same validation rules as registration except registering branch is not editable; edit applies to any non-archived patient in the organization, not only patients at the user's assigned or active branch; updates MUST use optimistic conflict detection via `updated_at` (or equivalent) and reject stale saves with an actionable error.
- **FR-010**: The system MUST provide patient archival (soft delete) with explicit confirmation for users with `patients.delete`; archival applies to any non-archived patient in the organization; archived patients MUST be hidden from normal list, search, and edit flows.
- **FR-011**: The system MUST implement a deduplication check before create (and on edit when identifiers change) returning likely matches by phone, national ID, and name plus date of birth when applicable.
- **FR-012**: The system MUST hard-block duplicate `national_id` values within the same organization on create and update.
- **FR-013**: The system MUST implement patient mutations through secured server-side functions with permission and scope validation, not unguarded direct client writes for protected operations.
- **FR-014**: The system MUST record patient create, update, and archive in the audit log with actor, action, target, and change payload.
- **FR-015**: The system MUST create database indexes supporting branch-scoped search by name and phone per architecture (`branch_id` with `full_name` and `branch_id` with `phone`).
- **FR-016**: The system MUST include backend verification utilities that validate patient CRUD, deduplication behavior, cross-branch visibility within an organization, and blocked cross-organization access.
- **FR-017**: The system MUST derive requirements from the architecture documents listed under Required Architecture Docs and treat `specs/operations/patients.spec.md` as an external reference until authored.
- **FR-018**: The system MUST NOT deliver appointment, visit, billing, shift, workflow, or AI workflows as part of this feature.
- **FR-019**: The system MUST NOT expose in-app restore of archived patients in V1-3.
- **FR-020**: The system MUST NOT change organization, branch, or staff management behavior except where patient screens integrate with active branch context and existing shell navigation.

### Non-Functional Requirements

- **NFR-001**: Patient management screens must use plain language suitable for reception staff.
- **NFR-002**: Branch-scoped list and search must remain usable with at least 500 patients per branch under normal local clinic network conditions without unacceptable delay.
- **NFR-003**: Org-wide search must return first page of results within perceived interactive time under normal local conditions for typical query lengths.
- **NFR-004**: Permission and scope checks must follow defense in depth: client gating, server function validation, and data-layer isolation.
- **NFR-005**: Save failures due to connectivity or validation errors must not leave the user believing data was saved.

### Required Architecture Docs

- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Patients`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Audit Trail`, `Soft Delete`, permission keys for patients
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

### External Spec Dependencies

- `specs/operations/patients.spec.md` is referenced by the roadmap but is not yet present. This specification captures patient management expectations for V1-3 until that shared operations spec is authored.
- `specs/003-org-branch-management` is a hard prerequisite: active branch context, branch switcher, staff permissions, and organization/branch administration must already be delivered.
- `specs/002-auth-rbac` is a hard prerequisite: authentication, JWT claims, RLS foundation, and session management must already be delivered.

### Data Model

- **Patient**: Person receiving care at the clinic. Key attributes: registering branch, full name, phone, date of birth, gender, national ID (optional but unique per organization when set), free-text notes. Organization scope is derived via registering branch. Lifecycle includes active and archived (soft-deleted) states.
- **Branch** (existing): Registering location; referenced for default list scope and display on cross-branch results.
- **Audit Log** (existing): Records patient create, update, and archive events.

No new core tenancy tables are required beyond the `patients` table and its policies, indexes, and functions.

### RPC Functions

Exact names are finalized in planning; required capabilities:

- **Search patients (branch-scoped)**: Paginated search for active branch; name: case-insensitive contains on `full_name` (query length ≥ 3); phone: prefix from start of stored value (query length ≥ 2); exclude archived; require `patients.view`.
- **Search patients (organization-wide)**: Cross-branch search within organization with the same name and phone match rules; exclude archived; require `patients.view`; include registering branch in results.
- **Get patient**: Single patient by id with organization scope check; require `patients.view`; reject archived for normal flows.
- **Check patient duplicates**: Accept candidate identifiers; return likely matches for advisory UI; used before create and on identifier change during edit.
- **Create patient**: Validate permission `patients.create`, active branch, field rules, national ID uniqueness, optional duplicate acknowledgment payload; set audit fields; audit log.
- **Update patient**: Validate permission `patients.edit`, organization scope, field rules, national ID uniqueness; accept client-supplied `updated_at` (or version) from form load and reject with a conflict error if the row changed since load; audit log on success only.
- **Archive patient**: Validate permission `patients.delete`, soft-delete with audit columns; audit log.

Simple reads that satisfy RLS and permission rules may use filtered table access where architecture allows; mutations MUST use RPC functions.

### RLS Policies

Policies on `patients` MUST enforce:

- Authenticated access only.
- Organization isolation: patient visible if registering branch belongs to the user's organization (per architecture org-isolation pattern).
- Archived rows (`is_deleted = true`) excluded from normal policy paths used by list, search, and detail.
- No cross-tenant reads or writes in verification scenarios.

Patient reads and mutations (except create) use organization isolation only—no additional branch-assignment filter on `patients` beyond org RLS. Permission keys (`patients.edit`, `patients.delete`) and RPC validation enforce authorized mutations; create remains scoped to the user's active branch at registration time.

### API Contracts

- List/search patients (branch-scoped and organization-wide).
- Get patient profile by id.
- Check duplicates for registration/edit.
- Create, update, and archive patient.
- Client supplies active branch context for registration; server validates membership.

Appointment, visit, billing, and AI APIs remain out of scope.

### UI States

- **Patient List - Loading / Loaded (this branch) / Loaded (all branches) / Scope switching / Empty / Error / Permission Denied**
- **Patient Registration - Initial / Validation Error / Duplicate Warning / Submitting / Success / Permission Denied**
- **Patient Detail - Loading / Loaded / Archived unavailable / Error / Permission Denied**
- **Patient Edit - Initial / Validation Error / Duplicate Warning / Submitting / Success / Stale conflict (reload required) / Permission Denied**
- **Archive Confirm - Active / Submitting / Success / Cancelled / Permission Denied**
- **Visits Placeholder on Detail - Informational only (no visit data in V1-3)**

Navigation integrates with the main app shell and respects active branch context from V1-2.

### Validation Rules

- Full name is required and non-empty after trim.
- Phone, when provided, must match clinic-configured format rules (planning defines locale-aware pattern; minimum length and digit validation).
- Date of birth, when provided, must be a valid calendar date not in the future.
- Gender, when provided, must be one of the product's allowed values (planning aligns with schema enum).
- National ID, when provided, must be unique within the organization and match format rules if defined in schema.
- Notes length must respect schema maximum.
- Duplicate advisory: at least one of phone, national ID, or name plus date of birth must match another non-archived patient to show warning.
- Patient list search: full name uses case-insensitive contains (minimum 3 characters); phone uses prefix match (minimum 2 characters); queries below minimum show inline guidance and do not invoke search.
- Archive requires explicit confirmation text or confirm action per product UX standards.

### AI Hooks

This feature introduces no AI-assisted workflow. Patient registration and search remain fully manual. AI-related permission keys may exist in the matrix but do not activate patient AI features in V1-3.

### Audit Requirements

- Patient create MUST write an audit log entry with new record payload.
- Patient update MUST write an audit log entry with meaningful before/after fields.
- Patient archive MUST write an audit log entry identifying soft-delete action.
- Routine list/search/get operations are not individually audited unless architecture mandates access logging later.

### Acceptance Criteria

1. User with `patients.create` can register a patient at the active branch; patient appears in branch list.
2. User without `patients.create` cannot register.
3. Branch-scoped search by name and phone returns expected patients; archived patients excluded.
4. Org-wide search returns patients from other branches in the same organization with branch label.
5. User with `patients.view` can open detail; visits section shows placeholder only.
6. User with `patients.edit` can update allowed fields; national ID conflict rejected.
7. Duplicate warning appears when creating a patient matching phone or name+DOB of an existing patient; user can confirm or correct.
8. Duplicate national ID on create is hard-blocked.
9. User with `patients.delete` can archive with confirmation; patient disappears from normal UI.
10. User without `patients.delete` cannot archive.
11. Backend verification utilities demonstrate blocked cross-organization patient access.
12. No appointment, visit, billing, or AI workflow is required to pass this feature.

### Test Cases

1. Register patient with required fields only at active branch; verify list and detail.
2. Register with phone matching existing patient; verify duplicate warning and successful proceed after confirm.
3. Register with duplicate national ID; verify hard block.
4. Search branch list by name substring (≥ 3 chars) and phone prefix (≥ 2 chars); verify pagination and minimum-length guidance when below threshold.
5. Org-wide search finds patient registered at another branch.
6. Edit notes and phone as authorized user at a branch different from the patient's registering branch; verify audit and persistence.
7. Attempt edit without permission; verify denial.
8. Two sessions edit same patient; first save succeeds; second save after first commits is rejected with stale-data message until reload.
9. Archive patient; verify absent from list and search; detail unavailable in normal flow.
10. Sign in as doctor with view-only; verify list/detail allowed, create/edit/archive denied.
11. Run backend verification utilities for CRUD, deduplication, org visibility, and cross-org denial.
12. Toggle list scope between this branch and all branches; verify results and registering-branch column; switch active branch with “this branch only” selected and verify list updates.
13. Attempt patient access with tampered organization context in verification harness; confirm denial.

### Implementation Constraints

- MUST build on completed `specs/002-auth-rbac` and `specs/003-org-branch-management` without breaking authentication or administration flows.
- Domain validation and authorization source of truth for mutations MUST live in database functions and policies—not solely in client logic.
- MUST use soft delete for archival; hard delete is not used.
- MUST NOT implement appointment, visit, billing, or AI schemas or screens in this feature.
- MUST NOT implement patient restore UI in V1-3.
- Cloud-only deployment enhancements are out of scope unless already supported by the local deployment path from V1-0.

### Key Entities *(include if feature involves data)*

- **Patient**: Clinic patient record scoped to organization via registering branch.
- **Registering Branch**: Branch where the patient was first registered; displayed on cross-branch search results.
- **Active Branch Context**: Session field from V1-2 used as default list scope and registration branch.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch clinics where reception registers patients at a desk and clinicians need reliable lookup across locations in the same business. Hospital EMR integrations, patient portals, and insurance eligibility are out of scope.
- **Layer Placement**: The desktop client owns patient list, registration, detail, edit, archive confirmation, validation UX, org-wide search mode, and permission-aware controls. The backend platform owns secured mutation and search functions, read paths subject to row-level policies, and audit writes. The database layer owns the `patients` schema, isolation policies, indexes, deduplication logic, and verification utilities. The AI layer remains absent.
- **Data Integrity & Security**: Mutations use audit and soft-delete conventions; row-level policies preserve organization isolation; permission keys gate operations; national ID uniqueness is enforced within the organization; defense in depth applies across UI, RPC, and policies.
- **Failure Handling**: Save and search failures surface clear errors without false success; connectivity loss shows degraded list states; AI unavailability does not affect patient management; subscription state does not block patient workflows.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 95% of test runs, authorized users complete patient registration and see confirmation within 15 seconds under normal local clinic network conditions.
- **SC-002**: In 100% of branch-scoped search test scenarios, relevant patients appear in the first page when searching by phone prefix (≥ 2 characters) or name substring (≥ 3 characters) that matches stored data.
- **SC-003**: In 100% of org-wide search test scenarios, a patient registered at branch B is discoverable by an authorized user at branch A in the same organization.
- **SC-004**: In 100% of permission test scenarios, users without the appropriate `patients.*` grant cannot perform the corresponding action in UI or via server calls.
- **SC-005**: In 100% of national ID conflict test scenarios, duplicate national ID create and update attempts are rejected.
- **SC-006**: In 100% of archive test scenarios, archived patients do not appear in normal list or search after confirmation.
- **SC-007**: In 100% of backend verification scenarios, cross-organization patient access is blocked.
- **SC-008**: In 100% of deduplication test scenarios, advisory duplicate warnings appear when phone or name+DOB match an existing non-archived patient before create.

## Assumptions

- `specs/002-auth-rbac` and `specs/003-org-branch-management` are implemented: session, claims, active branch, permissions, and administration exist.
- Patient permission keys (`patients.view`, `patients.create`, `patients.edit`, `patients.delete`) are seeded in `roles_permissions` per architecture defaults unless the clinic owner changes grants.
- Patient list scope defaults to “this branch only” on each sign-in; users opt in to “all branches” per session as needed.
- Gender values and phone validation patterns follow schema and locale defaults defined during implementation planning.
- Medical history on the detail page is limited to notes and a visits placeholder until V1-5; no visit data is fabricated in V1-3.
- Archival does not check for linked appointments or visits in V1-3 because those modules are not yet delivered; planning for V1-4+ may add dependency guards.
- `specs/operations/patients.spec.md` will be authored later; this feature spec is authoritative for V1-3 until that shared spec exists.
- AI remains optional and non-blocking for all patient flows.
