# Quickstart: Appointment Management

Implementation and verification for **V1-4**. Requires **V1-3** (`specs/004-patient-management`), **V1-2**, and **V1-1**.

## 1. Apply database migrations

From repository root with local Supabase running:

```bash
cd backend
supabase migration up
```

Key migrations:

- `backend/supabase/migrations/20260526140000_appointment_management.sql` — enums, `appointments`, RLS, RPCs
- `backend/supabase/migrations/20260528160000_appointment_confirmed_remove_walkin.sql` — `confirmed` status; planned-only booking
- `backend/supabase/migrations/20260531120000_remove_appointment_walk_in_type.sql` — `appointment_type` enum is `planned` only

## 2. Run backend verification

```bash
./backend/tests/run_all_backend_tests.sh
```

Appointment subset:

```bash
./backend/tests/run_appointment_management_tests.sh
```

Covers:

- Planned create + conflict rejection
- Status transitions including `confirmed` step; invalid skip rejected
- Reschedule `scheduled` only
- Cancel / no-show from `scheduled`, `confirmed`, `checked_in`
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
4. **Book appointment** — confirm duration pre-fill; try custom duration
5. Open **Today's queue** — confirm sort by `start_time`
6. **Confirm** (phone) → **Check in** → **Start** → **Complete**
7. **Reschedule** a `scheduled` appointment (before confirmation)
8. **Cancel** from `confirmed` when patient does not confirm; **no-show** scenarios
9. Doctor schedule filter — only that doctor's rows

## 4. Regression checks

- Patients module unchanged except patient picker on booking forms
- Auth, branch switcher, settings flows intact

## 5. Automated Flutter tests

```bash
cd frontend
python3 tool/run_all_tests.py
```

Or targeted:

```bash
flutter test test/unit/appointments/
flutter test test/widget/appointments/
flutter test test/integration/appointments/
```

## 6. Desk staff notes

- Queue order follows **appointment time**.
- After booking, reception **calls the patient** and taps **Confirm**; on arrival tap **Check in**.
- If the patient does not confirm, **Cancel** from `confirmed`.
- Default visit length is set in **settings**; each booking can use a different length if needed.
- Completing an appointment does **not** open a visit chart yet (V1-5).

## 7. Operator verification log (Phase 10)

| Step            | Command / action                               | Expected                                                           |
| --------------- | ---------------------------------------------- | ------------------------------------------------------------------ |
| Migrations      | `cd backend && supabase migration up`          | Appointment migrations applied incl. `confirmed`                   |
| Backend harness | `./backend/tests/run_all_backend_tests.sh`     | All suites pass                                                    |
| Flutter suite   | `cd frontend && python3 tool/run_all_tests.py` | Unit green; boundary includes appointment lifecycle                |
| Manual (desk)   | quickstart §3 on Windows client                | Book, confirm, check-in, queue, reschedule, cancel behave per spec |

**Permission reminder**: Viewing appointment screens requires `appointments.create` and/or `appointments.cancel`; booking requires `appointments.create` only.

**Realtime**: If the queue shows a degraded banner, use **Refresh** — list data still comes from `list_appointments` RPC; Realtime is optional UX.
