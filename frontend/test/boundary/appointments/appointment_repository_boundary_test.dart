@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

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

  group('AppointmentRepository (live PostgREST)', () {
    test('appointments.getSettings.success', () async {
      const ManifestScenario('appointments.getSettings.success');
      final clinic = await ctx.ensureClinic(label: 'appt_settings');
      await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);

      final settings = await ctx.appointments.getSettings(branchId: clinic.branchId);

      expect(settings.defaultDurationMinutes, greaterThanOrEqualTo(5));
      expect(settings.maxDurationMinutes, 240);
    });

    test('appointments.createAppointment.planned.success', () async {
      const ManifestScenario('appointments.createAppointment.planned.success');
      final clinic = await ctx.ensureClinic(label: 'appt_create');
      final patientId = await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);

      final start = DateTime.now().toUtc().add(const Duration(days: 2));
      final created = await ctx.appointments.createAppointment(
        branchId: clinic.branchId,
        patientId: patientId,
        doctorId: doctor.staffMemberId,
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 25,
      );

      expect(created.type, AppointmentType.planned);
      expect(created.status, AppointmentStatus.scheduled);
      expect(created.appointmentId, isNotEmpty);
    });

    test('appointments.createAppointment.SCHEDULE_CONFLICT', () async {
      const ManifestScenario('appointments.createAppointment.SCHEDULE_CONFLICT');
      final clinic = await ctx.ensureClinic(label: 'appt_conflict');
      final patientId = await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);

      final start = DateTime.now().toUtc().add(const Duration(days: 3));
      await ctx.appointments.createAppointment(
        branchId: clinic.branchId,
        patientId: patientId,
        doctorId: doctor.staffMemberId,
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 30,
      );

      await expectRpcCode(
        () => ctx.appointments.createAppointment(
          branchId: clinic.branchId,
          patientId: patientId,
          doctorId: doctor.staffMemberId,
          type: AppointmentType.planned,
          startTime: start.add(const Duration(minutes: 15)),
          durationMinutes: 30,
        ),
        'SCHEDULE_CONFLICT',
      );
    });

    test('appointments.createAppointment.planned.noDoctor', () async {
      const ManifestScenario('appointments.createAppointment.planned.noDoctor');
      final clinic = await ctx.ensureClinic(label: 'appt_no_doc');
      final patientId = await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);

      final start = DateTime.now().toUtc().add(const Duration(days: 4));
      final created = await ctx.appointments.createAppointment(
        branchId: clinic.branchId,
        patientId: patientId,
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 20,
      );

      expect(created.type, AppointmentType.planned);
      expect(created.status, AppointmentStatus.scheduled);
      expect(created.appointmentId, isNotEmpty);
    });

    test('appointments.createAppointment.FORBIDDEN.lab_staff', () async {
      const ManifestScenario('appointments.createAppointment.FORBIDDEN.lab_staff');
      final clinic = await ctx.ensureClinic(label: 'appt_lab_create');
      final patientId = await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);

      final start = DateTime.now().toUtc().add(const Duration(days: 5));
      await expectRpcCode(
        () => ctx.appointments.createAppointment(
          branchId: clinic.branchId,
          patientId: patientId,
          doctorId: doctor.staffMemberId,
          type: AppointmentType.planned,
          startTime: start,
          durationMinutes: 20,
        ),
        'FORBIDDEN',
      );
    });

    test('appointments.getSettings.FORBIDDEN.lab_staff', () async {
      const ManifestScenario('appointments.getSettings.FORBIDDEN.lab_staff');
      final clinic = await ctx.ensureClinic(label: 'appt_lab_denied');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);

      await expectRpcCode(() => ctx.appointments.getSettings(branchId: clinic.branchId), 'FORBIDDEN');
    });

    test('appointments.getSettings.FORBIDDEN.unauthenticated', () async {
      const ManifestScenario('appointments.getSettings.FORBIDDEN.unauthenticated');
      final clinic = await ctx.ensureClinic(label: 'appt_anon');
      await ctx.signOut();

      try {
        await ctx.appointments.getSettings(branchId: clinic.branchId);
        fail('Expected auth failure when signed out');
      } on RpcFailure catch (failure) {
        expect(failure.code, anyOf(equals('FORBIDDEN'), equals('PGRST301')));
      }
    });
  });
}
