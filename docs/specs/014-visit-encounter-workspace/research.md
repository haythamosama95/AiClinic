# Phase 0 Research: Visit Encounter Workspace (014)

Resolves the open decisions flagged during `/speckit-clarify` (data-model and implementation details deliberately deferred to planning) plus the technical unknowns from the plan's Technical Context. All decisions respect the constitution (clinic-fit, replaceable layers, backend authority, human-gated security, no AI dependency) and reuse 013 conventions.

---

## R1. Workspace navigation & "active phase only" rendering

- **Decision**: Implement the guided workspace as a single page with an in-memory `activeStep` (Riverpod `StateProvider`/notifier), not GoRouter sub-routes. The center canvas renders only the active phase's widgets via a `switch` on `EncounterPhase`; the step rail and safety rail are always mounted. Expert mode renders all phases as collapsible sections.
- **Rationale**: Keeps the existing `/visits/:id` route and permission gating intact (FR-003), avoids deep-link/route churn, makes non-linear jumps (FR-015) and mode toggling without data loss (FR-019) trivial in-state, and keeps the whole `VisitDetail` loaded once for `get_visit` single round-trip.
- **Alternatives considered**: Nested routes per phase (rejected — adds navigation/permission complexity and risks losing unsaved draft on route change); a `PageView` (rejected — implies linear paging, conflicts with free clickability).

## R2. Step completion / validation badge model

- **Decision**: Derive badge state purely from loaded `VisitDetail` + the in-progress draft, in `encounter_step_provider.dart`: `empty` (no content), `hasContent` (≥1 field populated), `error` (client-side validation failure, e.g., a treatment line missing required dosage/frequency/duration). No server round-trip for badges.
- **Rationale**: Badges must update instantly while typing (FR-016); validation rules already exist client-side in 013 list widgets. Submission validity (≥1 clinical section) is still enforced server-side at `complete_visit` (FR-018, unchanged).
- **Alternatives considered**: Server-computed completion (rejected — latency, unnecessary; the source of truth for *submission* remains the backend check).

## R3. Persistent safety surface — phased data source

