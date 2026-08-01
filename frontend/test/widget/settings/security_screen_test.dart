import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/features/settings/presentation/screens/security_screen.dart';

import 'settings_widget_test_harness.dart';

void main() {
  group('SecurityScreen', () {
    testWidgets('builds with idle timeout presets', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SecurityScreen(),
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Idle sign-out duration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows preset buttons for IdleTimeoutConfig.presetMinutes', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SecurityScreen(),
        overrides: settingsProviderOverrides(),
      );
      await settleSettingsWidget(tester);

      for (final preset in IdleTimeoutConfig.presetMinutes) {
        expect(settingsIdlePresetButton(preset), findsOneWidget);
      }
    });

    testWidgets('tapping preset calls selectPresetMinutes', (tester) async {
      final notifier = SpyIdleTimeoutSettingsNotifier(defaultIdleTimeoutSettingsState());

      await pumpSettingsWidget(
        tester,
        child: const SecurityScreen(),
        overrides: settingsProviderOverrides(idleNotifier: notifier),
      );
      await settleSettingsWidget(tester);

      await tester.tap(settingsIdlePresetButton(30));
      await settleSettingsWidget(tester);

      expect(notifier.selectPresetMinutesCallCount, 1);
      expect(notifier.lastPresetMinutes, 30);
    });

    testWidgets('tapping preset persists via fake store when using real notifier', (tester) async {
      final idleStore = FakeIdleTimeoutPreferencesStore();

      await pumpSettingsWidget(
        tester,
        child: const SecurityScreen(),
        overrides: settingsProviderOverrides(idleTimeoutStore: idleStore),
      );
      await settleSettingsWidget(tester);

      await tester.tap(settingsIdlePresetButton(30));
      await settleSettingsWidget(tester);

      expect(idleStore.duration, const Duration(minutes: 30));
    });

    testWidgets('marks the active preset with semantics selected state', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SecurityScreen(),
        overrides: settingsProviderOverrides(
          idleTimeoutStore: FakeIdleTimeoutPreferencesStore(duration: const Duration(minutes: 15)),
        ),
      );
      await settleSettingsWidget(tester);

      final activeSemantics = tester.getSemantics(settingsIdlePresetButton(15));
      final inactiveSemantics = tester.getSemantics(settingsIdlePresetButton(30));

      expect(activeSemantics.flagsCollection.isSelected, Tristate.isTrue);
      expect(inactiveSemantics.flagsCollection.isSelected, Tristate.isFalse);
    });

    testWidgets('shows loading indicator while idle timeout settings load', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SecurityScreen(),
        overrides: settingsProviderOverrides(
          idleTimeoutSettingsOverride: idleTimeoutSettingsProvider.overrideWith(
            () => LoadingIdleTimeoutSettingsNotifier(),
          ),
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Idle sign-out duration'), findsNothing);
    });
  });
}
