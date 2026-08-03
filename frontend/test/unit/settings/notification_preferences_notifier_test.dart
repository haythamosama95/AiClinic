import 'dart:async';

import 'package:ai_clinic/features/settings/application/notification_preferences_notifier.dart';
import 'package:ai_clinic/features/settings/data/workstation_preferences_store.dart';
import 'package:ai_clinic/features/settings/domain/notification_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWorkstationStore extends WorkstationPreferencesStore {
  _FakeWorkstationStore([NotificationPreferences? preferences])
      : preferences = preferences ?? NotificationPreferences.defaults;

  NotificationPreferences preferences;

  int saveCallCount = 0;

  @override
  Future<NotificationPreferences> loadNotificationPreferences() async => preferences;

  @override
  Future<void> saveNotificationPreferences(NotificationPreferences value) async {
    saveCallCount++;
    preferences = value;
  }
}

ProviderContainer _container(_FakeWorkstationStore store) {
  return ProviderContainer(
    overrides: [
      workstationPreferencesStoreProvider.overrideWithValue(store),
    ],
  );
}

void main() {
  group('NotificationPreferencesNotifier', () {
    test('build loads preferences from the store', () async {
      const prefs = NotificationPreferences(shiftHandoffs: true, productUpdates: true);
      final store = _FakeWorkstationStore(prefs);
      final container = _container(store);
      addTearDown(container.dispose);

      final loaded = await container.read(notificationPreferencesProvider.future);

      expect(loaded, prefs);
    });

    for (final entry in <(NotificationPreferenceKey, NotificationPreferences Function(NotificationPreferences))>[
      (NotificationPreferenceKey.appointmentReminders, (prefs) => prefs.copyWith(appointmentReminders: false)),
      (NotificationPreferenceKey.billingAlerts, (prefs) => prefs.copyWith(billingAlerts: false)),
      (NotificationPreferenceKey.labResults, (prefs) => prefs.copyWith(labResults: false)),
      (NotificationPreferenceKey.shiftHandoffs, (prefs) => prefs.copyWith(shiftHandoffs: true)),
      (NotificationPreferenceKey.productUpdates, (prefs) => prefs.copyWith(productUpdates: true)),
    ]) {
      test('setPreference updates ${entry.$1.name} and persists', () async {
        final store = _FakeWorkstationStore();
        final container = _container(store);
        addTearDown(container.dispose);

        await container.read(notificationPreferencesProvider.future);
        final expected = entry.$2(NotificationPreferences.defaults);

        await container.read(notificationPreferencesProvider.notifier).setPreference(
              entry.$1,
              _valueFor(expected, entry.$1),
            );

        expect(container.read(notificationPreferencesProvider).value, expected);
        expect(store.preferences, expected);
        expect(store.saveCallCount, 1);
      });
    }

    test('setPreference with same value is a no-op', () async {
      final store = _FakeWorkstationStore();
      final container = _container(store);
      addTearDown(container.dispose);

      await container.read(notificationPreferencesProvider.future);
      await container.read(notificationPreferencesProvider.notifier).setPreference(
            NotificationPreferenceKey.appointmentReminders,
            true,
          );

      expect(store.saveCallCount, 0);
    });

    test('setPreference while state is unresolved does nothing', () async {
      final store = _FakeWorkstationStore();
      final container = ProviderContainer(
        overrides: [
          workstationPreferencesStoreProvider.overrideWithValue(store),
          notificationPreferencesProvider.overrideWith(_LoadingNotificationPreferencesNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      await container.read(notificationPreferencesProvider.notifier).setPreference(
            NotificationPreferenceKey.billingAlerts,
            false,
          );

      expect(store.saveCallCount, 0);
      expect(container.read(notificationPreferencesProvider).hasValue, isFalse);
    });
  });
}

class _LoadingNotificationPreferencesNotifier extends NotificationPreferencesNotifier {
  @override
  Future<NotificationPreferences> build() async {
    return Completer<NotificationPreferences>().future;
  }
}

bool _valueFor(NotificationPreferences prefs, NotificationPreferenceKey key) => switch (key) {
      NotificationPreferenceKey.appointmentReminders => prefs.appointmentReminders,
      NotificationPreferenceKey.billingAlerts => prefs.billingAlerts,
      NotificationPreferenceKey.labResults => prefs.labResults,
      NotificationPreferenceKey.shiftHandoffs => prefs.shiftHandoffs,
      NotificationPreferenceKey.productUpdates => prefs.productUpdates,
    };
