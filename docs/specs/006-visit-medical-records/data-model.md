# Data Model: Visits and Medical Records

Introduces visit domain tables, storage bucket, permission seed extension, and appointment integration changes (V1-5). Builds on V1-1 auth, V1-2 org/branch/settings, V1-3 patients, V1-4 appointments.

## New schema (V1-5 migration)

### ENUM: `visit_status`

```sql
CREATE TYPE public.visit_status AS ENUM ('in_progress', 'completed');
```

### ENUM: `visit_attachment_file_type` (optional; or text + CHECK)

```sql
CREATE TYPE public.visit_attachment_file_type AS ENUM ('pdf', 'docx', 'jpeg', 'png');
```

### TABLE: `visits`

| Column           | Type                    | Notes                                                               |
| ---------------- | ----------------------- | ------------------------------------------------------------------- |
| `id`             | uuid PK                 | `gen_random_uuid()`                                                 |
| `branch_id`      | uuid FK → branches      | Copied from appointment; immutable                                  |
| `appointment_id` | uuid FK → appointments  | **One active visit per appointment** (partial unique index)         |
| `patient_id`     | uuid FK → patients      | Copied from appointment                                             |
| `doctor_id`      | uuid FK → staff_members | Required at creation; may be selected when appointment had none     |
| `visit_date`     | date NOT NULL           | Clinical date from appointment `start_time` in org timezone         |
| `status`         | visit_status            | Entry: `in_progress`; `complete_visit` → `completed`                |
| audit columns    | standard                | `created_at`, `created_by`, `updated_at`, `updated_by`, soft delete |

**Constraints**:

- `UNIQUE (appointment_id) WHERE is_deleted = false`
- FK appointment/patient/doctor must belong to same org as branch

### TABLE: `soap_notes`

| Column                | Type                    | Notes                                              |
| --------------------- | ----------------------- | -------------------------------------------------- |
| `id`                  | uuid PK                 |                                                    |
| `visit_id`            | uuid FK → visits UNIQUE | One SOAP row per visit                             |
| `subjective`          | text                    | Max 10000 chars (app + DB)                         |
| `objective`           | text                    | Max 10000 chars                                    |
| `assessment`          | text                    | Max 10000 chars                                    |
| `plan`                | text                    | Max 10000 chars                                    |
| `specialty_form_json` | jsonb                   | Default `{}`; validated against org schema on save |
| audit columns         | standard                | Used for optimistic concurrency on save            |

### TABLE: `treatment_plans`

| Column            | Type               | Notes                                 |
| ----------------- | ------------------ | ------------------------------------- |
| `id`              | uuid PK            |                                       |
| `visit_id`        | uuid FK → visits   |                                       |
| `patient_id`      | uuid FK → patients | Denormalized from visit               |
| `medication_name` | text NOT NULL      | Max 500 chars                         |
| `dosage`          | text               | Optional                              |
| `frequency`       | text               | Optional                              |
| `start_date`      | date               | Optional                              |
| `end_date`        | date               | Optional; must be ≥ start if both set |
| `notes`           | text               | Optional; max 2000 chars              |
| audit columns     | standard           | Soft delete for remove action         |

### TABLE: `visit_attachments`

| Column        | Type                       | Notes                                          |
| ------------- | -------------------------- | ---------------------------------------------- |
| `id`          | uuid PK                    |                                                |
| `visit_id`    | uuid FK → visits           |                                                |
| `file_path`   | text NOT NULL              | Storage object key under `visit-attachments`   |
| `file_type`   | visit_attachment_file_type | Derived from MIME at registration              |
| `label`       | text                       | Optional; max 200 chars                        |
| `uploaded_by` | uuid FK → staff_members    | Caller at registration                         |
| `size_bytes`  | bigint                     | Validated ≤ 26214400 (25 MB)                   |
| audit columns | standard                   | Soft delete optional future; not required V1-5 |

### Indexes

```sql
CREATE INDEX visits_patient_visit_date_idx
  ON public.visits (patient_id, visit_date DESC, created_at DESC)
  WHERE is_deleted = false;

CREATE INDEX visits_branch_visit_date_idx
  ON public.visits (branch_id, visit_date DESC)
  WHERE is_deleted = false;

CREATE INDEX treatment_plans_visit_idx
  ON public.treatment_plans (visit_id)
  WHERE is_deleted = false;

CREATE INDEX visit_attachments_visit_idx
  ON public.visit_attachments (visit_id)
  WHERE is_deleted = false;
```

### RLS (summary)

| Table               | SELECT                             | INSERT/UPDATE/DELETE |
| ------------------- | ---------------------------------- | -------------------- |
| `visits`            | Branch ∈ JWT; `is_deleted = false` | Deny direct writes   |
| `soap_notes`        | Via visit branch scope             | Deny direct writes   |
| `treatment_plans`   | Via visit branch scope             | Deny direct writes   |
| `visit_attachments` | Via visit branch scope             | Deny direct writes   |

Mutations **only** via RPC. Reads may use SELECT under RLS **or** list/get RPCs for permission-aware field filtering.

### Storage bucket: `visit-attachments`

| Setting    | Value                                                              |
| ---------- | ------------------------------------------------------------------ |
| Visibility | Private                                                            |
| Max size   | 25 MB per object (enforced in storage config + RPC)                |
| Path       | `{organization_id}/{branch_id}/{visit_id}/{uuid}_{sanitized_name}` |

Storage policies (summary):

