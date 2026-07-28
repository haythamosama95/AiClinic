# Data Model: Patient MRN (Medical Record Number)

Extends `public.patients` (V1-3, `20260523140000_patient_management.sql`) with a globally-unique, immutable Medical Record Number. Adds a PostgreSQL sequence, a global unique index, an admin-only reassignment RPC, and a new permission seed. No new tables, no new audit subsystem (reuses `audit_log`), no Edge Functions, no AI surface.

## New schema (migration `20260724120000_patient_mrn_field.sql`)

### SEQUENCE: `public.patient_mrn_seq`

```sql
CREATE SEQUENCE public.patient_mrn_seq
  AS bigint
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  NO CYCLE;
```

- Global, single namespace across all organizations/branches (one MRN space per database — spec Clarification).
- Never wraps (`NO CYCLE`); `bigint` capacity exceeds any plausible clinic-scale patient volume.
- Reset only by the dev-reset test helper (`setval('public.patient_mrn_seq', 1, false)`), never by application flows.

### TABLE: `public.patients` (additive change)

| Column            | Type       | Notes                                                                                 |
| ----------------- | ---------- | ------------------------------------------------------------------------------------- |
| *(existing cols)* | *(unchanged)* | `id`, `branch_id`, `organization_id`, `full_name`, `phone`, `date_of_birth`, `gender`, `national_id`, `notes`, audit columns |
| `mrn` *(new)*     | text NOT NULL | Globally unique; format `MRN-NNNNNN` (prefix + zero-padded ≥6 digits); set on insert by `assign_patient_mrn()`, never null, never reused. |

### Migration order (single file)

```sql
-- 1. Add column nullable so existing rows can be backfilled
ALTER TABLE public.patients ADD COLUMN mrn text;

-- 2. Backfill every existing row with a unique sequence-derived MRN
UPDATE public.patients
   SET mrn = format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0'))
 WHERE mrn IS NULL;

-- 3. Enforce NOT NULL
ALTER TABLE public.patients ALTER COLUMN mrn SET NOT NULL;

-- 4. Global unique index (spans all rows incl. soft-deleted — MRNs never reused)
CREATE UNIQUE INDEX patients_mrn_unique ON public.patients (mrn);
```

### Indexes

```sql
CREATE UNIQUE INDEX patients_mrn_unique ON public.patients (mrn);
-- Additional access patterns handled by existing patients_branch_full_name_idx / patients_branch_phone_idx
```

- The unique index is **not** partial on `is_deleted = false`. An issued MRN is never released for reuse, including on soft delete. See `research.md` Decision 2.

### RLS (unchanged)

Existing `patients` policies are unchanged — `mrn` is just a new column read under the same policies:

| Policy            | Rule (unchanged)                                                                          |
| ----------------- | ----------------------------------------------------------------------------------------- |
| `patients_select` | Authenticated; `is_deleted = false`; `organization_id = jwt.organization_id()` (covers `mrn`) |
| `patients_insert` | Deny direct insert (RPC only)                                                             |
| `patients_update` | Deny direct update (RPC only)                                                             |
| `patients_delete` | Deny direct delete                                                                        |

MRN uniqueness is **global** (DB constraint) and is **not** filtered by `organization_id` RLS; visibility of the value continues to be org-scoped (a user cannot read another org's patient's MRN because they cannot read that row at all).

## MRN format

| Component | Value                              |
| --------- | ---------------------------------- |
| Prefix    | `MRN-`                             |
| Number    | Zero-padded decimal, width 6+     |
| Example   | `MRN-000001`, `MRN-000042`, `MRN-104857` |
| Regex     | `^MRN-\d{6,}$`                     |

- Generation (normal path): `format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0'))` inside `auth_internal.assign_patient_mrn()`. `lpad` handles widths beyond 6 transparently (no overflow break).
- Reassignment (admin path): caller supplies the target value; RPC trims, uppercases, validates the regex, and checks uniqueness.

## Entity lifecycle

### Patient (status unchanged from V1-3)

