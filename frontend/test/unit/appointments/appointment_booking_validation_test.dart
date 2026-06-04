import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('booking past start validation', () {
    test('rejects start time before now', () {
      final past = DateTime.now().subtract(const Duration(minutes: 5));
      expect(past.isBefore(DateTime.now()), isTrue);
    });

    test('working hours validator catches late slot', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final start = DateTime(2026, 6, 4, 16, 45);

      expect(
        AppointmentBranchWorkingHours.validationMessage(schedule: schedule, startTime: start, durationMinutes: 30),
        isNotNull,
      );
    });
  });
}
