# Contract: Patient Safety Records (014, P3)

Patient-level safety data surfaced/edited from the Context phase and reused across visits. All RPCs follow the 013 pattern: `auth_internal.<fn>` (SECURITY DEFINER) + `public.<fn>` wrapper, returning `public.rpc_result` (`rpc_success`/`rpc_error`). Scoped via the patient's `organization_id` + `branch_id`. Custom names are client-normalized (`CatalogNameNormalizer`) before call.

## Authorization summary

| RPC | Permission |
| --- | ---------- |
| `get_patient_safety_context` | `visits.edit_soap` OR `patients.view` |
| `create/update/archive_patient_allergy` | `visits.edit_soap` |
| `create/update/archive_patient_medication` | `visits.edit_soap` |
| `create/update/archive_patient_chronic_condition` | `visits.edit_soap` |

Branch/org scope enforced by resolving the patient row and checking `organization_id = jwt_organization_id()` and `branch_id = ANY(jwt_branch_ids())`. Returns `NOT_FOUND` when the patient is outside scope (no cross-branch leakage).

---

## RPC: `get_patient_safety_context`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_patient_id` | uuid | Yes |

**Returns** `data`:

```json
{
  "allergies": [{ "id": "uuid", "substance": "Penicillin", "reaction": "Rash" }],
  "current_medications": [{ "id": "uuid", "name": "Metformin", "medication_id": "uuid|null", "note": null }],
  "chronic_conditions": [{ "id": "uuid", "name": "Hypertension", "diagnosis_code_id": "uuid|null", "note": null }],
  "last_vitals": {
    "visit_id": "uuid|null",
    "visit_date": "date|null",
    "items": [{ "name": "Blood Pressure", "value": "140/90", "unit": "mmHg", "measured_at": "ts|null" }]
  }
}
```

**Rules**: `last_vitals` reads the most recent **prior** completed/in-progress visit of the patient that has vital signs (excludes the current visit when a `p_exclude_visit_id` is later needed; for now most-recent by `visit_date`). Empty arrays when no data (drives the degraded empty state). Read-only.

---

## RPC: `create_patient_allergy`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_patient_id` | uuid | Yes |
| `p_substance` | text | Yes (≤200, normalized) |
| `p_reaction` | text | No (≤500) |

**Returns** `data`: `{ "id": "uuid" }`. **No severity parameter.**

## RPC: `update_patient_allergy`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_allergy_id` | uuid | Yes |
| `p_substance` | text | No |
| `p_reaction` | text | No |

## RPC: `archive_patient_allergy`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_allergy_id` | uuid | Yes |

Soft delete (`is_deleted = true`, `deleted_at/by`). Returns `{ "id": "uuid" }`.

---

## RPC: `create_patient_medication`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_patient_id` | uuid | Yes |
| `p_name` | text | Yes (≤200, normalized) |
| `p_medication_id` | uuid | No (catalog link) |
| `p_note` | text | No (≤500) |

`update_patient_medication` (`p_medication_record_id`, optional `p_name`/`p_medication_id`/`p_note`) and `archive_patient_medication` (`p_medication_record_id`) mirror the allergy shape.

---

## RPC: `create_patient_chronic_condition`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_patient_id` | uuid | Yes |
| `p_name` | text | Yes (≤200, normalized) |
| `p_diagnosis_code_id` | uuid | No (catalog link) |
| `p_note` | text | No (≤500) |

`update_patient_chronic_condition` (`p_condition_id`, optional fields) and `archive_patient_chronic_condition` (`p_condition_id`) mirror the allergy shape.

---

## Audit & errors

- Audit actions: `patient.allergy.*`, `patient.medication.*`, `patient.chronic_condition.*` into `public.audit_log` (`user_id`, `organization_id`, `action`, `table_name`, `record_id`).
- Errors: `FORBIDDEN` (permission), `NOT_FOUND` (patient/record out of scope), `INVALID_INPUT` (missing/oversized fields).

## Client integration notes

1. `patient_safety_provider.dart` calls `get_patient_safety_context` on workspace load; feeds `patient_safety_rail.dart`.
2. Context-phase editors reuse `CatalogAutocompleteField` for current-meds (medication catalog) and chronic conditions (diagnosis catalog), with `SaveToCatalogDialog` on custom entry.
3. Allergy editor is free-text substance + reaction (no catalog requirement, no severity).
4. Empty categories render an explicit empty state; before any structured data exists (P1), the rail shows the degraded free-text alerts line instead.
