import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CAL-H — resize (unit)', () {
    final schedule = BranchWorkingSchedule.defaultSchedule();
    final start = DateTime(2026, 6, 4, 10, 0);
    final end = DateTime(2026, 6, 4, 11, 0);

    AppointmentListItem item({String id = 'a1', DateTime? startTime, DateTime? endTime}) {
      return AppointmentListItem(
        id: id,
        patientId: 'p1',
        patientName: 'Patient',
        doctorId: 'd1',
        doctorName: 'Dr One',
        startTime: startTime ?? start,
        endTime: endTime ?? end,
        type: AppointmentType.planned,
        status: AppointmentStatus.scheduled,
      );
    }

    test('CAL-H03: validateMove rejects duration below 5 minutes', () {
      final appointment = item();

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        newEnd: DateTime(2026, 6, 4, 10, 3),
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, contains('too short'));
    });

    test('CAL-H04: validateMove rejects extending into overlapping appointment', () {
      final appointment = item(endTime: DateTime(2026, 6, 4, 10, 30));
      final adjacent = item(id: 'a2', startTime: DateTime(2026, 6, 4, 10, 30), endTime: DateTime(2026, 6, 4, 11, 0));

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        newEnd: DateTime(2026, 6, 4, 10, 45),
        schedule: schedule,
        branchAppointments: [appointment, adjacent],
      );

      expect(error, isNotNull);
    });

    test('CAL-H05: validateMove allows moving start earlier while end stays fixed', () {
      final appointment = item();

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 9, 30),
        newEnd: DateTime(2026, 6, 4, 11, 0),
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, isNull);
    });

    test('CAL-H06: isNoOpResize true when start and end unchanged', () {
      final appointment = item();

      expect(
        AppointmentRescheduleValidation.isNoOpResize(appointment: appointment, newStart: start, newEnd: end),
        isTrue,
      );
    });

    test('CAL-H07: validateMove allows duration greater than 240 minutes', () {
      final appointment = item(endTime: DateTime(2026, 6, 4, 10, 30));
      final extendedEnd = DateTime(2026, 6, 4, 15, 0); // 5 hours

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        newEnd: extendedEnd,
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, isNull);
    });

    test('CAL-H02: validateMove allows shrinking to 30 minutes when slot is free', () {
      final appointment = item();

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        newEnd: DateTime(2026, 6, 4, 10, 30),
        schedule: schedule,
        branchAppointments: [appointment],
      );

      expect(error, isNull);
    });

    test('snapTimeToSlot supports resize edge snapping', () {
      expect(AppointmentCalendarDisplay.snapTimeToSlot(DateTime(2026, 6, 4, 10, 44)), DateTime(2026, 6, 4, 10, 30));
      expect(AppointmentCalendarDisplay.snapTimeToSlot(DateTime(2026, 6, 4, 11, 1)), DateTime(2026, 6, 4, 11, 0));
    });
  });
}
