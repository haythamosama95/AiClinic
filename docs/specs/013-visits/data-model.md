# Data Model: Visits Page Redesign (014)

Builds on V1-5 (`docs/specs/006-visit-medical-records/data-model.md`). Replaces SOAP/specialty documentation; adds catalogs and visit child records. Attachments and visit lifecycle unchanged.

## Removed

| Artifact | Action |
| -------- | ------ |
| `soap_notes` table | `DROP TABLE` after migration deploy |
| `specialty_form_json` on visits | Removed with `soap_notes` |
| `save_soap_note` RPC | Dropped |
| `get_specialty_form_schema` RPC (visit usage) | Dropped from public API |
| `treatment_plans.start_date`, `end_date` | Migrated to `duration`, then dropped |
| `STALE_SOAP` error | Replaced by `STALE_DOCUMENTATION` |
| `SOAP_REQUIRED_FOR_COMPLETE` | Replaced by `DOCUMENTATION_REQUIRED_FOR_COMPLETE` |

## New tables

### `visit_clinical_notes`

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | `gen_random_uuid()` |
| `visit_id` | uuid FK → visits UNIQUE | One row per visit |
| `complaint` | text | Max 10000 chars |
| `history` | text | Max 10000 chars (HPI) |
| `examination` | text | Max 10000 chars |
| `diagnosis` | text | Max 10000 chars |
| `plan` | text | Max 10000 chars |
| audit columns | standard | Optimistic concurrency on `updated_at` |

**Constraints**: Each text column `CHECK (length(coalesce(col,'')) <= 10000)`

### `medications` (org catalog)

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `organization_id` | uuid FK → organizations NOT NULL | |
| `name` | text NOT NULL | Max 200 chars |
| audit columns | standard | Soft delete |

**Unique**: `(organization_id, lower(trim(name))) WHERE is_deleted = false`

### `investigations` (org catalog)

Same shape as `medications`.

### `predefined_vital_signs` (org catalog)

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `organization_id` | uuid FK NOT NULL | |
| `name` | text NOT NULL | Max 100 chars |
| `default_unit` | text | Optional; max 50 chars |
| audit columns | standard | Soft delete |

**Unique**: `(organization_id, lower(trim(name))) WHERE is_deleted = false`

### `visit_vital_signs`

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `visit_id` | uuid FK → visits NOT NULL | |
| `predefined_vital_sign_id` | uuid FK → predefined_vital_signs | Nullable |
| `name` | text NOT NULL | Denormalized; max 100 |
| `value` | text NOT NULL | Max 200 |
| `unit` | text | Optional; max 50 |
| audit columns | standard | Soft delete |

### `visit_investigations`

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `visit_id` | uuid FK → visits NOT NULL | |
| `investigation_id` | uuid FK → investigations | Nullable |
| `name` | text NOT NULL | Denormalized; max 200 |
| `note` | text | Optional; max 2000 |
| audit columns | standard | Soft delete |

## Updated tables

### `treatment_plans`

| Change | Detail |
| ------ | ------ |
| Add | `medication_id uuid FK → medications` (nullable) |
| Keep | `medication_name`, `dosage`, `frequency`, `duration`, `notes` |
| Remove | `start_date`, `end_date`, `treatment_plans_end_after_start` CHECK |
| Migration | `duration := coalesce(nullif(trim(duration),''), (end_date - start_date)::text \|\| ' days')` when dates exist |

**Create rules**: `medication_name` required; `duration` required (non-empty trim); `dosage` and `frequency` required per FR-005 UI validation.

## Dev seed data (per organization on migration)

**Predefined vital signs**: Blood Pressure (mmHg), Heart Rate (bpm), Temperature (°C), Respiratory Rate (/min), Oxygen Saturation (%), Weight (kg), Height (cm)

**Sample medications** (≥10): e.g. Amoxicillin, Ibuprofen, Paracetamol, Omeprazole, Metformin, …

**Sample investigations** (≥10): e.g. Complete Blood Count, Lipid Panel, Chest X-Ray, Urinalysis, …

Seeds insert only when org has zero non-deleted rows in each catalog (idempotent).

