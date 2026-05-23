# Contract: Patient Create, Read, Update, Archive, Duplicates

## Purpose

Patient profile mutations and duplicate detection (V1-3).

## Authorization

| RPC                        | Permission                           |
| -------------------------- | ------------------------------------ |
| `get_patient`              | `patients.view`                      |
| `check_patient_duplicates` | `patients.create` or `patients.edit` |
| `create_patient`           | `patients.create`                    |
| `update_patient`           | `patients.edit`                      |
| `archive_patient`          | `patients.delete`                    |

---

## RPC: `get_patient`

| Parameter      | Type | Required |
| -------------- | ---- | -------- |
| `p_patient_id` | uuid | Yes      |

**Rules**:

- Patient `organization_id` must match JWT org
- `is_deleted = false` for normal detail route

**Returns**: Full profile + `branch_name`, `created_at`, `updated_at`, `updated_at` for optimistic edit

**Errors**: `NOT_FOUND`, `FORBIDDEN`, `PATIENT_ARCHIVED`

---

## RPC: `check_patient_duplicates`

| Parameter              | Type | Required |
| ---------------------- | ---- | -------- |
| `p_full_name`          | text | No       |
| `p_phone`              | text | No       |
| `p_date_of_birth`      | date | No       |
| `p_national_id`        | text | No       |
| `p_exclude_patient_id` | uuid | No       | For edit flows |

**Returns**: `data.candidates[]` with id, full_name, phone, national_id, date_of_birth, branch_name

**Matching** (non-archived, same org):

- National ID normalized match → included; also checked separately on create/update for hard block
- Phone digits match
- `lower(trim(full_name))` + same `date_of_birth`

---

## RPC: `create_patient`

| Parameter                 | Type    | Required |
| ------------------------- | ------- | -------- |
| `p_active_branch_id`      | uuid    | Yes      |
| `p_full_name`             | text    | Yes      |
| `p_phone`                 | text    | No       |
| `p_date_of_birth`         | date    | No       |
| `p_gender`                | text    | No       | `patient_gender` enum |
| `p_national_id`           | text    | No       |
| `p_notes`                 | text    | No       |
| `p_acknowledge_duplicate` | boolean | No       | Default false         |

**Rules**:

- `p_active_branch_id` ∈ caller JWT `branch_ids` and active
- Set `branch_id` and `organization_id` from branch
- Normalize phone to digits; validate 8–15 if present
- National ID unique in org → else `NATIONAL_ID_EXISTS`
- Run duplicate check; if candidates and not `p_acknowledge_duplicate` → `DUPLICATE_WARNING` with candidates in `data` (no insert)
- On success: audit `patient.create`

**Returns**: `data.patient_id`

---

## RPC: `update_patient`

| Parameter                 | Type        | Required |
| ------------------------- | ----------- | -------- |
| `p_patient_id`            | uuid        | Yes      |
| `p_full_name`             | text        | Yes      |
| `p_phone`                 | text        | No       |
| `p_date_of_birth`         | date        | No       |
| `p_gender`                | text        | No       |
| `p_national_id`           | text        | No       |
| `p_notes`                 | text        | No       |
| `p_expected_updated_at`   | timestamptz | Yes      |
| `p_acknowledge_duplicate` | boolean     | No       |

**Rules**:

- Patient in caller org; not archived
- `updated_at` must equal `p_expected_updated_at` else `STALE_PATIENT`
- National ID uniqueness excluding self
- Duplicate advisory when identifiers change
- `branch_id` not mutable
- Audit `patient.update` with old/new json

---

## RPC: `archive_patient`

| Parameter      | Type | Required |
| -------------- | ---- | -------- |
| `p_patient_id` | uuid | Yes      |

**Rules**:

- Org scope; not already archived
- Soft delete via standard columns
- Audit `patient.archive`
- No downstream appointment guard in V1-3

---

## Flutter routes

| Route                | Page                        | Permission        |
| -------------------- | --------------------------- | ----------------- |
| `/patients/new`      | Registration form           | `patients.create` |
| `/patients/:id`      | Detail + visits placeholder | `patients.view`   |
| `/patients/:id/edit` | Edit form                   | `patients.edit`   |

**Detail actions**:

- Edit → `/patients/:id/edit`
- Archive → confirm dialog → `archive_patient` when `patients.delete`

**Edit UX**: Load `updated_at` into form; on `STALE_PATIENT`, show banner + reload button.

**Duplicate UX**: Dialog listing candidates; **Continue anyway** sets `acknowledge_duplicate=true` and retries RPC.

---

## Error codes (client mapping)

| Code                 | User message (representative)                            |
| -------------------- | -------------------------------------------------------- |
| `NATIONAL_ID_EXISTS` | This national ID is already registered.                  |
| `DUPLICATE_WARNING`  | Similar patients found — review before saving.           |
| `STALE_PATIENT`      | This record was updated elsewhere. Reload and try again. |
| `PATIENT_ARCHIVED`   | This patient is archived and cannot be edited.           |
| `INVALID_INPUT`      | Field validation message from server                     |
