# Patients Feature — Independent Architectural Review

Target: `frontend/lib/features/patients/**` in the `ai_clinic` Flutter desktop app
(repository root `C:\Users\haosama\Downloads\resources`, Dart package name `ai_clinic`).

## Scope & method

**What was read.** All 62 Dart files under `frontend/lib/features/patients/` were inventoried
(`application/` 1 file, `data/` 3 files, `domain/` 22 files incl. `domain/repositories/` and
`domain/usecases/`, `presentation/` 31 files, plus 5 supporting files). Every file above ~80 lines was
read in full, including `presentation/pages/patient_detail_page.dart` (819 lines),
`presentation/widgets/patient_invoice_card.dart` (475), `presentation/widgets/patient_list_controls.dart`
(406), `presentation/pages/patients_page.dart` (367), `presentation/add_patient/add_patient_form_fields.dart`
(505), `presentation/providers/patient_edit_notifier.dart` (259),
`presentation/providers/patient_registration_notifier.dart` (196),
`presentation/pages/mrn_reassignment_dialog.dart` (196), `data/patient_repository.dart` (200) and
`data/patient_dev_seed_service.dart` (190).

**Cross-boundary code read for context only** (not itself under review):
`frontend/lib/core/auth/permission_service.dart`, `frontend/lib/core/auth/auth_route_guard.dart`,
`frontend/lib/core/ui/components/app_list_control_bar.dart`,
`frontend/lib/app/router.dart`, `frontend/lib/app/app_routes.dart`,
`frontend/lib/app/navigation/app_navigator.dart`, `frontend/lib/app/shell/dev/dev_clinic_seed_service.dart`,
plus the touched surfaces of `features/appointments`, `features/visits`, `features/billing` and
`features/clinic-management`.

**Import-graph analysis.** Ripgrep was used in both directions: outbound
(`import 'package:ai_clinic/features/<not-patients>` inside `lib/features/patients`) and inbound
(`features/patients` referenced anywhere in `lib` excluding the patients folder), then the two sets were
intersected to detect cycles. Direct-data-access scans (`Supabase.instance`, `.rpc(`, `.from(`) and
permission-symbol scans were also run across `lib`.

**Grading baseline.** Findings are graded against the project's own documents, not against generic
Clean Architecture opinion:

- `docs/architecture/07-frontend.md` — canonical layering table (Presentation → domain use cases;
  Domain depends on **nothing**; Data = `*Impl` + RPC + error mapping), Riverpod provider-type
  conventions, and the explicit statement that **patients is the reference full-clean-architecture
  implementation**.
- `docs/architecture/09-security-rbac.md` — three enforcement levels; level 3 requires the Flutter layer
  to "check granular permissions from cached `roles_permissions` before rendering UI elements".
- `docs/architecture/01-principles.md` — modularity / feature isolation, server-authoritative writes.
- `docs/specs/016-patient-mrn-field/spec.md`, `contracts/mrn-generation.md`, `contracts/mrn-surfaces.md`
  — MRN generation is server-owned (sequence + unique index), MRN is immutable for ordinary staff,
  reassignment is admin-only, and the client must never fabricate an MRN (FR-010, FR-012).
- `docs/architecture/ARCHITECTURAL_FLAWS.md` — checked so that pre-existing documented debt is not
  re-reported as new. **None of the findings below are already recorded there.** The closest entries are
  `L2` (visits/billing skipping the use-case layer) and `H5` (monolithic `VisitDocumentationNotifier`);
  both concern other features. `ARCHITECTURAL_FLAWS.md` contains no Patients entry at all.

**Method for severity.** Critical = a layering inversion or contract violation that will actively
mis-guide future work or lets unverified identifiers reach the database. High = concrete
correctness/RBAC/coupling defect with user-visible or security-relevant consequence. Medium =
significant duplication, dead subsystems, or convention breaks that raise maintenance cost. Cosmetic,
naming and formatting issues were deliberately excluded.

**Overall assessment.** The Patients feature is **partially sound**. Its RPC boundary is disciplined:
there is no direct Supabase/PostgREST access anywhere in the feature (all writes go through
`AppRpcInvoker.invokeRpc` in `data/patient_repository.dart`), the use-case layer exists and is wired
through Riverpod, DTO parsing is defensive, and the optimistic-concurrency (`expectedUpdatedAt`) and
duplicate-detection flows are correct. The problems are concentrated in three places: (1) the
`domain`/`data` layers import the `presentation` layer, inverting the documented dependency direction;
(2) the patient **detail page** has absorbed billing, visits and appointments presentation logic and
calls those features' repositories directly, producing genuine import cycles; (3) client-side RBAC
gating for create/edit/archive is absent even though the guard helpers exist.

## Findings summary

| ID | Severity | Short title | Primary file |
| -- | -------- | ----------- | ------------ |
| C1 | Critical | `domain/` and `data/` import `presentation/` — inverted layering | `frontend/lib/features/patients/domain/repositories/patient_repository.dart` |
| C2 | Critical | Patients presentation calls other features' `data/` repositories; feature import cycles | `frontend/lib/features/patients/presentation/providers/patient_detail_history_provider.dart` |
| C3 | Critical | Client-supplied / client-generated MRN violates the 016 MRN contract | `frontend/lib/features/patients/domain/create_patient_input.dart` |
| H1 | High | No client-side RBAC gating for create/edit/archive; guard helpers are dead code | `frontend/lib/features/patients/presentation/widgets/patient_row_context_menu.dart` |
| H2 | High | Billing tab fetches invoices before checking `invoices.view` | `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart` |
| H3 | High | `PatientInvoiceCard` implements billing domain presentation inside Patients | `frontend/lib/features/patients/presentation/widgets/patient_invoice_card.dart` |
| H4 | High | Triple `search_patients` fetch per mount + provider mutation during `build()` | `frontend/lib/features/patients/presentation/pages/patients_page.dart` |
| H5 | High | Dead dev-seed subsystem in Patients that mutates clinic-management | `frontend/lib/features/patients/data/patient_dev_seed_service.dart` |
| M1 | Medium | `PatientListControls` duplicates the core `AppListControlBar` component | `frontend/lib/features/patients/presentation/widgets/patient_list_controls.dart` |
| M2 | Medium | `patient_rpc_failure.dart` sits in `data/` but is a presentation dependency | `frontend/lib/features/patients/data/patient_rpc_failure.dart` |
| M3 | Medium | Patients owns appointment/visit status→colour mapping | `frontend/lib/features/patients/presentation/widgets/patient_visit_record_card.dart` |
| M4 | Medium | Branch-name resolution lives in Patients and refetches all branches | `frontend/lib/features/patients/presentation/providers/active_branch_name_provider.dart` |
| M5 | Medium | Localization applied to only 7 of 31 presentation files | `frontend/lib/features/patients/presentation/pages/patients_page.dart` |
| M6 | Medium | Registration and edit notifiers are ~90% duplicated and use legacy `StateNotifier` | `frontend/lib/features/patients/presentation/providers/patient_edit_notifier.dart` |
| M7 | Medium | Dead code and unreachable branches, incl. an Edit action that lands on a placeholder | `frontend/lib/features/patients/domain/patient_exceptions.dart` |

**Counts:** 3 Critical, 5 High, 7 Medium. Total 15.

---

## C1 — `domain/` and `data/` import the `presentation/` layer (inverted dependency direction)

**Severity**: Critical

**Location**

- `frontend/lib/features/patients/domain/repositories/patient_repository.dart` — line 8:
  `import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';`
  The abstract method `PatientRepository.searchPatients` (lines 12–20) takes
  `PatientLastVisitFilter lastVisitFilter` and `PatientSortField sortField` as parameters.
- `frontend/lib/features/patients/domain/usecases/search_patients.dart` — line 4, same import; class
  `SearchPatients.call` (lines 10–28) repeats the same two parameter types.
- `frontend/lib/features/patients/data/patient_repository.dart` — line 16, same import; used in
  `PatientRepositoryImpl.searchPatients` (lines 34–59) where `sortField.wireValue` and
  `lastVisitFilter.wireValue` are serialised into the `search_patients` RPC params.
- The imported file `frontend/lib/features/patients/presentation/models/patient_list_filters.dart`
  declares `enum PatientSortField` (line 7), `enum PatientLastVisitFilter` (line 10), the
  `PatientSortFieldWire` / `PatientLastVisitFilterWire` wire-value extensions (lines 12–29), and at
  line 4 itself imports `presentation/utils/patient_presentation_formatting.dart`, which pulls in
  `package:intl` and `package:clock`.

**Issue**

The two enums that define the RPC wire contract for `search_patients` (`name_asc`, `last_visit_desc`,
`last_30_days`, …) live in the presentation layer, next to `PatientListFilters` (view state) and
`PatientTableRow` (a table row view-model). Both the domain repository interface, the domain use case,
and the data implementation import that presentation file to obtain them. The transitive closure means
`domain/` now depends on `intl` date formatting and `clock` via
`PatientPresentationFormatting`.

**Why it is a problem**

`docs/architecture/07-frontend.md` defines the layer table explicitly: Domain "Depends On: **Nothing**
(innermost layer)"; Data depends on "Domain interfaces, Supabase SDK". This is a straight inversion of
that rule, and it happens in the exact feature the same document names as the "reference
implementation" for the pattern — so every future feature copied from Patients will inherit the
inversion. Concretely it means: the repository contract cannot be unit-tested or reused without
compiling presentation widgets and their `intl`/`clock` dependencies; deleting or reshaping a UI file
(`patient_list_filters.dart`) is a breaking change to the data layer; and the RPC wire vocabulary is
not discoverable from `domain/`, where every other wire enum in the feature already lives
(`patient_list_scope.dart`, `patient_gender.dart`, `patient_marital_status.dart` all correctly expose
`wireValue` from `domain/`).

**Recommended architectural solution**

