@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';

import '../harness/boundary_test_context.dart';
import '../harness/manifest_scenario.dart';
import '../harness/reset.dart';
import '../harness/role_sessions.dart';

void main() {
  late BoundaryTestContext ctx;

  setUpAll(() async {
    ctx = await BoundaryTestContext.create();
  });

  installBoundaryTestLifecycle(() => ctx);

  group('PermissionRepositoryImpl', () {
    for (final role in StaffRole.values) {
      test('permission.loadGrantedPermissions.${role.wireValue}', () async {
        ManifestScenario('permission.loadGrantedPermissions.${role.wireValue}');
        final clinic = await ctx.ensureClinic(label: 'perm_${role.wireValue}');
        final sessions = RoleSessions(ctx, clinic);
        await sessions.signInAs(role);
        final grants = await ctx.permissions.loadGrantedPermissions(role);
        expect(grants, isNotEmpty);
      });
    }

    test('permission.aggressive.revokeShrinksGrants', () async {
      const ManifestScenario('permission.aggressive.revokeShrinksGrants');
      final clinic = await ctx.ensureClinic(label: 'perm_revoke');
      await ctx.signInAdmin();
      final before = await ctx.permissions.loadGrantedPermissions(StaffRole.receptionist);
      expect(before.contains('patients.create'), isTrue);

      await ctx.sql.revokePermission(role: 'receptionist', permissionKey: 'patients.create');
      await ctx.auth.refreshSession();

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final after = await ctx.permissions.loadGrantedPermissions(StaffRole.receptionist);
      expect(after.contains('patients.create'), isFalse);

      await ctx.signInAdmin();
      await ctx.sql.grantPermission(role: 'receptionist', permissionKey: 'patients.create');
    });
  });
}