| State    | `is_deleted` | MRN presence                | MRN editable inline | MRN reassignable |
| -------- | ------------ | --------------------------- | ------------------- | ---------------- |
| Active   | false        | Always present (`NOT NULL`) | No (read-only)      | Yes (admin RPC)  |
| Archived | true         | Retained (never reused)     | No                  | No (RPC rejects `PATIENT_ARCHIVED`) |

**Create**: `create_patient` RPC assigns `mrn` via `assign_patient_mrn()` inside the same transaction as the row insert; uniqueness is guaranteed by the sequence + the unique index backstop.

**Archive**: `archive_patient` is unchanged — the MRN column stays populated on the soft-deleted row; no sequence release.

### MRN reassignment state machine

```text
[patient row with mrn=A]
        │  admin calls reassign_patient_mrn(patient, B)
        │  RPC: assert_permission('patients.reassign_mrn')
        │       assert_org_patient (not archived)
        │       validate B matches ^MRN-\d{6,}$
        │       SELECT 1 FROM patients WHERE mrn=B AND id <> p_patient_id
        │         → if found: return rpc_error('MRN_EXISTS', '…', data={'conflicting_mrn': B})
        │       UPDATE patients SET mrn=B
        │       audit_log: action='patient.mrn_reassign', old={mrn:A}, new={mrn:B}
        ▼
[patient row with mrn=B]
```

- No state transition on the patient itself (still Active). Only the `mrn` value changes.
- All downstream surfaces (list, detail, invoices, appointments) read `mrn` via JOIN, so they reflect the new value on next refresh (FR-008).

## Authorization matrix (V1-3 + 016)

| Operation             | Permission key             | Scope                                | Role grants             |
| --------------------- | -------------------------- | ------------------------------------ | ----------------------- |
| View MRN in list/detail/invoice/appointment | `patients.view` (existing)  | Org via RLS                          | all clinical + admin     |
| Create patient (now also returns MRN)        | `patients.create` (existing)| Active branch for `branch_id`        | owner/admin/doctor/receptionist |
| Reassign MRN (restricted)                    | `patients.reassign_mrn` (NEW) | Org (patient must be in caller org) | **administrator only**  |
| Edit patient profile (unchanged, cannot touch MRN) | `patients.edit` (existing) | Org                          | owner/admin/doctor/receptionist |
| Archive patient        | `patients.delete` (existing) | Org                                 | owner/admin/doctor/receptionist |

New permission seed (`20260724120200_patient_reassign_mrn_permission.sql`):

- `administrator` → `patients.reassign_mrn` granted
- `owner`, `doctor`, `receptionist`, `lab_staff`, any others → revoked (`is_granted = false`)

## RPC inventory

### New RPCs

| RPC                        | Permission             | Purpose                                                                     |
| -------------------------- | ---------------------- | --------------------------------------------------------------------------- |
| `reassign_patient_mrn`     | `patients.reassign_mrn` | Admin reassigns a patient's MRN; validates uniqueness; audits old/new       |

### Extended existing RPCs (payload additions only — signatures unchanged)

| RPC                  | New field in payload                                  |
| -------------------- | ---------------------------------------------------- |
| `create_patient`     | returns `mrn` alongside `patient_id`; audit `new_data_json` gains `mrn` |
| `search_patients`    | each row gains `mrn`                                 |
| `get_patient`        | response gains `mrn`                                 |
| `list_invoices`      | each row's patient sub-object gains `patient_mrn`    |
| `get_invoice_detail` | patient sub-object gains `mrn` (`patient_mrn`)       |
| `list_patient_invoices` | each row gains `patient_mrn`                       |
| `list_appointments`  | each row gains `patient_mrn`                        |

### New helper (internal)

| Function                          | Schema/Visibility          | Purpose                                            |
| --------------------------------- | -------------------------- | -------------------------------------------------- |
| `auth_internal.assign_patient_mrn` | `auth_internal`, SECURITY DEFINER, not granted | Returns `format('MRN-%s', lpad(nextval::text, 6, '0'))`. Called only by `create_patient`. Reused by a future bulk import path if/when added. |

## Audit actions (new + extension)

