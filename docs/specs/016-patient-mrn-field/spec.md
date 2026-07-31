# Feature Specification: Patient MRN (Medical Record Number)

**Feature Branch**: `016-patient-mrn-field`

**Created**: 2026-07-24

**Status**: Draft

## Clarifications

### Session 2026-07-24

- Q: What is the uniqueness scope of the MRN? → A: Global unique across the entire database (one MRN space shared by all tenants/branches).
- Q: What format should the auto-generated MRN follow? → A: Sequential numeric, zero-padded with prefix (e.g., `MRN-000001`).
- Q: How should MRN uniqueness be technically enforced? → A: Server-side sequence + globally-unique constraint as backstop.
- Q: Is the generated MRN editable by staff? → A: Immutable after creation; no manual edits on the patient record (admin reconciliation flow may reassign with duplicate validation, but that is a restricted admin path, not the normal "edit MRN" field).
- Q: Who is permitted to perform restricted MRN reassignment? → A: Administrators only.

**Input**: User description: "Each patient shall have an MRN tied to it. This field is missing in the patients information.
1. When a patient is added, the MRN is auto-generated and viewed. Auto generation depends that the MRN is not a duplicate in the database. When the user attempts to edit the MRN, it shall check whether the MRN is not a duplicate or not.
2. In the patients list, the MRN shall be visible in a separate column.
3. In the patients details window, the MRN shall be put in a badge/chip.
4. It shall also reflect in the invoices table list, and in the invoices details page.
If you find any other place that the MRN should exist in, add it there as well."

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Auto-generate unique MRN when adding a patient (Priority: P1)

A receptionist or authorized clinic staff member opens the "Add Patient" form and fills in the patient's demographic details. On saving, the system automatically generates a unique Medical Record Number (MRN) for the new patient and displays it clearly so the staff member can confirm and read it back to or record it for the patient. The MRN must be guaranteed unique across the database (no duplicates) before the record is persisted.

**Why this priority**: Without a unique, auto-generated MRN at creation time, the entire identifier scheme has no foundation. Every other surface (list, details, invoice) depends on a correct MRN existing for every patient.

**Independent Test**: Create a single new patient through the Add Patient form and verify that a unique MRN is generated, displayed, and persists after reload — no other user story needs to be implemented to validate this.

**Acceptance Scenarios**:

1. **Given** a staff member with permission to create patients, **When** they submit a valid Add Patient form, **Then** the system generates a unique MRN, stores it with the patient, and displays the MRN to the staff member immediately on the confirmation/result.
2. **Given** the database already contains one or more patients with existing MRNs, **When** a new patient is created, **Then** the generated MRN does not match any existing MRN in the database.
3. **Given** a new patient is created, **When** the patient record is reopened later, **Then** the same MRN is present and unchanged on that record.

---

### User Story 2 - Restricted MRN reassignment with duplicate validation (Priority: P2)

An authorized administrator opens a restricted reconciliation flow (not an inline field on the patient record) to reassign a patient's MRN (e.g., to correct a duplicate/import error). On saving, the system validates that the proposed MRN value is not a duplicate of any other patient's MRN in the database. If it is a duplicate, the reassignment is rejected with a clear, actionable message; if unique, the change is persisted and fully audited, and all surfaces reflecting the patient's MRN update accordingly. Ordinary staff cannot edit the MRN on the patient record — it is immutable after auto-generation.

**Why this priority**: Reassignment is a safety/control concern rather than the foundational creation flow, but the restricted path must prevent duplicate identifiers before any downstream surface reads a wrong MRN.

**Independent Test**: Via the restricted admin flow, attempt to reassign an MRN to a value already used by another patient and confirm the rejection; then reassign it to a fresh value and confirm persistence and audit-record creation — testable without UI for invoices or lists.

**Acceptance Scenarios**:

1. **Given** an administrator opens the restricted MRN reassignment flow, **When** the user changes the MRN to a value already assigned to another patient and saves, **Then** the save is rejected and a clear duplicate-MRN error is shown without modifying the existing record.
2. **Given** an administrator opens the restricted MRN reassignment flow, **When** the user changes the MRN to a value not used by any other patient and saves, **Then** the new MRN is persisted, an audit entry (old/new value, actor, timestamp) is recorded, and all surfaces reflecting the patient's MRN update accordingly on next refresh.
3. **Given** a non-administrator staff member, **When** they attempt to access the restricted MRN reassignment flow or inline-edit the MRN on a patient record, **Then** access is denied / the flow is hidden and the field is read-only inline; only Administrator-role users may reassign MRNs.

