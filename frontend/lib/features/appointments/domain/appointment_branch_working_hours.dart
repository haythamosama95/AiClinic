import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

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

  static int? parseHm(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$').firstMatch(text);
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
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
    final closeMinutes = parseHm(dayHours.closeTime);
    if (openMinutes == null || closeMinutes == null || openMinutes >= closeMinutes) {
      return 'Branch working hours are not configured for the selected day.';
    }

    final startMinutes = localStart.hour * 60 + localStart.minute;
    final endMinutes = localEnd.hour * 60 + localEnd.minute;
    if (startMinutes < openMinutes || endMinutes > closeMinutes) {
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
