import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';

/// Persists clinic workstation preferences beside [deployment-profile.json].
class IdleTimeoutPreferencesStore {
  const IdleTimeoutPreferencesStore();

  static const fileName = 'clinic-settings.json';
  static const _idleTimeoutKey = 'idle_timeout_minutes';

  Future<Duration> loadIdleDuration() async {
    try {
      final file = _settingsFile();
      if (!await file.exists()) {
        return IdleTimeoutConfig.defaultDuration;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return IdleTimeoutConfig.defaultDuration;
      }

      final minutes = decoded[_idleTimeoutKey];
      if (minutes is! num) {
        return IdleTimeoutConfig.defaultDuration;
      }

      return IdleTimeoutConfig.clampMinutes(minutes.round());
    } on IOException catch (error) {
      AppLog.warning('settings.idle_timeout.load_failed reason=${error.runtimeType}');
      return IdleTimeoutConfig.defaultDuration;
    } on FormatException {
      return IdleTimeoutConfig.defaultDuration;
    }
  }

  Future<void> saveIdleDuration(Duration duration) async {
    final clamped = IdleTimeoutConfig.clampDuration(duration);
    final file = _settingsFile();
    Map<String, dynamic> payload = {};

    if (await file.exists()) {
      try {
        final existing = jsonDecode(await file.readAsString());
        if (existing is Map<String, dynamic>) {
          payload = Map<String, dynamic>.from(existing);
        }
      } on FormatException {
        payload = {};
      }
    }

    payload[_idleTimeoutKey] = clamped.inMinutes;
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    AppLog.fine('settings.idle_timeout.saved minutes=${clamped.inMinutes}');
  }

  File _settingsFile() {
    return File('${Directory.current.path}${Platform.pathSeparator}$fileName');
  }
}

final idleTimeoutPreferencesStoreProvider = Provider<IdleTimeoutPreferencesStore>(
  (ref) => const IdleTimeoutPreferencesStore(),
);
