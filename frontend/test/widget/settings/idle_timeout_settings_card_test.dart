import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/idle_timeout_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIdleStore extends IdleTimeoutPreferencesStore {
  _FakeIdleStore(this.duration);

  Duration duration;

  @override
  Future<Duration> loadIdleDuration() async => duration;

  @override
  Future<void> saveIdleDuration(Duration duration) async {
    this.duration = duration;
  }
}

void main() {
  group('IdleTimeoutSettingsCard', () {
    Future<void> pumpCard(WidgetTester tester, {Duration initial = const Duration(minutes: 15)}) async {
      final store = _FakeIdleStore(initial);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: IdleTimeoutSettingsCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows preset timeout dropdown', (tester) async {
      await pumpCard(tester);

      expect(find.text('Idle sign-out'), findsOneWidget);
      expect(find.text('Current timeout: 15 minutes'), findsOneWidget);
      expect(find.text('Timeout'), findsOneWidget);
    });

    testWidgets('custom duration from store shows custom input', (tester) async {
      await pumpCard(tester, initial: const Duration(minutes: 42));

      expect(find.text('Current timeout: 42 minutes'), findsOneWidget);
      expect(find.text('Custom duration'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Save'), findsOneWidget);
    });

    testWidgets('preset minutes selectable', (tester) async {
      await pumpCard(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(IdleTimeoutSettingsCard)));
      await container.read(idleTimeoutSettingsProvider.notifier).selectPresetMinutes(30);
      await tester.pumpAndSettle();

      expect(container.read(idleTimeoutSettingsProvider).value!.duration, const Duration(minutes: 30));
      expect(find.text('Current timeout: 30 minutes'), findsOneWidget);
    });
  });
}
