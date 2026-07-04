import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/shell_nav.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isShellNavLocation', () {
    test('matches every primary sidebar route', () {
      for (final path in shellNavRoutePaths) {
        expect(isShellNavLocation(path), isTrue, reason: path);
      }
    });

    test('rejects feature sub-routes', () {
      expect(isShellNavLocation(AppRoutes.patientsNew), isFalse);
      expect(isShellNavLocation(AppRoutes.patientDetail('p1')), isFalse);
      expect(isShellNavLocation(AppRoutes.settingsStaffNew), isFalse);
    });

    test('shellRouteForNavId covers all clinic nav ids', () {
      const navIds = [
        'home',
        'dashboard',
        'patients',
        'appointments',
        'encounters',
        'workspace',
        'billing',
        'invoices',
        'services',
        'staff',
        'shifts',
        'reports',
        'settings',
        'dev',
      ];

      for (final id in navIds) {
        final route = shellRouteForNavId(id);
        expect(route, isNotNull, reason: id);
        expect(isShellNavLocation(route!), isTrue, reason: id);
      }
    });
  });
}
