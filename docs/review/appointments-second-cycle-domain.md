# Appointments Feature — Second Cycle Domain Layer Review

**Date:** 2026-07-05  
**Scope:** All 23 files in `frontend/lib/features/appointments/domain/`  
**Related tests:** 20 domain-focused unit files under `frontend/test/unit/appointments/`  
**Baseline:** First-cycle review (`appointments-feature-code-review.md`)

---

## Summary

The domain layer remains **functionally rich and well-tested** for happy-path status transitions, org-timezone day gates, queue partitioning, and basic reschedule rules. **None of the first-cycle Critical domain findings have been fixed.** Several timezone and working-hours inconsistencies persist and are **worse than a single “calendar bounds” bug**: reschedule validation, calendar filtering, and working-hours weekday resolution all use **device `toLocal()`**, while queue day rules and today bounds correctly use **organization IANA timezone**.

**Finding counts (Critical / High / Medium only):** 2 Critical · 9 High · 9 Medium

---

## Critical Issues

### C-1. Syncfusion and Flutter rendering types in domain (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Category** | Clean Architecture violation |
| **Files** | `appointment_calendar_display.dart` |
| **Evidence** | Imports `dart:ui`, `package:intl/intl.dart`, `package:syncfusion_flutter_calendar/calendar.dart`. Exposes `TimeRegion`, `Color`, `Rect` in public API. |
| **Why it's a problem** | Domain cannot be compiled or unit-tested without Flutter and a third-party calendar widget. Business layout rules are locked to Syncfusion. |
| **Impact** | Blocks headless domain reuse; any calendar widget swap forces domain rewrite; violates dependency rule. |
| **Recommended solution** | Split into pure layout model (`AppointmentCalendarTimeSlotLayout`, shade regions as `DateTime` pairs) in domain; map to Syncfusion/`Color` in presentation. |

```1:5:frontend/lib/features/appointments/domain/appointment_calendar_display.dart
import 'dart:ui';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
```

```124:150:frontend/lib/features/appointments/domain/appointment_calendar_display.dart
  static List<TimeRegion> resourceRowStripeRegions({
    required List<Object> resourceIds,
    required DateTime focusDate,
    required double startHour,
    required double endHour,
    required Color stripeColor,
  }) {
    // ...
          TimeRegion(
            startTime: rangeStart,
            endTime: rangeEnd,
```

**First-cycle status:** §1.5 — unchanged.

---

### C-2. Dev credentials and seed data in domain (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Category** | Clean Architecture / security |
| **Files** | `doctor_dev_seed_data.dart` |
| **Evidence** | Hard-coded password and dev doctor list live in domain. |
| **Why it's a problem** | Domain should encode business rules only, not environment-specific credentials or seed orchestration. |
| **Impact** | Risk of accidental inclusion in production builds; pollutes the domain mental model. |
| **Recommended solution** | Move to `data/dev/` or `tooling/`; keep domain free of dev-only artifacts. |

```12:21:frontend/lib/features/appointments/domain/doctor_dev_seed_data.dart
abstract final class DoctorDevSeedData {
  static const String defaultPassword = 'DevDoctor123!';

  static const List<DoctorDevSeedSpec> doctors = [
    DoctorDevSeedSpec(username: 'dev_doc_01', fullName: '${DoctorDevSeedSpec.devNamePrefix}Dr Sara Nabil'),
    // ...
  ];
}
```

**First-cycle status:** §1.6 — unchanged.

---

## High Priority Issues

