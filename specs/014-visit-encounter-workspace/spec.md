# Feature Specification: Visit Encounter Workspace (Visits Page IA/UI Redesign)

**Feature Branch**: `014-visit-encounter-workspace`

**Created**: 2026-06-30

**Status**: Draft

**Input**: User description: "Redesign the visit documentation page (feature 013) into a calmer, clinically-sequenced encounter workspace. Split the monolithic clinical-note card along clinical phases; regroup all visit content into five encounter phases (Context, Subjective, Objective, Assessment, Plan) plus a Review step; surface encounter metadata that already exists; add a persistent patient-safety surface (allergies, current medications, chronic conditions, last vitals) visible while documenting; offer a non-linear stepper with a persistent context rail as the default, plus an expert single-page mode; and add structured enrichments (coded diagnosis, structured follow-up, derived BMI). Source: docs/ui/visits-page-redesign-analysis.md."

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

Feature 013 replaced SOAP/specialty documentation with a structured clinical note (Complaint, History, Examination, Diagnosis, Plan), searchable catalogs, vital signs, treatments, investigations, and attachments. The result records the right data but presents it as **one flat, vertically-scrolling plane**: five large text areas and four interactive list-builders all compete for attention at once, the clinical note is fused into a single card even though its sections belong to different phases of the encounter, objective data is scattered (Examination sits inside the note card while Vital signs live in a separate grid), the "Plan" concept is duplicated across three unrelated regions, and encounter metadata that already exists in the data (visit date/time, doctor, status) is never shown.

This feature is an **information-architecture and UI redesign plus additive, structured fields** on top of feature 013. It does **not** change the visit lifecycle, permissions, optimistic concurrency, attachment behavior, or branch-scope rules established in V1-5 and 013. It re-cuts the existing content along clinically-validated **encounter-workflow seams** (a SOAP-style progression), surfaces existing encounter metadata, introduces a persistent patient-safety surface so doctors never prescribe without seeing allergies, and offers a non-linear stepper workspace (with an expert single-page mode) so the screen shows only the current phase at any moment.

Primary users are **doctors** documenting encounters during live consultations, who need both calm guidance for thorough documentation and speed for quick follow-ups. **Clinical and administrative staff** review completed encounters on the detail view, which shares the same five-phase mental model. **Lab staff** continue uploading attachments unchanged.

The work is intentionally **phased**: low-cost / high-value regrouping and safety surfacing first, then the stepper workspace, then deeper structured data. Each phase is independently shippable.

## Clarifications

### Session 2026-06-30

- Q: What is the intended delivery scope of feature 014? → A: All three phases / all 8 user stories live in this one feature, sequenced by priority (P1 = shippable MVP, P2 and P3 follow). The feature is not split into separate specs per phase; each priority slice is independently shippable within feature 014.
- Q: What should sick-leave / medical-certificate "issuance" produce in this feature? → A: Record structured data only (start/end dates, reason, issuing doctor). Printable/exportable certificate document generation is out of scope for feature 014 and deferred to a separate feature.
- Q: How should allergy severity be represented? → A: No severity is represented. Allergy records capture substance and reaction only; there is no severity field, scale, or banner severity prioritization.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Surface Encounter Metadata in a Visit Header (Priority: P1)

As a doctor opening a visit, I can see the encounter context — visit date and time, attending doctor, visit status, and visit type — in a header at the top of the documentation and detail screens, so I always know which encounter I am working in instead of seeing only the patient.

**Why this priority**: The metadata already exists in the visit record; surfacing it is the lowest-cost, immediate clarity win and is a prerequisite for the workspace layout.

**Independent Test**: Open any in-progress and any completed visit; confirm the header shows visit date/time, attending doctor, and status, and that the value matches the underlying visit record. No data entry required.

**Acceptance Scenarios**:

1. **Given** an in-progress visit, **When** the documentation screen loads, **Then** a header displays the visit date/time, attending doctor name, and a status indicator (e.g., "In progress").
2. **Given** a completed visit, **When** the detail screen loads, **Then** the same encounter header is shown with the completed status.
3. **Given** a visit that has a recorded visit type/reason, **When** either screen loads, **Then** the visit type is shown in the header; **When** no visit type is recorded, **Then** the header renders gracefully without it.
4. **Given** a user without clinical read permission for the visit's branch, **When** they attempt to open the visit, **Then** access is denied and no metadata is leaked.

