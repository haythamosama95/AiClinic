# Quickstart: Visit Encounter Workspace (014)

How to build, run, and validate this feature locally. Builds on the 013 visits module; P1/P2 require **no** backend change.

## Prerequisites

- Local Supabase running with all migrations through `20260630120000_*` applied (013 visit documentation redesign in place).
- Flutter desktop (Windows) toolchain; `flutter pub get` done.
- A test org with branches, a doctor staff member holding `visits.edit_soap` and `visits.create`, and at least one patient with a checked-in/in-progress appointment.

## Build & run

```bash
# Frontend
cd frontend
flutter pub get
flutter run -d windows

# Backend (P3 only) — apply the additive migration
cd backend
supabase db reset            # dev only; or apply the new migration file forward
```

## Phase-by-phase validation

### P1 — header, regrouping, safety affordance (no backend change)

1. Open an in-progress visit → confirm the **encounter header** shows visit date/time, doctor, status, and (if present) visit type (US1 / FR-005).
2. Confirm content is grouped into **Context · Subjective · Objective · Assessment · Plan**, the old single clinical-note card is gone, Examination sits with Vital signs, and Plan sits with Treatments/Investigations/Attachments (US2 / FR-006–008).
3. Confirm a **safety surface** is visible on every phase, showing a free-text "alerts"/empty state (no structured data yet) and never blocking entry (US3 / FR-010–012).
4. Enter Height + Weight vitals → confirm **BMI** appears automatically; remove one → BMI hides (FR-025).
5. Open the detail view → same five-group layout (FR-009).

### P2 — workspace + modes (no backend change)

1. Default **guided stepper**: only the active phase renders in the center; step rail shows empty/has-content/error badges (US4 / FR-014–016).
2. Click directly from Context to **Plan** (non-linear) without visiting intermediate steps (FR-015 / SC-004).
3. Edit + save → sticky footer shows save status; concurrent stale save is rejected (FR-017).
4. Open **Review** → read-only summary + per-section edit links + submit; submitting with all clinical sections empty is rejected; otherwise the linked appointment advances (FR-018 / SC-005).
5. Toggle **expert mode** → five accordions on one page, safety surface retained, in-progress content preserved across the toggle (US5 / FR-019).
6. Shrink the window → step rail and safety rail collapse but the active phase and an allergy/alerts affordance stay visible (FR-020).

### P3 — structured data (additive migration)

1. Context phase: add an **allergy** (substance + reaction, **no severity**), a **current medication** (catalog or custom), and a **chronic condition**; reopen a *different* visit for the same patient → records appear in the safety rail without re-entry (US6 / FR-021).
2. Safety rail now shows structured allergies/meds/conditions + **last prior-visit vitals** (FR-013).
3. Assessment: search the **diagnosis catalog**, attach a coded diagnosis alongside free-text; custom entry offers save-to-catalog (US7 / FR-023).
4. Plan: set a **follow-up** interval/date, **patient instructions**, a **referral**, and a **sick-leave certificate** (dates + reason, data only — no document generated) (US7 / FR-024).
5. Objective: record a **pain score** (predefined vital sign), a vital **measurement time**, and on a later visit a **result** against a previously ordered investigation (US8 / FR-026/027).

## Tests

```bash
# Frontend
cd frontend
flutter analyze
flutter test test/unit/visits test/widget/visits

# Backend (P3)
cd backend
./tests/run_visit_medical_records_tests.sh   # includes new encounter-workspace CRUD + RLS suites
```

Focus areas: `bmi.dart` derivation; `encounter_step_provider` badge logic; regrouping coverage (every 013 field reachable, none duplicated — SC-005); safety rail presence on all phases (SC-002); expert/guided toggle data preservation; new RPC CRUD + cross-branch/cross-org RLS denial; `get_visit` additive-key backward compatibility.

## Rollback / safety

- P1/P2 are presentation-only; reverting the Flutter changes restores the 013 page with no data impact.
- P3 migration is **additive** (no drops); the new tables/columns can be left in place if the UI is rolled back. `get_visit` extra keys are ignored by 013 clients.
