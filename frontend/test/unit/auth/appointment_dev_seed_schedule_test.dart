import 'package:ai_clinic/features/auth/presentation/dev/appointment_dev_seed_schedule.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentDevSeedSchedule', () {
    test('plannedStartTimes stay within working hours on a working day', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final reference = DateTime(2026, 5, 28, 10, 0); // Thursday

      final slots = AppointmentDevSeedSchedule.plannedStartTimes(schedule: schedule, count: 3, reference: reference);

      expect(slots, hasLength(3));
      for (final slot in slots) {
        expect(slot.weekday, DateTime.thursday);
        final minutes = slot.hour * 60 + slot.minute;
        expect(minutes, greaterThanOrEqualTo(10 * 60 + 30));
        expect(minutes + 30, lessThanOrEqualTo(17 * 60));
      }
    });

    test('plannedStartTimes skip non-working days', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final reference = DateTime(2026, 5, 31, 10, 0); // Sunday

      final slots = AppointmentDevSeedSchedule.plannedStartTimes(schedule: schedule, count: 2, reference: reference);

      expect(slots, hasLength(2));
      for (final slot in slots) {
        expect(slot.weekday, isNot(DateTime.sunday));
      }
    });

    test('plannedStartTimes span multiple days when the day is full', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final reference = DateTime(2026, 5, 28, 16, 0); // Thursday 16:00

      final slots = AppointmentDevSeedSchedule.plannedStartTimes(schedule: schedule, count: 4, reference: reference);

      expect(slots, hasLength(4));
      expect(slots.first.weekday, DateTime.thursday);
      expect(slots.last.weekday, DateTime.friday);
    });

    test('plannedStartTimes accept postgres HH:mm:ss open and close times', () {
      final schedule = BranchWorkingSchedule.fromJson({
        'days': [
          {'day': 'thursday', 'is_working_day': true, 'open_time': '09:00:00', 'close_time': '17:00:00'},
        ],
      })!;

      final slots = AppointmentDevSeedSchedule.plannedStartTimes(
        schedule: schedule,
        count: 1,
        reference: DateTime(2026, 5, 28, 8, 0),
      );

      expect(slots, hasLength(1));
      expect(slots.first.hour, 9);
    });
  });
}
