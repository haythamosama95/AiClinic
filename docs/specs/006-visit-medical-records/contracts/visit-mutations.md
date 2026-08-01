# Contract: Visit Mutations

## Purpose

Create visits, document encounters (SOAP, specialty JSON, treatment plans), submit completion, and register attachments (V1-5).

## Authorization summary

| RPC                             | Permission                                                          |
| ------------------------------- | ------------------------------------------------------------------- |
| `create_visit`                  | `visits.create`                                                     |
| `save_soap_note`                | `visits.edit_soap`                                                  |
| `complete_visit`                | `visits.edit_soap`                                                  |
| `create_treatment_plan`         | `visits.edit_soap`                                                  |
| `update_treatment_plan`         | `visits.edit_soap`                                                  |
| `archive_treatment_plan`        | `visits.edit_soap`                                                  |
| `register_visit_attachment`     | `visits.upload_attachment` OR `visits.create` OR `visits.edit_soap` |
| `get_visit_attachment_download` | See queries contract (download gate)                                |

---

## RPC: `create_visit`

| Parameter          | Type | Required    | Notes                                         |
| ------------------ | ---- | ----------- | --------------------------------------------- |
| `p_appointment_id` | uuid | Yes         | Appointment ∈ caller branch scope             |
| `p_doctor_id`      | uuid | Conditional | Required when appointment.`doctor_id` IS NULL |

**Rules**:

- Appointment status ∈ (`checked_in`, `in_progress`); not archived patient
- No existing non-deleted visit for appointment
- If appointment is `checked_in`, set appointment → `in_progress`
- If appointment lacks doctor, `p_doctor_id` must be branch doctor (`role = doctor`)
- Copy `patient_id`, `branch_id`; set `visit_date` from appointment local date
- Initial visit status `in_progress`

**Returns** `data`:

```json
{
  "visit_id": "uuid",
  "appointment_id": "uuid",
  "status": "in_progress",
  "visit_date": "2026-05-31"
}
```

**Errors**: `FORBIDDEN`, `NOT_FOUND`, `APPOINTMENT_NOT_ELIGIBLE`, `VISIT_ALREADY_EXISTS`, `DOCTOR_REQUIRED`, `INVALID_DOCTOR`

**Audit**: `visit.create`; if appointment advanced, `appointment.status_in_progress`

---

## RPC: `save_soap_note`

| Parameter               | Type        | Required |
| ----------------------- | ----------- | -------- |
| `p_visit_id`            | uuid        | Yes      |
| `p_subjective`          | text        | No       |
| `p_objective`           | text        | No       |
| `p_assessment`          | text        | No       |
| `p_plan`                | text        | No       |
| `p_specialty_form_json` | jsonb       | No       |
| `p_expected_updated_at` | timestamptz | Yes      |

**Rules**:

- Visit branch ∈ JWT `branch_ids`
- Optimistic concurrency: compare `p_expected_updated_at` to `soap_notes.updated_at` if row exists, else `visits.updated_at`
- Partial SOAP allowed (at least one section may be empty on save)
- Validate `specialty_form_json` against org schema when non-empty

**Returns** `data`:

```json
{
  "visit_id": "uuid",
  "updated_at": "timestamptz"
}
```

**Errors**: `FORBIDDEN`, `NOT_FOUND`, `STALE_SOAP`, `INVALID_INPUT`

**Audit**: `visit.soap_save`

---

## RPC: `complete_visit`

| Parameter               | Type        | Required |
| ----------------------- | ----------- | -------- |
| `p_visit_id`            | uuid        | Yes      |
| `p_expected_updated_at` | timestamptz | No       |

**Rules**:

- Visit status must be `in_progress`
- Linked appointment status must be `in_progress`
- At least one SOAP section (S/O/A/P) contains non-whitespace text
- Optional final `p_expected_updated_at` check on SOAP row before status change
- Atomically: visit → `completed`, appointment → `completed`

**Returns** `data`:

```json
{
  "visit_id": "uuid",
  "visit_status": "completed",
  "appointment_id": "uuid",
  "appointment_status": "completed"
}
```

**Errors**: `FORBIDDEN`, `NOT_FOUND`, `SOAP_REQUIRED_FOR_COMPLETE`, `APPOINTMENT_NOT_IN_PROGRESS`, `STALE_SOAP`

**Audit**: `visit.complete`, `appointment.status_completed`

---

## RPC: `create_treatment_plan`

| Parameter           | Type | Required |
| ------------------- | ---- | -------- |
| `p_visit_id`        | uuid | Yes      |
| `p_medication_name` | text | Yes      |
| `p_dosage`          | text | No       |
| `p_frequency`       | text | No       |
| `p_start_date`      | date | No       |
| `p_end_date`        | date | No       |
| `p_notes`           | text | No       |

**Returns** `data.treatment_plan_id`

**Audit**: `visit.treatment_plan.create`

---

## RPC: `update_treatment_plan`

| Parameter                                       | Type | Required |
| ----------------------------------------------- | ---- | -------- |
| `p_treatment_plan_id`                           | uuid | Yes      |
| (same fields as create, all optional except id) |      |          |

**Audit**: `visit.treatment_plan.update`

---

## RPC: `archive_treatment_plan`

| Parameter             | Type | Required |
| --------------------- | ---- | -------- |
| `p_treatment_plan_id` | uuid | Yes      |

Soft-deletes row (`is_deleted = true`).

**Audit**: `visit.treatment_plan.archive`

---

## RPC: `register_visit_attachment`

| Parameter      | Type   | Required | Notes                                   |
| -------------- | ------ | -------- | --------------------------------------- |
| `p_visit_id`   | uuid   | Yes      |                                         |
| `p_file_path`  | text   | Yes      | Must match `{org}/{branch}/{visit}/...` |
| `p_file_type`  | text   | Yes      | `pdf`, `docx`, `jpeg`, `png`            |
| `p_label`      | text   | No       |                                         |
| `p_size_bytes` | bigint | Yes      | ≤ 26214400                              |

**Rules**:

- Object must already exist in `visit-attachments` bucket (client upload first)
- MIME/extension cross-check in implementation
- Sets `uploaded_by` to caller staff member

**Returns** `data.attachment_id`

**Errors**: `FORBIDDEN`, `NOT_FOUND`, `INVALID_FILE_TYPE`, `FILE_TOO_LARGE`, `INVALID_INPUT`

**Audit**: `visit.attachment.register`

---

## Storage upload (client contract, not RPC)

Before `register_visit_attachment`:

```dart
await supabase.storage.from('visit-attachments').upload(
  '$orgId/$branchId/$visitId/$uuid_$filename',
  file,
  fileOptions: FileOptions(contentType: mimeType),
);
```

Storage policies enforce branch scope and upload permission. Progress UI required (NFR-004).

---

## Appointment status RPC change

`update_appointment_status`: transition `in_progress` → `completed` **removed**.

**Error**: `VISIT_REQUIRED_FOR_COMPLETION` — "Complete the visit documentation to finish this appointment."
