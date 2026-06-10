import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:flutter_test/flutter_test.dart';

StaffProfile _profile({StaffRole role = StaffRole.administrator, bool isBootstrapAdmin = false}) {
  return StaffProfile(
    staffMemberId: 'staff-1',
    fullName: 'Test',
    role: role,
    isBootstrapAdmin: isBootstrapAdmin,
    isActive: true,
  );
}

void main() {
  group('ProvisioningRules', () {
    test('doctor cannot provision staff', () {
      expect(ProvisioningRules.canProvisionStaff(_profile(role: StaffRole.doctor)), isFalse);
    });

    test('owner and administrator can provision', () {
      expect(ProvisioningRules.canProvisionStaff(_profile(role: StaffRole.owner)), isTrue);
      expect(ProvisioningRules.canProvisionStaff(_profile(role: StaffRole.administrator)), isTrue);
    });

    test('bootstrap admin can provision', () {
      expect(
        ProvisioningRules.canProvisionStaff(_profile(role: StaffRole.administrator, isBootstrapAdmin: true)),
        isTrue,
      );
    });

    test('bootstrap admin may assign owner when no owner exists', () {
      final caller = _profile(role: StaffRole.administrator, isBootstrapAdmin: true);
      expect(ProvisioningRules.mayAssignOwnerRole(caller, ownerAlreadyExists: false), isTrue);
      expect(ProvisioningRules.selectableRoles(caller, ownerAlreadyExists: false), contains(StaffRole.owner));
    });

    test('administrator cannot assign owner when owner exists', () {
      final caller = _profile(role: StaffRole.administrator);
      expect(ProvisioningRules.mayAssignOwnerRole(caller, ownerAlreadyExists: true), isFalse);
      expect(ProvisioningRules.validateRoleChoice(caller, StaffRole.owner, ownerAlreadyExists: true), isNotNull);
    });

    test('owner may assign owner when owner exists', () {
      final caller = _profile(role: StaffRole.owner);
      expect(ProvisioningRules.mayAssignOwnerRole(caller, ownerAlreadyExists: true), isTrue);
      expect(ProvisioningRules.validateRoleChoice(caller, StaffRole.owner, ownerAlreadyExists: true), isNull);
    });

    test('bootstrap admin blocked from second owner when owner exists', () {
      final caller = _profile(role: StaffRole.administrator, isBootstrapAdmin: true);
      expect(ProvisioningRules.mayAssignOwnerRole(caller, ownerAlreadyExists: true), isFalse);
    });

    test('inferOwnerAlreadyExists for non-bootstrap administrator', () {
      expect(ProvisioningRules.inferOwnerAlreadyExists(_profile(role: StaffRole.administrator)), isTrue);
    });
  });
}
