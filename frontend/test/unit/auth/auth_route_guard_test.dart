import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthRouteGuard extended', () {
    test('unknown session on protected route redirects to login', () {
      // Cold-start unknown/loading must not render the authenticated shell (review §2.1).
      expect(
        AuthRouteGuard.resolveRedirect(location: AppRoutes.home, auth: AuthSessionState.initial()),
        AppRoutes.login,
      );
    });

    test('unknown session on a public route is left through', () {
      expect(AuthRouteGuard.resolveRedirect(location: AppRoutes.login, auth: AuthSessionState.initial()), isNull);
    });

    test('authenticated setup_required on login redirects to home for setup dialog', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.login,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.home,
      );
    });

    test('authenticated setup_required on home stays for setup dialog', () {
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

    test('authenticated setup_required on bootstrap redirects to home', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.bootstrap,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.home,
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

    test('setup-complete home stays while staff wizard step is active', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.home,
          auth: AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext()),
          bootstrapStaffWizardInProgress: true,
        ),
        isNull,
      );
    });

    test('protected app prefix without setup redirects to setup wizard', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: '${AppRoutes.protectedPrefix}/patients',
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.home,
      );
    });

    test('setup_required staff create redirects to setup wizard', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.staffCreate,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: true),
          ),
        ),
        AppRoutes.home,
      );
    });

    test('setup_complete staff create redirects to clinic management hub (US6)', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.staffCreate,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: false, permissions: {'settings.manage_staff'}),
          ),
        ),
        AppRoutes.clinicManagement,
      );
    });

    test('setup_complete legacy password reset redirects to clinic management hub', () {
      expect(
        AuthRouteGuard.resolveRedirect(
          location: AppRoutes.staffPasswordReset,
          auth: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(setupRequired: false, permissions: {'settings.manage_staff'}),
          ),
        ),
        AppRoutes.clinicManagement,
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