Move the two wire enums and their `wireValue` extensions into `domain/`, matching the existing
`PatientListScope` precedent. Keep `PatientListFilters` and `PatientTableRow` in
`presentation/models/patient_list_filters.dart` (they are genuine view state) and let that file import
the new domain files. After the move, `domain/` and `data/` must contain **zero** imports of
`features/patients/presentation/`.

Target files:

- New: `frontend/lib/features/patients/domain/patient_sort_field.dart` — `enum PatientSortField` +
  `extension PatientSortFieldWire`.
- New: `frontend/lib/features/patients/domain/patient_last_visit_filter.dart` —
  `enum PatientLastVisitFilter` + `extension PatientLastVisitFilterWire`.

**Suggested implementation steps**

1. Create `frontend/lib/features/patients/domain/patient_sort_field.dart`. Move into it, verbatim,
   `enum PatientSortField` (currently `patient_list_filters.dart` line 7) and
   `extension PatientSortFieldWire on PatientSortField` (lines 12–19). No imports are needed.
2. Create `frontend/lib/features/patients/domain/patient_last_visit_filter.dart`. Move into it,
   verbatim, `enum PatientLastVisitFilter` (line 10) and
   `extension PatientLastVisitFilterWire on PatientLastVisitFilter` (lines 21–29). No imports needed.
3. In `presentation/models/patient_list_filters.dart`: delete the moved enum and extension
   declarations, then add
   `import 'package:ai_clinic/features/patients/domain/patient_last_visit_filter.dart';` and
   `import 'package:ai_clinic/features/patients/domain/patient_sort_field.dart';`.
4. In `domain/repositories/patient_repository.dart`: delete the line-8 import of
   `presentation/models/patient_list_filters.dart` and replace it with the two new domain imports.
5. In `domain/usecases/search_patients.dart`: delete the line-4 presentation import and replace it with
   the two new domain imports.
6. In `data/patient_repository.dart`: delete the line-16 presentation import and replace it with the
   two new domain imports.
7. Fix any remaining call sites that relied on the enums being re-exported from
   `patient_list_filters.dart`. Known consumers to check and add the domain imports to if the analyzer
   complains: `presentation/providers/patient_list_notifier.dart`,
   `presentation/pages/patients_page.dart`, `presentation/widgets/patient_list_controls.dart`,
   `presentation/widgets/patient_table.dart`, `presentation/widgets/patient_row_context_menu.dart`,
   `data/patient_dev_seed_service.dart`.
8. Verify: run `rg -n "features/patients/presentation" frontend/lib/features/patients/domain frontend/lib/features/patients/data`
   — it must return no results. Then run `cd frontend; dart analyze lib/features/patients` and
   `flutter test test/unit/patients`.

---

## C2 — Patients presentation reaches into other features' `data/` layers, creating feature import cycles

**Severity**: Critical

**Location**

Outbound violations from `frontend/lib/features/patients/`:

- `presentation/providers/patient_detail_history_provider.dart`
  - line 5: `import '.../features/appointments/data/appointment_repository.dart';` — used in
    `patientUpcomingAppointmentsProvider` (lines 71–93) via
    `ref.read(appointmentRepositoryProvider).listAppointments(...)`.
  - line 9: `import '.../features/visits/data/visit_repository.dart';` — used in
    `patientPastVisitsProvider` (lines 60–68) via `ref.read(visitRepositoryProvider).listPatientVisits(...)`
    and in `patientVisitDocumentsProvider` (lines 96–109) via `listPatientVisitAttachments(...)`.
- `presentation/widgets/patient_document_card.dart` — line 11:
  `import '.../features/visits/data/visit_attachment_service.dart';` — used in
  `_PatientDocumentCardState._downloadFile()` (lines 28–59) via
  `ref.read(visitAttachmentServiceProvider).downloadAndOpen(...)`. Line 10 also imports
  `features/visits/application/visit_rpc_messages.dart` for `visitMessageForOpenError`.
- `presentation/pages/patient_detail_page.dart` — line 11:
  `import '.../features/billing/presentation/providers/invoice_detail_provider.dart';` — used in
  `_PatientDetailPageState._buildBillingTabBody()` (lines 372–428) via
  `ref.watch(patientInvoicesProvider(widget.patientId))`.
- `presentation/widgets/patient_invoice_card.dart` — lines 13, 14, 17 import
  `features/billing/presentation/utils/billing_formatting.dart`,
  `features/billing/presentation/utils/payment_method_l10n.dart` and
  `features/billing/presentation/providers/organization_currency_provider.dart`.

Inbound imports of Patients from the same features (the other half of the cycles):

- `frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart` lines 32–33 and
  `frontend/lib/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart`
  line 18 import `features/patients/presentation/providers/patient_detail_provider.dart`.
- `frontend/lib/features/visits/presentation/pages/visit_document_page.dart` lines 13–15 and
  `frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart` line 7 import
  `features/patients/presentation/providers/patient_detail_provider.dart` and
  `features/patients/presentation/utils/patient_presentation_formatting.dart`.
- `frontend/lib/features/appointments/presentation/widgets/appointment_booking_step1.dart` line 15
  imports `features/patients/presentation/widgets/patient_picker.dart`.

**Issue**

Two distinct violations are stacked here. First, Patients bypasses **two** layers at once: it skips its
own use-case layer *and* the owning feature's use-case layer, calling
`appointmentRepositoryProvider` / `visitRepositoryProvider` / `visitAttachmentServiceProvider`
(all `data/`-layer providers) straight from Riverpod providers and widgets. Second, the resulting
dependency graph is cyclic at the **presentation** level: `patients/presentation ↔ billing/presentation`
and `patients/presentation ↔ visits/presentation`.

Note the distinction that matters for grading: sharing the *domain* model is legitimate. Appointments
importing `patients/domain/patient_list_item.dart` and Visits/Billing importing
`patients/domain/patient_detail.dart` is fine — there is no `core/domain/` or `shared/` folder in this
codebase, and `docs/architecture/07-frontend.md` prescribes no alternative mechanism, so
domain-to-domain imports are the project's de-facto convention. What is **not** legitimate is importing
another feature's `data/` repository providers or `presentation/` providers, utils and widgets.

**Why it is a problem**

`docs/architecture/01-principles.md` states that "feature domains are isolated. Each can be specified,
built, tested, and replaced independently." With the present cycles, billing's presentation layer cannot
be compiled or tested without patients' presentation layer and vice-versa, so neither feature can be
replaced or extracted. Because Patients holds direct references to `AppointmentRepository`,
`VisitRepository` and `VisitAttachmentService`, any signature change in those three repositories breaks
the patient detail page — the change is invisible to whoever edits appointments or visits. The layer
skip also means the appointment/visit query parameters that belong in a use case (the hard-coded
365-day upcoming window and status whitelist at
`patient_detail_history_provider.dart` lines 76–90, the `limit: 100` at line 64) now live in a Patients
UI provider, where the owning teams will never find or maintain them.

**Recommended architectural solution**

Invert every cross-feature dependency so that the **owning** feature publishes the capability and
Patients consumes only that published surface. Three concrete moves:

1. *Visits* owns "patient's past visits" and "patient's visit attachments". Move
   `patientPastVisitsProvider` and `patientVisitDocumentsProvider` into a new
   `frontend/lib/features/visits/presentation/providers/patient_visit_history_provider.dart`, backed by
   new use cases `features/visits/domain/usecases/list_patient_visits.dart` and
   `features/visits/domain/usecases/list_patient_visit_attachments.dart`. Move
   `PatientDocumentCard` into `features/visits/presentation/widgets/patient_visit_document_card.dart`
   and, with it, `domain/patient_visit_document.dart` (which already imports
   `features/visits/domain/visit_attachment_item.dart`, proving it is a visits DTO).
2. *Appointments* owns "patient's upcoming appointments". Move `patientUpcomingAppointmentsProvider`
   and `PatientDetailHistoryQuery` into a new
   `frontend/lib/features/appointments/presentation/providers/patient_upcoming_appointments_provider.dart`,
   backed by a new `features/appointments/domain/usecases/list_patient_upcoming_appointments.dart` that
   encapsulates the 365-day window and the status whitelist.
3. *Billing* owns invoice rendering — see finding H3 for the `PatientInvoiceCard` move.

Patients then imports only those published providers/widgets. The cycles disappear because the
inbound direction (billing/visits importing `patients/domain/*` and
`patients/presentation/providers/patient_detail_provider.dart`) remains, while the outbound
patients → other-feature-`data`/`presentation` edges are removed.

**Suggested implementation steps**

1. Create `frontend/lib/features/visits/domain/usecases/list_patient_visits.dart` with a
   `ListPatientVisits` class taking `VisitRepository` and a `call({required String patientId, int limit = 100})`
   that returns the page and sorts descending by `visitDate` (logic currently in
   `patient_detail_history_provider.dart` lines 62–67). Register
   `listPatientVisitsUseCaseProvider` in the visits use-case provider file.
2. Create `frontend/lib/features/visits/domain/usecases/list_patient_visit_attachments.dart` with a
   `ListPatientVisitAttachments` class wrapping `VisitRepository.listPatientVisitAttachments`.
   Register `listPatientVisitAttachmentsUseCaseProvider`.
3. Create `frontend/lib/features/visits/presentation/providers/patient_visit_history_provider.dart`
   holding `patientPastVisitsProvider` and `patientVisitDocumentsProvider`, now calling the two new use
   cases instead of `visitRepositoryProvider`.
4. Move `frontend/lib/features/patients/domain/patient_visit_document.dart` to
   `frontend/lib/features/visits/domain/patient_visit_document.dart` (class name unchanged).
5. Move `frontend/lib/features/patients/presentation/widgets/patient_document_card.dart` to
   `frontend/lib/features/visits/presentation/widgets/patient_visit_document_card.dart`, renaming the
   class `PatientDocumentCard` → `PatientVisitDocumentCard`. Its imports of
   `visit_attachment_service.dart` and `visit_rpc_messages.dart` become same-feature imports and are
   then legal. Replace its use of `PatientPresentationFormatting.formatFileSize` (line 161) with a
   visits-local helper or move `formatFileSize` into `core/ui` — see M4/M5 note in step 12.
