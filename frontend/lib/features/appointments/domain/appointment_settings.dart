import 'package:flutter/foundation.dart';

/// Default duration settings for a branch (V1-4 `get_appointment_settings`).
@immutable
class AppointmentSettings {
  const AppointmentSettings({
    required this.defaultDurationMinutes,
    required this.minDurationMinutes,
    required this.maxDurationMinutes,
  });

  final int defaultDurationMinutes;
  final int minDurationMinutes;
  final int maxDurationMinutes;

  static AppointmentSettings? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final defaultMinutes = _parseInt(data['default_duration_minutes']);
    final minMinutes = _parseInt(data['min_duration_minutes']);
    final maxMinutes = _parseInt(data['max_duration_minutes']);

    if (defaultMinutes == null || minMinutes == null || maxMinutes == null) {
      return null;
    }

    return AppointmentSettings(
      defaultDurationMinutes: defaultMinutes,
      minDurationMinutes: minMinutes,
      maxDurationMinutes: maxMinutes,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
