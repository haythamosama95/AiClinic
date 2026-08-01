import 'package:ai_clinic/features/settings/domain/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationPreferences', () {
    test('defaults enable clinical alerts and disable marketing toggles', () {
      const defaults = NotificationPreferences.defaults;

      expect(defaults.appointmentReminders, isTrue);
      expect(defaults.billingAlerts, isTrue);
      expect(defaults.labResults, isTrue);
      expect(defaults.shiftHandoffs, isFalse);
      expect(defaults.productUpdates, isFalse);
    });

    test('copyWith updates only provided fields', () {
      const original = NotificationPreferences.defaults;

      final updated = original.copyWith(shiftHandoffs: true, productUpdates: true);

      expect(updated.appointmentReminders, isTrue);
      expect(updated.billingAlerts, isTrue);
      expect(updated.labResults, isTrue);
      expect(updated.shiftHandoffs, isTrue);
      expect(updated.productUpdates, isTrue);
    });

    test('merge overwrites every field from the other instance', () {
      const base = NotificationPreferences(
        appointmentReminders: true,
        billingAlerts: true,
        labResults: true,
        shiftHandoffs: false,
        productUpdates: false,
      );
      const other = NotificationPreferences(
        appointmentReminders: false,
        billingAlerts: false,
        labResults: false,
        shiftHandoffs: true,
        productUpdates: true,
      );

      expect(base.merge(other), other);
    });

    test('toJson and fromJson round-trip preserves values', () {
      const prefs = NotificationPreferences(
        appointmentReminders: false,
        billingAlerts: true,
        labResults: false,
        shiftHandoffs: true,
        productUpdates: false,
      );

      final restored = NotificationPreferences.fromJson(prefs.toJson());

      expect(restored.appointmentReminders, prefs.appointmentReminders);
      expect(restored.billingAlerts, prefs.billingAlerts);
      expect(restored.labResults, prefs.labResults);
      expect(restored.shiftHandoffs, prefs.shiftHandoffs);
      expect(restored.productUpdates, prefs.productUpdates);
    });

    test('fromJson uses defaults for missing keys', () {
      final restored = NotificationPreferences.fromJson({});

      expect(restored, NotificationPreferences.defaults);
    });

    test('fromJson uses defaults for null bool values', () {
      final restored = NotificationPreferences.fromJson({
        'appointmentReminders': null,
        'billingAlerts': null,
        'labResults': null,
        'shiftHandoffs': null,
        'productUpdates': null,
      });

      expect(restored, NotificationPreferences.defaults);
    });

    test('fromJson ignores unknown keys safely', () {
      final restored = NotificationPreferences.fromJson({
        'appointmentReminders': false,
        'unexpected': true,
      });

      expect(restored.appointmentReminders, isFalse);
      expect(restored.billingAlerts, NotificationPreferences.defaults.billingAlerts);
    });

    test('fromJson throws when bool fields have invalid types', () {
      expect(
        () => NotificationPreferences.fromJson({'appointmentReminders': 'yes'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => NotificationPreferences.fromJson({'billingAlerts': 1}),
        throwsA(isA<TypeError>()),
      );
    });

    test('equality compares all toggle fields', () {
      const a = NotificationPreferences(shiftHandoffs: true);
      const b = NotificationPreferences(shiftHandoffs: true);
      const c = NotificationPreferences(shiftHandoffs: false);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