6. Create `frontend/lib/features/appointments/domain/usecases/list_patient_upcoming_appointments.dart`
   with a `ListPatientUpcomingAppointments` class that wraps
   `AppointmentRepository.listAppointments`, hard-coding the `from = clock.now().toUtc()`,
   `to = from + 365 days` window and the `[scheduled, confirmed, checkedIn, inProgress]` status list
   currently at `patient_detail_history_provider.dart` lines 76–90. Register
   `listPatientUpcomingAppointmentsUseCaseProvider`.
7. Create
   `frontend/lib/features/appointments/presentation/providers/patient_upcoming_appointments_provider.dart`
   holding `PatientDetailHistoryQuery` and `patientUpcomingAppointmentsProvider`, calling the new use
   case.
8. Reduce `frontend/lib/features/patients/presentation/providers/patient_detail_history_provider.dart`
   to only `PatientDetailHistoryTab` and `patientDetailHistoryTabProvider` (lines 12–33). Delete lines
   1–11 imports of appointments/visits `data/` and all three moved providers.
9. Update `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`: change the
   imports at lines 20 and 24 to the new visits/appointments provider and widget paths; in
   `_buildDocumentsTabBody()` (lines 430–467) replace `PatientDocumentCard` with
   `PatientVisitDocumentCard`.
10. Update `frontend/lib/features/patients/presentation/widgets/patient_visit_record_card.dart` only if
    the `PatientVisitDocument` import path change affects it (it does not today).
11. Verify no cycle remains: run
    `rg -n "import 'package:ai_clinic/features/(appointments|visits|billing)/(data|presentation)/" frontend/lib/features/patients`
    — after H3 is also applied this must return no results.
12. Run `cd frontend; dart analyze lib` then `flutter test`.

---

## C3 — Client-supplied and client-generated MRN contradicts the 016 MRN contract

**Severity**: Critical

**Location**

- `frontend/lib/features/patients/domain/create_patient_input.dart` — field `final String? mrn;` at
  line 27 (constructor param line 14, `copyWith` param lines 38 and 49). Doc comment at line 26 reads
  "Optional explicit MRN (validated server-side). Used by dev seed flows."
- `frontend/lib/features/patients/data/patient_repository.dart` —
  `PatientRepositoryImpl.createPatient` lines 124 and 134:
  `final submittedMrn = input.mrn?.trim();` and
  `if (submittedMrn != null && submittedMrn.isNotEmpty) 'p_mrn': submittedMrn,`.
  The class's `migrationHint` at line 28 is
  `'20260724125000_create_patient_optional_mrn_param.sql'`, confirming a backend parameter was added
  specifically to accept a client MRN.
- `frontend/lib/features/patients/domain/patient_dev_seed_spec.dart` — static
  `PatientDevSeedSpec.mrnForSeedOrder(int oneBasedIndex)` at lines 37–40 returns
  `'MRN-${oneBasedIndex.toString().padLeft(6, '0')}'` — a client-side implementation of the server's
  MRN format.
- Live consumer outside the feature:
  `frontend/lib/app/shell/dev/dev_clinic_seed_spec.dart` line 122 `static String patientMrn(int globalPatientIndex)`
  and `frontend/lib/app/shell/dev/dev_clinic_seed_service.dart` line 908
  `mrn: DevClinicSeedSpec.patientMrn(globalIndex),` inside `_createPatient(...)`.
- Dead consumer inside the feature:
  `frontend/lib/features/patients/data/patient_dev_seed_service.dart` line 162
  `mrn: PatientDevSeedSpec.mrnForSeedOrder(seedOrder),` (see H5 — this whole service is unreachable).

**Issue**

`docs/specs/016-patient-mrn-field/contracts/mrn-generation.md` specifies that `create_patient` is
extended with **"signature otherwise unchanged"** and that the MRN is produced inside the RPC by
`auth_internal.assign_patient_mrn()`, a function explicitly documented as "**not** granted to any role".
`spec.md` FR-010 requires generation "via a server-side sequence", and FR-012 states the client
"MUST NOT allow saving a patient with a locally generated, unverified MRN". The frontend nonetheless
carries a first-class `mrn` field on the domain input DTO, forwards it as `p_mrn`, and contains two
independent client-side MRN formatters that reproduce the `MRN-%06d` shape.

There is no evidence of a runtime bug today — the production Add-Patient path
(`presentation/providers/patient_registration_notifier.dart` `submit()`, lines 188–201) never sets
`mrn`, so real patients still receive sequence-generated values, and
`createPatient` correctly hard-fails when the server returns no MRN (lines 142–144). The defect is that
the *contract surface* has been widened: a supported, documented-in-code path now exists for a client to
choose an MRN, and it is actively exercised by the dev seeder.

**Why it is a problem**

MRN is a globally unique clinical identifier (`spec.md` clarifications: "Global unique across the entire
database"). Client-chosen MRNs break the invariant the spec was written to protect: the seeder's
`mrnForSeedOrder(1) == 'MRN-000001'` and `DevClinicSeedSpec.patientMrn(...)` collide by construction
with values the sequence will later hand out, so after any dev seed the sequence and the occupied MRN
space diverge and subsequent real `create_patient` calls can hit the `patients_mrn_unique` backstop —
turning a routine registration into a hard RPC failure. The spec anticipated exactly this and mandated
"avoiding retry-based collision loops", which the client has no way to perform. Architecturally, the
`mrn` field on `CreatePatientInput` is also the only field in the DTO that does not correspond to
user-entered data, so it mis-teaches the model: any future bulk-import or migration feature copied from
this DTO will assume client MRN assignment is sanctioned.

**Recommended architectural solution**

Make the frontend physically incapable of supplying an MRN. Remove `mrn` from `CreatePatientInput`,
remove the `p_mrn` parameter from `PatientRepositoryImpl.createPatient`, and delete both client-side MRN
formatters. Dev seeders keep whatever MRN the server returns (`CreatePatientResult.mrn`, which
`createPatient` already parses at line 138) rather than dictating one. `frontend/lib/features/patients/domain/create_patient_result.dart`
already models `{patientId, mrn}` correctly, so no new type is required.

The backend migration `20260724125000_create_patient_optional_mrn_param.sql` may stay in place as a
harmless optional parameter, but no client code should pass it; update the `migrationHint` string to the
most recent patients migration so the diagnostic no longer advertises the MRN parameter.

**Suggested implementation steps**

1. In `frontend/lib/features/patients/domain/create_patient_input.dart`: delete the `this.mrn,`
   constructor parameter (line 14), the `final String? mrn;` field and its doc comment (lines 26–27),
   the `String? mrn,` parameter in `copyWith` (line 38), and `mrn: mrn ?? this.mrn,` (line 49).
2. In `frontend/lib/features/patients/data/patient_repository.dart` `createPatient`: delete line 124
   (`final submittedMrn = ...`) and line 134 (the conditional `'p_mrn'` entry). Leave lines 137–145
   (reading back `patient_id` and `mrn` from the response) untouched — that is the correct
   server-authoritative read.
3. In the same file, change `migrationHint` (line 28) to
   `'20260727160000_get_invoice_detail_patient_contact.sql'` or the newest patients-related migration
   filename, so the hint no longer names the MRN parameter migration.
4. Delete `static String mrnForSeedOrder(...)` from
   `frontend/lib/features/patients/domain/patient_dev_seed_spec.dart` (lines 37–40). (If H5 is applied,
   this whole file is deleted instead.)
5. Delete `static String patientMrn(int globalPatientIndex)` from
   `frontend/lib/app/shell/dev/dev_clinic_seed_spec.dart` (line 122). If
   `patientGlobalIndex(...)` (line 117) has no other caller after this, delete it too.
6. In `frontend/lib/app/shell/dev/dev_clinic_seed_service.dart` `_createPatient(...)` (around lines
   892–920): delete line 899 (`final globalIndex = ...`) and line 908 (`mrn: ...`). The method already
   returns `result.patientId`; if a seeded MRN is needed for logging, use `result.mrn` from the
   `CreatePatientResult` returned at line 912.
7. In `frontend/lib/features/patients/data/patient_dev_seed_service.dart` line 162: delete the
   `mrn:` argument (or delete the file per H5).
8. Verify: `rg -n "p_mrn|mrnForSeedOrder|patientMrn\(" frontend/lib` must return no results outside
   `presentation/pages/mrn_reassignment_dialog.dart` (which legitimately sends `p_new_mrn` to
   `reassign_patient_mrn`).
9. Run `cd frontend; dart analyze lib` and `flutter test test/unit/patients`.
10. Regression check the dev seeder manually: reset with
    `backend/tests/dev_reset_clinic_installation.sql` (which per the contract resets
    `public.patient_mrn_seq`), run the dev clinic seed, then register a patient through the UI and
    confirm the MRN toast in `presentation/add_patient/add_patient_dialog.dart` (line 48) shows a
    non-colliding sequential value.

---

## H1 — No client-side RBAC gating for patient create / edit / archive; the guard helpers are dead code

**Severity**: High

**Location**

- `frontend/lib/core/auth/auth_route_guard.dart`:
  - `canAccessPatientRegistration` (lines 57–62), `canAccessPatientEdit` (lines 68–73),
    `canAccessPatientDelete` (lines 75–80) — **none of these three is referenced anywhere in
    `frontend/lib`**. A repo-wide search finds references only in their own definitions and in
    `frontend/test/unit/...` for the underlying `PermissionService` methods.
  - `patientRouteRedirect` (lines 294–309) returns `null` unconditionally after the auth/setup checks,
    with the comment at line 307: "Permission checks are enforced on each patient page (UI stays
    visible; denial in-page)." That contract is not honoured for mutations.
