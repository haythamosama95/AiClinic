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

    test('accepts slots ending at midnight when close is 23:59 sentinel', () {
      final schedule = BranchWorkingSchedule(
        BranchWeekday.values
            .map(
              (day) => BranchWorkingDayHours(
                day: day,
                isWorkingDay: day != BranchWeekday.sunday,
                openTime: day == BranchWeekday.sunday ? null : '09:00',
                closeTime: day == BranchWeekday.sunday ? null : '23:59',
              ),
            )
            .toList(growable: false),
      );
      final start = DateTime(2026, 6, 1, 23, 0);
      final end = DateTime(2026, 6, 2, 0, 0);

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isTrue);
    });
  });
}
