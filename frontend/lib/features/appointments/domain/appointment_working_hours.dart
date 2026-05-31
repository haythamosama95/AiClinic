import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

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
    if (localStart.year != localEnd.year || localStart.month != localEnd.month || localStart.day != localEnd.day) {
      return false;
    }

    final dayHours = _hoursForDay(schedule, _weekdayFromDate(localStart));
    if (dayHours == null || !dayHours.isWorkingDay) {
      return false;
    }

    final openMinutes = _parseHm(dayHours.openTime);
    final closeMinutes = _parseHm(dayHours.closeTime);
    if (openMinutes == null || closeMinutes == null) {
      return false;
    }

    final startMinutes = localStart.hour * 60 + localStart.minute;
    final endMinutes = localEnd.hour * 60 + localEnd.minute;
    return startMinutes >= openMinutes && endMinutes <= closeMinutes;
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

  static int? _parseHm(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(text);
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }
}
