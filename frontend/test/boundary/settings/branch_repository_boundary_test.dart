@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';

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

  group('BranchRepositoryImpl', () {
    test('branch.listBranches.allActiveInactive', () async {
      const ManifestScenario('branch.listBranches.allActiveInactive');
      final clinic = await ctx.ensureClinic(label: 'branch_list');
      await ctx.signInAdmin();
      final secondId = await ctx.branches.createBranch(
        CreateBranchInput(
          name: 'Inactive Target ${clinic.suffix}',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          code: 'IN${clinic.suffix.hashCode.abs() % 999}',
        ),
      );
      await ctx.branches.setBranchActive(branchId: secondId, isActive: false);
      final all = await ctx.branches.listBranches(organizationId: clinic.organizationId);
      final active = await ctx.branches.listBranches(
        organizationId: clinic.organizationId,
        filter: BranchListFilter.active,
      );
      final inactive = await ctx.branches.listBranches(
        organizationId: clinic.organizationId,
        filter: BranchListFilter.inactive,
      );
      expect(all.length, greaterThanOrEqualTo(2));
      expect(active.length, greaterThanOrEqualTo(1));
      expect(inactive.any((b) => b.id == secondId), isTrue);
    });

    test('branch.listBranches.activeOnly', () async {
      const ManifestScenario('branch.listBranches.activeOnly');
      final clinic = await ctx.ensureClinic(label: 'branch_active_only');
      await ctx.signInAdmin();
      final rows = await ctx.branches.listBranches(
        organizationId: clinic.organizationId,
        filter: BranchListFilter.active,
      );
      expect(rows.every((b) => b.isActive), isTrue);
    });

    test('branch.listBranches.inactiveOnly', () async {
      const ManifestScenario('branch.listBranches.inactiveOnly');
      final clinic = await ctx.ensureClinic(label: 'branch_inactive_only');
      await ctx.signInAdmin();
      final secondId = await ctx.branches.createBranch(
        CreateBranchInput(
          name: 'To Deactivate ${clinic.suffix}',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          code: 'TD${clinic.suffix.hashCode.abs() % 999}',
        ),
      );
      await ctx.branches.setBranchActive(branchId: secondId, isActive: false);
      final rows = await ctx.branches.listBranches(
        organizationId: clinic.organizationId,
        filter: BranchListFilter.inactive,
      );
      expect(rows.any((b) => b.id == secondId), isTrue);
    });

    test('branch.createBranch.success', () async {
      const ManifestScenario('branch.createBranch.success');
      final clinic = await ctx.ensureClinic(label: 'branch_create');
      await ctx.signInAdmin();
      final id = await ctx.branches.createBranch(
        CreateBranchInput(
          name: 'Secondary ${clinic.suffix}',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          code: 'SEC${clinic.suffix.hashCode.abs() % 9999}',
        ),
      );
      expect(id, isNotEmpty);
    });

    test('branch.updateBranch.success', () async {
      const ManifestScenario('branch.updateBranch.success');
      final clinic = await ctx.ensureClinic(label: 'branch_update');
      await ctx.signInAdmin();
      await ctx.branches.updateBranch(
        UpdateBranchInput(
          branchId: clinic.branchId,
          name: 'Renamed ${clinic.suffix}',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          phone: '+19998887777',
        ),
      );
    });

    test('branch.updateBranch.fullOptional', () async {
      const ManifestScenario('branch.updateBranch.fullOptional');
      final clinic = await ctx.ensureClinic(label: 'branch_full');
      await ctx.signInAdmin();
      await ctx.branches.updateBranch(
        UpdateBranchInput(
          branchId: clinic.branchId,
          name: 'Full Branch ${clinic.suffix}',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          code: clinic.branchCode,
          address: '123 Main St',
          phone: '+15551234567',
          mapsUrl: 'https://maps.example.com/clinic',
        ),
      );
    });

    test('branch.BRANCH_NOT_FOUND', () async {
      const ManifestScenario('branch.BRANCH_NOT_FOUND');
      final clinic = await ctx.ensureClinic(label: 'branch_nf');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.branches.updateBranch(
          UpdateBranchInput(
            branchId: '00000000-0000-4000-8000-000000000099',
            name: 'Ghost Branch',
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          ),
        ),
        'BRANCH_NOT_FOUND',
      );
      clinic;
    });

    test('branch.setBranchActive.deactivateNonLast', () async {
      const ManifestScenario('branch.setBranchActive.deactivateNonLast');
      final clinic = await ctx.ensureClinic(label: 'branch_deactivate');
      await ctx.signInAdmin();
      final secondId = await ctx.branches.createBranch(
        CreateBranchInput(
          name: 'Extra ${clinic.suffix}',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          code: 'X${clinic.suffix.hashCode.abs() % 999}',
        ),
      );
      final result = await ctx.branches.setBranchActive(branchId: secondId, isActive: false);
      expect(result.success, isTrue);
    });

    test('branch.DUPLICATE_CODE', () async {
      const ManifestScenario('branch.DUPLICATE_CODE');
      final clinic = await ctx.ensureClinic(label: 'branch_dup');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.branches.createBranch(
          CreateBranchInput(
            name: 'Dup Branch',
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
            code: clinic.branchCode,
          ),
        ),
        'DUPLICATE_CODE',
      );
    });

    test('branch.INVALID_INPUT.client', () async {
      const ManifestScenario('branch.INVALID_INPUT.client');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.branches.createBranch(CreateBranchInput(name: '  ', workingSchedule: BranchWorkingSchedule.defaultSchedule())),
        'INVALID_INPUT',
      );
    });

    test('branch.LAST_ACTIVE_BRANCH', () async {
      const ManifestScenario('branch.LAST_ACTIVE_BRANCH');
      final clinic = await ctx.ensureClinic(label: 'branch_last');
      await ctx.signInAdmin();
      await expectRpcCode(
        () => ctx.branches.setBranchActive(branchId: clinic.branchId, isActive: false),
        'LAST_ACTIVE_BRANCH',
      );
    });

    test('branch.FORBIDDEN.receptionistCreate', () async {
      const ManifestScenario('branch.FORBIDDEN.receptionistCreate');
      final clinic = await ctx.ensureClinic(label: 'branch_forbidden');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await expectRpcCode(
        () => ctx.branches.createBranch(
          CreateBranchInput(
            name: 'No Auth Branch',
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
            code: 'NA${clinic.suffix}',
          ),
        ),
        'FORBIDDEN',
      );
    });
  });
}
