# Contract: `get_visit` Backward-Compatible Extension (014)

This note pins the compatibility rules for extending the 013 `get_visit` payload so P1/P2 (no backend change) and P3 (additive) interoperate cleanly.

## Invariants

- **Existing keys are never renamed, retyped, or removed.** 013 clients keep parsing the current payload.
- **New keys are additive**: `diagnosis_codes` (array, default `[]`), `plan_details` (object or `null`), plus per-line `measured_at` (vital signs) and `result` / `result_recorded_at` (investigations).
- **Single round-trip preserved**: all visit-scoped data continues to return from one `get_visit` call. Patient-scoped safety context (allergies/meds/conditions/last-vitals) is **not** added here — it is served by `get_patient_safety_context` (see `patient-safety.md`) because it is patient-scoped and needed independent of the current visit's own data.
- **Permission gating unchanged**: the new clinical blocks are included only when the caller `staff_has_visit_clinical_access()`, exactly like the existing `documentation`/`vital_signs`/`investigations` blocks.

## Client parsing rules (`VisitDetail.fromRow`)

| Key | Absent / null behavior |
| --- | ---------------------- |
| `diagnosis_codes` | Parse to empty list |
| `plan_details` | Parse to `null` (no structured plan yet) |
| `vital_signs[].measured_at` | `null` |
| `investigations[].result` / `result_recorded_at` | `null` |

This makes a P3-aware client safe against a pre-P3 backend (e.g., during phased rollout) and keeps 013 behavior intact.

## Versioning decision

No `get_visit_v2`. Additive keys on the existing function satisfy the constitution's replaceable-layer rule without duplicating the read path. If a future change must break a key, that is when a new versioned RPC would be introduced — out of scope here.