## RLS (summary)

| Table | SELECT | INSERT/UPDATE/DELETE |
| ----- | ------ | -------------------- |
| `visit_clinical_notes` | Via visit branch scope | Deny direct writes |
| `medications` | `organization_id = jwt org` | Deny direct writes |
| `investigations` | `organization_id = jwt org` | Deny direct writes |
| `predefined_vital_signs` | `organization_id = jwt org` | Deny direct writes |
| `visit_vital_signs` | Via visit branch scope | Deny direct writes |
| `visit_investigations` | Via visit branch scope | Deny direct writes |
| `treatment_plans` | Via visit branch scope (unchanged) | Deny direct writes |

Mutations **only** via RPC.

## Authorization matrix (014 extensions)

| Operation | Permission |
| --------- | ---------- |
| Save clinical note | `visits.edit_soap` |
| Complete visit | `visits.edit_soap` |
| Treatment plan CRUD | `visits.edit_soap` |
| Vital sign / investigation CRUD | `visits.edit_soap` |
| Catalog search (read) | `visits.edit_soap` OR `visits.create` |
| Catalog create (save-to-catalog prompt) | `visits.edit_soap` |
| Attachments | unchanged V1-5 |

Post-submit edits on `completed` visits: allowed for all above when permission held (spec FR-017).

## RPC inventory

### Replaced / removed

| RPC | Action |
| --- | ------ |
| `save_soap_note` | Replace with `save_visit_documentation` |
| `get_specialty_form_schema` | Remove |

### New / updated

| RPC | Purpose |
| --- | ------- |
| `save_visit_documentation` | Upsert clinical note; optimistic concurrency |
| `search_medications` | Org catalog typeahead |
| `search_investigations` | Org catalog typeahead |
| `list_predefined_vital_signs` | Full org predefined list |
| `create_catalog_medication` | Optional save-to-catalog |
| `create_catalog_investigation` | Optional save-to-catalog |
| `create_predefined_vital_sign` | Optional save-to-catalog |
| `create_visit_vital_sign` | Add vital sign line |
| `update_visit_vital_sign` | Edit line |
| `archive_visit_vital_sign` | Soft delete line |
| `create_visit_investigation` | Add investigation line |
| `update_visit_investigation` | Edit line |
| `archive_visit_investigation` | Soft delete line |
| `create_treatment_plan` | Updated: `p_medication_id`, `p_duration` required; no dates |
| `update_treatment_plan` | Updated: same |
| `get_visit` | Returns `documentation`, `vital_signs`, `investigations`; no `soap` |
| `complete_visit` | Clinical note non-empty check |

`create_visit`, attachment RPCs, `list_patient_visits`, `get_visit_by_appointment`: unchanged except `get_visit` payload.

## Audit actions

| Action | Trigger |
| ------ | ------- |
| `visit.documentation_save` | `save_visit_documentation` |
| `visit.complete` | `complete_visit` (unchanged) |
| `visit.vital_sign.create/update/archive` | vital sign RPCs |
| `visit.investigation.create/update/archive` | investigation RPCs |
| `catalog.medication.create` | `create_catalog_medication` |
| `catalog.investigation.create` | `create_catalog_investigation` |
| `catalog.vital_sign.create` | `create_predefined_vital_sign` |
| `visit.treatment_plan.*` | unchanged |

Remove: `visit.soap_save`

## Error codes

| Code | Meaning |
| ---- | ------- |
| `STALE_DOCUMENTATION` | Optimistic concurrency conflict on clinical note |
| `DOCUMENTATION_REQUIRED_FOR_COMPLETE` | All five clinical sections empty on submit |
| `CATALOG_DUPLICATE` | _(Not returned)_ Idempotent duplicate catalog names are a successful RPC result (`success: true`) with the existing catalog id and `created: false`; clients should not treat this as an error |
| `DURATION_REQUIRED` | Treatment missing duration |

Retain all V1-5 visit/attachment error codes not listed above as removed.

## Entity lifecycle

Unchanged from V1-5 for `visits` status transitions. Clinical note, vital signs, treatments, investigations editable in both `in_progress` and `completed` states (with permission).
