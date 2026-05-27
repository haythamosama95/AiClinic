import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/features/settings/presentation/providers/idle_timeout_settings_notifier.dart';
import '../../support/pump_auth_app.dart';
import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';

void main() {
  group('SettingsPage admin hub', () {
    testWidgets('owner sees all administration tiles', (tester) async {
      await tester.pumpWidget(
        _host(
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              role: StaffRole.owner,
              permissions: {'settings.manage_branches', 'settings.manage_staff'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clinic administration'), findsOneWidget);
      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Branches'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Role permissions'), findsOneWidget);
    });

    testWidgets('doctor does not see administration section', (tester) async {
      await tester.pumpWidget(
        _host(
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: {'patients.view'}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clinic administration'), findsNothing);
      expect(find.text('Organization'), findsNothing);
      expect(find.text('Idle sign-out'), findsOneWidget);
    });

    testWidgets('administrator with only manage_branches sees organization, branches, and role permissions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'settings.manage_branches'}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Branches'), findsOneWidget);
      expect(find.text('Staff'), findsNothing);
      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Role permissions'), findsOneWidget);
    });

    testWidgets('administrator without manage_branches sees organization and permissions only', (tester) async {
      await tester.pumpWidget(
        _host(
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'patients.view'}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Role permissions'), findsOneWidget);
      expect(find.text('Branches'), findsNothing);
      expect(find.text('Staff'), findsNothing);
    });

    testWidgets('doctor with manage_branches permission sees branches but not organization', (tester) async {
      await tester.pumpWidget(
        _host(
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              role: StaffRole.doctor,
              permissions: {'patients.view', 'settings.manage_branches'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Branches'), findsOneWidget);
      expect(find.text('Organization'), findsNothing);
      expect(find.text('Staff'), findsNothing);
    });

    testWidgets('owner tapping organization navigates to organization route', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_OwnerNavNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerNavNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Organization'));
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.settingsOrganization,
      );
    });
  });
}

class _OwnerNavNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.owner,
          permissions: {'settings.manage_branches', 'settings.manage_staff'},
        ),
      ),
    );
  }
}

Widget _host({required AuthSessionState auth}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(auth)),
      idleTimeoutSettingsProvider.overrideWith(_IdleTimeoutReadyNotifier.new),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _IdleTimeoutReadyNotifier extends IdleTimeoutSettingsNotifier {
  @override
  Future<IdleTimeoutSettingsState> build() async {
    return IdleTimeoutSettingsState(duration: IdleTimeoutConfig.defaultDuration);
  }
}