---

### User Story 3 - View MRN in the patients list (Priority: P1)

A staff member browsing the patients list sees a dedicated MRN column showing each patient's MRN alongside their other identifying details. The MRN column can be used to scan, sort, or locate a specific patient quickly.

**Why this priority**: The list is the primary lookup surface for patients; a dedicated MRN column is the core visibility requirement repeated across other surfaces.

**Independent Test**: Open the patients list with at least one patient present and verify the MRN column is present, populated, and correctly matches each patient's stored MRN.

**Acceptance Scenarios**:

1. **Given** one or more patients exist, **When** the staff member opens the patients list, **Then** a dedicated MRN column is visible with each patient's MRN displayed.
2. **Given** the patients list is displayed, **When** the staff member sorts or searches by MRN (if supported), **Then** the list orders/filters patients by their MRN accordingly.

---

### User Story 4 - View MRN as a badge/chip in patient details (Priority: P2)

A staff member opens a patient's details window and sees the MRN rendered as a prominent badge/chip near the patient's identifying information, so it can be quickly spotted, copied, or referenced during clinical or billing tasks.

**Why this priority**: The details window is the authoritative per-patient view; presenting the MRN as a chip is a presentation enhancement layered on top of the foundational unique-MRN requirement.

**Independent Test**: Open any patient's details window and verify the MRN appears as a distinct badge/chip element showing the correct value.

**Acceptance Scenarios**:

1. **Given** a patient with an MRN exists, **When** the staff member opens that patient's details window, **Then** the MRN is rendered as a clearly distinguishable badge/chip showing the correct value.
2. **Given** the MRN chip is displayed, **When** the staff member copies/reads the chip value, **Then** it matches the patient's stored MRN exactly.

---

### User Story 5 - Reflect MRN in invoices list and invoice details (Priority: P2)

A billing/finance staff member viewing the invoices table list sees the responsible patient's MRN in a dedicated column, and opening an invoice's details page shows the patient's MRN alongside other identifiers. This lets staff match invoices to patients reliably without opening the patient record.

**Why this priority**: Invoicing is a downstream consumer of patient identity; once foundational patient surfaces show the MRN, billing surfaces can reuse the same value. It depends on User Story 1 being complete.

**Independent Test**: Open the invoices list and any invoice's details page where the patient has an MRN, and verify the MRN is presented correctly in both places.

**Acceptance Scenarios**:

1. **Given** invoices exist tied to patients with MRNs, **When** the staff member opens the invoices list, **Then** a dedicated MRN column shows each invoice's patient MRN.
2. **Given** an invoice is open on its details page, **When** the staff member views the invoice, **Then** the patient's MRN is displayed alongside the patient identifier section of the invoice.
3. **Given** an invoice is tied to a patient, **When** the patient's MRN is later reassigned via the restricted admin flow (User Story 2), **Then** the invoice surfaces reflect the updated MRN without modifying the invoice's own line items.

---

### User Story 6 - Surface MRN in additional clinical/operational contexts (Priority: P3)

Wherever a patient is referenced in clinical or operational workflows beyond the lists and details explicitly requested, the MRN is also shown so staff can unambiguously identify patients. This includes appointment lists/entries, visit/encounter listings and details, medical records entries, and patient-oriented reports or printed documents.

**Why this priority**: Cross-surface consistency is a polish/usability concern; it strengthens correctness once the core creation and primary surfaces are in place.

**Independent Test**: Open an appointment, visit/encounter, or medical-records entry for a patient with an MRN and verify the MRN is displayed with the patient identification.

**Acceptance Scenarios**:

1. **Given** appointments/visits/encounters tied to patients exist, **When** the staff member opens those listings/entries or their detail views, **Then** the patient's MRN is displayed alongside the patient name.
2. **Given** a printed or exported report references a patient, **When** the report is generated, **Then** it includes the patient's MRN for unambiguous identification.

---

### Edge Cases

