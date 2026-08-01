import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaultWorkingSchedule', () {
    test('matches domain default schedule with configured hours', () {
      final schedule = defaultWorkingSchedule();

      expect(schedule, BranchWorkingSchedule.defaultSchedule());
      expect(hasConfiguredWorkingHours(schedule), isTrue);
    });
  });

  group('emptyWorkingSchedule', () {
    test('matches domain empty schedule', () {
      final schedule = emptyWorkingSchedule();

      expect(schedule, BranchWorkingSchedule.emptySchedule());
      expect(hasConfiguredWorkingHours(schedule), isFalse);
    });
  });

  group('weekdayLabel', () {
    test('returns human-readable weekday labels', () {
      expect(weekdayLabel(BranchWeekday.monday), 'Monday');
      expect(weekdayLabel(BranchWeekday.sunday), 'Sunday');
    });
  });

  group('formatWorkingHoursSummary', () {
    test('returns not configured for null or empty schedules', () {
      expect(formatWorkingHoursSummary(null), 'Not configured');
      expect(formatWorkingHoursSummary(emptyWorkingSchedule()), 'Not configured');
    });

    test('formats a single open day', () {
      final schedule = BranchWorkingSchedule(
        [
          const BranchWorkingDayHours(
            day: BranchWeekday.monday,
            isWorkingDay: true,
            openTime: '09:00',
            closeTime: '17:00',
          ),
        ],
      );

      expect(formatWorkingHoursSummary(schedule), 'Monday 09:00–17:00');
    });

    test('formats multiple days with identical hours', () {
      final schedule = BranchWorkingSchedule(
        BranchWeekday.values
            .where((day) => day != BranchWeekday.sunday)
            .map(
              (day) => BranchWorkingDayHours(
                day: day,
                isWorkingDay: true,
                openTime: '09:00',
                closeTime: '17:00',
              ),
            )
            .toList(growable: false),
      );

      expect(formatWorkingHoursSummary(schedule), '6 days · 09:00–17:00');
    });

    test('summarizes mixed hours as configured day count', () {
      final schedule = BranchWorkingSchedule(
        [
          const BranchWorkingDayHours(
            day: BranchWeekday.monday,
            isWorkingDay: true,
            openTime: '09:00',
            closeTime: '17:00',
          ),
          const BranchWorkingDayHours(
            day: BranchWeekday.tuesday,
            isWorkingDay: true,
            openTime: '10:00',
            closeTime: '18:00',
          ),
        ],
      );

      expect(formatWorkingHoursSummary(schedule), '2 days configured');
    });
  });

  group('weekdayFromId', () {
    test('resolves weekday ids from clinic constants', () {
      expect(weekdayFromId('monday'), BranchWeekday.monday);
      expect(weekdayFromId('friday'), BranchWeekday.friday);
    });

    test('returns null for unknown ids', () {
      expect(weekdayFromId('notaday'), isNull);
      expect(weekdayFromId(''), isNull);
    });
  });
}
