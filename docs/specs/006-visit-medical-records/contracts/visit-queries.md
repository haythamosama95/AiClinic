# Contract: Visit Queries

## Purpose

Read paths for visit detail, appointment linkage, patient history, specialty schema, and authorized attachment download (V1-5).

---

## RPC: `get_visit`

| Parameter    | Type | Required |
| ------------ | ---- | -------- |
| `p_visit_id` | uuid | Yes      |

**Authorization**:

- Metadata (date, doctor, status, branch): caller with branch SELECT scope
- SOAP, treatment plans, attachment list: `visits.create` OR `visits.edit_soap`
- Users with `patients.view` only receive metadata subset (no SOAP bodies)

**Returns** `data`:

```json
{
  "id": "uuid",
  "branch_id": "uuid",
  "appointment_id": "uuid",
  "patient_id": "uuid",
  "doctor_id": "uuid",
  "doctor_name": "string",
  "visit_date": "date",
  "status": "in_progress|completed",
  "soap": {
    "subjective": "string",
    "objective": "string",
    "assessment": "string",
    "plan": "string",
    "specialty_form_json": {},
    "updated_at": "timestamptz"
  },
  "treatment_plans": [],
  "attachments": [
    {
      "id": "uuid",
      "file_type": "pdf",
      "label": "string",
      "uploaded_by": "uuid",
      "uploaded_by_name": "string",
      "size_bytes": 12345,
      "created_at": "timestamptz",
      "can_download": true
    }
  ]
}
```

`can_download` computed server-side for lab-staff own-upload rule.

**Errors**: `FORBIDDEN`, `NOT_FOUND`

---

## RPC: `get_visit_by_appointment`

| Parameter          | Type | Required |
| ------------------ | ---- | -------- |
| `p_appointment_id` | uuid | Yes      |

**Rules**: Branch scope; returns visit id + status if exists, else empty.

**Returns** `data`:

```json
{
  "visit_id": "uuid|null",
  "status": "in_progress|completed|null"
}
```

Used by appointment UI for **Open visit** vs **Create visit**.

---

## RPC: `list_patient_visits`

| Parameter      | Type | Required | Default |
| -------------- | ---- | -------- | ------- |
| `p_patient_id` | uuid | Yes      |         |
| `p_limit`      | int  | No       | 50      |
| `p_offset`     | int  | No       | 0       |

**Authorization**: `patients.view`; patient in org; visits filtered to branches caller can access.

**Rules**:

- Order: `visit_date DESC`, `created_at DESC`
- Metadata only (no SOAP content)

**Returns** `data`:

```json
{
  "items": [
    {
      "id": "uuid",
      "visit_date": "date",
      "doctor_name": "string",
      "status": "in_progress|completed",
      "branch_name": "string"
    }
  ],
  "total_count": 120,
  "limit": 50,
  "offset": 0
}
```

---

## RPC: `get_specialty_form_schema`

No parameters.

**Authorization**: Any authenticated staff with visit read access at active branch (or `visits.edit_soap`).

**Returns** `data.schema_json` — JSON Schema object or `{}` when unset.

---

## RPC: `get_visit_attachment_download`

| Parameter         | Type | Required |
| ----------------- | ---- | -------- |
| `p_attachment_id` | uuid | Yes      |

**Authorization**:

- `visits.create` OR `visits.edit_soap` at visit branch → any attachment on visit
- OR `visits.upload_attachment` AND attachment.`uploaded_by` = caller staff member

**Returns** `data`:

```json
{
  "signed_url": "string",
  "file_type": "pdf",
  "filename": "string",
  "expires_at": "timestamptz"
}
```

**Errors**: `FORBIDDEN`, `NOT_FOUND`, `ATTACHMENT_DOWNLOAD_DENIED`

---

## Direct SELECT (optional read path)

RLS-permitted SELECT on `visits` / joined tables may be used for internal tooling; Flutter SHOULD use RPCs above for consistent permission filtering.

---

## Shared error codes

| Code                         | Meaning                               |
| ---------------------------- | ------------------------------------- |
| `FORBIDDEN`                  | Permission or branch                  |
| `NOT_FOUND`                  | Unknown id                            |
| `ATTACHMENT_DOWNLOAD_DENIED` | Lab staff downloading others' uploads |
