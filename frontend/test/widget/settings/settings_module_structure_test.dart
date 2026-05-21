import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/providers/idle_timeout_settings_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Settings module structure (phase 1)', () {
    testWidgets('SettingsPage renders idle timeout entry', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [idleTimeoutSettingsProvider.overrideWith(() => _IdleTimeoutReadyNotifier())],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Idle sign-out'), findsWidgets);
      expect(find.text('Organization'), findsNothing);
    });

    test('admin route constants are defined for settings hub', () {
      expect(AppRoutes.settingsOrganization, isNot(AppRoutes.settings));
      expect(AppRoutes.adminSettingsPaths.length, 6);
    });
  });
}

class _IdleTimeoutReadyNotifier extends IdleTimeoutSettingsNotifier {
  @override
  Future<IdleTimeoutSettingsState> build() async {
    return IdleTimeoutSettingsState(duration: IdleTimeoutConfig.defaultDuration);
  }
}
