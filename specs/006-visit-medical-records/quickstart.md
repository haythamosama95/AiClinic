# Quickstart: Visits and Medical Records

Implementation and verification for **V1-5**. Requires **V1-4** (`specs/005-appointment-management`), **V1-3**, **V1-2**, and **V1-1**.

## 1. Apply database migrations

From repository root with local Supabase running:

```bash
cd backend
supabase migration up
```

Key migration (planned):

- `backend/supabase/migrations/20260531180000_visit_medical_records.sql` — visit domain tables, storage bucket, RLS, RPCs, permission seed extension, appointment status change

## 2. Run backend verification

```bash
./backend/tests/run_all_backend_tests.sh
```

Visit subset:

```bash
./backend/tests/run_visit_medical_records_tests.sh
```

Covers:

- Create visit from `checked_in` (appointment advances) and `in_progress`
- Reject visit from `scheduled` / duplicate visit
- Doctor selection when appointment has no doctor
- SOAP save, partial save, stale concurrency (`STALE_SOAP`)
- Complete visit with SOAP → appointment `completed`
- Reject complete with empty SOAP; reject manual `in_progress` → `completed` on appointment
- Treatment plan CRUD + soft delete
- Attachment register + download authorization (clinical full; lab own-only)
- Cross-org / cross-branch denial
- Patient visit list metadata vs clinical detail permissions

## 3. Run the Flutter client

```bash
cd frontend
flutter pub get
flutter run -d windows
```

1. Sign in as **doctor** (or administrator with `visits.create` / `visits.edit_soap`)
2. Open **Appointments** → advance appointment to **checked in** or **in progress**
3. Tap **Create visit** (or **Open visit** if already created)
4. If appointment has no doctor, select doctor from branch list
5. Enter SOAP sections → **Save** → reload and verify persistence
6. Add treatment plan lines; upload PDF, DOCX, and photo attachments
7. **Submit visit** → verify linked appointment shows **completed**
8. Open **Patients** → patient profile → **Visit history** list (replaces placeholder)
9. Sign in as **receptionist** → verify visit metadata visible, SOAP/attachments hidden
10. Sign in as **lab staff** → upload attachment; download own file succeeds; others' files denied

## 4. Regression checks

- Appointment queue/calendar no longer offers **Complete** from `in_progress` — completion via visit submit only
- Patients module: `PatientVisitsPlaceholder` replaced with live history
- Auth, branch switcher, appointment booking flows intact
- V1-4 appointment tests updated for new completion path

## 5. Automated Flutter tests

```bash
cd frontend
python3 tool/run_all_tests.py
```

Or targeted:

```bash
flutter test test/unit/visits/
flutter test test/widget/visits/
flutter test test/integration/visits/
```

## 6. Clinical staff notes

- Visits are created **explicitly** from checked-in or in-progress appointments — not auto-created on check-in.
- At least **one SOAP section** must contain text before submit; treatment plans and attachments are optional.
- Completing an appointment requires **submitting the visit**, not the old queue **Complete** button.
- Allowed attachment types: **PDF**, **Word (DOCX)**, **JPEG/PNG photos** — max **25 MB** each.

## 7. Operator verification log

| Step                | Command / action                                                                                                                                           | Expected                                                 |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Migrations          | `cd backend && supabase migration up`                                                                                                                      | Visit migration + storage bucket applied                 |
| Backend harness     | `./backend/tests/run_visit_medical_records_tests.sh`                                                                                                       | CRUD + RLS visit suites pass                             |
| Flutter visit tests | `cd frontend && flutter test test/unit/visits/ test/widget/visits/ test/integration/visits/`                                                               | Phase 9 acceptance + guards green                        |
| Flutter regression  | `flutter test test/integration/patients/patient_management_acceptance_test.dart test/integration/appointments/appointment_management_acceptance_test.dart` | Patient/appointment smoke groups pass                    |
| Manual (clinical)   | quickstart §3 on Windows client                                                                                                                            | Full workflow through visit submit completes appointment |
| Manual (lab)        | lab staff upload/download own attachment                                                                                                                   | Own download OK; others denied                           |

**Phase 9 operator notes (2026-06-01)**:

- Automated acceptance maps spec cases 1–18: UI flows in `test/integration/visits/visit_medical_records_acceptance_test.dart`; cases 3–4, 6b, 9b, 10, 15–16 asserted against `backend/tests/visit_medical_records_*.sql`.
- Appointment queue no longer exposes **Complete** from `in_progress`; completion is visit submit only (`complete_visit` RPC).
- Receptionist retains `patients.view` visit history metadata; SOAP and documentation routes require `visits.create` / `visits.edit_soap`.

**Permission reminder**: Visit creation requires `visits.create`; SOAP/submit requires `visits.edit_soap`; lab upload requires `visits.upload_attachment`; visit history list requires `patients.view`.