### H-1. Cross-feature domain imports (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Clean Architecture violation |
| **Files** | `appointment_fetch_scope.dart`, `appointment_settings.dart`, `appointment_reschedule_validation.dart`, `appointment_working_hours.dart`, `appointment_branch_working_hours.dart`, `appointment_calendar_display.dart`, `appointment_queue_shift_doctors.dart` |
| **Evidence** | Appointments domain imports `auth_session.dart`, `branch_working_schedule.dart`, `staff_list_item.dart`, `shift_list_item.dart`, `shift_status.dart` directly. |
| **Why it's a problem** | Appointments domain cannot be understood or tested in isolation; changes to auth/settings/shifts enums ripple into appointments. |
| **Impact** | Feature fan-in; brittle contracts; prevents extracting appointments as a standalone module. |
| **Recommended solution** | Define appointments-local value types or ports (`BranchSchedule`, `StaffDoctor`, `ShiftCoverage`); map at application/provider boundary. |

```3:4:frontend/lib/features/appointments/domain/appointment_fetch_scope.dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
```

```4:8:frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
```

**First-cycle status:** §2.11 — unchanged.

---

### H-2. Duplicate working-hours logic with inconsistent parsers and contradictory end-of-day rules (STILL OPEN, WORSENED)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Code duplication / correctness |
| **Files** | `appointment_branch_working_hours.dart`, `appointment_working_hours.dart`, `appointment_reschedule_validation.dart`, `appointment_calendar_display.dart` |
| **Evidence** | Branch parser accepts optional seconds (`HH:MM:SS`); working-hours parser accepts only `HH:MM`. Branch `validationMessage` rejects slots crossing calendar midnight; `AppointmentWorkingHours` treats `23:59` close as end-of-day and accepts midnight-sentinel end times. Reschedule calls **both** validators sequentially. |
| **Why it's a problem** | Same schedule can pass one validator and fail another; maintenance drift is already visible in code and tests (midnight sentinel tested only on `AppointmentWorkingHours`). |
| **Impact** | False rejections for `HH:MM:SS` close times, late-day slots ending at midnight, and confusing duplicate error messages during drag-reschedule. |
| **Recommended solution** | Single `BranchScheduleValidator` with one parser, shared weekday helper, and unified end-of-day sentinel rules; expose thin `validateDuration` / `validateInterval` wrappers. |

```48:58:frontend/lib/features/appointments/domain/appointment_branch_working_hours.dart
  static int? parseHm(String? value) {
    // ...
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$').firstMatch(text);
```

```75:85:frontend/lib/features/appointments/domain/appointment_working_hours.dart
  static int? _parseHm(String? value) {
    // ...
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(text);
```

```67:69:frontend/lib/features/appointments/domain/appointment_branch_working_hours.dart
    if (localStart.year != localEnd.year || localStart.month != localEnd.month || localStart.day != localEnd.day) {
      return 'Appointment must start and end on the same day.';
    }
```

```30:40:frontend/lib/features/appointments/domain/appointment_working_hours.dart
    // Treat 23:59 close as end-of-day so slots ending at midnight are not rejected.
    final effectiveCloseMinutes = closeMinutes >= (23 * 60 + 59) ? 24 * 60 : closeMinutes;
    final midnightSentinelEnd = _isMidnightSentinelEnd(localStart, localEnd, closeMinutes);
```

```53:64:frontend/lib/features/appointments/domain/appointment_reschedule_validation.dart
    final hoursMessage = AppointmentBranchWorkingHours.validationMessage(/* ... */);
    if (hoursMessage != null) {
      return hoursMessage;
    }

    if (!AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: localNewStart, end: localNewEnd)) {
      return 'Appointment must be within branch working hours.';
    }
```

**First-cycle status:** §2.1 — still open; dual-validator contradiction on 23:59 slots confirmed in second cycle.

---

