import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';

/// Validates appointment slots against a branch [BranchWorkingSchedule].
class AppointmentBranchWorkingHours {
  AppointmentBranchWorkingHours._();

  static BranchWeekday weekdayFromDate(DateTime date) {
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

  static BranchWorkingDayHours? hoursForDate(BranchWorkingSchedule schedule, DateTime date) {
    final weekday = weekdayFromDate(date);
    for (final day in schedule.days) {
      if (day.day == weekday) {
        return day;
      }
    }
    return null;
  }

  static bool isWorkingDay(BranchWorkingSchedule schedule, DateTime date) {
    final day = hoursForDate(schedule, date);
    return day?.isWorkingDay ?? false;
  }

  /// Calendar date of the most recent working day strictly before [date].
  ///
  /// Walks backward up to 14 days to skip weekends and configured closures.
  static DateTime? previousWorkingDay(BranchWorkingSchedule schedule, DateTime date) {
    var candidate = DateTime(date.year, date.month, date.day).subtract(const Duration(days: 1));
    for (var i = 0; i < 14; i++) {
      if (isWorkingDay(schedule, candidate)) {
        return candidate;
      }
      candidate = candidate.subtract(const Duration(days: 1));
    }
    return null;
  }

  static const int endOfDayMinutes = 24 * 60;

  /// Parses `H:mm`, `HH:mm`, or `HH:mm:ss` clock strings into minutes since midnight.
  static int? parseHm(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    if (parts.length == 3) {
      final second = int.tryParse(parts[2]);
      if (second == null || second < 0 || second > 59) {
        return null;
      }
    }
    return hour * 60 + minute;
  }

  /// Treats a midnight (`00:00`) close time as end-of-day.
  static int? normalizeCloseMinutes(int? minutes) {
    if (minutes == null) {
      return null;
    }
    return minutes == 0 ? endOfDayMinutes : minutes;
  }

  static String? validationMessage({
    required BranchWorkingSchedule schedule,
    required DateTime startTime,
    required int durationMinutes,
  }) {
    final localStart = startTime.toLocal();
    final localEnd = localStart.add(Duration(minutes: durationMinutes));
    if (localStart.year != localEnd.year || localStart.month != localEnd.month || localStart.day != localEnd.day) {
      return 'Appointment must start and end on the same day.';
    }

    final dayHours = hoursForDate(schedule, localStart);
    if (dayHours == null || !dayHours.isWorkingDay) {
      return 'The branch is closed on the selected day.';
    }

    final openMinutes = parseHm(dayHours.openTime);
    final closeMinutes = normalizeCloseMinutes(parseHm(dayHours.closeTime));
    if (openMinutes == null || closeMinutes == null || openMinutes >= closeMinutes) {
      return 'Branch working hours are not configured for the selected day.';
    }

    final startMinutes = localStart.hour * 60 + localStart.minute;
    final endMinutes = localEnd.hour * 60 + localEnd.minute;
    // Half-open interval [open, close): reject starts at/after close or ends after close.
    if (startMinutes < openMinutes || startMinutes >= closeMinutes || endMinutes > closeMinutes) {
      return 'Appointment must be within branch working hours (${dayHours.openTime}–${dayHours.closeTime}).';
    }

    return null;
  }

  static bool isWithinWorkingHours({
    required BranchWorkingSchedule schedule,
    required DateTime startTime,
    required int durationMinutes,
  }) {
    return validationMessage(schedule: schedule, startTime: startTime, durationMinutes: durationMinutes) == null;
  }

  static String? hoursLabelForDate(BranchWorkingSchedule schedule, DateTime date) {
    final dayHours = hoursForDate(schedule, date);
    if (dayHours == null || !dayHours.isWorkingDay) {
      return 'Closed';
    }
    final open = dayHours.openTime;
    final close = dayHours.closeTime;
    if (open == null || close == null) {
      return null;
    }
    return '$open–$close';
  }
}
