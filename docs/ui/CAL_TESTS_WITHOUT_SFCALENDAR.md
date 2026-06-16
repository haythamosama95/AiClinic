# CAL-* tests implementable without `SfCalendar`

Companion to [QA_REVIEW_ui-008-calendar.md](./QA_REVIEW_ui-008-calendar.md).

These CAL-* tests can be implemented **without** mounting `SfCalendar` or `AppointmentCalendarPage`. Use this document to implement the first wave of the calendar test suite while avoiding Syncfusion widget-harness constraints (`pumpAndSettle`, bounded pumps, `--concurrency 1`).

**Totals:** 52 tests fully implementable without `SfCalendar` · 3 partial (sheet/logic only) · **~55 of 119** in the first wave.

---

## Tier 1 — Backend SQL / RPC (no Flutter)

| Test ID | Section | Priority | Area                 | Suggested target file                                      | What to test                                                         |
| ------- | ------- | -------- | -------------------- | ---------------------------------------------------------- | -------------------------------------------------------------------- |
| CAL-J01 | J       | Critical | Duration bounds fn   | `backend/tests/appointment_calendar_backend_integrity.sql` | `assert_appointment_duration_bounds(4)` → `INVALID_DURATION`         |
| CAL-J02 | J       | Critical | Duration 241         | same                                                       | `assert_appointment_duration_bounds(241)` → no error                 |
| CAL-J03 | J       | High     | get_settings shape   | same                                                       | `get_appointment_settings` has no `max_duration_minutes`             |
| CAL-J04 | J       | Critical | Create >240          | same                                                       | `create_appointment` 300 min succeeds                                |
| CAL-J05 | J       | Critical | Reschedule >240      | same                                                       | Reschedule to 300 min succeeds                                       |
| CAL-J06 | J       | Critical | Reschedule parity    | same                                                       | Reschedule outside hours → `INVALID_INPUT`                           |
| CAL-J07 | J       | Critical | Patient same day     | same                                                       | Reschedule same day → `PATIENT_ALREADY_BOOKED_SAME_DAY`              |
| CAL-J08 | J       | Medium   | Audit log            | same                                                       | Reschedule writes `audit_log` entry                                  |
| CAL-J09 | J       | High     | Fetch window day     | same                                                       | `list_appointments` UTC day bounds                                   |
| CAL-J10 | J       | High     | Fetch window month   | same                                                       | `list_appointments` UTC month bounds                                 |
| CAL-A06 | A       | Critical | Permissions          | same or existing RPC test harness                          | `reschedule_appointment` without `appointments.create` → `FORBIDDEN` |
| CAL-H07 | H       | High     | Max duration removed | same                                                       | Resize to >240 min via RPC succeeds                                  |

---

## Tier 2 — Dart unit tests (domain / provider / repository)