- `frontend/lib/features/patients/presentation/pages/patients_page.dart` — the "Add patient" primary
  button in `build()` (lines 344–350) and the empty-state `EmptyStateAction(label: 'Add patient')` in
  `_buildBody` (lines 274–282) are rendered unconditionally; `_openAddPatient()` (lines 84–86) opens
  `AddPatientDialog` with no `patients.create` check.
- `frontend/lib/features/patients/presentation/widgets/patient_row_context_menu.dart` —
  `PatientRowContextMenu.build` builds the menu entries at lines 32–60 unconditionally: `'edit'`
  (lines 44–51, navigates to the edit route) and `'deactivate'` (lines 53–59, calls
  `_deactivatePatient`). No `canEditPatients()` / `canDeletePatients()` check.
- `frontend/lib/features/patients/presentation/widgets/patient_row_context_menu.dart`
  `_deactivatePatient(...)` (lines 218–236) awaits `archivePatientUseCaseProvider` with **no
  confirmation dialog and no try/catch**, then reloads the list and toasts success.
- `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart` — `onEdit` is wired
  purely on data availability (`onEdit: detail != null ? _openEditPatient : null`, line 507); only
  `canReassignMrn` (line 528–530, via `permissionServiceProvider.canReassignPatientMrn()`) and the
  billing tab's `AuthRouteGuard.canAccessInvoiceList` (lines 373–375) are permission-driven.
- Working counter-example in the same feature (shows the intended pattern is understood):
  `presentation/providers/patient_list_notifier.dart` line 69 (`AuthRouteGuard.canAccessPatientList`)
  and `presentation/providers/patient_detail_provider.dart` lines 11–16
  (`AuthRouteGuard.canAccessPatientDetail`).

**Issue**

Read paths are gated; write paths are not. `patients.create`, `patients.edit` and `patients.delete` are
never consulted before rendering or invoking the corresponding actions, even though
`PermissionService.canCreatePatients()` / `canEditPatients()` / `canDeletePatients()`
(`frontend/lib/core/auth/permission_service.dart` lines 39–43) and the three `AuthRouteGuard` wrappers
already exist and are unit-tested. The archive action additionally has no confirmation step and swallows
nothing — an RPC failure becomes an unhandled async exception while the UI still shows the success
toast, because `_deactivatePatient` toasts unconditionally after the `await`.

A second, milder symptom of the same gap: when `canAccessPatientList` is false,
`PatientListNotifier._load` (lines 67–75) returns an *empty* state, which
`PatientListUiState.isNoPatientsYet` (lines 28–32) then classifies as first-run, so an unauthorised user
sees "No patients yet — Add your first patient to start building records" plus an Add-patient CTA
instead of a no-access state.

**Why it is a problem**

`docs/architecture/09-security-rbac.md` names three enforcement levels and describes level 3 as: "Flutter
service layer (application level): check granular permissions from cached `roles_permissions` **before
rendering UI elements**". The document's resolution flow diagram is explicit: "If denied: UI element
hidden/disabled, action blocked". The database RPCs are still the authoritative boundary — a
receptionist without `patients.delete` will get `FORBIDDEN` from `archive_patient` — so this is not a
data-breach hole. It is a defence-in-depth and UX-integrity failure: staff are shown destructive
affordances they cannot use, the resulting `FORBIDDEN` surfaces as an unhandled exception rather than a
clean message, and the role-specific UI that the permission matrix screen promises does not materialise.
The three dead guard helpers are worse than absent code, because a future implementer reading
`auth_route_guard.dart` will reasonably assume they are wired.

**Recommended architectural solution**

Gate every mutation affordance in Patients on the existing `permissionServiceProvider`, using the same
style already used for `canReassignPatientMrn` in `patient_detail_page.dart`. Convert
`PatientRowContextMenu` to build its entry list conditionally, add a confirmation dialog and error
handling to the archive path, and make the unauthorised list state render
`AppEmptyStateVariant.noAccess` instead of the first-run empty state.

Add an explicit no-access signal to the list state rather than inferring it from emptiness: extend
`PatientListUiState` (in `presentation/providers/patient_list_notifier.dart`) with
`final bool accessDenied` and have `_load` set it.