---

### User Story 2 - Regroup Documentation into Five Encounter Phases (Priority: P1)

As a doctor, I can document a visit organized into five clinically-meaningful phases — Context, Subjective, Objective, Assessment, Plan — instead of one flat plane, with the previously monolithic clinical-note card split so each section appears in the phase it belongs to (Complaint/History under Subjective, Examination under Objective next to Vital signs, Diagnosis under Assessment, Plan next to Treatments and Investigations under Plan), so the layout matches how I actually reason through an encounter.

**Why this priority**: Re-cutting the existing content along encounter seams is the core of this redesign and directly addresses the "too much information at once" problem; it can ship even within the current single-page layout.

**Independent Test**: Open a visit with populated 013 data (clinical note, vitals, treatments, investigations, attachments); confirm every existing field is reachable under exactly one of the five phases, that Examination renders next to Vital signs, that Plan prose renders next to Treatments/Investigations, and that no field is lost or duplicated versus the 013 page.

**Acceptance Scenarios**:

1. **Given** the documentation screen, **When** it loads, **Then** all existing 013 content is grouped into Context, Subjective, Objective, Assessment, and Plan with no field omitted and no field appearing in two phases.
2. **Given** the former clinical-note card, **When** the redesigned screen renders, **Then** Complaint and History appear under Subjective, Examination appears under Objective, Diagnosis appears under Assessment, and Plan appears under Plan — the single combined note card is no longer present.
3. **Given** the Objective phase, **When** it renders, **Then** Vital signs and Examination findings are presented together.
4. **Given** the Plan phase, **When** it renders, **Then** Treatments, Investigations, and Attachments are presented together as "what we will do / supporting documents."
5. **Given** a saved visit, **When** the user edits any field in its new location and saves, **Then** the same underlying clinical data is updated using existing 013 save behavior and optimistic concurrency (no new lifecycle).

---

### User Story 3 - Persistent Patient-Safety Context While Documenting (Priority: P1)

As a doctor, I can see a persistent, read-only patient-safety surface — allergies / adverse reactions, current (home) medications, chronic conditions, and last recorded vitals — that stays visible while I document and especially while I prescribe, so I never write a prescription on a screen that hides the patient's allergies.

**Why this priority**: A prescribing screen with no allergy surface is the single biggest clinical safety gap identified in the analysis; making safety context always-visible is the highest-value clinical improvement.

**Independent Test**: Open a visit for a patient that has safety information; confirm allergies, current medications, chronic conditions, and last vitals remain visible while scrolling/navigating through every phase including the prescribing (Plan) phase; confirm the surface is read-only and never blocks documentation.

**Acceptance Scenarios**:

1. **Given** a patient with recorded allergies, **When** the doctor is on any documentation phase including Plan/prescribing, **Then** the allergy information remains visible without extra navigation.
2. **Given** a patient with current medications and chronic conditions, **When** documenting, **Then** these are shown in the persistent safety surface alongside allergies and last vitals.
3. **Given** a patient with no structured safety data yet, **When** documenting, **Then** the surface degrades gracefully to an "alerts" line (free text or empty state) rather than disappearing, so the safety affordance is always present.
4. **Given** the safety surface, **When** the doctor interacts with documentation fields, **Then** the surface is read-only and does not capture focus or block rapid entry.
5. **Given** a previous visit with recorded vitals, **When** the current visit loads, **Then** the last recorded vitals (e.g., "Last visit: BP 140/90") are referenced in the safety/context surface.

---

### User Story 4 - Non-Linear Stepper Workspace with Review & Submit (Priority: P2)

As a doctor, I can work through the encounter in a multi-step workspace where the center shows only the current phase, a left rail lists the five phases plus a Review step with completion/validation badges, and steps are freely clickable so I can jump straight to any phase (e.g., go directly to Plan for a quick follow-up), with a sticky save/navigation footer and a final read-only Review summary that is also the detail view.

**Why this priority**: The stepper is the primary mechanism that makes the screen calm (showing ~1/5 of fields at a time) while staying fast for power users; it builds on the regrouping (US2) and safety surface (US3).

