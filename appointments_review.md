# Appointments Feature — Independent Architectural Review

Target: `frontend/lib/features/appointments/**` in the `ai_clinic` Flutter desktop app
(repository root `C:\Users\haosama\Downloads\resources`, Dart package name `ai_clinic`).

---

## Scope & method

**What was reviewed.** All 69 Dart files under `frontend/lib/features/appointments/` (~14,500 lines), split across
`application/` (1 file), `data/` (4 files), `domain/` (25 files) and `presentation/` (39 files across
`pages/`, `widgets/`, `providers/`, `models/`, `utils/`, `navigation/`).

**Cross-boundary inspection (not reviewed in depth, only for boundary violations).**
`frontend/lib/core/**`, `frontend/lib/app/**` (router, shell, navigation, dev seed), and the features
Appointments touches: `patients`, `visits`, `billing`, `shifts`, `service_catalog`, `clinic-management`, `setup`, `auth`.

**How the grading baseline was established.** The review was graded against:

- `docs/architecture/07-frontend.md` — canonical frontend architecture. Key rules used as the baseline:
  - Layer table: **Domain** (`domain/`) contains "value objects, enums, DTOs, abstract repository interfaces, use cases" and
    **"Depends On: Nothing (innermost layer)"**; **Data** (`data/`) contains concrete `*Impl` repositories, RPC call logic and
    error mapping; **Presentation** contains pages, widgets and Riverpod providers.
  - "Layering Inconsistency (Intentional)" table, which records `appointments` as an accepted exception using
    **"Repositories + presentation notifiers"** instead of a use-case layer.
  - The V1-4 appointment route table.
- `docs/architecture/01-principles.md` — "Modularity: feature domains are isolated. Each can be specified, built, tested,
  and replaced independently."
- `docs/architecture/ARCHITECTURAL_FLAWS.md` — the pre-existing flaw register (C1, H1–H7, M1–M9, L1–L6), used to avoid
  re-reporting known issues.

**Grading rules applied.**

- Because 07-frontend.md explicitly grants Appointments an exception from the use-case layer, **the absence of
  `domain/usecases/` and of an abstract `domain/repositories/appointment_repository.dart` is NOT reported as a finding.**
- Existing behaviour is assumed correct unless there is direct code evidence of a defect.
- Minor style, naming and formatting issues are deliberately excluded.
- Already-documented flaws are called out as such. Nothing in this report duplicates an open item in
  `ARCHITECTURAL_FLAWS.md`; the closest neighbours are `L2` (features skipping the use-case layer) and `H5`
  (monolithic `VisitDocumentationNotifier`), and where a finding is thematically adjacent to those, this is stated inline.

**Method.** Full read of `data/`, `application/` and `domain/`; full structural read of the four largest presentation
files (`appointment_calendar_page.dart` 2,180 lines, `appointment_booking_sheet.dart` 968,
`appointment_status_timeline_widget.dart` 903, `appointment_detail_page.dart` 886) plus all providers and all
`appointment_detail_*` widgets; import-graph analysis with `rg` in both directions (Appointments → other features, and
other features/core/app → Appointments); consumer analysis for every public API of the queue subsystem;
`frontend/analysis_options.yaml` and `frontend/pubspec.yaml` checked for boundary-enforcement tooling.

**Two doc/code drifts noticed while establishing the baseline** (context, not findings in their own right):
07-frontend.md describes the realtime queue as a `StreamProvider`, but it is implemented as a
`NotifierProvider` (`appointmentQueueProvider`) driving a manual Supabase channel; and 07-frontend.md's route table
marks `/appointments/queue` → `AppointmentQueuePage` as "built", which is not true (see finding H5).

---

## Findings summary

| ID | Severity | Short title | Primary file(s) |
| -- | -------- | ----------- | --------------- |
| C1 | Critical | Domain layer depends on Flutter `dart:ui` and the Syncfusion calendar package, and holds the UI palette, pixel geometry and label strings | `domain/appointment_calendar_display.dart`, `domain/appointment_calendar_status_style.dart`, `domain/appointment_queue_display.dart` |
| C2 | Critical | Widgets execute multi-RPC and cross-feature write transactions with no application layer (visit creation, doctor reassignment + status advance) | `presentation/widgets/appointment_detail_status_actions.dart`, `presentation/widgets/appointment_detail_open_visit_button.dart` |
| C3 | Critical | Doctor identity is resolved by full-name string matching between shifts and staff, and the resolved id is written back to the appointment | `domain/appointment_queue_shift_doctors.dart`, `presentation/providers/appointment_queue_shift_provider.dart` |
| H1 | High | `appointment_calendar_page.dart` is a 2,180-line god page with two near-duplicate drag/resize reschedule pipelines | `presentation/pages/appointment_calendar_page.dart` |
| H2 | High | `core/ui` design-system component imports Appointments domain (core → feature inversion) | `frontend/lib/core/ui/components/app_booking_slot_grid.dart` |
| H3 | High | Real bidirectional feature cycles: Appointments ↔ Visits and Appointments ↔ Patients, with Patients calling the Appointments repository directly | `frontend/lib/features/patients/presentation/providers/patient_detail_history_provider.dart`, `presentation/widgets/appointment_detail_open_visit_button.dart` |
| H4 | High | `AppointmentCalendarController.refresh()` has no request sequencing — out-of-order responses render the wrong period | `presentation/providers/appointment_calendar_provider.dart` |
| H5 | High | The whole queue subsystem (~1,500 lines) has no UI consumer, yet opens a live Realtime subscription for every signed-in user | `presentation/providers/appointment_queue_provider.dart`, `domain/appointment_queue_display.dart`, `data/appointment_queue_realtime.dart` |
| H6 | High | Appointment mutations are duplicated across 13 widget/page call sites with copy-pasted error handling | `presentation/pages/appointment_calendar_page.dart`, `presentation/widgets/appointment_detail_status_actions.dart`, `presentation/widgets/appointment_booking_sheet.dart` |
| M1 | Medium | Business logic (`resolveQueueShiftDoctors`) lives in `presentation/providers/`, and its fetch orchestration is duplicated in two providers | `presentation/providers/appointment_queue_shift_provider.dart`, `presentation/providers/appointment_detail_shift_provider.dart` |
| M2 | Medium | Lossy and inconsistent error handling: raw `error.toString()` shown to users, `catch (_)` in 10+ sites, malformed RPC payload silently becomes an empty list | `presentation/pages/appointment_detail_page.dart`, `data/appointment_repository.dart`, `presentation/providers/appointment_calendar_provider.dart` |
| M3 | Medium | Cache invalidation is ad hoc and inconsistent; the detail page bypasses the shared invalidation helper and omits the queue | `presentation/pages/appointment_detail_page.dart`, `presentation/providers/appointment_surface_invalidation.dart` |
| M4 | Medium | Dev-only `DoctorDevSeedService` sits in Appointments `data/` and provisions staff accounts through Setup and Clinic-Management repositories | `data/doctor_dev_seed_service.dart` |
| M5 | Medium | Shared clinic vocabulary (`BranchWorkingSchedule`, `StaffListItem`, `BranchListItem`) is owned by `clinic-management` and consumed by Appointments in 30+ places with no shared home | `domain/appointment_settings.dart`, `domain/appointment_branch_working_hours.dart`, `domain/appointment_booking_slots.dart` |
| M6 | Medium | `build()` in the calendar page has side effects, rebuilds the fullscreen overlay every frame, and does a linear scan per tile | `presentation/pages/appointment_calendar_page.dart` |
| M7 | Medium | Two divergent working-hours parsers (`parseHm`) accept different formats, so the same schedule validates differently on different paths | `domain/appointment_branch_working_hours.dart`, `domain/appointment_working_hours.dart` |
| M8 | Medium | No static enforcement of layer or feature boundaries anywhere in the toolchain | `frontend/analysis_options.yaml` |

Counts: **3 Critical, 6 High, 8 Medium.**

---

## C1 — Domain layer depends on Flutter UI primitives and the Syncfusion calendar package

**Severity:** Critical

**Location:**

- `frontend/lib/features/appointments/domain/appointment_calendar_display.dart`
  - line 1: `import 'dart:ui';` (uses `Color`, `Brightness`, `Rect`)
  - line 4: `import 'package:syncfusion_flutter_calendar/calendar.dart';`
  - line 3: `import 'package:intl/intl.dart';`
  - class `AppointmentCalendarDisplay`: pixel constants at lines 52–78 (`defaultViewportHeight`, `minTimeIntervalHeight`,
    `doctorsTimelineTimeIntervalWidth`, `viewHeaderBadgeSize`, `viewHeaderVerticalPadding`, `viewHeaderHeight`,
    `timeLabelWidth`, `timeSlotChromeHeight`); `headerTitle` (96–102) formats a month/year string;
    `timeSlotLayout` (111–157) computes Syncfusion axis geometry; `resourceRowStripeRegions` (211–240) builds
    `List<TimeRegion>` and takes a `Color stripeColor`; `isAlignedToSlotGrid` (354–367) takes a `Rect` and pixel
    `slotSize`; `statusStyle` / `filteredOutStyle` / `statusColor` / `filteredOutStatusColor` / `appointmentTileColor`
    (498–544) return `Color`/style objects; `filteredOutOpacity = 0.4` (522).
- `frontend/lib/features/appointments/domain/appointment_calendar_status_style.dart`
  - line 1: `import 'dart:ui';`; class `AppointmentCalendarStatusStyle` (9–27) is six `Color` fields;
    `AppointmentCalendarStatusPalette` (30–201) is a hard-coded light/dark hex palette keyed by `AppointmentStatus`.
- `frontend/lib/features/appointments/domain/appointment_queue_display.dart`
  - UI label constants `noShiftDoctorLabel` (61) and `noPreferredDoctorLabel` (64);
    `formatDurationLabel` / `formatWaitLabel` / `formatWaitedLabel` / `formatSessionLabel` (434–456);
    `waitPresentation` (458–464); `scheduleBadgeTone` (466–477) returning the design-system enum `AppBadgeTone`;
    `scheduleBadgeLabel` (479); `estimatedScheduleScrollOffset` (362–372) and `indexClosestToNow` (334–359) compute
    scroll geometry.
- Contagion path: `frontend/lib/features/appointments/domain/appointment_booking_slots.dart` line 5 imports
  `appointment_calendar_display.dart` only to read the two integer constants `defaultTimeIntervalMinutes` and
  `supportedTimeIntervalMinutes` (used in `AppointmentBookingSlots.defaultSlotMinutes`, lines 230–239). As a result the
  pure booking-slot generator transitively depends on the Syncfusion calendar widget package.

**Issue:** `docs/architecture/07-frontend.md` states that the domain layer "Depends On: Nothing (innermost layer)".
The Appointments domain layer instead depends on `dart:ui` and on a third-party Flutter *widget* library
(`syncfusion_flutter_calendar`), and it owns the theme palette, pixel layout constants, scroll offsets, human-readable
duration labels and design-system badge tones. Roughly 400 of the ~1,200 lines in
`appointment_calendar_display.dart` + `appointment_calendar_status_style.dart` + `appointment_queue_display.dart` are
presentation concerns, not domain rules.

**Why it is a problem:**

- *Replaceability.* Swapping the calendar widget (the stated reason Syncfusion is imported) requires editing the domain
  layer, which contradicts 01-principles.md ("Every layer is designed to be replaceable without cascading changes").
- *Theming correctness.* Status colours are hard-coded hex constants keyed only by `Brightness`, so they cannot
  participate in the four theme variants that `core/ui/theme` supports (`med_spectra`, `ecarely`, `clinic`,
  `parchment`). The design system is bypassed for the single most visible surface in the feature.
- *Testability.* Pure scheduling rules (working hours, slot filtering, status visibility) cannot be unit-tested without
  pulling in Flutter UI bindings and the Syncfusion package, because they live in the same class as `Rect`/`Color` code.
- *Localisation.* All user-facing strings for the calendar and queue are hard-coded English inside domain files, so no
  localisation layer can intercept them.

**Recommended architectural solution:** split each of the three files along the domain/presentation seam. Domain keeps
scheduling rules and returns *semantic* values (enums, minutes, `Duration`, status sets); presentation maps those to
colours, pixels and strings.

Target files:

| New/changed file | Layer | Contents |
| --- | --- | --- |
| `domain/appointment_calendar_layout.dart` | domain | `AppointmentCalendarHourRange` (a new plain `{double startHour, double endHour}` value object), `hourRangeForDay`, `hourRangeForWeek`, `nonWorkingDays`, `closedDatesInMonth`, `shadeRegionsForWeek`, `AppointmentCalendarShadeRegion`, `slotRangeFromTap`, `snapTimeToSlot`. No `dart:ui`, no Syncfusion, no `intl`. |
| `domain/appointment_calendar_status_filter.dart` | domain | `calendarStatusLegend`, `isHiddenOnCalendar`, `isVisibleOnCalendar`, `isDefaultStatusFilter`, `isStatusChipSelected`, `toggleStatusChip`, `isStatusHighlighted`, `filterVisibleAppointments`, `resolveBranchSchedule`, `isClosedOnDate`, `showWeekends`. |
| `presentation/theme/appointment_calendar_status_theme.dart` | presentation | The moved `AppointmentCalendarStatusStyle` + `AppointmentCalendarStatusPalette`, plus `statusColor`, `filteredOutStatusColor`, `appointmentTileColor`, `filteredOutOpacity`. Should read from `core/ui/theme/app_semantic_colors.dart` where an equivalent token exists. |
| `presentation/widgets/appointment_calendar_geometry.dart` | presentation | `AppointmentCalendarTimeSlotLayout`, `timeSlotLayout(...)` (consuming `AppointmentCalendarHourRange`), the pixel constants from lines 52–78, `isAlignedToSlotGrid(Rect, ...)`, `resourceRowStripeRegions(... Color stripeColor)` returning `List<TimeRegion>`, and `headerTitle` (the only `intl` user). |
| `presentation/formatting/appointment_queue_labels.dart` | presentation | `noShiftDoctorLabel`, `noPreferredDoctorLabel`, `formatDurationLabel`, `formatWaitLabel`, `formatWaitedLabel`, `formatSessionLabel`, `waitPresentation`, `scheduleBadgeTone`, `scheduleBadgeLabel`, `estimatedScheduleScrollOffset`, `indexClosestToNow`. |
| `domain/appointment_queue_metrics.dart` | domain | The remainder of `AppointmentQueueDisplay`: `AppointmentQueueStats`, `AppointmentQueueStatTrend`, `AppointmentQueuePartition`, `computeStats`, `partition`, `estimateWaitDuration`, `estimateSessionDuration`, `waitTierFor`, `waitWarningMinutes`, `waitCriticalMinutes`, `inProgressAppointmentForDoctor`, `doctorInProgressBlockReason`, `isScheduleRowDimmed`. |
| `domain/appointment_slot_defaults.dart` | domain | `defaultTimeIntervalMinutes = 30` and `supportedTimeIntervalMinutes = [15, 30, 60]`, so `appointment_booking_slots.dart` no longer imports the calendar display file. |

**Suggested implementation steps:**

1. Create `domain/appointment_slot_defaults.dart` containing only `const defaultTimeIntervalMinutes = 30;` and
   `const supportedTimeIntervalMinutes = <int>[15, 30, 60];` (top-level constants, no class).
2. In `domain/appointment_booking_slots.dart`: delete the import of `appointment_calendar_display.dart` (line 5), import
   `appointment_slot_defaults.dart`, and change `defaultSlotMinutes` (lines 230–239) to use the new top-level constants.
3. Create `presentation/theme/appointment_calendar_status_theme.dart`. Move the entire contents of
   `domain/appointment_calendar_status_style.dart` into it unchanged, then also move `statusStyle`, `filteredOutStyle`,
   `statusColor`, `filteredOutStatusColor`, `filteredOutOpacity` and `appointmentTileColor` out of
   `AppointmentCalendarDisplay` (lines 498–544 of `appointment_calendar_display.dart`) into a new
   `abstract final class AppointmentCalendarStatusTheme` in the same file. Keep the method names identical.
4. Delete `domain/appointment_calendar_status_style.dart`.
5. Create `presentation/widgets/appointment_calendar_geometry.dart`. Move `AppointmentCalendarTimeSlotLayout` (lines
   26–46), the constants at lines 52–78, `timeSlotLayout` (111–157), `resourceRowStripeRegions` (211–240),
   `isAlignedToSlotGrid` (354–367), `headerTitle` (96–102), `_minutesToHour`, `_minutesToEndHour` into a new
   `abstract final class AppointmentCalendarGeometry`. This file may import `dart:ui`, `intl` and Syncfusion.
6. Create `domain/appointment_calendar_layout.dart`. Move `AppointmentCalendarShadeRegion` (15–23),
   `visibleHeaderDays`, `_weekStart`, `_hourRangeForDay`, `_hourRangeForWeek` (rename the last two to public
   `hourRangeForDay` / `hourRangeForWeek` returning a new `AppointmentCalendarHourRange` class defined in this file),
   `nonWorkingDays`, `closedDatesInMonth`, `shadeRegionsForWeek`, `slotRangeFromTap`, `snapTimeToSlot`,
   `_isWorkingWeekday`, `_weekdayConstant` into `abstract final class AppointmentCalendarLayout`. Verify this file
   imports only `appointment_branch_working_hours.dart`, `appointment_calendar_period.dart` and
   `clinic-management/domain/branch_working_schedule.dart`.
7. Create `domain/appointment_calendar_status_filter.dart` and move `calendarStatusLegend`, `isHiddenOnCalendar`,
   `isVisibleOnCalendar`, `isDefaultStatusFilter`, `_calendarWorkflowStatuses`, `_calendarHiddenStatuses`,
   `isStatusChipSelected`, `toggleStatusChip`, `isStatusHighlighted`, `filterVisibleAppointments`,
   `resolveBranchSchedule`, `isClosedOnDate`, `showWeekends` into `abstract final class AppointmentCalendarStatusFilter`.
