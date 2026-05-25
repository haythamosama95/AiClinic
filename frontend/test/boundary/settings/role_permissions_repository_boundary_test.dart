@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';

import '../harness/boundary_assertions.dart';
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

  group('RolePermissionsRepositoryImpl', () {
    test('rolePermissions.fetchMatrix.success', () async {
      const ManifestScenario('rolePermissions.fetchMatrix.success');
      await ctx.ensureClinic(label: 'role_matrix');
      await ctx.signInAdmin();
      final rows = await ctx.rolePermissions.fetchMatrix();
      expect(rows.length, greaterThan(0));
    });

    test('rolePermissions.updateRolePermission.grant', () async {
      const ManifestScenario('rolePermissions.updateRolePermission.grant');
      await ctx.ensureClinic(label: 'role_grant');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.view',
        isGranted: true,
      );
    });

    test('rolePermissions.updateRolePermission.revoke', () async {
      const ManifestScenario('rolePermissions.updateRolePermission.revoke');
      await ctx.ensureClinic(label: 'role_revoke');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: false,
      );
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: true,
      );
    });

    test('rolePermissions.INVALID_PERMISSION', () async {
      const ManifestScenario('rolePermissions.INVALID_PERMISSION');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.rolePermissions.updateRolePermission(
          role: StaffRole.owner,
          permissionKey: 'not.a.real.permission',
          isGranted: true,
        ),
        'INVALID_PERMISSION',
      );
    });

    test('rolePermissions.FORBIDDEN.nonOwner', () async {
      const ManifestScenario('rolePermissions.FORBIDDEN.nonOwner');
      final clinic = await ctx.ensureClinic(label: 'role_forbidden');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await expectRpcCode(
        () => ctx.rolePermissions.updateRolePermission(
          role: StaffRole.receptionist,
          permissionKey: 'patients.view',
          isGranted: false,
        ),
        'FORBIDDEN',
      );
    });

    test('rolePermissions.INVALID_INPUT.emptyKey', () async {
      const ManifestScenario('rolePermissions.INVALID_INPUT.emptyKey');
      await ctx.signInAdmin();
      expect(
        () => ctx.rolePermissions.updateRolePermission(role: StaffRole.owner, permissionKey: '   ', isGranted: true),
        throwsA(isA<StateError>()),
      );
    });
  });
}