**Independent Test**: Open a visit; confirm only the active phase's fields are shown in the center; confirm each step shows a filled/empty/error badge; jump directly from Context to Plan without visiting intermediate steps; open Review and confirm it shows a read-only summary of all phases with the submit action and per-section edit links.

**Acceptance Scenarios**:

1. **Given** the workspace, **When** a phase is active, **Then** only that phase's fields are shown in the center canvas while the step rail and safety context remain visible.
2. **Given** the step rail, **When** the user clicks any step, **Then** navigation is non-linear and jumps directly to that phase without forcing completion of earlier phases.
3. **Given** documentation in progress, **When** the user views the step rail, **Then** each step shows an indicator for empty / has-content / validation-error state.
4. **Given** the sticky footer, **When** content is saved, **Then** autosave/save status (e.g., "Saved ✓ 19:42") and Previous/Next navigation are shown, reusing existing per-section save and optimistic concurrency.
5. **Given** the Review step, **When** it loads, **Then** a single read-only summary of every phase is shown with inline "edit this section" links and the submit action, and submission still enforces the existing rule that at least one clinical section is non-empty.
6. **Given** a quick follow-up, **When** the doctor jumps to Plan, fills a treatment, and submits via Review, **Then** the visit completes using existing 013 submission behavior with no new lifecycle steps.

---

### User Story 5 - Expert Single-Page Mode (Priority: P2)

As a fast/experienced doctor, I can toggle to a single-page "expert" mode that renders the five phases as collapsible accordions on one screen (close to the prior layout but regrouped per the five phases, with the safety context retained), so I can keep a single-screen flow without losing the regrouping and safety benefits.

**Why this priority**: Preserves documentation speed for power users so the calmer default does not slow experts down; depends on the same regrouping and content as the stepper.

**Independent Test**: Toggle from guided/stepper mode to expert mode; confirm all five phases appear as collapsible sections on one page with the safety context retained; document a full visit end-to-end in expert mode and submit; toggle back and confirm the same data is shown in the stepper.

**Acceptance Scenarios**:

1. **Given** the documentation screen in guided mode, **When** the user toggles expert mode, **Then** all five phases render as collapsible accordions on a single scrollable page.
2. **Given** expert mode, **When** the page renders, **Then** the persistent safety/context surface is still present.
3. **Given** either mode, **When** the user switches modes, **Then** in-progress content and save state are preserved (no data loss on toggle).
4. **Given** expert mode, **When** the user submits, **Then** the same submission rules and lifecycle apply as in stepper mode.

---

### User Story 6 - Structured Patient Safety Records (Allergies, Current Medications, Chronic Conditions) (Priority: P3)

As a doctor, I can record and maintain structured patient-level safety data — allergies (substance, reaction), current/home medications, and chronic conditions / problem list — surfaced and editable from the Context phase and reused across that patient's future visits, instead of burying this information in free-text History.

**Why this priority**: Structured safety data powers the persistent safety surface (US3) with reliable, reusable records and enables future interaction/continuation reasoning; it is higher-cost than the free-text safety surface, hence later.

**Independent Test**: From the Context phase, add an allergy with substance/reaction, a current medication, and a chronic condition for a patient; open a different visit for the same patient and confirm the structured records appear in the safety surface without re-entry.

**Acceptance Scenarios**:

1. **Given** the Context phase, **When** a doctor adds an allergy with substance and reaction, **Then** the allergy is stored at patient level and appears in the persistent safety surface for this and future visits of that patient.
2. **Given** the Context phase, **When** a doctor records current/home medications and chronic conditions, **Then** they are stored as structured patient-level records and surfaced on future visits.
3. **Given** structured safety records, **When** the doctor searches for an allergen, medication, or condition, **Then** the existing catalog-search machinery (used for medications/investigations) powers selection with custom entry and optional save-to-catalog, and custom names are normalized consistently with 013.
4. **Given** a user without documentation edit permission, **When** they view the Context phase, **Then** safety records are read-only.
5. **Given** safety records edited on one visit, **When** another authorized user opens a concurrent session, **Then** stale writes are rejected (optimistic concurrency) consistent with existing behavior.

