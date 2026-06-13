import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_auth_app.dart';
import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';

void main() {
  group('AuthRouteGuard.resolveRedirect', () {
    test('unauthenticated home redirects to login', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.home,
          auth: const AuthSessionState(status: AuthSessionStatus.unauthenticated),
        ),
        AppRoutes.login,
      );
    });

    test('authenticated setup complete redirects login to home', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.login,
          auth: AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext()),
        ),
        AppRoutes.home,
      );
    });

    test('authenticated setup required allows home shell without redirect', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.home,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        isNull,
      );
    });

    test('loading session does not redirect', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.home,
          auth: const AuthSessionState(status: AuthSessionStatus.loading),
        ),
        isNull,
      );
    });
  });

  group('router integration', () {
    testWidgets('unauthenticated protected route redirects to login when startup is valid', (tester) async {
      await pumpStartupApp(tester);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.protectedPlaceholder);
      await settleRouterRedirects(tester);

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('REG-008: unauthenticated /patients redirects to login', (tester) async {
      await pumpStartupApp(tester);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.patients);
      await settleRouterRedirects(tester);

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('authenticated setup-complete user reaches home from login', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.login);
      await settleRouterRedirects(tester);

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
      expect(find.text('UI Pending Migration'), findsOneWidget);
      expect(find.text(AppRoutes.home), findsOneWidget);
    });

    testWidgets('authenticated user navigating to login bounces to home', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.login);
      await settleRouterRedirects(tester);

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    });
  });
}
