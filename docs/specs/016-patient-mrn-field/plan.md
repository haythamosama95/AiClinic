# Implementation Plan: Patient MRN (Medical Record Number)

**Branch**: `016-patient-mrn-field` | **Date**: 2026-07-24 | **Spec**: `docs/specs/016-patient-mrn-field/spec.md`

**Input**: Feature specification from `/docs/specs/016-patient-mrn-field/spec.md`

## Summary

Add a globally-unique, immutable Medical Record Number (MRN) to every patient, generated server-side as a sequential zero-padded prefixed string (`MRN-000001`) via a PostgreSQL sequence plus a global unique constraint as backstop. Extend `create_patient` to assign and return the MRN; add an admin-only `reassign_patient_mrn` RPC with duplicate validation and audit; surface the MRN in patients list (new column), patient details (badge/chip), invoices list + invoice details (already wired in frontend, requires backend payload), and downstream clinical surfaces (appointments list, encounter headers). No AI dependency; deterministic DB-owned generation; safe degradation when backend is unreachable (no offline/local MRN writes). Frontend (`features/patients`, `features/billing`, `features/appointments`) already anticipates `mrn`/`patient_mrn` fields — this plan delivers the backend column, sequence, RPCs, and fills the remaining Flutter surfaces.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via local Supabase stack; PL/pgSQL in `auth_internal` + `public` RPC wrappers (PostgREST invokes `public.*` SQL functions)

**Primary Dependencies**: Supabase Flutter SDK, Riverpod (`Provider`, `StateNotifierProvider`, `AsyncNotifierProvider`, `FutureProvider`), GoRouter; existing `AppRpcInvoker` / `RpcResult` / `RpcFailure`; `supabaseClientProvider`; `PermissionKeys` + `PermissionService`; shared `AppBadge`, `AppDataTable`/`TableColumn`, `AppTypography.mono`; `apply_standard_audit_triggers`; `audit_log` table; `rpc_success` / `rpc_error` helpers; existing `assert_org_patient`, `assert_permission` helpers; `invoice_number_sequences` + `assign_invoice_number` precedent for sequential ID generation

**Storage**: Extend `public.patients` with `mrn text NOT NULL`; add `public.patient_mrn_seq` PostgreSQL sequence (`CREATE SEQUENCE`) and a `UNIQUE` index on `patients(mrn)`; reuse existing `audit_log` (action `patient.mrn_reassign`); add permission seed `patients.reassign_mrn` (administrator only). No new tables, no Edge Functions, no AI storage

**Testing**: `backend/tests/patient_mrn_generation.sql` (sequence uniqueness under concurrent create), `patient_mrn_reassign.sql` (admin-only, duplicate rejection, audit row), extend `patient_management_crud.sql`; run via `run_patient_management_tests.sh`. Flutter: `frontend/test/unit/patients/patient_mrn_*_test.dart` (parsing, notifier), `frontend/test/boundary/patients/reassign_patient_mrn_boundary_test.dart`; extend `patient_list_notifer_test.dart` / `patient_detail_test.dart` / `invoice_list_item_test.dart`. Manual `quickstart.md` end-to-end

**Target Platform**: Windows desktop on clinic LAN against local Supabase (standard V1-0 deployment profile)

**Project Type**: Desktop client + Supabase PostgreSQL (migrations, RLS, RPC); no custom API server; no Edge Functions; no AI involvement

**Performance Goals**: MRN generation ≤ single PostgreSQL `nextval` + UPDATE (sub-millisecond per create); patients list with MRN column usable at 500+ patients/branch; concurrent patient creation never collides (DB-enforced); 100% duplicate-reassignment rejection before persistence

**Constraints**: Global uniqueness across ALL tenants/branches (one MRN namespace — deliberate cross-branch scope, see Complexity Tracking); immutable on the patient record for ordinary staff; admin-only reassignment via restricted flow (not inline edit); client MUST treat server duplicate-detection as authoritative — never persist locally generated/unverified MRNs; soft-deleted patients retain their MRN (never reused, never released to sequence); no AI dependency for generation/validation/display; existing tenant/branch-scoped RLS continues to govern visibility/editability of the value but NOT the uniqueness scope

