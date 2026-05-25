import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthRouteGuard patient routes', () {
    test('isPatientRoute matches list, register, detail, and edit paths', () {
      expect(AuthRouteGuard.isPatientRoute(AppRoutes.patients), isTrue);
      expect(AuthRouteGuard.isPatientRoute(AppRoutes.patientsNew), isTrue);
      expect(AuthRouteGuard.isPatientRoute(AppRoutes.patientDetail('abc')), isTrue);
      expect(AuthRouteGuard.isPatientRoute(AppRoutes.patientEdit('abc')), isTrue);
      expect(AuthRouteGuard.isPatientRoute(AppRoutes.home), isFalse);
    });

    test('authenticated staff may open patient routes; pages enforce permissions', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
      );

      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patients, auth: auth), isNull);
      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patientDetail('id'), auth: auth), isNull);
      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patientsNew, auth: auth), isNull);
      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patientEdit('id'), auth: auth), isNull);
    });

    test('staff without patient grants are not redirected away from patient routes', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: const {PermissionKeys.aiAccess}),
      );

      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patients, auth: auth), isNull);
      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patientsNew, auth: auth), isNull);
    });

    test('stupid usage: unauthenticated user sent to login', () {
      const auth = AuthSessionState(status: AuthSessionStatus.unauthenticated);

      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patients, auth: auth), AppRoutes.login);
    });

    test('setup_required user sent to bootstrap', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: true, permissions: RolePermissionSeed.owner),
      );

      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patients, auth: auth), AppRoutes.bootstrap);
    });

    test('owner with full patient grants can access all patient routes', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          permissions: {
            PermissionKeys.patientsView,
            PermissionKeys.patientsCreate,
            PermissionKeys.patientsEdit,
            PermissionKeys.patientsDelete,
          },
        ),
      );

      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patientsNew, auth: auth), isNull);
      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patientEdit('id'), auth: auth), isNull);
    });
  });
}
