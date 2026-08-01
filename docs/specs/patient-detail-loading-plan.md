# Implementation Plan: Wire Patient Detail Loading (Approach A completion)

## Context / Decision

The patients feature already uses the correct data-loading strategy: a lightweight
list DTO (`search_patients` → `PatientListItem`) for the table, and a full-profile
RPC (`get_patient` → `PatientDetail`) for the detail view. **Do not change this
split.** The list query is expensive (two LATERAL joins per row for last-visit /
next-appointment), so it must stay paginated and minimal. The detail record carries
fields the list never fetches (`notes`, `marital_status`, audit metadata), so the
detail view MUST fetch its own data — it cannot be served from the list row.

The only gap: `PatientDetailDrawer` is a stub that reuses the in-memory list row and
never calls `get_patient`. This plan wires the existing (already-tested) `getPatient`
use case into the drawer.

**Scope:** frontend only. No backend/migration/RPC changes. No model changes.

---

## Goal

When a user taps a patient row, the drawer:
1. Opens instantly, showing header info already known from the list row
   (full name, truncated id, phone, age/gender) as an immediate skeleton/header.
2. Asynchronously calls `get_patient(id)` to load the full profile.
3. Renders full fields (`notes`, `maritalStatus`, branch, created/updated, createdBy)
   once loaded, with loading and error states.

---

## Files to read first (context)

- `frontend/lib/features/patients/presentation/widgets/patient_detail_drawer.dart` (the stub to replace)
- `frontend/lib/features/patients/domain/patient_detail.dart` (target model)
- `frontend/lib/features/patients/data/patient_repository.dart` (`getPatient`)
- `frontend/lib/features/patients/presentation/providers/patient_use_case_providers.dart` (`getPatientUseCaseProvider`)
- `frontend/lib/features/patients/presentation/providers/patient_list_notifier.dart` (provider/Riverpod patterns to mirror)
- `frontend/lib/features/patients/presentation/models/patient_list_filters.dart` (`PatientTableRow`)
- Existing tests under `frontend/test/.../patients/` that already cover `getPatient`

---

## Tasks

### Task 1 — Add a detail provider
Create `frontend/lib/features/patients/presentation/providers/patient_detail_provider.dart`.

- Add a Riverpod `FutureProvider.family<PatientDetail, String>` (or `AsyncNotifier`
  family, matching the style used in `patient_list_notifier.dart`) keyed by patient id.
- It calls `ref.read(getPatientUseCaseProvider)(patientId)`.
- Mirror existing error mapping / logging conventions used in the list notifier.

Acceptance: provider compiles, returns `AsyncValue<PatientDetail>`, is auto-disposed.

### Task 2 — Rebuild `PatientDetailDrawer` to consume the provider
Edit `patient_detail_drawer.dart`.

- Convert to a `ConsumerWidget` (or wrap with `Consumer`).
- Keep `PatientTableRow row` for the instant header (name, `displayId`, phone,
  ageGenderLabel) so the drawer feels instant.
- Watch the detail provider with `row.item.id`.
- Render three states using existing app widgets:
  - **loading**: header + skeleton/spinner for the body.
  - **error**: header + inline error with a retry action (`ref.invalidate(provider)`).
  - **data**: full profile section.
- Detail body fields to show (from `PatientDetail`): `phone`, `dateOfBirth` (+ computed
  age), `gender`, `maritalStatus`, `branchName`, `notes`, `createdAt`, `updatedAt`,
  `createdByDisplay`. Use `'—'` for nulls, consistent with the table.
- Remove the "coming soon" placeholder.

Acceptance: tapping a row shows header immediately, then full data; null fields render `—`.

### Task 3 — Reuse formatting helpers
- Reuse the same date/age formatting used in `patients_table.dart` (extract a shared
  helper if duplicated, e.g. into an existing patients presentation util). Do not
  introduce a second age-calculation implementation.

### Task 4 — Tests
Add `frontend/test/.../patient_detail_drawer_test.dart` (mirror existing widget-test setup).

- Override `getPatientUseCaseProvider` with a fake.
- Test: loading state renders header from row; success renders `notes`/`maritalStatus`;
  error renders retry; retry re-invokes the use case.

Acceptance: `flutter test` passes for the new + existing patient tests.

### Task 5 — Verify
- Run `flutter analyze` and `flutter test` in `frontend/`.
- Confirm no change to `search_patients` payload or `PatientListItem` (list stays lean).

---

## Explicitly OUT of scope (do not do)
- Do NOT add `notes`/`marital_status`/audit fields to `search_patients` or `PatientListItem`.
- Do NOT prefetch full records for the whole list.
- Do NOT change RPCs, migrations, or the `/patients/:id` route (separate task).
- Do NOT change pagination/search behavior.

## Optional follow-ups (separate tickets, not this plan)
- Parse `marital_status` in `PatientListItem.fromRow` only if a list column needs it.
- Implement the real `/patients/:patientId` route page (reuse the detail provider).
- Fix toolbar hint advertising "ID" search that isn't implemented.
