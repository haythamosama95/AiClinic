@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';

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

  group('Patient cross-organization isolation', () {
    test('patients.getPatient.crossOrgNOT_FOUND', () async {
      const ManifestScenario('patients.getPatient.crossOrgNOT_FOUND');
      final clinicA = await ctx.ensureClinic(label: 'iso_a_get');
      final patientB = await _patientInOtherOrg(ctx, clinicA, 'iso_b_get');
      final sessions = RoleSessions(ctx, clinicA);
      await sessions.signInAs(StaffRole.owner);
      await expectRpcCode(() => ctx.patients.getPatient(patientB), 'NOT_FOUND');
    });

    test('patients.archivePatient.crossOrgNOT_FOUND', () async {
      const ManifestScenario('patients.archivePatient.crossOrgNOT_FOUND');
      final clinicA = await ctx.ensureClinic(label: 'iso_a_arch');
      final patientB = await _patientInOtherOrg(ctx, clinicA, 'iso_b_arch');
      final sessions = RoleSessions(ctx, clinicA);
      await sessions.signInAs(StaffRole.owner);
      await expectRpcCode(() => ctx.patients.archivePatient(patientB), 'NOT_FOUND');
    });

    test('postgrest.aggressive.crossOrgPatientInvisible', () async {
      const ManifestScenario('postgrest.aggressive.crossOrgPatientInvisible');
      final clinicA = await ctx.ensureClinic(label: 'iso_a_pg');
      final patientB = await _patientInOtherOrg(ctx, clinicA, 'iso_b_pg');
      final sessions = RoleSessions(ctx, clinicA);
      await sessions.signInAs(StaffRole.owner);
      await expectRpcCode(() => ctx.patients.getPatient(patientB), 'NOT_FOUND');
      final page = await ctx.patients.searchPatients(scope: PatientListScope.allBranches);
      expect(page.items.any((p) => p.id == patientB), isFalse);
    });
  });
}

Future<String> _patientInOtherOrg(BoundaryTestContext ctx, Object clinicA, String label) async {
  final clinicB = await ctx.bootstrapSecondaryClinic(label);
  final phoneDigits = clinicB.phone('01').replaceAll(RegExp(r'\D'), '');
  return ctx.sql.insertPatient(clinic: clinicB, fullName: 'Iso Patient $label', phoneDigits: phoneDigits);
}
