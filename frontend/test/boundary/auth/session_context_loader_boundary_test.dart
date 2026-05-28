@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';

import '../harness/boundary_test_context.dart';
import '../harness/fake_session.dart';
import '../harness/manifest_scenario.dart';
import '../harness/reset.dart';
import '../harness/role_sessions.dart';

void main() {
  late BoundaryTestContext ctx;

  setUpAll(() async {
    ctx = await BoundaryTestContext.create();
  });

  installBoundaryTestLifecycle(() => ctx);

  group('SessionContextLoader', () {
    test('sessionContext.load.afterSignIn', () async {
      const ManifestScenario('sessionContext.load.afterSignIn');
      final clinic = await ctx.ensureClinic(label: 'session_load');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      final session = ctx.auth.currentSession!;
      final context = await ctx.sessionLoader.load(session);
      expect(context.staffProfile.staffMemberId, isNotEmpty);
      expect(context.organizationId, isNotEmpty);
      expect(context.staffProfile.role, StaffRole.owner);
    });

    test('sessionContext.refreshSession.reloadClaims', () async {
      const ManifestScenario('sessionContext.refreshSession.reloadClaims');
      final clinic = await ctx.ensureClinic(label: 'session_refresh');
      await ctx.signInAdmin();
      await ctx.auth.refreshSession();
      final claims = decodeAccessTokenClaims(ctx.auth.currentSession!.accessToken);
      expect(claims['organization_id'], isNotNull);
      clinic;
    });

    test('sessionContext.inactiveStaff', () async {
      const ManifestScenario('sessionContext.inactiveStaff');
      final clinic = await ctx.ensureClinic(label: 'session_inactive');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.sql.deactivateStaff(staff.staffMemberId);
      await ctx.signInStaff(staff.username, staff.password);
      final session = ctx.auth.currentSession!;
      expect(() => ctx.sessionLoader.load(session), throwsA(isA<StateError>()));
      await ctx.signInAdmin();
      await ctx.sql.execute(
        "UPDATE public.staff_members SET is_active = true WHERE id = '${staff.staffMemberId}'::uuid;",
      );
    });

    test('sessionContext.multiBranchPrimary', () async {
      const ManifestScenario('sessionContext.multiBranchPrimary');
      final clinic = await ctx.ensureClinic(label: 'session_multi_branch');
      await ctx.signInAdmin();
      final secondBranchId = await ctx.branches.createBranch(
        CreateBranchInput(
          name: 'Second ${clinic.suffix}',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          code: 'S2${clinic.suffix.hashCode.abs() % 999}',
        ),
      );
      final username = clinic.usernameFor(StaffRole.doctor);
      await ctx.provisioning.createStaffAccount(
        CreateStaffAccountInput(
          username: username,
          password: 'TestPass1',
          fullName: 'Multi Branch Doc',
          role: StaffRole.doctor,
          branchIds: [clinic.branchId, secondBranchId],
          primaryBranchId: secondBranchId,
        ),
      );
      await ctx.signOut();
      await ctx.signInStaff(username, 'TestPass1');
      await ctx.auth.refreshSession();
      final context = await ctx.sessionLoader.load(ctx.auth.currentSession!);
      expect(context.activeBranchId, secondBranchId);
      expect(context.branchIds, containsAll([clinic.branchId, secondBranchId]));
    });

    test('sessionContext.setupRequired', () async {
      const ManifestScenario('sessionContext.setupRequired');
      await ctx.resetInstallation();
      await ctx.signInAdmin();
      final claimsBefore = decodeAccessTokenClaims(ctx.auth.currentSession!.accessToken);
      expect(claimsBefore['setup_required'], isTrue);
      await ctx.ensureClinic(label: 'session_setup');
      await ctx.signInAdmin();
      await ctx.auth.refreshSession();
      final claimsAfter = decodeAccessTokenClaims(ctx.auth.currentSession!.accessToken);
      expect(claimsAfter['setup_required'], isNot(true));
    });

    test('sessionContext.missingStaffMemberIdClaim', () async {
      const ManifestScenario('sessionContext.missingStaffMemberIdClaim');
      final session = sessionWithClaims({
        'sub': '00000000-0000-0000-0000-000000000099',
        'role': 'authenticated',
        'organization_id': '00000000-0000-4000-8000-000000000099',
      });
      expect(() => ctx.sessionLoader.load(session), throwsA(isA<StateError>()));
    });

    test('sessionContext.aggressive.refreshThenLoad', () async {
      const ManifestScenario('sessionContext.aggressive.refreshThenLoad');
      final clinic = await ctx.ensureClinic(label: 'session_refresh_load');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      await ctx.auth.refreshSession();
      final context = await ctx.sessionLoader.load(ctx.auth.currentSession!);
      expect(context.staffProfile.role, StaffRole.owner);
      expect(context.organizationId, isNotEmpty);
    });
  });
}
