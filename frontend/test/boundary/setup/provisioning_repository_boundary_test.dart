@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';

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

  group('ProvisioningRepositoryImpl', () {
    test('provisioning.createStaffAccount.success', () async {
      const ManifestScenario('provisioning.createStaffAccount.success');
      final clinic = await ctx.ensureClinic(label: 'prov_create');
      await ctx.signInAdmin();
      final result = await ctx.provisioning.createStaffAccount(
        CreateStaffAccountInput(
          username: clinic.usernameFor(StaffRole.doctor),
          password: 'TestPass1',
          fullName: 'Dr Boundary',
          role: StaffRole.doctor,
          branchIds: [clinic.branchId],
          primaryBranchId: clinic.branchId,
        ),
      );
      expect(result.staffMemberId, isNotEmpty);
    });

    test('provisioning.resetStaffPassword.success', () async {
      const ManifestScenario('provisioning.resetStaffPassword.success');
      final clinic = await ctx.ensureClinic(label: 'prov_reset_pw');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.receptionist);
      await ctx.signInAdmin();
      final result = await ctx.provisioning.resetStaffPassword(
        staffMemberId: staff.staffMemberId,
        newPassword: 'NewPass2',
      );
      expect(result.staffMemberId, staff.staffMemberId);
    });

    test('provisioning.listOrgStaffMembers', () async {
      const ManifestScenario('provisioning.listOrgStaffMembers');
      final clinic = await ctx.ensureClinic(label: 'prov_list_staff');
      await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInAdmin();
      final rows = await ctx.provisioning.listOrgStaffMembers();
      expect(rows.length, greaterThanOrEqualTo(1));
    });

    test('provisioning.listBranchesByIds.empty', () async {
      const ManifestScenario('provisioning.listBranchesByIds.empty');
      await ctx.signInAdmin();
      final rows = await ctx.provisioning.listBranchesByIds([]);
      expect(rows, isEmpty);
    });

    test('provisioning.listBranchesByIds.validAndMissing', () async {
      const ManifestScenario('provisioning.listBranchesByIds.validAndMissing');
      final clinic = await ctx.ensureClinic(label: 'prov_branches');
      await ctx.signInAdmin();
      final rows = await ctx.provisioning.listBranchesByIds([clinic.branchId, '00000000-0000-4000-8000-000000000099']);
      expect(rows.length, 1);
      expect(rows.first.id, clinic.branchId);
    });

    test('provisioning.ORG_SETUP_INCOMPLETE', () async {
      const ManifestScenario('provisioning.ORG_SETUP_INCOMPLETE');
      await devResetAsBootstrapAdmin(ctx.client);
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          const CreateStaffAccountInput(
            username: 'orphan_staff',
            password: 'TestPass1',
            fullName: 'Orphan',
            role: StaffRole.receptionist,
            branchIds: [],
          ),
        ),
        'ORG_SETUP_INCOMPLETE',
      );
    });

    test('provisioning.USERNAME_EXISTS', () async {
      const ManifestScenario('provisioning.USERNAME_EXISTS');
      final clinic = await ctx.ensureClinic(label: 'prov_dup_user');
      await ctx.signInAdmin();
      final username = clinic.usernameFor(StaffRole.labStaff);
      await ctx.provisioning.createStaffAccount(
        CreateStaffAccountInput(
          username: username,
          password: 'TestPass1',
          fullName: 'Lab One',
          role: StaffRole.labStaff,
          branchIds: [clinic.branchId],
        ),
      );
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: username,
            password: 'TestPass1',
            fullName: 'Lab Two',
            role: StaffRole.labStaff,
            branchIds: [clinic.branchId],
          ),
        ),
        'USERNAME_EXISTS',
      );
    });

    test('provisioning.WEAK_PASSWORD', () async {
      const ManifestScenario('provisioning.WEAK_PASSWORD');
      final clinic = await ctx.ensureClinic(label: 'prov_weak');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: clinic.usernameFor(StaffRole.doctor),
            password: 'short',
            fullName: 'Weak Pass',
            role: StaffRole.doctor,
            branchIds: [clinic.branchId],
          ),
        ),
        'WEAK_PASSWORD',
      );
    });

    test('provisioning.INVALID_BRANCH', () async {
      const ManifestScenario('provisioning.INVALID_BRANCH');
      final clinic = await ctx.ensureClinic(label: 'prov_bad_branch');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: clinic.usernameFor(StaffRole.receptionist),
            password: 'TestPass1',
            fullName: 'Bad Branch',
            role: StaffRole.receptionist,
            branchIds: ['00000000-0000-4000-8000-000000000099'],
          ),
        ),
        'INVALID_BRANCH',
      );
    });

    test('provisioning.FORBIDDEN.nonAdministratorCreate', () async {
      const ManifestScenario('provisioning.FORBIDDEN.nonAdministratorCreate');
      final clinic = await ctx.ensureClinic(label: 'prov_no_owner');
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInStaff(doctor.username, doctor.password);
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: 'own_${clinic.suffix.hashCode.abs().toRadixString(36)}',
            password: 'TestPass1',
            fullName: 'Administrator Attempt',
            role: StaffRole.administrator,
            branchIds: [clinic.branchId],
          ),
        ),
        'FORBIDDEN',
      );
    });

    test('provisioning.resetStaffPassword.STAFF_NOT_FOUND', () async {
      const ManifestScenario('provisioning.resetStaffPassword.STAFF_NOT_FOUND');
      final clinic = await ctx.ensureClinic(label: 'prov_staff_nf');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.resetStaffPassword(
          staffMemberId: '00000000-0000-4000-8000-000000000099',
          newPassword: 'TestPass1',
        ),
        'STAFF_NOT_FOUND',
      );
      clinic;
    });

    for (final role in StaffRole.values) {
      test('provisioning.createStaffAccount.perRole.${role.wireValue}', () async {
        ManifestScenario('provisioning.createStaffAccount.perRole.${role.wireValue}');
        final clinic = await ctx.ensureClinic(label: 'prov_role_${role.wireValue}');
        await ctx.signInAdmin();
        if (role == StaffRole.administrator) {
          final result = await ctx.provisioning.createStaffAccount(
            CreateStaffAccountInput(
              username: clinic.usernameFor(role),
              password: 'TestPass1',
              fullName: 'Administrator ${clinic.suffix}',
              role: role,
              branchIds: [clinic.branchId],
              primaryBranchId: clinic.branchId,
            ),
          );
          expect(result.staffMemberId, isNotEmpty);
        } else {
          await ctx.provisioning.createStaffAccount(
            CreateStaffAccountInput(
              username: clinic.usernameFor(role),
              password: 'TestPass1',
              fullName: 'Staff ${role.wireValue}',
              role: role,
              branchIds: [clinic.branchId],
              primaryBranchId: clinic.branchId,
            ),
          );
        }
      });
    }

    test('provisioning.FORBIDDEN.generic', () async {
      const ManifestScenario('provisioning.FORBIDDEN.generic');
      final clinic = await ctx.ensureClinic(label: 'prov_forbidden');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: clinic.usernameFor(StaffRole.receptionist),
            password: 'TestPass1',
            fullName: 'Doctor Provision',
            role: StaffRole.receptionist,
            branchIds: [clinic.branchId],
          ),
        ),
        'FORBIDDEN',
      );
    });

    test('provisioning.INVALID_INPUT.username', () async {
      const ManifestScenario('provisioning.INVALID_INPUT.username');
      final clinic = await ctx.ensureClinic(label: 'prov_user_invalid');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: '  ',
            password: 'TestPass1',
            fullName: 'Bad User',
            role: StaffRole.receptionist,
            branchIds: [clinic.branchId],
          ),
        ),
        'INVALID_INPUT',
      );
    });

    test('provisioning.INVALID_INPUT.password', () async {
      const ManifestScenario('provisioning.INVALID_INPUT.password');
      final clinic = await ctx.ensureClinic(label: 'prov_pw_invalid');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: clinic.usernameFor(StaffRole.doctor),
            password: '   ',
            fullName: 'Bad Pass',
            role: StaffRole.doctor,
            branchIds: [clinic.branchId],
          ),
        ),
        'INVALID_INPUT',
      );
    });

    test('provisioning.INVALID_INPUT.fullName', () async {
      const ManifestScenario('provisioning.INVALID_INPUT.fullName');
      final clinic = await ctx.ensureClinic(label: 'prov_name_invalid');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: clinic.usernameFor(StaffRole.receptionist),
            password: 'TestPass1',
            fullName: '   ',
            role: StaffRole.receptionist,
            branchIds: [clinic.branchId],
          ),
        ),
        'INVALID_INPUT',
      );
    });

    test('provisioning.INVALID_INPUT.emptyBranches', () async {
      const ManifestScenario('provisioning.INVALID_INPUT.emptyBranches');
      await ctx.ensureClinic(label: 'prov_empty_br');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          const CreateStaffAccountInput(
            username: 'empty_br',
            password: 'TestPass1',
            fullName: 'Empty Branches',
            role: StaffRole.receptionist,
            branchIds: [],
          ),
        ),
        'INVALID_INPUT',
      );
    });

    test('provisioning.resetStaffPassword.FORBIDDEN', () async {
      const ManifestScenario('provisioning.resetStaffPassword.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'prov_reset_forbidden');
      final target = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.receptionist);
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInStaff(doctor.username, doctor.password);
      await expectRpcCode(
        () => ctx.provisioning.resetStaffPassword(staffMemberId: target.staffMemberId, newPassword: 'TestPass2'),
        'FORBIDDEN',
      );
    });

    test('provisioning.resetStaffPassword.INVALID_INPUT', () async {
      const ManifestScenario('provisioning.resetStaffPassword.INVALID_INPUT');
      final clinic = await ctx.ensureClinic(label: 'prov_reset_invalid');
      final target = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.receptionist);
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.resetStaffPassword(staffMemberId: target.staffMemberId, newPassword: '   '),
        'INVALID_INPUT',
      );
    });

    test('provisioning.aggressive.emptyBranchListServer', () async {
      const ManifestScenario('provisioning.aggressive.emptyBranchListServer');
      await ctx.ensureClinic(label: 'prov_empty_br_srv');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          const CreateStaffAccountInput(
            username: 'empty_br_srv',
            password: 'TestPass1',
            fullName: 'Empty Br Server',
            role: StaffRole.receptionist,
            branchIds: [],
          ),
        ),
        'INVALID_INPUT',
      );
    });

    test('provisioning.aggressive.primaryBranchNullVsSet', () async {
      const ManifestScenario('provisioning.aggressive.primaryBranchNullVsSet');
      final clinic = await ctx.ensureClinic(label: 'prov_primary');
      await ctx.signInAdmin();
      final withoutPrimary = await ctx.provisioning.createStaffAccount(
        CreateStaffAccountInput(
          username: '${clinic.usernameFor(StaffRole.doctor)}a',
          password: 'TestPass1',
          fullName: 'No Primary',
          role: StaffRole.doctor,
          branchIds: [clinic.branchId],
        ),
      );
      expect(withoutPrimary.staffMemberId, isNotEmpty);
      final withPrimary = await ctx.provisioning.createStaffAccount(
        CreateStaffAccountInput(
          username: '${clinic.usernameFor(StaffRole.receptionist)}b',
          password: 'TestPass1',
          fullName: 'With Primary',
          role: StaffRole.receptionist,
          branchIds: [clinic.branchId],
          primaryBranchId: clinic.branchId,
        ),
      );
      expect(withPrimary.staffMemberId, isNotEmpty);
    });
  });
}
