import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';

import 'settings_widget_test_harness.dart';

void main() {
  group('SettingsPage', () {
    testWidgets('builds at wide width with rail and appearance content', (tester) async {
      await pumpSettingsPage(
        tester,
        surfaceSize: settingsWideSurfaceSize,
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsWidgets);
      expect(find.text('Color theme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('defaults to appearance screen content', (tester) async {
      await pumpSettingsPage(
        tester,
        initialLocation: AppRoutes.settingsAppearance,
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      expect(
        find.text('Set how the app looks and formats dates and times on this workstation.'),
        findsOneWidget,
      );
      expect(find.text('Date format'), findsOneWidget);
      expect(find.text('Idle sign-out duration'), findsNothing);
    });

    testWidgets('navigating via rail switches to notifications and security', (tester) async {
      final router = await pumpSettingsPage(
        tester,
        surfaceSize: settingsWideSurfaceSize,
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      await tester.tap(settingsRailSection('Notifications'));
      await settleSettingsWidget(tester);

      expect(router.routeInformationProvider.value.uri.path, AppRoutes.settingsNotifications);
      expect(find.text('Appointment reminders'), findsOneWidget);
      expect(find.text('Date format'), findsNothing);

      await tester.tap(settingsRailSection('Security'));
      await settleSettingsWidget(tester);

      expect(router.routeInformationProvider.value.uri.path, AppRoutes.settingsSecurity);
      expect(find.text('Idle sign-out duration'), findsOneWidget);
      expect(find.text('Appointment reminders'), findsNothing);
    });

    testWidgets('shows page header with Settings title', (tester) async {
      await pumpSettingsPage(
        tester,
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(
        find.text('Personal preferences for this workstation — theme, alerts, and security.'),
        findsOneWidget,
      );
    });

    testWidgets('builds in narrow layout', (tester) async {
      await pumpSettingsPage(
        tester,
        surfaceSize: settingsNarrowSurfaceSize,
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsWidgets);
      expect(find.text('Color theme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