### H-3. Organization timezone vs device-local split across domain (STILL OPEN — broader than first cycle)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Business rule inconsistency |
| **Files** | `appointment_org_calendar.dart`, `appointment_calendar_period.dart`, `appointment_status_day_rules.dart`, `appointment_reschedule_validation.dart`, `appointment_working_hours.dart`, `appointment_branch_working_hours.dart`, `appointment_calendar_display.dart` |
| **Evidence** | Queue/day rules use `appointmentTodayRangeInTimezone` and `canTransitionToStatusOnDate` with org IANA TZ (regression-tested). Calendar fetch bounds use `DateTime(focusDate.year, focusDate.month, focusDate.day)` — device-local components. Reschedule, overlap, patient same-day, and working-hours weekday all call `.toLocal()` on UTC instants. |
| **Why it's a problem** | A clinic in `America/Los_Angeles` can gate check-in correctly per org day while calendar fetch, reschedule validation, and visibility filtering use the device clock/timezone. |
| **Impact** | Missing/extra appointments on calendar; false overlap/same-day errors; working-hours checks on wrong weekday near midnight; status actions and visible data disagree. |
| **Recommended solution** | Thread `organizationTimezone` through calendar bounds, reschedule validation, working-hours helpers, and `filterVisibleAppointments`; convert UTC instants via `appointmentWallClockInOrganizationTimezone` before calendar-day/weekday math. |

```15:19:frontend/lib/features/appointments/domain/appointment_calendar_period.dart
(DateTime, DateTime) appointmentCalendarFetchBounds(DateTime focusDate, AppointmentCalendarMode mode) {
  final dayStart = DateTime(focusDate.year, focusDate.month, focusDate.day);
```

```41:42:frontend/lib/features/appointments/domain/appointment_reschedule_validation.dart
    final localNewStart = newStart.toLocal();
    final localNewEnd = (newEnd ?? localNewStart.add(Duration(minutes: originalDurationMinutes))).toLocal();
```

```16:19:frontend/lib/features/appointments/domain/appointment_working_hours.dart
    final localStart = start.toLocal();
    final localEnd = end.toLocal();

    final dayHours = _hoursForDay(schedule, _weekdayFromDate(localStart));
```

**First-cycle status:** §2.2 — still open; second cycle confirms reschedule/filter/working-hours also lack org TZ (not only calendar bounds).

---

### H-4. Global timezone initialization side effect in domain (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Infrastructure leak |
| **Files** | `appointment_org_calendar.dart`, `appointment_queue_shift_doctors.dart` |
| **Evidence** | Module-level `_timezonesInitialized` flag; `ensureAppointmentTimezonesInitialized()` calls `tz_data.initializeTimeZones()`. |
| **Why it's a problem** | Domain performs one-time global IO-ish init; tests require `setUpAll(ensureAppointmentTimezonesInitialized)`. |
| **Impact** | Test ordering hazards; domain functions are not pure functions of inputs. |
| **Recommended solution** | Inject `TimezoneService` / `CalendarClock` port from app bootstrap; remove global init from domain. |

```6:15:frontend/lib/features/appointments/domain/appointment_org_calendar.dart
bool _timezonesInitialized = false;

void ensureAppointmentTimezonesInitialized() {
  if (_timezonesInitialized) {
    return;
  }
  tz_data.initializeTimeZones();
  _timezonesInitialized = true;
}
```

**First-cycle status:** §2.3 — unchanged.

---

### H-5. `AppointmentListItem` vs `AppointmentDetail` parsing policy divergence (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Data integrity |
| **Files** | `appointment_list_item.dart`, `appointment_detail.dart` |
| **Evidence** | List maps unknown type/status to `unknown` placeholders and keeps the row. Detail returns `null` when `type` or `status` fails strict parse. |
| **Why it's a problem** | Same backend row can appear on calendar/queue but fail detail hydration. |
| **Impact** | User sees appointment in list; detail screen fails silently or shows error. |
| **Recommended solution** | Unify policy (strict everywhere with explicit `unknown` only where product requires list resilience), or always refetch detail with tolerant mapping. |

```52:53:frontend/lib/features/appointments/domain/appointment_list_item.dart
    final type = AppointmentType.tryParse(typeRaw) ?? AppointmentType.unknown;
    final status = AppointmentStatus.tryParse(statusRaw) ?? AppointmentStatus.unknown;
```

