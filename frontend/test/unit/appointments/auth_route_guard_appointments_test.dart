import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

AuthSessionState _auth({required Set<String> permissions, bool setupRequired = false}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, setupRequired: setupRequired),
  );
}

void main() {
  group('AuthRouteGuard appointments', () {
    test('isAppointmentRoute matches static and schedule paths', () {
      expect(AuthRouteGuard.isAppointmentRoute(AppRoutes.appointments), isTrue);
      expect(AuthRouteGuard.isAppointmentRoute(AppRoutes.appointmentsBook), isTrue);
      expect(AuthRouteGuard.isAppointmentRoute(AppRoutes.appointmentsSchedule('doc-1')), isTrue);
      expect(AuthRouteGuard.isAppointmentRoute(AppRoutes.appointmentsCalendar), isTrue);
      expect(AuthRouteGuard.isAppointmentRoute(AppRoutes.patients), isFalse);
    });

    test('booking routes require appointments.create', () {
      final auth = _auth(permissions: {PermissionKeys.appointmentsCancel});

      expect(AuthRouteGuard.canAccessAppointmentBooking(auth), isFalse);
      expect(AuthRouteGuard.appointmentRouteRedirect(location: AppRoutes.appointmentsBook, auth: auth), AppRoutes.home);
    });

    test('hub routes allow create OR cancel', () {
      final auth = _auth(permissions: {PermissionKeys.appointmentsCancel});

      expect(AuthRouteGuard.canAccessAppointmentHub(auth), isTrue);
      expect(AuthRouteGuard.appointmentRouteRedirect(location: AppRoutes.appointments, auth: auth), isNull);
    });

    test('view routes allow cancel-only grant', () {
      final auth = _auth(permissions: {PermissionKeys.appointmentsCancel});

      expect(AuthRouteGuard.appointmentRouteRedirect(location: AppRoutes.appointmentsQueue, auth: auth), isNull);
      expect(
        AuthRouteGuard.appointmentRouteRedirect(location: AppRoutes.appointmentsSchedule('doc-1'), auth: auth),
        isNull,
      );
    });

    test('booking requires create grant', () {
      final auth = _auth(permissions: {PermissionKeys.appointmentsCancel});

      expect(AuthRouteGuard.appointmentRouteRedirect(location: AppRoutes.appointmentsBook, auth: auth), AppRoutes.home);
    });

    test('setup required redirects to bootstrap', () {
      final auth = _auth(permissions: {PermissionKeys.appointmentsCreate}, setupRequired: true);

      expect(
        AuthRouteGuard.appointmentRouteRedirect(location: AppRoutes.appointmentsQueue, auth: auth),
        AppRoutes.bootstrap,
      );
    });
  });
}
