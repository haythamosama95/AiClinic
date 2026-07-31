# Research: Visits Page Redesign (014)

Decisions for Phase 0 unknowns. No `NEEDS CLARIFICATION` items remain after spec clarifications (2026-06-28).

---

## R1 — Clinical note storage model

**Decision**: One row per visit in `visit_clinical_notes` (1:1 with `visits.id`), replacing `soap_notes`.

**Rationale**: Mirrors existing SOAP 1:1 pattern; simplifies `get_visit` join; supports optimistic concurrency on `updated_at` like V1-5.

**Alternatives considered**:
- Columns on `visits` table — rejected (mixes lifecycle metadata with large text blobs)
- Separate row per section — rejected (unnecessary normalization for five fixed fields)

---

## R2 — Catalog scope and search

**Decision**: Organization-scoped catalogs (`medications`, `investigations`, `predefined_vital_signs`) with `UNIQUE (organization_id, lower(trim(name))) WHERE is_deleted = false`. Search via `search_medications` / `search_investigations` RPC with `ilike` prefix/substring match, `LIMIT 20`, ordered by name.

**Rationale**: Spec clarifications: catalogs shared across branches in an org; fast typing search; matches existing multi-tenant patterns.

**Alternatives considered**:
- Branch-scoped catalogs — rejected (out of scope per spec assumptions)
- Client-side filter on full catalog fetch — rejected (does not scale; spec requires backend-backed search)

---

## R3 — Custom entry → catalog prompt

**Decision**: After saving a visit line with a custom normalized name, Flutter shows `SaveToCatalogDialog`. Accept calls `create_catalog_medication` / `create_catalog_investigation` / `create_predefined_vital_sign` RPC; decline leaves denormalized name on visit line only.

**Rationale**: Spec clarification Option C; backend deduplicates on unique constraint (return existing id if name matches).

**Alternatives considered**:
- Auto-append to catalog — rejected (typo pollution)
- Visit-line only always — rejected (user chose optional prompt)

---

## R4 — Custom name normalization (frontend)

**Decision**: `CatalogNameNormalizer.normalize(String raw)` → trim, collapse internal whitespace, capitalize first character. Applied before display, RPC payload, and catalog prompt.

**Rationale**: Spec clarification: custom names must match catalog entry formatting; pure Dart unit-testable; no server-side locale rules needed.

**Alternatives considered**:
- Title-case every word — rejected (medication names like "IBUPROFEN" edge cases; leading cap sufficient)
- Backend normalization — rejected (spec assigns to frontend; display consistency before network)

---

## R5 — Legacy SOAP/specialty handling

**Decision**: Drop `soap_notes` table and all specialty form visit integration. No data migration. `get_specialty_form_schema` removed from visit flows.

**Rationale**: Spec clarifications: new view only; discard legacy content.

**Alternatives considered**:
- Read-only legacy section — rejected by user
- Auto-map SOAP → new fields — rejected by user

---

## R6 — Treatment time fields

**Decision**: `treatment_plans` retains `duration text NOT NULL` on create (required in UI); drop `start_date` and `end_date` columns. One-time SQL migration: `duration = (end_date - start_date) || ' days'` when both set; else keep existing `duration` if present.

**Rationale**: Spec clarification: duration only; aligns with existing `20260601100000_treatment_plan_duration.sql` partial work.

**Alternatives considered**:
- Keep date columns hidden — rejected (spec requires removal)

---

## R7 — Save interaction model

**Decision**: Explicit **Save** for clinical note (like V1-5 SOAP editor) with `p_expected_updated_at` optimistic concurrency. Vital signs, treatments, and investigations save per line via existing create/update/archive RPC pattern (immediate on add/edit/remove).

**Rationale**: V1-5 established pattern; avoids partial auto-save complexity; clear error on `STALE_DOCUMENTATION`.

**Alternatives considered**:
- Auto-save debounced clinical note — deferred (higher UX risk during consultations)

---

## R8 — Catalog autocomplete UI pattern

**Decision**: Debounced RPC search (300ms, matching `appointment_booking_sheet` patient search) in a `CatalogAutocompleteField` wrapping `AppTextField` + overlay results list; free-text commit when no selection.

**Rationale**: Reuses proven clinic search UX; meets SC-002 perceived speed; no new pubspec dependencies.

**Alternatives considered**:
- `AppAutocomplete` with static `Map` — rejected (catalog is dynamic/backend-backed)

---

## R9 — Permission key naming

**Decision**: Keep `visits.edit_soap` permission key unchanged; map to all new documentation mutations.

**Rationale**: Spec assumption defers rename; avoids migration of permission seeds and Flutter `PermissionService` churn in this feature.

**Alternatives considered**:
- Rename to `visits.edit_documentation` — deferred to follow-up

---

## R10 — Complete visit validation

**Decision**: Replace `SOAP_REQUIRED_FOR_COMPLETE` with `DOCUMENTATION_REQUIRED_FOR_COMPLETE`; require at least one of complaint/history/examination/diagnosis/plan non-whitespace in `visit_clinical_notes`.

**Rationale**: FR-011 direct mapping; same rule shape as V1-5.

**Alternatives considered**:
- Require specific section (e.g. Complaint only) — rejected (spec allows any section)