```59:77:frontend/lib/features/appointments/domain/appointment_detail.dart
    final type = AppointmentType.tryParse(row['type']?.toString());
    final status = AppointmentStatus.tryParse(row['status']?.toString());
    // ...
        type == null ||
        status == null ||
```

**First-cycle status:** §2.4 — unchanged; tests in `appointment_list_item_test.dart` encode lenient list behavior.

---

### H-6. Status lifecycle rules fragmented across domain modules (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | SOLID / maintainability |
| **Files** | `appointment_status.dart`, `appointment_status_transitions.dart`, `appointment_status_day_rules.dart`, `appointment_status_timeline.dart`, `appointment_queue_display.dart` |
| **Evidence** | Matrix in `canTransitionTo`; day gates in `canTransitionToStatusOnDate`; forward actions in `forwardStatusTargetFor` (adds doctor-busy rules); timeline uses separate `mainFlow`; queue partition/stats apply their own status filters. No single policy entry point. |
| **Why it's a problem** | Callers using `canTransitionTo` or `canCancelAppointment` alone miss day gates; display partition rules can diverge from action gates. |
| **Impact** | UI may offer actions server rejects; queue/calendar/timeline disagree on terminal handling. |
| **Recommended solution** | Introduce `AppointmentLifecyclePolicy.canApply(item, target, context)` combining matrix, day rules, doctor-busy, and queue display rules. |

```61:68:frontend/lib/features/appointments/domain/appointment_status.dart
  bool canTransitionTo(AppointmentStatus target) {
    if (isTerminal) {
      return false;
    }
    return switch (this) { /* matrix only — no day rules */ };
  }
```

```66:68:frontend/lib/features/appointments/domain/appointment_status_transitions.dart
bool canCancelAppointment(AppointmentListItem item) {
  return item.status.canTransitionTo(AppointmentStatus.cancelled);
}
```

**First-cycle status:** §2.10 — unchanged.

---

### H-7. Doctor-busy / in-progress slot detection duplicated (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Code duplication |
| **Files** | `appointment_queue_start_doctor.dart`, `appointment_queue_display.dart`, `appointment_status_transitions.dart` |
| **Evidence** | Nearly identical iteration for assigned vs unassigned in-progress semantics in three places. |
| **Why it's a problem** | Fix in one location may not propagate; rules cannot be reused without copy-paste. |
| **Impact** | Start button, block reason, and forward target can drift. |
| **Recommended solution** | Extract `AppointmentDoctorAvailability` helper used by all three modules. |

```20:40:frontend/lib/features/appointments/domain/appointment_queue_start_doctor.dart
  static bool isDoctorBusy({
    required String doctorId,
    required String excludeAppointmentId,
    required Iterable<AppointmentListItem> items,
  }) {
    // assigned vs unassigned in-progress iteration
  }
```

```237:254:frontend/lib/features/appointments/domain/appointment_queue_display.dart
  static AppointmentListItem? inProgressAppointmentForDoctor(String? doctorId, Iterable<AppointmentListItem> items) {
    // same unassigned-slot semantics
  }
```

**First-cycle status:** §2.12 — unchanged.

---

### H-8. Domain lacks repository and timezone ports (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Clean Architecture / DIP |
| **Files** | Entire `domain/` (no `repositories/` or `usecases/` folders; contrast with `features/auth/domain/`) |
| **Evidence** | No `abstract class AppointmentRepository`; no use-case layer. Domain is a flat folder of entities + static helpers. |
| **Why it's a problem** | Domain cannot define appointment operations as inward-facing ports; presentation calls concrete data repositories directly. |
| **Impact** | Domain grows as a “god folder”; business orchestration cannot be expressed at the correct layer. |
| **Recommended solution** | Add `domain/repositories/appointment_repository.dart` and use cases mirroring auth feature shape. |

**First-cycle status:** §1.3 (feature-wide) — domain structural gap confirmed unchanged.