**Scale/Scope**: 2-3 new migrations; 1 new RPC (`reassign_patient_mrn`) + additions to existing RPCs (`create_patient`, `search_patients`, `get_patient`, `list_invoices`, `get_invoice_detail`, `list_patient_invoices`, `list_appointments`); 1 new permission key; ~6 Flutter model-field additions; 4 surface edits (patient table column, identity chip, add-patient success display, appointment list) + confirm already-wired invoice list/hero/detail; admin reassignment UI (net-new, restricted)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope fits small-to-mid-size multi-branch clinics; explicitly rejects enterprise hospital-scale MPI federation and national-identifier integration (spec Constitution Alignment)
- [x] Simple operational model retained — no microservices, queues, Kubernetes, or custom primary backend service; all logic in PostgreSQL migrations/RPCs
- [x] Layer ownership explicit: Flutter renders column/chip/invoice/appointment surfaces + admin reassignment flow; Supabase/PostgREST exposes RPC for generation + reassignment; PostgreSQL owns sequence + unique constraint + audit; AI not involved
- [x] Protected writes via `auth_internal` RPCs (`create_patient` extended, new `reassign_patient_mrn`); uniqueness enforced by DB sequence + UNIQUE index; duplicate validation server-side; audit row on reassignment
- [x] Security authenticated, tenant/branch-scoped (RLS unchanged on `patients`), permission-gated (`patients.create`, `patients.reassign_mrn`), audited, soft-delete-preserving (MRNs never reused, soft-deleted rows keep value)
- [x] AI not used for generation/validation/display; feature degrades to manual operation when AI unavailable (it is unaffected); when backend unreachable, save is blocked with clear error (no local MRN writes per FR-012)

### Post-Design Re-Check

- [x] `mrn` column on `patients` reuses shared schema conventions (audit triggers, soft-delete); no new audit subsystem — reuses `audit_log`
- [x] Global uniqueness via PostgreSQL `SEQUENCE` + `UNIQUE` index (no retry-based collision loops, per FR-010); client treats server duplicate detection as authoritative
- [x] RLS unchanged in scope — MRN is just a column on `patients` (org-scoped read, RPC-only mutations); visibility governed by existing policies
- [x] Reassignment is admin-only RPC with duplicate check + audit (`patient.mrn_reassign` with old/new value, actor, timestamp); ordinary staff see read-only field, no inline edit
- [x] Soft-deleted patients keep MRN (UNIQUE on all rows, not partial on `is_deleted=false`); no MRN reuse ambiguity
- [x] No Edge Functions, no AI service, no custom backend service introduced
- [x] Bulk import (out of scope per assumptions) would reuse same per-row `assign_patient_mrn()` guarantee if added later

## Project Structure

### Documentation (this feature)

```text
docs/specs/016-patient-mrn-field/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── mrn-generation.md
│   └── mrn-surfaces.md
└── tasks.md             # Phase 2 — /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/supabase/migrations/
├── 20260724120000_patient_mrn_field.sql            # mrn column, sequence, unique index, backfill, create_patient/search/get/list RPC updates
├── 20260724120100_reassign_patient_mrn_rpc.sql     # auth_internal.reassign_patient_mrn + public wrapper + grant
└── 20260724120200_patient_reassign_mrn_permission.sql  # patients.reassign_mrn seed (administrator only)

backend/tests/
├── patient_mrn_generation.sql
├── patient_mrn_reassign.sql
└── run_patient_management_tests.sh                # extended

frontend/lib/features/auth/domain/
└── permission_keys.dart                           # + patientsReassignMrn = 'patients.reassign_mrn'

frontend/lib/features/patients/
├── data/patient_repository.dart                   # createPatient returns mrn; + reassignPatientMrn()
├── domain/
│   ├── patient_list_item.dart                     # + mrn
│   ├── patient_detail.dart                        # + mrn
│   └── usecases/reassign_patient_mrn.dart         # new
├── presentation/
│   ├── add_patient/add_patient_dialog.dart        # surface generated MRN on success
│   ├── providers/patient_registration_notifier.dart # return mrn from submit()
│   ├── pages/patient_detail_page.dart              # MRN AppBadge in identity card
│   ├── pages/mrn_reassignment_dialog.dart          # new (admin only)
│   └── widgets/patient_table.dart                 # MRN TableColumn

frontend/lib/features/billing/
├── domain/invoice_list_item.dart                  # already has patientMrn — confirm
└── presentation/widgets/invoice_table.dart        # already renders patientMrn — locked once backend returns it

frontend/lib/features/appointments/
├── domain/appointment_list_item.dart              # + patientMrn
└── presentation/widgets/appointment_calendar_tile.dart  # surface MRN

frontend/test/
├── unit/patients/patient_mrn_parsing_test.dart
├── unit/patients/patient_list_item_mrn_test.dart
├── unit/patients/patient_detail_mrn_test.dart
├── boundary/patients/reassign_patient_mrn_boundary_test.dart
└── integration/patients/patient_mrn_acceptance_test.dart
```

