@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
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

  group('PatientRepositoryImpl', () {
    test('patients.searchPatients.branchName', () async {
      const ManifestScenario('patients.searchPatients.branchName');
      final clinic = await ctx.ensureClinic(label: 'pat_search_name');
      final patientId = await ctx.fixtures.createPatientAsAdmin(
        clinic: clinic,
        fullName: 'Searchable Alpha',
        phone: clinic.phone('11'),
      );
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final page = await ctx.patients.searchPatients(
        query: 'Searchable',
        scope: PatientListScope.thisBranch,
        branchId: clinic.branchId,
      );
      expect(page.items.any((p) => p.id == patientId), isTrue);
    });

    test('patients.searchPatients.orgScope', () async {
      const ManifestScenario('patients.searchPatients.orgScope');
      final clinic = await ctx.ensureClinic(label: 'pat_search_org');
      await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('12'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);
      final page = await ctx.patients.searchPatients(scope: PatientListScope.allBranches);
      expect(page.items, isNotEmpty);
    });

    test('patients.searchPatients.emptyBrowse', () async {
      const ManifestScenario('patients.searchPatients.emptyBrowse');
      final clinic = await ctx.ensureClinic(label: 'pat_search_empty');
      await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);
      final page = await ctx.patients.searchPatients(scope: PatientListScope.thisBranch, branchId: clinic.branchId);
      expect(page.items, isNotEmpty);
    });

    test('patients.searchPatients.pagination', () async {
      const ManifestScenario('patients.searchPatients.pagination');
      final clinic = await ctx.ensureClinic(label: 'pat_page');
      for (var i = 0; i < 3; i++) {
        await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('2$i'));
      }
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      final page1 = await ctx.patients.searchPatients(
        scope: PatientListScope.thisBranch,
        branchId: clinic.branchId,
        limit: 2,
        offset: 0,
      );
      final page2 = await ctx.patients.searchPatients(
        scope: PatientListScope.thisBranch,
        branchId: clinic.branchId,
        limit: 2,
        offset: 2,
      );
      expect(page1.items.length, lessThanOrEqualTo(2));
      expect(page2.items.length, greaterThanOrEqualTo(1));
    });

    test('patients.searchPatients.BRANCH_REQUIRED', () async {
      const ManifestScenario('patients.searchPatients.BRANCH_REQUIRED');
      final clinic = await ctx.ensureClinic(label: 'pat_branch_req');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final raw = await ctx.client.rpc('search_patients', params: {'p_scope': 'branch', 'p_limit': 25, 'p_offset': 0});
      final result = RpcResult.fromDynamic(raw);
      expect(result.success, isFalse);
      expect(result.errorCode, 'BRANCH_REQUIRED');
    });

    test('patients.getPatient.success', () async {
      const ManifestScenario('patients.getPatient.success');
      final clinic = await ctx.ensureClinic(label: 'pat_get');
      final id = await ctx.fixtures.createPatientFullDemographics(clinic: clinic);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);
      final detail = await ctx.patients.getPatient(id);
      expect(detail.fullName, contains('Full Demo'));
    });

    test('patients.getPatient.NOT_FOUND', () async {
      const ManifestScenario('patients.getPatient.NOT_FOUND');
      final clinic = await ctx.ensureClinic(label: 'pat_not_found');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      await expectRpcCode(() => ctx.patients.getPatient('00000000-0000-4000-8000-000000000099'), 'NOT_FOUND');
    });

    test('patients.getPatient.PATIENT_ARCHIVED', () async {
      const ManifestScenario('patients.getPatient.PATIENT_ARCHIVED');
      final clinic = await ctx.ensureClinic(label: 'pat_archived_get');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('93'));
      final ownerSessions = RoleSessions(ctx, clinic);
      await ownerSessions.signInAs(StaffRole.owner);
      await ctx.patients.archivePatient(id);
      await ctx.signOut();

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);
      await expectRpcCode(() => ctx.patients.getPatient(id), 'PATIENT_ARCHIVED');
    });

    test('patients.getPatient.INVALID_INPUT.client', () async {
      const ManifestScenario('patients.getPatient.INVALID_INPUT.client');
      final clinic = await ctx.ensureClinic(label: 'pat_get_invalid');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      await expectRpcCode(() => ctx.patients.getPatient('  '), 'INVALID_INPUT');
      clinic;
    });

    test('patients.checkDuplicates.success', () async {
      const ManifestScenario('patients.checkDuplicates.success');
      final clinic = await ctx.ensureClinic(label: 'pat_dup_check');
      await ctx.fixtures.createPatientAsAdmin(clinic: clinic, fullName: 'Dup Target', phone: clinic.phone('31'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final candidates = await ctx.patients.checkDuplicates(fullName: 'Dup Target', phone: clinic.phone('31'));
      expect(candidates, isNotEmpty);
    });

    test('patients.createPatient.minimal', () async {
      const ManifestScenario('patients.createPatient.minimal');
      final clinic = await ctx.ensureClinic(label: 'pat_create_min');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final id = await ctx.patients.createPatient(
        CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'New Patient', phone: clinic.phone('41')),
      );
      expect(id, isNotEmpty);
    });

    test('patients.createPatient.DUPLICATE_WARNING', () async {
      const ManifestScenario('patients.createPatient.DUPLICATE_WARNING');
      final clinic = await ctx.ensureClinic(label: 'pat_dup_warn');
      await ctx.fixtures.createPatientAsAdmin(clinic: clinic, fullName: 'Dup Warn', phone: clinic.phone('51'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      try {
        await ctx.patients.createPatient(
          CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'Dup Warn', phone: clinic.phone('51')),
        );
        fail('expected DUPLICATE_WARNING');
      } on RpcFailure catch (e) {
        expect(e.code, 'DUPLICATE_WARNING');
        expect(PatientRepositoryImpl.parseDuplicateCandidates(e.result.data?['candidates']), isNotEmpty);
      }
    });

    test('patients.createPatient.acknowledgeDuplicate', () async {
      const ManifestScenario('patients.createPatient.acknowledgeDuplicate');
      final clinic = await ctx.ensureClinic(label: 'pat_ack_dup');
      await ctx.signInAdmin();
      await ctx.patients.createPatient(
        CreatePatientInput(
          activeBranchId: clinic.branchId,
          fullName: 'Ack Dup',
          phone: clinic.phone('61'),
          dateOfBirth: DateTime(1990, 5, 15),
        ),
      );
      await ctx.signOut();
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final id = await ctx.patients.createPatient(
        CreatePatientInput(
          activeBranchId: clinic.branchId,
          fullName: 'Ack Dup',
          phone: clinic.phone('62'),
          dateOfBirth: DateTime(1990, 5, 15),
          acknowledgeDuplicate: true,
        ),
      );
      expect(id, isNotEmpty);
    });

    test('patients.updatePatient.STALE_PATIENT', () async {
      const ManifestScenario('patients.updatePatient.STALE_PATIENT');
      final clinic = await ctx.ensureClinic(label: 'pat_stale');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('81'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      final detail = await ctx.patients.getPatient(id);
      await expectRpcCode(
        () => ctx.patients.updatePatient(
          UpdatePatientInput(
            patientId: id,
            fullName: 'Stale Name',
            expectedUpdatedAt: detail.updatedAt.subtract(const Duration(hours: 1)),
          ),
        ),
        'STALE_PATIENT',
      );
    });

    test('patients.archivePatient.success', () async {
      const ManifestScenario('patients.archivePatient.success');
      final clinic = await ctx.ensureClinic(label: 'pat_archive');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('91'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      await ctx.patients.archivePatient(id);
    });

    test('patients.aggressive.concurrentDuplicatePhone', () async {
      const ManifestScenario('patients.aggressive.concurrentDuplicatePhone');
      final clinic = await ctx.ensureClinic(label: 'pat_concurrent');
      final phone = clinic.phone('92');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await ctx.patients.createPatient(
        CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'Concurrent A', phone: phone),
      );
      await expectRpcCode(
        () => ctx.patients.createPatient(
          CreatePatientInput(
            activeBranchId: clinic.branchId,
            fullName: 'Concurrent B',
            phone: phone,
            acknowledgeDuplicate: true,
          ),
        ),
        'DUPLICATE_PHONE',
      );
    });
  });
}
