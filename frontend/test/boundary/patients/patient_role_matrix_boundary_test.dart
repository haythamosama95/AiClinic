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

  group('Patient role matrix', () {
    for (final role in StaffRole.values) {
      final labMutationsForbidden = role == StaffRole.labStaff;

      test('patientRole.${role.wireValue}.search', () async {
        ManifestScenario('patientRole.${role.wireValue}.search');
        final clinic = await ctx.ensureClinic(label: 'matrix_${role.wireValue}_search');
        await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('10'));
        final sessions = RoleSessions(ctx, clinic);
        await sessions.signInAs(role);
        final page = await ctx.patients.searchPatients(scope: PatientListScope.thisBranch, branchId: clinic.branchId);
        expect(page.items, isNotEmpty);
      });

      test('patientRole.${role.wireValue}.create', () async {
        ManifestScenario('patientRole.${role.wireValue}.create');
        final clinic = await ctx.ensureClinic(label: 'matrix_${role.wireValue}_create');
        final sessions = RoleSessions(ctx, clinic);
        await sessions.signInAs(role);
        Future<void> run() => ctx.patients.createPatient(
          CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'Matrix Create', phone: clinic.phone('20')),
        );
        if (labMutationsForbidden) {
          await expectRpcCode(run, 'FORBIDDEN');
        } else {
          await run();
        }
      });

      test('patientRole.${role.wireValue}.get', () async {
        ManifestScenario('patientRole.${role.wireValue}.get');
        final clinic = await ctx.ensureClinic(label: 'matrix_${role.wireValue}_get');
        final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('30'));
        final sessions = RoleSessions(ctx, clinic);
        await sessions.signInAs(role);
        await ctx.patients.getPatient(id);
      });

      test('patientRole.${role.wireValue}.update', () async {
        ManifestScenario('patientRole.${role.wireValue}.update');
        final clinic = await ctx.ensureClinic(label: 'matrix_${role.wireValue}_update');
        final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('40'));
        final sessions = RoleSessions(ctx, clinic);
        await sessions.signInAs(role);
        if (labMutationsForbidden) {
          await expectRpcCode(
            () => ctx.patients.updatePatient(
              UpdatePatientInput(patientId: id, fullName: 'Updated Matrix', expectedUpdatedAt: DateTime.now().toUtc()),
            ),
            'FORBIDDEN',
          );
        } else {
          final detail = await ctx.patients.getPatient(id);
          await ctx.patients.updatePatient(
            UpdatePatientInput(patientId: id, fullName: 'Updated Matrix', expectedUpdatedAt: detail.updatedAt),
          );
        }
      });

      test('patientRole.${role.wireValue}.checkDuplicates', () async {
        ManifestScenario('patientRole.${role.wireValue}.checkDuplicates');
        final clinic = await ctx.ensureClinic(label: 'matrix_${role.wireValue}_dup');
        final sessions = RoleSessions(ctx, clinic);
        await sessions.signInAs(role);
        Future<void> run() => ctx.patients.checkDuplicates(fullName: 'X', phone: clinic.phone('50'));
        if (labMutationsForbidden) {
          await expectRpcCode(run, 'FORBIDDEN');
        } else {
          await run();
        }
      });

      test('patientRole.${role.wireValue}.archive', () async {
        ManifestScenario('patientRole.${role.wireValue}.archive');
        final clinic = await ctx.ensureClinic(label: 'matrix_${role.wireValue}_archive');
        final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('60'));
        final sessions = RoleSessions(ctx, clinic);
        await sessions.signInAs(role);
        Future<void> run() => ctx.patients.archivePatient(id);
        if (labMutationsForbidden) {
          await expectRpcCode(run, 'FORBIDDEN');
        } else {
          await run();
        }
      });
    }
  });
}
