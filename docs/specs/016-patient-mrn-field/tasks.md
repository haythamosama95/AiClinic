---

description: "Task list for Patient MRN (Medical Record Number) feature implementation"
---

# Tasks: Patient MRN (Medical Record Number)

**Input**: Design documents from `/docs/specs/016-patient-mrn-field/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/mrn-generation.md, contracts/mrn-surfaces.md, quickstart.md

**Tests**: Backend tests ARE generated — MRN uniqueness, RLS scope, admin-only reassignment, and auditability are constitution-sensitive (Backend Authority III, Secure Operations IV). Flutter unit/boundary/integration tests are generated to lock parsing contracts and the reassignment permission gate.

**Organization**: Tasks are grouped by user story (US1…US6) in priority order. User stories can be implemented independently after the Foundational phase completes; each delivers an independently testable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Includes exact file paths in descriptions

## Path Conventions

- **Supabase backend**: `backend/supabase/migrations/`, `backend/supabase/seed/`, `backend/tests/`
- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- No Edge Functions / custom backend service / AI service for this feature (N/A) — see `plan.md` Project Structure

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm prerequisites are in place; no new scaffolding required (additive feature on existing repo)

- [X] T001 Verify local Supabase stack runs and latest migration applied (`backend/local`, `supabase status`); confirm `backend/supabase/migrations/20260717120000_billing_currency.sql` is the current highest timestamp before adding new migrations
- [X] T002 [P] Confirm Flutter_repo `flutter pub get` succeeds and existing patient/invoice/appointment feature packages compile (`cd frontend && flutter analyze` clean) before changes

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core schema + sequence + unique index + backfill that EVERY user story depends on. MUST be complete before any user story work begins.

**CRITICAL**: No user story work can begin until this phase is complete. The `mrn` column, sequence, and global unique index must exist; `create_patient` must generate and return the MRN (US1 backend) so subsequent stories can read it.

- [X] T003 [P] Create migration `backend/supabase/migrations/20260724120000_patient_mrn_field.sql` Part A (schema): `CREATE SEQUENCE public.patient_mrn_seq AS bigint START 1 INCREMENT 1 NO CYCLE;`, `ALTER TABLE public.patients ADD COLUMN mrn text;`, backfill `UPDATE public.patients SET mrn = format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0')) WHERE mrn IS NULL;`, `ALTER TABLE public.patients ALTER COLUMN mrn SET NOT NULL;`, `CREATE UNIQUE INDEX patients_mrn_unique ON public.patients (mrn);` (global — NOT partial on `is_deleted`)
- [X] T004 [P] Create internal helper `auth_internal.assign_patient_mrn()` in the same migration `backend/supabase/migrations/20260724120000_patient_mrn_field.sql` Part B: `SECURITY DEFINER`, `SET search_path = public`, returns `format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0'))`; `REVOKE ALL ON FUNCTION auth_internal.assign_patient_mrn() FROM PUBLIC, authenticated, anon;` (internal only — callable only by other `auth_internal` RPCs)
- [X] T005 Extend `auth_internal.create_patient` in `backend/supabase/migrations/20260724120000_patient_mrn_field.sql` Part C: call `assign_patient_mrn()` inside the same transaction as the insert to set `mrn`; return `mrn` in `rpc_success(jsonb_build_object('patient_id', …, 'mrn', v_mrn))`; include `mrn` in the existing `patient.create` audit row's `new_data_json` (depends on T003, T004)
- [X] T006 [P] Update `backend/tests/dev_reset_clinic_installation.sql` to call `SELECT setval('public.patient_mrn_seq', 1, false);` after the existing patients deletion, so a fresh dev install reproduces `MRN-000001` for the first created patient
- [X] T007 [P] Create backend test `backend/tests/patient_mrn_generation.sql` testing MRN generation constitution invariants: consecutive `create_patient` calls return `MRN-000001`, `MRN-000002`, …; manual `INSERT INTO patients (mrn) VALUES ('MRN-000001')` is rejected by the unique index; archived patient's MRN is not reused (archive then create → next MRN advances past the archived value); wire into `backend/tests/run_patient_management_tests.sh`

