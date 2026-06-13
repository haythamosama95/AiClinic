import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('AuthRouteGuard admin settings', () {
    test('isAdminSettingsRoute matches static and parameterized paths', () {
      expect(AuthRouteGuard.isAdminSettingsRoute(AppRoutes.settingsOrganization), isTrue);
      expect(AuthRouteGuard.isAdminSettingsRoute('/settings/branches/abc/edit'), isTrue);
      expect(AuthRouteGuard.isAdminSettingsRoute('/settings/staff/abc/reset-password'), isTrue);
      expect(AuthRouteGuard.isAdminSettingsRoute(AppRoutes.settingsIdleTimeout), isFalse);
    });

    test('owner can access organization and permission matrix', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.administrator,
          permissions: {'settings.manage_branches', 'settings.manage_staff'},
        ),
      );

      expect(AuthRouteGuard.canAccessOrganizationSettings(auth), isTrue);
      expect(AuthRouteGuard.canAccessPermissionMatrix(auth), isTrue);
      expect(AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsOrganization, auth: auth), isNull);
      expect(AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsPermissions, auth: auth), isNull);
    });

    test('doctor denied admin routes redirects to settings hub', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: {'patients.view'}),
      );

      expect(AuthRouteGuard.canAccessClinicSetup(auth), isFalse);
      expect(
        AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsBranches, auth: auth),
        AppRoutes.settings,
      );
      expect(
        AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsPermissions, auth: auth),
        AppRoutes.settings,
      );
    });

    test('administrator with manage_branches can open branch routes', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'settings.manage_branches'}),
      );

      expect(AuthRouteGuard.canAccessBranchManagement(auth), isTrue);
      expect(AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsBranchesNew, auth: auth), isNull);
    });

    test('setup_required session redirected to bootstrap', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: true),
      );

      expect(AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsStaff, auth: auth), AppRoutes.bootstrap);
    });

    test('stupid usage: unauthenticated admin URL goes to login', () {
      const auth = AuthSessionState(status: AuthSessionStatus.unauthenticated);
      expect(
        AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsOrganization, auth: auth),
        AppRoutes.login,
      );
    });

    test('corner case: doctor with manage_branches can open branch routes but not organization', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.doctor,
          permissions: {'patients.view', 'settings.manage_branches'},
        ),
      );

      expect(AuthRouteGuard.canAccessBranchManagement(auth), isTrue);
      expect(AuthRouteGuard.canAccessOrganizationSettings(auth), isFalse);
      expect(AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsBranches, auth: auth), isNull);
      expect(
        AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsOrganization, auth: auth),
        AppRoutes.settings,
      );
    });

    test('corner case: administrator without manage_branches cannot open branch routes', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'patients.view'}),
      );

      expect(AuthRouteGuard.canAccessBranchManagement(auth), isFalse);
      expect(
        AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsBranches, auth: auth),
        AppRoutes.settings,
      );
    });

    test('corner case: staff without manage_staff cannot open staff routes', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'settings.manage_branches'}),
      );

      expect(AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsStaff, auth: auth), AppRoutes.settings);
    });
  });
}
