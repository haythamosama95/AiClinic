/// Preset default appointment durations for branch settings (15-minute steps up to 3 hours).
abstract final class AppointmentDurationOptions {
  static const int stepMinutes = 15;
  static const int maxMinutes = 180;
  static const int defaultMinutes = 30;

  static final List<int> presetMinutes = List.generate(maxMinutes ~/ stepMinutes, (index) => (index + 1) * stepMinutes);

  static Map<String, int> selectItems({int? includeMinutes}) {
    final minutes = <int>{...presetMinutes};
    if (includeMinutes != null && includeMinutes > 0) {
      minutes.add(includeMinutes);
    }

    final sorted = minutes.toList()..sort();
    return {for (final value in sorted) formatMinutes(value): value};
  }

  static String formatMinutes(int minutes) {
    if (minutes < 60) {
      return '$minutes minutes';
    }

    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    final hourLabel = hours == 1 ? '1 hr' : '$hours hr';
    if (remainder == 0) {
      return hourLabel;
    }
    return '$hourLabel $remainder minutes';
  }
}