New file: `frontend/lib/features/patients/presentation/widgets/archive_patient_dialog.dart` exposing
`ArchivePatientDialog.show(BuildContext, {required String fullName}) → Future<bool>` built on
`AppDialog` (mirror the structure of `presentation/pages/mrn_reassignment_dialog.dart`, which is the
feature's existing confirm-dialog pattern).

**Suggested implementation steps**

1. In `frontend/lib/features/patients/presentation/pages/patients_page.dart`: add
   `import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';` is **not** needed; instead
   add `import 'package:ai_clinic/core/auth/permission_denied_handler.dart';` only if a toast is wanted.
   In `build()`, read `final canCreate = ref.watch(permissionServiceProvider).canCreatePatients();`
   (the provider is exported from `frontend/lib/core/auth/permission_service.dart`'s provider file
   already used at `patient_detail_page.dart` line 529). Wrap the `AppButton` at lines 344–350 in
   `if (canCreate)`, and pass `action: canCreate ? EmptyStateAction(...) : null` at lines 278–281.
2. In `frontend/lib/features/patients/presentation/providers/patient_list_notifier.dart`: add
   `final bool accessDenied;` to `PatientListUiState` (default `false`) including constructor param;
   in `_load`, the early return at lines 70–74 becomes
   `PatientListUiState(rows: const [], totalCount: 0, filters: filters, accessDenied: true)`. Adjust
   `isNoPatientsYet` (line 28) to also require `!accessDenied`.
3. In `patients_page.dart` `_buildBody`: before the `state.isNoPatientsYet` branch (line 273), add
   `if (state.accessDenied) return AppEmptyState(variant: AppEmptyStateVariant.noAccess, title: 'You do not have access to patient records');`
   (use the l10n key added in M5 if that finding is applied first).
4. Create `frontend/lib/features/patients/presentation/widgets/archive_patient_dialog.dart` with an
   `abstract final class ArchivePatientDialog` exposing
   `static Future<bool> show(BuildContext context, {required String fullName})`. Model it on
   `MrnReassignmentDialog.show` in `presentation/pages/mrn_reassignment_dialog.dart` lines 16–34:
   `AppDialog.show<bool>` with a destructive primary button, returning `result ?? false`.
5. In `frontend/lib/features/patients/presentation/widgets/patient_row_context_menu.dart`: convert
   `build` to read
   `final permissions = ref.watch(permissionServiceProvider);` then build `entries` conditionally —
   include the `'edit'` item only when `permissions.canEditPatients()`, and the `AppMenuSeparator()` +
   `'deactivate'` item only when `permissions.canDeletePatients()`. Keep `'open'` and `'book'`
   unconditional (`'book'` should additionally check `permissions.canCreateAppointments()`).
6. In the same file, change the `'deactivate'` `onSelect` to an async handler that first awaits
   `ArchivePatientDialog.show(context, fullName: fullName)` and returns early on `false`.
7. Rewrite `_deactivatePatient` (lines 218–236) to wrap the `archivePatientUseCaseProvider` call in
   `try / on RpcFailure / catch`, and only emit the success `appToast` inside the success path. On
   `RpcFailure`, toast `patientMessageForRpc(error)` from
   `frontend/lib/features/patients/application/patient_rpc_messages.dart` with
   `AppToastVariant.danger`.
8. In `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`: read
   `final canEdit = ref.watch(permissionServiceProvider).canEditPatients();` alongside the existing
   `canReassignMrn` at lines 528–530, thread a `required bool canEdit` parameter through
   `_buildMainContent` (lines 477–523), and change line 507 to
   `onEdit: detail != null && canEdit ? _openEditPatient : null`.
9. Delete `canAccessPatientRegistration`, `canAccessPatientEdit` and `canAccessPatientDelete` from
   `frontend/lib/core/auth/auth_route_guard.dart` (lines 57–80) **or** wire them in place of the direct
   `PermissionService` calls in steps 1, 5 and 8 — pick one and be consistent. Preferred: keep the
   guards and use them, since `patient_list_notifier.dart` and `patient_detail_provider.dart` already
   use the `AuthRouteGuard.*` style.
10. Verify: `rg -n "canAccessPatientRegistration|canAccessPatientEdit|canAccessPatientDelete" frontend/lib`
    must now return call sites, not only definitions. Run `cd frontend; dart analyze lib` and
    `flutter test test/unit/patients`.
11. Manual check: sign in as a `lab_staff` account (per `09-security-rbac.md` it has view-only patient
    access) and confirm the Add-patient button, row Edit and row Deactivate are all absent.

---

## H2 — Billing tab issues the invoice fetch before evaluating `invoices.view`

**Severity**: High

**Location**

`frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`,
`_PatientDetailPageState._buildBillingTabBody()` — lines 372–380:

```370:380:frontend/lib/features/patients/presentation/pages/patient_detail_page.dart
  Widget _buildBillingTabBody() {
    final invoicesAsync = ref.watch(patientInvoicesProvider(widget.patientId));
    final canViewInvoices = AuthRouteGuard.canAccessInvoiceList(ref);
    if (!canViewInvoices) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Billing access required',
      );
    }
```

**Issue**

`ref.watch(patientInvoicesProvider(...))` executes *before* the `canViewInvoices` test. In Riverpod,
`watch` on a `FutureProvider.family` instantiates the provider and starts its future immediately, so the
`list_invoices` RPC is dispatched even for a user with no `invoices.view` permission; the widget then
discards the result and renders the no-access state. The declared variable `invoicesAsync` is also unused
along the denial branch.

**Why it is a problem**

Every deny is a guaranteed round-trip whose only possible outcome is a `FORBIDDEN` RPC error, so the
denial path is the slowest path and it produces spurious `FORBIDDEN` entries in Supabase logs, which
makes real authorisation-probe detection harder. It also inverts the ordering
`docs/architecture/09-security-rbac.md` prescribes for level 3 — permission is meant to be checked
*before* the action, not concurrently with it. Because `patientInvoicesProvider` is `autoDispose`-less
family state, the rejected future is additionally cached and re-thrown on every rebuild of the tab.

**Recommended architectural solution**

Check the permission first and return early; only then watch the provider. This is a two-line
reordering, no new abstraction needed. Apply the same ordering discipline anywhere else in the feature
where a guard and a `watch` co-exist (currently only this site).

**Suggested implementation steps**

1. In `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`, move
   `final canViewInvoices = AuthRouteGuard.canAccessInvoiceList(ref);` (line 374) to be the **first**
   statement of `_buildBillingTabBody()`.
2. Move `final invoicesAsync = ref.watch(patientInvoicesProvider(widget.patientId));` (line 373) to
   **after** the `if (!canViewInvoices) { ... return ...; }` block that currently ends at line 381.
3. Re-run the tab: `cd frontend; dart analyze lib/features/patients/presentation/pages/patient_detail_page.dart`
   (the previously-unused-on-deny variable warning, if any, disappears).
4. Manual check: as a role without `invoices.view`, open a patient and select the Billing tab; confirm
   via the Supabase logs / dev network panel that no `list_invoices` call is made.

---

## H3 — `PatientInvoiceCard` implements billing-domain presentation inside the Patients feature

**Severity**: High

**Location**

`frontend/lib/features/patients/presentation/widgets/patient_invoice_card.dart` (475 lines), class
`PatientInvoiceCard` and its private helpers. Billing-owned logic embedded here:

- lines 13–17: imports of `features/billing/presentation/utils/billing_formatting.dart`,
  `features/billing/presentation/utils/payment_method_l10n.dart`,
  `features/billing/presentation/providers/organization_currency_provider.dart`, plus
  `features/billing/domain/invoice_*` DTOs.
- `_statusStyle(...)` / `_statusLabel(...)` — a local `InvoiceStatus` → colour/label mapping.
- `_buildLineItems(...)`, `_buildPaymentRows(...)`, `_buildTotals(...)` — invoice line-item, payment and
  totals layout, including currency formatting through
  `ref.watch(organizationCurrencyProvider)` and `BillingFormatting`.
- `_buildRefundBadge(...)` / refund-vs-payment discrimination.

Consumers: only `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`
`_buildBillingTabBody()` (line 404).

**Issue**

The Patients feature owns a 475-line renderer for the billing aggregate: invoice status semantics,
payment-method labels, refund handling, line items, and currency presentation. All of the inputs are
Billing DTOs (`InvoiceListItem`, `InvoiceLineItem`, `InvoicePayment`, `InvoiceStatus`) and all of the
formatting helpers are Billing utilities imported across the feature boundary. Nothing in the widget is
patient-specific except that it is placed inside a patient tab.

**Why it is a problem**

This is the largest single contributor to the `patients/presentation ↔ billing/presentation` cycle
described in C2, and it duplicates knowledge that Billing must already hold: Billing's own
`invoice_detail_page.dart` and `features/billing/presentation/widgets/**` render the same status
vocabulary and totals. When `InvoiceStatus` changes — and `docs/specs/007-billing/invoice-status-cycle.md`
plus the recent `20260727140000_remove_payment_reference.sql` migration show the status/payment model is
actively evolving — two independent mappings must be updated, and the Patients one will be forgotten
because it lives under a folder no billing engineer greps. Colour/label drift between the patient billing
tab and the billing module is then user-visible for the same invoice.

**Recommended architectural solution**

Move the widget into Billing and have Patients consume it as a published component. It becomes
`frontend/lib/features/billing/presentation/widgets/patient_invoice_card.dart` (class name unchanged), at
which point all five cross-feature imports become intra-feature. In the same move, replace the local
`_statusStyle` / `_statusLabel` with Billing's existing status presentation helper if one exists in
`features/billing/presentation/utils/` — check `billing_formatting.dart` first — and only keep a local
mapping if Billing genuinely has none, in which case create
`features/billing/presentation/utils/invoice_status_presentation.dart` and have both the new card and
Billing's own pages use it.

**Suggested implementation steps**

1. Move the file `frontend/lib/features/patients/presentation/widgets/patient_invoice_card.dart` to
   `frontend/lib/features/billing/presentation/widgets/patient_invoice_card.dart`. Keep the class name
   `PatientInvoiceCard`.
2. In the moved file, rewrite the billing imports as relative-to-feature absolute paths that are now
   intra-feature (paths are unchanged textually since the project uses `package:ai_clinic/...`
   everywhere — no edit needed), and delete any now-unused import.
3. Search Billing for an existing invoice-status presentation mapping:
   `rg -n "InvoiceStatus" frontend/lib/features/billing/presentation`. If a shared mapping exists, delete
   `_statusStyle` and `_statusLabel` from the moved file and call it. If none exists, create
   `frontend/lib/features/billing/presentation/utils/invoice_status_presentation.dart` containing
   `InvoiceStatusPresentation.styleFor(BuildContext, InvoiceStatus)` and
   `InvoiceStatusPresentation.labelFor(BuildContext, InvoiceStatus)` moved verbatim from the two private
   helpers, then use it from the card.
4. In `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart`: change the import at
   line 25 from `.../patients/presentation/widgets/patient_invoice_card.dart` to
   `.../billing/presentation/widgets/patient_invoice_card.dart`. The usage at line 404 is unchanged.
5. If `patientInvoicesProvider` currently lives in
   `features/billing/presentation/providers/invoice_detail_provider.dart`, leave it there — that is the
   correct owner and the Patients import of it (line 11) is a legitimate published-provider dependency
   once the widget has moved.
6. Verify: `rg -n "features/billing" frontend/lib/features/patients` should now show at most the single
   `invoice_detail_provider.dart` provider import (and `invoice_list_item.dart` if still needed by the
   page's `AsyncValue` typing).
7. Run `cd frontend; dart analyze lib` and `flutter test`.

---

## H4 — Patients list triggers `search_patients` three times per mount and mutates a provider during `build()`

**Severity**: High

**Location**

`frontend/lib/features/patients/presentation/pages/patients_page.dart`:

- `_PatientsPageState.initState()` (lines 48–56) calls
  `WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(patientListNotifierProvider.notifier).reload());`
- `_PatientsPageState.build()` (around lines 300–320) contains, inside the build method:
  `ref.listen(...)` **and** a direct `ref.read(patientListNotifierProvider.notifier).setScope(...)` /
  `applyFilters(...)` invocation reacting to `widget.initialScope` — a state mutation performed during
  the build phase.
- `frontend/lib/features/patients/presentation/providers/patient_list_notifier.dart` —
  `PatientListNotifier` extends the legacy `StateNotifier<PatientListUiState>`; its constructor body
  calls `_load()` (constructor around lines 40–48), so provider construction is itself a fetch.
  `setScope`, `applyFilters`, `setPage` and `reload` each call `_load()` (lines 80–130).
- Search debounce: `_onSearchChanged` in `patients_page.dart` uses a `Timer` but the initial
  `setScope`-from-`build` path bypasses it.

**Issue**

Three separate `search_patients` RPCs fire for a single navigation to `/patients`: (1) the notifier
constructor's `_load()`, (2) the `initState` post-frame `reload()`, (3) the `setScope`/`applyFilters`
call executed from `build()` when `widget.initialScope` differs from the default. The third is also a
Riverpod anti-pattern — mutating a notifier inside `build()` schedules another rebuild, and because the
scope comparison is against the *current* state rather than a stored "already applied" flag, it can fire
again on unrelated rebuilds (window resize, theme change, tab focus).

**Why it is a problem**

`search_patients` is the heaviest read in the feature (paged join over patients + last-visit aggregate).
Tripling it on every list mount triples the perceived load latency and the row-level-security evaluation
cost, and the three responses race: whichever resolves last wins, so a user who navigates with
`initialScope: archived` can briefly see active patients, or vice-versa. `docs/architecture/07-frontend.md`
prescribes `AsyncNotifierProvider` for "async state with loading/error", precisely so that initial load
is expressed once as `build()` of the notifier rather than as constructor side-effect plus
`initState` kick plus in-build mutation. Mutating providers during `build()` is the class of defect that
produces the "setState during build" / infinite-rebuild reports the project already tracks in
`docs/ui/memory/ui-runtime-errors.md`.

**Recommended architectural solution**

Make the initial load happen exactly once, owned by the notifier, and pass the initial scope as
provider input rather than as a post-construction mutation.

Minimal, low-risk version (recommended for a cheap model): keep `StateNotifier` but (a) remove the
`_load()` call from the constructor **or** remove the `initState` `reload()` — keep exactly one; and
(b) move the `initialScope` application out of `build()` into `initState`'s post-frame callback, guarded
by a `bool _initialScopeApplied` field so it runs once.

Fuller version (aligns with `07-frontend.md`): convert `PatientListNotifier` to
`AsyncNotifier<PatientListUiState>` registered as
`AsyncNotifierProvider<PatientListNotifier, PatientListUiState>`, with the initial fetch in its
`build()` and the scope supplied via a separate `patientListScopeProvider` that the notifier watches.

**Suggested implementation steps**

1. In `frontend/lib/features/patients/presentation/providers/patient_list_notifier.dart`: delete the
   `_load();` statement from the `PatientListNotifier` constructor body. The notifier now starts in its
   initial (empty, `isLoading: true`) state and loads only when told to.
2. In `frontend/lib/features/patients/presentation/pages/patients_page.dart`: add a private field
   `bool _initialLoadDone = false;` to `_PatientsPageState`.
3. Rewrite `initState()` so the single post-frame callback does both jobs in order: if
   `widget.initialScope != null`, call `setScope(widget.initialScope!)` (which internally calls `_load()`);
   otherwise call `reload()`. Then set `_initialLoadDone = true;`. Guard the whole body with
   `if (!mounted) return;`.
4. Delete the `setScope(...)` / `applyFilters(...)` call that currently executes inside `build()`. Keep
   any `ref.listen(...)` there — `ref.listen` in `build` is legal and correct.
5. If a scope change can still arrive via widget update (route re-navigation with a different
   `initialScope`), implement `didUpdateWidget(covariant PatientsPage oldWidget)` that compares
   `oldWidget.initialScope != widget.initialScope` and calls `setScope` from a post-frame callback.
6. Verify exactly one RPC per mount: add a temporary `debugPrint` at the top of
   `PatientRepositoryImpl.searchPatients` (`frontend/lib/features/patients/data/patient_repository.dart`
   line 34), run the app, navigate to `/patients`, confirm a single line, then remove the `debugPrint`.
7. Confirm the deep-link paths still work: `/patients` (default scope), and the archived-scope entry
   point used by `frontend/lib/app/navigation/app_navigator.dart` (`goPatients`/`goPatientsArchived`).
8. Run `cd frontend; dart analyze lib/features/patients` and `flutter test test/unit/patients`.

---

## H5 — An entire unreachable dev-seed subsystem lives in Patients and writes to clinic-management

**Severity**: High

**Location**

- `frontend/lib/features/patients/data/patient_dev_seed_service.dart` (190 lines) — class
  `PatientDevSeedService`, provider `patientDevSeedServiceProvider`. Line 5 imports
  `features/clinic-management/data/branch_repository.dart`; line 6 imports
  `features/clinic-management/domain/branch.dart`. It creates branches (`_ensureBranch`, around lines
  60–95) and then patients (`_seedPatients`, lines 120–180, including the MRN passed at line 162).
- `frontend/lib/features/patients/domain/patient_dev_seed_spec.dart` — `PatientDevSeedSpec`, consumed
  only by the above.
- `frontend/lib/features/patients/domain/patient_dev_seed_data.dart` — the seed name/DOB/gender tables,
  consumed only by the above.
- **No caller.** `rg -n "patientDevSeedServiceProvider|PatientDevSeedService" frontend/lib` matches only
  the definition file. The dev tooling that actually runs is
  `frontend/lib/app/shell/dev/dev_clinic_seed_service.dart` +
  `frontend/lib/app/shell/dev/shell_dev_fill_dummy_clinic.dart`, which implement their own patient
  seeding (`_createPatient`, around line 892) and their own spec
  (`frontend/lib/app/shell/dev/dev_clinic_seed_spec.dart`).

**Issue**

Three files (~350 lines) form a complete, compiling, provider-registered patient seeding service that
nothing invokes, while a second independent implementation of the same job lives in `app/shell/dev/` and
is the one wired to the UI. The dead copy additionally violates feature isolation twice over: it is
`data/`-layer code in Patients that (a) imports another feature's `data/` repository
(`branchRepositoryProvider`) and (b) *creates* clinic-management entities (branches) — a write into
another feature's aggregate from inside Patients.

**Why it is a problem**

Two divergent seeders guarantee drift: the `app/shell/dev` one has already gained organization/currency
and service-catalog awareness (`dev_clinic_seed_service_catalog.dart`, `dev_clinic_seed_billing.dart`)
that the Patients copy lacks, so anyone who finds the Patients copy first will "fix" seeding in the file
that never runs. Because it compiles, it also keeps `CreatePatientInput.mrn` (C3) and the
`patients → clinic-management/data` edge alive in the import graph, making the graph look worse than the
runtime behaviour actually is and blocking any automated boundary lint. Dead code that constructs
branches is a real hazard if someone ever wires the provider up: it would silently add branches to a live
installation.

**Recommended architectural solution**

Delete the dead subsystem. `app/shell/dev/dev_clinic_seed_service.dart` is the single sanctioned seeder;
dev tooling correctly belongs in `app/shell/dev/` (outside the feature folders) because it spans multiple
features, and that is where the seed spec/data for patients should live too. If any of the seed *data*
tables in `patient_dev_seed_data.dart` are richer than what `dev_clinic_seed_spec.dart` has, port the
tables into `app/shell/dev/` before deleting.

**Suggested implementation steps**

1. Confirm there is still no caller:
   `rg -n "patientDevSeedServiceProvider|PatientDevSeedService|PatientDevSeedSpec|PatientDevSeedData" frontend`
   (include `frontend/test`). If a test references them, delete that test too or repoint it at
   `DevClinicSeedService`.
2. Compare seed data: open `frontend/lib/features/patients/domain/patient_dev_seed_data.dart` and
   `frontend/lib/app/shell/dev/dev_clinic_seed_spec.dart`. If the Patients file has name/DOB/gender
   tables the shell seeder lacks, copy those `static const` lists into `dev_clinic_seed_spec.dart`.
3. Delete `frontend/lib/features/patients/data/patient_dev_seed_service.dart`.
4. Delete `frontend/lib/features/patients/domain/patient_dev_seed_spec.dart`.
5. Delete `frontend/lib/features/patients/domain/patient_dev_seed_data.dart`.
6. Run `cd frontend; dart analyze lib` and fix any orphaned import (there should be none).
7. Verify the boundary is clean:
   `rg -n "features/clinic-management" frontend/lib/features/patients` — should return nothing after this
   deletion.
8. Manual check: run the app in debug, open the dev shell menu, and execute "Fill dummy clinic" to
   confirm `shell_dev_fill_dummy_clinic.dart` still seeds patients successfully.

---

## M1 — `PatientListControls` duplicates the new core `AppListControlBar` / `AppFilterMenuPanel`

**Severity**: Medium

**Location**

- `frontend/lib/features/patients/presentation/widgets/patient_list_controls.dart` (406 lines) — class
  `PatientListControls` plus private `_buildSearchField`, `_buildScopeSegmented`, `_buildSortMenu`,
  `_buildLastVisitMenu`, `_buildFilterChips`, and its own popover/anchor plumbing via `AppPopover`.
- Core components that already exist and cover this:
  `frontend/lib/core/ui/components/app_list_control_bar.dart` (`AppListControlBar`, with
  `searchField`, `segmented`, `trailing`, `activeFilters` slots) and
  `frontend/lib/core/ui/components/app_filter_menu_panel.dart` (`AppFilterMenuPanel`, the
  standard filter-popover body). Both are exported from
  `frontend/lib/core/ui/widgets/widgets.dart`.

**Issue**

The Patients list bar predates the two shared components and re-implements their layout, spacing,
popover anchoring and active-filter chip rendering by hand. The shared components were introduced for
exactly this surface (they are used by the newer invoices/appointments list pages), so Patients is now
the only list in the app with a bespoke control bar.

**Why it is a problem**

`docs/architecture/07-frontend.md` places shared presentational widgets in `core/ui` specifically so
list surfaces stay visually identical; a hand-rolled duplicate drifts on padding, chip styling, popover
offset and keyboard behaviour, and every design-system change (density tokens, focus rings) must be
applied twice. It is also ~250 lines of avoidable maintenance surface in a feature that is meant to be
the reference implementation.

**Recommended architectural solution**

Re-implement `PatientListControls` as a thin composition over `AppListControlBar`, passing
`AppFilterMenuPanel` bodies for the sort and last-visit menus. Keep `PatientListControls` as the
feature-level widget (it owns the patients-specific filter vocabulary and callbacks); delete only the
generic layout/popover/chip code it currently duplicates.

**Suggested implementation steps**

1. Read `frontend/lib/core/ui/components/app_list_control_bar.dart` and note the exact constructor slots
   (`searchField`, `segmented`, `trailing`, `activeFilters`, and any density/spacing params).
2. Read `frontend/lib/core/ui/components/app_filter_menu_panel.dart` and note its item/section API.
3. In `frontend/lib/features/patients/presentation/widgets/patient_list_controls.dart`, replace the
   top-level `Row`/`Wrap` layout in `build()` with a single `AppListControlBar(...)`, mapping:
   existing search `AppTextField` → `searchField`; existing scope `AppSegmentedControl` → `segmented`;
   the sort + last-visit trigger buttons → `trailing`; the chips built by `_buildFilterChips` →
   `activeFilters`.
4. Replace the bodies of `_buildSortMenu` and `_buildLastVisitMenu` with `AppFilterMenuPanel`
   configurations, keeping the same `PatientSortField` / `PatientLastVisitFilter` options and the same
   `onChanged` callbacks.
5. Delete the now-unused private layout helpers and any direct `AppPopover` wiring that
   `AppFilterMenuPanel` subsumes.
6. Add `import 'package:ai_clinic/core/ui/widgets/widgets.dart';` if not already present, and remove
   imports that become unused.
7. Visual regression: run the app, open `/patients`, and compare the control bar against
   `/invoices` (which already uses `AppListControlBar`) at the same window width — spacing and chip
   styling must match.
8. Run `cd frontend; dart analyze lib/features/patients` and `flutter test`.

---

## M2 — `patient_rpc_failure.dart` sits in `data/` but is consumed by presentation as a public contract

**Severity**: Medium

**Location**

- `frontend/lib/features/patients/data/patient_rpc_failure.dart` — declares the Patients-specific
  failure/error-code surface used to interpret RPC errors.
- `frontend/lib/features/patients/application/patient_rpc_messages.dart` — `patientMessageForRpc(...)`
  maps those codes to user strings; imported by presentation notifiers and dialogs.
- Presentation consumers importing the `data/` file directly include
  `presentation/providers/patient_registration_notifier.dart`,
  `presentation/providers/patient_edit_notifier.dart`,
  `presentation/pages/mrn_reassignment_dialog.dart`, and
  `presentation/widgets/patient_row_context_menu.dart`.

**Issue**

Presentation code imports a `data/`-layer file to catch and classify errors. Per
`docs/architecture/07-frontend.md`, Presentation depends on Domain (use cases + DTOs), not on Data;
the error vocabulary that a use-case can throw is part of the domain contract. The feature already has a
`domain/patient_exceptions.dart`, so the placement is inconsistent within the feature itself.

**Why it is a problem**

It is the third instance of the same layering inversion as C1 (presentation ↔ data coupling), which
collectively makes the `data/` layer non-replaceable: swapping the Supabase repository for a mock or a
different transport would require touching four presentation files. It also blurs which exceptions are
part of the public contract versus internal transport detail.

**Recommended architectural solution**

Move the failure type and its error codes into `domain/`, keeping `application/patient_rpc_messages.dart`
as the only place that turns them into strings. `data/patient_repository.dart` then imports the domain
failure type (a legal direction), and presentation imports only `domain/` and `application/`.

**Suggested implementation steps**

1. Move `frontend/lib/features/patients/data/patient_rpc_failure.dart` to
   `frontend/lib/features/patients/domain/patient_rpc_failure.dart`. Do not rename the classes.
2. If the moved file imports anything from `core/data/` (e.g. a base `RpcFailure`), leave that import —
   `core/` is shared infrastructure, not another feature's data layer. If it imports the Supabase SDK,
   remove that import and keep the type transport-agnostic.
3. Update the import path in `frontend/lib/features/patients/data/patient_repository.dart`.
4. Update the import path in `frontend/lib/features/patients/application/patient_rpc_messages.dart`.
5. Update the import path in the four presentation consumers listed above; find them all with
   `rg -n "patient_rpc_failure" frontend/lib frontend/test`.
6. Verify `rg -n "features/patients/data" frontend/lib/features/patients/presentation` returns nothing.
7. Run `cd frontend; dart analyze lib` and `flutter test test/unit/patients`.

---

## M3 — Patients owns appointment- and visit-status presentation mapping

**Severity**: Medium

**Location**

- `frontend/lib/features/patients/presentation/widgets/patient_visit_record_card.dart` — local status
  colour/label mapping for visit records, and visit-type labelling.
- `frontend/lib/features/patients/presentation/widgets/patient_upcoming_appointment_card.dart` (rendered
  from `patient_detail_page.dart` `_buildAppointmentsTabBody`) — local `AppointmentStatus` →
  colour/label mapping.
- The canonical mappings already exist in the owning features:
  `frontend/lib/features/appointments/domain/appointment_calendar_status_style.dart` and
  `frontend/lib/features/appointments/domain/appointment_status.dart` (with its label/`wireValue`
  extensions), plus the visits feature's own status presentation helpers.

**Issue**

Status → colour and status → label decisions for appointments and visits are duplicated inside Patients
widgets instead of being imported from the owning feature's published presentation helpers.

**Why it is a problem**

`AppointmentStatus` is actively churning — `docs/specs`/migrations show status transitions and the queue
model evolving (`appointment_status_transitions.dart`, `appointment_status_timeline.dart`) — so a
duplicate mapping in Patients silently falls behind, and the same appointment is rendered with a
different colour on the calendar than on the patient page. The user reads that as a data inconsistency.

**Recommended architectural solution**

Delete the local mappings and import the owning feature's helpers. If the appointments feature exposes
only a *domain* style object (`AppointmentCalendarStatusStyle`), use that; if the colour resolution needs
`BuildContext`, add a small published helper in
`frontend/lib/features/appointments/presentation/utils/appointment_status_presentation.dart` and use it
from both the calendar and the patient card. Note that after C2 these two cards should move to their
owning features anyway, which resolves this finding as a side effect — do C2 first if both are being
applied.

**Suggested implementation steps**

1. Run `rg -n "AppointmentStatus" frontend/lib/features/appointments/domain frontend/lib/features/appointments/presentation`
   and identify the single canonical label + style source.
2. In `frontend/lib/features/patients/presentation/widgets/patient_upcoming_appointment_card.dart`,
   delete the private status colour/label helpers and call the canonical source instead.
3. Repeat for `frontend/lib/features/patients/presentation/widgets/patient_visit_record_card.dart` using
   the visits feature's equivalent helper; if visits has none, create
   `frontend/lib/features/visits/presentation/utils/visit_status_presentation.dart` from the code being
   deleted and use it from both places.
4. Confirm no `switch` over `AppointmentStatus` or the visit status enum remains under
   `frontend/lib/features/patients`: `rg -n "case AppointmentStatus\." frontend/lib/features/patients`.
5. Run `cd frontend; dart analyze lib` and visually compare a single appointment's badge colour on
   `/appointments/calendar` and on the patient detail Appointments tab.

---

## M4 — Branch-name resolution lives in Patients and refetches the whole branch list

**Severity**: Medium

**Location**

`frontend/lib/features/patients/presentation/providers/active_branch_name_provider.dart` — provider
`activeBranchNameProvider`, which imports `features/clinic-management/data/branch_repository.dart` (a
cross-feature `data/` import, same class of violation as C2) and calls `listBranches(...)` to find the
active branch, returning only its display name. Consumed by patient registration/edit UI to show the
branch a patient is being created in.

**Issue**

A whole-list branch fetch is performed to obtain one name, from a provider that belongs in
clinic-management, reaching directly into that feature's repository.

**Why it is a problem**

It adds a second source of truth for "the active branch's name". Clinic-management already owns branch
state, so the two can disagree after a branch rename until this provider's cache is invalidated — and it
is invalidated by nothing in Patients. It also repeats the boundary violation pattern, so a boundary lint
cannot be enabled while it exists.

**Recommended architectural solution**

Move the provider to clinic-management and back it by that feature's existing branch state rather than a
fresh repository call.

**Suggested implementation steps**

1. Find clinic-management's existing branch state:
   `rg -n "branchesProvider|activeBranch" frontend/lib/features/clinic-management/presentation/providers`.
2. Create `frontend/lib/features/clinic-management/presentation/providers/active_branch_name_provider.dart`
   containing `activeBranchNameProvider`, implemented by selecting the active branch from that existing
   state (`ref.watch(...).valueOrNull?.firstWhereOrNull(...)`) instead of calling
   `branchRepositoryProvider.listBranches`.
3. Delete `frontend/lib/features/patients/presentation/providers/active_branch_name_provider.dart`.
4. Update all Patients consumers to the new import path:
   `rg -n "active_branch_name_provider" frontend/lib`.
5. Verify `rg -n "features/clinic-management/data" frontend/lib/features/patients` returns nothing
   (together with H5 this removes the last patients → clinic-management `data` edge).
6. Run `cd frontend; dart analyze lib`; manually rename a branch in clinic-management and confirm the
   Add-Patient dialog shows the new name without an app restart.

---

## M5 — Localization is applied to only a fraction of the Patients presentation layer

**Severity**: Medium

**Location**

Files that correctly use `context.l10n` (from `frontend/lib/core/l10n/`): `presentation/pages/patients_page.dart`
(partially), `presentation/add_patient/add_patient_form_fields.dart` (partially),
`presentation/utils/patient_field_validation.dart`, `application/patient_rpc_messages.dart`.

Files with hard-coded English user-facing strings include:

- `presentation/pages/patient_detail_page.dart` — e.g. `'Billing access required'` (line 379),
  `'No invoices yet'`, `'Documents'`, `'Appointments'`, tab labels and empty-state titles throughout
  `_buildBillingTabBody`, `_buildDocumentsTabBody`, `_buildAppointmentsTabBody`.
- `presentation/pages/mrn_reassignment_dialog.dart` — dialog title, helper text, button labels.
- `presentation/widgets/patient_row_context_menu.dart` — `'Open'`, `'Book appointment'`, `'Edit'`,
  `'Deactivate'` and the success toast text.
- `presentation/widgets/patient_invoice_card.dart`, `patient_document_card.dart`,
  `patient_visit_record_card.dart`, `patient_list_controls.dart`, `patient_table.dart`,
  `patient_picker.dart` — column headers, chip labels, empty states.

Roughly 7 of the 31 presentation files use `l10n`; the rest do not.

**Issue**

Two conventions coexist for user-facing text within one feature, with the majority of strings
untranslatable.

**Why it is a problem**

The app ships an l10n layer and the project targets Arabic/English (the shell has a locale switch and
`intl` is a direct dependency), so any untranslated string is a visible defect in the non-default locale
and an RTL layout risk. Mixed conventions also mean a translator pass cannot be scoped by file, and new
contributors copy whichever pattern they open first.

**Recommended architectural solution**

Complete the migration rather than adding more keys ad-hoc: move every user-facing literal in
`frontend/lib/features/patients/presentation/**` into the ARB files and access it via `context.l10n`.
Do it file-by-file so each step is independently reviewable, starting with the highest-traffic surfaces.

**Suggested implementation steps**

1. Enumerate the offenders: `rg -n "'[A-Z][a-z][^']{3,}'" frontend/lib/features/patients/presentation`
   and triage hits into "user-facing" vs "identifier/debug".
2. Locate the ARB source files (`rg --files -g "*.arb" frontend/lib` — typically
   `frontend/lib/core/l10n/arb/app_en.arb` and `app_ar.arb`) and note the existing key naming
   convention for patients keys (e.g. `patientsListTitle`).
3. For each file, in this order — `patient_detail_page.dart`, `patient_row_context_menu.dart`,
   `mrn_reassignment_dialog.dart`, `patient_table.dart`, `patient_list_controls.dart`,
   `patient_picker.dart`, then the three cards — add one ARB key per literal to **both** ARB files
   (Arabic may temporarily reuse the English text if no translation is available yet), then replace the
   literal with `context.l10n.<key>`.
4. Regenerate localizations: `cd frontend; flutter gen-l10n` (or `flutter pub run build_runner build`
   if the project generates them that way — check `frontend/l10n.yaml`).
5. Run `cd frontend; dart analyze lib/features/patients` after each file to catch missing keys early.
6. Smoke-test both locales: switch the app language from the shell and walk
   `/patients` → patient detail → all four tabs → Add patient → Edit patient → MRN reassignment.

---

## M6 — Registration and edit notifiers are near-duplicates and use the legacy `StateNotifier`

**Severity**: Medium

**Location**

- `frontend/lib/features/patients/presentation/providers/patient_registration_notifier.dart` (196 lines)
  — `PatientRegistrationState`, `PatientRegistrationNotifier extends StateNotifier<...>`, with
  `updateField`-style setters, `_validate()`, duplicate-check handling, and `submit()` (lines 188–201).
- `frontend/lib/features/patients/presentation/providers/patient_edit_notifier.dart` (259 lines) —
  `PatientEditState`, `PatientEditNotifier extends StateNotifier<...>`, with the same setters, the same
  validation, the same duplicate handling, plus `expectedUpdatedAt` optimistic-concurrency handling.
- Provider-type convention: `docs/architecture/07-frontend.md` prescribes `NotifierProvider` /
  `AsyncNotifierProvider` (Riverpod 2 generation) for mutable and async state; `StateNotifier` is the
  legacy API. Other Patients providers (`patient_list_notifier.dart`) share the same issue.

**Issue**

Roughly 90% of the two notifiers is identical: the same ~14 field setters, the same
`PatientFieldValidation` calls, the same `PatientDuplicateMatch` handling, the same
`RpcFailure → patientMessageForRpc` mapping. Only three things genuinely differ: the initial state
(empty vs hydrated from `PatientDetail`), the use case invoked (`createPatientUseCaseProvider` vs
`updatePatientUseCaseProvider`), and `expectedUpdatedAt`.

**Why it is a problem**

Every field added to the patient record must be added twice, in two files, with two validators — a change
that is easy to half-apply, and the resulting asymmetry (a field validated on create but not on edit) is
a data-integrity bug rather than a cosmetic one. The MRN work already shows this cost: MRN display had to
be threaded through both. Using the deprecated `StateNotifier` also blocks the codebase-wide Riverpod
generation migration and means these providers cannot use `ref.listenSelf`/`AsyncValue` ergonomics.

**Recommended architectural solution**

Extract the shared form state and behaviour once, and keep only the mode-specific parts separate.
Concretely: a single `PatientFormState` value class holding the fields + validation errors +
`submissionStatus` + `duplicateMatches`, and a single `PatientFormNotifier extends Notifier<PatientFormState>`
with all setters and `validate()`, then two thin subclasses (or one notifier parameterised by a
`PatientFormMode { create, edit }` family argument) that implement only `submit()`.

Recommended file layout:

- New `frontend/lib/features/patients/presentation/providers/patient_form_state.dart` —
  `PatientFormState` + `copyWith` + `PatientFormMode` enum.
- New `frontend/lib/features/patients/presentation/providers/patient_form_notifier.dart` —
  `PatientFormNotifier extends Notifier<PatientFormState>` with the setters, `validate()`, duplicate
  handling, and an abstract-ish `submit()` that switches on `state.mode`.

**Suggested implementation steps**

1. Create `patient_form_state.dart`. Copy the fields of `PatientEditState` (the superset — it has
   `expectedUpdatedAt`) into `PatientFormState`, add `final PatientFormMode mode;` and
   `final String? patientId;` (null for create), and write a complete `copyWith`.
2. Create `patient_form_notifier.dart` with `class PatientFormNotifier extends Notifier<PatientFormState>`.
   Move every field setter and `_validate()` from `patient_edit_notifier.dart` verbatim, plus the
   duplicate-match handling. Implement
   `PatientFormState build()` returning either an empty state (`mode == create`) or a state hydrated from
   an injected `PatientDetail`.
3. Register it as a family keyed on the mode+patientId:
   `final patientFormNotifierProvider = NotifierProvider.autoDispose.family<PatientFormNotifier, PatientFormState, PatientFormArgs>(PatientFormNotifier.new);`
   where `PatientFormArgs` is a small equatable record of `(mode, patientId, initialDetail)`.
4. Implement `Future<void> submit()` on the notifier with a single `switch (state.mode)`: `create` →
   `ref.read(createPatientUseCaseProvider)(CreatePatientInput(...))` then store `result.mrn` in state
   for the success toast; `edit` → `ref.read(updatePatientUseCaseProvider)(UpdatePatientInput(..., expectedUpdatedAt: state.expectedUpdatedAt!))`.
   Keep the existing `try / on RpcFailure` structure and duplicate-detection branch from
   `patient_edit_notifier.dart`.
5. Repoint `frontend/lib/features/patients/presentation/add_patient/add_patient_dialog.dart` and
   `add_patient_form_fields.dart` at `patientFormNotifierProvider(PatientFormArgs.create())`.
6. Repoint `frontend/lib/features/patients/presentation/edit_patient/edit_patient_dialog.dart` (and its
   form-fields file) at `patientFormNotifierProvider(PatientFormArgs.edit(detail))`.
7. Delete `patient_registration_notifier.dart` and `patient_edit_notifier.dart`.
8. Update `frontend/test/unit/patients/**` references; run `cd frontend; dart analyze lib` and
   `flutter test`.
9. Manual check: create a patient (confirm the MRN toast), then edit the same patient and confirm the
   stale-write path still surfaces the conflict message by editing the record from a second window first.

---

## M7 — Dead code and dead-end user actions

**Severity**: Medium

**Location**

1. `frontend/lib/features/patients/domain/patient_exceptions.dart` — the exception types declared here
   are not thrown anywhere in the feature; all error handling flows through
   `data/patient_rpc_failure.dart` + `application/patient_rpc_messages.dart` instead.
   Verify with `rg -n "PatientNotFoundException|PatientValidationException" frontend/lib`
   (adjust to the actual class names in the file).
2. Route-based patient edit dead end — `frontend/lib/app/app_routes.dart` defines a patient-edit route
   and `frontend/lib/app/router.dart` registers it, but the registered builder resolves to a placeholder
   scaffold rather than `EditPatientDialog`. Meanwhile
   `frontend/lib/features/patients/presentation/widgets/patient_row_context_menu.dart` `'edit'` entry
   (lines 44–51) navigates to that route, so the row Edit action lands on a placeholder, whereas
   `patient_detail_page.dart` `_openEditPatient` (called from line 507) correctly opens the dialog.
3. `frontend/lib/features/patients/presentation/models/patient_list_filters.dart` — `PatientTableRow`
   carries fields that no column renders after the MRN column work; confirm against
   `presentation/widgets/patient_table.dart` before deleting any.
4. Unused local in `patient_detail_page.dart` `_buildBillingTabBody` — see H2 step 2.

**Issue**

Three unreachable or misleading constructs: an exception hierarchy that is never thrown, a menu action
that navigates to a placeholder page, and view-model fields with no consumer.

**Why it is a problem**

The edit dead end is a user-visible functional bug: the same logical action succeeds from the detail page
and fails from the list row, and the failure mode is a blank placeholder with no error, so it reads as a
broken build. The unused exception hierarchy is an active trap — a future contributor will `throw` one of
those types from a use case and no `catch` will handle it, because every call site catches `RpcFailure`
only.

**Recommended architectural solution**

Make the list-row Edit action use the same dialog as the detail page (dialog, not route — patient editing
is modal everywhere else in the app), and delete the unused exception types and view-model fields. Remove
the placeholder edit route entirely so no navigation target can regress to it.

**Suggested implementation steps**

1. In `frontend/lib/features/patients/presentation/widgets/patient_row_context_menu.dart`, change the
   `'edit'` `onSelect` from a route navigation to: read the patient detail (or pass the already-loaded
   `PatientTableRow`'s `patientId`), then `await EditPatientDialog.show(context, patientId: id)` —
   mirror exactly what `_openEditPatient` in `patient_detail_page.dart` does, then call
   `ref.read(patientListNotifierProvider.notifier).reload()` on success.
2. If `EditPatientDialog.show` requires a fully-loaded `PatientDetail`, await
   `ref.read(patientDetailProvider(id).future)` first and show `AppToast` on failure.
3. Delete the patient-edit route constant from `frontend/lib/app/app_routes.dart` and its `GoRoute`
   registration (including the placeholder builder) from `frontend/lib/app/router.dart`.
4. Remove any `goPatientEdit`-style helper from `frontend/lib/app/navigation/app_navigator.dart` and fix
   its callers (should be only the context menu, fixed in step 1).
5. Run `rg -n "PatientNotFound|PatientValidation|patient_exceptions" frontend/lib frontend/test`. If
   there are genuinely no throw sites and no test references, delete
   `frontend/lib/features/patients/domain/patient_exceptions.dart` and its imports.
6. For each field on `PatientTableRow` in `presentation/models/patient_list_filters.dart`, grep the field
   name across `frontend/lib/features/patients/presentation`. Delete only fields with zero consumers, and
   remove the corresponding assignments in the mapper inside
   `presentation/providers/patient_list_notifier.dart`. Do **not** delete `mrn` — it is rendered by the
   MRN column and required by `docs/specs/016-patient-mrn-field/contracts/mrn-surfaces.md`.
7. Run `cd frontend; dart analyze lib` and `flutter test`.
8. Manual check: from `/patients`, right-click a row → Edit, confirm the edit dialog opens, save a change,
   and confirm the list refreshes with the new value.

---

## Applying these findings

Suggested order, chosen so that later steps do not fight earlier ones:

1. **H2** and **M7 step 1–4** first — smallest diffs, immediate user-visible fixes.
2. **C3** then **H5** — H5 deletes one of C3's call sites, so doing C3 first keeps each step compiling.
3. **C1** — pure file moves, unblocks any boundary lint.
4. **C2** then **H3** then **M3** — H3 and M3 are largely subsumed by C2's moves; doing C2 first avoids
   moving the same code twice.
5. **M2**, **M4** — remaining boundary/layering moves.
6. **H1** — RBAC gating; do after C2 so the detail page is already smaller.
7. **H4**, **M6**, **M1**, **M5** — provider/state and UI-consistency refactors, largest and most
   test-sensitive, best done last and individually.

After the set is complete, the following two commands should both return no results, and are worth adding
to CI as a boundary check:

```bash
rg -n "features/patients/presentation" frontend/lib/features/patients/domain frontend/lib/features/patients/data
rg -n "import 'package:ai_clinic/features/(appointments|visits|billing|clinic-management)/(data|presentation)/" frontend/lib/features/patients
```

