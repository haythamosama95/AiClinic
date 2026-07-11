import 'package:ai_clinic/app/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoutes V1-2 settings administration', () {
    test('static admin paths are unique and under /settings', () {
      final paths = AppRoutes.adminSettingsPaths;
      expect(paths.toSet().length, paths.length, reason: 'duplicate route constant');

      for (final path in paths) {
        expect(path.startsWith(AppRoutes.settings), isTrue);
        expect(path, isNot(AppRoutes.settings));
      }
    });

    test('static paths match spec segment names', () {
      expect(AppRoutes.settingsOrganization, '/settings/organization');
      expect(AppRoutes.settingsBranches, '/settings/branches');
      expect(AppRoutes.settingsBranchesNew, '/settings/branches/new');
      expect(AppRoutes.settingsStaff, '/settings/staff');
      expect(AppRoutes.settingsStaffNew, '/settings/staff/new');
      expect(AppRoutes.settingsPermissions, '/settings/permissions');
    });

    test('branch edit path embeds id without double slashes', () {
      const id = '550e8400-e29b-41d4-a716-446655440000';
      expect(AppRoutes.settingsBranchEdit(id), '/settings/branches/$id/edit');
    });

    test('staff detail and reset-password paths nest under staff base', () {
      const id = 'staff-uuid-1';
      expect(AppRoutes.settingsStaffDetail(id), '/settings/staff/$id');
      expect(AppRoutes.settingsStaffResetPassword(id), '/settings/staff/$id/reset-password');
    });

    test('parameterized builders preserve opaque ids (slashes, spaces, unicode)', () {
      const weirdIds = ['../escape', '  spaced  ', 'branch/inner', 'مركز-١', ''];
      for (final id in weirdIds) {
        expect(AppRoutes.settingsBranchEdit(id), contains(id));
        expect(AppRoutes.settingsStaffDetail(id), contains(id));
        expect(AppRoutes.settingsStaffResetPassword(id), endsWith('/reset-password'));
      }
    });

    test('new branch route is not confused with edit segment', () {
      expect(AppRoutes.settingsBranchesNew, isNot(endsWith('/edit')));
      expect(AppRoutes.settingsBranchesNew.startsWith(AppRoutes.settingsBranches), isTrue);
    });

    test('idle timeout route remains separate from admin hub paths', () {
      expect(AppRoutes.settingsIdleTimeout, '/settings/idle-timeout');
      expect(AppRoutes.adminSettingsPaths, isNot(contains(AppRoutes.settingsIdleTimeout)));
    });

    test('legacy staff provisioning paths differ from settings staff routes', () {
      expect(AppRoutes.staffCreate, isNot(startsWith(AppRoutes.settingsStaff)));
      expect(AppRoutes.staffPasswordReset, isNot(startsWith(AppRoutes.settingsStaff)));
    });
  });
}