---

### H-9. Reschedule overlap treats `completed` visits as blocking (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Business rule correctness |
| **Files** | `appointment_reschedule_validation.dart` |
| **Evidence** | `_blocksScheduling` only skips `cancelled` and `noShow`. Completed appointments still participate in overlap and same-day patient checks. No unit test covers this path. |
| **Why it's a problem** | Completed visits occupy past slots; blocking reuse is likely incorrect vs backend overlap rules. |
| **Impact** | False “overlap” / “same day” errors when moving appointments into freed slots. |
| **Recommended solution** | Align `_blocksScheduling` with server overlap policy; likely skip `completed` (and possibly `unknown`). Add regression tests. |

```112:114:frontend/lib/features/appointments/domain/appointment_reschedule_validation.dart
  static bool _blocksScheduling(AppointmentListItem item) {
    return item.status == AppointmentStatus.cancelled || item.status == AppointmentStatus.noShow;
  }
```

**First-cycle status:** §3.2 — still open; elevated to High for second cycle because it is a user-facing false-negative with no test coverage.

---

## Medium Priority Issues

### M-1. Hardcoded 5-minute minimum ignores `AppointmentSettings.minDurationMinutes` (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_reschedule_validation.dart`, `appointment_settings.dart` |
| **Evidence** | Reschedule rejects `durationMinutes < 5` locally. Settings entity parses `minDurationMinutes` from RPC but validation never receives settings. |
| **Impact** | Client allows shorter durations than org policy until server rejects with `INVALID_INPUT`. |
| **Recommended solution** | Pass `AppointmentSettings` into validation; use `minDurationMinutes` (and optional `maxDurationMinutes`). |

```37:50:frontend/lib/features/appointments/domain/appointment_reschedule_validation.dart
    if (originalDurationMinutes < 5) {
      return 'Appointment duration is too short to reschedule.';
    }
    // ...
    if (durationMinutes < 5) {
      return 'Appointment duration is too short to reschedule.';
    }
```

**First-cycle status:** §3.3 — unchanged.

---

### M-2. `AppointmentStatus.canTransitionTo` does not encode day rules (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_status.dart`, `appointment_status_day_rules.dart`, `appointment_status_transitions.dart` |
| **Evidence** | `canCancelAppointment` uses matrix only; `canMarkNoShowAppointment` adds day gate. `canTransitionTo` has no date/org-tz parameters. |
| **Impact** | Future callers using `canTransitionTo` alone for check-in will be wrong. |
| **Recommended solution** | Add composed `canTransitionToStatus(from, to, {orgTimezone, startTime, referenceUtc})` or deprecate raw matrix for UI use. |

**First-cycle status:** §3.7 — unchanged.

---

### M-3. Schedule calendar mode: week fetch window, day navigation, and hardcoded 8–18 layout (STILL OPEN + NEW)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_calendar_period.dart`, `appointment_calendar_display.dart` |
| **Evidence** | `schedule` fetch uses 7-day week bounds; navigation advances one day. `timeSlotLayout` for `schedule` mode returns hardcoded `(8.0, 18.0)` instead of branch hours. No test covers schedule layout. |
| **Impact** | Wasteful refetch; UI grid may not match branch hours in schedule view. |
| **Recommended solution** | Align fetch bounds to single day or document prefetch; derive schedule hours from `BranchWorkingSchedule` like day/week modes. |

```12:14:frontend/lib/features/appointments/domain/appointment_calendar_period.dart
    case AppointmentCalendarMode.schedule:
      final weekStart = dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
      return (weekStart.toUtc(), weekStart.add(const Duration(days: 7)).toUtc());
```

```75:76:frontend/lib/features/appointments/domain/appointment_calendar_display.dart
      AppointmentCalendarMode.schedule => (8.0, 18.0),
      AppointmentCalendarMode.month => (8.0, 18.0),
```