| Test ID | Section | Priority | Area                 | Suggested target file                                                            | What to test                                              |
| ------- | ------- | -------- | -------------------- | -------------------------------------------------------------------------------- | --------------------------------------------------------- |
| CAL-B06 | B       | High     | Refresh              | `frontend/test/unit/appointments/appointment_calendar_provider_test.dart`        | Branch filter change triggers new fetch                   |
| CAL-B07 | B       | High     | Auth change          | same                                                                             | `activeBranchId` change resets filters                    |
| CAL-G05 | G       | Critical | Confirmed appt       | `frontend/test/unit/appointments/appointment_reschedule_validation_test.dart`    | `validateMove` rejects confirmed status                   |
| CAL-G06 | G       | Critical | Overlap              | same                                                                             | Overlap → validation error                                |
| CAL-G07 | G       | Critical | Outside hours        | same                                                                             | Outside working hours → error                             |
| CAL-G08 | G       | High     | Same-day patient     | same                                                                             | Same-day patient conflict                                 |
| CAL-G09 | G       | High     | Doctor resource move | same                                                                             | Cross-doctor move rejected                                |
| CAL-G15 | G       | Critical | Server conflict      | same + mocked repo                                                               | Client validation passes; RPC returns `SCHEDULE_CONFLICT` |
| CAL-H03 | H       | Critical | Min 5 min            | `frontend/test/unit/appointments/appointment_reschedule_validation_test.dart`    | Duration < 5 min blocked                                  |
| CAL-H04 | H       | Critical | Extend into overlap  | same                                                                             | Extend into adjacent appt blocked                         |
| CAL-H06 | H       | Medium   | No-op resize         | same                                                                             | Resize back to original → no-op                           |
| CAL-I01 | I       | Medium   | Status colors        | `frontend/test/unit/appointments/appointment_calendar_display_test.dart`         | `statusColor` mapping per status                          |
| CAL-I02 | I       | Medium   | Doctor name          | same                                                                             | Doctor name in tile notes/subtitle                        |
| CAL-I07 | I       | High     | Hidden appts         | same or provider test                                                            | `filterVisibleAppointments` hides out-of-hours            |
| CAL-K06 | K       | High     | Contract settings    | `frontend/test/unit/appointments/appointment_settings_test.dart`                 | JSON without `max_duration_minutes` parses; no crash      |
| CAL-L04 | L       | High     | Repository boundary  | `frontend/test/unit/appointments/appointment_repository_test.dart` (or existing) | 4 min duration → client `INVALID_INPUT` before RPC        |
| CAL-M11 | M       | Medium   | Midnight span        | `appointment_reschedule_validation_test.dart` + booking validation               | Hours near midnight handled                               |
| CAL-M12 | M       | High     | Null doctor overlap  | `appointment_reschedule_validation_test.dart`                                    | Two unassigned appts overlap detected                     |
| CAL-E17 | E       | High     | Long duration        | booking sheet unit + repo/RPC mock                                               | Create >240 min via sheet succeeds (no 240 cap)           |

### Extend existing unit files (do not duplicate)

| Existing file                                               | CAL IDs to map here                            |
| ----------------------------------------------------------- | ---------------------------------------------- |
| `appointment_calendar_period_test.dart`                     | Period/window helpers (client side of J09/J10) |
| `appointment_calendar_data_source_test.dart`                | DataSource mapping (supports G/H indirectly)   |
| `appointment_calendar_drag_reschedule_test.dart` (planned)  | G02 snap-to-grid logic if extracted from page  |
| `appointment_calendar_resize_section_h_test.dart` (planned) | H05 resize edge logic if unit-testable         |

---

## Tier 3 — Isolated widget tests (no full calendar page)

Mount `AppointmentBookingSheet`, `AppointmentRescheduleConfirmDialog`, or `AppClockTimeField` only.

| Test ID | Section | Priority | Area                 | Suggested target file                                                               | What to test                                          |
| ------- | ------- | -------- | -------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------- |
| CAL-A04 | A       | Critical | Permissions          | `frontend/test/widget/appointments/appointment_booking_sheet_test.dart`             | Create permission: valid submit → success toast       |
| CAL-E03 | E       | High     | Settings load        | same                                                                                | Default/min duration from mocked `getSettings`        |
| CAL-E04 | E       | High     | Settings error       | same                                                                                | Settings RPC fail → error + retry                     |
| CAL-E05 | E       | Critical | Patient search       | same                                                                                | 3+ chars → debounced results; select patient          |
| CAL-E06 | E       | Medium   | Patient min query    | same                                                                                | 1–2 chars → no RPC                                    |
| CAL-E07 | E       | High     | No patient           | same                                                                                | Submit without patient → validation message           |
| CAL-E08 | E       | Critical | Past start time      | same                                                                                | Past start → error                                    |
| CAL-E09 | E       | Critical | Outside hours        | same                                                                                | Outside branch hours → error                          |
| CAL-E10 | E       | High     | Min duration         | same                                                                                | <5 min → duration error                               |
| CAL-E12 | E       | Critical | Schedule conflict    | same                                                                                | `SCHEDULE_CONFLICT` inline; form stays open           |
| CAL-E13 | E       | Medium   | Dismiss scrim        | same                                                                                | Tap outside → closes; no create                       |
| CAL-E14 | E       | High     | Double submit        | same                                                                                | Rapid double-click → single create                    |
| CAL-E15 | E       | High     | Doctor optional      | same                                                                                | “No doctor assigned” → null `doctorId`                |
| CAL-G04 | G       | High     | Cancel dialog        | `frontend/test/widget/appointments/appointment_reschedule_confirm_dialog_test.dart` | Cancel → revert callback / no confirm                 |
| CAL-G14 | G       | High     | Edit times in dialog | same                                                                                | Change start/end → re-validation before confirm       |
| CAL-K02 | K       | Critical | Offline book         | `appointment_booking_sheet_test.dart`                                               | Network fail on submit → user error                   |
| CAL-K04 | K       | Medium   | Refresh during book  | `appointment_booking_sheet_test.dart`                                               | Provider refresh while sheet open → sheet still works |
| CAL-M04 | M       | Medium   | Back button          | `appointment_booking_sheet_test.dart`                                               | Back/pop → sheet closes gracefully                    |
| CAL-L01 | L       | High     | AppClockTimeField    | `frontend/test/regression/appointments/calendar_section_l_regression_test.dart`     | Parent value change → field updates                   |

