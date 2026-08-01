import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/features/settings/domain/format_preferences.dart';
import 'package:ai_clinic/features/settings/domain/notification_preferences.dart';

const _dateFormatKey = 'aiclinic.date-format';
const _timeFormatKey = 'aiclinic.time-format';
const _notificationPrefsKey = 'aiclinic.notification-prefs';

/// Persists workstation appearance and notification preferences.
class WorkstationPreferencesStore {
  const WorkstationPreferencesStore();

  Future<AppDateFormat> loadDateFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return AppDateFormat.tryParse(prefs.getString(_dateFormatKey)) ?? AppDateFormat.defaultValue;
  }

  Future<void> saveDateFormat(AppDateFormat value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dateFormatKey, value.storageValue);
  }

  Future<AppTimeFormat> loadTimeFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return AppTimeFormat.tryParse(prefs.getString(_timeFormatKey)) ?? AppTimeFormat.defaultValue;
  }

  Future<void> saveTimeFormat(AppTimeFormat value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_timeFormatKey, value.storageValue);
  }

  Future<NotificationPreferences> loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notificationPrefsKey);
    if (raw == null) {
      return NotificationPreferences.defaults;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return NotificationPreferences.defaults;
      }
      return NotificationPreferences.defaults.merge(NotificationPreferences.fromJson(decoded));
    } catch (_) {
      return NotificationPreferences.defaults;
    }
  }

  Future<void> saveNotificationPreferences(NotificationPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notificationPrefsKey, jsonEncode(value.toJson()));
  }
}

final workstationPreferencesStoreProvider = Provider<WorkstationPreferencesStore>(
  (ref) => const WorkstationPreferencesStore(),
);
