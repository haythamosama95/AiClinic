@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';

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

  group('OrganizationRepositoryImpl', () {
    test('organization.fetchProfile.success', () async {
      const ManifestScenario('organization.fetchProfile.success');
      final clinic = await ctx.ensureClinic(label: 'org_fetch');
      await ctx.signInAdmin();
      final profile = await ctx.organization.fetchProfile(organizationId: clinic.organizationId);
      expect(profile?.name, clinic.organizationName);
    });

    test('organization.fetchProfile.nullUnknown', () async {
      const ManifestScenario('organization.fetchProfile.nullUnknown');
      await ctx.signInAdmin();
      final profile = await ctx.organization.fetchProfile(organizationId: '00000000-0000-4000-8000-000000000099');
      expect(profile, isNull);
    });

    test('organization.updateOrganization.success', () async {
      const ManifestScenario('organization.updateOrganization.success');
      await ctx.ensureClinic(label: 'org_update');
      await ctx.signInAdmin();
      final id = await ctx.organization.updateOrganization(
        const UpdateOrganizationInput(name: 'Updated Org Name', currencyCode: 'EUR', timezone: 'UTC'),
      );
      expect(id, isNotEmpty);
    });

    test('organization.INVALID_INPUT.client', () async {
      const ManifestScenario('organization.INVALID_INPUT.client');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.organization.updateOrganization(const UpdateOrganizationInput(name: '   ')),
        'INVALID_INPUT',
      );
    });

    test('organization.FORBIDDEN.update', () async {
      const ManifestScenario('organization.FORBIDDEN.update');
      final clinic = await ctx.ensureClinic(label: 'org_forbidden');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);
      await expectRpcCode(
        () => ctx.organization.updateOrganization(const UpdateOrganizationInput(name: 'Hacked Org')),
        'FORBIDDEN',
      );
    });
  });
}
