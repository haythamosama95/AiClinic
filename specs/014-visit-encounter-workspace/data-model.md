# Data Model: Visit Encounter Workspace (014)

Builds additively on feature 013 (`specs/013-visits/data-model.md`). **P1 and P2 introduce no schema change** (pure presentation over the existing 013 model). **P3** adds the structures below. Nothing from 013/V1-5 is dropped; `get_visit` is extended with new keys only.

Standard audit/soft-delete columns (matching 013) on every new table:
`created_at timestamptz NOT NULL DEFAULT now()`, `created_by uuid REFERENCES auth.users(id)`, `updated_at timestamptz`, `updated_by uuid REFERENCES auth.users(id)`, `is_deleted boolean NOT NULL DEFAULT false`, `deleted_at timestamptz`, `deleted_by uuid REFERENCES auth.users(id)`.

---

## Presentation-only mapping (P1/P2 — no storage)

The five encounter phases are a **view grouping** over existing fields; no column moves in the database.

| Phase | Existing source (013) |
| ----- | --------------------- |
| Context | `visits` metadata (date/time, doctor, status, type) + patient snapshot + safety surface |
| Subjective | `visit_clinical_notes.complaint`, `.history` |
| Objective | `visit_vital_signs` + `visit_clinical_notes.examination` (+ derived BMI, investigation results in P3) |
| Assessment | `visit_clinical_notes.diagnosis` (+ coded diagnosis in P3) |
| Plan | `visit_clinical_notes.plan` + `treatment_plans` + `visit_investigations` + `visit_attachments` (+ plan outputs in P3) |

BMI is **derived client-side** from Height/Weight `visit_vital_signs`; never stored.

---

## New patient-level tables (P3)

Scoped through the patient row (`patients` already carry `organization_id` + `branch_id`). RLS: SELECT where patient is in caller's org/branch; writes denied except via RPC.

### `patient_allergies`

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | `gen_random_uuid()` |
| `patient_id` | uuid FK → patients NOT NULL | |
| `substance` | text NOT NULL | Max 200; client-normalized |
| `reaction` | text | Optional; max 500 |
| audit columns | standard | Soft delete; `updated_at` concurrency |

**No `severity` column** (per clarification). Index `(patient_id) WHERE is_deleted = false`.

### `patient_medications` (current / home meds)

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `patient_id` | uuid FK → patients NOT NULL | |
| `medication_id` | uuid FK → medications | Nullable (catalog link) |
| `name` | text NOT NULL | Denormalized; max 200; normalized |
| `note` | text | Optional; max 500 |
| audit columns | standard | |

### `patient_chronic_conditions` (problem list)

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `patient_id` | uuid FK → patients NOT NULL | |
| `diagnosis_code_id` | uuid FK → diagnosis_codes | Nullable (catalog link) |
| `name` | text NOT NULL | Denormalized; max 200; normalized |
| `note` | text | Optional; max 500 |
| audit columns | standard | |

---

## New org catalog table (P3)

### `diagnosis_codes`

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `organization_id` | uuid FK → organizations NOT NULL | |
| `code` | text | Optional; max 20 (e.g., ICD-like clinic code) |
| `name` | text NOT NULL | Max 200 |
| audit columns | standard | Soft delete |

**Unique**: `(organization_id, lower(trim(name))) WHERE is_deleted = false`. RLS SELECT `organization_id = jwt_organization_id()`; writes via RPC only. Mirrors `medications`/`investigations`.

---

## New visit-level tables (P3)

### `visit_diagnosis_codes`

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `visit_id` | uuid FK → visits NOT NULL | |
| `diagnosis_code_id` | uuid FK → diagnosis_codes | Nullable (custom allowed) |
| `code` | text | Denormalized; max 20 |
| `label` | text NOT NULL | Denormalized; max 200 |
| audit columns | standard | Soft delete |

Multiple lines per visit allowed (final/differential). Index `(visit_id) WHERE is_deleted = false`. Coexists with free-text `visit_clinical_notes.diagnosis`.

### `visit_plan_details` (1:1 with visit)

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `visit_id` | uuid FK → visits NOT NULL | `UNIQUE (visit_id)` |
| `follow_up_interval` | text | Optional; max 100 (e.g., "in 2 weeks") |
| `follow_up_date` | date | Optional |
| `patient_instructions` | text | Optional; max 10000 |
| `referral` | text | Optional; max 2000 (target + reason) |
| `certificate_start_date` | date | Optional |
| `certificate_end_date` | date | Optional |
| `certificate_reason` | text | Optional; max 2000 |
| audit columns | standard | `updated_at` for optimistic concurrency |

Certificate is **data only** (no document generation — clarified). Upsert via `save_visit_plan_details` with `STALE_PLAN_DETAILS` concurrency check on `updated_at`, mirroring `save_visit_documentation`.

---

## Altered 013 tables (P3, additive columns)

### `visit_vital_signs`

| Change | Detail |
| ------ | ------ |
| Add | `measured_at timestamptz` (nullable) — when the measurement was taken, distinct from `created_at` |

### `visit_investigations`

