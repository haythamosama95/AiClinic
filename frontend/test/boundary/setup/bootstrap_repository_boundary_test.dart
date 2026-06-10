@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';

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

  group('BootstrapRepositoryImpl', () {
    test('bootstrap.createOrganization.createBranch.success', () async {
      const ManifestScenario('bootstrap.createOrganization.createBranch.success');
      final clinic = await ctx.fixtures.resetAndBootstrap(label: 'boot_ok');
      expect(clinic.organizationId, isNotEmpty);
      expect(clinic.branchId, isNotEmpty);
    });

    test('bootstrap.resetInstallation.success', () async {
      const ManifestScenario('bootstrap.resetInstallation.success');
      await ctx.signInAdmin();
      final result = await ctx.bootstrap.resetInstallationForDevelopment();
      expect(result.success, isTrue);
    });

    test('bootstrap.INVALID_INPUT.emptyOrgName', () async {
      const ManifestScenario('bootstrap.INVALID_INPUT.emptyOrgName');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.bootstrap.createOrganization(const BootstrapOrganizationInput(name: '   ')),
        'INVALID_INPUT',
      );
    });

    test('bootstrap.ORG_ALREADY_EXISTS', () async {
      const ManifestScenario('bootstrap.ORG_ALREADY_EXISTS');
      final clinic = await ctx.fixtures.resetAndBootstrap(label: 'boot_dup_org');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.bootstrap.createOrganization(BootstrapOrganizationInput(name: clinic.organizationName)),
        'ORG_ALREADY_EXISTS',
      );
    });

    test('bootstrap.ORG_NOT_FOUND.branchBeforeOrg', () async {
      const ManifestScenario('bootstrap.ORG_NOT_FOUND.branchBeforeOrg');
      await devResetAsBootstrapAdmin(ctx.client);
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.bootstrap.createBranch(
          const BootstrapBranchInput(organizationId: '00000000-0000-4000-8000-000000000099', name: 'Ghost Branch'),
        ),
        'ORG_NOT_FOUND',
      );
    });

    test('bootstrap.NOT_BOOTSTRAP_ADMIN.resetDenied', () async {
      const ManifestScenario('bootstrap.NOT_BOOTSTRAP_ADMIN.resetDenied');
      final clinic = await ctx.fixtures.resetAndBootstrap(label: 'boot_reset_denied');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await expectRpcCode(() => ctx.bootstrap.resetInstallationForDevelopment(), 'NOT_BOOTSTRAP_ADMIN');
    });

    test('bootstrap.FORBIDDEN.resetProduction', () async {
      const ManifestScenario('bootstrap.FORBIDDEN.resetProduction');
      await ctx.sql.expectDevResetForbiddenInProduction();
    });
  });
}
