# Appointments Feature – End-to-End Review

Scope: `frontend/lib/features/appointments/**` and `backend/supabase/migrations/*appoint*.sql`
(plus the most recent in-force RPC definitions from the migration chain).

Only actionable findings are listed. Pure style/naming is omitted.

---

## 1. Reschedule does not enforce branch working hours

- Severity: **High**
- Files:
  - `backend/supabase/migrations/20260527170000_optional_appointment_doctor.sql`
    (current definition of `auth_internal.reschedule_appointment`)
  - `backend/supabase/migrations/20260528153000_enforce_appointment_branch_working_hours.sql`
- Problem: `create_appointment` validates the new slot with
  `auth_internal.appointment_within_branch_working_hours(...)`. The current
  in-force `reschedule_appointment` does not call this validator, so a
  `scheduled` planned appointment can be moved to a closed weekday, before
  opening, after closing, or to a slot that spans two local days. This
  breaks parity with create and silently violates the working-hours
  invariant the rest of the feature relies on.
- Recommended fix: In `reschedule_appointment`, after `resolve_appointment_times`
  add:
  ```sql
  IF NOT auth_internal.appointment_within_branch_working_hours(v_appt.branch_id, v_start, v_end) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Appointment must be within branch working hours.');
  END IF;
  ```
  Add a regression test mirroring the create-path working-hours tests.

---

## 2. Reschedule does not enforce "patient already booked same day"

- Severity: **High**
- Files:
  - `backend/supabase/migrations/20260527170000_optional_appointment_doctor.sql`
  - `backend/supabase/migrations/20260528150500_appointment_slot_and_patient_day_conflicts.sql`
- Problem: `create_appointment` rejects with `PATIENT_ALREADY_BOOKED_SAME_DAY`
  when the patient already has a non-terminal appointment in the org on
  that local day. `reschedule_appointment` never calls
  `auth_internal.patient_has_same_day_appointment(...)`, so a user can
  reschedule appointment A to a day on which the same patient already has
  another non-cancelled appointment B.
- Recommended fix: In `reschedule_appointment`, after `resolve_appointment_times`
  call `auth_internal.patient_has_same_day_appointment(v_appt.branch_id,
  v_appt.patient_id, v_start, v_appt.id)` and return the
  `PATIENT_ALREADY_BOOKED_SAME_DAY` rpc_error when true. The
  `p_exclude_appointment_id` argument already exists on the helper.

---

## 3. Reschedule overlap check is silently skipped for appointments with no doctor

- Severity: **High**
- File: `backend/supabase/migrations/20260527170000_optional_appointment_doctor.sql`
  (current definition of `auth_internal.reschedule_appointment`)
- Problem: A later migration
  (`20260528150500_appointment_slot_and_patient_day_conflicts.sql`)
  redefined `auth_internal.appointment_has_overlap` to be **branch-wide**
  (it no longer filters by `doctor_id`). However, `reschedule_appointment`
  still gates the call with:
  ```sql
  IF v_appt.doctor_id IS NOT NULL
     AND auth_internal.appointment_has_overlap(...)
  ```
  For an appointment whose `doctor_id` is NULL (allowed since the
  optional-doctor migration), the overlap check is entirely skipped on
  reschedule, even though `create_appointment` always runs the
  branch-wide overlap check unconditionally. Result: a doctor-less
  appointment can be rescheduled on top of any other appointment in the
  same branch.
- Recommended fix: Remove the `v_appt.doctor_id IS NOT NULL AND` guard
  in `reschedule_appointment`. The helper is now branch-wide and accepts
  a NULL doctor argument. Make the call unconditional to match
  `create_appointment`.

---

## 4. Frontend uses device timezone, backend uses organization timezone

- Severity: **Medium** (correctness, UX/skew near midnight, cross-timezone staff)
- Files:
  - `frontend/lib/features/appointments/domain/appointment_status_day_rules.dart`
  - `frontend/lib/features/appointments/domain/appointment_today_range.dart`
  - `backend/supabase/migrations/20260528180000_appointment_status_requires_appointment_day.sql`
  - `backend/supabase/migrations/20260528150500_appointment_slot_and_patient_day_conflicts.sql`
