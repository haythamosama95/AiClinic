# Contract: Visit Plan Outputs & Objective Enrichments (014, P3)

Structured Plan-phase outputs (1:1 with visit) and Objective-phase enrichments (vital measurement time, investigation results). Pattern and scoping identical to 013 visit RPCs (`assert_visit_branch_scope`, `visits.edit_soap`, audit_log, `rpc_result`).

---

## RPC: `save_visit_plan_details` (1:1 upsert, optimistic concurrency)

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_id` | uuid | Yes |
| `p_expected_updated_at` | timestamptz | Yes (null on first save when no row exists → use visit `updated_at`, mirroring `save_visit_documentation`) |
| `p_follow_up_interval` | text | No (≤100) |
| `p_follow_up_date` | date | No |
| `p_patient_instructions` | text | No (≤10000) |
| `p_referral` | text | No (≤2000) |
| `p_certificate_start_date` | date | No |
| `p_certificate_end_date` | date | No |
| `p_certificate_reason` | text | No (≤2000) |

**Rules**:

- Upsert the single `visit_plan_details` row for the visit.
- Optimistic concurrency: if current `updated_at` ≠ `p_expected_updated_at` → `STALE_PLAN_DETAILS`.
- Certificate fields are **data only** — no document is generated (clarified).
- `certificate_end_date >= certificate_start_date` when both present → else `INVALID_INPUT`.

**Returns** `data`: `{ "visit_id": "uuid", "updated_at": "ts" }`

---

## RPC: `record_investigation_result`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_investigation_line_id` | uuid | Yes |
| `p_result` | text | No (≤10000; null clears) |

**Rules**: Sets `result`, `result_recorded_at = now()`, `result_recorded_by = auth.uid()` on the existing `visit_investigations` line (which may have been ordered on a prior visit). Branch-scoped via the line's visit.

**Returns** `data`: `{ "investigation_line_id": "uuid", "result_recorded_at": "ts" }`

---

## Updated RPCs: vital sign measurement time

`create_visit_vital_sign` and `update_visit_vital_sign` gain an optional parameter:

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_measured_at` | timestamptz | No |

Stored in the new `visit_vital_signs.measured_at`, distinct from `created_at` (save time). All other parameters/behavior unchanged from 013.

**Pain score**: no new parameter — recorded as a vital sign whose name is the seeded predefined "Pain Score" (value 0–10), using the existing vital-sign builder.

**BMI**: never sent or stored — derived client-side from Height/Weight vitals (`bmi.dart`).

---

## `get_visit` payload extension

`auth_internal.get_visit` adds the following keys (existing keys unchanged; absent → client parses as empty/null):

```json
{
  "diagnosis_codes": [
    { "id": "uuid", "code": "I10", "label": "Essential hypertension", "diagnosis_code_id": "uuid|null" }
  ],
  "plan_details": {
    "follow_up_interval": "in 2 weeks",
    "follow_up_date": "date|null",
    "patient_instructions": "string|null",
    "referral": "string|null",
    "certificate_start_date": "date|null",
    "certificate_end_date": "date|null",
    "certificate_reason": "string|null",
    "updated_at": "ts"
  },
  "vital_signs": [ { "...013 fields": "...", "measured_at": "ts|null" } ],
  "investigations": [ { "...013 fields": "...", "result": "string|null", "result_recorded_at": "ts|null" } ]
}
```

`plan_details` is `null` when no row exists. `diagnosis_codes` is `[]` when none. Only doctors with clinical access receive these blocks (gated exactly like the existing clinical payload in `get_visit`).

---

## Client integration & errors

1. `visit_plan_details.dart` model + `save_visit_plan_details` wrapper; Plan phase edits flow through the existing documentation notifier with its own `expectedUpdatedAt` for plan details.
2. Investigation result entry lives in the Objective phase result list (later visit) → `record_investigation_result`.
3. `bmi.dart` derives and displays BMI only when both Height and Weight vitals exist (FR-025).
4. Errors: `STALE_PLAN_DETAILS`, `FORBIDDEN`, `NOT_FOUND`, `INVALID_INPUT`.
