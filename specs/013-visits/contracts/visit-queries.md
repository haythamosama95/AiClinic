# Contract: Visit Queries (014)

Updates `specs/006-visit-medical-records/contracts/visit-queries.md` for new `get_visit` payload. Other query RPCs unchanged.

---

## RPC: `get_visit`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_id` | uuid | Yes |

**Authorization** (unchanged):

- Metadata: branch SELECT scope
- Full documentation (clinical note, vital signs, treatments, investigations, attachments): `visits.create` OR `visits.edit_soap`
- `patients.view` only: metadata subset (no clinical bodies)

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
  "updated_at": "timestamptz",
  "documentation": {
    "complaint": "string",
    "history": "string",
    "examination": "string",
    "diagnosis": "string",
    "plan": "string",
    "updated_at": "timestamptz"
  },
  "vital_signs": [
    {
      "id": "uuid",
      "name": "string",
      "value": "string",
      "unit": "string|null",
      "predefined_vital_sign_id": "uuid|null"
    }
  ],
  "treatment_plans": [
    {
      "id": "uuid",
      "medication_name": "string",
      "medication_id": "uuid|null",
      "dosage": "string",
      "frequency": "string",
      "duration": "string",
      "notes": "string|null"
    }
  ],
  "investigations": [
    {
      "id": "uuid",
      "name": "string",
      "note": "string|null",
      "investigation_id": "uuid|null"
    }
  ],
  "attachments": []
}
```

**Removed fields**: `soap`, `specialty_form_json`

Pre-redesign visits without `visit_clinical_notes` row return empty strings in `documentation` sections.

**Errors**: `FORBIDDEN`, `NOT_FOUND`

---

## RPC: `get_visit_by_appointment`

Unchanged from V1-5.

---

## RPC: `list_patient_visits`

Unchanged metadata shape from V1-5 (no clinical bodies in list).

---

## RPC: `get_visit_attachment_download`

Unchanged from V1-5.
