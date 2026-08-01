import 'dart:convert';

import 'package:ai_clinic/features/settings/data/workstation_preferences_store.dart';
import 'package:ai_clinic/features/settings/domain/format_preferences.dart';
import 'package:ai_clinic/features/settings/domain/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = WorkstationPreferencesStore();

  group('WorkstationPreferencesStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('loadDateFormat and loadTimeFormat return defaults when empty', () async {
      expect(await store.loadDateFormat(), AppDateFormat.defaultValue);
      expect(await store.loadTimeFormat(), AppTimeFormat.defaultValue);
    });

    test('save and reload date and time formats', () async {
      await store.saveDateFormat(AppDateFormat.mdy);
      await store.saveTimeFormat(AppTimeFormat.h24);

      expect(await store.loadDateFormat(), AppDateFormat.mdy);
      expect(await store.loadTimeFormat(), AppTimeFormat.h24);
    });

    test('invalid stored format strings fall back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        'aiclinic.date-format': 'invalid',
        'aiclinic.time-format': 'invalid',
      });

      expect(await store.loadDateFormat(), AppDateFormat.defaultValue);
      expect(await store.loadTimeFormat(), AppTimeFormat.defaultValue);
    });

    test('loadNotificationPreferences returns defaults when missing', () async {
      expect(await store.loadNotificationPreferences(), NotificationPreferences.defaults);
    });

    test('save and reload notification preferences round-trip', () async {
      const prefs = NotificationPreferences(
        appointmentReminders: false,
        billingAlerts: true,
        labResults: false,
        shiftHandoffs: true,
        productUpdates: true,
      );

      await store.saveNotificationPreferences(prefs);

      expect(await store.loadNotificationPreferences(), prefs);
    });

    test('corrupt notification JSON returns defaults', () async {
      SharedPreferences.setMockInitialValues({
        'aiclinic.notification-prefs': '{not-json',
      });

      expect(await store.loadNotificationPreferences(), NotificationPreferences.defaults);
    });

    test('non-map notification JSON returns defaults', () async {
      SharedPreferences.setMockInitialValues({
        'aiclinic.notification-prefs': jsonEncode(['not', 'a', 'map']),
      });

      expect(await store.loadNotificationPreferences(), NotificationPreferences.defaults);
    });

    test('partial notification JSON merges with defaults', () async {
      SharedPreferences.setMockInitialValues({
        'aiclinic.notification-prefs': jsonEncode({'shiftHandoffs': true}),
      });

      final loaded = await store.loadNotificationPreferences();

      expect(loaded.shiftHandoffs, isTrue);
      expect(loaded.appointmentReminders, NotificationPreferences.defaults.appointmentReminders);
    });

    test('notification JSON with invalid bool types returns defaults', () async {
      SharedPreferences.setMockInitialValues({
        'aiclinic.notification-prefs': jsonEncode({'appointmentReminders': 'yes'}),
      });

      expect(await store.loadNotificationPreferences(), NotificationPreferences.defaults);
    });
  });
}
