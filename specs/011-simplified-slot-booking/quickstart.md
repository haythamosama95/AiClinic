# Quickstart: Simplified Slot Booking

Implementation and verification for **011**. Requires **V1-4** (`specs/005-appointment-management`), **V1-3** patients, **V1-2** staff/branches.

## 1. Apply database migration

From repository root with local Supabase running:

```bash
cd backend
supabase migration up
```

Key migration:

- `backend/supabase/migrations/20260627120000_simplified_slot_booking.sql` — per-doctor overlap + `get_simplified_booking_slots`

## 2. Run backend verification

```bash
./backend/tests/run_all_backend_tests.sh
```

Simplified booking subset (after implementation):

```bash
psql "$DATABASE_URL" -f backend/tests/simplified_slot_booking.sql
```

Covers:

- Slot RPC returns `available`, `alternate_doctors_available`, `fully_unavailable`
- Per-doctor overlap: two doctors same time allowed; same doctor blocked
- Date validation (today..+90)
- Settings RPC unchanged

## 3. Run the Flutter client

```bash
cd frontend
flutter pub get
flutter run -d windows
```

### Settings

1. Sign in as admin or role with settings access
2. Open **Settings → Clinic setup**
3. Set **default appointment duration** (e.g. 15 minutes) for a branch
4. Save and reopen simplified booking — blocks should match duration

### Simplified booking (header path)

1. Sign in as receptionist (`appointments.create`)
2. Open **Appointments** calendar
3. Tap **Book Appointment** (header) — **not** an empty calendar slot
4. Step 1: select patient and preferred doctor → Next
5. Step 2: verify day strip centers today; select an available block
6. Confirm summary card shows date, time range, doctor
7. Submit — appointment appears on calendar

### Alternate doctors

1. Book doctor A at a time slot via calendar
2. Start simplified booking with preferred doctor A
3. Select same time — block shows alternate-doctors styling
4. Tap → choose doctor B → slot selects; confirm creates for doctor B

### Calendar path unchanged

1. Tap empty calendar slot
2. Verify legacy `AppointmentBookingSheet` opens (duration override still available)

## 4. Automated tests

```bash
cd frontend
flutter test test/unit/appointments/simplified_booking_slot_test.dart
flutter test test/widget/appointments/
```

## 5. Regression checks

- [ ] Header **Book Appointment** opens two-step flow
- [ ] Calendar slot tap opens legacy sheet
- [ ] No duration override in simplified flow
- [ ] Day navigation stops at 90 days
- [ ] Past blocks not selectable today
- [ ] `SCHEDULE_CONFLICT` refreshes grid after race
- [ ] Users without `appointments.create` cannot open flow

## 6. Spec traceability

| Spec FR | Quickstart step |
| ------- | --------------- |
| FR-002 | §3 Settings |
| FR-004–004d | §3 Alternate doctors |
| FR-009a/b | §3 Simplified + Calendar paths |
| FR-003a | §3 no duration field in step 2 |
| FR-006a | §3 day strip 90-day cap |

**Next**: `/speckit-tasks` for `tasks.md`.
