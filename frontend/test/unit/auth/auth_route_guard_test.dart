import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthRouteGuard extended', () {
    test('unknown session on protected route does not redirect', () {
      expect(AuthRouteGuard.resolveRedirect(location: AppRoutes.home, auth: AuthSessionState.initial()), isNull);
    });

    test('authenticated setup_required on login redirects to bootstrap', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.login,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.bootstrap,
      );
    });

    test('authenticated setup-complete on bootstrap redirects to home', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.bootstrap,
          auth: AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext()),
        ),
        AppRoutes.home,
      );
    });

    test('protected app prefix without setup redirects to bootstrap', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: '${AppRoutes.protectedPrefix}/patients',
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.bootstrap,
      );
    });

    test('setup_required staff create redirects to bootstrap', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.staffCreate,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.bootstrap,
      );
    });

    test('setup_complete staff create does not redirect away', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.staffCreate,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: false),
          ),
        ),
        isNull,
      );
    });

    test('unauthenticated non-public route redirects to login', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: '/unknown-route',
          auth: const AuthSessionState(status: AuthSessionStatus.unauthenticated),
        ),
        AppRoutes.login,
      );
    });
  });
}