- Problem: The backend gates "checked_in / in_progress / completed / no_show"
  on the **organization's** timezone (`o.timezone`) and rejects with
  `INVALID_TRANSITION` if `today < appointment_day` in that timezone. The
  frontend's `appointmentCalendarDayHasArrived` uses `startTime.toLocal()`
  and `DateTime.now()` (the **device** timezone). Similarly, the queue's
  `appointmentTodayRange` builds today's window from device-local midnight
  and sends it as UTC. A staff member in a different timezone (or near
  midnight) will see today's queue offset by a day or have action buttons
  enabled/disabled inconsistently with the server. The mismatch is
  graceful when the server rejects but is a silent UX bug when the
  frontend disables an action the backend would accept.
- Recommended fix: Expose the active org's timezone (already present in
  `organizations.timezone`) in the auth session context and use it for
  the queue range calculation and day-gating predicates. Pass the
  resolved `from`/`to` to `list_appointments` as the local-day window in
  that timezone, not the device's.

---

## 5. Calendar controller does not react to branch changes from the shell

- Severity: **Medium**
- File: `frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart`
- Problem: `AppointmentCalendarController.build()` reads
  `authSessionProvider.context?.activeBranchId` once at construction and
  never subscribes to subsequent changes. `AppointmentQueueController`
  uses `ref.listen<AuthSessionState>(...)` for exactly this. If
  `activeBranchId` is null at build time (e.g., branch resolution is
  still in flight) or is changed via the branch picker, the calendar
  stays stuck on "Select an active branch" or continues to display the
  previous branch's data.
- Recommended fix: Mirror the queue controller and add a
  `ref.listen<AuthSessionState>(authSessionProvider, ...)` in `build()`
  that calls `setBranchFilter` whenever `context?.activeBranchId`
  changes.

---

## 6. `rescheduleAppointment` repository fabricates `status` and `type`

- Severity: **Medium** (contract/parsing)
- Files:
  - `frontend/lib/features/appointments/data/appointment_repository.dart`
    (lines 184–215)
  - `frontend/lib/features/appointments/domain/create_appointment_result.dart`
- Problem: The backend `reschedule_appointment` response only contains
  `appointment_id`, `start_time`, `end_time`. The repository merges in
  hard-coded defaults (`type = planned`, `status = scheduled`) so it can
  reuse `CreateAppointmentResult.fromRpcData`. This silently lies to the
  caller and breaks if the backend ever auto-advances status on
  reschedule (e.g., to `confirmed`) or introduces additional appointment
  types. Type-system signals that the data was returned from the server
  when it actually wasn't.
- Recommended fix: Either (a) extend the backend response to include
  `status` and `type` (and keep the parser strict), or (b) introduce a
  dedicated `RescheduleAppointmentResult` model containing only
  `appointmentId`, `startTime`, `endTime`, and adjust the dialog/caller
  accordingly. Option (a) is preferred for symmetry with `create`.

---

## 7. Unknown enum values cause silent row drops

- Severity: **Medium** (extendability / forward-compat)
- File: `frontend/lib/features/appointments/domain/appointment_list_item.dart`
  (`AppointmentListItem.fromRow`)
- Problem: When `AppointmentType.tryParse` or `AppointmentStatus.tryParse`
  returns null, `fromRow` returns null and the row is dropped via
  `whereType<AppointmentListItem>()` in the repository. If the backend
  adds a new status value (the `confirmed` rollout is a recent example),
  every appointment carrying that status disappears from the calendar and
  queue with no error, no log, and no banner. Future enum additions
  (e.g., `rescheduled`, `arrived`, …) will produce silent data loss.
- Recommended fix: Log/`debugPrint` when an enum fails to parse, return a
  placeholder `AppointmentStatus.unknown` (and equivalent for type), and
  render such rows with a neutral label. Alternatively surface a "this
  view is out of date — please update the app" banner when any row is
  unparseable.

---

## 8. `update_appointment_status` permission check runs after transition validation

