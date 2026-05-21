import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_auth_app.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

void main() {
  group('admin settings router redirects', () {
    testWidgets('doctor deep-linking to branches is redirected to settings hub', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_DoctorSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _DoctorSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsBranches);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settings);
      expect(find.text('Branches'), findsNothing);
    });

    testWidgets('owner can open organization admin route', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_OwnerSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsOrganization);
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.settingsOrganization,
      );
      expect(find.text('Organization'), findsWidgets);
    });

    testWidgets('setup_required user is redirected to bootstrap from staff admin route', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_OwnerSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            setupRequired: true,
            permissions: {'settings.manage_staff', 'settings.manage_branches'},
          ),
        ),
      );
      container.read(appRouterProvider).go(AppRoutes.settingsStaff);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.bootstrap);
    });

    testWidgets('unauthenticated user opening organization admin route goes to login', (tester) async {
      await pumpAuthApp(tester);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsOrganization);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
    });
  });
}

class _DoctorSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: {'patients.view'}),
      ),
    );
  }
}

class _OwnerSessionNotifier extends TestAuthSessionNotifier {
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
