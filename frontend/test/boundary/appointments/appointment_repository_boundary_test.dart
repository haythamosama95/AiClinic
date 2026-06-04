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

Future<void> _openBranchHours24x7(BoundaryTestContext ctx, String branchId) {
  return ctx.sql.execute('''
UPDATE public.branches
SET working_schedule = jsonb_build_object(
  'days',
  jsonb_build_array(
    jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
    jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59')
  )
)
WHERE id = '$branchId'::uuid;
''');
}

/// Planned start on today's UTC calendar day (org TZ in crud suite is UTC).
DateTime _boundarySameDayPlannedStartUtc({int hourOffset = 10}) {
  final now = DateTime.now().toUtc();
  final dayStart = DateTime.utc(now.year, now.month, now.day);
  var start = dayStart.add(Duration(hours: hourOffset));
  if (!start.isAfter(now.add(const Duration(minutes: 30)))) {
    start = now.add(const Duration(hours: 1));
    start = DateTime.utc(start.year, start.month, start.day, start.hour);
  }
  return start;
}

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
      await _openBranchHours24x7(ctx, clinic.branchId);

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
      await _openBranchHours24x7(ctx, clinic.branchId);

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
      await _openBranchHours24x7(ctx, clinic.branchId);

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

    test('appointments.getSettings.success.lab_staff', () async {
      const ManifestScenario('appointments.getSettings.success.lab_staff');
      final clinic = await ctx.ensureClinic(label: 'appt_lab_read');
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.labStaff);

      final settings = await ctx.appointments.getSettings(branchId: clinic.branchId);

      expect(settings.defaultDurationMinutes, greaterThanOrEqualTo(5));
      expect(settings.maxDurationMinutes, 240);
    });

    test('appointments.updateAppointmentStatus.lifecycle.success', () async {
      const ManifestScenario('appointments.updateAppointmentStatus.lifecycle.success');
      final clinic = await ctx.ensureClinic(label: 'appt_status');
      final patientId = await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await _openBranchHours24x7(ctx, clinic.branchId);

      final start = _boundarySameDayPlannedStartUtc(hourOffset: 10);
      final created = await ctx.appointments.createAppointment(
        branchId: clinic.branchId,
        patientId: patientId,
        doctorId: doctor.staffMemberId,
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 20,
      );

      var status = await ctx.appointments.updateAppointmentStatus(
        appointmentId: created.appointmentId,
        newStatus: AppointmentStatus.confirmed,
      );
      expect(status, AppointmentStatus.confirmed);

      status = await ctx.appointments.updateAppointmentStatus(
        appointmentId: created.appointmentId,
        newStatus: AppointmentStatus.checkedIn,
      );
      expect(status, AppointmentStatus.checkedIn);

      status = await ctx.appointments.updateAppointmentStatus(
        appointmentId: created.appointmentId,
        newStatus: AppointmentStatus.inProgress,
      );
      expect(status, AppointmentStatus.inProgress);

      // V1-5: in_progress → completed requires visit documentation (not a direct status RPC).
      await sessions.signInAs(StaffRole.doctor);
      final visit = await ctx.visits.createVisit(appointmentId: created.appointmentId);
      final detail = await ctx.visits.getVisit(visitId: visit.visitId);
      expect(detail.soap, isNotNull);
      await ctx.visits.saveSoapNote(
        visitId: visit.visitId,
        expectedUpdatedAt: detail.soap!.updatedAt,
        subjective: 'Chief complaint documented.',
      );
      final completed = await ctx.visits.completeVisit(visitId: visit.visitId);
      expect(completed.visitStatus, 'completed');
      expect(completed.appointmentStatus, 'completed');
    });

    test('appointments.rebookAfterCancel.sameSlot.success', () async {
      const ManifestScenario('appointments.rebookAfterCancel.sameSlot.success');
      final clinic = await ctx.ensureClinic(label: 'appt_rebook_cancel');
      final patientId = await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await _openBranchHours24x7(ctx, clinic.branchId);

      final start = DateTime.now().toUtc().add(const Duration(days: 10));
      final first = await ctx.appointments.createAppointment(
        branchId: clinic.branchId,
        patientId: patientId,
        doctorId: doctor.staffMemberId,
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 30,
      );

      final cancelled = await ctx.appointments.cancelAppointment(
        appointmentId: first.appointmentId,
        reason: 'Patient called',
      );
      expect(cancelled, AppointmentStatus.cancelled);

      final second = await ctx.appointments.createAppointment(
        branchId: clinic.branchId,
        patientId: patientId,
        doctorId: doctor.staffMemberId,
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 30,
      );

      expect(second.status, AppointmentStatus.scheduled);
      expect(second.appointmentId, isNotEmpty);
      expect(second.appointmentId, isNot(first.appointmentId));
    });

    test('appointments.updateAppointmentStatus.INVALID_TRANSITION', () async {
      const ManifestScenario('appointments.updateAppointmentStatus.INVALID_TRANSITION');
      final clinic = await ctx.ensureClinic(label: 'appt_status_invalid');
      final patientId = await ctx.fixtures.createPatientAsAdmin(clinic: clinic);
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.receptionist);
      await _openBranchHours24x7(ctx, clinic.branchId);

      final start = DateTime.now().toUtc().add(const Duration(days: 7));
      final created = await ctx.appointments.createAppointment(
        branchId: clinic.branchId,
        patientId: patientId,
        doctorId: doctor.staffMemberId,
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 20,
      );

      await expectRpcCode(
        () => ctx.appointments.updateAppointmentStatus(
          appointmentId: created.appointmentId,
          newStatus: AppointmentStatus.inProgress,
        ),
        'INVALID_TRANSITION',
      );
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
