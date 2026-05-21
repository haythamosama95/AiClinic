import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1 setup: routes + domain stubs wire together for later repositories/UI.
void main() {
  group('Settings phase 1 integration', () {
    test('admin route builders produce paths parseable as GoRouter segments', () {
      const branchId = 'b1';
      const staffId = 's1';

      final paths = [
        AppRoutes.settingsOrganization,
        AppRoutes.settingsBranches,
        AppRoutes.settingsBranchesNew,
        AppRoutes.settingsBranchEdit(branchId),
        AppRoutes.settingsStaff,
        AppRoutes.settingsStaffNew,
        AppRoutes.settingsStaffDetail(staffId),
        AppRoutes.settingsStaffResetPassword(staffId),
        AppRoutes.settingsPermissions,
      ];

      for (final path in paths) {
        expect(path.startsWith('/'), isTrue);
        expect(path.contains('//'), isFalse);
        expect(path.split('/').where((s) => s.isEmpty).length, lessThanOrEqualTo(1));
      }
    });

    test('domain models deserialize PostgREST-shaped payloads consistently', () {
      final org = OrganizationProfile.fromRow({'id': 'org', 'name': 'Clinic'});
      final branch = BranchListItem.fromRow({'id': 'b', 'name': 'Main', 'is_active': true});
      final staff = StaffListItem.fromRow({'id': 's', 'full_name': 'User', 'role': 'owner', 'is_active': true});
      final perm = PermissionMatrixRow.fromRow({
        'role': 'owner',
        'permission_key': 'settings.manage_staff',
        'is_granted': true,
      });

      expect(org, isNotNull);
      expect(branch, isNotNull);
      expect(staff, isNotNull);
      expect(perm, isNotNull);
    });

    test('deactivated branch and staff rows remain parseable for inactive filters', () {
      final branch = BranchListItem.fromRow({'id': 'b', 'name': 'Closed', 'is_active': false});
      final staff = StaffListItem.fromRow({
        'id': 's',
        'full_name': 'Inactive',
        'role': 'receptionist',
        'is_active': false,
        'branch_names': [],
      });

      expect(branch!.isActive, isFalse);
      expect(staff!.isActive, isFalse);
    });
  });
}