- **INSERT**: authenticated; path prefix matches org/branch; caller has upload permission; visit exists and branch ∈ JWT
- **SELECT**: authenticated; same prefix; download rules mirror RPC (clinical permissions OR own upload)
- **DELETE**: deny for app users (orphan cleanup via service role / dev scripts only)

## Settings extension (existing `app_settings`)

| Key                          | Scope | Value                                      |
| ---------------------------- | ----- | ------------------------------------------ |
| `specialty.form_schema_json` | org   | JSON Schema object for dynamic form fields |

Resolution: org row (`branch_id IS NULL`) only in V1-5; branch override deferred.

## Permission seed extension

| permission_key             | owner | administrator | doctor | receptionist | lab_staff |
| -------------------------- | ----- | ------------- | ------ | ------------ | --------- |
| `visits.create`            | ✓     | ✓             | ✓      |              |           |
| `visits.edit_soap`         | ✓     | ✓             | ✓      |              |           |
| `visits.upload_attachment` | ✓     | ✓             | ✓      |              | ✓         |

(`visits.create` / `visits.edit_soap` already seeded in V1-1; migration adds `visits.upload_attachment` rows.)

## Entity lifecycle

### Visit

| Event                     | Visit status  | Appointment status (before → after) |
| ------------------------- | ------------- | ----------------------------------- |
| Create from `checked_in`  | `in_progress` | `checked_in` → `in_progress`        |
| Create from `in_progress` | `in_progress` | `in_progress` → `in_progress`       |
| Submit complete           | `completed`   | `in_progress` → `completed`         |

| From          | To          | Permission         |
| ------------- | ----------- | ------------------ |
| `in_progress` | `completed` | `visits.edit_soap` |
| `completed`   | (none)      | —                  |

SOAP and treatment plan edits on `completed` visits remain allowed with audit (corrections before billing).

### Appointment integration change

`update_appointment_status`: remove allowed transition `in_progress` → `completed`. Error code `VISIT_REQUIRED_FOR_COMPLETION` with message directing user to submit visit.

## Authorization matrix (V1-5)

| Operation                   | Permission key(s)                                                   |
| --------------------------- | ------------------------------------------------------------------- |
| Create visit                | `visits.create`                                                     |
| Save SOAP / treatment plans | `visits.edit_soap`                                                  |
| Submit visit complete       | `visits.edit_soap`                                                  |
| Upload attachment           | `visits.upload_attachment` OR `visits.create` OR `visits.edit_soap` |
| Download attachment (full)  | `visits.create` OR `visits.edit_soap`                               |
| Download own attachment     | `visits.upload_attachment` AND `uploaded_by = caller`               |
| List visit history metadata | `patients.view` (branch/org patient scope)                          |
| Open visit clinical detail  | `visits.create` OR `visits.edit_soap`                               |

## RPC inventory

| RPC                             | Purpose                                              |
| ------------------------------- | ---------------------------------------------------- |
| `create_visit`                  | From eligible appointment; doctor pick; audit        |
| `save_soap_note`                | Upsert SOAP + specialty JSON; optimistic concurrency |
| `complete_visit`                | Validate SOAP; complete visit + appointment          |
| `create_treatment_plan`         | Add line item                                        |
| `update_treatment_plan`         | Edit line item                                       |
| `archive_treatment_plan`        | Soft delete line item                                |
| `register_visit_attachment`     | Metadata after storage upload                        |
| `get_visit_attachment_download` | Authorized signed download                           |
| `get_visit`                     | Full visit detail                                    |
| `get_visit_by_appointment`      | Lookup for appointment context                       |
| `list_patient_visits`           | Paginated history metadata                           |
| `get_specialty_form_schema`     | Org specialty JSON schema                            |

## Audit actions

| Action                         | Trigger                     |
| ------------------------------ | --------------------------- |
| `visit.create`                 | `create_visit`              |
| `visit.soap_save`              | `save_soap_note`            |
| `visit.complete`               | `complete_visit`            |
| `appointment.status_completed` | inside `complete_visit`     |
| `visit.treatment_plan.create`  | `create_treatment_plan`     |
| `visit.treatment_plan.update`  | `update_treatment_plan`     |
| `visit.treatment_plan.archive` | `archive_treatment_plan`    |
| `visit.attachment.register`    | `register_visit_attachment` |

## Error codes (domain)

| Code                            | Meaning                                  |
| ------------------------------- | ---------------------------------------- |
| `FORBIDDEN`                     | Permission or branch                     |
| `NOT_FOUND`                     | Unknown id                               |
| `INVALID_INPUT`                 | Validation                               |
| `APPOINTMENT_NOT_ELIGIBLE`      | Status not `checked_in`/`in_progress`    |
| `VISIT_ALREADY_EXISTS`          | Duplicate for appointment                |
| `DOCTOR_REQUIRED`               | Missing doctor on appointment            |
| `STALE_SOAP`                    | Optimistic concurrency conflict          |
| `SOAP_REQUIRED_FOR_COMPLETE`    | All SOAP sections empty on submit        |
| `APPOINTMENT_NOT_IN_PROGRESS`   | Linked appointment changed during submit |
| `VISIT_REQUIRED_FOR_COMPLETION` | Manual appointment complete blocked      |
| `INVALID_FILE_TYPE`             | Not PDF/DOCX/JPEG/PNG                    |
| `FILE_TOO_LARGE`                | > 25 MB                                  |
| `ATTACHMENT_DOWNLOAD_DENIED`    | Lab staff downloading others' files      |
