# Quickstart: Appointment Management

Implementation and verification for **V1-4**. Requires **V1-3** (`specs/004-patient-management`), **V1-2**, and **V1-1**.

## 1. Apply database migrations

From repository root with local Supabase running:

```bash
cd backend
supabase migration up
```

Expected new migration:

- `backend/supabase/migrations/20260526140000_appointment_management.sql` — enums, `appointments`, RLS, settings helpers, appointment RPCs

## 2. Run backend verification

```bash
./backend/tests/run_appointment_management_tests.sh
```

Covers:

- Planned create + conflict rejection
- Walk-in auto-slot in gap; `NO_SLOT_AVAILABLE` when full
- Status transitions; invalid skip rejected
- Reschedule `scheduled` only
- Cancel / no-show frees slot
- Cross-org / cross-branch denial
- Default duration from `app_settings`

## 3. Run the Flutter client

```bash
cd frontend
flutter pub get
flutter run -d windows
```

1. Sign in as receptionist (or role with `appointments.create`)
2. Set **default appointment duration** in organization settings (e.g. 20 minutes)
3. Open **Appointments** from shell
4. **Book planned** appointment — confirm duration pre-fill; try custom duration
5. **Register walk-in** — confirm auto time in gap, status `checked_in`, queue order by time
6. Open **Today's queue** — confirm sort by `start_time`; optional second client for live update
7. **Check in** planned → **Start** → **Complete**
8. **Reschedule** a `scheduled` appointment
9. **Cancel** and **no-show** scenarios
10. Doctor schedule filter — only that doctor's rows

## 4. Regression checks

- Patients module unchanged except patient picker on booking forms
- Auth, branch switcher, settings flows intact

## 5. Automated Flutter tests

```bash
cd frontend
flutter test test/unit/appointments/
flutter test test/widget/appointments/
flutter test test/integration/appointments/appointment_management_acceptance_test.dart
```

## 6. Desk staff notes

- Queue order follows **appointment time**, not arrival order alone.
- Walk-ins get a **time slot** automatically; they appear among booked patients at that time.
- Default visit length is set in **settings**; each booking can use a different length if needed.
- Completing an appointment does **not** open a visit chart yet (V1-5).

## 7. Operator verification log (Phase 10)

Verified during V1-4 polish (automated unless noted):

| Step                | Command / action                                                                | Expected                                                                      |
| ------------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Migrations          | `cd backend && supabase migration up`                                           | `20260526140000_appointment_management.sql` applied                           |
| Backend harness     | `./backend/tests/run_appointment_management_tests.sh`                           | CRUD + RLS pass (conflict, walk-in slot, transitions, reschedule, cancel)     |
| Flutter unit/widget | `cd frontend && flutter test test/unit/appointments/ test/widget/appointments/` | All appointment tests green                                                   |
| Flutter integration | `flutter test test/integration/appointments/`                                   | US1/US2 smoke + `appointment_management_acceptance_test.dart` (cases 4–14 UI) |
| Full frontend suite | `python3 tool/run_all_tests.py` from `frontend/`                                | Full regression including patients/settings smoke                             |
| Manual (desk)       | quickstart §3 steps 1–10 on Windows client                                      | Calendar, queue, booking, walk-in, status, reschedule, cancel behave per spec |

**Permission reminder**: Viewing appointment screens requires `appointments.create` and/or `appointments.cancel`; booking and walk-in require `appointments.create` only.

**Realtime**: If the queue shows a degraded banner, use **Refresh** — list data still comes from `list_appointments` RPC; Realtime is optional UX.
