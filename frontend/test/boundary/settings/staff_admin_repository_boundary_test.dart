@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';

import '../harness/boundary_assertions.dart';
import '../harness/boundary_test_context.dart';
import '../harness/manifest_scenario.dart';
import '../harness/reset.dart';

void main() {
  late BoundaryTestContext ctx;

  setUpAll(() async {
    ctx = await BoundaryTestContext.create();
  });

  installBoundaryTestLifecycle(() => ctx);

  group('StaffAdminRepositoryImpl', () {
    test('staffAdmin.listStaff.filters', () async {
      const ManifestScenario('staffAdmin.listStaff.filters');
      final clinic = await ctx.ensureClinic(label: 'staff_list');
      await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInAdmin();
      for (final filter in StaffListFilter.values) {
        final rows = await ctx.staffAdmin.listStaff(filter: filter);
        expect(rows, isA<List<dynamic>>());
      }
    });

    test('staffAdmin.fetchStaffMember.nested', () async {
      const ManifestScenario('staffAdmin.fetchStaffMember.nested');
      final clinic = await ctx.ensureClinic(label: 'staff_fetch');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInAdmin();
      final detail = await ctx.staffAdmin.fetchStaffMember(staff.staffMemberId);
      expect(detail, isNotNull);
      expect(detail!.branchIds, contains(clinic.branchId));
    });

    test('staffAdmin.updateStaffMember.success', () async {
      const ManifestScenario('staffAdmin.updateStaffMember.success');
      final clinic = await ctx.ensureClinic(label: 'staff_update');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.receptionist);
      await ctx.signInAdmin();
      await ctx.staffAdmin.updateStaffMember(
        UpdateStaffMemberInput(
          staffMemberId: staff.staffMemberId,
          fullName: 'Updated Name',
          role: StaffRole.receptionist,
          branchIds: [clinic.branchId],
        ),
      );
    });

    test('staffAdmin.setStaffActive.success', () async {
      const ManifestScenario('staffAdmin.setStaffActive.success');
      final clinic = await ctx.ensureClinic(label: 'staff_active');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.labStaff);
      await ctx.signInAdmin();
      final deactivate = await ctx.staffAdmin.setStaffActive(staffMemberId: staff.staffMemberId, isActive: false);
      expect(deactivate.success, isTrue);
      final activate = await ctx.staffAdmin.setStaffActive(staffMemberId: staff.staffMemberId, isActive: true);
      expect(activate.success, isTrue);
    });

    test('staffAdmin.INVALID_INPUT.emptyName', () async {
      const ManifestScenario('staffAdmin.INVALID_INPUT.emptyName');
      final clinic = await ctx.ensureClinic(label: 'staff_invalid');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.staffAdmin.updateStaffMember(
          UpdateStaffMemberInput(
            staffMemberId: staff.staffMemberId,
            fullName: '  ',
            role: StaffRole.doctor,
            branchIds: [clinic.branchId],
          ),
        ),
        'INVALID_INPUT',
      );
    });

    test('staffAdmin.INVALID_INPUT.emptyBranches', () async {
      const ManifestScenario('staffAdmin.INVALID_INPUT.emptyBranches');
      final clinic = await ctx.ensureClinic(label: 'staff_empty_br');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.staffAdmin.updateStaffMember(
          UpdateStaffMemberInput(
            staffMemberId: staff.staffMemberId,
            fullName: 'Valid Name',
            role: StaffRole.doctor,
            branchIds: [],
          ),
        ),
        'INVALID_INPUT',
      );
    });

    test('staffAdmin.FORBIDDEN.nonAdministratorCreate', () async {
      const ManifestScenario('staffAdmin.FORBIDDEN.nonAdministratorCreate');
      final clinic = await ctx.ensureClinic(label: 'staff_no_own_create');
      await ctx.signInAdmin();
      await ctx.provisioning.createStaffAccount(
        CreateStaffAccountInput(
          username: clinic.usernameFor(StaffRole.administrator),
          password: 'TestPass1',
          fullName: 'First Administrator',
          role: StaffRole.administrator,
          branchIds: [clinic.branchId],
          primaryBranchId: clinic.branchId,
        ),
      );
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInStaff(doctor.username, doctor.password);
      await expectRpcCode(
        () => ctx.provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: '${clinic.usernameFor(StaffRole.administrator)}2',
            password: 'TestPass1',
            fullName: 'Second Administrator',
            role: StaffRole.administrator,
            branchIds: [clinic.branchId],
          ),
        ),
        'FORBIDDEN',
      );
    });

    test('staffAdmin.STAFF_NOT_FOUND', () async {
      const ManifestScenario('staffAdmin.STAFF_NOT_FOUND');
      final clinic = await ctx.ensureClinic(label: 'staff_nf');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.staffAdmin.setStaffActive(staffMemberId: '00000000-0000-4000-8000-000000000099', isActive: false),
        'STAFF_NOT_FOUND',
      );
      clinic;
    });

    test('staffAdmin.INVALID_BRANCH', () async {
      const ManifestScenario('staffAdmin.INVALID_BRANCH');
      final clinic = await ctx.ensureClinic(label: 'staff_bad_branch');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.receptionist);
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.staffAdmin.updateStaffMember(
          UpdateStaffMemberInput(
            staffMemberId: staff.staffMemberId,
            fullName: 'Cross Branch Staff',
            role: StaffRole.receptionist,
            branchIds: ['00000000-0000-4000-8000-000000000099'],
          ),
        ),
        'INVALID_BRANCH',
      );
    });

    test('staffAdmin.LAST_ADMINISTRATOR', () async {
      const ManifestScenario('staffAdmin.LAST_ADMINISTRATOR');
      final clinic = await ctx.ensureClinic(label: 'staff_last_admin');
      await ctx.signInAdmin();
      final temporaryAdmin = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.administrator);
      await ctx.signInAdmin();
      final deactivateTemporary = await ctx.staffAdmin.setStaffActive(
        staffMemberId: temporaryAdmin.staffMemberId,
        isActive: false,
      );
      expect(deactivateTemporary.success, isTrue);

      final authSession = ctx.client.auth.currentSession;
      expect(authSession, isNotNull);
      final session = await ctx.sessionLoader.load(authSession!);
      final bootstrapAdministratorId = session.staffProfile.staffMemberId;

      await expectRpcCode(
        () => ctx.staffAdmin.updateStaffMember(
          UpdateStaffMemberInput(
            staffMemberId: bootstrapAdministratorId,
            fullName: session.staffProfile.fullName,
            role: StaffRole.doctor,
            branchIds: [clinic.branchId],
          ),
        ),
        'LAST_ADMINISTRATOR',
      );
    });

    test('staffAdmin.aggressive.crossOrgStaff', () async {
      const ManifestScenario('staffAdmin.aggressive.crossOrgStaff');
      final clinicA = await ctx.ensureClinic(label: 'staff_cross_a');
      final clinicB = await ctx.bootstrapSecondaryClinic('staff_cross_b');
      final staffB = await ctx.sql.insertStaffMember(clinic: clinicB, role: 'receptionist');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.staffAdmin.updateStaffMember(
          UpdateStaffMemberInput(
            staffMemberId: staffB.staffMemberId,
            fullName: 'Cross Org Hijack',
            role: StaffRole.receptionist,
            branchIds: [clinicA.branchId],
          ),
        ),
        'CROSS_ORG_DENIED',
      );
    });
  });
}
