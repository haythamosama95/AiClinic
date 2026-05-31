import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

void main() {
  group('AppointmentWorkingHours', () {
    test('accepts slots inside a working day', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final start = DateTime(2026, 6, 1, 10, 0);
      final end = start.add(const Duration(minutes: 30));

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isTrue);
    });

    test('rejects slots outside open hours', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final start = DateTime(2026, 6, 1, 8, 0);
      final end = start.add(const Duration(minutes: 30));

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isFalse);
    });

    test('rejects non-working days', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final start = DateTime(2026, 6, 7, 10, 0);
      final end = start.add(const Duration(minutes: 30));

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isFalse);
    });
  });
}
