import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';

StaffProfile _profile({StaffRole role = StaffRole.administrator, bool isBootstrapAdmin = false}) {
  return StaffProfile(
    staffMemberId: 'staff-1',
    fullName: 'Test User',
    role: role,
    isBootstrapAdmin: isBootstrapAdmin,
    isActive: true,
  );
}

void main() {
  group('ProvisioningRules', () {
    test('doctor cannot provision', () {
      expect(ProvisioningRules.canProvisionStaff(_profile(role: StaffRole.doctor)), isFalse);
    });

    test('administrator can provision', () {
      expect(ProvisioningRules.canProvisionStaff(_profile(role: StaffRole.administrator)), isTrue);
    });

    test('bootstrap admin can provision', () {
      expect(
        ProvisioningRules.canProvisionStaff(_profile(role: StaffRole.administrator, isBootstrapAdmin: true)),
        isTrue,
      );
    });

    test('administrator selectable roles include all operational roles', () {
      final caller = _profile(role: StaffRole.administrator);
      expect(ProvisioningRules.selectableRoles(caller), contains(StaffRole.administrator));
      expect(ProvisioningRules.selectableRoles(caller), contains(StaffRole.doctor));
      expect(ProvisioningRules.validateRoleChoice(caller, StaffRole.administrator), isNull);
    });

    test('bootstrap admin may assign administrator during setup', () {
      final caller = _profile(role: StaffRole.administrator, isBootstrapAdmin: true);
      expect(ProvisioningRules.selectableRoles(caller), contains(StaffRole.administrator));
      expect(ProvisioningRules.validateRoleChoice(caller, StaffRole.administrator), isNull);
    });

    test('doctor cannot reset passwords', () {
      expect(ProvisioningRules.canResetStaffPassword(_profile(role: StaffRole.doctor)), isFalse);
    });

    test('administrator can reset passwords', () {
      expect(ProvisioningRules.canResetStaffPassword(_profile(role: StaffRole.administrator)), isTrue);
    });

    test('receptionist cannot provision or assign administrator', () {
      final caller = _profile(role: StaffRole.receptionist);
      expect(ProvisioningRules.canProvisionStaff(caller), isFalse);
      expect(ProvisioningRules.selectableRoles(caller), isEmpty);
      expect(ProvisioningRules.validateRoleChoice(caller, StaffRole.administrator), isNotNull);
    });
  });
}