**Structure Decision**: All schema/sequence/constraint work lives in PostgreSQL migrations under `backend/supabase/migrations/` (timestamped after the latest `20260717120000`). Reassignment RPC follows the established two-layer `auth_internal.<fn>` (`SECURITY DEFINER`, permission + uniqueness check + audit) + `public.<fn>` (`SECURITY INVOKER` + `GRANT EXECUTE … TO authenticated`) pattern. Frontend mutations stay in `features/patients` (domain + presentation), surfacing in `features/patients`, `features/billing`, and `features/appointments`. Admin reassignment UI is net-new and lives in `features/patients/presentation` (a restricted dialog opened from patient detail only when `patients.reassign_mrn` is granted) — kept in the patients feature rather than `settings` because it operates on a single patient's record. No `ai/` or `functions/` directories are introduced (N/A for this feature).

## Implementation Phases (high level)

### Phase A — Backend: schema & generation

1. Migration `20260724120000_patient_mrn_field.sql`:
   - `CREATE SEQUENCE public.patient_mrn_seq START 1;`
   - `ALTER TABLE public.patients ADD COLUMN mrn text;`
   - Backfill existing rows: `UPDATE patients SET mrn = format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0')) WHERE mrn IS NULL;`
   - `ALTER TABLE public.patients ALTER COLUMN mrn SET NOT NULL;`
   - `CREATE UNIQUE INDEX patients_mrn_unique ON public.patients (mrn);` (global, not partial — soft-deleted rows keep MRN, never reused)
   - `auth_internal.assign_patient_mrn()` SECURITY DEFINER helper: `format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0'))` (atomic, no retry loops)
   - Extend `auth_internal.create_patient` to call `assign_patient_mrn()` on insert and include `mrn` in `rpc_success` payload (`patient_id` + `mrn`) and in `audit_log.new_data_json`
   - Update `search_patients` / `get_patient` SELECTs to include `mrn` in row JSON
   - Update `list_invoices` / `get_invoice_detail` / `list_patient_invoices` SELECTs to include `p.mrn AS patient_mrn` in patient sub-objects
   - Update `list_appointments` SELECT to include `p.mrn AS patient_mrn`
2. Migration `20260724120100_reassign_patient_mrn_rpc.sql`:
   - `auth_internal.reassign_patient_mrn(p_patient_id uuid, p_new_mrn text)` — `assert_permission('patients.reassign_mrn')`, `assert_org_patient`, validate non-null + format (`^MRN-\d{6,}$` or accept free-form per reconciliation, applied via shared normalizer), uniqueness check excluding self (`SELECT 1 FROM patients WHERE mrn = p_new_mrn AND id <> p_patient_id` → `MRN_EXISTS`), `UPDATE patients SET mrn = p_new_mrn`, audit `patient.mrn_reassign` (old/new in `old_data_json`/`new_data_json`)
   - `public.reassign_patient_mrn` SQL wrapper + `GRANT EXECUTE … TO authenticated`
3. Migration `20260724120200_patient_reassign_mrn_permission.sql`:
   - Seed `patients.reassign_mrn` in `roles_permissions` granted to `administrator` only; revoked for all other roles

### Phase B — Backend verification

1. `patient_mrn_generation.sql` — consecutive creates produce `MRN-000001 … MRN-00000n`, no duplicates; concurrent create (pgTAP `pg_sleep` + parallel sessions) never collides; unique index rejects manual dup insert
2. `patient_mrn_reassign.sql` — administrator succeeds; non-admin → `FORBIDDEN`; duplicate value → `MRN_EXISTS`; audit row present with old/new; archived patient → `PATIENT_ARCHIVED`
3. Extend `patient_management_crud.sql` — `create_patient` returns `mrn`; `search_patients`/`get_patient` include `mrn`; invoice/appointment RPCs include `patient_mrn`
4. Update `dev_reset_clinic_installation.sql` to delete patients before resetting sequence (`setval('public.patient_mrn_seq', 1, false)`) so dev reset reproduces `MRN-000001`

