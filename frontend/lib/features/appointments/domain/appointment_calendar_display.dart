import 'dart:ui';

import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

/// Muted time blocks (before open / after close) for week-style views.
class AppointmentCalendarShadeRegion {
  const AppointmentCalendarShadeRegion({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// Resolved axis and slot layout for Syncfusion time-slot views.
class AppointmentCalendarTimeSlotLayout {
  const AppointmentCalendarTimeSlotLayout({
    required this.startHour,
    required this.endHour,
    required this.timeIntervalHeight,
    required this.timeIntervalMinutes,
    required this.nonWorkingDays,
    required this.shadeRegions,
  });

  final double startHour;
  final double endHour;
  final double timeIntervalHeight;
  final int timeIntervalMinutes;
  final List<int> nonWorkingDays;
  final List<AppointmentCalendarShadeRegion> shadeRegions;
}

/// Pure calendar display rules derived from branch working hours.
class AppointmentCalendarDisplay {
  AppointmentCalendarDisplay._();

  static const double defaultViewportHeight = 640;
  static const int defaultTimeIntervalMinutes = 30;
  static const double minTimeIntervalHeight = 44;

  /// Day/week header chrome above the scrollable time-slot grid.
  static const double timeSlotChromeHeight = 80;

  static AppointmentCalendarTimeSlotLayout timeSlotLayout({
    required BranchWorkingSchedule schedule,
    required AppointmentCalendarMode mode,
    required DateTime focusDate,
    double viewportHeight = defaultViewportHeight,
  }) {
    final (startHour, endHour) = switch (mode) {
      AppointmentCalendarMode.day => _hourRangeForDay(schedule, focusDate),
      AppointmentCalendarMode.week => _hourRangeForWeek(schedule),
      AppointmentCalendarMode.month => (8.0, 18.0),
    };

    final slotCount = ((endHour - startHour) * 60 / defaultTimeIntervalMinutes).ceil().clamp(1, 48);
    final slotAreaHeight = (viewportHeight - timeSlotChromeHeight).clamp(minTimeIntervalHeight, double.infinity);
    final intervalHeight = (slotAreaHeight / slotCount).clamp(minTimeIntervalHeight, double.infinity);

    return AppointmentCalendarTimeSlotLayout(
      startHour: startHour,
      endHour: endHour,
      timeIntervalHeight: intervalHeight,
      timeIntervalMinutes: defaultTimeIntervalMinutes,
      nonWorkingDays: nonWorkingDays(schedule),
      shadeRegions: mode == AppointmentCalendarMode.week ? shadeRegionsForWeek(schedule, focusDate) : const [],
    );
  }

  static bool isClosedOnDate(BranchWorkingSchedule schedule, DateTime date) {
    return !AppointmentBranchWorkingHours.isWorkingDay(schedule, date);
  }

  static bool showWeekends(BranchWorkingSchedule schedule) {
    return _isWorkingWeekday(schedule, BranchWeekday.saturday) || _isWorkingWeekday(schedule, BranchWeekday.sunday);
  }

  static List<int> nonWorkingDays(BranchWorkingSchedule schedule) {
    final closed = <int>[];
    for (final day in schedule.days) {
      if (!day.isWorkingDay) {
        closed.add(_weekdayConstant(day.day));
      }
    }
    return closed;
  }

  static List<DateTime> closedDatesInMonth(BranchWorkingSchedule schedule, DateTime focusDate) {
    final monthStart = DateTime(focusDate.year, focusDate.month, 1);
    final monthEnd = DateTime(focusDate.year, focusDate.month + 1, 1);
    final closed = <DateTime>[];
    for (var date = monthStart; date.isBefore(monthEnd); date = date.add(const Duration(days: 1))) {
      if (isClosedOnDate(schedule, date)) {
        closed.add(DateTime(date.year, date.month, date.day));
      }
    }
    return closed;
  }

  static List<AppointmentCalendarShadeRegion> shadeRegionsForWeek(BranchWorkingSchedule schedule, DateTime focusDate) {
    final dayStart = DateTime(focusDate.year, focusDate.month, focusDate.day);
    final weekStart = dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
    final regions = <AppointmentCalendarShadeRegion>[];

    for (var offset = 0; offset < 7; offset++) {
      final date = weekStart.add(Duration(days: offset));
      final dayHours = AppointmentBranchWorkingHours.hoursForDate(schedule, date);
      if (dayHours == null || !dayHours.isWorkingDay) {
        continue;
      }

      final openMinutes = AppointmentBranchWorkingHours.parseHm(dayHours.openTime);
      final closeMinutes = AppointmentBranchWorkingHours.parseHm(dayHours.closeTime);
      if (openMinutes == null || closeMinutes == null || openMinutes >= closeMinutes) {
        continue;
      }

      final dayMidnight = DateTime(date.year, date.month, date.day);
      if (openMinutes > 0) {
        regions.add(
          AppointmentCalendarShadeRegion(
            start: dayMidnight,
            end: dayMidnight.add(Duration(minutes: openMinutes)),
          ),
        );
      }

      if (closeMinutes < 24 * 60) {
        regions.add(
          AppointmentCalendarShadeRegion(
            start: dayMidnight.add(Duration(minutes: closeMinutes)),
            end: dayMidnight.add(const Duration(days: 1)),
          ),
        );
      }
    }

    return regions;
  }

  static List<AppointmentListItem> filterVisibleAppointments(
    List<AppointmentListItem> items,
    BranchWorkingSchedule schedule,
  ) {
    return items
        .where(
          (item) =>
              AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: item.startTime, end: item.endTime),
        )
        .toList(growable: false);
  }

  static Color statusColor(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => const Color(0xFF2563EB),
      AppointmentStatus.confirmed => const Color(0xFF0D9488),
      AppointmentStatus.checkedIn => const Color(0xFF0891B2),
      AppointmentStatus.inProgress => const Color(0xFFEA580C),
      AppointmentStatus.completed => const Color(0xFF16A34A),
      AppointmentStatus.cancelled => const Color(0xFFDC2626),
      AppointmentStatus.noShow => const Color(0xFF7C3AED),
      AppointmentStatus.unknown => const Color(0xFF6B7280),
    };
  }

  static (double, double) _hourRangeForDay(BranchWorkingSchedule schedule, DateTime date) {
    final dayHours = AppointmentBranchWorkingHours.hoursForDate(schedule, date);
    if (dayHours == null || !dayHours.isWorkingDay) {
      return (8, 18);
    }

    final open = AppointmentBranchWorkingHours.parseHm(dayHours.openTime);
    final close = AppointmentBranchWorkingHours.parseHm(dayHours.closeTime);
    if (open == null || close == null || open >= close) {
      return (8, 18);
    }

    return (_minutesToHour(open), _minutesToEndHour(close));
  }

  static (double, double) _hourRangeForWeek(BranchWorkingSchedule schedule) {
    var minMinutes = 24 * 60;
    var maxMinutes = 0;

    for (final day in schedule.days) {
      if (!day.isWorkingDay) {
        continue;
      }
      final open = AppointmentBranchWorkingHours.parseHm(day.openTime);
      final close = AppointmentBranchWorkingHours.parseHm(day.closeTime);
      if (open == null || close == null || open >= close) {
        continue;
      }
      if (open < minMinutes) {
        minMinutes = open;
      }
      if (close > maxMinutes) {
        maxMinutes = close;
      }
    }

    if (minMinutes == 24 * 60 || maxMinutes == 0) {
      return (8, 18);
    }

    var startHour = _minutesToHour(minMinutes);
    var endHour = _minutesToEndHour(maxMinutes);
    if (endHour <= startHour) {
      endHour = (startHour + 1).clamp(1, 24).toDouble();
    }
    return (startHour, endHour);
  }

  static double _minutesToHour(int minutes) => (minutes ~/ 60) + (minutes % 60) / 60;

  static double _minutesToEndHour(int minutes) {
    if (minutes % 60 == 0) {
      return (minutes ~/ 60).toDouble();
    }
    return ((minutes + 59) ~/ 60).toDouble().clamp(1, 24);
  }

  static bool _isWorkingWeekday(BranchWorkingSchedule schedule, BranchWeekday weekday) {
    for (final day in schedule.days) {
      if (day.day == weekday) {
        return day.isWorkingDay;
      }
    }
    return false;
  }

  static int _weekdayConstant(BranchWeekday weekday) {
    return switch (weekday) {
      BranchWeekday.monday => DateTime.monday,
      BranchWeekday.tuesday => DateTime.tuesday,
      BranchWeekday.wednesday => DateTime.wednesday,
      BranchWeekday.thursday => DateTime.thursday,
      BranchWeekday.friday => DateTime.friday,
      BranchWeekday.saturday => DateTime.saturday,
      BranchWeekday.sunday => DateTime.sunday,
    };
  }
}
