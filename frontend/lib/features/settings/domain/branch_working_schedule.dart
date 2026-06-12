import 'package:flutter/foundation.dart';

enum BranchWeekday { monday, tuesday, wednesday, thursday, friday, saturday, sunday }

extension BranchWeekdayLabel on BranchWeekday {
  String get wireValue => name;

  String get label => switch (this) {
    BranchWeekday.monday => 'Monday',
    BranchWeekday.tuesday => 'Tuesday',
    BranchWeekday.wednesday => 'Wednesday',
    BranchWeekday.thursday => 'Thursday',
    BranchWeekday.friday => 'Friday',
    BranchWeekday.saturday => 'Saturday',
    BranchWeekday.sunday => 'Sunday',
  };
}

@immutable
class BranchWorkingDayHours {
  const BranchWorkingDayHours({required this.day, required this.isWorkingDay, this.openTime, this.closeTime});

  final BranchWeekday day;
  final bool isWorkingDay;
  final String? openTime;
  final String? closeTime;

  BranchWorkingDayHours copyWith({bool? isWorkingDay, Object? openTime = _sentinel, Object? closeTime = _sentinel}) {
    return BranchWorkingDayHours(
      day: day,
      isWorkingDay: isWorkingDay ?? this.isWorkingDay,
      openTime: identical(openTime, _sentinel) ? this.openTime : openTime as String?,
      closeTime: identical(closeTime, _sentinel) ? this.closeTime : closeTime as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day.wireValue,
    'is_working_day': isWorkingDay,
    if (openTime != null) 'open_time': openTime,
    if (closeTime != null) 'close_time': closeTime,
  };

  static BranchWorkingDayHours? fromJson(Map<String, dynamic> json) {
    final dayRaw = json['day']?.toString();
    if (dayRaw == null) {
      return null;
    }
    BranchWeekday? day;
    for (final candidate in BranchWeekday.values) {
      if (candidate.wireValue == dayRaw) {
        day = candidate;
        break;
      }
    }
    if (day == null) {
      return null;
    }

    final workingRaw = json['is_working_day'];
    final isWorkingDay = workingRaw is bool
        ? workingRaw
        : (workingRaw?.toString().toLowerCase() == 'true' || workingRaw == 1);

    String? normalizeTime(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return BranchWorkingDayHours(
      day: day,
      isWorkingDay: isWorkingDay,
      openTime: normalizeTime(json['open_time']),
      closeTime: normalizeTime(json['close_time']),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BranchWorkingDayHours &&
            runtimeType == other.runtimeType &&
            day == other.day &&
            isWorkingDay == other.isWorkingDay &&
            openTime == other.openTime &&
            closeTime == other.closeTime;
  }

  @override
  int get hashCode => Object.hash(day, isWorkingDay, openTime, closeTime);
}

@immutable
class BranchWorkingSchedule {
  const BranchWorkingSchedule(this.days);

  final List<BranchWorkingDayHours> days;

  static BranchWorkingSchedule defaultSchedule() {
    return BranchWorkingSchedule(
      BranchWeekday.values
          .map(
            (day) => BranchWorkingDayHours(
              day: day,
              isWorkingDay: day != BranchWeekday.sunday,
              openTime: day == BranchWeekday.sunday ? null : '09:00',
              closeTime: day == BranchWeekday.sunday ? null : '17:00',
            ),
          )
          .toList(growable: false),
    );
  }

  /// Setup wizard initial state: every day closed until the user configures hours.
  static BranchWorkingSchedule emptySchedule() {
    return BranchWorkingSchedule(
      BranchWeekday.values
          .map((day) => BranchWorkingDayHours(day: day, isWorkingDay: false, openTime: null, closeTime: null))
          .toList(growable: false),
    );
  }

  /// True when at least one day is open with valid HH:mm open/close times.
  bool get hasConfiguredWorkingHours => days.any(isValidWorkingDay);

  static bool isValidWorkingDay(BranchWorkingDayHours hours) {
    if (!hours.isWorkingDay) {
      return false;
    }
    final open = parseHmTime(hours.openTime);
    final close = parseHmTime(hours.closeTime);
    if (open == null || close == null) {
      return false;
    }
    return open < close;
  }

  static int? parseHmTime(String? input) {
    final normalized = input?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(normalized);
    if (match == null) {
      return null;
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    return hour * 60 + minute;
  }

  Map<String, dynamic> toJson() => {'days': days.map((day) => day.toJson()).toList(growable: false)};

  static BranchWorkingSchedule? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(json);
    final rawDays = map['days'];
    if (rawDays is! List) {
      return null;
    }
    final parsed = <BranchWorkingDayHours>[];
    for (final raw in rawDays) {
      if (raw is! Map) {
        continue;
      }
      final day = BranchWorkingDayHours.fromJson(Map<String, dynamic>.from(raw));
      if (day != null) {
        parsed.add(day);
      }
    }
    if (parsed.isEmpty) {
      return null;
    }

    final indexed = {for (final day in parsed) day.day: day};
    return BranchWorkingSchedule(
      BranchWeekday.values
          .map(
            (weekday) =>
                indexed[weekday] ??
                BranchWorkingDayHours(day: weekday, isWorkingDay: false, openTime: null, closeTime: null),
          )
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! BranchWorkingSchedule || days.length != other.days.length) {
      return false;
    }
    for (var i = 0; i < days.length; i++) {
      if (days[i] != other.days[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(days);
}

const _sentinel = Object();
