import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/settings/data/workstation_preferences_store.dart';
import 'package:ai_clinic/features/settings/domain/notification_preferences.dart';

final notificationPreferencesProvider =
    AsyncNotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
      NotificationPreferencesNotifier.new,
    );

class NotificationPreferencesNotifier extends AsyncNotifier<NotificationPreferences> {
  @override
  Future<NotificationPreferences> build() async {
    return ref.read(workstationPreferencesStoreProvider).loadNotificationPreferences();
  }

  Future<void> setPreference(NotificationPreferenceKey key, bool value) async {
    final current = state.value;
    if (current == null) {
      return;
    }

    final next = switch (key) {
      NotificationPreferenceKey.appointmentReminders => current.copyWith(appointmentReminders: value),
      NotificationPreferenceKey.billingAlerts => current.copyWith(billingAlerts: value),
      NotificationPreferenceKey.labResults => current.copyWith(labResults: value),
      NotificationPreferenceKey.shiftHandoffs => current.copyWith(shiftHandoffs: value),
      NotificationPreferenceKey.productUpdates => current.copyWith(productUpdates: value),
    };

    if (next == current) {
      return;
    }

    state = AsyncData(next);
    await ref.read(workstationPreferencesStoreProvider).saveNotificationPreferences(next);
  }
}
