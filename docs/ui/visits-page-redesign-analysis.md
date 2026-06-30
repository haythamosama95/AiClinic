# Visits Page — Information Architecture & UI Redesign Analysis

**Status**: Proposal / discussion document
**Scope**: `frontend/lib/features/visits` documentation + detail pages (feature 013)
**Author**: Design review
**Date**: 2026-06-30

---

## 1. What the page records today

The current visit documentation/detail page (`visit_documentation_page.dart`, `visit_detail_page.dart`) renders everything on a **single vertically-scrolling page**:

| Block | Widget | Fields captured |
|---|---|---|
| Patient header | `VisitPatientBasicInfoCard` | Name, ID, gender, DOB, phone, marital status, registered date (all **read-only**) |
| Clinical note | `ClinicalNoteEditor` | Complaint, History, Examination, Diagnosis, Plan (5 free-text, ≤10k chars each) |
| Vital signs | `VitalSignList` | name, value, unit (predefined or custom) |
| Treatment plans | `TreatmentPlanList` | medication, dosage, frequency, duration, note |
| Investigations | `InvestigationList` | name, note |
| Attachments | `VisitAttachmentList` | PDF / DOCX / JPEG / PNG ≤25 MB |

Layout: patient card → full-width clinical-note card → a 2-column grid that drops the four remaining cards (`VisitSectionGrid`) side by side.

### Why it "feels like too much"

1. **One flat plane, no priority.** Five large text areas plus four interactive list-builders compete for attention at once. There is no sense of "where am I / what's next" during a live consultation.
2. **The clinical note is one giant card.** Complaint, History, Examination, Diagnosis and Plan are visually fused into a single panel even though they belong to *different phases* of the encounter (see §3). The user explicitly noted the card should not be treated as intact — and clinically it shouldn't be.
3. **Objective data is scattered.** Examination (inside the note card) and Vital signs (a separate grid card) describe the same thing — the physical exam — but live far apart.
4. **Plan is duplicated conceptually.** The free-text "Plan" section, the Treatment plans builder, and the Investigations builder are all "what we're going to do," yet they are presented as three unrelated regions.
5. **No visit context.** The model already carries `visitDate`, `doctorName`, and `status`, but none of it is shown. The header only shows the *patient*, not the *encounter*.

---

## 2. What is missing (information that should be recordable)

Grouped by clinical importance. Items marked **(safety)** are the highest-value gaps.

### 2.1 Patient safety context — currently absent entirely
- **Allergies / adverse drug reactions (safety).** There is no allergy field anywhere. A prescribing screen with no allergy surface is the single biggest clinical gap. At minimum: substance, reaction, severity. Should be visible as a persistent banner while prescribing.
- **Current / home medications (medication reconciliation) (safety).** What the patient already takes — needed to reason about interactions and continuation vs. new scripts.
- **Chronic conditions / problem list (safety).** Diabetes, hypertension, etc. Today this can only live as prose inside "History," so it is neither structured nor reusable across visits.

### 2.2 Encounter metadata — exists in data, not surfaced
- **Visit date & time, attending doctor, visit status** (already in `VisitDetail`, just not displayed).
- **Visit type / reason classification** — new consult vs. follow-up vs. procedure vs. result review. Drives layout and reporting.
- **Triage / urgency** for queueing context.

### 2.3 Subjective enrichments
- **Chief complaint vs. History of Present Illness as distinct fields** (currently "Complaint" + "History," but HPI structure like onset/duration/severity is free text only).
- **Past medical / surgical history, family history, social history** (smoking, alcohol, occupation) — standard outpatient intake, currently has no home.
- **Review of systems (ROS)** — optional checklist.

### 2.4 Objective enrichments
- **BMI auto-calculation** — Height and Weight are already captured as vitals; BMI should be derived, not re-entered.
- **Pain score**, and a clearer **vitals timestamp** (when the measurement was taken vs. when the row was saved).
- **Vitals trend vs. previous visit** — even a simple "last visit: BP 140/90" reference adds a lot of value.

