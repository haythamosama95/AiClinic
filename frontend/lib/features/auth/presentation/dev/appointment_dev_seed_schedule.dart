import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

/// Computes appointment start times that fit a branch [BranchWorkingSchedule].
class AppointmentDevSeedSchedule {
  AppointmentDevSeedSchedule._();

  static const _plannedDurationMinutes = 30;
  static const _plannedIntervalMinutes = 30;
  static const _maxDayLookahead = 366;

  /// Returns up to [count] local start times for planned appointments.
  ///
  /// Slots are aligned to 15-minute boundaries, start at least 30 minutes after
  /// [reference], and stay within each working day's open/close times.
  static List<DateTime> plannedStartTimes({
    required BranchWorkingSchedule schedule,
    required int count,
    int durationMinutes = _plannedDurationMinutes,
    int intervalMinutes = _plannedIntervalMinutes,
    DateTime? reference,
  }) {
    if (count <= 0) {
      return const [];
    }

    final now = (reference ?? DateTime.now()).toLocal();
    final earliest = _roundUpToQuarterHour(now).add(const Duration(minutes: 30));
    final slots = <DateTime>[];

    for (var dayOffset = 0; dayOffset < _maxDayLookahead && slots.length < count; dayOffset++) {
      final day = DateTime(earliest.year, earliest.month, earliest.day).add(Duration(days: dayOffset));
      final dayHours = _hoursForDate(schedule, day);
      if (dayHours == null || !dayHours.isWorkingDay) {
        continue;
      }

      final openMinutes = _parseHm(dayHours.openTime);
      final closeMinutes = _parseHm(dayHours.closeTime);
      if (openMinutes == null || closeMinutes == null || openMinutes >= closeMinutes) {
        continue;
      }

      var slotStart = DateTime(day.year, day.month, day.day, openMinutes ~/ 60, openMinutes % 60);
      final dayEnd = DateTime(day.year, day.month, day.day, closeMinutes ~/ 60, closeMinutes % 60);

      if (dayOffset == 0 && slotStart.isBefore(earliest)) {
        slotStart = _roundUpToQuarterHour(earliest);
      }

      while (slots.length < count) {
        final slotEnd = slotStart.add(Duration(minutes: durationMinutes));
        if (slotEnd.isAfter(dayEnd)) {
          break;
        }
        slots.add(slotStart);
        slotStart = slotStart.add(Duration(minutes: intervalMinutes));
      }
    }

    return slots;
  }

  static BranchWorkingDayHours? _hoursForDate(BranchWorkingSchedule schedule, DateTime date) {
    final weekday = switch (date.weekday) {
      DateTime.monday => BranchWeekday.monday,
      DateTime.tuesday => BranchWeekday.tuesday,
      DateTime.wednesday => BranchWeekday.wednesday,
      DateTime.thursday => BranchWeekday.thursday,
      DateTime.friday => BranchWeekday.friday,
      DateTime.saturday => BranchWeekday.saturday,
      _ => BranchWeekday.sunday,
    };

    for (final day in schedule.days) {
      if (day.day == weekday) {
        return day;
      }
    }
    return null;
  }

  static int? _parseHm(String? value) {
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

  static DateTime _roundUpToQuarterHour(DateTime value) {
    final roundedMinute = ((value.minute + 14) ~/ 15) * 15;
    if (roundedMinute >= 60) {
      return DateTime(value.year, value.month, value.day, value.hour + 1, 0);
    }
    return DateTime(value.year, value.month, value.day, value.hour, roundedMinute);
  }
}
