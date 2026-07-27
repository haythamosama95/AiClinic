import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';

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

    test('parseHm accepts HH:mm, HH:mm:ss, and single-digit hour formats', () {
      const expected = 9 * 60;

      expect(AppointmentBranchWorkingHours.parseHm('09:00'), expected);
      expect(AppointmentBranchWorkingHours.parseHm('09:00:00'), expected);
      expect(AppointmentBranchWorkingHours.parseHm('9:00'), expected);
    });

    test('treats 00:00 close time as end-of-day', () {
      final midnightCloseSchedule = BranchWorkingSchedule(
        BranchWeekday.values
            .map(
              (day) => BranchWorkingDayHours(
                day: day,
                isWorkingDay: day != BranchWeekday.sunday,
                openTime: day == BranchWeekday.sunday ? null : '09:00:00',
                closeTime: day == BranchWeekday.sunday ? null : '00:00:00',
              ),
            )
            .toList(growable: false),
      );
      final start = DateTime(2026, 6, 1, 23, 0);
      final end = start.add(const Duration(minutes: 30));

      expect(
        AppointmentWorkingHours.isWithinSchedule(schedule: midnightCloseSchedule, start: start, end: end),
        isTrue,
      );
    });

    test('rejects slot starting exactly at close (half-open interval)', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final start = DateTime(2026, 6, 1, 17, 0);
      final end = start.add(const Duration(minutes: 30));

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isFalse);
    });

    test('accepts slot ending exactly at close', () {
      final schedule = BranchWorkingSchedule(
        BranchWeekday.values
            .map(
              (day) => BranchWorkingDayHours(
                day: day,
                isWorkingDay: day != BranchWeekday.sunday,
                openTime: day == BranchWeekday.sunday ? null : '09:00:00',
                closeTime: day == BranchWeekday.sunday ? null : '17:00:00',
              ),
            )
            .toList(growable: false),
      );
      final start = DateTime(2026, 6, 1, 16, 30);
      final end = start.add(const Duration(minutes: 30));

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isTrue);
    });
  });
}