### 2.5 Assessment enrichments
- **Structured/coded diagnosis (ICD-10 or a clinic code list)** alongside the free-text diagnosis — needed for any future reporting, billing, or analytics. Reuses the same catalog-search pattern already built for medications/investigations.
- **Differential vs. final diagnosis** distinction (optional).

### 2.6 Plan enrichments
- **Structured follow-up** — a "next visit in X / on date" field that could pre-fill an appointment, instead of burying it in free-text Plan.
- **Patient instructions / advice** as a discrete field (today merged into Plan).
- **Referral** to another specialty/clinic.
- **Investigation result capture** — investigations can be *ordered* but there is no field to record the *result* on a later visit.
- **Sick leave / medical certificate** issuance (common outpatient output).

### 2.7 Cross-cutting
- **Linkage to billing** — treatments/investigations ordered are natural billable items; today there is no bridge.
- **Visit-level summary / "reason this visit closed"** for the detail/read view.

> Recommendation: not all of these should ship at once. The **safety trio (allergies, current meds, chronic conditions)** and **encounter metadata** are the highest priority and lowest cost (metadata already exists).

---

## 3. How information should be grouped

The natural, clinically-validated grouping is the **encounter workflow order** (a SOAP-style progression), which also happens to map onto discrete steps. Re-cut the current cards along these seams instead of the existing "note vs. lists" seam:

### Group A — Encounter & Patient Context *(read + safety, always visible)*
- Visit date/time, doctor, status, visit type
- Patient snapshot (name, age/DOB, gender)
- **Safety strip: allergies · current medications · chronic conditions**

### Group B — Subjective (the story)
- Chief complaint
- History of present illness
- (optional) PMH / family / social history, ROS

### Group C — Objective (the findings)
- **Vital signs** *(+ derived BMI, pain score)*
- **Examination findings** ← move here, out of the "clinical note" card
- Investigation **results** (if available)

### Group D — Assessment (the conclusion)
- Diagnosis: structured/coded **and** free text
- (optional) differential

### Group E — Plan (the actions)
- **Treatments / prescriptions**
- **Investigations ordered**
- Follow-up + patient instructions + referral + certificates
- **Attachments**

The key regroupings vs. today:
- **Split the monolithic clinical-note card.** Complaint/History → Subjective; Examination → Objective; Diagnosis → Assessment; Plan → Plan. The "card" is explicitly *not* kept intact.
- **Examination joins Vital signs** under Objective (they are the same clinical phase).
- **Plan, Treatments, Investigations and Attachments unify** under Plan (they are all "what we will do / supporting docs").

---

## 4. Suggested UI design

### 4.1 Core idea: a non-linear stepper with a persistent context rail

Replace the single long scroll with a **multi-step workspace** that mirrors Groups A–E, while staying fast for power users.

```
┌───────────────────────────────────────────────────────────────────────┐
│  ← Back        Visit · 30 Jun 2026 · Dr. Sarah · [In progress]   [Submit]│  ← encounter header (fills the metadata gap)
├──────────────┬─────────────────────────────────────────┬──────────────┤
│  STEPS        │            ACTIVE STEP CANVAS            │  CONTEXT RAIL │
│               │                                          │               │
│ ① Context     │   (only the current group's fields,      │  Patient      │
│ ② Subjective  │    e.g. Subjective = Complaint + HPI)     │  Age/Gender   │
│ ③ Objective ● │                                          │  ⚠ Allergies  │
│ ④ Assessment  │                                          │  Current meds │
│ ⑤ Plan        │                                          │  Chronic dx   │
│               │                                          │  Last vitals  │
│ ▸ Review      │                                          │               │
├──────────────┴─────────────────────────────────────────┴──────────────┤
│  Saved ✓ 19:42     [ Previous ]                      [ Next: Assessment ]│  ← sticky save/nav bar
└───────────────────────────────────────────────────────────────────────┘
```

