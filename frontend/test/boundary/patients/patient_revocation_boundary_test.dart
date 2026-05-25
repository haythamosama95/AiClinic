@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';

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

  group('Patient permission revocation', () {
    test('patients.revoke.create.FORBIDDEN', () async {
      const ManifestScenario('patients.revoke.create.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'revoke_create');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.create',
        isGranted: false,
      );
      await ctx.signOut();

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await expectRpcCode(
        () => ctx.patients.createPatient(
          CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'Revoked Create', phone: clinic.phone('70')),
        ),
        'FORBIDDEN',
      );

      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.create',
        isGranted: true,
      );
    });

    test('patients.revoke.view.search.FORBIDDEN', () async {
      const ManifestScenario('patients.revoke.view.search.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'revoke_view');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: false,
      );
      await ctx.signOut();

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);
      await expectRpcCode(
        () => ctx.patients.searchPatients(scope: PatientListScope.thisBranch, branchId: clinic.branchId),
        'FORBIDDEN',
      );

      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: true,
      );
    });

    test('patients.revoke.view.get.FORBIDDEN', () async {
      const ManifestScenario('patients.revoke.view.get.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'revoke_get');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: false,
      );
      await ctx.signOut();

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);
      await expectRpcCode(() => ctx.patients.getPatient(id), 'FORBIDDEN');

      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: true,
      );
    });

    test('patients.revoke.create.afterRevokeRestore', () async {
      const ManifestScenario('patients.revoke.create.afterRevokeRestore');
      final clinic = await ctx.ensureClinic(label: 'revoke_restore');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.create',
        isGranted: false,
      );
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.create',
        isGranted: true,
      );
      await ctx.signOut();
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final id = await ctx.patients.createPatient(
        CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'Restored Create', phone: clinic.phone('71')),
      );
      expect(id, isNotEmpty);
    });

    test('patients.revoke.view.checkDuplicates.FORBIDDEN', () async {
      const ManifestScenario('patients.revoke.view.checkDuplicates.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'revoke_dup');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: false,
      );
      await ctx.signOut();
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);
      await expectRpcCode(() => ctx.patients.checkDuplicates(fullName: 'X', phone: clinic.phone('72')), 'FORBIDDEN');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.labStaff,
        permissionKey: 'patients.view',
        isGranted: true,
      );
    });

    test('patients.revoke.edit.update.FORBIDDEN', () async {
      const ManifestScenario('patients.revoke.edit.update.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'revoke_edit');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('73'));
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.edit',
        isGranted: false,
      );
      await ctx.signOut();
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final detail = await ctx.patients.getPatient(id);
      await expectRpcCode(
        () => ctx.patients.updatePatient(
          UpdatePatientInput(patientId: id, fullName: 'Revoked Edit', expectedUpdatedAt: detail.updatedAt),
        ),
        'FORBIDDEN',
      );
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.edit',
        isGranted: true,
      );
    });

    test('patients.revoke.delete.archive.FORBIDDEN', () async {
      const ManifestScenario('patients.revoke.delete.archive.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'revoke_archive');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('74'));
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.doctor,
        permissionKey: 'patients.delete',
        isGranted: false,
      );
      await ctx.signOut();
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);
      await expectRpcCode(() => ctx.patients.archivePatient(id), 'FORBIDDEN');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.doctor,
        permissionKey: 'patients.delete',
        isGranted: true,
      );
    });
  });
}