- What happens when AI is unavailable during a workflow that normally offers assistance? The MRN generation is a deterministic database-unique operation and MUST NOT depend on AI; AI unavailability has no effect on MRN creation, editing, or display.
- How does the feature behave when a user lacks tenant-scoped or branch-scoped permission for the requested action? MRN visibility and editing follow existing patient- and invoice-level role permissions (tenant/branch scoped); unauthorized users see neither the value nor the editing affordance.
- What happens when network, sync, or backend connectivity is degraded but clinic work still needs to continue safely? MRN uniqueness is enforced server-side as the source of truth; client forms must reject save attempts on duplicate-detection failures and must not generate locally unique-only values that could clash on sync.
- Edge: a very large number of patients — the generation strategy must still produce unique values without exhausting collisions or noticeable latency.
- Edge: importing patients in bulk — each imported row must still receive a guaranteed-unique MRN; existing MRNs, if supplied on import, must be validated for uniqueness.
- Edge: merging duplicate patient records — the resulting merged patient retains exactly one MRN; the merge flow must surface a duplicate-MRN conflict resolution.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST assign a unique Medical Record Number (MRN) to every patient at the moment of creation, generated by a backend-deterministic mechanism that guarantees no duplicate MRNs exist across the entire database (global uniqueness, not tenant/branch-scoped). The MRN format MUST be a sequential numeric value, zero-padded with a fixed prefix (e.g., `MRN-000001`).
- **FR-002**: System MUST display the generated MRN to the creating user immediately upon successful patient creation.
- **FR-003**: System MUST keep the auto-generated MRN immutable on the patient record for ordinary staff (no inline edit field). A restricted reassignment flow MUST exist for administrators only (no other role may access this flow), and it MUST validate, server-side, that the proposed new value is not a duplicate of any other patient's MRN before persisting the change; duplicate attempts MUST be rejected with a clear, actionable message. Every reassignment MUST produce an audit entry (old/new value, actor, timestamp).
- **FR-004**: System MUST preserve tenant-scoped and branch-scoped permission rules for both viewing and editing the MRN, consistent with existing patient permissions.
- **FR-005**: System MUST present the MRN in a dedicated column in the patients list, populated for every patient.
- **FR-006**: System MUST render the MRN as a distinct badge/chip element in the patient details window.
- **FR-007**: System MUST present the patient's MRN in a dedicated column in the invoices list and within the patient identification area of each invoice's details page.
- **FR-008**: System MUST automatically reflect the current MRN value on all surfaces (list, details, invoice list, invoice details, appointments, visits/encounters, medical records, reports) after a patient's MRN is created or edited, without requiring duplicated migration of the value.
- **FR-009**: System MUST surface the MRN next to the patient identity in additional contexts where a patient is referenced: appointment listings/entries and detail, visit/encounter listings and details, medical-records entries, and patient-referencing printed/exported reports.
- **FR-010**: System MUST enforce MRN uniqueness globally (across all tenants/branches) in PostgreSQL-backed mechanisms, keeping the source of truth and transactional correctness in the database layer; the client MUST treat server duplicate-detection as authoritative. Uniqueness MUST be enforced via a server-side sequence for generation plus a globally-unique database constraint as a backstop, avoiding retry-based collision loops.
- **FR-011**: System MUST retain an auditable record of MRN creation and any restricted administrator MRN reassignments (old/new value, actor, timestamp) consistent with existing audit/soft-delete conventions for operationally significant patient identifiers.
- **FR-012**: System MUST degrade safely when backend services are unavailable: the client MUST NOT allow saving a patient with a locally generated, unverified MRN, and MUST surface a clear error rather than persist a potentially clashing value.

### Key Entities *(include if feature involves data)*