| Change | Detail |
| ------ | ------ |
| Add | `result text` (nullable; max 10000) |
| Add | `result_recorded_at timestamptz` (nullable) |
| Add | `result_recorded_by uuid REFERENCES auth.users(id)` (nullable) |

---

## Dev seed data (P3, per organization, idempotent)

- **`diagnosis_codes`** (≥10 samples): e.g., Essential hypertension (I10), Type 2 diabetes mellitus (E11), Acute upper respiratory infection (J06.9), Gastro-oesophageal reflux disease (K21), Migraine (G43), … Seed only when org has zero non-deleted rows.
- **Predefined vital sign** "Pain Score" (no default unit, 0–10 scale by convention) added to `predefined_vital_signs` seed if absent — backs FR-026 pain score via the existing vital-sign builder.

---

## RLS (summary, new tables)

| Table | SELECT | INSERT/UPDATE/DELETE |
| ----- | ------ | -------------------- |
| `patient_allergies` | Patient in caller org+branch | Deny direct (RPC only) |
| `patient_medications` | Patient in caller org+branch | Deny direct |
| `patient_chronic_conditions` | Patient in caller org+branch | Deny direct |
| `diagnosis_codes` | `organization_id = jwt org` | Deny direct |
| `visit_diagnosis_codes` | Via visit branch scope | Deny direct |
| `visit_plan_details` | Via visit branch scope | Deny direct |

Mutations **only** via `auth_internal` SECURITY DEFINER RPCs + `public` wrappers.

---

## Authorization matrix (014 P3 extensions)

| Operation | Permission |
| --------- | ---------- |
| Patient safety record CRUD (allergy/med/condition) | `visits.edit_soap` |
| Read patient safety context | `visits.edit_soap` OR `patients.view` |
| Diagnosis catalog search | `visits.edit_soap` OR `visits.create` |
| Diagnosis catalog create (save-to-catalog) | `visits.edit_soap` |
| Visit diagnosis-code line create/archive | `visits.edit_soap` |
| Save visit plan details | `visits.edit_soap` |
| Record investigation result | `visits.edit_soap` |
| Update vital sign `measured_at` | `visits.edit_soap` (existing RPC extended) |

Post-submit edits on `completed` visits remain allowed when permission held (spec FR-003), consistent with 013.

---

## RPC inventory (P3)

### New

| RPC | Purpose |
| --- | ------- |
| `get_patient_safety_context` | Allergies + current meds + chronic conditions + last prior-visit vitals (FR-010/013) |
| `create_patient_allergy` / `update_patient_allergy` / `archive_patient_allergy` | Allergy CRUD |
| `create_patient_medication` / `update_patient_medication` / `archive_patient_medication` | Current-meds CRUD |
| `create_patient_chronic_condition` / `update_patient_chronic_condition` / `archive_patient_chronic_condition` | Problem-list CRUD |
| `search_diagnosis_codes` | Org diagnosis catalog typeahead |
| `create_catalog_diagnosis_code` | Optional save-to-catalog (idempotent) |
| `create_visit_diagnosis_code` / `archive_visit_diagnosis_code` | Visit coded-diagnosis lines |
| `save_visit_plan_details` | 1:1 upsert; optimistic concurrency (`STALE_PLAN_DETAILS`) |
| `record_investigation_result` | Set result fields on a visit investigation line |

### Updated

| RPC | Change |
| --- | ------ |
| `update_visit_vital_sign` / `create_visit_vital_sign` | Accept optional `p_measured_at` |
| `get_visit` | Add `diagnosis_codes`, `plan_details`, vital `measured_at`, investigation `result`/`result_recorded_at` (existing keys unchanged) |

`create_visit`, `complete_visit`, attachment RPCs, `list_patient_visits`, `save_visit_documentation`, catalog/medication/investigation RPCs: **unchanged**.

---

## Audit actions (P3)

| Action | Trigger |
| ------ | ------- |
| `patient.allergy.create/update/archive` | allergy RPCs |
| `patient.medication.create/update/archive` | current-meds RPCs |
| `patient.chronic_condition.create/update/archive` | condition RPCs |
| `catalog.diagnosis_code.create` | `create_catalog_diagnosis_code` |
| `visit.diagnosis_code.create/archive` | visit diagnosis-code RPCs |
| `visit.plan_details_save` | `save_visit_plan_details` |
| `visit.investigation.result_record` | `record_investigation_result` |

---

## Error codes (P3)

| Code | Meaning |
| ---- | ------- |
| `STALE_PLAN_DETAILS` | Optimistic concurrency conflict on `visit_plan_details` |
| `CATALOG_DUPLICATE` | Diagnosis-code save-to-catalog duplicate → return existing id (success) |

Retain all 013/V1-5 error codes. No codes removed.

---

## Entity lifecycle

- `visits` status transitions unchanged from V1-5/013; no new lifecycle.
- Patient safety records persist at patient level across visits; editable any time with permission.
- Visit-level structured records (`visit_diagnosis_codes`, `visit_plan_details`, investigation results) editable in both `in_progress` and `completed` states with `visits.edit_soap` (FR-003), consistent with 013.