| Action                    | Trigger                                | `old_data_json`        | `new_data_json`                                  |
| ------------------------- | -------------------------------------- | ---------------------- | ------------------------------------------------ |
| `patient.create` (extend) | `create_patient`                       | *(none)*               | adds `mrn` to the existing payload                |
| `patient.update` (extend) | `update_patient`                       | adds `mrn` (unchanged) | adds `mrn` (unchanged) — MRN not editable here     |
| `patient.mrn_reassign` (NEW) | `reassign_patient_mrn`               | `{"mrn": "<old>"}`     | `{"mrn": "<new>"}`                                |

- `audit_log` columns reused: `user_id`, `organization_id`, `action`, `table_name='patients'`, `record_id`, `old_data_json`, `new_data_json`, `timestamp`.

## Client models (Flutter)

| Type                     | New / extended fields                          |
| ------------------------ | ---------------------------------------------- |
| `PatientListItem`        | + `mrn: String` (parsed from `mrn`/`patient_mrn`) |
| `PatientDetail`          | + `mrn: String`                                |
| `AppointmentListItem`    | + `patientMrn: String?`                        |
| `CreatePatientResult` (new DTO) | `patientId: String`, `mrn: String`      |
| `InvoiceListItem`        | already has `patientMrn` — confirm (no change) |
| `InvoiceDetail`          | already has patient `mrn` access — confirm     |

Parsing rules (in `patient_row_parsing.dart` and the corresponding invoice/appointment parsers):
- Read `row['mrn']?.toString() ?? row['patient_mrn']?.toString()` (matches existing invoice-list convention).
- Treat missing/null as `'—'` for display, but the backend guarantees `mrn` is never null on `patients`.

## Relationships (unchanged)

```text
organizations 1──* branches 1──* patients (registering branch)
patients 1──* invoices        (MRN surfaced via JOIN, not stored on invoices)
patients 1──* appointments    (MRN surfaced via JOIN)
patients 1──* visits ──* soap_notes / treatment_plans / visit_attachments
                                            │
                          MRN surfaced on patient-detail surfaces (chip);
                          visits inherit the chip from patient-detail context
```

- No stored MRN on `invoices`, `appointments`, `visits`, `soap_notes`, … — all surfaces derive the MRN from the patient join at read time, satisfying FR-008 (single refresh, no value migration).

## Validation rules summary

| Rule                                            | Enforced by                                                            |
| ----------------------------------------------- | --------------------------------------------------------------------- |
| MRN present on every patient                     | `mrn text NOT NULL` column constraint                                  |
| No duplicate MRN across the entire database      | `UNIQUE` index `patients_mrn_unique` (global, includes soft-deleted)  |
| Sequential, zero-padded, prefixed format         | `assign_patient_mrn()` generator + regex validation in reassign RPC   |
| Immutable for ordinary staff                     | `update_patient` does not accept `p_mrn`; no inline edit UI; RLS denies direct UPDATE |
| Admin-only reassignment                          | `patients.reassign_mrn` permission seed (administrator only) + `assert_permission` in RPC |
| Reassignment uniqueness excludes self            | `SELECT 1 FROM patients WHERE mrn = p_new_mrn AND id <> p_patient_id`  |
| Archived patient cannot be reassigned            | `assert_org_patient(p_allow_archived => false)` → `PATIENT_ARCHIVED`    |
| No MRN mutation while backend unreachable        | RPC-only write path; client `AppRpcInvoker` surfaces `RpcFailure`; no local write path |
| No reuse of soft-deleted MRN                     | Global unique index (not partial on `is_deleted`)                      |

## Out of scope (per spec / research)

- Bulk patient import (deferred; when added must call `assign_patient_mrn()` per row).
- Patient merge flow (deferred; must surface MRN conflict resolution consistent with `reassign_patient_mrn`).
- AI-assisted MRN generation/validation (explicitly no — deterministic DB operation).
- External MPI / national-identifier federation (explicitly out of scope).
- Cross-organization MRN uniqueness (single database = single organization cluster by deployment model; "global" here = within one database).