**First-cycle status:** §3.4 — still open; hardcoded schedule hours newly noted in second cycle.

---

### M-4. Month navigation date overflow (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_calendar_period.dart` |
| **Evidence** | `DateTime(focusDate.year, focusDate.month - 1, focusDate.day)` relies on Dart date normalization (e.g. Mar 31 → Mar 3). Test only covers Mar 15 → Feb 15. |
| **Impact** | Focus date jumps unexpectedly when navigating months from day-of-month 29–31. |
| **Recommended solution** | Safe month arithmetic clamping day to last day of target month. |

```32:34:frontend/lib/features/appointments/domain/appointment_calendar_period.dart
    case AppointmentCalendarMode.month:
      return DateTime(focusDate.year, focusDate.month - 1, focusDate.day);
```

**First-cycle status:** §3.5 — unchanged; edge-day overflow still untested.

---

### M-5. `debugPrint` in domain entity factory (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_list_item.dart` |
| **Evidence** | `fromRow` logs unrecognized type/status via `debugPrint`. |
| **Impact** | Console noise in production; domain depends on Flutter logging. |
| **Recommended solution** | Return parse warnings via result type or log in data layer only. |

```58:63:frontend/lib/features/appointments/domain/appointment_list_item.dart
    if (type == AppointmentType.unknown) {
      debugPrint('AppointmentListItem: unrecognized type "$typeRaw" for appointment $id');
    }
```

**First-cycle status:** §3.6 — unchanged.

---

### M-6. Presentation enum `AppBadgeTone` in domain queue display (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_queue_display.dart` |
| **Evidence** | `scheduleBadgeTone` returns `AppBadgeTone`; enum defined at bottom of domain file. |
| **Impact** | Presentation semantics leak into domain policy file. |
| **Recommended solution** | Keep pure metrics/status in domain; map to badge tones in presentation. |

```388:410:frontend/lib/features/appointments/domain/appointment_queue_display.dart
  static AppBadgeTone scheduleBadgeTone(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => AppBadgeTone.neutral,
      // ...
    };
  }
}

enum AppBadgeTone { neutral, info, success, warning, destructive, muted }
```

**First-cycle status:** §3.16 — unchanged.

---

### M-7. `unknown` status terminal handling under-tested in transitions and timeline (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_status.dart`, `appointment_status_timeline.dart`, `appointment_queue_display.dart` |
| **Evidence** | `unknown.isTerminal => true`; timeline `indexOf(unknown)` → all steps `skipped`; `_activeToday` excludes `unknown` from queue stats. No test for forward actions or timeline on unknown rows. |
| **Impact** | Unknown rows may appear on calendar (not hidden by `isHiddenOnCalendar`) with no recovery UX contract. |
| **Recommended solution** | Explicit product rule (hide vs banner); add tests for `forwardStatusTargetFor`, timeline, and queue partition on `unknown`. |

```27:28:frontend/lib/features/appointments/domain/appointment_status_timeline.dart
    if (currentIndex < 0 || stepIndex < 0) {
      return AppointmentTimelineStepState.skipped;
```

```402:405:frontend/lib/features/appointments/domain/appointment_queue_display.dart
  static List<AppointmentListItem> _activeToday(List<AppointmentListItem> items) {
    return items
        .where((item) => item.status != AppointmentStatus.cancelled && item.status != AppointmentStatus.unknown)
```

**First-cycle status:** §3.1 — unchanged.

---

### M-8. `appointment_org_calendar.dart` and `appointment_fetch_scope.dart` test gaps (STILL OPEN)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_org_calendar.dart`, `appointment_fetch_scope.dart` |
| **Evidence** | No tests for `appointmentWallClockInOrganizationTimezone`, `effectiveOrganizationTimezone`, init idempotency, invalid IANA fallback, or `AppointmentFetchScope` `==` / `hashCode`. |
| **Impact** | Regressions in session-scope reload triggers and display formatting may go unnoticed. |
| **Recommended solution** | Add focused unit tests for wall-clock conversion, empty timezone defaulting, and fetch-scope equality. |

