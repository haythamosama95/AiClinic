import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_switch.dart';
import 'package:ai_clinic/features/settings/application/notification_preferences_notifier.dart';
import 'package:ai_clinic/features/settings/domain/notification_preferences.dart';
import 'package:ai_clinic/features/settings/presentation/screens/notifications_screen.dart';

import 'settings_widget_test_harness.dart';

void main() {
  const notificationItems = <String>[
    'Appointment reminders',
    'Billing alerts',
    'Lab results',
    'Shift handoffs',
    'Product updates',
  ];

  group('NotificationsScreen', () {
    testWidgets('builds with notification toggles', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const NotificationsScreen(),
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.byType(AppSwitch), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows all five notification items', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const NotificationsScreen(),
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      for (final title in notificationItems) {
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('toggling a switch calls setPreference', (tester) async {
      final notifier = SpyNotificationPreferencesNotifier(NotificationPreferences.defaults);

      await pumpSettingsWidget(
        tester,
        child: const NotificationsScreen(),
        overrides: settingsProviderOverrides(notificationNotifier: notifier),
      );
      await settleSettingsWidget(tester);

      await tester.tap(find.byType(AppSwitch).first);
      await settleSettingsWidget(tester);

      expect(notifier.setPreferenceCallCount, 1);
      expect(notifier.lastKey, NotificationPreferenceKey.appointmentReminders);
      expect(notifier.lastValue, isFalse);
    });

    testWidgets('toggling a switch persists via fake store when using real notifier', (tester) async {
      final store = FakeWorkstationPreferencesStore();

      await pumpSettingsWidget(
        tester,
        child: const NotificationsScreen(),
        overrides: settingsProviderOverrides(workstationStore: store),
      );
      await settleSettingsWidget(tester);

      await tester.tap(find.byType(AppSwitch).at(3));
      await settleSettingsWidget(tester);

      expect(store.notificationPreferences.shiftHandoffs, isTrue);
    });

    testWidgets('shows loading indicator while notification preferences load', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const NotificationsScreen(),
        overrides: settingsProviderOverrides(
          notificationPreferencesOverride: notificationPreferencesProvider.overrideWith(
            () => LoadingNotificationPreferencesNotifier(),
          ),
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Appointment reminders'), findsNothing);
    });
  });
}
