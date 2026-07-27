import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';

import 'appointment_branch_working_hours.dart';

/// Client-side branch working-hours checks aligned with appointment calendar display.
class AppointmentWorkingHours {
  AppointmentWorkingHours._();

  static bool isWithinSchedule({
    required BranchWorkingSchedule schedule,
    required DateTime start,
    required DateTime end,
  }) {
    if (!end.isAfter(start)) {
      return false;
    }

    final localStart = start.toLocal();
    final localEnd = end.toLocal();

    final dayHours = _hoursForDay(schedule, _weekdayFromDate(localStart));
    if (dayHours == null || !dayHours.isWorkingDay) {
      return false;
    }

    final openMinutes = AppointmentBranchWorkingHours.parseHm(dayHours.openTime);
    final closeMinutes = AppointmentBranchWorkingHours.normalizeCloseMinutes(
      AppointmentBranchWorkingHours.parseHm(dayHours.closeTime),
    );
    if (openMinutes == null || closeMinutes == null) {
      return false;
    }

    // Treat 23:59 close as end-of-day so slots ending at midnight are not rejected.
    final effectiveCloseMinutes =
        closeMinutes >= (23 * 60 + 59) ? AppointmentBranchWorkingHours.endOfDayMinutes : closeMinutes;
    final midnightSentinelEnd = _isMidnightSentinelEnd(localStart, localEnd, closeMinutes);
    if (!midnightSentinelEnd &&
        (localStart.year != localEnd.year || localStart.month != localEnd.month || localStart.day != localEnd.day)) {
      return false;
    }

    final startMinutes = localStart.hour * 60 + localStart.minute;
    final endMinutes = midnightSentinelEnd ? AppointmentBranchWorkingHours.endOfDayMinutes : localEnd.hour * 60 + localEnd.minute;
    // Half-open interval [open, close): reject starts at/after close or ends after close.
    return startMinutes >= openMinutes && startMinutes < effectiveCloseMinutes && endMinutes <= effectiveCloseMinutes;
  }

  static BranchWorkingDayHours? _hoursForDay(BranchWorkingSchedule schedule, BranchWeekday weekday) {
    for (final day in schedule.days) {
      if (day.day == weekday) {
        return day;
      }
    }
    return null;
  }

  static BranchWeekday _weekdayFromDate(DateTime date) {
    return switch (date.weekday) {
      DateTime.monday => BranchWeekday.monday,
      DateTime.tuesday => BranchWeekday.tuesday,
      DateTime.wednesday => BranchWeekday.wednesday,
      DateTime.thursday => BranchWeekday.thursday,
      DateTime.friday => BranchWeekday.friday,
      DateTime.saturday => BranchWeekday.saturday,
      _ => BranchWeekday.sunday,
    };
  }

  static bool _isMidnightSentinelEnd(DateTime localStart, DateTime localEnd, int closeMinutes) {
    if (closeMinutes < 23 * 60 + 59) {
      return false;
    }
    if (localEnd.hour != 0 || localEnd.minute != 0) {
      return false;
    }
    final nextDay = DateTime(localStart.year, localStart.month, localStart.day + 1);
    return localEnd.year == nextDay.year && localEnd.month == nextDay.month && localEnd.day == nextDay.day;
  }

}
