import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/clinic_management_tab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

AuthSessionState _auth({
  StaffRole role = StaffRole.administrator,
  Set<String> permissions = const {},
}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(role: role, permissions: permissions),
  );
}

void main() {
  group('clinicManagementTabsFor', () {
    test('shows all tabs for administrator with full permissions', () {
      final tabs = clinicManagementTabsFor(
        _auth(
          permissions: {
            PermissionKeys.manageBranches,
            PermissionKeys.manageStaff,
            PermissionKeys.servicesView,
            PermissionKeys.invoicesView,
          },
        ),
      );

      expect(tabs, ClinicManagementTab.values);
    });

    test('hides admin-only tabs for doctor without permissions', () {
      final tabs = clinicManagementTabsFor(
        _auth(role: StaffRole.doctor, permissions: {PermissionKeys.patientsView}),
      );

      expect(tabs, isEmpty);
    });

    test('shows organization and branches for doctor with branch management permission', () {
      final tabs = clinicManagementTabsFor(
        _auth(
          role: StaffRole.doctor,
          permissions: {PermissionKeys.manageBranches},
        ),
      );

      expect(tabs, [ClinicManagementTab.organization, ClinicManagementTab.branches]);
    });

    test('shows organization tab for administrator even without branch permission', () {
      final tabs = clinicManagementTabsFor(
        _auth(role: StaffRole.administrator, permissions: {PermissionKeys.patientsView}),
      );

      expect(tabs, contains(ClinicManagementTab.organization));
      expect(tabs, contains(ClinicManagementTab.roles));
      expect(tabs, isNot(contains(ClinicManagementTab.branches)));
      expect(tabs, isNot(contains(ClinicManagementTab.staff)));
    });

    test('gates staff tab on manage_staff permission', () {
      final withStaff = clinicManagementTabsFor(
        _auth(permissions: {PermissionKeys.manageStaff}),
      );
      final withoutStaff = clinicManagementTabsFor(
        _auth(permissions: {PermissionKeys.manageBranches}),
      );

      expect(withStaff, contains(ClinicManagementTab.staff));
      expect(withoutStaff, isNot(contains(ClinicManagementTab.staff)));
    });

    test('gates services tab on services permissions', () {
      final viewOnly = clinicManagementTabsFor(
        _auth(permissions: {PermissionKeys.servicesView}),
      );
      final manage = clinicManagementTabsFor(
        _auth(permissions: {PermissionKeys.servicesManage}),
      );
      final none = clinicManagementTabsFor(
        _auth(permissions: {PermissionKeys.patientsView}),
      );

      expect(viewOnly, contains(ClinicManagementTab.services));
      expect(manage, contains(ClinicManagementTab.services));
      expect(none, isNot(contains(ClinicManagementTab.services)));
    });

    test('gates settings tab on billing-related permissions', () {
      final invoices = clinicManagementTabsFor(
        _auth(permissions: {PermissionKeys.invoicesView}),
      );
      final payments = clinicManagementTabsFor(
        _auth(permissions: {PermissionKeys.paymentsRecord}),
      );
      final none = clinicManagementTabsFor(
        _auth(permissions: {PermissionKeys.manageBranches}),
      );

      expect(invoices, contains(ClinicManagementTab.settings));
      expect(payments, contains(ClinicManagementTab.settings));
      expect(none, isNot(contains(ClinicManagementTab.settings)));
    });
  });
}
