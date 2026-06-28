# Contract: Visit Mutations (014)

Replaces `specs/006-visit-medical-records/contracts/visit-mutations.md` visit documentation sections. `create_visit`, attachment RPCs, and visit completion coupling unchanged unless noted.

## Authorization summary

| RPC | Permission |
| --- | ---------- |
| `create_visit` | `visits.create` |
| `save_visit_documentation` | `visits.edit_soap` |
| `complete_visit` | `visits.edit_soap` |
| `create_treatment_plan` | `visits.edit_soap` |
| `update_treatment_plan` | `visits.edit_soap` |
| `archive_treatment_plan` | `visits.edit_soap` |
| `create_visit_vital_sign` | `visits.edit_soap` |
| `update_visit_vital_sign` | `visits.edit_soap` |
| `archive_visit_vital_sign` | `visits.edit_soap` |
| `create_visit_investigation` | `visits.edit_soap` |
| `archive_visit_investigation` | `visits.edit_soap` |
| `update_visit_investigation` | `visits.edit_soap` |
| `register_visit_attachment` | unchanged V1-5 |

**Removed**: `save_soap_note`

Allowed on `completed` visits: all `visits.edit_soap` mutations above (spec FR-017).

---

## RPC: `save_visit_documentation`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_id` | uuid | Yes |
| `p_complaint` | text | No |
| `p_history` | text | No |
| `p_examination` | text | No |
| `p_diagnosis` | text | No |
| `p_plan` | text | No |
| `p_expected_updated_at` | timestamptz | Yes |

**Rules**:

- Visit branch ∈ JWT `branch_ids`
- Optimistic concurrency: compare `p_expected_updated_at` to `visit_clinical_notes.updated_at` if row exists, else `visits.updated_at`
- Partial save allowed (sections may be empty on save)
- Each section max 10000 chars

**Returns** `data`:

```json
{
  "visit_id": "uuid",
  "updated_at": "timestamptz"
}
```

**Errors**: `FORBIDDEN`, `NOT_FOUND`, `STALE_DOCUMENTATION`, `INVALID_INPUT`

**Audit**: `visit.documentation_save`

---

## RPC: `complete_visit`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_id` | uuid | Yes |
| `p_expected_updated_at` | timestamptz | No |

**Rules** (updated):

- Visit status `in_progress`; linked appointment `in_progress`
- At least one clinical note field (complaint/history/examination/diagnosis/plan) contains non-whitespace text
- Atomically set visit → `completed`, appointment → `completed`

**Errors**: `DOCUMENTATION_REQUIRED_FOR_COMPLETE` (replaces `SOAP_REQUIRED_FOR_COMPLETE`), plus existing V1-5 codes

**Audit**: `visit.complete`, `appointment.status_completed`

---

## RPC: `create_treatment_plan`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_id` | uuid | Yes |
| `p_medication_name` | text | Yes |
| `p_medication_id` | uuid | No |
| `p_dosage` | text | Yes |
| `p_frequency` | text | Yes |
| `p_duration` | text | Yes |
| `p_notes` | text | No |

**Rules**:

- `p_medication_id` when set must belong to caller's organization
- `p_duration` non-empty after trim; max 200 chars
- No `start_date` / `end_date` parameters

**Returns** `data.treatment_plan_id`

---

## RPC: `update_treatment_plan`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_treatment_plan_id` | uuid | Yes |
| `p_medication_name` | text | No |
| `p_medication_id` | uuid | No |
| `p_dosage` | text | No |
| `p_frequency` | text | No |
| `p_duration` | text | No |
| `p_notes` | text | No |

**Rules**: Same validation as create when fields provided; dates not accepted.

---

## RPC: `create_visit_vital_sign`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_id` | uuid | Yes |
| `p_name` | text | Yes |
| `p_value` | text | Yes |
| `p_unit` | text | No |
| `p_predefined_vital_sign_id` | uuid | No |

**Returns** `data.vital_sign_id`

---

## RPC: `update_visit_vital_sign`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_vital_sign_id` | uuid | Yes |
| `p_name` | text | No |
| `p_value` | text | No |
| `p_unit` | text | No |
| `p_predefined_vital_sign_id` | uuid | No |

---

## RPC: `archive_visit_vital_sign`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_vital_sign_id` | uuid | Yes |

---

## RPC: `create_visit_investigation`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_id` | uuid | Yes |
| `p_name` | text | Yes |
| `p_note` | text | No |
| `p_investigation_id` | uuid | No |

**Returns** `data.investigation_line_id`

---

## RPC: `update_visit_investigation` / `archive_visit_investigation`

Same pattern as vital signs.

---

## RPC: `create_catalog_medication` / `create_catalog_investigation` / `create_predefined_vital_sign`

Used when doctor accepts save-to-catalog prompt. See `catalog-queries.md`.

**Permission**: `visits.edit_soap`

**Rules**: Name required (already normalized by client); on unique violation return existing catalog id (idempotent success).