- Severity: **Medium** (security / info leak; also error UX)
- File: `backend/supabase/migrations/20260528180000_appointment_status_requires_appointment_day.sql`
- Problem: The function checks the transition matrix and day-gate first,
  then calls `assert_permission('appointments.cancel' | 'appointments.create')`.
  A caller without either permission can probe which transitions are
  valid for any appointment in their branch by observing
  `INVALID_TRANSITION` vs no error. Conversely, a caller with permission
  for an invalid transition gets `INVALID_TRANSITION` instead of
  `FORBIDDEN` for the no-permission case — confusing in mixed-role
  setups. (Note: the row is still constrained to `jwt_branch_ids()`,
  so this is bounded, but still a needless capability oracle.)
- Recommended fix: Move the `assert_permission` call before the
  transition matrix evaluation, OR perform a cheap permission check
  (caller has at least `appointments.create` or `appointments.cancel`)
  up front using a helper similar to `assert_appointment_access`.

---

## 9. `set_appointment_default_duration` repository hides null response

- Severity: **Low/Medium**
- File: `frontend/lib/features/appointments/data/appointment_repository.dart`
  (`setDefaultDuration`, lines 44–58)
- Problem:
  ```dart
  return savedMinutes ?? durationMinutes;
  ```
  If the server returns success with a missing/unexpected
  `default_duration_minutes`, the caller is told the user-provided value
  was saved. The earlier `if (result.data != null && savedMinutes == null)`
  catches *parse failure* but not *missing field*. The fallback masks a
  real schema drift.
- Recommended fix: Treat a missing/null `default_duration_minutes` on a
  successful response as `StateError("...unexpected shape...")`, the
  same way `getSettings` does.

---

## 10. `appointmentMessageForRpc` does not cover all known error codes

- Severity: **Low**
- Files:
  - `frontend/lib/features/appointments/presentation/appointment_rpc_messages.dart`
  - All current backend RPCs
- Problem: The mapper handles `SCHEDULE_CONFLICT`,
  `PATIENT_ALREADY_BOOKED_SAME_DAY`, `INVALID_TRANSITION`,
  `PATIENT_ARCHIVED`, `INVALID_DOCTOR`, `FORBIDDEN`, `INVALID_INPUT`,
  and the two `RPC_NOT_*` codes. It does *not* map `NOT_FOUND` or
  `INVALID_BRANCH`, which the backend can return from
  `cancel_appointment`, `reschedule_appointment`, `update_appointment_status`,
  `create_appointment`, and `list_appointments`. They will fall through
  to the raw English server message and bypass the localization
  story.
- Recommended fix: Add explicit branches for `NOT_FOUND` and
  `INVALID_BRANCH` with user-facing copy, and audit the mapper
  whenever a new `public.rpc_error(...)` code is added on the backend.

---

## 11. `list_appointments` requires create or cancel permission to read

- Severity: **Medium** (extendability / future RBAC needs)
- Files:
  - `backend/supabase/migrations/20260526140000_appointment_management.sql`
    (`auth_internal.assert_appointment_access`)
  - All `auth_internal.list_appointments` definitions and `get_appointment_settings`
- Problem: `assert_appointment_access` admits the caller only when they
  have `appointments.create` OR `appointments.cancel`. There is no
  read-only permission. A future "scheduling reader" or
  "front-desk-readonly" role cannot list appointments or settings
  without being granted the ability to mutate them. This is
  inconsistent with the more granular RBAC the rest of the codebase
  is moving toward.
- Recommended fix: Introduce an `appointments.read` permission key,
  use it inside `assert_appointment_access` (`create OR cancel OR read`),
  and grant it to roles that should view but not mutate.

---

## 12. Booking page allows picking times that the backend will always reject

- Severity: **Low**
- Files:
  - `frontend/lib/features/appointments/presentation/pages/appointment_booking_page.dart`
  - `frontend/lib/features/appointments/presentation/widgets/appointment_reschedule_dialog.dart`
- Problem: The pickers allow any time on any selected day (no branch
  working hours awareness), so a user can pick e.g. 22:00 with a 240-min
  duration that crosses midnight. The backend will reject with the
  generic `'Appointment must be within branch working hours.'`. There is
  no client-side guidance about the actual working hours.