8. Delete `domain/appointment_calendar_display.dart` once empty.
9. Update every call site. Search with `rg -n "AppointmentCalendarDisplay\." frontend/lib frontend/test` and rewrite each
   reference to the new owner class. Known call sites: `presentation/pages/appointment_calendar_page.dart`,
   `presentation/pages/appointment_detail_page.dart` (line 132), `presentation/widgets/appointment_calendar_tile.dart`,
   `presentation/widgets/appointment_calendar_data_source.dart` (line 96),
   `presentation/widgets/appointment_calendar_filters.dart` (line 619),
   `presentation/widgets/appointment_calendar_status_swatch.dart`,
   `presentation/widgets/appointment_calendar_color_legend_button.dart`,
   `presentation/widgets/appointment_status_timeline_widget.dart`,
   `presentation/widgets/appointment_detail_status_actions.dart` (lines 514, 531, 550),
   `presentation/providers/appointment_calendar_provider.dart` (lines 32, 271),
   `domain/appointment_booking_slots.dart`, and `frontend/test/unit/appointments/appointment_calendar_display_test.dart`.
10. Create `presentation/formatting/appointment_queue_labels.dart` and move the label/format/scroll members listed in the
    table above out of `domain/appointment_queue_display.dart`. Move the `AppBadgeTone` reference with them so the
    design-system enum is no longer referenced from `domain/`.
11. Rename the remainder of `domain/appointment_queue_display.dart` to `domain/appointment_queue_metrics.dart` with class
    `AppointmentQueueMetrics`, and update its only production call site,
    `presentation/providers/appointment_queue_provider.dart` line 350
    (`AppointmentQueueDisplay.partition(items).waiting.length`), plus
    `frontend/test/unit/appointments/appointment_queue_display_test.dart`.
12. Verify: run `rg -n "dart:ui|syncfusion|package:intl|AppBadgeTone" frontend/lib/features/appointments/domain` and
    confirm zero matches. Then run `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## C2 — Widgets execute multi-RPC and cross-feature write transactions with no application layer

**Severity:** Critical

**Location:**

- `frontend/lib/features/appointments/presentation/widgets/appointment_detail_status_actions.dart`
  - `_AppointmentDetailStatusActionsState._handleAdvanceStatus()` lines 216–294. Inside a widget it performs a two-step
    write: `appointmentRepositoryProvider.updateAppointment(... doctorId: selectedDoctorId ...)` (lines 240–249) followed
    by `appointmentRepositoryProvider.updateAppointmentStatus(... newStatus: target)` (lines 252–257).
  - `_resolveDoctorForStart()` lines 186–214 decides *which doctor is assigned to a patient* and, when ambiguous, opens
    `AppointmentStartDoctorDialog` (line 213) from inside the same widget.
  - Also `_handleRevertStatus` (296–380), `_handleCancel` (382–433), `_handleMarkNoShow` (435–509) each read the
    repository directly.
- `frontend/lib/features/appointments/presentation/widgets/appointment_detail_open_visit_button.dart`
  - line 12 imports `package:ai_clinic/features/visits/data/visit_repository.dart`.
  - `_AppointmentDetailOpenVisitButtonState._handleOpenVisit()` lines 69–125 calls
    `visitRepositoryProvider.getVisitByAppointment` (line 77) and then **creates a row in another feature's aggregate**:
    `repo.createVisit(appointmentId: detail.id, doctorId: detail.doctorId)` (lines 81–84). It then compensates for a
    server-side race by catching `RpcFailure` with code `VISIT_ALREADY_EXISTS` and re-reading
    (`_openExistingVisit`, lines 127–148).
- `frontend/lib/features/appointments/presentation/widgets/appointment_detail_invoice_summary_button.dart`
  - lines 11–13 import `features/billing/data/invoice_repository.dart`, `features/visits/data/visit_repository.dart`, and
    `features/billing/presentation/widgets/visit_billing/visit_invoice_summary_dialog.dart`.
  - `_handleOpenInvoiceSummary()` lines 41–113 chains three cross-feature reads
    (`visitRepo.getVisitByAppointment` → `invoiceRepo.findForVisit` → `invoiceRepo.getDetail`) and then shows another
    feature's dialog (line 87).

**Issue:** Business transactions that span two RPCs and three features are orchestrated inside `StatefulWidget` state
classes. There is no application/service layer between the widgets and the repositories, and `appointments/application/`
contains only `appointment_rpc_messages.dart` (36 lines of error-message mapping). Concretely, three distinct
responsibilities are fused into widget callbacks: (a) choosing the doctor to assign, (b) issuing a doctor reassignment
write, (c) issuing a status transition write — plus, in the sibling buttons, (d) creating visits and (e) resolving
invoices in other features.

**Why it is a problem:**

- *Correctness — non-atomic transaction with no compensation.* In `_handleAdvanceStatus`, if `updateAppointment` succeeds
  and `updateAppointmentStatus` then fails (network drop, `INVALID_TRANSITION`), the appointment is left with a **newly
  reassigned doctor but the old status**. The `catch` blocks at lines 271–292 only show a toast; there is no rollback and
  no record that a partial write happened. In a clinical scheduling system this silently reassigns a patient to a
  different doctor.
- *Boundary violation.* `createVisit` is a write into the Visits aggregate. Appointments deciding when a visit row comes
  into existence means the Visits feature can no longer own its own invariants, and it is why the
  `VISIT_ALREADY_EXISTS` compensation exists at all.
- *Untestable.* Every one of these flows requires a full widget test with `BuildContext`, `Navigator`, `Overlay` and toast
  infrastructure to test what is really a three-line orchestration rule.
- *Unreusable.* When the queue UI is (re)built (see H5), the same "start appointment → maybe assign doctor → advance
  status" rule must be re-implemented, because it lives inside a specific button's state class.

**Recommended architectural solution:** introduce an `application/` orchestration layer in Appointments, and require the
other features to expose their own entry points instead of Appointments reaching into their `data/`.

New files:

| File | Layer | Contents |
| --- | --- | --- |
| `frontend/lib/features/appointments/application/appointment_status_service.dart` | application | `AppointmentStatusService` with `advanceStatus({required AppointmentDetail detail, required AppointmentStatus target, required String? selectedDoctorId})`, `revertStatus(...)`, `cancel({required String appointmentId, required String? reason})`, `markNoShow({required String appointmentId})`. Each returns a sealed result (see step 2). Exposed as `appointmentStatusServiceProvider`. |
| `frontend/lib/features/appointments/application/appointment_status_action_result.dart` | application | `sealed class AppointmentStatusActionResult` with subclasses `AppointmentStatusActionSuccess(AppointmentStatus status)`, `AppointmentStatusActionFailed(String userMessage, {required bool doctorWasReassigned})`. The `doctorWasReassigned` flag is what makes the partial-write visible to the caller. |
| `frontend/lib/features/visits/application/visit_launch_service.dart` | Visits (application) | `VisitLaunchService.openOrCreateVisitForAppointment({required String appointmentId, required String? doctorId})` returning `VisitLaunchResult` (`visitId` or a user message). This is the single sanctioned entry point; it absorbs the current `VISIT_ALREADY_EXISTS` retry. Exposed as `visitLaunchServiceProvider`. |
| `frontend/lib/features/billing/application/appointment_invoice_summary_service.dart` | Billing (application) | `AppointmentInvoiceSummaryService.loadForAppointment({required String appointmentId})` returning `InvoiceDetail?` plus a reason enum for the "no visit" / "no invoice" cases. Exposed as `appointmentInvoiceSummaryServiceProvider`. |

**Suggested implementation steps:**

1. Create `application/appointment_status_action_result.dart` exactly as described in the table above.
2. Create `application/appointment_status_service.dart`. Constructor takes `AppointmentRepository`. Move the bodies of
   `_handleAdvanceStatus` (lines 226–293 of `appointment_detail_status_actions.dart`), `_handleRevertStatus`
   (336–379), `_handleCancel` (395–432) and `_handleMarkNoShow` (470–508) into it, **omitting** every `setState`,
   `mounted` check, `appToast` call and `AppDialog.show` call — those stay in the widget. Where the current code calls
   `appointmentMessageForRpc(error)`, keep that call inside the service and put the resulting string into
   `AppointmentStatusActionFailed.userMessage`.
3. In `AppointmentStatusService.advanceStatus`, wrap the two writes so the partial-write case is reported: set a local
   `var doctorWasReassigned = false;` before calling `updateAppointment`, set it to `true` immediately after that call
   returns, and pass it into `AppointmentStatusActionFailed` if `updateAppointmentStatus` then throws.
4. Add `final appointmentStatusServiceProvider = Provider<AppointmentStatusService>((ref) =>
   AppointmentStatusService(ref.watch(appointmentRepositoryProvider)));` at the bottom of the same file.
5. Rewrite `appointment_detail_status_actions.dart` so each `_handle*` method: computes its guard, shows its dialog,
   `await`s `ref.read(appointmentStatusServiceProvider).<method>(...)`, then switches on the sealed result to call
   `widget.onChanged()` + success toast, or a danger toast. When `AppointmentStatusActionFailed.doctorWasReassigned` is
   `true`, additionally call `widget.onChanged()` so the UI reflects the doctor change that did land.
6. Move `_resolveDoctorForStart` doctor-selection *rules* (lines 186–209) into
   `domain/appointment_queue_start_doctor.dart` as a new static
   `AppointmentQueueStartDoctor.autoResolveDoctorId({required AppointmentListItem item, required Iterable<AppointmentListItem> siblingAppointments, required AppointmentQueueShiftDoctorLookup shiftLookup})`.
   The widget keeps only "if `requiresDoctorPicker` then show `AppointmentStartDoctorDialog`, else use
   `autoResolveDoctorId`".
7. Create `frontend/lib/features/visits/application/visit_launch_service.dart`. Move the whole body of
   `_handleOpenVisit` (lines 75–124) and `_openExistingVisit` (128–147) into
   `VisitLaunchService.openOrCreateVisitForAppointment`, minus toasts and navigation.
8. Rewrite `appointment_detail_open_visit_button.dart` to import only
   `features/visits/application/visit_launch_service.dart` (delete the `features/visits/data/visit_repository.dart`
   import at line 12) and to call `ref.read(visitLaunchServiceProvider).openOrCreateVisitForAppointment(...)`, then
   `context.nav.pushVisitDocument(result.visitId)` or show the returned message.
9. Create `frontend/lib/features/billing/application/appointment_invoice_summary_service.dart` and move the three-call
   chain from `appointment_detail_invoice_summary_button.dart` lines 48–82 into it.
10. Rewrite `appointment_detail_invoice_summary_button.dart` to import only the new billing application service and
    `features/billing/presentation/widgets/visit_billing/visit_invoice_summary_dialog.dart`; delete the imports of
    `features/billing/data/invoice_repository.dart` (line 11) and `features/visits/data/visit_repository.dart` (line 12).
11. Verify: `rg -n "features/(visits|billing)/data/" frontend/lib/features/appointments` must return zero matches. Then
    `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## C3 — Doctor identity is resolved by full-name string matching, and the result is written back to the appointment

**Severity:** Critical

**Location:**

- `frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart`
  - `AppointmentQueueShiftDoctorLookup` fields `doctorNamesByNormalizedName` and `doctorIdsByNormalizedName`
    (lines 58–59) — the lookup is keyed on `fullName.toLowerCase()`.
  - `AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors` lines 68–106: builds those maps and, when two doctors share
    a lower-cased full name, adds the key to `ambiguousKeys` (line 86) and then **removes both entries entirely**
    (lines 93–96).
  - `_doctorNamesOnShiftAt` lines 156–198: for each shift, iterates `shift.assigneeNames` and resolves each name through
    `_resolveDoctorName` (lines 239–241).
  - `_queueShiftDoctorsForNames` lines 141–154: converts a resolved name back to an id via `_resolveDoctorId`
    (lines 243–245), producing `QueueShiftDoctor(id:, name:)`.
- `frontend/lib/features/appointments/presentation/providers/appointment_queue_shift_provider.dart`
  - `resolveQueueShiftDoctors` lines 63–139: matches shift assignees to staff with
    `assigneeKeys.contains(member.fullName.toLowerCase())` (lines 100 and 109), and synthesises a `StaffListItem` from a
    `ShiftBranchStaffMember` with `isActive: true` hard-coded (lines 74–79).
- Root cause on the Shifts side: `frontend/lib/features/shifts/domain/shift_list_item.dart` exposes
  `final List<String> assigneeNames;` (line 27) and `assigneeCount` (line 28) but **no assignee ids**.
- Write path that consumes the name-derived id:
  `frontend/lib/features/appointments/domain/appointment_queue_start_doctor.dart`
  `AppointmentQueueStartDoctor.shiftOptionsFor` lines 49–72 builds `QueueStartDoctorOption(id: doctor.id, ...)` from
  `shiftLookup.doctorsOnShiftAt(item.startTime)` (line 55); that option id flows through
  `frontend/lib/features/appointments/presentation/widgets/appointment_detail_status_actions.dart`
  `_resolveDoctorForStart` (lines 186–214) into
  `updateAppointment(appointmentId: ..., doctorId: selectedDoctorId, ...)` at lines 240–249.

**Issue:** The chain "which doctors are on shift right now" → "which doctor gets assigned to this patient" is resolved
entirely by comparing lower-cased human names. Two failure modes are directly evidenced in the code:

1. **Silent disappearance.** Two active doctors with the same display name (e.g. two "Ahmed Hassan") cause
   `fromShiftsAndDoctors` to delete both from the lookup (lines 93–96). They then never appear in
   `doctorsOnShiftAt`, so `AppointmentQueueStartDoctor.shiftOptionsFor` returns an empty list and
   `blockReasonForStart` reports `'No doctor is on shift for this appointment time.'`
   (`appointment_queue_start_doctor.dart` line 189) even though both are on shift.
2. **Wrong-doctor assignment.** `resolveQueueShiftDoctors` (queue shift provider lines 97–121) adds a fallback
   org-wide staff member whenever their name matches a shift assignee name, with no branch or shift-id check. Because
   the resulting id is written by `updateAppointment(doctorId: ...)`, a name collision between a branch doctor and an
   org-wide doctor can persist the wrong `doctor_id` onto a real appointment.

Additionally, `isActive: true` is fabricated at queue shift provider lines 74–79, so an inactive staff member surfaced
via `ShiftBranchStaffMember` is presented as active.

**Why it is a problem:** this is a data-integrity defect in a clinical record, not a cosmetic one. The persisted
`appointments.doctor_id` drives the visit, the encounter workspace and ultimately the invoice, so a mis-resolved doctor
propagates across Visits and Billing. The failure is silent — no exception, no log, only a misleading
"no doctor on shift" message or a quietly wrong assignment. Because the collision handling is *inside* the domain type,
it is also invisible at the call site.

**Recommended architectural solution:** stop using names as identity. `ShiftListItem` must carry assignee ids, and
`AppointmentQueueShiftDoctorLookup` must key on `staffId`. Names become display-only.

Target changes:

| File | Change |
| --- | --- |
| `frontend/lib/features/shifts/domain/shift_list_item.dart` | Add `final List<String> assigneeIds;` alongside `assigneeNames`; parse it in `fromRow` from the row key `assignee_ids` with a `_parseIdList` helper mirroring `_parseAssigneeNames` (lines 59–67). |
| `frontend/lib/features/shifts/data/shift_repository.dart` | Ensure the `list_shifts` RPC payload is read for `assignee_ids`. If the backend RPC does not yet return it, add a new domain-level `ShiftAssignee { String id; String fullName; }` and populate `assigneeIds` as empty until the RPC ships — then the lookup must fall back to *excluding* unresolvable assignees rather than name-matching them. |
| `frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart` | Replace `doctorNamesByNormalizedName` / `doctorIdsByNormalizedName` with a single `Map<String, QueueShiftDoctor> doctorsById`. Delete `_resolveDoctorName`, `_resolveDoctorId` and the whole `ambiguousKeys` block (lines 75, 85–96). `_doctorNamesOnShiftAt` becomes `_doctorsOnShiftAt` iterating `shift.assigneeIds` and looking up `doctorsById`. |
| `frontend/lib/features/appointments/presentation/providers/appointment_queue_shift_provider.dart` | `resolveQueueShiftDoctors` matches on `shift.assigneeIds` instead of names; drop the fabricated `isActive: true` and carry the real value through (see M1, which moves this function to `domain/`). |

**Suggested implementation steps:**

1. Confirm whether the `list_shifts` RPC already returns assignee ids: run
   `rg -n "assignee" backend/supabase/migrations` and inspect the newest `list_shifts` definition. Record the exact JSON
   key (expected `assignee_ids`).
2. If the key exists: in `frontend/lib/features/shifts/domain/shift_list_item.dart` add `required this.assigneeIds` to the
   constructor (after line 15), the field `final List<String> assigneeIds;` (after line 27), a
   `static List<String> _parseIdList(dynamic raw)` copied from `_parseAssigneeNames` (lines 59–67), and wire it in
   `fromRow` (lines 69–105). If the key does **not** exist, stop and file a backend task first — do not proceed with a
   name-based "fix".
3. Update every `ShiftListItem(` construction site: `rg -n "ShiftListItem\(" frontend/lib frontend/test`.
4. In `appointment_queue_shift_doctors.dart`: change the `AppointmentQueueShiftDoctorLookup` constructor and fields to
   `required this.doctorsById` of type `Map<String, QueueShiftDoctor>`; update `empty` (lines 61–66) to
   `doctorsById: {}`.
5. Rewrite `fromShiftsAndDoctors` (lines 68–106) to build `doctorsById` by `doctor.id` for every `doctors` entry whose
   `role == StaffRole.doctor`; delete `namesByKey`, `idsByKey`, `ambiguousKeys` and lines 93–96 entirely.
6. Rewrite `_doctorNamesOnShiftAt` (156–198) as
   `List<QueueShiftDoctor> _doctorsOnShiftAt(DateTime appointmentStartUtc, {bool requireCoveringInstant = true})`:
   keep the timezone/day/minute logic at lines 160–186 unchanged, but replace the inner loop at lines 187–192 with an
   iteration over `shift.assigneeIds` doing `final doctor = doctorsById[id]; if (doctor != null) doctors.add(doctor);`.
7. Simplify `doctorsOnCurrentShiftAt` (118–127) and `doctorsOnShiftAt` (130–134) to return `_doctorsOnShiftAt(...)`
   directly; delete `_queueShiftDoctorsForNames` (141–154), `_resolveDoctorName` (239–241) and `_resolveDoctorId`
   (243–245). Keep `doctorNamesOnShiftAt` as a thin
   `_doctorsOnShiftAt(...).map((d) => d.name).toList(growable: false)` for existing display call sites.