Key properties:
- **Left rail = steps with completion/validation badges.** Steps are *freely clickable* (non-linear) — a doctor doing a quick follow-up can jump straight to Plan. Each step shows a filled/empty/error indicator.
- **Center = only the active group**, so the screen shows ~1/5 of the fields at any moment → directly addresses "too much information."
- **Right rail = the safety/context the doctor needs while typing** (allergies, current meds, chronic conditions, last vitals). This is read-only and persistent across every step, solving the "no allergy surface while prescribing" gap without adding noise.
- **Sticky footer** with autosave status (reuse the existing per-section save + optimistic concurrency) and Previous / Next.

### 4.2 Two modes (don't slow down experts)
- **Guided mode (default):** the stepper above — great for new visits, trainees, and thorough documentation.
- **Single-page / "expert" mode:** a toggle that renders all five groups as collapsible accordions on one page (close to today's layout but regrouped per §3, with the context rail retained). Lets fast doctors keep a single-screen flow.

This preserves spec goal **SC-001** (full visit < 5 min) and **FR-015** (layout optimized for rapid entry) while making the default experience calmer.

### 4.3 Step-by-step content
- **① Context** — confirm patient, set visit type, review/add allergies & current meds & chronic conditions (these can be patient-level records surfaced here).
- **② Subjective** — Complaint (hint preserved), HPI/History, optional histories.
- **③ Objective** — Vital signs builder (with derived BMI chip), Examination free text, optional investigation results.
- **④ Assessment** — coded diagnosis search (reuses `CatalogAutocompleteField`) + free-text diagnosis.
- **⑤ Plan** — Treatments builder, Investigations builder, follow-up/instructions/referral, Attachments.
- **▸ Review & submit** — a single read-only summary of everything (this *is* the detail view), with inline "edit this section" links and the submit action. Enforces **FR-011** (≥1 clinical section) right here.

### 4.4 Smaller, concrete UI wins (independent of the stepper)
- **Surface encounter metadata** in the header immediately (cheap, high value, data already present).
- **Add a persistent allergy/safety banner** even before full allergy data modelling lands — start with a single free-text "alerts" line if needed.
- **Derive BMI** from existing Height + Weight vitals rather than leaving it to mental math.
- **Move Examination next to Vital signs**; move "Plan" prose next to Treatments/Investigations — even within today's layout this reduces cognitive load.
- **Compact the read-only detail view** into the same five collapsible groups so editing and reviewing share one mental model.

### 4.5 Reuse what already exists
- Catalog search (`CatalogAutocompleteField`), name normalization, and the save-to-catalog prompt can power the new **diagnosis-code**, **allergy**, and **current-medication** fields with no new patterns.
- Optimistic concurrency, permission gating (`visits.edit_soap`), and branch-scope checks are unchanged — the redesign is presentational + additive fields, not a lifecycle change.

---

## 5. Summary of recommendations

1. **Split the clinical-note card** along clinical phases; stop treating it as one block.
2. **Regroup** into 5 encounter phases: Context → Subjective → Objective → Assessment → Plan (+ Review).
3. **Add the missing safety trio** (allergies, current meds, chronic conditions) and **surface encounter metadata** that already exists.
4. **Adopt a non-linear stepper + persistent context rail**, with an expert single-page mode for speed.
5. **Add structured diagnosis codes and structured follow-up** by reusing the existing catalog-search machinery.

### Suggested phasing
- **Phase 1 (low cost, high value):** surface encounter metadata; add safety banner (even free-text); regroup Examination↔Vitals and Plan↔Treatments/Investigations; derive BMI.
- **Phase 2:** introduce the stepper + context rail + review step.
- **Phase 3:** structured allergies/current meds/chronic conditions, coded diagnosis, structured follow-up, investigation results, billing linkage.
