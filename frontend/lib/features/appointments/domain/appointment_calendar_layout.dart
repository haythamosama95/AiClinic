import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_slot_defaults.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';

/// Muted time blocks (before open / after close) for week-style views.
class AppointmentCalendarShadeRegion {
  const AppointmentCalendarShadeRegion({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// Visible hour range for a calendar day or week axis.
class AppointmentCalendarHourRange {
  const AppointmentCalendarHourRange({required this.startHour, required this.endHour});

  final double startHour;
  final double endHour;
}

/// Domain scheduling layout rules for the appointment calendar.
abstract final class AppointmentCalendarLayout {
  static List<DateTime> visibleHeaderDays(AppointmentCalendarMode mode, DateTime focusDate) {
    final anchor = DateTime(focusDate.year, focusDate.month, focusDate.day);
    return switch (mode) {
      AppointmentCalendarMode.day => [anchor],
      AppointmentCalendarMode.week => List.generate(7, (index) => _weekStart(anchor).add(Duration(days: index))),
      _ => const [],
    };
  }

  static AppointmentCalendarHourRange hourRangeForDay(BranchWorkingSchedule schedule, DateTime date) {
    final (startHour, endHour) = _hourRangeForDay(schedule, date);
    return AppointmentCalendarHourRange(startHour: startHour, endHour: endHour);
  }

  static AppointmentCalendarHourRange hourRangeForWeek(BranchWorkingSchedule schedule) {
    final (startHour, endHour) = _hourRangeForWeek(schedule);
    return AppointmentCalendarHourRange(startHour: startHour, endHour: endHour);
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
      if (!AppointmentBranchWorkingHours.isWorkingDay(schedule, date)) {
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

  /// Resolves the booking window for a calendar tap (slot start/end in local time).
  static ({DateTime start, DateTime end}) slotRangeFromTap({
    required DateTime tappedDate,
    required BranchWorkingSchedule schedule,
    required AppointmentCalendarMode mode,
    int slotMinutes = defaultTimeIntervalMinutes,
  }) {
    final local = tappedDate.toLocal();
    final hasExplicitTime = local.hour != 0 || local.minute != 0;
    final DateTime start;

    if (mode == AppointmentCalendarMode.month || !hasExplicitTime) {
      final dayHours = AppointmentBranchWorkingHours.hoursForDate(schedule, local);
      final openMinutes = dayHours != null && dayHours.isWorkingDay
          ? AppointmentBranchWorkingHours.parseHm(dayHours.openTime) ?? 9 * 60
          : 9 * 60;
      start = DateTime(local.year, local.month, local.day, openMinutes ~/ 60, openMinutes % 60);
    } else {
      start = DateTime(local.year, local.month, local.day, local.hour, local.minute);
    }

    return (start: start, end: start.add(Duration(minutes: slotMinutes)));
  }

  /// Snaps [time] to the nearest calendar slot start (e.g. 30-minute grid).
  static DateTime snapTimeToSlot(DateTime time, {int slotMinutes = defaultTimeIntervalMinutes}) {
    if (slotMinutes <= 0) {
      return time.toLocal();
    }

    final local = time.toLocal();
    final dayStart = DateTime(local.year, local.month, local.day);
    final totalMinutes = local.hour * 60 + local.minute;
    final slotIndex = ((totalMinutes + slotMinutes ~/ 2) / slotMinutes).floor();
    final snappedMinutes = slotIndex * slotMinutes;
    return dayStart.add(Duration(minutes: snappedMinutes));
  }

  static DateTime _weekStart(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    return dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
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
