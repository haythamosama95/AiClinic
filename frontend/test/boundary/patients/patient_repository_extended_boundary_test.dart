@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
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

  group('PatientRepositoryImpl extended', () {
    test('patients.searchPatients.branchPhone', () async {
      const ManifestScenario('patients.searchPatients.branchPhone');
      final clinic = await ctx.ensureClinic(label: 'pat_phone_search');
      final phone = clinic.phone('77');
      await ctx.fixtures.createPatientAsAdmin(clinic: clinic, fullName: 'Phone Search Target', phone: phone);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
      final page = await ctx.patients.searchPatients(
        query: phoneDigits.substring(0, phoneDigits.length - 2),
        scope: PatientListScope.thisBranch,
        branchId: clinic.branchId,
      );
      expect(page.items.any((p) => (p.phone ?? '').replaceAll(RegExp(r'\D'), '').contains(phoneDigits)), isTrue);
    });

    test('patients.searchPatients.INVALID_INPUT', () async {
      const ManifestScenario('patients.searchPatients.INVALID_INPUT');
      final clinic = await ctx.ensureClinic(label: 'pat_search_invalid');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      final raw = await ctx.client.rpc(
        'search_patients',
        params: {'p_scope': 'organization', 'p_limit': 25, 'p_offset': -1},
      );
      final result = RpcResult.fromDynamic(raw);
      expect(result.success, isTrue);
      expect((result.data?['offset'] as num?)?.toInt(), 0);
      clinic;
    });

    test('patients.checkDuplicates.INVALID_INPUT', () async {
      const ManifestScenario('patients.checkDuplicates.INVALID_INPUT');
      final clinic = await ctx.ensureClinic(label: 'pat_dup_invalid');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await expectRpcCode(() => ctx.patients.checkDuplicates(phone: '1234567'), 'INVALID_INPUT');
    });

    test('patients.createPatient.fullDemographics', () async {
      const ManifestScenario('patients.createPatient.fullDemographics');
      final clinic = await ctx.ensureClinic(label: 'pat_full_demo');
      final id = await ctx.fixtures.createPatientFullDemographics(clinic: clinic);
      expect(id, isNotEmpty);
    });

    test('patients.createPatient.INVALID_INPUT.name', () async {
      const ManifestScenario('patients.createPatient.INVALID_INPUT.name');
      final clinic = await ctx.ensureClinic(label: 'pat_name_invalid');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await expectRpcCode(
        () => ctx.patients.createPatient(
          CreatePatientInput(activeBranchId: clinic.branchId, fullName: '  ', phone: clinic.phone('80')),
        ),
        'INVALID_INPUT',
      );
    });

    test('patients.createPatient.INVALID_INPUT.phone', () async {
      const ManifestScenario('patients.createPatient.INVALID_INPUT.phone');
      final clinic = await ctx.ensureClinic(label: 'pat_phone_invalid');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await expectRpcCode(
        () => ctx.patients.createPatient(
          CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'No Phone', phone: '  '),
        ),
        'INVALID_INPUT',
      );
    });

    test('patients.createPatient.FORBIDDEN', () async {
      const ManifestScenario('patients.createPatient.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'pat_create_forbidden');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);
      await expectRpcCode(
        () => ctx.patients.createPatient(
          CreatePatientInput(activeBranchId: clinic.branchId, fullName: 'Lab Create', phone: clinic.phone('81')),
        ),
        'FORBIDDEN',
      );
    });

    test('patients.updatePatient.success', () async {
      const ManifestScenario('patients.updatePatient.success');
      final clinic = await ctx.ensureClinic(label: 'pat_update_ok');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('82'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      final detail = await ctx.patients.getPatient(id);
      final updatedAt = await ctx.patients.updatePatient(
        UpdatePatientInput(patientId: id, fullName: 'Updated OK', expectedUpdatedAt: detail.updatedAt),
      );
      expect(updatedAt.isAfter(detail.updatedAt) || updatedAt.isAtSameMomentAs(detail.updatedAt), isTrue);
    });

    test('patients.updatePatient.DUPLICATE_WARNING', () async {
      const ManifestScenario('patients.updatePatient.DUPLICATE_WARNING');
      final clinic = await ctx.ensureClinic(label: 'pat_upd_dup');
      await ctx.fixtures.createPatientAsAdmin(clinic: clinic, fullName: 'Dup A', phone: clinic.phone('83'));
      final idB = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, fullName: 'Dup B', phone: clinic.phone('84'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      final detail = await ctx.patients.getPatient(idB);
      try {
        await ctx.patients.updatePatient(
          UpdatePatientInput(
            patientId: idB,
            fullName: 'Dup A',
            phone: clinic.phone('83'),
            expectedUpdatedAt: detail.updatedAt,
          ),
        );
        fail('expected DUPLICATE_WARNING');
      } on RpcFailure catch (e) {
        expect(e.code, 'DUPLICATE_WARNING');
      }
    });

    test('patients.updatePatient.acknowledgeDuplicate', () async {
      const ManifestScenario('patients.updatePatient.acknowledgeDuplicate');
      final clinic = await ctx.ensureClinic(label: 'pat_upd_ack');
      final sharedDob = DateTime(1990, 6, 12);
      await ctx.fixtures.createPatientAsAdmin(
        clinic: clinic,
        fullName: 'Ack Match',
        phone: clinic.phone('85'),
        dateOfBirth: sharedDob,
      );
      final idB = await ctx.fixtures.createPatientAsAdmin(
        clinic: clinic,
        fullName: 'Ack Other',
        phone: clinic.phone('86'),
      );
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      final detail = await ctx.patients.getPatient(idB);
      await ctx.patients.updatePatient(
        UpdatePatientInput(
          patientId: idB,
          fullName: 'Ack Match',
          phone: clinic.phone('86'),
          dateOfBirth: sharedDob,
          expectedUpdatedAt: detail.updatedAt,
          acknowledgeDuplicate: true,
        ),
      );
    });

    test('patients.updatePatient.PATIENT_ARCHIVED', () async {
      const ManifestScenario('patients.updatePatient.PATIENT_ARCHIVED');
      final clinic = await ctx.ensureClinic(label: 'pat_upd_archived');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('87'));
      final ownerSessions = RoleSessions(ctx, clinic);
      await ownerSessions.signInAs(StaffRole.owner);
      await ctx.patients.archivePatient(id);
      await ctx.signOut();
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);
      await expectRpcCode(
        () => ctx.patients.updatePatient(
          UpdatePatientInput(patientId: id, fullName: 'Cannot Edit', expectedUpdatedAt: DateTime.now().toUtc()),
        ),
        'PATIENT_ARCHIVED',
      );
    });

    test('patients.updatePatient.NOT_FOUND', () async {
      const ManifestScenario('patients.updatePatient.NOT_FOUND');
      final clinic = await ctx.ensureClinic(label: 'pat_upd_nf');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      await expectRpcCode(
        () => ctx.patients.updatePatient(
          UpdatePatientInput(
            patientId: '00000000-0000-4000-8000-000000000099',
            fullName: 'Ghost',
            expectedUpdatedAt: DateTime.now().toUtc(),
          ),
        ),
        'NOT_FOUND',
      );
    });

    test('patients.updatePatient.FORBIDDEN', () async {
      const ManifestScenario('patients.updatePatient.FORBIDDEN');
      final clinic = await ctx.ensureClinic(label: 'pat_upd_forbidden');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('88'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);
      final detail = await ctx.patients.getPatient(id);
      await expectRpcCode(
        () => ctx.patients.updatePatient(
          UpdatePatientInput(patientId: id, fullName: 'Lab Edit', expectedUpdatedAt: detail.updatedAt),
        ),
        'FORBIDDEN',
      );
    });

    test('patients.archivePatient.FORBIDDEN.receptionist', () async {
      const ManifestScenario('patients.archivePatient.FORBIDDEN.receptionist');
      final clinic = await ctx.ensureClinic(label: 'pat_arch_recv');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('89'));
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.delete',
        isGranted: false,
      );
      await ctx.signOut();
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await expectRpcCode(() => ctx.patients.archivePatient(id), 'FORBIDDEN');
      await ctx.signInAdmin();
      await ctx.rolePermissions.updateRolePermission(
        role: StaffRole.receptionist,
        permissionKey: 'patients.delete',
        isGranted: true,
      );
    });

    test('patients.archivePatient.FORBIDDEN.lab', () async {
      const ManifestScenario('patients.archivePatient.FORBIDDEN.lab');
      final clinic = await ctx.ensureClinic(label: 'pat_arch_lab');
      final id = await ctx.fixtures.createPatientAsAdmin(clinic: clinic, phone: clinic.phone('90'));
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);
      await expectRpcCode(() => ctx.patients.archivePatient(id), 'FORBIDDEN');
    });

    test('patients.archivePatient.NOT_FOUND', () async {
      const ManifestScenario('patients.archivePatient.NOT_FOUND');
      final clinic = await ctx.ensureClinic(label: 'pat_arch_nf');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.owner);
      await expectRpcCode(() => ctx.patients.archivePatient('00000000-0000-4000-8000-000000000099'), 'NOT_FOUND');
    });
  });
}