### Phase C — Flutter patients models & repository

1. Extend `PatientListItem` and `PatientDetail` with `mrn` field; extend row-parsing helpers (`patient_row_parsing.dart`) to read `mrn`/`patient_mrn`
2. `PatientRepository.createPatient` returns `CreatePatientResult ({ patientId, mrn })` instead of bare id; reads `data['mrn']` / `data['patient_id']`
3. Add `reassignPatientMrn(patientId, newMrn)` to repository + a `ReassignPatientMrn` usecase
4. Add `patientsReassignMrn = 'patients.reassign_mrn'` to `PermissionKeys`; extend `PermissionService` (`canReassignPatientMrn`)

### Phase D — Flutter surfaces

1. `PatientTable`: add `TableColumn(id: 'mrn', header: 'MRN', accessor: row => Text(row.mrn ?? '—')` with monospace typography; place as the first column for fast scanning
2. `PatientDetailPage._PatientIdentityCard`: add an MRN `AppBadge` (prominent `BadgeColor` — e.g. primary/teal) inside the identity `Wrap`, near the patient name
3. `AddPatientDialog` + `patientRegistrationProvider.submit()`: surface the generated MRN immediately on success (toast with the MRN value AND carry it onto the navigated detail page so the new chip confirms); spec FR-002 / US-1
4. Confirm `InvoiceLedgerTable._PatientCell` already renders `item.patientMrn ?? '—'` — becomes populated automatically once `list_invoices` returns `patient_mrn` (no UI change required, only verify)
5. Confirm `InvoiceHeroCard` / `InvoiceLinkCard` already accept and render `mrn:` — becomes populated once `get_invoice_detail` returns `mrn`
6. `appointment_calendar_tile.dart` / appointment list: surface `patientMrn` next to patient name; extend `AppointmentListItem` with `patientMrn`

### Phase E — Admin reassignment flow

1. `MrnReassignmentDialog` — restricted confirmation dialog with new-MRN input; opened from patient detail only when `canReassignPatientMrn`; calls `reassignPatientMrn` usecase
2. On `MRN_EXISTS`, show clear duplicate error (per US-2 acceptance 1); on stale/failure, surface standard error mapping
3. On success, refresh patient detail (chip updates to new MRN); list/invoices/appointments reflect on next refresh (FR-008)

### Phase F — Tests & docs

1. Flutter unit tests: `patient_mrn_parsing_test.dart`, `patient_list_item_mrn_test.dart`, `patient_detail_mrn_test.dart`, invoice/appointment MRN parsing extensions
2. Boundary test: `reassign_patient_mrn_boundary_test.dart` (admin OK, non-admin `FORBIDDEN`, duplicate rejection)
3. Integration test: `patient_mrn_acceptance_test.dart` (create → MRN displayed; reassign → surfaces propagate)
4. Update `quickstart.md` verification steps

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Global MRN uniqueness scope (spans ALL tenants/branches, not per-org) | Spec Clarification session locks a single shared MRN namespace across the entire database so any patient is unambiguously identifiable across branches; reassignment uniqueness check and the unique index must therefore be global, not `organization_id`-partitioned | Per-organization scoping (matching `national_id` and the org-scoped tenant model) is rejected because it would allow the same MRN string to exist under different orgs, defeating the cross-branch unambiguous identification goal and conflicting with the explicit clarification. This is a deliberate, spec-mandated data-boundary deviation, not an architectural one — it stays DB-owned (PostgreSQL SEQUENCE + UNIQUE index), preserves RLS for visibility/editability, and does not introduce any prohibited infrastructure. |

## Phase 0 & Phase 1 Artifacts

| Artifact                                          | Status               |
| ------------------------------------------------- | -------------------- |
| `research.md`                                     | Complete             |
| `data-model.md`                                   | Complete             |
| `contracts/*`                                      | Complete (2 files)   |
| `quickstart.md`                                   | Complete             |
| Agent context (`AGENTS.md` SPECKIT markers)        | Updated to this plan |

**Next command**: `/speckit-tasks` to generate `tasks.md`.