---

## Tier 4 — Regression / integration without calendar UI

| Test ID | Section | Priority | Area                  | Suggested target file                                                           | What to test                               |
| ------- | ------- | -------- | --------------------- | ------------------------------------------------------------------------------- | ------------------------------------------ |
| CAL-L02 | L       | Critical | Appointments list RPC | `frontend/test/regression/appointments/calendar_section_l_regression_test.dart` | List page / RPC unchanged by calendar work |
| CAL-L03 | L       | Medium   | Dev seed              | seed script test or manual doc                                                  | `dev_clinic_seed_*` schedule compatible    |
| CAL-L06 | L       | Medium   | Permission service    | existing `permission_service_appointments_test`                                 | All permission tests still pass            |

---

## Partial — implement now; calendar needed for full CAL-ID

| Test ID | Section | Without `SfCalendar`                             | Still needs calendar for               |
| ------- | ------- | ------------------------------------------------ | -------------------------------------- |
| CAL-E11 | E       | Sheet submit → RPC success, dialog closes, toast | “calendar refreshes; new tile visible” |
| CAL-G10 | G       | Confirm dialog + mocked RPC error → toast        | “calendar reverted” on grid            |
| CAL-G03 | G       | `validateMove` no-op when same slot (unit)       | Widget drop gesture on grid            |

---

## Sections with no no-`SfCalendar` tests

| Section              | Tests            | Notes                                              |
| -------------------- | ---------------- | -------------------------------------------------- |
| **C** — View modes   | C01–C11 (all 11) | View tabs, grid, swipe — all need mounted calendar |
| **D** — Filtering    | D01–D08 (all 8)  | Filter popover lives on calendar chrome            |
| **F** — Detail sheet | F01–F03 (all 3)  | Tile tap on calendar grid                          |

---

## Verification commands

```bash
cd frontend

flutter test \
  test/unit/appointments/appointment_calendar_* \
  test/unit/appointments/appointment_reschedule_validation_test.dart \
  test/unit/appointments/appointment_settings_test.dart \
  test/widget/appointments/appointment_booking_sheet_test.dart \
  test/widget/appointments/appointment_reschedule_confirm_dialog_test.dart \
  test/regression/appointments/calendar_* \
  --concurrency 1

# Backend (Tier 1)
psql -f backend/tests/appointment_calendar_backend_integrity.sql
./backend/tests/run_appointment_management_tests.sh
```

---

## Implementation order (suggested)

1. **Tier 1** — Backend SQL (J + A06 + H07): highest confidence, no Flutter harness.
2. **Tier 2** — Unit tests on validation, display, provider: extend existing `appointment_*_test.dart` files.
3. **Tier 3** — Booking sheet + confirm dialog widget tests: shared stubs in `appointment_booking_sheet_test_support.dart`.
4. **Tier 4** — Regression (L01–L03, L06).
5. **Partial** — Complete E11/G10/G03 sheet/unit portions; defer grid assertions to the `SfCalendar` wave.

---

*Derived from [QA_REVIEW_ui-008-calendar.md](./QA_REVIEW_ui-008-calendar.md) · Branch `ui/008-calendar`*
