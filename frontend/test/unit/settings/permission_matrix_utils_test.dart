import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/permission_matrix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('createDefaultRoleGrants', () {
    test('returns independent mutable copies per role', () {
      final grants = createDefaultRoleGrants();

      expect(grants[StaffRole.administrator], contains('settings.manage_staff'));
      expect(grants[StaffRole.doctor], contains('patients.view'));
      expect(grants[StaffRole.receptionist], contains('invoices.view'));
      expect(grants[StaffRole.labStaff], contains('visits.upload_attachment'));

      grants[StaffRole.doctor]!.add('analytics.view');
      expect(createDefaultRoleGrants()[StaffRole.doctor], isNot(contains('analytics.view')));
    });
  });

  group('cloneRoleGrants', () {
    test('deep-copies grant sets', () {
      final original = createDefaultRoleGrants();
      final clone = cloneRoleGrants(original);

      original[StaffRole.administrator]!.remove('ai.access');

      expect(clone[StaffRole.administrator], contains('ai.access'));
    });
  });

  group('roleGrantsEqual', () {
    test('compares grants for every role', () {
      final left = createDefaultRoleGrants();
      final right = cloneRoleGrants(left);

      expect(roleGrantsEqual(left, right), isTrue);

      right[StaffRole.receptionist]!.add('analytics.view');
      expect(roleGrantsEqual(left, right), isFalse);
    });

    test('treats missing role entries as empty sets', () {
      final left = <StaffRole, Set<String>>{StaffRole.doctor: {'patients.view'}};
      final right = <StaffRole, Set<String>>{};

      expect(roleGrantsEqual(left, right), isFalse);
    });
  });

  group('isPermissionGrantedInMap', () {
    test('returns grant state for role and key', () {
      final grants = createDefaultRoleGrants();

      expect(isPermissionGrantedInMap(grants, StaffRole.doctor, 'patients.view'), isTrue);
      expect(isPermissionGrantedInMap(grants, StaffRole.doctor, 'settings.manage_staff'), isFalse);
      expect(isPermissionGrantedInMap({}, StaffRole.doctor, 'patients.view'), isFalse);
    });
  });

  group('canTogglePermissionGrant', () {
    test('blocks billing manage grant for non-administrator roles', () {
      expect(
        canTogglePermissionGrant(
          role: StaffRole.doctor,
          permissionKey: 'settings.billing.manage',
          nextGranted: true,
        ),
        isFalse,
      );
      expect(
        canTogglePermissionGrant(
          role: StaffRole.administrator,
          permissionKey: 'settings.billing.manage',
          nextGranted: true,
        ),
        isTrue,
      );
    });

    test('allows revoking or toggling other permissions', () {
      expect(
        canTogglePermissionGrant(
          role: StaffRole.doctor,
          permissionKey: 'settings.billing.manage',
          nextGranted: false,
        ),
        isTrue,
      );
      expect(
        canTogglePermissionGrant(
          role: StaffRole.receptionist,
          permissionKey: 'patients.view',
          nextGranted: true,
        ),
        isTrue,
      );
    });
  });

  group('permissionCategoryGroups', () {
    test('groups catalog permissions by category in sorted order', () {
      final groups = permissionCategoryGroups();

      expect(groups, isNotEmpty);
      expect(groups.first.category.compareTo(groups.last.category), lessThanOrEqualTo(0));

      final patients = groups.firstWhere((group) => group.category == 'patients');
      expect(patients.permissionKeys, containsAll(['patients.view', 'patients.create']));
      expect(patients.permissionKeys, equals([...patients.permissionKeys]..sort()));
    });

    test('includes every known permission key exactly once', () {
      final groupedKeys = permissionCategoryGroups().expand((group) => group.permissionKeys).toList();

      expect(groupedKeys, containsAll(kPermissionKeys));
      expect(groupedKeys.length, kPermissionKeys.length);
    });
  });
}