- Recommended fix: Fetch the branch's working schedule (already on
  `branches.working_schedule`) alongside `get_appointment_settings`,
  expose `open_time`/`close_time` per day to the booking form, and
  constrain the start time + duration so the resulting end time stays
  within the same day's window.

---

## 13. Reschedule flow can't move a `confirmed` appointment

- Severity: **Low** (likely intentional, but worth confirming against spec)
- Files:
  - `frontend/lib/features/appointments/domain/appointment_status_transitions.dart`
    (`canRescheduleAppointment`)
  - `backend/supabase/migrations/20260527170000_optional_appointment_doctor.sql`
    (reschedule status guard)
- Problem: Both sides only allow reschedule when `status = 'scheduled'`.
  After phone-confirmation, an appointment becomes `confirmed` and is
  immutable except via cancel-and-re-book. This is a real UX dead-end if
  the spec wants confirmed appointments to be movable.
- Recommended fix: If the spec allows it, extend the guard to
  `status IN ('scheduled', 'confirmed') AND type = 'planned'` on both
  the backend status check and `canRescheduleAppointment`. Otherwise
  document the deliberate restriction.

---

## 14. Queue realtime client refreshes the entire list on any branch change

- Severity: **Low** (scalability)
- File: `frontend/lib/features/appointments/data/appointment_queue_realtime.dart`
- Problem: Any insert/update/delete on the `appointments` table for the
  branch triggers a full `refresh()`. For a busy branch this means
  re-running `list_appointments` per row mutation. Not incorrect, but
  it scales poorly and is also a thundering herd on any bulk operation
  (e.g., dev seed). The realtime payload already carries the row, but
  it's discarded.
- Recommended fix: When the payload is sufficient, apply the change
  in-place to the state list (insert/update/delete by id) and debounce
  the full refresh as a fallback. Same pattern is already used elsewhere
  in the app for patient queues.

---

## 15. `cancel_appointment` and `update_appointment_status` audit logs differ in shape

- Severity: **Low** (observability / extendability)
- Files:
  - `backend/supabase/migrations/20260528160000_appointment_confirmed_remove_walkin.sql`
  - `backend/supabase/migrations/20260528180000_appointment_status_requires_appointment_day.sql`
- Problem: `appointment.cancel` audit rows carry `status` + `cancel_reason`.
  `appointment.status` audit rows carry `old_status` + `new_status` but
  not the appointment's branch/patient/doctor. Reconstructing a status
  timeline downstream requires joining back to the appointment, which
  may have been further mutated.
- Recommended fix: Standardize the appointment audit payload to always
  include `appointment_id`, `branch_id`, `patient_id`, `doctor_id`,
  `old_status`, `new_status`, and any action-specific fields.

---

## 16. `AppointmentBookingPage` `_pickStartTime` `firstDate` allows yesterday

- Severity: **Low**
- File: `frontend/lib/features/appointments/presentation/pages/appointment_booking_page.dart`
- Problem: `firstDate: now.subtract(const Duration(days: 1))` lets the
  user pick yesterday in the date picker. The backend doesn't
  explicitly forbid a past start time on `create_appointment`, so a
  staff member can accidentally book a past slot (subject only to
  branch working hours / overlap). This is also inconsistent with the
  spec (V1-4 implies future scheduling).
- Recommended fix: Use `firstDate: DateTime(now.year, now.month, now.day)`
  on the date picker, and additionally reject `startTime < now` in
  `_submit` (or in the repository) with a clear message. Optionally
  add a backend guard.

---

## Summary by severity

- **High** (3): #1, #2, #3 — reschedule path skips working-hours,
  same-day patient, and (for doctor-less appointments) overlap checks
  that create enforces.
- **Medium** (5): #4, #5, #6, #7, #8, #11 — timezone divergence between
  device and org, calendar controller missing branch listener,
  reschedule response fabrication, silent row drops on unknown enums,
  status permission ordering, missing read-only RBAC.
- **Low** (8): #9, #10, #12, #13, #14, #15, #16 — defensive
  improvements, message coverage, picker constraints, audit shape.

The High items break parity between `create_appointment` and
`reschedule_appointment` and should be fixed together with regression
tests that mirror the existing create-path SQL tests in
`backend/tests/appointment_management_crud.sql`.
