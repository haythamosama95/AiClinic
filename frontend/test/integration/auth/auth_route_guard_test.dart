import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_auth_app.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

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

    test('authenticated setup required redirects home to bootstrap', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.home,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.bootstrap,
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
      await tester.pumpAndSettle();

      expect(find.text('Sign in with your clinic staff account'), findsOneWidget);
      expect(find.text('Protected route blocked'), findsNothing);
    });

    testWidgets('authenticated setup-complete user reaches home from login', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.login);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
      expect(find.textContaining('Welcome, Test Staff'), findsOneWidget);
    });

    testWidgets('authenticated user navigating to login bounces to home', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.login);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    });
  });
}