---

### User Story 7 - Structured Diagnosis Codes and Structured Plan Outputs (Priority: P3)

As a doctor, I can attach a structured/coded diagnosis (from an organization-scoped diagnosis catalog) alongside the free-text diagnosis in the Assessment phase, and record structured Plan outputs — a follow-up interval/date, discrete patient instructions, a referral, and sick-leave/medical-certificate issuance — instead of burying them in free-text Plan.

**Why this priority**: Structured codes and follow-up unlock reporting/analytics and reduce free-text ambiguity, but they are additive enrichments that depend on the regrouped Assessment/Plan phases already existing.

**Independent Test**: In Assessment, search and attach a coded diagnosis while keeping free-text diagnosis; in Plan, set a follow-up interval, add a patient-instruction field, a referral, and issue a certificate; reload and confirm all structured outputs persist and render on the detail view.

**Acceptance Scenarios**:

1. **Given** the Assessment phase, **When** the doctor searches the diagnosis catalog and selects a coded diagnosis, **Then** the code is stored alongside the free-text diagnosis, reusing the existing catalog-search/custom-entry/normalize pattern.
2. **Given** the Plan phase, **When** the doctor sets a structured follow-up (interval such as "in 2 weeks" or a date), **Then** it is stored as a discrete field separate from free-text Plan.
3. **Given** the Plan phase, **When** the doctor records discrete patient instructions, a referral, or a sick-leave/medical certificate, **Then** each is stored as its own structured output.
4. **Given** structured Plan outputs, **When** the detail/Review view loads, **Then** follow-up, instructions, referral, and certificate appear as distinct, scannable items.
5. **Given** the diagnosis catalog, **When** no coded match exists, **Then** the doctor can continue with free-text diagnosis only without being blocked.

---

### User Story 8 - Objective Enrichments (Derived BMI, Pain Score, Vitals Timing, Investigation Results) (Priority: P3)

As a doctor, I can rely on derived and enriched objective data in the Objective phase — automatic BMI from existing Height and Weight vitals, a pain score, a clearer measurement timestamp for vitals, and a place to record investigation **results** on a later visit — so I don't re-enter derivable values or lose result data.

**Why this priority**: These are quality-of-life and completeness improvements on the Objective phase; valuable but the least safety-critical, so they ship last.

**Independent Test**: Enter Height and Weight vitals and confirm BMI is shown automatically without manual entry; record a pain score and a measurement time on a vital; on a follow-up visit, record a result against a previously ordered investigation and confirm it persists.

**Acceptance Scenarios**:

1. **Given** Height and Weight vital signs are present, **When** the Objective phase renders, **Then** BMI is derived and displayed automatically and is not a manually entered field.
2. **Given** only one of Height or Weight is present, **When** the Objective phase renders, **Then** BMI is not shown and no error occurs.
3. **Given** a vital sign, **When** the doctor records it, **Then** a measurement timestamp (when the measurement was taken) can be captured distinctly from the save time.
4. **Given** an investigation ordered on a prior visit, **When** the doctor opens a later visit, **Then** a result can be recorded against that investigation and persists.
5. **Given** a pain score field, **When** the doctor records it, **Then** it is stored with the visit's objective data.

---

### Edge Cases

- **AI unavailable**: This feature introduces no AI dependency; documentation, the stepper, the safety surface, and all structured fields remain fully manual. Any future AI drafting assistance is out of scope.
- **Missing permission**: A user lacking tenant- or branch-scoped permission is denied reads and writes at both UI and server layers; the encounter header and safety surface leak no cross-branch data.
- **Degraded connectivity**: Saves and catalog searches fail with clear errors; the sticky footer must not show "Saved ✓" when a save did not persist. Unsaved local edits are never presented as persisted. Offline draft persistence is out of scope.
- **No structured safety data**: The persistent safety surface degrades to a free-text "alerts" line / empty state rather than disappearing, so the prescribing screen always shows a safety affordance even before structured allergy data exists.
- **Narrow / small screens**: When the three-region layout (steps · canvas · context rail) does not fit, the context rail and step rail collapse into accessible, on-demand surfaces without hiding the active phase or the safety affordance.
- **Mode toggle mid-edit**: Switching between guided (stepper) and expert (single-page) mode preserves in-progress content and save state.
- **Non-linear jump to incomplete phase**: Jumping directly to a later phase (e.g., Plan) is always allowed; submission validation (≥1 clinical section non-empty) is enforced at Review/submit, not by blocking navigation.
- **BMI with incomplete inputs**: BMI is shown only when both Height and Weight exist; otherwise it is hidden gracefully.
- **Legacy/empty data**: Visits created before this redesign (including 013 visits with empty sections) render correctly in all five phases with empty states; no field is required to exist for a phase to render.
- **Stale concurrent edits**: Editing the clinical note or structured records from two sessions rejects the stale write with a refresh prompt (existing optimistic concurrency), unchanged by the redesign.