**First-cycle status:** §3.20, §3.21 — unchanged.

---

### M-9. Shift date matching uses naive calendar components (NEW)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_queue_shift_doctors.dart` |
| **Evidence** | `appointmentDay` is derived from org TZ wall clock, but `shift.shiftDate` is compared via `_isSameCalendarDay` using bare `year/month/day` with no org-TZ normalization on the shift side. |
| **Why it's a problem** | If `shift_date` from the API is ever interpreted in a different timezone context than org-local appointment day, shift doctor resolution can miss or include wrong shifts near midnight. |
| **Impact** | Empty or incorrect doctor lists on queue sidebar; false “no doctor on shift” block reasons. |
| **Recommended solution** | Normalize both sides to org-timezone calendar dates; add boundary test with non-UTC org TZ. |

```146:152:frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart
    final appointmentDay = DateTime(localStart.year, localStart.month, localStart.day);
    // ...
      if (!_isSameCalendarDay(shift.shiftDate, appointmentDay)) {
        continue;
      }
```

---

## First-Cycle Issue Verification Matrix

| First-cycle ID | Topic | Second-cycle status |
|----------------|-------|---------------------|
| §1.5 | Syncfusion in domain | **Still Critical** (C-1) |
| §1.6 | Dev seed in domain | **Still Critical** (C-2) |
| §2.1 | Duplicate working hours | **Still High** (H-2) |
| §2.2 | Calendar bounds vs org TZ | **Still High** (H-3) |
| §2.3 | Global TZ init | **Still High** (H-4) |
| §2.4 | List vs detail parsing | **Still High** (H-5) |
| §2.10 | Fragmented lifecycle | **Still High** (H-6) |
| §2.11 | Cross-feature imports | **Still High** (H-1) |
| §2.12 | Doctor-busy duplication | **Still High** (H-7) |
| §3.2 | Completed blocks overlap | **Still open**, elevated High (H-9) |
| §3.3 | Hardcoded min duration | **Still Medium** (M-1) |
| §3.4 | Schedule fetch/nav mismatch | **Still Medium** (M-3) |
| §3.5 | Month overflow | **Still Medium** (M-4) |
| §3.6 | debugPrint in domain | **Still Medium** (M-5) |
| §3.7 | canTransitionTo footgun | **Still Medium** (M-2) |
| §3.16 | AppBadgeTone in domain | **Still Medium** (M-6) |
| §3.1 | unknown status gaps | **Still Medium** (M-7) |
| §4.1 | Dead `appointmentTodayRange` | Still present; not elevated (device-local helper unused) |

---

## Test Coverage Notes (Domain)

**Well covered:** status enum/matrix, day rules with org-TZ regression, transitions (including doctor-busy + shift fallback), queue display partition/stats, branch working hours basics, working-hours midnight sentinel (interval validator only), calendar period bounds, reschedule happy paths, shift doctor lookup (UTC).

**Gaps confirmed in second cycle:**

| Gap | Risk |
|-----|------|
| Reschedule + `completed` overlap | False overlap errors (H-9) |
| Dual validator 23:59 / `HH:MM:SS` paths | Inconsistent rejections (H-2) |
| Reschedule with non-UTC org timezone | Wrong hours/day (H-3) |
| `appointmentWallClockInOrganizationTimezone` | Display/TZ bugs (M-8) |
| `AppointmentFetchScope` equality | Provider reload bugs (M-8) |
| Schedule mode layout hours | Wrong grid (M-3) |
| Month nav from day 31 | Focus jump (M-4) |
| `unknown` status forward/timeline | UX contract drift (M-7) |
| Shift date boundary in org TZ | Doctor list errors (M-9) |

---

*Second-cycle domain review — 2026-07-05. All 23 domain files read in full; 20 related unit test files consulted.*
