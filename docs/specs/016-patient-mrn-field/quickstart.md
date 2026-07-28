# Quickstart: Patient MRN (Medical Record Number)

Implementation and verification for **016-patient-mrn-field**. Extends **V1-3** (`docs/specs/004-patient-management`) and **V1-5** (`docs/specs/007-billing`) payloads with the patient MRN.

## 1. Apply database migrations

From the repository root with the local Supabase stack running (`backend/local`):

```bash
cd backend
supabase migration up
# or: supabase db reset  (re-runs all migrations from scratch — preferred for clean verification)
```

Expected new migrations (timestamped after `20260717120000`):

- `backend/supabase/migrations/20260724120000_patient_mrn_field.sql` — `mrn` column, `patient_mrn_seq` sequence, backfill, `NOT NULL`, global `UNIQUE` index, `assign_patient_mrn()` helper, and extensions to `create_patient` / `search_patients` / `get_patient` / `list_invoices` / `get_invoice_detail` / `list_patient_invoices` / `list_appointments` payloads.
- `backend/supabase/migrations/20260724120100_reassign_patient_mrn_rpc.sql` — `auth_internal.reassign_patient_mrn` + `public.reassign_patient_mrn` wrapper + `GRANT EXECUTE … TO authenticated`.
- `backend/supabase/migrations/20260724120200_patient_reassign_mrn_permission.sql` — seeds `patients.reassign_mrn` (administrator only; revoked for all other roles).

After migration, confirm in `psql`:

```sql
\d public.patients                  -- the new `mrn` column is present, NOT NULL
\di public.patients_mrn_unique      -- unique index exists
SELECT * FROM public.patient_mrn_seq;  -- sequence exists, current value = # of existing patients
```

## 2. Run backend verification

```bash
./backend/tests/run_patient_management_tests.sh
```

Or run individual SQL suites:

```bash
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/patient_mrn_generation.sql
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/patient_mrn_reassign.sql
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/patient_management_crud.sql   # extended
```

**New scenarios** (map to spec user stories):

- `create_patient` returns `MRN-000001` for the first patient on a fresh DB; subsequent creates return incrementing values (`MRN-000002`, …)
- Concurrency: two parallel `create_patient` calls produce two distinct MRNs (no collision); the unique index blocks any manual duplicate insert
- `search_patients` rows include `mrn`; `get_patient` includes `mrn`
- `list_invoices`, `get_invoice_detail`, `list_patient_invoices` rows include `patient_mrn`
- `list_appointments` rows include `patient_mrn`
- `reassign_patient_mrn` as administrator succeeds; audit row present with `old.mrn` / `new.mrn`
- Non-administrator → `FORBIDDEN`
- Duplicate target value → `MRN_EXISTS` (target row unchanged)
- Archived patient → `PATIENT_ARCHIVED`
- Dev reset reproduces `MRN-000001` for the first patient after `dev_reset_clinic_installation.sql`

## 3. Run the Flutter client

```bash
cd frontend
flutter pub get
flutter run -d windows
```

1. Sign in as a **receptionist** (or any role with `patients.create`).
2. Open **Patients** from the shell navigation.
3. Confirm the new **MRN** column appears first in the table, populated for every patient, in monospace.
4. **Register patient** with a minimal full name → on save, a toast shows `MRN-NNNNNN`; navigation lands on the detail page where the MRN chip is present and matches the toast.
5. Open an existing patient's **detail** → the MRN badge/chip appears in the identity card (first chip, distinct color / monospace).
6. Open **Invoices** → the patient's MRN appears under each patient name (was `—` before the backend change).
7. Open an **invoice detail** → the MRN appears in the hero card subtitle and the patient link card.
8. Open **Appointments** → the MRN appears next to the patient name on each appointment tile/row.
9. **Re-sign in as an administrator**: on a patient's detail page, an **Reassign MRN** action is visible (entry point exists).
   - Try reassigning to a value already used by another patient → the dialog shows `Another patient already uses this MRN.` inline; the row is unchanged.
   - Reassign to a fresh value (`MRN-000999`) → on save, the chip updates on the same screen; refresh the invoices list → the invoice row now shows the new MRN.
10. **Re-sign in as a non-administrator** (e.g., doctor): on any patient detail page, the **Reassign MRN** action is hidden; calling `reassign_patient_mrn` directly (via boundary test) returns `FORBIDDEN`.
11. With the backend stopped, attempt **Register patient** → the form surfaces a connectivity error and **does not** save a patient with a fabricated MRN (FR-012).

## 4. Regression checks (V1-3 / V1-5)

- `patients` RLS still scopes reads to caller org; MRN visibility follows existing org policy (no new read permission).
- Existing `patients.create/edit/delete` flows unchanged except for the new returned `mrn` field.
- Existing `update_patient` still cannot mutate `mrn` (no `p_mrn` parameter) — confirming immutability for ordinary staff.
- Invoice and appointment flows unchanged except for the additional `patient_mrn` payload field.
- Soft delete (archive) still leaves the MRN retained on the row; the value is not reused for any subsequent create (verify: archive `MRN-000001`, create a new patient → it receives `MRN-00000N`, never `MRN-000001`).

## 5. Automated Flutter tests

```bash
cd frontend
flutter test test/unit/patients/patient_mrn_parsing_test.dart
flutter test test/unit/patients/patient_list_item_mrn_test.dart
flutter test test/unit/patients/patient_detail_mrn_test.dart
flutter test test/boundary/patients/reassign_patient_mrn_boundary_test.dart
flutter test test/integration/patients/patient_mrn_acceptance_test.dart
```

Boundary tests require a running Supabase stack (set the boundary-integration env flag as documented in `frontend/lib/core/config/supabase_config.dart`).

## 6. Operator documentation

Update the desk-staff notes in `docs/architecture/12-roadmap-phases.md` (or the equivalent desk-staff quick reference) with:

**Desk staff notes (verified 2026-07-24)**

- Every patient now has a **Medical Record Number (MRN)** in the form `MRN-NNNNNN`, generated automatically when the patient is registered. You cannot edit it on the patient record.
- The **MRN** appears as the **first column** in the patients list so you can scan and locate a patient quickly. On a patient's detail page, it appears as a prominent chip near the name.
- When you register a patient, a toast confirms the new MRN immediately; the detail page also shows it.
- The MRN appears on **invoices** (list and detail) and **appointments** so billing and clinical staff can match records to the patient without opening the patient record.
- **Reassigning an MRN** is a restricted action available only to **administrators**. From a patient's detail page, an administrator can open the reassignment dialog, enter a new value, and the system rejects duplicates. Every reassignment is recorded in the audit log with the old and new values, who did it, and when.
- MRNs are **never reused**, even when a patient is archived.
- If the system cannot reach the database, **you cannot register a patient** — the form shows an error rather than save a patient with a locally generated MRN. Retry once connectivity returns.

**Automated verification**

- Backend: `./backend/tests/run_patient_management_tests.sh` from the repo root (requires local Supabase on port 54322).
- Flutter: `cd frontend && flutter test test/unit/patients/ test/boundary/patients/ test/integration/patients/`.