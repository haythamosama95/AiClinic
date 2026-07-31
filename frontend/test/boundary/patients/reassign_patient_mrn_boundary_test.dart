@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';

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

  group('PatientRepositoryImpl.reassignPatientMrn', () {
    test('patients.reassignMrn.success', () async {
      const ManifestScenario('patients.reassignMrn.success');
      final clinic = await ctx.ensureClinic(label: 'reassign_ok');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final created = await ctx.patients.createPatient(
        CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'Reassign Target', phone: clinic.phone('81')),
      );
      const newMrn = 'MRN-999990';

      final assignedMrn = await ctx.patients.reassignPatientMrn(patientId: created.patientId, newMrn: newMrn);

      expect(assignedMrn, newMrn);
      final detail = await ctx.patients.getPatient(created.patientId);
      expect(detail.mrn, newMrn);
    });

    test('patients.reassignMrn.FORBIDDEN', () async {
      const ManifestScenario('patients.reassignMrn.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'reassign_forbidden');
      final patientId = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('82'));
      await ctx.signOut();

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);
      await expectRpcCode(
        () => ctx.patients.reassignPatientMrn(patientId: patientId, newMrn: 'MRN-999991'),
        'FORBIDDEN',
      );
    });

    test('patients.reassignMrn.MRN_EXISTS', () async {
      const ManifestScenario('patients.reassignMrn.MRN_EXISTS');
      final clinic = await ctx.ensureClinic(label: 'reassign_dup');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final first = await ctx.patients.createPatient(
        CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'MRN Owner', phone: clinic.phone('83')),
      );
      final second = await ctx.patients.createPatient(
        CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'MRN Target', phone: clinic.phone('84')),
      );

      await expectRpcCode(
        () => ctx.patients.reassignPatientMrn(patientId: second.patientId, newMrn: first.mrn),
        'MRN_EXISTS',
      );

      final unchanged = await ctx.patients.getPatient(second.patientId);
      expect(unchanged.mrn, second.mrn);
    });
  });
}