## Requirements *(mandatory)*

### Functional Requirements

#### Layer placement & integrity (cross-cutting)

- **FR-001**: The redesign MUST keep presentation, navigation (stepper/expert mode), client-side validation, BMI derivation, and catalog-search orchestration in the Flutter desktop app; persistence, validation, audit, RLS, and transactional saves for any new structured data MUST remain in PostgreSQL via Supabase RPCs. No custom primary backend service may be introduced.
- **FR-002**: All reads and writes MUST remain tenant-scoped and branch-scoped and MUST reuse the existing visit documentation edit permission (`visits.edit_soap` or its successor); the redesign MUST NOT broaden clinical access.
- **FR-003**: The visit lifecycle (creation from checked-in/in-progress appointments, one visit per appointment, completion advancing the appointment, post-submit editability, optimistic concurrency, attachments) MUST remain exactly as defined in V1-5 and 013; this feature is presentational and additive only.
- **FR-004**: New structured records introduced by this feature (safety records, coded diagnosis, structured Plan outputs, enriched objective fields) MUST follow shared schema conventions for IDs, timestamps, audit fields, soft deletion, and optimistic concurrency, and MUST degrade safely (clear errors, no false success) when the backend is unavailable.

#### Encounter header & regrouping (Phase 1)

- **FR-005**: The documentation and detail screens MUST display an encounter header showing visit date/time, attending doctor, and visit status using data already present on the visit; visit type/reason MUST be shown when present and omitted gracefully when absent.
- **FR-006**: The documentation and detail screens MUST organize all existing 013 content into exactly five encounter phases — Context, Subjective, Objective, Assessment, Plan — such that every existing field appears under exactly one phase with none omitted or duplicated.
- **FR-007**: The previously combined clinical-note presentation MUST be split: Complaint and History under Subjective, Examination under Objective, Diagnosis under Assessment, and Plan under Plan. The single combined clinical-note card MUST NOT be retained.
- **FR-008**: The Objective phase MUST present Examination findings together with Vital signs; the Plan phase MUST present free-text Plan together with Treatments, Investigations, and Attachments.
- **FR-009**: The read-only detail view MUST use the same five-phase grouping (e.g., collapsible groups) so editing and reviewing share one mental model.

#### Persistent safety surface (Phase 1 → Phase 3 data)

- **FR-010**: A persistent, read-only patient-safety/context surface MUST remain visible across every documentation phase, including the prescribing (Plan) phase, showing allergies, current medications, chronic conditions, and last recorded vitals.
- **FR-011**: When structured safety data does not yet exist, the safety surface MUST degrade to a free-text "alerts" line / empty state and MUST NOT disappear, so a safety affordance is always present while prescribing.
- **FR-012**: The safety surface MUST be read-only within the documentation canvas and MUST NOT capture focus or impede rapid data entry.
- **FR-013**: The system MUST reference the patient's last recorded vitals (from a prior visit) in the safety/context surface when available.

#### Workspace & modes (Phase 2)

