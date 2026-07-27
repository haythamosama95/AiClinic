import 'dart:ui';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_calendar_layout.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_slot_defaults.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';

/// Resolved axis and slot layout for Syncfusion time-slot views.
class AppointmentCalendarTimeSlotLayout {
  const AppointmentCalendarTimeSlotLayout({
    required this.startHour,
    required this.endHour,
    required this.timeIntervalHeight,
    required this.timeIntervalWidth,
    required this.timeIntervalMinutes,
    required this.nonWorkingDays,
    required this.shadeRegions,
  });

  final double startHour;
  final double endHour;
  final double timeIntervalHeight;

  /// Width of each time column in doctor timeline views (`CalendarView.timelineDay`).
  final double timeIntervalWidth;
  final int timeIntervalMinutes;
  final List<int> nonWorkingDays;
  final List<AppointmentCalendarShadeRegion> shadeRegions;
}

/// Pixel layout and Syncfusion geometry helpers for the appointment calendar.
abstract final class AppointmentCalendarGeometry {
  static const double defaultViewportHeight = 640;

  static const double minTimeIntervalHeight = 44;

  /// Wider than Syncfusion's default (60) so doctor-timeline appointment cards
  /// can show patient/time details instead of a compact sliver.
  static const double doctorsTimelineTimeIntervalWidth = 120;

  /// Height of the day/week column header row in the Syncfusion calendar.
  static const double viewHeaderBadgeSize = 26;

  /// Symmetric vertical padding inside each day/week column header cell.
  static const double viewHeaderVerticalPadding = 6;

  /// Height of the day/week column header row in the Syncfusion calendar.
  static const double viewHeaderHeight = viewHeaderVerticalPadding * 2 + viewHeaderBadgeSize;

  /// Width of the time-label gutter to the left of day columns (Syncfusion default).
  static const double timeLabelWidth = 50;

  /// Chrome above the scrollable time-slot grid (view header + borders).
  static const double timeSlotChromeHeight = viewHeaderHeight;

  /// Header title text matching Syncfusion calendar header formatting.
  static String headerTitle(AppointmentCalendarMode mode, DateTime focusDate) {
    final anchor = switch (mode) {
      AppointmentCalendarMode.week => _weekStart(focusDate),
      _ => DateTime(focusDate.year, focusDate.month, focusDate.day),
    };
    return '${DateFormat('MMMM').format(anchor)} ${anchor.year}';
  }

  static AppointmentCalendarTimeSlotLayout timeSlotLayout({
    required BranchWorkingSchedule schedule,
    required AppointmentCalendarMode mode,
    required DateTime focusDate,
    double viewportHeight = defaultViewportHeight,
    int timeIntervalMinutes = defaultTimeIntervalMinutes,
  }) {
    final intervalMinutes = supportedTimeIntervalMinutes.contains(timeIntervalMinutes)
        ? timeIntervalMinutes
        : defaultTimeIntervalMinutes;
    final hourRange = switch (mode) {
      AppointmentCalendarMode.day => AppointmentCalendarLayout.hourRangeForDay(schedule, focusDate),
      AppointmentCalendarMode.doctors => AppointmentCalendarLayout.hourRangeForDay(schedule, focusDate),
      AppointmentCalendarMode.week => AppointmentCalendarLayout.hourRangeForWeek(schedule),
      AppointmentCalendarMode.schedule => const AppointmentCalendarHourRange(startHour: 8, endHour: 18),
      AppointmentCalendarMode.month => const AppointmentCalendarHourRange(startHour: 8, endHour: 18),
    };

    final slotCount = ((hourRange.endHour - hourRange.startHour) * 60 / intervalMinutes).ceil().clamp(1, 48);
    final slotAreaHeight = (viewportHeight - timeSlotChromeHeight).clamp(minTimeIntervalHeight, double.infinity);
    final intervalHeight = (slotAreaHeight / slotCount).clamp(minTimeIntervalHeight, double.infinity);

    final timeIntervalWidth = mode == AppointmentCalendarMode.doctors ? doctorsTimelineTimeIntervalWidth : -2.0;

    return AppointmentCalendarTimeSlotLayout(
      startHour: hourRange.startHour,
      endHour: hourRange.endHour,
      timeIntervalHeight: intervalHeight,
      timeIntervalWidth: timeIntervalWidth,
      timeIntervalMinutes: intervalMinutes,
      nonWorkingDays: AppointmentCalendarLayout.nonWorkingDays(schedule),
      shadeRegions: mode == AppointmentCalendarMode.week
          ? AppointmentCalendarLayout.shadeRegionsForWeek(schedule, focusDate)
          : const [],
    );
  }

  /// Alternating row stripes for the doctor resource timeline view.
  static List<TimeRegion> resourceRowStripeRegions({
    required List<Object> resourceIds,
    required DateTime focusDate,
    required double startHour,
    required double endHour,
    required Color stripeColor,
  }) {
    if (resourceIds.isEmpty) {
      return const [];
    }

    final local = focusDate.toLocal();
    final dayStart = DateTime(local.year, local.month, local.day);
    final rangeStart = dayStart.add(Duration(minutes: (startHour * 60).round()));
    final rangeEnd = dayStart.add(Duration(minutes: (endHour * 60).round()));

    return [
      for (var index = 0; index < resourceIds.length; index++)
        if (index.isOdd)
          TimeRegion(
            startTime: rangeStart,
            endTime: rangeEnd,
            enablePointerInteraction: false,
            color: stripeColor,
            resourceIds: [resourceIds[index]],
          ),
    ];
  }

  /// Whether [bounds] align to the calendar slot grid (as opposed to a free drag ghost).
  static bool isAlignedToSlotGrid(Rect bounds, double slotSize, {required bool timelineAxisIsHorizontal}) {
    if (slotSize <= 0) {
      return true;
    }

    final offset = timelineAxisIsHorizontal ? bounds.left % slotSize : bounds.top % slotSize;
    return offset <= 1 || offset >= slotSize - 1;
  }

  static DateTime _weekStart(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    return dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
  }
}