8. In `_isStaffedShift` (108–112) replace `shift.assigneeNames.isNotEmpty` with `shift.assigneeIds.isNotEmpty`.
9. In `appointment_queue_shift_provider.dart` `resolveQueueShiftDoctors`: replace the `assigneeKeys` name set
   (lines 87–95) with `final assigneeIds = {for (final s in shifts) ...s.assigneeIds};`, replace both name comparisons
   (lines 100 and 109) with `assigneeIds.contains(member.id)`, and change lines 74–79 to pass the member's real active
   flag instead of the literal `true`.
10. Update tests: `frontend/test/unit/appointments/appointment_queue_shift_doctors_test.dart`,
    `appointment_queue_start_doctor_test.dart`, `appointment_queue_doctor_rollback_test.dart`,
    `appointment_status_transitions_test.dart`. Add one new test asserting that two doctors sharing a full name are both
    returned by `doctorsOnShiftAt` — this is the regression this finding is about.
11. Verify: `rg -n "toLowerCase\(\)" frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart
    frontend/lib/features/appointments/presentation/providers/appointment_queue_shift_provider.dart` should show no
    identity comparisons (sorting comparators are fine). Then `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## H1 — `appointment_calendar_page.dart` is a 2,180-line god page with two near-duplicate reschedule pipelines

**Severity:** High

**Location:** `frontend/lib/features/appointments/presentation/pages/appointment_calendar_page.dart`
(2,180 lines; classes `AppointmentCalendarPage` 42–48, `_AppointmentCalendarPageState` 50–2106,
`_CalendarDragSession` 2108–2128, `_CalendarResizeSession` 2130–2153, `_CalendarPermissionDenied` 2155–2164,
`_CalendarSkeletonBody` 2166–2179).

`_AppointmentCalendarPageState` holds 22 mutable fields (lines 52–73) and 40 methods. The responsibilities bundled into
this one class are:

| Responsibility | Lines |
| --- | --- |
| Permission gating | 144–148, 183–188 |
| Filter/visible-item derivation and doctor-resource filtering | 163–179, 2040–2053 |
| Syncfusion `CalendarController` view/date synchronisation + fingerprint change detection | 54–59, 824–927, 962–983 |
| Skeleton reveal animation with generation counter | 61–63, 768–822 |
| Fullscreen `OverlayEntry` lifecycle | 67–73, 88–139, 211–237, 284–292 |
| Drag-and-drop reschedule (preview, validation, confirm dialog, RPC, revert) | 64–65, 985–1353 |
| Resize reschedule (same pipeline again) | 66, 1355–1714 |
| Booking sheet launch | 1850–1909 |
| Edit (prefetch detail then open sheet) | 1929–1984 |
| Cancel (dialog + RPC + refresh) | 1986–2034 |
| Navigation to detail | 1911–1927 |
| Syncfusion view/mode/height mapping | 2055–2089 |
| Toast + date formatting | 2091–2105 |
| `SfCalendar` construction and `appointmentBuilder` | 333–766 |

`_onAppointmentDragEnd` (1090–1353, 264 lines) and `_onAppointmentResizeEnd` (1477–1714, 238 lines) are structurally the
same pipeline — resolve the item, apply a snapped preview, `isNoOpMove` check, `AppointmentRescheduleValidation`
check, `AppointmentRescheduleConfirmDialog.show`, post-edit re-validation, `rescheduleAppointment`, `refresh()`, success
toast, and `_revertCalendarItems` on each of the seven early-exit branches. `_revertCalendarItems(...)` is called with
the same five arguments **11 times** inside `_onAppointmentDragEnd` alone.

**Issue:** a single `State` class owns realtime-adjacent data synchronisation, Syncfusion widget-library adaptation,
gesture-driven mutation workflows, overlay/window management, permission checks and user messaging. There is no seam at
which any of it can be tested or replaced.

**Why it is a problem:**

- *Change risk.* Any edit to the drag pipeline must be mirrored by hand in the resize pipeline; the two have already
  drifted (the resize path additionally decides resize-from-start vs resize-from-end at lines 1417–1419, and only the
  drag path validates doctor-resource moves at lines 1161–1188).
- *Untestable.* The reschedule workflow — the most defect-prone behaviour in the feature — can only be exercised through
  a full widget test driving Syncfusion gesture callbacks. The existing
  `frontend/test/unit/appointments/appointment_calendar_drag_reschedule_test.dart` therefore tests the domain validator,
  not this pipeline.
- *Readability.* 22 interdependent mutable fields with three separate ad-hoc change-detection mechanisms
  (`_itemsFingerprint`, `_resourceFingerprint`, `_statusFilterFingerprint`, `_themeFingerprint`, `_lastRevealSourceFingerprint`,
  `_calendarViewSyncScheduled`) make the frame lifecycle impossible to reason about locally (see also M6).

**Recommended architectural solution:** reduce the page to a composition shell and extract four cohesive collaborators.
Reschedule becomes one parameterised pipeline used by both gestures.

| New file | Contents |
| --- | --- |
| `presentation/controllers/appointment_calendar_sync_controller.dart` | `AppointmentCalendarSyncController` — a plain `ChangeNotifier`-free helper owning `_calendarController`, `_dataSource`, `_lastMode`, `_lastSyncedFocusDate`, all five fingerprints, `_syncedBrightness`, `_calendarViewSyncScheduled`; methods `syncDataSource`, `scheduleDataSourceSync`, `scheduleCalendarViewSync`, `syncCalendarView`, `onViewChanged`, `revertItems`, `applySnappedPreview`, `applyDragPreview`, `applyResizePreview`, plus the statics `calendarViewFor`, `modeForCalendarView`, `syncfusionViewHeaderHeight`, `isSameCalendarPeriod`, `weekStart`. |
| `presentation/controllers/appointment_calendar_reschedule_controller.dart` | `AppointmentCalendarRescheduleController` with one public method `Future<void> run(AppointmentRescheduleRequest request)` plus the moved `_CalendarDragSession` / `_CalendarResizeSession`. `AppointmentRescheduleRequest` carries `{item, newStart, newEnd, mode, schedule, branchAppointments, targetDoctorId}` so the drag and resize paths differ only in how the request is built. Delegates the RPC to the new `AppointmentRescheduleService` (below). |
| `presentation/controllers/appointment_calendar_fullscreen_controller.dart` | `AppointmentCalendarFullscreenController` owning `_fullscreenOverlay`, `_isCalendarFullscreen`, `_calendarHostHeight`, `_calendarHostKey`, `open`, `close`, `toggle`. |
| `presentation/controllers/appointment_calendar_reveal_controller.dart` | `AppointmentCalendarRevealController` owning `_revealedAppointmentIds`, `_revealGeneration`, `_lastRevealSourceFingerprint`, `scheduleRevealIfNeeded`, `startSkeletonReveal`, `dispose`. |
| `presentation/widgets/appointment_calendar_view.dart` | The whole of `_buildCalendar` (333–766) as a `StatelessWidget` `AppointmentCalendarView` taking the already-resolved state, layout, callbacks and colours. |
| `presentation/widgets/appointment_calendar_permission_denied.dart` and `presentation/widgets/appointment_calendar_skeleton_body.dart` | The extracted `_CalendarPermissionDenied` and `_CalendarSkeletonBody`. |
| `application/appointment_reschedule_service.dart` | `AppointmentRescheduleService.reschedule({required String appointmentId, required DateTime startTime, required DateTime endTime})` returning a sealed result, so the RPC call and `appointmentMessageForRpc` mapping leave the widget (consistent with C2). Exposed as `appointmentRescheduleServiceProvider`. |

**Suggested implementation steps:**

1. Create `application/appointment_reschedule_service.dart` with `AppointmentRescheduleService` (constructor takes
   `AppointmentRepository`) and `appointmentRescheduleServiceProvider`. Move the `try/catch` at lines 1293–1352 into it,
   returning a sealed `AppointmentRescheduleResult` (`Success` / `Failed(String userMessage)`).
2. Create `presentation/widgets/appointment_calendar_permission_denied.dart` and
   `presentation/widgets/appointment_calendar_skeleton_body.dart`; move `_CalendarPermissionDenied` (2155–2164) and
   `_CalendarSkeletonBody` (2166–2179) there, renaming to public `AppointmentCalendarPermissionDenied` /
   `AppointmentCalendarSkeletonBody`.
3. Create `presentation/controllers/appointment_calendar_reveal_controller.dart`; move fields at lines 61–63 and methods
   `_scheduleRevealIfNeeded` (768–804) and `_startSkeletonReveal` (806–822). Give it a `dispose()` that bumps
   `_revealGeneration` so pending delayed callbacks are cancelled. Instantiate it in `initState` and dispose in `dispose`.
4. Create `presentation/controllers/appointment_calendar_fullscreen_controller.dart`; move fields at lines 67–72 and
   methods `_toggleCalendarFullscreen` (88–94), `_openCalendarFullscreen` (96–130), `_closeCalendarFullscreen` (132–139).
   Pass the `_fullscreenCalendarBuilder` in as a callback argument rather than storing it as page state.
5. Create `presentation/controllers/appointment_calendar_sync_controller.dart`; move fields at lines 52–60 and 73 and
   methods `_scheduleDataSourceSync` (824–847), `_syncDataSource` (849–901), `_scheduleCalendarViewSync` (903–915),
   `_syncCalendarView` (917–927), `_onViewChanged` (929–960), `_isSameCalendarPeriod` (962–976), `_weekStart` (978–983),
   `_revertCalendarItems` (1716–1732), `_applySnappedPreview` (1734–1758), `_applyDragPreview` (1055–1072),
   `_applyResizePreview` (1441–1459), `_calendarViewFor` (2055–2063), `_syncfusionViewHeaderHeight` (2065–2078),
   `_modeForCalendarView` (2080–2089).
6. Create `presentation/controllers/appointment_calendar_reschedule_controller.dart`. Move `_CalendarDragSession` and
   `_CalendarResizeSession` into it. Define
   `class AppointmentRescheduleRequest { final AppointmentListItem item; final DateTime newStart; final DateTime newEnd;
   final AppointmentCalendarMode mode; final BranchWorkingSchedule schedule; final List<AppointmentListItem> branchAppointments;
   final String? targetDoctorId; }`.
7. Implement `AppointmentCalendarRescheduleController.run(request)` by copying `_onAppointmentDragEnd` lines 1147–1352
   **once**, replacing the drag-specific doctor-resource branch (1161–1188) with
   `if (request.mode == AppointmentCalendarMode.doctors && request.targetDoctorId != null) { ... }` and replacing the raw
   RPC block with a call to `appointmentRescheduleServiceProvider`. Replace the 11 repeated
   `_revertCalendarItems(items, doctors: ..., includeDoctorResources: ..., evenResourceRowColor: ..., oddResourceRowColor: ...)`
   calls with a single local closure `void revert() => sync.revertItems(...)`.
8. Reduce `_onAppointmentDragEnd` to: resolve `item` (1113–1123), compute `newStart`/`newEnd` (1125–1132), clear the drag
   session, build an `AppointmentRescheduleRequest` with
   `targetDoctorId: doctorIdFromCalendarResource(details.targetResource)`, and `await controller.run(request)`.
   Reduce `_onAppointmentResizeEnd` the same way, building the request with `targetDoctorId: null`.
9. Create `presentation/widgets/appointment_calendar_view.dart` and move `_buildCalendar` (333–766) into it verbatim as
   `AppointmentCalendarView.build`, converting each of its named parameters into a constructor field and each `_on*`
   handler into a callback field.
10. Reduce `build` (142–331) to: permission gate, provider watches, the derived values at lines 156–188, the three
    controller `schedule*` calls, and the `AppointmentPageShell` + `LayoutBuilder` + `AppointmentCalendarView` tree.
    Target under 150 lines.
11. Verify: `(Get-Content frontend/lib/features/appointments/presentation/pages/appointment_calendar_page.dart | Measure-Object -Line).Lines`
    should be under 300. Then `cd frontend; flutter analyze; flutter test test/unit/appointments`, and manually confirm
    drag, resize, fullscreen, booking, edit and cancel still work on `/appointments/calendar`.

## H2 — A `core/ui` design-system component imports the Appointments domain (core → feature inversion)

**Severity:** High

**Location:**

- `frontend/lib/core/ui/components/app_booking_slot_grid.dart`
  - line 10: `import 'package:ai_clinic/features/appointments/domain/appointment_booking_slots.dart';`
  - class `AppBookingSlotGrid` (line 13) declares `final List<AppointmentBookingTimeSlot> slots;` (line 23),
    `final ValueChanged<AppointmentBookingTimeSlot> onSlotSelected;` (line 26), and branches on
    `AppointmentBookingSlotStatus.locked` (line 55). The doc comment on line 12 reads "Time slot grid with legend for
    appointment booking step 2".
- Types being reached for:
  `frontend/lib/features/appointments/domain/appointment_booking_slots.dart` —
  `enum AppointmentBookingSlotStatus { locked, available, preferred, alternate }` (line 12) and
  `class AppointmentBookingTimeSlot` (lines 16–28).
- Consumer: `frontend/lib/features/appointments/presentation/widgets/appointment_booking_step2.dart` (the only user of
  `AppBookingSlotGrid`).

**Issue:** the shared design system depends on a feature. `core/` is the innermost shared layer in
`docs/architecture/07-frontend.md`, yet this component cannot compile without the Appointments feature present, and it is
explicitly named for one screen of one feature. The related components `app_booking_day_picker.dart`,
`app_booking_summary_card.dart` and `app_booking_step_rail.dart` correctly avoid feature imports, so this file is the
lone outlier in the booking component family.

**Why it is a problem:**

- *Dependency inversion.* Deleting or restructuring Appointments breaks `core/ui`. This defeats the modularity principle
  in `01-principles.md` ("Each can be specified, built, tested, and replaced independently").
- *Cycle risk.* Appointments already imports 17 files from `core/ui/widgets/widgets.dart`; this import closes a
  `core/ui ↔ features/appointments` loop at the package level, which prevents `core/` from ever being extracted into its
  own package and makes analyzer/build-graph reasoning harder.
- *Misplaced ownership.* Either the slot value type is shared UI vocabulary (in which case it belongs to `core`), or the
  widget is appointment-specific (in which case it belongs to the feature). The current split is the one arrangement that
  is wrong either way.

There is a broader pattern here: the same inversion exists at
`frontend/lib/core/ui/components/app_rich_text_editor.dart` (imports Visits' rich-text draft utilities) and
`frontend/lib/core/auth/auth_route_guard.dart` / `permission_service.dart` (import `features/auth/domain`). Those are out
of scope for this review but should be fixed by the same mechanism.

**Recommended architectural solution:** move the two slot value types into `core/`, since the widget's whole API is built
on them and `core/` has no domain folder yet. Create `frontend/lib/core/ui/models/booking_slot.dart` holding
`BookingSlotStatus` and `BookingTimeSlot`, and have Appointments' `AppointmentBookingSlots` produce those types instead of
its own.

Alternative considered and rejected: keeping the types in Appointments and generic-ising `AppBookingSlotGrid` over a
`<T>` plus adapter callbacks. Rejected because it adds generics to a design-system widget purely to hide a layering
mistake, and because `AppointmentBookingTimeSlot` has no appointment-specific fields — it is `{start, label, status,
availableDoctorIds}`, all of which are generic booking vocabulary.

**Suggested implementation steps:**

1. Create `frontend/lib/core/ui/models/booking_slot.dart` containing exactly:
   `enum BookingSlotStatus { locked, available, preferred, alternate }` and an `@immutable class BookingTimeSlot` with
   `final DateTime start; final String label; final BookingSlotStatus status; final List<String> availableDoctorIds;` and
   a `const` constructor with all four `required`. Import only `package:flutter/foundation.dart`.
2. In `frontend/lib/features/appointments/domain/appointment_booking_slots.dart`: delete the local
   `AppointmentBookingSlotStatus` enum (line 12) and `AppointmentBookingTimeSlot` class (lines 16–28); add
   `import 'package:ai_clinic/core/ui/models/booking_slot.dart';`; add
   `typedef AppointmentBookingTimeSlot = BookingTimeSlot;` and
   `typedef AppointmentBookingSlotStatus = BookingSlotStatus;` **temporarily** so the rest of the migration can proceed
   without touching every call site at once.
3. Fix the enum references inside the same file: `_resolveStatus` (lines 148–163), `resolveAssignedDoctorId` (129–130),
   `openSlotCount` (142–146) and the `slotsForDay` construction at lines 112–119 now build `BookingTimeSlot`.
4. In `frontend/lib/core/ui/components/app_booking_slot_grid.dart`: delete the import at line 10, add
   `import 'package:ai_clinic/core/ui/models/booking_slot.dart';`, and change the field types at lines 23 and 26 and the
   status comparison at line 55 to `BookingTimeSlot` / `BookingSlotStatus`. Search the remaining ~245 lines of the file
   (`_SlotButton` and the legend) with `rg -n "AppointmentBooking" frontend/lib/core/ui/components/app_booking_slot_grid.dart`
   and replace every remaining reference.
5. Replace the typedefs from step 2 with real renames: run
   `rg -n "AppointmentBookingTimeSlot|AppointmentBookingSlotStatus" frontend/lib frontend/test` and rewrite each hit to
   `BookingTimeSlot` / `BookingSlotStatus`. Known hits are in
   `frontend/lib/features/appointments/presentation/widgets/appointment_booking_step2.dart`,
   `frontend/lib/features/appointments/presentation/widgets/appointment_booking_sheet.dart`,
   `frontend/lib/features/appointments/domain/appointment_booking_slots.dart`, and
   `frontend/test/unit/appointments/appointment_booking_slots_test.dart`.
6. Delete the two typedefs from `appointment_booking_slots.dart`.
7. Verify: `rg -n "package:ai_clinic/features/" frontend/lib/core/ui/components/app_booking_slot_grid.dart` must return
   zero matches. Then `cd frontend; flutter analyze; flutter test test/unit/appointments/appointment_booking_slots_test.dart`.
8. Optional guard (see M8): add `app_booking_slot_grid.dart` to whatever boundary check M8 introduces so the import cannot
   come back.

## H3 — Real bidirectional feature cycles: Appointments ↔ Visits and Appointments ↔ Patients

**Severity:** High

**Location:**

*Appointments → Visits* (reach into another feature's `data/`):

- `frontend/lib/features/appointments/presentation/widgets/appointment_detail_open_visit_button.dart` line 12 →
  `features/visits/data/visit_repository.dart`; used at lines 76–85 and 129–131.
- `frontend/lib/features/appointments/presentation/widgets/appointment_detail_invoice_summary_button.dart` line 12 →
  same repository; used at lines 48–53.

*Visits → Appointments* (reach into Appointments' `presentation/providers/`):

- `frontend/lib/features/visits/presentation/pages/visit_document_page.dart` lines 11–12 →
  `appointments/domain/appointment_detail.dart` and `appointments/presentation/providers/appointment_detail_provider.dart`;
  `ref.watch(appointmentDetailProvider(visit.appointmentId))` at lines 119–129, navigation at line 260.
- `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` line 6 →
  `appointments/presentation/providers/appointment_surface_invalidation.dart`;
  `invalidateAppointmentAfterVisitCompleted(ref, appointmentId: ...)` at line 282.
- `frontend/lib/features/visits/presentation/widgets/visit_submitted_dialog.dart` line 6 →
  `appointment_detail_provider.dart`; used at lines 65, 93–99, 123.

*Appointments → Patients*:

- `frontend/lib/features/appointments/presentation/widgets/appointment_booking_step1.dart` lines 13–15 →
  `patients/domain/patient_list_item.dart`, `patients/domain/patient_list_scope.dart`, and
  `patients/presentation/widgets/patient_picker.dart` (a **presentation** reach-in); `PatientPicker` used at lines 75–79.
- `frontend/lib/features/appointments/presentation/widgets/appointment_booking_sheet.dart` line 28 →
  `patients/domain/patient_list_item.dart`; also **constructs** a `PatientListItem` from appointment fields at
  lines 156–163, fabricating `registeringBranchName: 'Branch'` when no branch name is supplied.

*Patients → Appointments* (reach into Appointments' `data/`):

- `frontend/lib/features/patients/presentation/providers/patient_detail_history_provider.dart` lines 5–7 →
  `appointments/data/appointment_repository.dart`, `appointment_list_item.dart`, `appointment_status.dart`;
  `ref.read(appointmentRepositoryProvider).listAppointments(...)` in `patientUpcomingAppointmentsProvider` at lines 77–90.
- `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart` line 10 and
  `frontend/lib/features/patients/presentation/widgets/patient_visit_record_card.dart` lines 4–6 use Appointments domain
  DTOs (acceptable) — `PatientVisitRecordCard.fromAppointment` at lines 39–63.

For contrast, the one-directional dependencies are fine: Appointments → Billing, → Shifts, → Clinic-Management,
→ Setup and → Auth have **no** return edge (verified by `rg` across `frontend/lib/features/{billing,shifts,clinic-management,setup,auth}`).

**Issue:** two genuine cycles exist, and in both cases at least one side crosses into the other feature's *internals*
rather than its public domain surface. Appointments calls `visitRepository.createVisit`; Patients calls
`appointmentRepository.listAppointments`; Visits calls Appointments' Riverpod providers, including the invalidation
helper that lives in `presentation/providers/`.

**Why it is a problem:**

- *Neither feature can be built or tested in isolation*, which is the explicit modularity requirement in
  `01-principles.md`. A unit test of `patientUpcomingAppointmentsProvider` must construct the Appointments repository and
  its Supabase client.
- *Invalidation coupling is fragile.* `invalidateAppointmentAfterVisitCompleted` lives in Appointments'
  `presentation/providers/` and is called from Visits' notifier, so a rename inside Appointments' presentation layer
  breaks Visits at compile time.
- *`PatientListItem` fabrication.* `appointment_booking_sheet.dart` lines 156–163 synthesises another feature's DTO with a
  placeholder `'Branch'` string, so the edit flow displays a fake registering-branch name. This is the classic symptom of
  a missing local view model.

Note: `ARCHITECTURAL_FLAWS.md` records nothing about these cycles. `L2` mentions layering inconsistency generally, but
the Appointments ↔ Visits and Appointments ↔ Patients cycles are new findings.

**Recommended architectural solution:**

1. Break Appointments → Visits/Billing `data/` reach-in by introducing the application-layer entry points already
   specified in **C2** (`VisitLaunchService`, `AppointmentInvoiceSummaryService`). After C2, Appointments depends only on
   `features/visits/application/**` and `features/billing/application/**`.
2. Break Patients → Appointments `data/` reach-in by having Appointments own a read API for its own data:
   create `frontend/lib/features/appointments/application/patient_appointments_query.dart` exposing
   `patientUpcomingAppointmentsForPatientProvider` as a `FutureProvider.autoDispose.family<List<AppointmentListItem>, String>`.
   Patients then watches that provider instead of constructing the repository. This keeps the edge (Patients still depends
   on Appointments) but restricts it to a sanctioned surface.
3. Break Visits → Appointments `presentation/providers/` reach-in by moving the invalidation helpers out of
   `presentation/` into `frontend/lib/features/appointments/application/appointment_surface_invalidation.dart` and
   treating that file as Appointments' published cache-coordination API (see also **M3**).
4. Introduce a local booking view model so Appointments stops fabricating `PatientListItem`:
   `frontend/lib/features/appointments/domain/appointment_booking_patient.dart` with
   `class AppointmentBookingPatient { final String id; final String fullName; final String? branchLabel; }` plus a
   `fromPatientListItem` factory and a `fromAppointmentDetail` factory.

**Suggested implementation steps:**

1. Complete **C2** steps 7–10 first. Then verify
   `rg -n "features/visits/data|features/billing/data" frontend/lib/features/appointments` returns nothing.
2. Create `frontend/lib/features/appointments/application/patient_appointments_query.dart` containing a
   `FutureProvider.autoDispose.family<List<AppointmentListItem>, String>` named
   `patientUpcomingAppointmentsForPatientProvider`. Move the body of `patientUpcomingAppointmentsProvider`
   (`frontend/lib/features/patients/presentation/providers/patient_detail_history_provider.dart` lines 77–90) into it
   verbatim, keeping the same branch/date/status arguments passed to `listAppointments`.
3. In `patient_detail_history_provider.dart`: delete the import of
   `appointments/data/appointment_repository.dart` (line 5); import the new
   `appointments/application/patient_appointments_query.dart`; change `patientUpcomingAppointmentsProvider` to
   `ref.watch(patientUpcomingAppointmentsForPatientProvider(patientId))` and return its value. Keep the
   `appointment_list_item.dart` / `appointment_status.dart` domain imports — those are legitimate.
4. Create `frontend/lib/features/appointments/application/appointment_surface_invalidation.dart` and move both functions
   from `frontend/lib/features/appointments/presentation/providers/appointment_surface_invalidation.dart`
   (`invalidateAppointmentSurfaceProviders` lines 9–15 and `invalidateAppointmentAfterVisitCompleted` lines 18–25)
   unchanged. Delete the old file.
5. Update the four importers of the old path:
   `frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart` line 12,
   `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` line 6,
   `frontend/lib/app/application/clinic_setup_orchestrator.dart` line 4,
   `frontend/lib/app/shell/dev/dev_clinic_seed_notifier.dart` line 22.
6. Create `frontend/lib/features/appointments/domain/appointment_booking_patient.dart` as described above.
7. In `frontend/lib/features/appointments/presentation/widgets/appointment_booking_sheet.dart`: change
   `PatientListItem? _selectedPatient;` (line 104) to `AppointmentBookingPatient? _selectedPatient;`; replace the
   fabricated construction at lines 156–163 with `AppointmentBookingPatient.fromAppointmentDetail(existing,
   branchLabel: widget.branchName)`; and where `PatientPicker` returns a `PatientListItem`, convert with
   `AppointmentBookingPatient.fromPatientListItem(...)`. Keep the `patients/domain/patient_list_item.dart` import only for
   that conversion boundary.
8. In `frontend/lib/features/appointments/presentation/widgets/appointment_booking_step1.dart`, leave the
   `patients/presentation/widgets/patient_picker.dart` import in place but add a `// TODO` noting it should be promoted to
   `features/patients/presentation/widgets/` public barrel; do not generic-ise the picker in this pass.
9. Verify with an explicit cycle check:
   `rg -n "features/appointments" frontend/lib/features/patients frontend/lib/features/visits` must show only
   `domain/` imports plus `application/` imports — no `data/` and no `presentation/providers/` hits.
   Then `cd frontend; flutter analyze; flutter test`.

## H4 — `AppointmentCalendarController.refresh()` has no request sequencing, so out-of-order responses render the wrong period

**Severity:** High

**Location:** `frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart`

- `AppointmentCalendarController.refresh()` lines 132–169. It reads `state.focusDate` / `state.mode` at lines 149–152,
  awaits `listAppointments` at lines 153–160, then unconditionally writes
  `state = state.copyWith(loading: false, items: items, error: null);` at line 161.
- Callers that can fire in rapid succession: `setMode` (171–177), `setFocusDate` (179–186), `goToToday` (188–191),
  `previousPeriod` (193–197), `nextPeriod` (199–203), `applyFilters` (205–233), `clearFilters` (235–250), the
  `authSessionProvider` listener (98–111), and `AppointmentCalendarController.refresh()` invoked externally after every
  mutation (e.g. `appointment_calendar_page.dart` lines 1304, 2010 and the booking-sheet success path).

**Issue:** there is no generation token, no cancellation and no check that the awaited response still corresponds to the
current `focusDate`/`mode`/filters. Clicking `nextPeriod` twice quickly issues two overlapping `list_appointments` RPCs;
whichever resolves last wins. If the first (older, wider or slower) response resolves second, the calendar displays week
N's appointments while the header, `_calendarController` display date and `slotLayout` all show week N+1.

The same class already demonstrates that the codebase knows the fix: `appointment_booking_sheet.dart` guards the
identical pattern with `int _branchAppointmentsRequestId = 0;` (line 112) and `final requestId = ++_branchAppointmentsRequestId;`
(line 218). `AppointmentQueueController.refresh()`
(`appointment_queue_provider.dart` lines 128–175) has the same gap and can additionally be re-entered from
`_onRealtimeChange` (line 338, `unawaited(refresh())`) while a refresh is already in flight.

**Why it is a problem:**

- *Silent wrong data.* Users see appointments for a day they are not looking at, with no error and no loading indicator,
  which in a scheduling application can lead staff to double-book or to tell a patient the wrong slot is free.
- *Compounding with drag-and-drop.* `appointment_calendar_page.dart` line 1304 awaits `refresh()` immediately after a
  reschedule RPC; if a period change is in flight at that moment the post-mutation refresh can be discarded, leaving the
  moved appointment at its old position until the next manual refresh.
- *Error state can also be stale.* The `catch (_)` at line 162 sets `items: const []` and an error string, so a *late*
  failure from a superseded request wipes a successfully loaded newer period.

**Recommended architectural solution:** add a monotonically increasing request generation to both notifiers and drop any
response whose generation is no longer current. Keep it local to the notifiers — no new files needed.

Target shape (described, not code): a private `int _requestGeneration = 0;` field on each controller; `refresh()`
increments it into a local `final generation = ++_requestGeneration;` before the first `await`, and every `state = ...`
assignment that happens **after** an `await` is guarded by `if (generation != _requestGeneration) return;`.

**Suggested implementation steps:**

1. In `appointment_calendar_provider.dart`, add `int _requestGeneration = 0;` as the first member of
   `AppointmentCalendarController` (immediately before `build()` at line 91).
2. In `refresh()`, insert `final generation = ++_requestGeneration;` immediately after the early-return branch at
   lines 134–141 (i.e. after the "Select an active branch" guard, before line 143).
3. Guard the success write: change line 161 to be preceded by
   `if (generation != _requestGeneration) { return; }`.
4. Guard the failure write: inside the `catch` block at lines 162–168, insert the same
   `if (generation != _requestGeneration) { return; }` before the `state = ...` assignment. Also replace `catch (_)` with
   `catch (error, stack)` and add `AppLog.warning('appointments.calendar.refresh_failed reason=${error.runtimeType}');`
   plus `AppLog.fine('appointments.calendar.refresh_failed.stack $stack');`, importing
   `package:ai_clinic/core/logging/app_log.dart` (this also resolves part of **M2**).
5. Do not clear `items` on failure any more: change line 165 from `items: const []` to omitting `items` entirely, so a
   transient failure does not blank an already-rendered period. Keep the error banner behaviour at
   `appointment_calendar_page.dart` lines 303–313 unchanged.
6. Apply the identical treatment to `AppointmentQueueController` in
   `frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart`: add
   `int _requestGeneration = 0;` next to `_realtimeListening` (line 75); in `refresh()` add
   `final generation = ++_requestGeneration;` after the branch guard at lines 129–137; guard the `state = state.copyWith(...)`
   at lines 156–167 and the `catch` write at lines 169–174.
7. In the same file, guard the realtime-triggered refresh so a burst of Postgres change events cannot stack refreshes:
   in `_onRealtimeChange` (lines 324–339) replace `unawaited(refresh());` at line 338 with a guarded call that first
   checks a new `bool _refreshInFlight` field, set to `true` at the top of `refresh()` and reset in a `finally`.
8. Replace `debugPrint` with `AppLog` in `appointment_queue_provider.dart` at lines 173, 220–222 and 247–249, importing
   `package:ai_clinic/core/logging/app_log.dart`.
9. Add regression tests in `frontend/test/unit/appointments/appointment_calendar_provider_test.dart`: using the existing
   `frontend/test/support/appointment_rpc_test_client.dart` fake, make the first `list_appointments` call resolve on a
   delayed future and the second resolve immediately, invoke `nextPeriod()` twice, and assert the final
   `state.items` correspond to the second request and `state.focusDate` matches.
10. Verify: `cd frontend; flutter analyze; flutter test test/unit/appointments/appointment_calendar_provider_test.dart test/unit/appointments/appointment_queue_provider_test.dart`.

## H5 — The queue subsystem has no UI consumer, yet opens a live Realtime subscription for every signed-in user

**Severity:** High

**Location:**

Queue subsystem (≈1,500 lines):

- `frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart` (366 lines) —
  `AppointmentQueueState`, `AppointmentQueueController` (realtime subscribe/unsubscribe, today + previous-working-day
  comparison fetch, `patchAppointmentStatus`), `appointmentQueueProvider`,
  `appointmentQueueCheckedInCountProvider` (348–351), `appointmentQueueShellWarmProvider` (355–365).
- `frontend/lib/features/appointments/data/appointment_queue_realtime.dart` (84 lines) —
  `SupabaseAppointmentQueueRealtimeClient.subscribe` (37–80) opens channel `appointments-queue-$branchId` with
  `onPostgresChanges` on `public.appointments`.
- `frontend/lib/features/appointments/data/appointment_queue_realtime_apply.dart` (100 lines).
- `frontend/lib/features/appointments/domain/appointment_queue_display.dart` (442 lines) — ~25 public static members.
- `frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart` (236 lines).
- `frontend/lib/features/appointments/domain/appointment_queue_start_doctor.dart` (225 lines).
- `frontend/lib/features/appointments/presentation/providers/appointment_queue_shift_provider.dart` (125 lines).
- `frontend/lib/features/appointments/presentation/widgets/appointment_start_doctor_dialog.dart` (93 lines).

Evidence of no consumer:

- `frontend/lib/app/router.dart` line 112: `GoRoute(path: AppRoutes.appointmentsQueue, builder: shellPlaceholderPage)` —
  **there is no `AppointmentQueuePage` anywhere in the repository.**
- The only reference to `appointmentQueueProvider` outside its own file is
  `frontend/lib/app/shell/authenticated_shell.dart` line 30, which watches `appointmentQueueShellWarmProvider` —
  a provider whose only purpose is to keep the queue alive.
- `appointmentQueueCheckedInCountProvider` (line 348, documented as feeding "the shell queue nav badge") has **no
  consumer**: `rg -n "badge" frontend/lib/app/shell/navigation/shell_nav_config.dart` returns nothing.
- Of the ~25 public members of `AppointmentQueueDisplay`, exactly one is called in `frontend/lib`:
  `AppointmentQueueDisplay.partition(items).waiting.length` at `appointment_queue_provider.dart` line 350 — inside the
  unconsumed count provider.
- The subsystem *is* covered by tests (`appointment_queue_display_test.dart`, `appointment_queue_provider_test.dart`,
  `appointment_queue_realtime_apply_test.dart`, `appointment_queue_shift_doctors_test.dart`,
  `appointment_queue_start_doctor_test.dart`, `appointment_queue_doctor_rollback_test.dart`), so it is deliberate,
  working, unshipped code rather than an accident.
- Genuinely live parts: `AppointmentQueueShiftDoctorLookup` and `AppointmentQueueStartDoctor` are used by
  `appointment_detail_status_actions.dart` and `appointment_status_transitions.dart`; `appointmentDetailShiftLookupProvider`
  is used by `appointment_detail_page.dart` lines 101 and 152.

**Issue:** `authenticated_shell.dart` line 30 warms `appointmentQueueShellWarmProvider` for every authenticated user. That
transitively builds `AppointmentQueueController`, which in `build()` (lines 77–107) schedules `refresh()` and
`_subscribeRealtime()`. So every signed-in workstation issues two `list_appointments` RPCs (today plus the previous
working day, lines 147–155 and 209–213) and holds an open Supabase Realtime channel for `public.appointments` — to feed a
count that nothing displays and a page that does not exist.

**Why it is a problem:**

- *Runtime cost with zero user value.* On the LAN-tier deployment targeted by `01-principles.md` (8 GB RAM, no GPU, local
  Supabase), every client keeps a websocket channel and re-fetches on every change event for nothing. `_onRealtimeChange`
  falls back to a full `refresh()` for every insert (`appointment_queue_realtime_apply.dart` line 34 returns `false` for
  `PostgresChangeEvent.insert`), so a busy clinic triggers repeated full list fetches per client.
- *Maintenance burden.* ~1,500 lines and six test files must be kept compiling and green while delivering nothing, and
  they are the most complex code in the feature (this is where **C3** hides).
- *Misleading documentation.* `docs/architecture/07-frontend.md` states `/appointments/queue` → "`AppointmentQueuePage` —
  today's queue (Realtime + manual refresh) — built". It is not built. This is a *new* doc/code inconsistency;
  `ARCHITECTURAL_FLAWS.md` records the analogous gaps for Billing (`H1`) and Shifts (`M3`) but not for the appointments
  queue.
- *Hidden coupling.* Because the queue never renders, `AppointmentQueueState.error` (set at lines 133–135 and 169–174) is
  never surfaced anywhere, so realtime degradation is invisible.

**Recommended architectural solution:** pick one of two outcomes explicitly and record it. Do not leave the subsystem
warmed-but-unrendered.

*Option A — stop warming it (recommended as the immediate step, ~15 minutes, no code deleted).* Remove the shell warm so
the cost disappears while the implementation and its tests stay available for the queue page work.

*Option B — ship or delete.* If the queue page is on the near roadmap, build
`presentation/pages/appointment_queue_page.dart` and wire it into `router.dart` line 112. If it is not, delete the queue
subsystem, its tests, and the placeholder route, keeping only `AppointmentQueueShiftDoctorLookup` and
`AppointmentQueueStartDoctor` (which the detail page genuinely uses) after renaming them per **M1**.

**Suggested implementation steps (Option A, then decide on B):**

1. In `frontend/lib/app/shell/authenticated_shell.dart`, delete line 30 (`ref.watch(appointmentQueueShellWarmProvider);`)
   and its now-unused import at line 18. Keep line 31 (`appointmentCalendarShellWarmProvider`) — the calendar page is real.
2. Move the clinic-data invalidation wiring that currently lives inside `appointmentQueueShellWarmProvider`
   (`appointment_queue_provider.dart` lines 355–365) into `appointmentCalendarShellWarmProvider`
   (`appointment_calendar_provider.dart` lines 296–298), so `invalidateAppointmentSurfaceProviders` still runs when
   `clinicDataChangedProvider` ticks. Concretely: add `ref.watch(clinicDataChangedProvider);` and
   `ref.listen<int>(clinicDataChangedProvider, (_, _) { invalidateAppointmentSurfaceProviders(ref); });` to
   `appointmentCalendarShellWarmProvider`, importing `app/application/clinic_data_changed_provider.dart` and the
   invalidation helper.
3. Delete `appointmentQueueShellWarmProvider` (lines 355–365) and `appointmentQueueCheckedInCountProvider`
   (lines 348–351) from `appointment_queue_provider.dart`.
4. Because step 3 removes the last `AppointmentQueueDisplay` call site, mark the class as unshipped: add a file-level doc
   comment to `domain/appointment_queue_display.dart` reading
   `/// Unshipped: queue UI is not built (router.dart uses a placeholder for /appointments/queue).` Do the same for
   `appointment_queue_provider.dart`, `data/appointment_queue_realtime.dart` and
   `data/appointment_queue_realtime_apply.dart`.
5. Update `docs/architecture/07-frontend.md`: in the V1-4 appointment routes table, change the
   `/appointments/queue` row from "`AppointmentQueuePage` — today's queue (Realtime + manual refresh) — built" to
   "**Placeholder** — queue page not built; queue provider/domain implemented but not wired". Also correct the
   "Layering Inconsistency" table entry for appointments from "Realtime queue via `StreamProvider`" to
   "Realtime queue via `NotifierProvider` + manual Supabase channel (not currently rendered)".
6. Add a row to `docs/architecture/ARCHITECTURAL_FLAWS.md` under **High**:
   `H8 | frontend/lib/features/appointments/{presentation/providers,data,domain} queue files vs router.dart:112 | Queue subsystem (~1,500 lines) implemented and tested but no page; docs claim built | Dead weight + previously an idle Realtime channel per client | Build AppointmentQueuePage or delete the subsystem; shell warm removed`.
7. Verify: `rg -n "appointmentQueueShellWarmProvider|appointmentQueueCheckedInCountProvider" frontend/lib` returns nothing;
   `cd frontend; flutter analyze; flutter test`. Then launch the app and confirm no `appointments-queue-` channel is
   created (search the debug console for `appointments-queue-`).
8. Record the Option B decision in `docs/architecture/12-roadmap-phases.md` so the subsystem's fate is explicit.

## H6 — Appointment mutations are duplicated across 13 widget/page call sites with copy-pasted error handling

**Severity:** High

**Location:** every direct `appointmentRepositoryProvider` call site in `presentation/`:

| File | Lines | Repository method |
| --- | --- | --- |
| `presentation/pages/appointment_calendar_page.dart` | 1294–1300 | `rescheduleAppointment` (drag) |
| `presentation/pages/appointment_calendar_page.dart` | 1656–1661 | `rescheduleAppointment` (resize) |
| `presentation/pages/appointment_calendar_page.dart` | 1942–1943 | `getAppointment` (edit prefetch) |
| `presentation/pages/appointment_calendar_page.dart` | 1997–1998 | `cancelAppointment` |
| `presentation/widgets/appointment_booking_sheet.dart` | 188–190 | `getSettings` |
| `presentation/widgets/appointment_booking_sheet.dart` | 228–233 | `listAppointments` |
| `presentation/widgets/appointment_booking_sheet.dart` | 542–551 | `updateAppointment` |
| `presentation/widgets/appointment_booking_sheet.dart` | 554–563 | `createAppointment` |
| `presentation/widgets/appointment_detail_status_actions.dart` | 240–249 | `updateAppointment` |
| `presentation/widgets/appointment_detail_status_actions.dart` | 252–257 | `updateAppointmentStatus` (advance) |
| `presentation/widgets/appointment_detail_status_actions.dart` | 338–343 | `updateAppointmentStatus` (revert) |
| `presentation/widgets/appointment_detail_status_actions.dart` | 397–399 | `cancelAppointment` |
| `presentation/widgets/appointment_detail_status_actions.dart` | 472–474 | `markAppointmentNoShow` |

Duplicated logic across these sites:

- **Cancel appears twice, differently.** `appointment_calendar_page.dart._cancelAppointment` (1986–2034) and
  `appointment_detail_status_actions.dart._handleCancel` (382–433) each show `AppointmentCancelDialog`, call
  `cancelAppointment`, refresh/notify, and toast — with different success strings and different refresh targets (the page
  calls `appointmentCalendarProvider.notifier.refresh()`, the widget calls `widget.onChanged()`).
- **Edit eligibility diverges.** `appointment_calendar_tile_context_menu.dart` lines 40–42 allow edit when
  `!item.status.isTerminal`; `appointment_detail_edit_button.dart` lines 36–46 use the same rule; but
  `appointment_booking_sheet.dart._canEditSchedule` (lines 134–136) only allows schedule edits when the status is exactly
  `scheduled`. So the calendar context menu offers "Edit" for a `confirmed` appointment and then silently opens a sheet
  with the time step skipped (`_skipsTimeStep`, line 142).
- **The `on RpcFailure catch → appointmentMessageForRpc → danger toast` + `catch (_) → generic danger toast` pair is
  written out 10 times** (calendar page 1316–1349, 1968–1980 and 2019–2031; status actions 271–292, 357–378, 411–431 and
  486–507; open-visit button 93–124; invoice button 88–112).
- **Permission checks use two different APIs for the same predicate.** The calendar page uses
  `ref.watch(permissionServiceProvider).canAccessAppointments()` / `.canCreateAppointments()` / `.canCancelAppointments()`
  (lines 144–146, 183–188), while the detail surfaces use
  `ref.watch(authSessionProvider.select(AuthRouteGuard.canAccessAppointmentHub))` etc.
  (`appointment_detail_page.dart` line 48, `appointment_detail_status_actions.dart` lines 57–65). `AuthRouteGuard`
  delegates to `PermissionService` (`frontend/lib/core/auth/auth_route_guard.dart` lines 87–105), so behaviour matches,
  but there are two spellings of every check.
- **Two `_StatusChip` implementations** exist: `appointment_detail_page.dart` line 594 and
  `appointment_calendar_tile.dart` line 468.
- **Two range formatters** exist with different formats: `appointment_calendar_page.dart._formatRange` (2097–2105, uses
  `Hm`) and `appointment_reschedule_confirm_dialog.dart` (295–302, uses `h:mm a`).

**Issue:** the feature has no single place that knows "how to cancel an appointment", "how to edit an appointment", or
"how to report an appointment RPC failure". Each surface re-derives it.

**Why it is a problem:** every new appointment surface (a queue page, a doctor-schedule page, a patient-detail action)
must re-implement the same five workflows and will drift again, as the edit-eligibility mismatch already shows. The
duplicated `catch` blocks mean an improvement to error reporting has to be applied in 10 places. The two `_StatusChip`s
and two range formats make the UI visibly inconsistent between the calendar and the detail page.

**Recommended architectural solution:** build on the `AppointmentStatusService` introduced in **C2**, add two shared
presentation helpers, and pick one permission API.

| New file | Contents |
| --- | --- |
| `application/appointment_status_service.dart` (from C2) | The single owner of advance / revert / cancel / no-show, including `appointmentMessageForRpc` mapping. |
| `application/appointment_reschedule_service.dart` (from H1) | The single owner of reschedule. |
| `application/appointment_edit_policy.dart` | `AppointmentEditPolicy` with `canEditAppointment(AppointmentStatus)`, `canEditSchedule(AppointmentStatus)`, `editDisabledReason(...)`, `cancelDisabledReason(...)`. Single source for the eligibility rules currently split three ways. |
| `presentation/widgets/appointment_status_chip.dart` | One public `AppointmentStatusChip` replacing both private `_StatusChip`s. |
| `presentation/formatting/appointment_range_format.dart` | One `formatAppointmentRange(DateTime start, DateTime end)` replacing both formatters. Pick the `h:mm a` variant to match the detail page (`appointment_detail_page.dart` line 126 `_timeFormat`). |

**Suggested implementation steps:**

1. Complete **C2** steps 1–6 and **H1** step 1 so the two services exist.
2. Create `application/appointment_edit_policy.dart`. Move `_canEditAppointment` / `_editDisabledReason` /
   `_cancelDisabledReason` from `presentation/widgets/appointment_calendar_tile_context_menu.dart` (lines 40–67), the
   `_disabledReason` logic from `presentation/widgets/appointment_detail_edit_button.dart` (lines 36–46), and
   `_canEditSchedule` / `_skipsTimeStep` from `presentation/widgets/appointment_booking_sheet.dart` (lines 134–142) into
   it. Reconcile the divergence explicitly: keep `canEditAppointment == !status.isTerminal` and
   `canEditSchedule == status == AppointmentStatus.scheduled`, and have the context menu label the action "Edit details"
   when `canEditAppointment && !canEditSchedule` so the UI no longer promises a time edit it will not offer.
3. Update those three widgets to call `AppointmentEditPolicy` and delete their local copies.
4. Delete `_cancelAppointment` from `appointment_calendar_page.dart` (lines 1986–2034) and have the context-menu
   `onCancel` callback (line 606–607) call a new small shared widget-level helper
   `presentation/widgets/appointment_cancel_action.dart` exposing
   `Future<bool> runAppointmentCancelFlow(BuildContext context, WidgetRef ref, AppointmentListItem item)` that shows
   `AppointmentCancelDialog`, calls `appointmentStatusServiceProvider.cancel(...)`, toasts, and returns whether it
   succeeded. Have `appointment_detail_status_actions.dart._handleCancel` call the same helper.
5. Create `presentation/widgets/appointment_status_chip.dart` by promoting the richer of the two implementations
   (`appointment_calendar_tile.dart` line 468). Replace `_StatusChip` usages in `appointment_detail_page.dart` (line 594)
   and `appointment_calendar_tile.dart`, then delete both private classes.
6. Create `presentation/formatting/appointment_range_format.dart` with a single top-level
   `String formatAppointmentRange(DateTime start, DateTime end)` using `DateFormat('EEE, MMM d')` +
   `DateFormat('h:mm a')`. Replace `_formatRange` in `appointment_calendar_page.dart` (2097–2105) and the equivalent in
   `appointment_reschedule_confirm_dialog.dart` (295–302).
7. Standardise permissions on `AuthRouteGuard` (it is the API the router already uses at
   `frontend/lib/core/auth/auth_route_guard.dart` lines 285–287). In `appointment_calendar_page.dart` replace
   `ref.watch(permissionServiceProvider).canAccessAppointments()` (144–146) with
   `ref.watch(authSessionProvider.select(AuthRouteGuard.canAccessAppointmentHub))`, `.canCreateAppointments()`
   (183–185) with `AuthRouteGuard.canAccessAppointmentBooking`, and `.canCancelAppointments()` (186–188) with
   `AuthRouteGuard.canAccessAppointmentCancelActions`.
8. Verify: `rg -n "appointmentRepositoryProvider" frontend/lib/features/appointments/presentation` should match only
   read-only fetches (`getSettings`, `listAppointments`, `getAppointment`) — every mutation should now go through
   `application/`. Also `rg -n "permissionServiceProvider" frontend/lib/features/appointments` should return nothing.
   Then `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## M1 — Business logic lives in `presentation/providers/`, and its fetch orchestration is duplicated

**Severity:** Medium

**Location:**

- `frontend/lib/features/appointments/presentation/providers/appointment_queue_shift_provider.dart`
  - `resolveQueueShiftDoctors(...)` lines 63–139 — a **pure, top-level, side-effect-free function** (188 lines of the
    file's 125-line provider body plus this function) implementing doctor-eligibility rules: branch staff first, then
    shift assignees, then org-wide fallback, then a last-resort "all branch doctors, else all active org doctors" pass
    (lines 123–134), finishing with `..sort(StaffListItem.compareByFullName)`.
  - `appointmentQueueShiftDoctorLookupProvider` lines 16–60 — fetch orchestration: timezone resolution (22–35),
    `shiftRepository.listShifts` (38–42), `shiftRepository.listActiveStaffForBranch` (43–45),
    `listStaffUseCaseProvider` (50–52), then `AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors` (55–59).
- `frontend/lib/features/appointments/presentation/providers/appointment_detail_shift_provider.dart`
  - line 8 imports the sibling provider file **solely to reuse `resolveQueueShiftDoctors`**.
  - `appointmentDetailShiftLookupProvider` lines 37–86 repeats the same orchestration for a specific appointment day:
    timezone resolution (47–60), `listShifts` (63–67), `listActiveStaffForBranch` (68–70),
    `listStaffUseCaseProvider` (71–73), `resolveQueueShiftDoctors` (75–79), `fromShiftsAndDoctors` (81–85).

**Issue:** a domain rule sits in the presentation layer, and one provider file imports another provider file to borrow it.
The surrounding fetch sequence (three async calls in a fixed order, then one factory) is written twice with only the
date range differing (`today` vs `appointmentDay`).

**Why it is a problem:**

- *Layer inversion.* `docs/architecture/07-frontend.md` places value objects and rules in `domain/`; a pure function that
  decides which clinicians are eligible for an appointment is domain logic. Its current location means any non-provider
  caller (e.g. a future queue page, or a test) must import a Riverpod provider file.
- *Drift risk.* The two orchestrations already differ subtly: the queue provider awaits `listStaffUseCaseProvider`
  *inline inside the argument list* (line 50) while the detail provider awaits it into a local first (line 71); and the
  detail provider uses `ref.read(authSessionProvider)` (line 48) while the queue provider uses
  `ref.watch(authSessionProvider.select(...))` (lines 18–27), so the two disagree about whether they rebuild on session
  change.
- *Hides C3.* The name-matching defect in **C3** lives in this function; having it in `presentation/providers/` is why it
  has no dedicated domain test file of its own.

**Recommended architectural solution:** move the rule into `domain/`, and factor the repeated fetch into one
parameterised provider that both call sites use.

| New/changed file | Contents |
| --- | --- |
| `frontend/lib/features/appointments/domain/appointment_shift_doctor_resolution.dart` | The moved `resolveQueueShiftDoctors`, renamed `resolveShiftDoctors`. Imports only `clinic-management/domain/staff_list_item.dart`, `shifts/domain/shift_branch_staff.dart`, `shifts/domain/shift_list_item.dart` and `auth/domain/auth_session.dart` (for `StaffRole`). |
| `frontend/lib/features/appointments/presentation/providers/appointment_shift_lookup_provider.dart` | A single `FutureProvider.autoDispose.family<AppointmentQueueShiftDoctorLookup, AppointmentShiftLookupQuery>` named `appointmentShiftLookupProvider`, where `AppointmentShiftLookupQuery { String branchId; DateTime? day; }` and `day == null` means "today in org timezone". Replaces both existing providers. |

**Suggested implementation steps:**

1. Create `domain/appointment_shift_doctor_resolution.dart`. Move `resolveQueueShiftDoctors` (queue shift provider
   lines 63–139) verbatim, rename it to `resolveShiftDoctors`, and add the four imports listed above.
2. Create `presentation/providers/appointment_shift_lookup_provider.dart` with an `@immutable`
   `AppointmentShiftLookupQuery` class (`branchId`, nullable `day`, `==`/`hashCode` following the existing
   `AppointmentDetailShiftQuery` pattern at `appointment_detail_shift_provider.dart` lines 13–34).
3. Implement `appointmentShiftLookupProvider` by copying `appointmentDetailShiftLookupProvider` (lines 37–86) and
   replacing the day computation: if `query.day != null` use the existing `tz.TZDateTime.from(query.day!.toUtc(), location)`
   normalisation (lines 51–60); otherwise use `tz.TZDateTime.from(DateTime.now().toUtc(), location)` as the queue provider
   does (lines 33–35). Use `ref.watch(authSessionProvider.select((s) => s.context?.organizationTimezone))` so both
   call sites get consistent rebuild behaviour.
4. Return `AppointmentQueueShiftDoctorLookup.empty` when `query.branchId.trim().isEmpty` (matching both current guards at
   queue provider lines 28–30 and detail provider lines 42–45).
5. Delete `appointmentQueueShiftDoctorLookupProvider` from `appointment_queue_shift_provider.dart` and delete
   `appointmentDetailShiftLookupProvider` from `appointment_detail_shift_provider.dart`; delete both files once empty
   (`appointment_queue_shift_provider.dart` and `appointment_detail_shift_provider.dart`).
6. Update call sites:
   - `frontend/lib/features/appointments/presentation/pages/appointment_detail_page.dart` lines 100–107 and 144–153:
     replace `appointmentDetailShiftLookupProvider(AppointmentDetailShiftQuery(branchId: ..., appointmentStart: ...))`
     with `appointmentShiftLookupProvider(AppointmentShiftLookupQuery(branchId: detail.branchId, day: detail.startTime))`.
   - `frontend/lib/features/appointments/presentation/providers/appointment_surface_invalidation.dart` line 12:
     replace `ref.invalidate(appointmentQueueShiftDoctorLookupProvider)` with
     `ref.invalidate(appointmentShiftLookupProvider)`.
7. Move the tests: rename `frontend/test/unit/appointments/appointment_queue_shift_doctors_test.dart` tests that exercise
   `resolveQueueShiftDoctors` into a new `frontend/test/unit/appointments/appointment_shift_doctor_resolution_test.dart`
   and update the import + function name.
8. Verify: `rg -n "resolveQueueShiftDoctors|appointmentQueueShiftDoctorLookupProvider|appointmentDetailShiftLookupProvider" frontend`
   returns nothing. Then `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## M2 — Lossy and inconsistent error handling: raw exception text shown to users, diagnostics discarded, malformed payload silently becomes an empty list

**Severity:** Medium

**Location:**

- **Raw exception text rendered in the UI.**
  `frontend/lib/features/appointments/presentation/pages/appointment_detail_page.dart`
  `AppointmentDetailPage.build` error branch, line 67: `message: error.toString()`. Because
  `frontend/lib/features/appointments/presentation/providers/appointment_detail_provider.dart` lines 15–17 throw a bare
  `StateError` for permission denial, a permission failure renders as
  `Bad state: <internal message>` in `_AppointmentDetailErrorView`.
- **Malformed RPC payload silently yields an empty result.**
  `frontend/lib/features/appointments/data/appointment_repository.dart` `listAppointments`, lines 190–194:
  ```dart
  final rawItems = result.data?['items'];
  if (rawItems is! List) {
    return const [];
  }
  ```
  Every other method in the same class throws `StateError('... returned an unexpected shape.')` in this situation
  (lines 48–51, 72, 137, 153, 221–224, 285, 323, 356). `listAppointments` is the only exception, and it is the method that
  feeds the calendar, the queue and the booking sheet's conflict detection.
- **Rows with unknown wire values are silently accepted.**
  `frontend/lib/features/appointments/domain/appointment_list_item.dart` `fromRow` lines 64–66 fall back to
  `AppointmentType.unknown` / `AppointmentStatus.unknown` rather than rejecting the row, so a bad enum value surfaces in
  the UI as an appointment with no status styling.
- **`catch (_)` discarding diagnostics** (10 sites): `appointment_calendar_provider.dart` line 162;
  `appointment_booking_sheet.dart` lines 242–250 (a failed day-appointments fetch silently produces
  `_branchAppointments = const []`, so the slot grid shows every slot as free);
  `appointment_calendar_page.dart` lines 1972 and 2023; `appointment_detail_status_actions.dart` lines 281, 367, 421, 496;
  `appointment_detail_open_visit_button.dart` line 110; `appointment_detail_invoice_summary_button.dart` line 98.
- **`debugPrint` used instead of the project logger** in `appointment_queue_provider.dart` lines 173, 220–222, 247–249,
  and in `appointment_list_item.dart` lines 72–79 (a `debugPrint` inside a domain DTO). The project has
  `frontend/lib/core/logging/app_log.dart` (`AppLog.info` / `warning` / `fine`), used correctly by
  `data/doctor_dev_seed_service.dart` lines 55, 76, 82–84, 92–95.
- **User-facing English strings inside the repository.** `appointment_repository.dart` lines 38, 100, 110, 254, 342, 378,
  400 build `RpcResult.errorMessage` strings like `'Notes must be 2000 characters or fewer.'` and `'$field is required.'`,
  bypassing `application/appointment_rpc_messages.dart` which is the designated message-mapping layer.

**Issue:** four different error strategies coexist — throw a typed `RpcFailure`, throw a bare `StateError`, return an empty
list, or swallow. The presentation layer then either maps `RpcFailure` correctly, or prints `error.toString()`, or shows a
generic string having discarded the cause.

**Why it is a problem:**

- *Silent wrong data.* The two "return empty" paths are the dangerous ones: a malformed `list_appointments` payload makes
  the calendar look like an empty day, and a failed branch-appointments fetch in the booking sheet makes every slot look
  bookable, which can produce a double booking that the server then rejects with a confusing conflict error.
- *Undiagnosable field reports.* With `catch (_)` in 10 places and no logging, "the calendar didn't load" produces no
  artefact on a clinic workstation.
- *PHI/internal leakage.* `error.toString()` on a `PostgrestException` can print SQL details or internal messages to a
  shared reception screen.
- *Layering.* Validation message text in `data/` cannot be localised or reworded without editing the repository.

**Recommended architectural solution:** make `RpcFailure` the only error currency crossing layer boundaries; map to user
text in exactly one place per feature (`application/appointment_rpc_messages.dart`); log every swallowed error via
`AppLog`; and make malformed payloads loud.

New/changed:

| File | Change |
| --- | --- |
| `frontend/lib/features/appointments/application/appointment_rpc_messages.dart` | Add `String appointmentMessageForError(Object error)` that returns `appointmentMessageForRpc(error)` for `RpcFailure`, and otherwise delegates to `UserErrorMapper.mapToUserMessage(error)` (already used at `appointment_booking_sheet.dart` line 206). This becomes the single entry point for all appointment error text. |
| `frontend/lib/features/appointments/data/appointment_repository.dart` | Replace inline English strings with codes; `listAppointments` throws on malformed payload. |
| `frontend/lib/features/appointments/presentation/providers/appointment_detail_provider.dart` | Throw `RpcFailure` with code `PERMISSION_DENIED` instead of `StateError`. |

**Suggested implementation steps:**

1. In `application/appointment_rpc_messages.dart`, add `appointmentMessageForError(Object error)` as described, importing
   `package:ai_clinic/core/utils/user_error_mapper.dart`. Add a `PERMISSION_DENIED` case to the existing
   `appointmentMessageForRpc` switch returning `'You do not have permission to view this appointment.'`.
2. In `presentation/providers/appointment_detail_provider.dart` lines 15–17, replace the `StateError` throw with
   `throw RpcFailure(const RpcResult(success: false, errorCode: 'PERMISSION_DENIED', errorMessage: 'Permission denied.'));`
   importing `package:ai_clinic/core/rpc/rpc_result.dart`.
3. In `presentation/pages/appointment_detail_page.dart` line 67, replace `message: error.toString()` with
   `message: appointmentMessageForError(error)` and add the import of
   `package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart`.
4. In `data/appointment_repository.dart` `listAppointments`, replace lines 192–194 with a throw:
   `throw StateError('List appointments returned an unexpected shape.');` — matching the other nine methods.
5. In `data/appointment_repository.dart`, change the seven inline `errorMessage` strings (lines 38, 100, 110, 254, 342,
   378, 400) to stable machine codes by leaving `errorCode` as-is and setting `errorMessage` to a short non-user-facing
   token (e.g. `'branch_id_required'`, `'notes_too_long'`, `'start_time_required'`, `'cancel_reason_too_long'`,
   `'field_required'`, `'duration_below_minimum'`). Then add the corresponding user text for each code to
   `appointmentMessageForRpc`.
6. Replace all 10 `catch (_)` sites listed in the Location section with `catch (error, stack)` plus
   `AppLog.warning('appointments.<surface>.<action>_failed reason=${error.runtimeType}');` and
   `AppLog.fine('appointments.<surface>.<action>_failed.stack $stack');`, importing
   `package:ai_clinic/core/logging/app_log.dart`. Keep the existing user-facing toast text unchanged. Use these surface
   names: `calendar`, `booking_sheet`, `detail_status_actions`, `detail_open_visit`, `detail_invoice_summary`.
7. In `presentation/widgets/appointment_booking_sheet.dart` lines 242–250, additionally surface the failure rather than
   pretending there are no appointments: add a `String? _branchAppointmentsError` field, set it in the catch, and render an
   inline warning above the slot grid in step 2 (`appointment_booking_step2.dart`) when it is non-null, disabling slot
   selection while it is set.
8. Replace the `debugPrint` calls in `presentation/providers/appointment_queue_provider.dart` (lines 173, 220–222,
   247–249) with `AppLog.warning` / `AppLog.fine`.
9. Remove the `debugPrint` block from `domain/appointment_list_item.dart` lines 72–79 and its
   `package:flutter/foundation.dart` import if `@immutable` is the only other usage (keep the import if `@immutable` is
   still needed). Domain code must not log to the console.
10. In `domain/appointment_list_item.dart` `fromRow` lines 64–66, keep the `unknown` fallback (changing it is a behaviour
    change out of scope) but add a `bool get hasUnknownWireValues => type == AppointmentType.unknown || status == AppointmentStatus.unknown;`
    so surfaces can flag such rows instead of silently rendering them.
11. Verify: `rg -n "catch \(_\)" frontend/lib/features/appointments` and
    `rg -n "debugPrint" frontend/lib/features/appointments` must both return nothing;
    `rg -n "error\.toString\(\)" frontend/lib/features/appointments` must return nothing.
    Then `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## M3 — Cache invalidation is ad hoc; the detail page bypasses the shared helper and omits the queue

**Severity:** Medium

**Location:**

- `frontend/lib/features/appointments/presentation/providers/appointment_surface_invalidation.dart` — the intended
  single source of truth:
  - `invalidateAppointmentSurfaceProviders(Ref ref)` lines 9–15 invalidates `appointmentQueueProvider`,
    `appointmentCalendarProvider`, `appointmentQueueShiftDoctorLookupProvider`, `appointmentCalendarBranchesProvider`,
    `appointmentCalendarDoctorsProvider`.
  - `invalidateAppointmentAfterVisitCompleted(Ref ref, {required String appointmentId})` lines 18–25 invalidates
    `appointmentDetailProvider(appointmentId)`, `appointmentCalendarProvider`, `appointmentQueueProvider`.
- `frontend/lib/features/appointments/presentation/pages/appointment_detail_page.dart`
  `AppointmentDetailPage._invalidateSurfaces` lines 90–109 — a **fourth, hand-rolled** invalidation set: detail, siblings,
  shift lookup, calendar. It **omits `appointmentQueueProvider`**, and it does not use the shared helper. It is wired as
  `onChanged: () => _invalidateSurfaces(ref, detail)` at line 77 and is therefore what runs after every status advance,
  revert, cancel and no-show performed from the detail page.
- `frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart`
  `appointmentQueueShellWarmProvider` lines 355–365 — calls `invalidateAppointmentSurfaceProviders(ref)` from a
  `ref.listen` while itself watching `appointmentQueueCheckedInCountProvider` (line 364), which depends on
  `appointmentQueueProvider`, which the helper invalidates. The provider therefore invalidates something it transitively
  watches, causing itself to rebuild and re-register the listener.
- Other invalidation entry points, each with its own set: `frontend/lib/app/application/clinic_setup_orchestrator.dart`
  line 124; `frontend/lib/app/shell/dev/dev_clinic_seed_notifier.dart` line 106;
  `frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart` line 282;
  and ad-hoc `refresh()` calls at `appointment_calendar_page.dart` lines 1304, 2010 and in the booking-sheet success path.

**Issue:** there are four different definitions of "which appointment surfaces are now stale", one of which
(`_invalidateSurfaces`) is inconsistent with the shared helper it duplicates, plus a self-referential invalidation in the
warm provider.

**Why it is a problem:**

- *Stale UI.* Because `_invalidateSurfaces` omits the queue, a status change made on the detail page leaves
  `appointmentQueueProvider` holding the old status. Today this is masked by **H5** (nothing renders the queue), so it is
  a latent defect that will appear the moment a queue page ships — exactly when it is hardest to attribute.
- *Comment drift.* `appointment_queue_provider.dart` lines 356–359 contain an inline comment referencing "review §6.2",
  a document not present in the repo, and the mechanism it describes (routing setup-driven invalidation through
  Appointments so Setup need not import Appointments) is undermined by `clinic_setup_orchestrator.dart` importing
  Appointments' invalidation helper directly at line 4 anyway.
- *Unclear ownership.* The helper lives in `presentation/providers/`, so external features (Visits, the app shell, the dev
  seeder) all reach into Appointments' presentation layer for cache coordination (see **H3**).

**Recommended architectural solution:** one file owns every invalidation set, it lives in `application/`, and no surface
hand-rolls its own.

| File | Contents |
| --- | --- |
| `frontend/lib/features/appointments/application/appointment_surface_invalidation.dart` (moved from `presentation/providers/`, per **H3** step 4) | `invalidateAllAppointmentSurfaces(Ref)` (the current `invalidateAppointmentSurfaceProviders`), `invalidateAppointmentAfterMutation(Ref, {required String appointmentId, required String branchId, required DateTime startTime})` (new — the union of what the detail page needs *plus* the queue), and `invalidateAppointmentAfterVisitCompleted(Ref, {required String appointmentId})` delegating to the new function. |

**Suggested implementation steps:**

1. Perform **H3** step 4 first (move the file to `application/`).
2. Add `void invalidateAppointmentAfterMutation(Ref ref, {required String appointmentId, required String branchId, required DateTime startTime})`
   to the moved file. Its body invalidates, in this order: `appointmentDetailProvider(appointmentId)`;
   `appointmentDetailSiblingsProvider(AppointmentDetailSiblingsQuery(branchId: branchId, startTime: startTime))`;
   the shift lookup provider (`appointmentShiftLookupProvider(AppointmentShiftLookupQuery(branchId: branchId, day: startTime))`
   after **M1**, or `appointmentDetailShiftLookupProvider(...)` before it); `appointmentCalendarProvider`;
   `appointmentQueueProvider`. This is the union of `_invalidateSurfaces` (lines 91–108) and the missing queue entry.
3. Rewrite `invalidateAppointmentAfterVisitCompleted` to call `invalidateAppointmentAfterMutation`. Because the Visits
   caller only has an `appointmentId`, add optional `branchId` / `startTime` parameters that, when null, skip the
   siblings and shift invalidations.
4. Delete `AppointmentDetailPage._invalidateSurfaces` (lines 90–109) from
   `presentation/pages/appointment_detail_page.dart` and change line 77 to
   `onChanged: () => invalidateAppointmentAfterMutation(ref, appointmentId: detail.id, branchId: detail.branchId, startTime: detail.startTime)`.
   Note the `WidgetRef` vs `Ref` mismatch: give the new function a `Ref`-typed parameter and add a thin
   `invalidateAppointmentAfterMutationFromWidget(WidgetRef ref, {...})` overload in the same file that mirrors the
   `ref.invalidate` calls, rather than casting.
5. Rename `invalidateAppointmentSurfaceProviders` to `invalidateAllAppointmentSurfaces` and update its three call sites:
   `frontend/lib/app/application/clinic_setup_orchestrator.dart` line 124,
   `frontend/lib/app/shell/dev/dev_clinic_seed_notifier.dart` line 106, and the warm provider.
6. Fix the self-referential warm provider. After **H5** step 2 the invalidation wiring lives in
   `appointmentCalendarShellWarmProvider` (`appointment_calendar_provider.dart` lines 296–298). Ensure that provider does
   **not** `ref.watch` anything the helper invalidates: it should `ref.watch(clinicDataChangedProvider)` and
   `ref.listen<int>(clinicDataChangedProvider, ...)` only, without `ref.watch(appointmentCalendarProvider)`. Use
   `ref.read(appointmentCalendarProvider)` once inside the listener if warming is still desired.
7. Delete the stale `(review §6.2)` comment at `appointment_queue_provider.dart` lines 356–359.
8. Verify: `rg -n "ref.invalidate\(appointment" frontend/lib` should show matches **only** inside
   `frontend/lib/features/appointments/application/appointment_surface_invalidation.dart`. Then
   `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## M4 — Dev-only `DoctorDevSeedService` sits in Appointments `data/` and provisions staff accounts through two other features

**Severity:** Medium

**Location:** `frontend/lib/features/appointments/data/doctor_dev_seed_service.dart` (103 lines)

- Imports at lines 5–8: `features/setup/domain/create_staff_account_input.dart`,
  `features/setup/domain/repositories/provisioning_repository.dart`,
  `features/clinic-management/domain/repositories/staff_admin_repository.dart`,
  `features/clinic-management/domain/staff_list_filter.dart`.
- `DoctorDevSeedService` constructor lines 26–33 takes `StaffAdminRepository` and `ProvisioningRepository`.
- `seed(AuthSessionContext auth)` lines 35–102: calls `_staffAdmin.listStaff(filter: StaffListFilter.all)` (line 46) to
  detect existing dev doctors by name prefix (lines 47–53), then loops
  `_provisioning.createStaffAccount(CreateStaffAccountInput(... role: StaffRole.doctor ...))` (lines 64–73).
- Supporting data: `frontend/lib/features/appointments/domain/doctor_dev_seed_data.dart` (33 lines) holds
  `DoctorDevSeedData.doctors`, `DoctorDevSeedData.defaultPassword` and `DoctorDevSeedSpec.devNamePrefix` — a dev fixture
  living in the domain layer.

**Issue:** the Appointments `data/` layer contains a debug utility whose entire job is to **create staff accounts**, which
belongs to Setup/Clinic-Management. Two of the eight cross-feature imports in Appointments' non-presentation layers exist
solely for this file, and both are reach-ins to other features' repository contracts. It also stores a default password
constant (`DoctorDevSeedData.defaultPassword`) in `domain/`.

**Why it is a problem:**

- *Boundary noise.* An import-graph audit of Appointments shows it depending on Setup's provisioning repository, which
  reads as "Appointments provisions users". Any future boundary lint (**M8**) would have to whitelist this file.
- *Layer misuse.* `docs/architecture/07-frontend.md` defines `data/` as "concrete repository implementations, RPC call
  logic, error mapping". This is neither — it is a dev orchestration script. It also has no interface and no provider, so
  it is wired by hand from `frontend/lib/app/shell/dev/`.
- *Ships in release builds.* Nothing in the file is guarded by `kDebugMode`, so the seed data (including the default
  password) is compiled into production binaries. Compare `ARCHITECTURAL_FLAWS.md` `L4`, which flags the analogous
  bootstrap-seed password risk in migrations.
- *Precedent already exists elsewhere.* The app already centralises dev seeding under
  `frontend/lib/app/shell/dev/` (`dev_clinic_seed_service.dart`, `dev_clinic_seed_schedule.dart`,
  `dev_clinic_seed_notifier.dart`, `dev_clinic_seed_service_catalog.dart`), so this file is the outlier.

**Recommended architectural solution:** move the dev doctor seeder into the existing app-level dev seeding area, where
depending on multiple features is already the accepted arrangement.

| Change | Detail |
| --- | --- |
| Move `frontend/lib/features/appointments/data/doctor_dev_seed_service.dart` → `frontend/lib/app/shell/dev/dev_doctor_seed_service.dart` | Rename class `DoctorDevSeedService` → `DevDoctorSeedService`, `DoctorDevSeedOutcome` → `DevDoctorSeedOutcome`. |
| Move `frontend/lib/features/appointments/domain/doctor_dev_seed_data.dart` → `frontend/lib/app/shell/dev/dev_doctor_seed_data.dart` | Rename `DoctorDevSeedData` → `DevDoctorSeedData`, `DoctorDevSeedSpec` → `DevDoctorSeedSpec`. |
| Guard construction behind `kDebugMode` | At the wiring site in `frontend/lib/app/shell/dev/`, so release builds do not retain the seed fixtures. |

**Suggested implementation steps:**

1. Find the current wiring: run `rg -n "DoctorDevSeedService|DoctorDevSeedData|DoctorDevSeedSpec|DoctorDevSeedOutcome" frontend`
   and record every hit (expected: the two source files, plus a construction site under `frontend/lib/app/shell/dev/`, plus
   any dev UI action).
2. Create `frontend/lib/app/shell/dev/dev_doctor_seed_data.dart` and move the contents of
   `frontend/lib/features/appointments/domain/doctor_dev_seed_data.dart` into it, renaming
   `DoctorDevSeedData` → `DevDoctorSeedData` and `DoctorDevSeedSpec` → `DevDoctorSeedSpec`.
3. Create `frontend/lib/app/shell/dev/dev_doctor_seed_service.dart` and move the contents of
   `frontend/lib/features/appointments/data/doctor_dev_seed_service.dart` into it, renaming `DoctorDevSeedService` →
   `DevDoctorSeedService` and `DoctorDevSeedOutcome` → `DevDoctorSeedOutcome`. Update the internal import of the seed data
   to the new path. Change the two `AppLog` message prefixes at lines 55, 76, 83, 93, 95 from
   `appointments.dev_seed_doctors.*` to `dev.seed_doctors.*`.
4. Delete `frontend/lib/features/appointments/data/doctor_dev_seed_service.dart` and
   `frontend/lib/features/appointments/domain/doctor_dev_seed_data.dart`.
5. Update every call site found in step 1 to the new paths and class names.
6. At the construction site, wrap creation in `if (kDebugMode)` (importing `package:flutter/foundation.dart`) and make the
   dev action a no-op returning
   `DevDoctorSeedOutcome(created: 0, skippedBecauseAlreadySeeded: false, errorMessage: 'Dev seeding is disabled in release builds.')`
   in release mode.
7. Verify: `rg -n "features/setup|features/clinic-management/domain/repositories" frontend/lib/features/appointments/data frontend/lib/features/appointments/domain`
   must return zero matches — this removes Appointments' only dependency on Setup entirely except for
   `appointment_booking_step1.dart`'s layout helper. Then `cd frontend; flutter analyze; flutter test`.
8. Optional follow-up: `frontend/lib/features/appointments/presentation/widgets/appointment_booking_step1.dart` line 16
   imports `features/setup/presentation/setup/setup_form_layout.dart` for `setupFormUseTwoColumns(context)` (used at
   line 67). Move that single helper to `frontend/lib/core/ui/layout/form_column_layout.dart` as
   `formUseTwoColumns(BuildContext)` and update both Setup and Appointments, eliminating the last
   Appointments → Setup edge.

## M5 — Shared clinic vocabulary is owned by `clinic-management` and consumed by Appointments in 30+ places, with no shared home

**Severity:** Medium

**Location:**

Appointments files importing `features/clinic-management/domain/**` (30 import statements across 24 files):

- `branch_working_schedule.dart` — 11 importers, including four **domain** files:
  `domain/appointment_branch_working_hours.dart` line 1, `domain/appointment_working_hours.dart` line 1,
  `domain/appointment_settings.dart` line 1, `domain/appointment_booking_slots.dart` line 8,
  `domain/appointment_calendar_display.dart` line 12, `domain/appointment_reschedule_validation.dart` line 6, plus
  `presentation/providers/appointment_queue_provider.dart` line 20 and four widgets.
- `staff_list_item.dart` — 12 importers, including `domain/appointment_booking_slots.dart` line 9 and
  `domain/appointment_queue_shift_doctors.dart` line 5.
- `branch_list_item.dart` — 7 importers (all presentation).
- `staff_list_filter.dart` — 4 importers; `branch_list_filter.dart` — 2 importers.
- `usecases/clinic_management_use_case_providers.dart` — 4 importers (`listBranchesUseCaseProvider`,
  `listStaffUseCaseProvider`) at `appointment_calendar_provider.dart` line 17 (used lines 307, 315),
  `appointment_queue_provider.dart` line 21 (used line 237), `appointment_detail_shift_provider.dart` line 10 (used
  line 71), `appointment_queue_shift_provider.dart` line 10 (used line 50).
- `repositories/staff_admin_repository.dart` — 1 importer (`data/doctor_dev_seed_service.dart` line 7; removed by **M4**).

Notable consequence inside Appointments' own domain:
`frontend/lib/features/appointments/domain/appointment_settings.dart` line 19 declares
`final BranchWorkingSchedule? workingSchedule;` and line 38 parses it from the `get_appointment_settings` RPC payload
(`BranchWorkingSchedule.fromJson(data['working_schedule'])`) — so an Appointments DTO carries another feature's aggregate.

Ownership evidence (from a repository-wide `rg` count of unique importing files):

| Shared file | appointments | clinic-management | setup | patients | app | total |
| --- | --- | --- | --- | --- | --- | --- |
| `staff_list_item.dart` | 12 | 10 | 2 | 0 | 1 | 25 |
| `branch_working_schedule.dart` | 11 | 7 | 3 | 1 | 1 | 22 |
| `branch_list_item.dart` | 7 | 14 | 2 | 1 | 1 | 25 |

There is **no shared domain location** in the project: `frontend/lib/shared/`, `frontend/lib/core/domain/` and
`frontend/lib/core/models/` do not exist. `frontend/lib/core/` contains only `auth/`, `config/`, `data/`, `errors/`,
`logging/`, `rpc/`, `ui/`, `utils/`.

**Issue:** `BranchWorkingSchedule`, `StaffListItem` and `BranchListItem` are the shared vocabulary of the whole clinic
domain (25, 22 and 25 importing files respectively, spread over four features), yet they are namespaced as if they were
Clinic-Management internals. Appointments — the heaviest consumer of two of the three — must therefore import another
feature in its innermost layer.

**Why it is a problem:**

- *False coupling signal.* An audit sees "Appointments domain depends on Clinic-Management domain" and cannot distinguish
  legitimate shared vocabulary from a real boundary violation, which is exactly what happened while reviewing this
  feature. It also makes it impossible to state a simple rule such as "no feature's `domain/` may import another feature".
- *Change amplification.* A refactor of `StaffListItem` (e.g. adding the assignee-id support needed by **C3**) touches 25
  files across four features with no owning module to coordinate it.
- *Aggregate leakage.* `AppointmentSettings.workingSchedule` means the Appointments settings RPC contract is coupled to
  Clinic-Management's schedule serialisation; a change to `BranchWorkingSchedule.fromJson` silently changes Appointments'
  slot generation, working-hours validation and calendar axis range.

This is a **structural** finding, not a defect: the code works, and the DTOs genuinely are shared. It is graded Medium
because the fix is a mechanical move with wide blast radius and no behaviour change.

**Recommended architectural solution:** create a shared clinic-domain module and move the three genuinely shared value
types into it, leaving Clinic-Management owning only its own inputs, filters and use cases.

| New file | Moved from | Contents |
| --- | --- | --- |
| `frontend/lib/core/domain/clinic/branch_working_schedule.dart` | `features/clinic-management/domain/branch_working_schedule.dart` | `BranchWorkingSchedule`, `BranchWeekday`, `BranchWorkingDayHours`, `defaultSchedule()`, `fromJson`, `hasConfiguredWorkingHours` |
| `frontend/lib/core/domain/clinic/branch_list_item.dart` | `features/clinic-management/domain/branch_list_item.dart` | `BranchListItem` |
| `frontend/lib/core/domain/clinic/staff_list_item.dart` | `features/clinic-management/domain/staff_list_item.dart` | `StaffListItem`, `compareByFullName` |
| `frontend/lib/core/domain/clinic/clinic_domain.dart` | — | Barrel exporting the three files above |

Left in place (correctly feature-owned): `branch_list_filter.dart`, `staff_list_filter.dart`, `staff_list_query.dart`,
`create_branch_input.dart`, `update_branch_input.dart`, `staff_member_detail.dart`, `organization_profile.dart`,
`permission_matrix_*`, all `repositories/` and all `usecases/`.

**Suggested implementation steps:**

1. Create the directory `frontend/lib/core/domain/clinic/`.
2. Move `frontend/lib/features/clinic-management/domain/branch_working_schedule.dart` to
   `frontend/lib/core/domain/clinic/branch_working_schedule.dart` with no content changes. Confirm it imports only
   `package:flutter/foundation.dart` (it must not import anything from `features/`); if it does import a feature file, stop
   and reduce that dependency first.
3. Repeat for `branch_list_item.dart` and `staff_list_item.dart`. If `staff_list_item.dart` references `StaffRole` from
   `features/auth/domain/auth_session.dart`, leave that import — `StaffRole` is a separate follow-up move and does not
   block this one.
4. Create `frontend/lib/core/domain/clinic/clinic_domain.dart` exporting the three files.
5. Rewrite imports repository-wide. Run
   `rg -l "features/clinic-management/domain/(branch_working_schedule|branch_list_item|staff_list_item).dart" frontend`
   and in each file replace the import with the corresponding `package:ai_clinic/core/domain/clinic/...` path. Expected
   ~40 files across `features/appointments`, `features/clinic-management`, `features/setup`, `features/patients` and
   `frontend/lib/app/`.
6. Delete the three original files from `features/clinic-management/domain/`.
7. Run `rg -n "package:ai_clinic/features/" frontend/lib/features/appointments/domain` and confirm the only remaining
   cross-feature imports in Appointments' domain are `features/shifts/domain/*` (in
   `appointment_queue_shift_doctors.dart` lines 6–7) and `features/auth/domain/auth_session.dart` (in
   `appointment_fetch_scope.dart` line 3). Document those two as accepted, or schedule `ShiftListItem` and `StaffRole` for
   the same treatment in a follow-up.
8. Remove the dead import at `frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart` line 4
   (`auth_session.dart`) if no symbol from it is used after step 7 — verify with
   `rg -n "AuthSession|StaffRole" frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart`
   (`StaffRole` is used at line 77, so keep the import if that is the only source).
9. Update `docs/architecture/07-frontend.md`: add `core/domain/clinic/` to the project-structure tree with a one-line note
   that it holds cross-feature clinic value types, and state the rule "a feature's `domain/` must not import another
   feature's `domain/`; shared types belong in `core/domain/`".
10. Verify: `cd frontend; flutter analyze; flutter test`.

## M6 — `build()` in the calendar page has side effects, rebuilds the fullscreen overlay every frame, and scans linearly per tile

**Severity:** Medium

**Location:** `frontend/lib/features/appointments/presentation/pages/appointment_calendar_page.dart`,
`_AppointmentCalendarPageState.build` (lines 142–331) and its `appointmentBuilder` callback (lines 570–632).

1. **Side effects scheduled from `build`** — lines 190–204:
   ```dart
   _scheduleRevealIfNeeded(visibleItems, loading: state.loading);
   if (!state.loading) {
     if (_dragSession == null && _resizeSession == null) {
       _scheduleDataSourceSync(visibleItems, ...);
     }
     _scheduleCalendarViewSync();
   }
   ```
   All three register `addPostFrameCallback` work that mutates `_dataSource` and `_calendarController`, which in turn
   triggers further rebuilds.
2. **Mutable state assigned during `build`** — line 211 assigns the closure `_fullscreenCalendarBuilder = (overlayContext) {...}`
   as a field every time `build` runs.
3. **Overlay marked dirty on every parent build** — lines 233–237:
   ```dart
   if (_isCalendarFullscreen) {
     WidgetsBinding.instance.addPostFrameCallback(
       (_) => _fullscreenOverlay?.markNeedsBuild(),
     );
   }
   ```
   While fullscreen, every rebuild of the page schedules an overlay rebuild; because the overlay renders the same calendar
   via `_fullscreenCalendarBuilder`, this is a self-sustaining rebuild loop for as long as any ancestor rebuilds.
4. **Linear scan per visible tile per frame** — lines 573–577 inside `appointmentBuilder`:
   ```dart
   final item = id == null
       ? null
       : state.items
             .where((entry) => entry.id == id)
             .firstOrNull;
   ```
   `appointmentBuilder` runs for every rendered appointment, so this is O(tiles × items) per frame. The same pattern
   appears in the gesture handlers: lines 1119, 1374 and (per the resize path) again in `_onAppointmentResizeEnd`.
5. **Three independent post-frame schedulers plus five fingerprints** (`_itemsFingerprint`, `_resourceFingerprint`,
   `_statusFilterFingerprint`, `_themeFingerprint`, `_lastRevealSourceFingerprint`) and the `_calendarViewSyncScheduled`
   latch (lines 56–63, 73) coordinate the above by hand.

**Issue:** `build` is not a pure function of state — it mutates fields, schedules asynchronous mutations of the Syncfusion
controller and data source, and unconditionally dirties an overlay. Correctness therefore depends on frame ordering and on
five hand-maintained change-detection strings.

**Why it is a problem:**

- *Performance on target hardware.* `01-principles.md` targets 8 GB RAM machines with no GPU. A continuously dirty overlay
  plus O(tiles × items) lookups on a week view with a few hundred appointments is measurable jank on exactly the machines
  this product runs on.
- *Non-deterministic behaviour.* Because the data-source sync is skipped while a drag/resize session is active
  (line 192), a provider refresh landing mid-gesture is dropped and only reapplied on the next unrelated rebuild.
- *Debuggability.* When the calendar shows stale tiles, there is no single place to look: the cause could be any of the
  five fingerprints, the `_calendarViewSyncScheduled` latch, or the skipped sync.

**Recommended architectural solution:** move the synchronisation out of `build` into lifecycle hooks on the
`AppointmentCalendarSyncController` introduced in **H1**, drive it from `ref.listen` instead of `build`, key appointment
lookups off a map, and make the overlay rebuild event-driven.

**Suggested implementation steps:**

1. Complete **H1** step 5 so `AppointmentCalendarSyncController` exists and owns the fingerprints and sync methods.
2. Replace the build-time sync calls (lines 190–204) with a `ref.listen` registered once in `build` *before* any widget is
   returned but with no other side effects — specifically
   `ref.listen<AppointmentCalendarState>(appointmentCalendarProvider, (previous, next) { _sync.onStateChanged(previous, next, ...); });`.
   Riverpod guarantees the listener fires outside the build phase, which removes the `addPostFrameCallback` indirection.
   Keep `_scheduleRevealIfNeeded` behind the same listener.
3. Move the theme-dependent arguments (`colors.surfaceCanvas`, `oddResourceRowColor`, `Theme.of(context).brightness`) into
   fields updated in `didChangeDependencies` rather than read inside `build` and passed to a post-frame callback.
4. Build an id→item map once per state change instead of scanning: in `AppointmentCalendarSyncController`, add
   `Map<String, AppointmentListItem> _itemsById = const {};` populated in `onStateChanged` via
   `{for (final item in next.items) item.id: item}`, plus `AppointmentListItem? itemById(String? id)`.
5. Replace the four linear scans with `_sync.itemById(id)`: `appointmentBuilder` lines 573–577,
   `_onAppointmentDragEnd` line 1119, `_onAppointmentResizeStart` line 1374, and the equivalent lookup in
   `_onAppointmentResizeEnd`.
6. Make the fullscreen overlay rebuild event-driven. Delete lines 233–237. In
   `AppointmentCalendarFullscreenController` (from **H1** step 4), expose
   `void refreshOverlay() { _fullscreenOverlay?.markNeedsBuild(); }` and call it **only** from the `ref.listen` callback in
   step 2, and only when `previous != next`.
7. Stop assigning `_fullscreenCalendarBuilder` in `build` (line 211). Instead pass the builder into
   `AppointmentCalendarFullscreenController.open(...)` at the moment fullscreen is entered
   (`_openCalendarFullscreen`, lines 96–130), and have that builder read the current state via
   `ref.read(appointmentCalendarProvider)` when invoked.
8. Remove the now-redundant latch `_calendarViewSyncScheduled` (line 73) and the wrapper
   `_scheduleCalendarViewSync` (903–915), since `onStateChanged` already runs once per state change.
9. Handle the dropped-refresh case explicitly: in `onStateChanged`, when a drag/resize session is active, store the pending
   items in a `List<AppointmentListItem>? _pendingItems` field and apply them from
   `AppointmentCalendarRescheduleController`'s completion path, rather than silently skipping (current line 192).
10. Verify: run the app on `/appointments/calendar`, enter fullscreen, and confirm with the Flutter DevTools performance
    overlay that no frames are being rebuilt while idle. Then `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## M7 — Two divergent working-hours parsers accept different formats, so one schedule validates differently on different paths

**Severity:** Medium

**Location:**

- `frontend/lib/features/appointments/domain/appointment_branch_working_hours.dart`
  - `AppointmentBranchWorkingHours.parseHm(String)` — public, at line 64. Its regex accepts an **optional seconds
    component**, so `'09:00:00'` (the PostgreSQL `time` text representation) parses successfully.
  - Also owns `isWorkingDay`, `hoursForDate`, `previousWorkingDay`, `validationMessage` (lines 72–105) and
    `hoursLabelForDate` (lines 120–134).
- `frontend/lib/features/appointments/domain/appointment_working_hours.dart`
  - `AppointmentWorkingHours._parseHm(String)` — private, at line 103. Its parser does **not** accept seconds, so
    `'09:00:00'` yields `null`.
  - Owns `isWithinSchedule` (used by `AppointmentCalendarDisplay.filterVisibleAppointments`,
    `appointment_calendar_display.dart` lines 478–482) and midnight-sentinel end handling (lines 77–96).
- Consumers of the two parsers therefore disagree:
  - `parseHm` (seconds-tolerant) is used by `appointment_calendar_display.dart` lines 262–267, 314, 555–556, 572–573;
    `appointment_booking_slots.dart` lines 67–72.
  - `_parseHm` (seconds-intolerant) backs `AppointmentWorkingHours.isWithinSchedule`, which is what decides whether an
    appointment is **rendered at all** (`filterVisibleAppointments`) and whether a booking is inside hours
    (`appointment_booking_sheet.dart` lines 518–527).
- Additional divergence: `AppointmentWorkingHours` treats a `'00:00'` close time as an end-of-day sentinel
  (lines 77–96); `AppointmentBranchWorkingHours.validationMessage` (lines 72–105) does not, so a branch configured to
  close at midnight is handled inconsistently.

**Issue:** the same `BranchWorkingSchedule.openTime` / `closeTime` strings are parsed by two different implementations with
different accepted grammars and different midnight semantics, and the strings originate from a backend `time` column whose
text form may or may not include seconds depending on the RPC's serialisation.

**Why it is a problem:**

- *Appointments can disappear from the calendar.* If the RPC returns `'09:00:00'`, `AppointmentBranchWorkingHours.parseHm`
  succeeds (so the calendar axis spans 09:00–17:00 and the day is treated as open) while
  `AppointmentWorkingHours._parseHm` returns `null`. Depending on the null-handling branch in `isWithinSchedule`, real
  appointments are then filtered out of `filterVisibleAppointments` on a day the calendar renders as open — a silent data
  loss in the primary UI.
- *Inconsistent validation.* A booking can pass `AppointmentBranchWorkingHours.validationMessage` and fail
  `AppointmentWorkingHours.isWithinSchedule` (or vice versa), producing contradictory messages between the reschedule
  dialog and the booking sheet.
- *Duplicated invariant.* Two files each encode "what a valid clinic clock time looks like", so a backend format change
  requires finding both.

**Recommended architectural solution:** one parser, one midnight rule, in one file. Make
`AppointmentBranchWorkingHours` the single owner of clock-string parsing and have `AppointmentWorkingHours` consume it.

| File | Change |
| --- | --- |
| `frontend/lib/features/appointments/domain/appointment_clock_time.dart` (new) | `int? parseClockMinutes(String raw)` — the seconds-tolerant parser, plus `const int endOfDayMinutes = 24 * 60;` and `int? normalizeCloseMinutes(int? minutes)` implementing the single midnight-sentinel rule (`0` → `endOfDayMinutes`). |
| `frontend/lib/features/appointments/domain/appointment_branch_working_hours.dart` | `parseHm` becomes a one-line delegate to `parseClockMinutes`. |
| `frontend/lib/features/appointments/domain/appointment_working_hours.dart` | Delete `_parseHm` (line 103); use `parseClockMinutes` and `normalizeCloseMinutes`. |
| `frontend/lib/features/appointments/domain/appointment_queue_shift_doctors.dart` | Its private `_parseClockMinutes` (lines 251–267) is a **third** copy for shift times — replace it with `parseClockMinutes` too. |

**Suggested implementation steps:**

1. Read `frontend/lib/features/appointments/domain/appointment_branch_working_hours.dart` line 64 and
   `frontend/lib/features/appointments/domain/appointment_working_hours.dart` line 103 side by side and record both exact
   grammars before changing anything.
2. Determine the authoritative wire format: run
   `rg -n "open_time|close_time" backend/supabase/migrations | rg -i "to_char|::text|working_schedule"` and inspect the
   newest branch working-schedule serialisation. Record whether seconds are emitted.
3. Create `frontend/lib/features/appointments/domain/appointment_clock_time.dart` with top-level
   `int? parseClockMinutes(String raw)` using the seconds-tolerant grammar (the safer superset), rejecting
   `hour > 23` / `minute > 59` exactly as `AppointmentQueueShiftDoctorLookup._parseClockMinutes` does at lines 256–265;
   plus `const int endOfDayMinutes = 24 * 60;` and
   `int? normalizeCloseMinutes(int? minutes) => minutes == 0 ? endOfDayMinutes : minutes;`.
4. In `appointment_branch_working_hours.dart`, replace the body of `parseHm` with `return parseClockMinutes(raw);`,
   keeping the public signature so its ten existing call sites are unaffected.
5. In `appointment_working_hours.dart`, delete `_parseHm` (line 103) and replace its call sites with `parseClockMinutes`.
   Then replace the local midnight-sentinel handling (lines 77–96) with `normalizeCloseMinutes(...)` so the rule exists
   once.
6. In `appointment_branch_working_hours.dart` `validationMessage` (lines 72–105), apply `normalizeCloseMinutes` to the
   parsed close time so it now agrees with `AppointmentWorkingHours` about midnight closes.
7. In `appointment_queue_shift_doctors.dart`, delete `_parseClockMinutes` (lines 251–267) and replace the two call sites at
   lines 178–179 with `parseClockMinutes(shift.startTime)` / `parseClockMinutes(shift.endTime)`.
8. Fix the exclusive shift-end boundary while in this file: line 184 uses
   `appointmentMinutes >= shiftEnd`, which excludes an appointment starting exactly at the shift end. That is correct for
   a half-open interval, so **leave it**, but add a unit test pinning the behaviour so it is no longer accidental.
9. Add tests to `frontend/test/unit/appointments/appointment_branch_working_hours_test.dart` and
   `appointment_working_hours_test.dart` asserting that `'09:00'`, `'09:00:00'` and `'9:00'` all parse to the same minute
   value on **both** paths, and that a `'00:00'` close time is treated as end-of-day on both paths.
10. Verify: `rg -n "_parseHm|_parseClockMinutes" frontend/lib/features/appointments` returns nothing. Then
    `cd frontend; flutter analyze; flutter test test/unit/appointments`.

## M8 — No static enforcement of layer or feature boundaries anywhere in the toolchain

**Severity:** Medium

**Location:**

- `frontend/analysis_options.yaml` — includes only `package:flutter_lints/flutter.yaml`; no custom lint rules, no
  `custom_lint` plugin, no import restrictions.
- `frontend/pubspec.yaml` — no `import_lint`, `custom_lint`, `dart_code_metrics` or `dependency_validator` entry.
- `frontend/test/boundary/**` and `frontend/tool/run_boundary_tests.py` — despite the name, these are **live Supabase
  integration tests** (RPC/RLS behaviour) tagged `boundary` in `frontend/dart_test.yaml`. They test *database* boundaries,
  not Dart module dependencies. `frontend/test/boundary/appointments/appointment_repository_boundary_test.dart` is an RPC
  test.
- `.github/workflows/ci.yml` — runs Flutter analyze/test only; no dependency-graph check.

**Issue:** every architectural rule in `docs/architecture/07-frontend.md` — "domain depends on nothing", "data depends on
domain interfaces and Supabase", "features are isolated" — is enforced only by human review. Nothing in the build fails when
a rule is broken.

**Why it is a problem:** this is the *reason* findings C1, H2, H3 and M4 exist and why they will recur. Concretely, all of
the following compile cleanly today and would each be caught by a boundary check:

- `domain/appointment_calendar_display.dart` importing `dart:ui` and `syncfusion_flutter_calendar` (**C1**).
- `core/ui/components/app_booking_slot_grid.dart` importing `features/appointments/domain/**` (**H2**).
- `features/patients/presentation/providers/patient_detail_history_provider.dart` importing
  `features/appointments/data/**` (**H3**).
- `features/appointments/presentation/widgets/appointment_detail_open_visit_button.dart` importing
  `features/visits/data/**` (**C2**, **H3**).
- `features/appointments/data/doctor_dev_seed_service.dart` importing `features/setup/domain/repositories/**` (**M4**).

Without a gate, each fix above is a one-time cleanup that regresses on the next feature.

**Recommended architectural solution:** add a single Dart test that walks the import graph and asserts a small, explicit
rule set. A test is preferable to an analyzer plugin here because it requires no new tooling, runs in the existing CI job,
and can carry an explicit, reviewable allow-list for the known exceptions the architecture docs already sanction.

| New file | Contents |
| --- | --- |
| `frontend/test/architecture/import_boundaries_test.dart` | Reads every `.dart` file under `frontend/lib`, extracts `package:ai_clinic/...` imports with a regex, and asserts the rules below. Fails with the offending file, line and import. |
| `frontend/test/architecture/import_boundaries_allowlist.dart` | A `const Map<String, String>` of `'<relative path>|<imported path>' : '<reason + tracking finding id>'` entries for sanctioned exceptions, so every violation left in place is explicit and attributable. |

Rules to assert:

1. No file under `frontend/lib/core/**` may import `package:ai_clinic/features/**`.
2. No file under `frontend/lib/features/<X>/domain/**` may import `package:ai_clinic/features/<Y>/**` where `Y != X`.
3. No file under `frontend/lib/features/<X>/domain/**` may import `package:flutter/material.dart`,
   `package:flutter/widgets.dart`, `dart:ui`, `package:flutter_riverpod/**`, `package:supabase_flutter/**`,
   `package:syncfusion_flutter_calendar/**`, or `package:ai_clinic/core/ui/**`.
   (`package:flutter/foundation.dart` is permitted for `@immutable`.)
4. No file under `frontend/lib/features/<X>/**` may import `package:ai_clinic/features/<Y>/data/**` where `Y != X`.
5. No file under `frontend/lib/features/<X>/**` may import `package:ai_clinic/features/<Y>/presentation/providers/**`
   where `Y != X`.
6. No file under `frontend/lib/features/<X>/data/**` may import `package:ai_clinic/features/<X>/presentation/**`.

**Suggested implementation steps:**

1. Create `frontend/test/architecture/import_boundaries_allowlist.dart` exporting
   `const Map<String, String> importBoundaryAllowlist = { ... };`, initially empty.
2. Create `frontend/test/architecture/import_boundaries_test.dart`. In `main()`, list files with
   `Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))`, read each with
   `readAsLinesSync()`, and match imports with `RegExp(r"^import\s+'(package:[^']+|dart:[^']+)'")`.
3. Implement each of the six rules above as a separate `test(...)` block. For each violation, build the key
   `'<posix-normalised relative path>|<imported uri>'`; skip it if present in `importBoundaryAllowlist`; otherwise collect it.
   Fail with `expect(violations, isEmpty, reason: violations.join('\n'))`.
4. Run the test once to capture the current baseline: `cd frontend; flutter test test/architecture/import_boundaries_test.dart`.
5. Populate `importBoundaryAllowlist` with **exactly** the violations the baseline reports, each annotated with the finding
   id that will remove it, e.g.
   `'lib/core/ui/components/app_booking_slot_grid.dart|package:ai_clinic/features/appointments/domain/appointment_booking_slots.dart': 'H2 — slot types to move to core/ui/models'`.
   Do not add wildcard entries.
6. Confirm the suite is green with the allow-list in place, then commit the test and the allow-list together so the gate is
   active from this point forward.
7. As each finding in this report is implemented, delete its allow-list entries. Leave the two entries that **M5** step 7
   identifies as deliberate (`appointment_queue_shift_doctors.dart` → `features/shifts/domain/**` and
   `appointment_fetch_scope.dart` → `features/auth/domain/auth_session.dart`) until `ShiftListItem` and `StaffRole` are
   moved to `core/domain/`.
8. Wire it into CI: confirm `.github/workflows/ci.yml`'s Flutter test step runs the whole `test/` tree (not a filtered
   subset). If it filters, add `test/architecture/` explicitly.
9. Record the rule set in `docs/architecture/07-frontend.md` under the "Layer Responsibilities" section, with a pointer to
   `frontend/test/architecture/import_boundaries_test.dart` as the enforcement mechanism, and note that
   `docs/architecture/ARCHITECTURAL_FLAWS.md` `L2` (features skipping the use-case layer) remains an accepted exception
   that these rules do not check.

---

## What is architecturally sound

The following areas were examined and found sound; they need no work and should not be "improved":

- **Domain business rules are genuinely well factored.** The scheduling invariants live in small, pure, individually
  tested units: `domain/appointment_status_transitions.dart`, `domain/appointment_status_day_rules.dart`,
  `domain/appointment_reschedule_validation.dart`, `domain/appointment_working_hours.dart`,
  `domain/appointment_calendar_period.dart`, `domain/appointment_row_parsing.dart`, `domain/appointment_fetch_scope.dart`.
  There is no business rule reimplemented inside a widget: the calendar's drag and resize paths both delegate to
  `AppointmentRescheduleValidation` (`appointment_calendar_page.dart` lines 1147–1271 and 1535–1632), and the detail
  actions delegate to `forwardStatusTargetFor` / `previousStatusTargetFor` / `canCancelAppointment` /
  `canMarkNoShowAppointment`. The problems in C1 are about *where UI concerns sit*, not about rule duplication.
- **Timezone handling is deliberate and correct in the live paths.** `domain/appointment_org_calendar.dart` centralises
  `ensureAppointmentTimezonesInitialized()` and `effectiveOrganizationTimezone(...)`, and organisation-local day
  boundaries are computed through the `timezone` package (`appointmentTodayRangeInTimezone`,
  `calendarDayInOrganizationTimezone`) rather than device-local time. `main.dart` line 11 initialises the database at
  startup. (The device-local `appointmentTodayRange` in `domain/appointment_today_range.dart` lines 12–17 is unused by
  feature code; it is a latent trap rather than a live defect, so it is not reported as a finding — deleting it during any
  of the above work would be a small improvement.)
- **The repository is a clean, thin RPC boundary.** `data/appointment_repository.dart` uses the shared
  `AppRpcInvoker` mixin, declares `migrationHint` and `rpcLogDomain`, converts all `DateTime` arguments with
  `.toUtc().toIso8601String()`, does no direct table access (`.from()`), and does no presentation formatting. Parsing is
  delegated to domain `fromRow` / `fromRpcData` factories. Apart from the two issues in **M2**, this file is a good model
  for the rest of the codebase.
- **Realtime lifecycle is correctly scoped.** `data/appointment_queue_realtime.dart` `subscribe` (lines 37–80) calls
  `unsubscribe()` first, scopes the channel per branch and filters server-side on `branch_id`;
  `AppointmentQueueController.build` registers `ref.onDispose(_unsubscribeRealtime)` (line 79) and guards callbacks with
  `_realtimeListening` (lines 275–277, 325–327). There is no listener leak. The only gap is that
  `channelError` / `timedOut` / `closed` set a `degraded` state without attempting resubscription (lines 74–77) — worth
  addressing if and when the queue page ships (**H5**), but not a defect today.
- **Controller and timer disposal is correct throughout presentation.** `appointment_booking_sheet.dart` disposes
  `_notesController` (lines 176–178); `appointment_cancel_dialog.dart` disposes at lines 36–38;
  `appointment_detail_page.dart`'s `_HeroAuditInfoChip` cancels its timer (lines 386, 396–401);
  `appointment_calendar_page.dart` removes the overlay and disposes `_calendarController` (lines 82–86). No leaks found.
- **`mounted` discipline after `await` is consistently applied.** Every async gap that subsequently touches `context` or
  calls `setState` is guarded — verified across `appointment_calendar_page.dart` (lines 1177, 1204, 1216, 1280, 1301,
  1305), `appointment_detail_status_actions.dart` (180, 210, 232, 259, 272, 332, 345, 358, 391, 400, 412, 466, 475, 487),
  `appointment_detail_open_visit_button.dart` (88, 94, 111, 121, 133, 138) and
  `appointment_booking_sheet.dart` (191, 199).
- **Route-level permission gating is complete.** `core/auth/auth_route_guard.dart` lines 285–287 gate every appointment
  route, and both appointment pages independently re-check on entry (`appointment_calendar_page.dart` lines 144–148,
  `appointment_detail_page.dart` lines 47–50), with `appointment_detail_provider.dart` lines 15–17 enforcing at the data
  fetch as well. No permission bypass was found. (**H6** step 7 only unifies which of the two equivalent APIs is used.)
- **The `application/` message-mapping pattern is right, just underused.** `application/appointment_rpc_messages.dart`
  matches the same pattern in `visits/application/visit_rpc_messages.dart` and
  `billing/application/billing_rpc_messages.dart`, and the presentation layer routes `RpcFailure` through it consistently.
  The recommendations in **C2**, **H1** and **H6** extend this existing, correct pattern rather than introducing a new one.
- **The absence of a use-case layer is not a defect.** `docs/architecture/07-frontend.md` records Appointments as an
  intentional exception using "Repositories + presentation notifiers", so this was excluded from grading. The problem this
  review does report (**C2**, **H6**) is narrower: there is no place at all for *multi-step orchestration*, which is why
  transactions ended up inside widgets.

---

## Suggested implementation order

The findings interlock; implementing them in this order avoids rework:

1. **M8** — add the boundary test with an allow-list first, so every subsequent fix is verifiable and cannot regress.
2. **M5** — move the shared clinic DTOs to `core/domain/clinic/`. Wide but mechanical; unblocks the domain-purity check.
3. **C1** — split the domain/presentation seam in the three display files. Largest single win for testability.
4. **H2** and **M4** — two small, self-contained boundary fixes.
5. **C2**, then **H3** and **H6** — introduce `application/` services, which is what makes the cycle fixes possible.
6. **C3** — the doctor-identity fix; requires a backend confirmation step first (step 1 of that finding).
7. **H4**, **M2**, **M3**, **M7** — correctness and diagnostics hardening; each is independent and small.
8. **H1** and **M6** — the calendar page split. Deliberately last: it is the largest change, and it consumes the services
   created in steps 5–7.
9. **H5** — decide and record the fate of the queue subsystem. Step 1 of that finding (removing the shell warm) can be
   done immediately and independently at any point.