- **Patient**: Gains a required, unique, immutable-on-record `mrn` identifier attribute (format: prefix + zero-padded sequential number, e.g., `MRN-000001`), alongside existing demographic attributes. Reassignment is allowed only via a restricted admin reconciliation flow (see FR-003), not inline editing. Relationships to invoices, appointments, visits/encounters, and medical records remain unchanged but each now surfaces the patient's MRN.
- **Invoice**: Carries a read-only view of the responsible patient's MRN (derived from its patient relationship, not a separately editable value).
- **Appointment / Visit / Encounter / Medical Record**: Each carries a read-only view of the associated patient's MRN for unambiguous identification.
- **MRN Audit Log (or existing audit trail)**: Records MRN creation and restricted-flow reassignments (patient id, old value, new value, actor, timestamp).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Supports small-to-mid-size multi-branch clinics by giving every patient a single, unambiguous medical record number that staff can read across lists, details, invoices, and clinical workflows. Out of scope: enterprise hospital-level MPI (master patient index) federation across separate organizations, and external national-identifier integration.
- **Layer Placement**: Flutter renders the MRN column, badge/chip, invoice/clinical surfaces, the Add Patient form, and the restricted administrator MRN reassignment flow. Supabase exposes edge functions / RPCs for MRN generation and duplicate validation. PostgreSQL holds the globally-unique sequence + constraint and is the source of truth for uniqueness, returning generated/validated MRNs. No AI dependency for MRN generation or validation.
- **Data Integrity & Security**: A database-level globally unique constraint on the patient MRN (spanning all tenants/branches) prevents duplicates regardless of client behavior; MRN values are generated by a server-side sequence with the unique constraint as a backstop (no collision-retry loops). tenant/branch RLS continues to govern visibility and editability of the MRN value but not the uniqueness scope. RLS and existing patient/invoice role permissions govern MRN visibility and editability. MRN creation and restricted admin reassignments are captured in the audit trail with actor and timestamp. Soft-delete of a patient must not release an MRN for immediate reuse in a way that creates ambiguity (e.g., retained/soft-deleted MRNs remain excluded from active uniqueness checks but preserved for audit).
- **Failure Handling**: When Supabase/PostgreSQL is unreachable, the Add Patient form and the restricted MRN reassignment flow MUST NOT save a patient with an unverified MRN and MUST show a clear connectivity/uniqueness error. When AI services (used elsewhere in workflows) are unavailable, MRN generation, reassignment validation, and display are unaffected because they are deterministic and database-backed. UI surfaces continue to display already-persisted MRNs from cached/local reads where the application supports offline reads, but never accept MRN mutations while offline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of newly created patients receive a unique MRN at creation time, verifiable by creating consecutive patients and confirming no duplicates exist across the dataset.
- **SC-002**: 100% of attempts to set an MRN to an already-used value (on create or edit) are rejected before persistence, with no duplicate MRNs ever present in the dataset.
- **SC-003**: Staff can locate a patient by scanning the patients list within 5 seconds using the dedicated MRN column, without needing to open the patient record.
- **SC-004**: Staff can visually confirm a patient's identity at a glance on the patient details window via the MRN badge/chip on the first attempt, with no need to open secondary fields.
- **SC-005**: 100% of invoices in the invoices list and 100% of invoice detail views display the responsible patient's correct MRN, matching the patient's stored MRN.
- **SC-006**: MRN edits propagate to all surfacing contexts (patients list, patient details, invoices list, invoice details, appointments, visits/encounters, medical records, reports) within a single refresh, for 100% of edited patients.
- **SC-007**: 0 incidents of staff misidentifying patients in billing or clinical workflows due to missing patient identifiers after rollout, as measured by post-release support tickets in the first month.

## Assumptions

- Primary users are clinic staff (reception, clinical, billing) operating on desktop systems; the existing patient and invoice permission model (tenant-scoped and branch-scoped) is reused unchanged for MRN visibility/editability.
- The MRN format is a fixed prefix followed by a zero-padded sequential number (e.g., `MRN-000001`), generated by a server-side sequence; the zero-padding width is chosen to comfortably exceed the largest expected patient volume per database.
- MRNs are unique globally across the entire database (all tenants/branches share one MRN namespace); cross-organization/federation uniqueness is out of scope.
- Existing audit/soft-delete conventions for operationally significant records are extended to cover MRN creation and restricted admin reassignments, rather than introducing a brand-new audit subsystem.
- AI assistance, if present in surrounding workflows, remains optional and is NOT used for MRN generation or duplicate validation, which are deterministic database operations.
- Appointments, visits/encounters, medical records, and reports expose a patient reference today; adding an MRN read alongside that reference is a presentation change, not a data-model change for those entities.
- Bulk patient import (if/when used) follows the same uniqueness guarantees as single creation; an import pre-validation step may be added but is out of scope for the initial increment unless required.