import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchWorkingSchedule', () {
    test('emptySchedule starts with every day closed', () {
      final schedule = BranchWorkingSchedule.emptySchedule();

      expect(schedule.hasConfiguredWorkingHours, isFalse);
      expect(schedule.days.every((day) => !day.isWorkingDay), isTrue);
    });

    test('defaultSchedule is configured', () {
      expect(BranchWorkingSchedule.defaultSchedule().hasConfiguredWorkingHours, isTrue);
    });

    test('isValidWorkingDay rejects open day without times', () {
      const hours = BranchWorkingDayHours(day: BranchWeekday.monday, isWorkingDay: true);
      expect(BranchWorkingSchedule.isValidWorkingDay(hours), isFalse);
    });
  });
}