- **FR-014**: The default documentation experience MUST be a multi-step workspace where the center canvas shows only the active phase's fields, with a step rail listing the five phases plus a Review step.
- **FR-015**: Steps MUST be freely clickable (non-linear navigation); the system MUST NOT force completion of earlier phases before allowing access to a later phase.
- **FR-016**: Each step MUST show a completion/validation indicator distinguishing empty, has-content, and validation-error states.
- **FR-017**: The workspace MUST provide a sticky footer with save/autosave status and Previous/Next navigation, reusing existing per-section save and optimistic concurrency.
- **FR-018**: A Review step MUST present a single read-only summary of all phases (this is also the detail view) with inline per-section edit links and the submit action, enforcing the existing rule that at least one clinical section is non-empty before submission.
- **FR-019**: An expert single-page mode MUST be available as a toggle, rendering the five phases as collapsible accordions on one page while retaining the persistent safety surface; switching modes MUST preserve in-progress content and save state.
- **FR-020**: The layout MUST remain usable on small/narrow windows by collapsing the step rail and context rail into accessible on-demand surfaces without hiding the active phase or the safety affordance.

#### Structured enrichments (Phase 3)

- **FR-021**: The system MUST support structured patient-level safety records: allergies (substance, reaction), current/home medications, and chronic conditions / problem list, editable from the Context phase and reused across that patient's future visits. Allergies MUST NOT include a severity field.
- **FR-022**: Structured safety records, coded diagnosis, and any new catalog-backed fields MUST reuse the existing catalog-search, custom-entry, client-side name normalization, and optional save-to-organization-catalog patterns from 013 (no new interaction patterns).
- **FR-023**: The Assessment phase MUST support a structured/coded diagnosis (from an organization-scoped diagnosis catalog) recorded alongside the existing free-text diagnosis; coded diagnosis MUST be optional and MUST NOT block free-text-only diagnosis.
- **FR-024**: The Plan phase MUST support structured outputs as discrete fields separate from free-text Plan: a follow-up interval or date, patient instructions, a referral, and sick-leave/medical-certificate issuance. Certificate issuance MUST record structured data only (e.g., start/end dates, reason, issuing doctor); generating a printable/exportable certificate document is out of scope for this feature.
- **FR-025**: The Objective phase MUST automatically derive and display BMI from existing Height and Weight vital signs (not a manually entered field), showing it only when both inputs exist and hiding it gracefully otherwise.
- **FR-026**: The Objective phase MUST support a pain score and a distinct measurement timestamp for vitals (when the measurement was taken vs. when the row was saved).
- **FR-027**: The system MUST allow recording investigation **results** on a later visit against investigations previously ordered, persisting the result with the visit.

### Key Entities *(include if feature involves data)*

