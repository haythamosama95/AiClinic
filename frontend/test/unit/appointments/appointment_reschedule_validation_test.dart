import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentRescheduleValidation', () {
    final schedule = BranchWorkingSchedule.defaultSchedule();
    final thursday = DateTime(2026, 6, 4, 10, 0);
    final thursdayEnd = DateTime(2026, 6, 4, 10, 30);

    AppointmentListItem item({
      String id = 'a1',
      String patientId = 'p1',
      String? doctorId = 'd1',
      DateTime? start,
      DateTime? end,
      AppointmentStatus status = AppointmentStatus.scheduled,
    }) {
      return AppointmentListItem(
        id: id,
        patientId: patientId,
        patientName: 'Patient $id',
        doctorId: doctorId,
        doctorName: 'Dr One',
        startTime: start ?? thursday,
        endTime: end ?? thursdayEnd,
        type: AppointmentType.planned,
        status: status,
      );
    }

    test('allows move into a free slot within working hours', () {
      final appointment = item();
      final others = [
        appointment,
        item(id: 'a2', patientId: 'p2', start: DateTime(2026, 6, 4, 11, 0), end: DateTime(2026, 6, 4, 11, 30)),
      ];

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 9, 30),
        schedule: schedule,
        branchAppointments: others,
      );

      expect(error, isNull);
    });

    test('rejects confirmed appointments', () {
      final appointment = item(status: AppointmentStatus.confirmed);

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 11, 0),
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, contains('Only scheduled appointments'));
    });

    test('rejects moves outside branch working hours', () {
      final appointment = item();

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 7, 30),
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, contains('working hours'));
    });

    test('rejects branch overlap with another appointment', () {
      final appointment = item();
      final blocker = item(id: 'a2', start: DateTime(2026, 6, 4, 10, 15), end: DateTime(2026, 6, 4, 10, 45));

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        schedule: schedule,
        branchAppointments: [appointment, blocker],
      );

      expect(error, contains('overlaps'));
    });

    test('rejects doctor overlap with clearer message', () {
      final appointment = item(doctorId: 'd1');
      final blocker = item(
        id: 'a2',
        doctorId: 'd1',
        start: DateTime(2026, 6, 4, 10, 15),
        end: DateTime(2026, 6, 4, 10, 45),
      );

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        schedule: schedule,
        branchAppointments: [appointment, blocker],
      );

      expect(error, contains('doctor is not available'));
    });

    test('rejects same-day patient duplicate on another day', () {
      final appointment = item(patientId: 'p1');
      final samePatient = item(
        id: 'a2',
        patientId: 'p1',
        start: DateTime(2026, 6, 5, 14, 0),
        end: DateTime(2026, 6, 5, 14, 30),
      );

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 5, 10, 0),
        schedule: schedule,
        branchAppointments: [appointment, samePatient],
      );

      expect(error, contains('same day'));
    });

    test('ignores cancelled appointments when checking overlap', () {
      final appointment = item();
      final cancelled = item(
        id: 'a2',
        start: DateTime(2026, 6, 4, 10, 15),
        end: DateTime(2026, 6, 4, 10, 45),
        status: AppointmentStatus.cancelled,
      );

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        schedule: schedule,
        branchAppointments: [appointment, cancelled],
      );

      expect(error, isNull);
    });

    test('rejects cross-doctor resource moves', () {
      final appointment = item(doctorId: 'd1');

      final error = AppointmentRescheduleValidation.validateDoctorResourceMove(
        appointment: appointment,
        targetDoctorId: 'd2',
      );

      expect(error, contains('another doctor'));
    });

    test('isNoOpMove true when start time unchanged', () {
      expect(AppointmentRescheduleValidation.isNoOpMove(appointment: item(), newStart: thursday), isTrue);
    });

    test('isNoOpResize true when start and end unchanged', () {
      expect(
        AppointmentRescheduleValidation.isNoOpResize(appointment: item(), newStart: thursday, newEnd: thursdayEnd),
        isTrue,
      );
    });

    test('isNoOpResize false when only end time changes', () {
      expect(
        AppointmentRescheduleValidation.isNoOpResize(
          appointment: item(),
          newStart: thursday,
          newEnd: DateTime(2026, 6, 4, 11, 0),
        ),
        isFalse,
      );
    });
  });
}
