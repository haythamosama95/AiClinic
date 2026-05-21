import 'package:ai_clinic/core/auth/idle_timeout_service.dart';

/// Validation and presets for workstation idle sign-out duration.
abstract final class IdleTimeoutConfig {
  static const int minMinutes = 1;
  static const int maxMinutes = 120;
  static const int defaultMinutes = 15;

  static const List<int> presetMinutes = [5, 10, 15, 20, 30, 45, 60];

  static Duration get defaultDuration => kIdleTimeoutDuration;

  static Duration clampMinutes(int minutes) {
    final clamped = minutes.clamp(minMinutes, maxMinutes);
    return Duration(minutes: clamped);
  }

  static Duration clampDuration(Duration duration) {
    return clampMinutes(duration.inMinutes);
  }

  /// Parses user input; returns null when empty or invalid.
  static int? tryParseMinutes(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final value = int.tryParse(trimmed);
    if (value == null || value < minMinutes || value > maxMinutes) {
      return null;
    }

    return value;
  }

  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes == 1) {
      return '1 minute';
    }
    return '$minutes minutes';
  }
}