- **Visit (existing)**: Clinical encounter linked to appointment, patient, doctor, branch; lifecycle and status unchanged from 013. Source of the encounter-header metadata (date/time, doctor, status, visit type/reason).
- **Clinical Note (existing, regrouped)**: The five free-text sections from 013 (Complaint, History, Examination, Diagnosis, Plan); unchanged in storage, redistributed across phases in presentation.
- **Patient Safety Record (new, patient-level)**: Structured allergy (substance, reaction; no severity), current/home medication, and chronic condition / problem-list entries scoped to a patient and reused across visits; powers the persistent safety surface.
- **Coded Diagnosis (new)**: Organization-scoped diagnosis catalog entry (code + label) optionally attached to a visit's Assessment alongside free-text diagnosis.
- **Structured Plan Output (new)**: Discrete follow-up interval/date, patient instructions, referral, and sick-leave/certificate records attached to a visit's Plan.
- **Enriched Objective Data (new/derived)**: Derived BMI (from Height/Weight vitals), pain score, vital measurement timestamp, and investigation-result records.
- **Visit Vital Sign / Treatment / Investigation / Attachment (existing)**: Unchanged collections from 013, re-presented under Objective and Plan phases.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch outpatient clinics by making the existing visit page calmer and safer for doctors documenting during live consultations, while keeping experts fast via single-page mode. Hospital-grade CPOE, enterprise formularies, and complex order sets remain out of scope; the diagnosis catalog reuses the same lightweight org-scoped search pattern rather than a licensed enterprise terminology service.
- **Layer Placement**: **Flutter** owns the redesigned presentation, the stepper/expert-mode navigation, the persistent context rail, client-side validation, BMI derivation, and catalog-search orchestration. **Supabase** continues to expose authenticated RPC access, storage for attachments, and authorization enforcement. **PostgreSQL** owns schema, constraints, RLS, audit, soft deletion, and transactional saves for the new structured records (safety records, coded diagnosis, structured Plan outputs, enriched objective data). **AI service** is not involved.
- **Data Integrity & Security**: All new structured records MUST be tenant-isolated (patient-level safety records scoped to organization/patient; org-scoped diagnosis catalog) and branch-scoped via visit/patient linkage, enforced with RLS plus RPC validation. Existing visit permission keys gate edits; the safety surface is read-only in the canvas. New tables follow shared conventions for IDs, timestamps, audit fields, soft delete, and optimistic concurrency. The redesign adds no hard-delete paths and does not weaken 013/V1-5 isolation.
- **Failure Handling**: When the backend is unavailable, saves and catalog searches fail with clear errors and the footer never shows false "Saved" status; unsaved edits are not presented as persisted. The safety surface still renders (degraded "alerts" line) so the prescribing affordance persists. AI unavailability has no effect because the feature does not depend on AI. Attachment flows degrade exactly as in V1-5.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the default workspace, no more than one encounter phase's fields are presented in the active canvas at a time (≈1/5 of the prior single-page fields), measurably reducing on-screen field count versus the 013 page.
- **SC-002**: 100% of documentation phases, including the prescribing (Plan) phase, display the patient-safety surface (allergies / alerts) without additional navigation.
- **SC-003**: Doctors can still complete a full visit documentation session in under 5 minutes on a reference desktop workflow, preserving the 013 speed target despite the calmer default layout.
- **SC-004**: For a quick follow-up, a doctor can reach the Plan phase from visit open in a single navigation action (non-linear jump) without passing through intervening phases.
- **SC-005**: 100% of existing 013 fields remain reachable and editable after regrouping, with zero fields lost or duplicated across the five phases, and zero regression in visit submission rules (cannot submit with all clinical text sections empty; successful submission still advances the linked appointment).
- **SC-006**: BMI is displayed automatically whenever both Height and Weight vitals exist, with zero manual BMI entry required.
- **SC-007**: At least 90% of doctors in a moderated usability session rate the five-phase workspace as "efficient" or better and report the always-visible safety context as an improvement over the 013 single-page layout.
- **SC-008**: Attachment upload/list/download and all V1-5/013 permission and lifecycle behaviors show zero regression after the redesign.

## Assumptions

- This feature builds directly on feature 013 (`specs/013-visits`); the 013 clinical-note model, catalogs, child records, attachments, permissions, optimistic concurrency, and lifecycle are the foundation and are not changed by the redesign.
- The redesign is **presentational plus additive fields**; it is not a lifecycle change. Phase 1 (encounter header, regrouping, free-text safety surface, BMI derivation, Examination↔Vitals and Plan↔Treatments/Investigations co-location) can ship before any new tables exist.
- Structured safety records (allergies, current medications, chronic conditions) are **patient-level** and reused across that patient's visits, surfaced/edited from the Context phase. Patient-level (not visit-level) is chosen so safety context persists across encounters.
- The coded-diagnosis catalog is an **organization-scoped** catalog reusing the existing 013 catalog-search/custom-entry/normalize machinery, rather than mandating a licensed external terminology (e.g., full ICD-10 distribution). A code field is supported but coded diagnosis is always optional alongside free text.
- Guided/stepper mode is the **default**; expert single-page (accordion) mode is an opt-in toggle. Mode preference may be remembered per user but that persistence is a minor detail, not a hard requirement.
- The persistent context rail/safety surface is read-only within the documentation canvas; editing safety records happens via the Context phase, not the rail itself.
- Desktop-first on Windows over clinic LAN remains the primary target (per constitution and 013); a responsive collapse handles narrow windows, but dedicated mobile layouts are out of scope.
- "Last vitals" reference reads from the patient's most recent prior visit vitals; richer multi-visit trend charts are out of scope for this feature.
- Billing linkage for treatments/investigations is acknowledged in the analysis but is **out of scope** here and left to the billing feature (007); this spec only ensures the data is structured enough to support a future bridge.
- Offline draft persistence and AI-assisted drafting are out of scope; documentation remains manual with clear online-only save semantics.
- Existing visit documentation edit permission (`visits.edit_soap` or its successor) governs the new structured records; any permission rename is handled separately and not assumed here.
