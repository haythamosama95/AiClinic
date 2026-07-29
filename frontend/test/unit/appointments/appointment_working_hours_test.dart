import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';

void main() {
  group('AppointmentWorkingHours', () {
    final schedule = BranchWorkingSchedule.defaultSchedule();

    BranchWorkingSchedule scheduleWithDay({
      required BranchWeekday weekday,
      required bool isWorkingDay,
      String? openTime,
      String? closeTime,
    }) {
      return BranchWorkingSchedule(
        BranchWeekday.values
            .map(
              (day) => BranchWorkingDayHours(
                day: day,
                isWorkingDay: day == weekday ? isWorkingDay : false,
                openTime: day == weekday ? openTime : null,
                closeTime: day == weekday ? closeTime : null,
              ),
            )
            .toList(growable: false),
      );
    }

    test('accepts slots inside a working day', () {
      final start = DateTime(2026, 6, 1, 10, 0);
      final end = start.add(const Duration(minutes: 30));

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isTrue);
    });

    test('rejects slots outside open hours', () {
      final start = DateTime(2026, 6, 1, 8, 0);
      final end = start.add(const Duration(minutes: 30));

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isFalse);
    });

    test('rejects non-working days', () {
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

    test('invalid state: rejects when end is not after start', () {
      final start = DateTime(2026, 6, 1, 10, 0);

      expect(
        AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: start),
        isFalse,
      );
      expect(
        AppointmentWorkingHours.isWithinSchedule(
          schedule: schedule,
          start: start,
          end: start.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('invalid state: rejects cross-day slots without midnight sentinel', () {
      final mondaySchedule = scheduleWithDay(
        weekday: BranchWeekday.monday,
        isWorkingDay: true,
        openTime: '09:00',
        closeTime: '17:00',
      );
      final start = DateTime(2026, 6, 1, 23, 30);
      final end = DateTime(2026, 6, 2, 0, 15);

      expect(
        AppointmentWorkingHours.isWithinSchedule(schedule: mondaySchedule, start: start, end: end),
        isFalse,
      );
    });

    test('invalid state: rejects unparseable open or close times', () {
      final badHours = scheduleWithDay(
        weekday: BranchWeekday.monday,
        isWorkingDay: true,
        openTime: '9:00',
        closeTime: '17:00',
      );
      final start = DateTime(2026, 6, 1, 10, 0);
      final end = start.add(const Duration(minutes: 30));

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: badHours, start: start, end: end), isFalse);
    });

    test('edge case: minute-range boundaries at open and close', () {
      final monday = DateTime(2026, 6, 1);
      final atOpen = DateTime(2026, 6, 1, 9, 0);
      final beforeOpen = DateTime(2026, 6, 1, 8, 59);
      final endingAtClose = DateTime(2026, 6, 1, 16, 30);
      final endingAfterClose = DateTime(2026, 6, 1, 16, 31);

      expect(
        AppointmentWorkingHours.isWithinSchedule(
          schedule: schedule,
          start: atOpen,
          end: atOpen.add(const Duration(minutes: 30)),
        ),
        isTrue,
      );
      expect(
        AppointmentWorkingHours.isWithinSchedule(
          schedule: schedule,
          start: beforeOpen,
          end: beforeOpen.add(const Duration(minutes: 30)),
        ),
        isFalse,
      );
      expect(
        AppointmentWorkingHours.isWithinSchedule(
          schedule: schedule,
          start: endingAtClose,
          end: DateTime(monday.year, monday.month, monday.day, 17, 0),
        ),
        isTrue,
      );
      expect(
        AppointmentWorkingHours.isWithinSchedule(
          schedule: schedule,
          start: endingAfterClose,
          end: DateTime(monday.year, monday.month, monday.day, 17, 1),
        ),
        isFalse,
      );
    });

    test('invalid state: HH:mm parser rejects malformed values via schedule', () {
      const rejectedTimes = ['24:00', '9:00', '08:60', '', 'abc'];
      final start = DateTime(2026, 6, 1, 10, 0);
      final end = start.add(const Duration(minutes: 30));

      for (final badOpen in rejectedTimes) {
        final badSchedule = scheduleWithDay(
          weekday: BranchWeekday.monday,
          isWorkingDay: true,
          openTime: badOpen,
          closeTime: '17:00',
        );
        expect(
          AppointmentWorkingHours.isWithinSchedule(schedule: badSchedule, start: start, end: end),
          isFalse,
          reason: 'openTime $badOpen should be rejected',
        );
      }

      for (final badClose in rejectedTimes) {
        final badSchedule = scheduleWithDay(
          weekday: BranchWeekday.monday,
          isWorkingDay: true,
          openTime: '09:00',
          closeTime: badClose,
        );
        expect(
          AppointmentWorkingHours.isWithinSchedule(schedule: badSchedule, start: start, end: end),
          isFalse,
          reason: 'closeTime $badClose should be rejected',
        );
      }
    });
  });
}