- **Decision**: P1 ships the safety rail backed by a **degraded free-text "alerts"/empty state** (FR-011) with no new storage. P3 adds a single read RPC `get_patient_safety_context(p_patient_id)` returning structured allergies, current medications, chronic conditions, and the patient's **last prior-visit vitals** (FR-013); the rail upgrades to structured data with the empty state retained per category.
- **Rationale**: Lets the highest-value safety affordance appear in P1 with zero backend cost, then enriches it in P3 without changing the rail's contract. Last-vitals is a read-only convenience, naturally grouped with the other patient-level safety reads in one RPC to avoid extra round-trips.
- **Alternatives considered**: Folding last-vitals into `get_visit` (rejected — `get_visit` is visit-scoped; last vitals is patient-scoped and also needed on the rail before a visit's own vitals exist). Per-category RPCs (rejected — 3–4 round-trips for one rail).

## R4. Patient-level safety records — scope & schema

- **Decision**: Three patient-level tables (`patient_allergies`, `patient_medications`, `patient_chronic_conditions`), each FK → `patients(id)`, scoped via the patient's existing `organization_id` + `branch_id` (patients carry both). Standard audit + soft-delete columns; per-row `updated_at` for optimistic concurrency. Allergy = `substance` + `reaction` only (**no severity**, per clarification). Current medication = `name` (+ optional `medication_id` catalog link, optional `note`). Chronic condition = `name` (+ optional `diagnosis_code_id` link, optional `note`).
- **Rationale**: Patient-level reuse across visits (clarified scope); mirrors the proven 013 catalog/child-record conventions; RLS scopes through the patient row exactly as `patients` already do.
- **Alternatives considered**: Visit-level safety records (rejected by clarification — safety must persist across encounters); a single polymorphic `patient_safety` table (rejected — different columns per type; three small tables are clearer and easier to RLS/test).

## R5. Coded diagnosis catalog

- **Decision**: New org-scoped `diagnosis_codes` catalog (`organization_id`, `code`, `name`) reusing the exact 013 catalog pattern: `search_diagnosis_codes` typeahead (ILIKE on code or name) + `create_catalog_diagnosis_code` (idempotent on duplicate, returns existing id), wired through a thin `diagnosis_autocomplete_field.dart` over the existing `CatalogAutocompleteField`, with `CatalogNameNormalizer` applied. Visit linkage via `visit_diagnosis_codes` lines (denormalized `code`+`label`, nullable `diagnosis_code_id`) so custom entries and multiples are allowed alongside the free-text diagnosis.
- **Rationale**: Clarification chose an org-scoped catalog over a licensed terminology (no ICD-10 distribution/licensing); reuse means no new interaction pattern (FR-022) and minimal new code. Free-text diagnosis stays primary and unblocked (FR-023).
- **Alternatives considered**: Bundling a full ICD-10 dataset (rejected — licensing, size, and operator burden conflict with clinic-fit simplicity); storing only a single code on the clinical note (rejected — clinics often record multiple/differential codes; a line table is more flexible and matches the catalog-line idiom).

## R6. Structured Plan outputs & certificate

- **Decision**: One 1:1 `visit_plan_details` table (FK → visit, unique on visit_id) holding `follow_up_interval` (text) **and** `follow_up_date` (date, either/both optional), `patient_instructions` (text), `referral` (text: target + reason), and certificate-as-data fields `certificate_start_date`, `certificate_end_date`, `certificate_reason`. Saved via `save_visit_plan_details` upsert with optimistic concurrency (`STALE_PLAN_DETAILS`), mirroring `save_visit_documentation`.
- **Rationale**: These outputs are all 1:1 with a visit and edited together in the Plan phase; a single upsert table keeps round-trips and concurrency handling simple and consistent with the clinical-note pattern. Certificate is **data-only** (clarified — no document generation), so plain columns suffice.
- **Alternatives considered**: Separate tables per output / a `visit_certificates` 1:many table (rejected for this feature — over-modeling; one certificate per visit is sufficient and document export is out of scope); free-text-only (rejected — defeats the "structured outputs" requirement FR-024).

## R7. Objective enrichments — BMI, pain score, measurement time, results

- **Decision**:
  - **BMI**: derived **client-side only** in `bmi.dart` from the existing Height/Weight vital signs; never stored; shown only when both exist (FR-025).
  - **Pain score**: modeled as a seeded **predefined vital sign** ("Pain Score", unitless 0–10) rather than a new column — reuses the vital-sign builder and storage (FR-026).
  - **Vitals measurement time**: add nullable `measured_at timestamptz` to `visit_vital_signs`; `update/create_visit_vital_sign` accept it, distinct from `created_at`/save time (FR-026).
  - **Investigation results**: add `result text`, `result_recorded_at timestamptz`, `result_recorded_by uuid` to `visit_investigations`; new `record_investigation_result` RPC sets them on a later visit (FR-027).
- **Rationale**: Maximize reuse, minimize schema churn; BMI as a derived value avoids data drift; pain score via the vital-sign idiom avoids a bespoke field; result columns extend the existing investigation line in place.
- **Alternatives considered**: Storing BMI (rejected — derivable, risks staleness); a dedicated `pain_score` column on the clinical note (rejected — pain is a measurement that fits the vital-sign model and seed); a separate `investigation_results` table (rejected — results belong to the ordered line; in-place columns are simpler and keep `get_visit` flat).

## R8. `get_visit` payload extension strategy

- **Decision**: Extend `auth_internal.get_visit` to add `diagnosis_codes` (array), `plan_details` (object or null), and per-line `measured_at` / `result` / `result_recorded_at`. **Existing keys are untouched.** `VisitDetail.fromRow` parses the new keys defensively (absent → empty/null) so pre-P3 backends and 013 clients keep working.
- **Rationale**: Single round-trip preserved (performance goal); additive payload is backward compatible (constitution: replaceable layers, no cascading redesign). Patient-level safety + last vitals stay in the separate `get_patient_safety_context` RPC (R3) because they are patient-scoped.
- **Alternatives considered**: A new `get_visit_v2` (rejected — unnecessary duplication; additive keys suffice); multiple new per-section read RPCs (rejected — extra round-trips).

## R9. Expert-mode toggle persistence

- **Decision**: `workspace_mode_provider.dart` defaults to **guided**; the toggle is remembered per user via existing local client preference storage (best-effort, non-critical). Switching modes preserves the in-memory draft and save state (FR-019).
- **Rationale**: Clarification/Assumptions treat persistence as a minor nicety; no backend involvement keeps it simple and offline-safe.
- **Alternatives considered**: Server-stored preference (rejected — over-engineering for a view toggle); no memory (acceptable fallback if local storage is unavailable).

## R10. Responsive collapse for the 3-region layout

- **Decision**: Above a width breakpoint, render steps · canvas · safety rail side by side; below it, collapse the step rail to a compact selector and the safety rail to a collapsible top banner — the active phase and an allergy/alerts affordance remain visible at all widths (FR-020, edge case).
- **Rationale**: Desktop-first (constitution) but clinic laptops/narrow windows must not hide the safety affordance (SC-002).
- **Alternatives considered**: Hiding the safety rail on narrow widths (rejected — violates FR-010/SC-002); a fixed non-responsive layout (rejected — breaks on small windows).

---

## Resolved unknowns summary

| Topic | Decision |
| ----- | -------- |
| Navigation model | In-state active step; single route; non-linear |
| Badge state | Client-derived (empty/hasContent/error); submit still server-checked |
| Safety data (P1) | Degraded free-text alerts; (P3) `get_patient_safety_context` |
| Safety record schema | 3 patient-level tables; allergy has no severity |
| Coded diagnosis | Org `diagnosis_codes` catalog reusing 013 machinery; line table |
| Plan outputs | 1:1 `visit_plan_details` upsert; certificate data-only |
| BMI / pain / measured_at / results | Derived / seeded vital / new column / in-place result columns |
| `get_visit` | Additive keys only; backward compatible |
| Mode persistence | Local per-user, best-effort |
| Responsive | Collapse rails; never hide safety affordance |

No remaining `NEEDS CLARIFICATION` items.
