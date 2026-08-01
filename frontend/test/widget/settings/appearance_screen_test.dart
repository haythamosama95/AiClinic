import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/settings/application/format_preferences_notifier.dart';
import 'package:ai_clinic/features/settings/domain/format_preferences.dart';
import 'package:ai_clinic/features/settings/presentation/screens/appearance_screen.dart';

import 'settings_widget_test_harness.dart';

void main() {
  group('AppearanceScreen', () {
    testWidgets('builds successfully with loaded format preferences', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const AppearanceScreen(),
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Color theme'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Date format'), findsOneWidget);
      expect(find.text('Time format'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows color theme, language, date format, and time format rows', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const AppearanceScreen(),
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      expect(find.text('Light'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text(AppDateFormat.dmy.label), findsOneWidget);
      expect(find.text(AppTimeFormat.h12.label), findsOneWidget);
    });

    testWidgets('tapping date format option triggers notifier', (tester) async {
      final notifier = SpyFormatPreferencesNotifier(defaultFormatPreferencesState());

      await pumpSettingsWidget(
        tester,
        child: const AppearanceScreen(),
        overrides: settingsProviderOverrides(formatNotifier: notifier),
      );
      await settleSettingsWidget(tester);

      await tester.tap(settingsSegmentedOption(AppDateFormat.mdy.label));
      await settleSettingsWidget(tester);

      expect(notifier.setDateFormatCallCount, 1);
      expect(notifier.lastDateFormat, AppDateFormat.mdy);
    });

    testWidgets('tapping date format option updates fake store', (tester) async {
      final store = FakeWorkstationPreferencesStore(dateFormat: AppDateFormat.dmy);

      await pumpSettingsWidget(
        tester,
        child: const AppearanceScreen(),
        overrides: settingsProviderOverrides(workstationStore: store),
      );
      await settleSettingsWidget(tester);

      await tester.tap(settingsSegmentedOption(AppDateFormat.mdy.label));
      await settleSettingsWidget(tester);

      expect(store.dateFormat, AppDateFormat.mdy);
    });

    testWidgets('shows loading indicator while format preferences load', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const AppearanceScreen(),
        overrides: settingsProviderOverrides(
          formatPreferencesOverride: formatPreferencesProvider.overrideWith(
            () => LoadingFormatPreferencesNotifier(),
          ),
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Date format'), findsNothing);
    });
  });
}
