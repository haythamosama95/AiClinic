# Data Model: Patient Management

Introduces `public.patients` (V1-3). Builds on V1-1/V1-2 tenancy tables from `specs/002-auth-rbac/data-model.md` and `specs/003-org-branch-management/data-model.md`.

## New schema (V1-3 migration)

### ENUM: `patient_gender`

```sql
CREATE TYPE public.patient_gender AS ENUM (
  'male',
  'female',
  'other',
  'unknown'
);
```

### TABLE: `patients`

| Column            | Type                     | Notes                                                                      |
| ----------------- | ------------------------ | -------------------------------------------------------------------------- |
| `id`              | uuid PK                  | `gen_random_uuid()`                                                        |
| `branch_id`       | uuid FK → branches       | Registering branch; immutable in V1-3 UI                                   |
| `organization_id` | uuid FK → organizations  | Denormalized from `branch_id` at create for RLS and national ID uniqueness |
| `full_name`       | text NOT NULL            | Trimmed; min 1 char                                                        |
| `phone`           | text                     | Digits only when set; 8–15 digits                                          |
| `date_of_birth`   | date                     | Optional; not future                                                       |
| `gender`          | patient_gender           | Optional                                                                   |
| `national_id`     | text                     | Optional; unique per org when set                                          |
| `notes`           | text                     | Max 4000 chars (app + DB check)                                            |
| audit columns     | timestamptz/uuid/boolean | Standard platform conventions                                              |

### Indexes

```sql
CREATE INDEX patients_branch_full_name_idx ON public.patients (branch_id, full_name)
  WHERE is_deleted = false;

CREATE INDEX patients_branch_phone_idx ON public.patients (branch_id, phone)
  WHERE is_deleted = false AND phone IS NOT NULL;

CREATE UNIQUE INDEX patients_org_national_id_unique
  ON public.patients (organization_id, lower(trim(national_id)))
  WHERE national_id IS NOT NULL
    AND trim(national_id) <> ''
    AND is_deleted = false;
```

### RLS (summary)

| Policy            | Rule                                                                           |
| ----------------- | ------------------------------------------------------------------------------ |
| `patients_select` | Authenticated; `is_deleted = false`; `organization_id = jwt.organization_id()` |
| `patients_insert` | Deny direct insert (RPC only)                                                  |
| `patients_update` | Deny direct update (RPC only)                                                  |
| `patients_delete` | Deny direct delete                                                             |

Reads for list/detail may use SELECT under RLS **or** search RPC returning JSON — mutations **only** via RPC.

## Entity lifecycle

### Patient

| State    | `is_deleted` | In list/search | Detail (normal) | Edit | Archive again |
| -------- | ------------ | -------------- | --------------- | ---- | ------------- |
| Active   | false        | Yes            | Yes             | Yes  | Yes           |
| Archived | true         | No             | Denied / N/A    | No   | No            |

**Create**: `branch_id` = caller’s active branch (validated membership in `branch_ids` JWT); requires `patients.create`.

**Update**: Any patient in org with `patients.edit`; `p_expected_updated_at` required.

**Archive**: Soft delete with `patients.delete`; org-wide.

## Deduplication rules

| Match type  | Condition                                         | UI         |
| ----------- | ------------------------------------------------- | ---------- |
| National ID | Same org, same normalized ID, other patient       | Hard block |
| Phone       | Same org, same digits, other non-archived patient | Advisory   |
| Name + DOB  | Same org, case-insensitive name trim + same DOB   | Advisory   |

Archived patients excluded from duplicate candidate sets.

## Authorization matrix (V1-3)

| Operation          | Permission key    | Scope                         |
| ------------------ | ----------------- | ----------------------------- |
| List/search/detail | `patients.view`   | Org via RLS                   |
| Register           | `patients.create` | Active branch for `branch_id` |
| Edit               | `patients.edit`   | Org                           |
| Archive            | `patients.delete` | Org                           |

Seeded grants (V1-1): owner/administrator/doctor/receptionist — full CRUD; `lab_staff` — view only.

## RPC inventory (planned names)

| RPC                        | Purpose                                                                                |
| -------------------------- | -------------------------------------------------------------------------------------- |
| `search_patients`          | Paginated list/search; scope `branch` \| `organization`; field detection phone vs name |
| `get_patient`              | Detail by id; rejects archived for normal flow                                         |
| `check_patient_duplicates` | Advisory candidates before create/edit                                                 |
| `create_patient`           | Register at active branch; duplicate acknowledge flag                                  |
| `update_patient`           | Profile update + optimistic lock                                                       |
| `archive_patient`          | Soft delete                                                                            |

## Client models (Flutter)

| Type                 | Fields (representative)                                                      |
| -------------------- | ---------------------------------------------------------------------------- |
| `PatientListItem`    | id, fullName, phone, dateOfBirth, registeringBranchId, registeringBranchName |
| `PatientDetail`      | all profile fields + createdAt, updatedAt, createdBy display                 |
| `PatientEditorState` | form fields + expectedUpdatedAt                                              |
| `DuplicateCandidate` | id, fullName, phone, nationalId, dateOfBirth, branchName                     |
| `PatientListScope`   | `thisBranch` \| `allBranches`                                                |

## Relationships

```text
branches 1──* patients (registering branch)
organizations 1──* branches
patients ── (future) appointments, visits, invoices
```

## Audit actions (new)

| Action            | Trigger           |
| ----------------- | ----------------- |
| `patient.create`  | `create_patient`  |
| `patient.update`  | `update_patient`  |
| `patient.archive` | `archive_patient` |