**Checkpoint**: `mrn` column, sequence, global unique index, generator helper, and `create_patient` returning MRN all ready. Foundation solid — user story implementation can now begin. (Note: US1's frontend display layers on top of T005's payload.)

---

## Phase 3: User Story 1 — Auto-generate unique MRN when adding a patient (Priority: P1) MVP

**Goal**: A staff member creates a patient; the system generates a guaranteed-unique MRN and displays it immediately. Backend foundation already delivered in Phase 2 (T003–T005).

**Independent Test**: Create one new patient via the Add Patient form and verify a unique MRN is generated, displayed to the user immediately (toast + detail page chip-after-navigation), and persists after reload — no other user story needs to be implemented to validate this (US4's chip is needed for the "persists on detail" portion, but the toast + returned MRN alone proves generation).

### Tests for User Story 1

- [X] T008 [P] [US1] Extend `backend/tests/patient_mrn_generation.sql` (or add `backend/tests/patient_mrn_create_payload.sql`) to assert `create_patient` returned payload includes a non-null `mrn` matching `^MRN-\d{6,}$` AND that the audit row for `patient.create` contains that `mrn` in `new_data_json`
- [X] T009 [P] [US1] Create Flutter unit test `frontend/test/unit/patients/patient_repository_create_mrn_test.dart` asserting `PatientRepository.createPatient` returns a `CreatePatientResult` whose `mrn` equals the mocked RPC payload's `mrn`/`patient_id`; follow the `patient_rpc_test_client.dart` mock pattern

### Implementation for User Story 1

- [X] T010 [US1] Add `CreatePatientResult` DTO in `frontend/lib/features/patients/domain/create_patient_result.dart` with fields `patientId: String`, `mrn: String`, `fromJson`/`copyWith`/`==`/`hashCode` conventions matching other domain DTOs (depends on T005 backend payload)
- [X] T011 [US1] Extend `PatientRepository.createPatient` in `frontend/lib/features/patients/data/patient_repository.dart` to return `CreatePatientResult` instead of bare `String` patient id; read `result.data?['patient_id']` and `result.data?['mrn']`; preserve existing `migrationHint` and `rpcLogDomain`
- [X] T012 [US1] Extend `CreatePatient` usecase and `patientRegistrationProvider.submit()` in `frontend/lib/features/patients/presentation/providers/patient_registration_notifier.dart` to return `CreatePatientResult` (carrying `mrn`) up to the dialog
- [X] T013 [US1] Surface the generated MRN on success in `frontend/lib/features/patients/presentation/add_patient/add_patient_dialog.dart`: on successful submit display an `appToast` with the generated MRN (e.g., `Patient created — MRN MRN-000042`) BEFORE navigating to the patient detail page; on `RpcFailure`/connectivity, surface the existing error message and DO NOT fabricate an MRN (FR-012)
- [X] T014 [US1] Verify degraded behavior: with backend unreachable, confirm the Add Patient form surfaces a clear connectivity/uniqueness error and does not save a patient with an unverified MRN (manual verification + assert in `patient_repository_create_mrn_test.dart` that a failure result throws/not returns an MRN)

**Checkpoint**: User Story 1 fully functional — staff create a patient and receive a unique MRN immediately. The MRN column exists on the table (T003), but the patients list does NOT yet display it (that's US3). The patient detail chip is US4. Independent test passes.

---

## Phase 4: User Story 3 — View MRN in the patients list (Priority: P1)

**Goal**: Each row in the patients list shows the patient's MRN in a dedicated first column.

**Independent Test**: Open the patients list with at least one patient present and verify the MRN column is present, populated, monospace, and matches each patient's stored MRN exactly.

### Tests for User Story 3

- [X] T015 [P] [US3] Add pgTAP assertions to `backend/tests/patient_management_crud.sql` (or new `backend/tests/search_patients_mrn_test.sql`) that `search_patients` row objects include a non-null `mrn` matching `^MRN-\d{6,}$` for every returned patient; wire into `run_patient_management_tests.sh`
- [X] T016 [P] [US3] Create Flutter unit test `frontend/test/unit/patients/patient_list_item_mrn_test.dart` asserting `PatientListItem.fromJson` parses `mrn` from `row['mrn']` (with fallback to `row['patient_mrn']`); add a list-notifier test fixture row containing `mrn` and confirm it flows into `PatientListUiState` rows
- [X] T017 [P] [US3] Create Flutter widget test `frontend/test/widget/patients/patient_table_mrn_column_test.dart` asserting the `MRN` header is rendered as the first column and the cell text equals the row's `mrn`

### Implementation for User Story 3

- [X] T018 [P] [US3] Extend `search_patients` RPC SELECT in `backend/supabase/migrations/20260724121000_search_patients_include_mrn.sql` to include `mrn` in each row's `jsonb_build_object(...)` output (add the field alongside the existing `full_name`, `phone`, `date_of_birth`, `branch_id`, `branch_name`); run the migration and confirm via psql
- [X] T019 [P] [US3] Add `mrn: String?` field to `PatientListItem` in `frontend/lib/features/patients/domain/patient_list_item.dart` and parse it in the row parser; add a corresponding case to `frontend/lib/features/patients/domain/patient_row_parsing.dart` (key `mrn`, fallback `patient_mrn`)
- [X] T020 [US3] Add a `TableColumn(id: 'mrn', header: 'MRN', accessor: (row) => Text(row.mrn ?? '—', style: AppTypography.mono))` as the FIRST column in `frontend/lib/features/patients/presentation/widgets/patient_table.dart` (before the patient name column); use an explicit width (~140) so the column doesn't collapse; shift existing columns right by one

**Checkpoint**: User Stories 1 AND 3 both work independently. Staff can create a patient (US1) AND see MRNs in the list (US3) without needing other stories.

---

## Phase 5: User Story 4 — View MRN as a badge/chip in patient details (Priority: P2)

**Goal**: A patient's details window shows the MRN as a prominent badge/chip near the identifying information.

**Independent Test**: Open any patient's details window and verify the MRN appears as a distinct badge/chip element showing the correct value, prominently colored, adjacent to the name.

### Tests for User Story 4

- [X] T021 [P] [US4] Add pgTAP assertions (extend `backend/tests/patient_management_crud.sql` or new `backend/tests/get_patient_mrn_test.sql`) that `get_patient` response includes a non-null `mrn` matching the patient's stored value; include in `run_patient_management_tests.sh`
- [X] T022 [P] [US4] Create Flutter unit test `frontend/test/unit/patients/patient_detail_mrn_test.dart` asserting `PatientDetail.fromJson` parses `mrn` (key `mrn`, fallback `patient_mrn`) and exposes it as a non-null field
- [X] T023 [P] [US4] Create Flutter widget test `frontend/test/widget/patients/patient_identity_mrn_chip_test.dart` asserting `_PatientIdentityCard` renders an `AppBadge` whose text equals the patient's `mrn`, placed first in the identity `Wrap`

### Implementation for User Story 4

- [X] T024 [P] [US4] Extend `get_patient` RPC SELECT in `backend/supabase/migrations/20260724122000_get_patient_include_mrn.sql` to include `mrn` in the returned detail object (alongside existing profile fields)
- [X] T025 [P] [US4] Add `mrn: String?` field to `PatientDetail` in `frontend/lib/features/patients/domain/patient_detail.dart` and parse it from the RPC payload
- [X] T026 [US4] Add an MRN `AppBadge` to `_PatientIdentityCard` in `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`: place it FIRST in the existing identity `Wrap` of `AppBadge`s, use `AppBadge(size: BadgeSize.md, variant: BadgeVariant.soft, color: <distinct identifier color, e.g., BadgeColor.primary/teal>, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(identity_icon, size: 14), SizedBox(width:4), Text(patient.mrn, style: AppTypography.mono)]))`; ensure the value matches `patient.mrn` exactly (US-4 acceptance 2)

**Checkpoint**: User Story 4 delivers the durable per-patient MRN surface. Combined with US1, the Add-Patient success flow now lands on a detail page that confirms the MRN visibly.

---

## Phase 6: User Story 2 — Restricted MRN reassignment with duplicate validation (Priority: P2)

**Goal**: An administrator reassigns a patient's MRN via a restricted flow (not inline edit) with server-side duplicate validation and a full audit record; ordinary staff cannot access the flow.

**Independent Test**: Via the restricted admin flow, attempt to reassign an MRN to a value already used by another patient → confirm rejection (`MRN_EXISTS`); then reassign to a fresh value → confirm persistence and audit-row creation; confirm a non-administrator cannot open the flow and the inline field stays read-only — testable without the UI for invoices or lists.

### Tests for User Story 2

- [ ] T027 [P] [US2] Create backend test `backend/tests/patient_mrn_reassign.sql`: administrator succeeds; non-administrator → `FORBIDDEN`; duplicate target → `MRN_EXISTS` (target row unchanged); malformed value → `INVALID_INPUT`; same-as-current → `INVALID_INPUT`; archived patient → `PATIENT_ARCHIVED`; audit row present with `action='patient.mrn_reassign'`, correct `old_data_json.mrn`/`new_data_json.mrn`, `user_id`, `organization_id`, `timestamp` populated; wire into `run_patient_management_tests.sh`
- [ ] T028 [P] [US2] Create Flutter boundary test `frontend/test/boundary/patients/reassign_patient_mrn_boundary_test.dart`: admin → success; non-admin → `FORBIDDEN`; duplicate → `MRN_EXISTS`; reuse the `patient_rpc_test_client.dart` pattern; gate by the boundary-integration env flag

### Implementation for User Story 2

- [ ] T029 [P] [US2] Create migration `backend/supabase/migrations/20260724120100_reassign_patient_mrn_rpc.sql`: `auth_internal.reassign_patient_mrn(p_patient_id uuid, p_new_mrn text) RETURNS public.rpc_result`, `SECURITY DEFINER`, `SET search_path = public`, `assert_permission('patients.reassign_mrn')`, `assert_org_patient(p_patient_id, false)`, normalize `upper(trim(p_new_mrn))`, validate `^MRN-\d{6,}$` → `INVALID_INPUT`, reject same-as-current → `INVALID_INPUT`, uniqueness check `SELECT 1 FROM public.patients WHERE mrn = p_new_mrn AND id <> p_patient_id` → `rpc_error('MRN_EXISTS', 'Another patient already uses this MRN.', jsonb_build_object('conflicting_mrn', p_new_mrn))`, `UPDATE patients SET mrn = p_new_mrn, updated_at = now(), updated_by = auth.uid() WHERE id = p_patient_id`, insert `audit_log` row (`action='patient.mrn_reassign'`, `old_data_json={'mrn': old}`, `new_data_json={'mrn': new}`), return `rpc_success(jsonb_build_object('patient_id', p_patient_id, 'mrn', p_new_mrn))`
- [ ] T030 [P] [US2] Add the thin `public.reassign_patient_mrn(p_patient_id uuid, p_new_mrn text)` SQL wrapper in the same migration: `LANGUAGE sql`, `SECURITY INVOKER`, `SET search_path = public, auth_internal`, `SELECT auth_internal.reassign_patient_mrn(p_patient_id, p_new_mrn);`, then `GRANT EXECUTE ON FUNCTION public.reassign_patient_mrn(uuid, text) TO authenticated;`
- [ ] T031 [P] [US2] Create migration `backend/supabase/migrations/20260724120200_patient_reassign_mrn_permission.sql` seeding `patients.reassign_mrn` in `roles_permissions`: granted to `administrator` only; `is_granted = false` (or revoke row) for `owner`, `doctor`, `receptionist`, `lab_staff`, and any other existing roles; verify via `SELECT role, permission_key, is_granted FROM public.roles_permissions WHERE permission_key = 'patients.reassign_mrn';`
- [ ] T032 [P] [US2] Add `static const patientsReassignMrn = 'patients.reassign_mrn';` to `frontend/lib/features/auth/domain/permission_keys.dart`; add `canReassignPatientMrn` helper to `frontend/lib/core/auth/permission_service.dart` using the established `PermissionService` helper pattern
- [ ] T033 [P] [US2] Add `reassignPatientMrn({required String patientId, required String newMrn})` method to `PatientRepository` in `frontend/lib/features/patients/data/patient_repository.dart`: invoke `reassign_patient_mrn` RPC via `AppRpcInvoker.invokeRpc`, read `mrn` from `data`; set `migrationHint = '20260724120100_reassign_patient_mrn_rpc.sql'`, `rpcLogDomain = 'patients'`; throw `RpcFailure` on non-success; add a `ReassignPatientMrn` usecase in `frontend/lib/features/patients/domain/usecases/reassign_patient_mrn.dart`
- [ ] T034 [US2] Create dialog `frontend/lib/features/patients/presentation/pages/mrn_reassignment_dialog.dart`: confirmation-style dialog with one MRN input (pre-filled with current value, selected for easy overwrite), format hint `MRN-NNNNNN` under the field, Save disabled while empty or unchanged; handle `MRN_EXISTS` (inline error below field, keep dialog open), `INVALID_INPUT` (show format hint as inline error), `PATIENT_ARCHIVED` / `FORBIDDEN` (close dialog + toast); on success close dialog + toast confirmation + invalidate `patientDetailProvider`
- [ ] T035 [US2] Open the dialog from `PatientDetailPage` actions in `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`: render the action ONLY when `canReassignPatientMrn` is true; on success refresh detail so the identity chip (from US4) updates to the new MRN on the same screen (depends on T026 from US4 for the chip to exist)
- [ ] T036 [US2] Verify layer ownership: confirm `update_patient` still does NOT accept a `p_mrn` parameter (defense-in-depth) — no inline MRN edit affordance exists in the UI for any role other than the entry point added in T035 (manual review)

**Checkpoint**: User Story 2 fully functional alongside US1/US3/US4. Admins can reassign MRNs; ordinary staff cannot.

---

## Phase 7: User Story 5 — Reflect MRN in invoices list and invoice details (Priority: P2)

**Goal**: The invoices list shows the responsible patient's MRN in a dedicated column; each invoice's details page shows the MRN alongside patient identifiers. (Frontend already anticipates the field — this story mainly delivers the backend payload.)

**Independent Test**: Open the invoices list and any invoice's details page where the patient has an MRN; verify the MRN displays correctly in both places. Most directly testable once US1 is complete (patients exist with MRNs).

### Tests for User Story 5

- [ ] T037 [P] [US5] Add pgTAP assertions (extend `backend/tests/patient_management_crud.sql` or new `backend/tests/invoices_patient_mrn_payload_test.sql`) that `list_invoices`, `get_invoice_detail`, and `list_patient_invoices` row objects include `patient_mrn` (`mrn` alias on `get_invoice_detail` patient sub-object) for a patient with a known MRN; include in `run_patient_management_tests.sh`
- [ ] T038 [P] [US5] Create Flutter unit test `frontend/test/unit/billing/invoice_list_item_mrn_payload_test.dart` (and extend `invoice_detail_test.dart` if present) confirming the existing `InvoiceListItem.fromJson`/`InvoiceDetail.fromJson` parsers continue to resolve `patient_mrn` from the new payload (`row['patient_mrn'] ?? row['mrn']` — already implemented) and populate `InvoiceListItem.patientMrn`; helpers in `frontend/test/helpers/`

### Implementation for User Story 5

- [ ] T039 [P] [US5] Extend `list_invoices` RPC SELECT in `backend/supabase/migrations/20260724123000_list_invoices_include_mrn.sql` to include `p.mrn AS patient_mrn` on the patient join and add `'patient_mrn', sub_or_p.patient_mrn` to the row's `jsonb_build_object(...)` (file: derived from `20260713130000_list_invoices_include_payments.sql`)
- [ ] T040 [P] [US5] Extend `get_invoice_detail` RPC SELECT in the same migration `20260724123000_list_invoices_include_mrn.sql` to include both `mrn` and `patient_mrn` in the patient sub-object so the existing frontend parser (`patient['mrn'] ?? patient['patient_mrn']`) resolves unmodified
- [ ] T041 [P] [US5] Extend `list_patient_invoices` RPC SELECT in the same migration `20260724123000_list_invoices_include_mrn.sql` to include `patient_mrn` per row
- [ ] T042 [US5] Verify (no code change expected) `frontend/lib/features/billing/presentation/widgets/invoice_table.dart._PatientCell` already renders `item.patientMrn ?? '—'`; confirm cells now show real MRNs instead of `—` (manual + extend the widget/contract test to assert non-`—` once payload is present if one exists)
- [ ] T043 [US5] Verify (no code change expected) `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_hero_card.dart` (` · $mrnDisplay`) and `invoice_link_card.dart` (subtitle `$patientMrn · $patientPhone`) populate once `get_invoice_detail` returns `mrn`; manual verification + extend invoice detail widget tests if present (depends on T040)

**Checkpoint**: User Story 5 delivered. With US1 done, invoice surfaces show patient MRNs. FR-008 propagation confirmed for invoices after reassignment (next refresh shows new MRN — manual verification in T036's refresh path).

---

## Phase 8: User Story 6 — Surface MRN in additional clinical/operational contexts (Priority: P3)

**Goal**: Appointments list/entries (and detail) show the patient's MRN next to the patient name. Visits/encounters inherit the MRN chip from the patient-detail context (US4). Printed/exported reports are deferred (no renderer exists in codebase).

**Independent Test**: Open an appointment (or appointment list entry) for a patient with an MRN and verify the MRN displays alongside the patient name.

### Tests for User Story 6

- [ ] T044 [P] [US6] Add pgTAP assertions (extend relevant appointments test or new `backend/tests/appointments_patient_mrn_payload_test.sql`) that `list_appointments` row objects include `patient_mrn` for each appointment tied to a patient with a known MRN
- [ ] T045 [P] [US6] Create Flutter unit test `frontend/test/unit/appointments/appointment_list_item_mrn_test.dart` asserting `AppointmentListItem.fromJson` parses `patientMrn` from `row['patient_mrn']` (fallback `row['mrn']`) and the field is exposed

### Implementation for User Story 6

- [ ] T046 [P] [US6] Extend `list_appointments` RPC SELECT in `backend/supabase/migrations/20260724124000_list_appointments_include_mrn.sql` to include `p.mrn AS patient_mrn` from the JOIN to `public.patients` and add `'patient_mrn', p.patient_mrn` to the row `jsonb_build_object(...)`
- [ ] T047 [P] [US6] Add `patientMrn: String?` field to `AppointmentListItem` in `frontend/lib/features/appointments/domain/appointment_list_item.dart`, parsing `row['patient_mrn']` with fallback `row['mrn']`
- [ ] T048 [US6] Surface `patientMrn` next to the patient name in `frontend/lib/features/appointments/presentation/widgets/appointment_calendar_tile.dart` (and the appointment list row widget if separate): render `"$patientMrn · $patientName"` when MRN present, fall back to `patientName` only when null (avoid clutter); use `AppTypography.mono` for the MRN portion

**Checkpoint**: All user stories complete. Appointments now show MRNs; visits/encounters inherit the patient-detail chip (US4).

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Verification, docs, regression, and constitution compliance across all stories.

- [ ] T049 [P] Run full backend test suite `./backend/tests/run_patient_management_tests.sh` (and any broader `run_all_backend_tests.sh`) — all green; explicitly re-verify cross-org denial still holds (MRN visibility follows existing `patients` RLS, no new read permission)
- [ ] T050 [P] Run Flutter tests `cd frontend && flutter test test/unit/patients/ test/boundary/patients/ test/integration/patients/ test/unit/billing/ test/unit/appointments/` — all green
- [ ] T051 [P] Run `flutter analyze` and `dart format` across touched files in `frontend/lib/features/patients/`, `frontend/lib/features/billing/`, `frontend/lib/features/appointments/`, `frontend/lib/core/auth/` — clean
- [ ] T052 [P] Create/update desktop integration test `frontend/test/integration/patients/patient_mrn_acceptance_test.dart` covering the end-to-end journey: create patient → toast shows MRN → list shows MRN column → detail shows chip → invoice list shows MRN (boundary-gated)
- [ ] T053 [P] Update operator/quickstart docs: confirm `docs/specs/016-patient-mrn-field/quickstart.md` steps still pass; add desk-staff notes to the established desk quick-reference (e.g., `docs/architecture/12-roadmap-phases.md`) per the quickstart "Operator documentation" section
- [ ] T054 [P] Run `quickstart.md` validation end-to-end on local stack (migrate → backend tests → Flutter run → manual scenarios 1–11)
- [ ] T055 Constitution compliance review for final architecture and operations: verify (a) global uniqueness still DB-owned (sequence + unique index, no retry loops), (b) RLS unchanged on `patients`, (c) reassignment admin-only + audited, (d) `update_patient` still has no `p_mrn` parameter (immutability), (e) no AI dependency introduced, (f) soft-deleted MRNs not reused (manual archive+create regression), (g) safe degradation — backend unreachable blocks MRN writes (no local fabrication)
- [ ] T056 Re-confirm `AGENTS.md` SPECKIT markers still point at `docs/specs/016-patient-mrn-field/plan.md`; ensure no stray JSDoc/docstring mentions of "MRN" contradict the spec invariants

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately (verification only, additive feature)
- **Foundational (Phase 2)**: Depends on Setup; BLOCKS all user stories (T003 → T004 → T005 within the file; T006/T007 parallel)
- **User Stories (Phase 3–8)**: All depend on Foundational completion
  - US1 (Phase 3): depends only on Foundational (T005 returns MRN; frontend layers on top)
  - US3 (Phase 4): depends on Foundational (column exists); independent of US1 (no patient creation needed to display the column)
  - US4 (Phase 5): depends on Foundational (column exists); independent of US1/US3
  - US2 (Phase 6): depends on Foundational (column/audit exist); T035's refresh UX optionally chains onto US4's chip (T026) but the RPC/permission/usecase tasks (T029–T033) are independent
  - US5 (Phase 7): depends on Foundational; primary backend work (T039–T041) independent; frontend already wired
  - US6 (Phase 8): depends on Foundational; independent of other stories
- **Polish (Phase 9)**: Depends on all desired user stories being complete; T052 integration test spans US1+US3+US4+US5

### User Story Dependencies

- **US1 (P1) MVP**: Can start after Foundational — no dependencies on other stories. (Its frontend portion T010–T013 depends on T005 from Phase 2.)
- **US3 (P1)**: Can start in parallel with US1 after Foundational — no shared files (backend: `search_patients` migration vs `create_patient`; frontend: `patient_table.dart`/`PatientListItem` vs add-patient dialog/repository). Stories 1 and 3 ARE parallel-safe.
- **US4 (P2)**: Can start after Foundational in parallel with US1/US3 — backend `get_patient` migration independent; `PatientDetail` model + `_PatientIdentityCard` chip are isolated files.
- **US2 (P2)**: Can start after Foundational in parallel with US1/US3/US4 for the RPC/permission/usecase (T029–T033); the dialog's refresh-from-detail UX (T034/T035) benefits from US4's chip existing (T026) but is not blocked by it (dialog can refresh detail regardless).
- **US5 (P2)**: Backend payload migrations (T039–T041) independent; frontend unchanged/verification only (T042/T043).
- **US6 (P3)**: Independent of US1–US5; can start anytime after Foundational.

### Within Each User Story

- Tests written and FAIL before implementation (or written alongside per the existing repo's test style)
- Models before repository/usecases
- Repository/usecases before UI widgets
- Backend migration before the Flutter consumers that parse its payload
- Story checkpoint validated before next priority

### Parallel Opportunities

- T006, T007 in Phase 2 (parallel — different files from T003/T004/T005)
- After Foundational: US1 backend/frontend (T010–T013) ∥ US3 backend/frontend (T018–T020) ∥ US4 backend/frontend (T024–T026) ∥ US5 backend (T039–T041) ∥ US6 backend (T046–T047) — five stories' backend migrations touch DIFFERENT RPCs (files can be parallel IF migration filenames don't collide; coordinate timestamps)
- Within US2: T029 ∥ T030 ∥ T031 ∥ T032 (distinct files/seeds) before T033 (repository reads the RPC)
- All backend tests marked [P] can run in parallel (distinct `.sql` files)
- All Flutter unit tests marked [P] can run in parallel

---

## Parallel Example: After Foundational (T001–T007 complete)

```bash
# Five developer streams running in parallel (distinct feature folders / RPC files):

# Stream A — US1 (P1)
Task: "Add CreatePatientResult DTO in frontend/lib/features/patients/domain/create_patient_result.dart"
Task: "Extend PatientRepository.createPatient in frontend/lib/features/patients/data/patient_repository.dart"
Task: "Surface MRN on Add-Patient success in frontend/lib/features/patients/presentation/add_patient/add_patient_dialog.dart"

# Stream B — US3 (P1)
Task: "Migration 20260724121000_search_patients_include_mrn.sql"
Task: "Add mrn field to PatientListItem / patient_row_parsing.dart"
Task: "Add MRN TableColumn to patient_table.dart"

# Stream C — US4 (P2)
Task: "Migration 20260724122000_get_patient_include_mrn.sql"
Task: "Add mrn to PatientDetail.dart"
Task: "Add MRN AppBadge in patient_detail_page.dart _PatientIdentityCard"

# Stream D — US5 (P2)
Task: "Migration 20260724123000_list_invoices_include_mrn.sql (list_invoices + get_invoice_detail + list_patient_invoices)"
Task: "Verify already-wired invoice_table.dart / invoice_hero_card.dart populate"

# Stream E — US6 (P3)
Task: "Migration 20260724124000_list_appointments_include_mrn.sql"
Task: "Add patientMrn to AppointmentListItem"
Task: "Surface MRN in appointment_calendar_tile.dart"
```

Within each stream, model-parse → repository/usecase → widget, sequentially.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational (T003–T007) — CRITICAL, blocks all stories; delivers the column, sequence, unique index, generator helper, and `create_patient` returning the MRN
3. Complete Phase 3: User Story 1 (T008–T014) — toast + returned MRN + safe-degradation check
4. **STOP and VALIDATE**: Create a patient end-to-end; verify the toast shows the MRN, reload shows the MRN is persisted, concurrent creates never collide, archived-MRN-not-reused holds
5. Deploy/demo if ready — this is the foundational MVP (every other surface depends on US1's guarantee)

### Incremental Delivery

1. Setup + Foundational → Foundation ready (`mrn` exists on every patient)
2. Add US1 → Test independently → Demo (creation returns MRN)
3. Add US3 → Test independently → Demo (list shows MRN column)
4. Add US4 → Test independently → Demo (detail shows MRN chip; combined with US1, the Add-Patient journey is end-to-end visible)
5. Add US2 → Test independently → Demo (admin reassignment, duplicate rejection, audit)
6. Add US5 → Test independently → Demo (invoices show MRN)
7. Add US6 → Test independently → Demo (appointments show MRN)
8. Polish (Phase 9) → final constitution review & docs

### Parallel Team Strategy

With multiple developers:

1. Team completes Foundational together (single migration file — coordinate)
2. Once Foundational is done:
   - Developer A: US1 (P1, MVP)
   - Developer B: US3 (P1)
   - Developer C: US4 (P2)
   - Developer D: US2 (P2 RPC + permission + usecase; dialog UX coordination)
   - Developer E: US5 (P2 backend; verify wired frontend)
   - US6 (P3) can be picked up once US1 frees a developer
3. Coordinate only on migration-file timestamps and `quickstart.md`/integration test (T052)
4. Stories complete and integrate independently — each independently testable per its Independent Test criterion

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to a user story for traceability
- Each story checkpoint should be validated independently before moving on
- Backend tests generated because MRN uniqueness + RLS + admin-only reassignment + audit are constitution-sensitive
- Preserve layer boundaries: MRN generation, uniqueness, reassignment validation, and audit MUST live in PostgreSQL (`auth_internal` + `public` RPC wrappers); Flutter never generates or fabricates an MRN
- `update_patient` MUST NOT gain a `p_mrn` parameter — immutability for ordinary staff is enforced at the RPC schema boundary (T055 review)
- No Edge Functions / custom backend service / AI service involvement (N/A) — see `plan.md`
- Commit after each task or logical group; stop at any checkpoint to validate