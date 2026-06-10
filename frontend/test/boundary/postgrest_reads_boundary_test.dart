@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';

import 'harness/boundary_test_context.dart';
import 'harness/manifest_scenario.dart';
import 'harness/reset.dart';
import 'harness/role_sessions.dart';

void main() {
  late BoundaryTestContext ctx;

  setUpAll(() async {
    ctx = await BoundaryTestContext.create();
  });

  installBoundaryTestLifecycle(() => ctx);

  group('PostgREST table reads', () {
    test('postgrest.staff_members.read', () async {
      const ManifestScenario('postgrest.staff_members.read');
      final clinic = await ctx.ensureClinic(label: 'pg_staff');
      await ctx.signInAdmin();
      final rows = await ctx.client.from('staff_members').select('id, full_name').eq('is_deleted', false).limit(5);
      expect(rows, isNotEmpty);
      clinic;
    });

    test('postgrest.branches.read', () async {
      const ManifestScenario('postgrest.branches.read');
      final clinic = await ctx.ensureClinic(label: 'pg_branches');
      await ctx.signInAdmin();
      final rows = await ctx.client
          .from('branches')
          .select('id, name')
          .eq('organization_id', clinic.organizationId)
          .eq('is_deleted', false);
      expect(rows.length, greaterThanOrEqualTo(1));
    });

    test('postgrest.organizations.read', () async {
      const ManifestScenario('postgrest.organizations.read');
      final clinic = await ctx.ensureClinic(label: 'pg_orgs');
      await ctx.signInAdmin();
      final row = await ctx.client
          .from('organizations')
          .select('id, name')
          .eq('id', clinic.organizationId)
          .maybeSingle();
      expect(row, isNotNull);
    });

    test('postgrest.roles_permissions.read', () async {
      const ManifestScenario('postgrest.roles_permissions.read');
      await ctx.ensureClinic(label: 'pg_roles');
      await ctx.signInAdmin();
      final rows = await ctx.client
          .from('roles_permissions')
          .select('permission_key')
          .eq('role', 'administrator')
          .eq('is_granted', true)
          .limit(5);
      expect(rows, isNotEmpty);
    });

    test('postgrest.staff_branch_assignments.read', () async {
      const ManifestScenario('postgrest.staff_branch_assignments.read');
      final clinic = await ctx.ensureClinic(label: 'pg_assign');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInAdmin();
      final rows = await ctx.client
          .from('staff_branch_assignments')
          .select('branch_id, is_primary')
          .eq('staff_member_id', staff.staffMemberId);
      expect(rows, isNotEmpty);
    });

    test('postgrest.aggressive.foreignOrgBranchesEmpty', () async {
      const ManifestScenario('postgrest.aggressive.foreignOrgBranchesEmpty');
      await ctx.ensureClinic(label: 'pg_foreign_org');
      await ctx.signInAdmin();
      final rows = await ctx.client
          .from('branches')
          .select('id')
          .eq('organization_id', '00000000-0000-4000-8000-000000000099');
      expect(rows, isEmpty);
    });

    test('postgrest.staff_members.rlsDenied', () async {
      const ManifestScenario('postgrest.staff_members.rlsDenied');
      await ctx.ensureClinic(label: 'pg_staff_rls_a');
      final clinicB = await ctx.bootstrapSecondaryClinic('pg_staff_rls_b');
      final staffB = await ctx.sql.insertStaffMember(clinic: clinicB);
      await ctx.signInAdmin();
      final row = await ctx.client.from('staff_members').select('id').eq('id', staffB.staffMemberId).maybeSingle();
      expect(row, isNull);
    });

    test('postgrest.branches.rlsDenied', () async {
      const ManifestScenario('postgrest.branches.rlsDenied');
      await ctx.ensureClinic(label: 'pg_branch_rls_a');
      final clinicB = await ctx.bootstrapSecondaryClinic('pg_branch_rls_b');
      await ctx.signInAdmin();
      final rows = await ctx.client.from('branches').select('id').eq('organization_id', clinicB.organizationId);
      expect(rows, isEmpty);
    });

    test('postgrest.organizations.rlsDenied', () async {
      const ManifestScenario('postgrest.organizations.rlsDenied');
      await ctx.ensureClinic(label: 'pg_org_rls_a');
      final clinicB = await ctx.bootstrapSecondaryClinic('pg_org_rls_b');
      await ctx.signInAdmin();
      final row = await ctx.client.from('organizations').select('id').eq('id', clinicB.organizationId).maybeSingle();
      expect(row, isNull);
    });

    test('postgrest.roles_permissions.rlsDenied', () async {
      const ManifestScenario('postgrest.roles_permissions.rlsDenied');
      final clinic = await ctx.ensureClinic(label: 'pg_roles_rls');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: false,
      );
      await ctx.signOut();
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);
      final rows = await ctx.client
          .from('roles_permissions')
          .select('permission_key, is_granted')
          .eq('role', 'lab_staff')
          .eq('permission_key', 'patients.view');
      expect(rows.where((r) => r['is_granted'] == false), isEmpty);
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: true,
      );
    });

    test('postgrest.staffMemberDetail.nestedShape', () async {
      const ManifestScenario('postgrest.staffMemberDetail.nestedShape');
      final clinic = await ctx.ensureClinic(label: 'pg_nested');
      final staff = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      await ctx.signInAdmin();
      final row = await ctx.client
          .from('staff_members')
          .select('id, full_name, role, phone, is_active, staff_branch_assignments(branch_id, is_primary, is_deleted)')
          .eq('id', staff.staffMemberId)
          .maybeSingle();
      final detail = StaffMemberDetail.fromRow(Map<String, dynamic>.from(row!));
      expect(detail, isNotNull);
      expect(detail!.branchIds, contains(clinic.branchId));
    });
  });
}
