import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentBranchWorkingHours', () {
    final schedule = BranchWorkingSchedule.defaultSchedule();

    test('accepts slot within working hours', () {
      final start = DateTime(2026, 6, 4, 10, 0); // Thursday

      expect(
        AppointmentBranchWorkingHours.isWithinWorkingHours(schedule: schedule, startTime: start, durationMinutes: 30),
        isTrue,
      );
    });

    test('rejects slot before opening', () {
      final start = DateTime(2026, 6, 4, 7, 0);

      final message = AppointmentBranchWorkingHours.validationMessage(
        schedule: schedule,
        startTime: start,
        durationMinutes: 30,
      );

      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('working hours'));
    });

    test('rejects slot that ends after closing', () {
      final start = DateTime(2026, 6, 4, 16, 45);

      final message = AppointmentBranchWorkingHours.validationMessage(
        schedule: schedule,
        startTime: start,
        durationMinutes: 30,
      );

      expect(message, isNotNull);
    });

    test('rejects slot crossing midnight', () {
      final start = DateTime(2026, 6, 4, 23, 30);

      final message = AppointmentBranchWorkingHours.validationMessage(
        schedule: schedule,
        startTime: start,
        durationMinutes: 60,
      );

      expect(message, contains('same day'));
    });

    test('rejects non-working day', () {
      final start = DateTime(2026, 6, 7, 10, 0); // Sunday

      final message = AppointmentBranchWorkingHours.validationMessage(
        schedule: schedule,
        startTime: start,
        durationMinutes: 30,
      );

      expect(message, contains('closed'));
    });

    test('isWorkingDay reflects schedule', () {
      expect(AppointmentBranchWorkingHours.isWorkingDay(schedule, DateTime(2026, 6, 4)), isTrue);
      expect(AppointmentBranchWorkingHours.isWorkingDay(schedule, DateTime(2026, 6, 7)), isFalse);
    });
  });
}
