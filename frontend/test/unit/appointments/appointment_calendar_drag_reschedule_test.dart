import 'package:ai_clinic/features/appointments/domain/appointment_calendar_layout.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CAL-G — drag-and-drop reschedule (unit)', () {
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

    test('CAL-G02: snapTimeToSlot rounds arbitrary drag times to 30-minute grid', () {
      expect(AppointmentCalendarLayout.snapTimeToSlot(DateTime(2026, 6, 4, 10, 7)), DateTime(2026, 6, 4, 10, 0));
      expect(AppointmentCalendarLayout.snapTimeToSlot(DateTime(2026, 6, 4, 10, 23)), DateTime(2026, 6, 4, 10, 30));
    });

    test('CAL-G03: isNoOpMove true when dropping on original start', () {
      final appointment = item();
      expect(AppointmentRescheduleValidation.isNoOpMove(appointment: appointment, newStart: thursday), isTrue);
    });

    test('CAL-G05: validateMove rejects confirmed appointments', () {
      final appointment = item(status: AppointmentStatus.confirmed);

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 11, 0),
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, contains('Only scheduled appointments'));
    });

    test('CAL-G06: validateMove rejects branch overlap', () {
      final appointment = item();
      final blocker = item(
        id: 'a2',
        patientId: 'p2',
        start: DateTime(2026, 6, 4, 10, 15),
        end: DateTime(2026, 6, 4, 10, 45),
      );

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        schedule: schedule,
        branchAppointments: [appointment, blocker],
      );

      expect(error, contains('overlaps'));
    });

    test('CAL-G07: validateMove rejects moves outside working hours', () {
      final appointment = item();

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 7, 30),
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, contains('working hours'));
    });

    test('CAL-G08: validateMove rejects same-day patient duplicate', () {
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

    test('CAL-G09: validateDoctorResourceMove rejects cross-doctor moves', () {
      final appointment = item(doctorId: 'd1');

      final error = AppointmentRescheduleValidation.validateDoctorResourceMove(
        appointment: appointment,
        targetDoctorId: 'd2',
      );

      expect(error, contains('another doctor'));
    });

    test('CAL-G15: validateMove still passes when slot appears free (server may conflict later)', () {
      final appointment = item();

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 11, 0),
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, isNull);
    });
  });
}
