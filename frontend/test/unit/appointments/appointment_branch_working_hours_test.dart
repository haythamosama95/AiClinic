import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';
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

    test('previousWorkingDay skips closures', () {
      final monday = DateTime(2026, 6, 8); // Monday

      expect(
        AppointmentBranchWorkingHours.previousWorkingDay(schedule, monday),
        DateTime(2026, 6, 6), // Saturday (Sunday is closed in default schedule)
      );
      expect(
        AppointmentBranchWorkingHours.previousWorkingDay(schedule, DateTime(2026, 6, 9)),
        DateTime(2026, 6, 8), // Tuesday -> Monday
      );
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
                openTime: day == BranchWeekday.sunday ? null : '09:00',
                closeTime: day == BranchWeekday.sunday ? null : '00:00',
              ),
            )
            .toList(growable: false),
      );
      final start = DateTime(2026, 6, 4, 22, 0);

      expect(
        AppointmentBranchWorkingHours.isWithinWorkingHours(
          schedule: midnightCloseSchedule,
          startTime: start,
          durationMinutes: 60,
        ),
        isTrue,
      );
    });

    test('rejects slot starting exactly at close (half-open interval)', () {
      final start = DateTime(2026, 6, 4, 17, 0);

      final message = AppointmentBranchWorkingHours.validationMessage(
        schedule: schedule,
        startTime: start,
        durationMinutes: 30,
      );

      expect(message, isNotNull);
    });

    test('accepts slot ending exactly at close', () {
      final start = DateTime(2026, 6, 4, 16, 30);

      expect(
        AppointmentBranchWorkingHours.isWithinWorkingHours(schedule: schedule, startTime: start, durationMinutes: 30),
        isTrue,
      );
    });
  });
}
