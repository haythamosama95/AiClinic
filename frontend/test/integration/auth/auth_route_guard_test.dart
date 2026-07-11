import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

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

    test('postLoginDestination uses setup_required claim', () {
      expect(
        AuthRouteGuard.postLoginDestination(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.home,
      );
      expect(
        AuthRouteGuard.postLoginDestination(
          AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext()),
        ),
        AppRoutes.home,
      );
    });

    test('authenticated setup required keeps home for setup dialog', () {
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
}
