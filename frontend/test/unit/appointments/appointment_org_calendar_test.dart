import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(ensureAppointmentTimezonesInitialized);

  group('ensureAppointmentTimezonesInitialized', () {
    test('trivial: calling twice is idempotent', () {
      ensureAppointmentTimezonesInitialized();
      expect(() => ensureAppointmentTimezonesInitialized(), returnsNormally);
    });
  });

  group('effectiveOrganizationTimezone', () {
    test('trivial: null maps to UTC', () {
      expect(effectiveOrganizationTimezone(null), 'UTC');
    });

    test('trivial: empty and whitespace map to UTC', () {
      expect(effectiveOrganizationTimezone(''), 'UTC');
      expect(effectiveOrganizationTimezone('   '), 'UTC');
    });

    test('trivial: valid timezone id passes through', () {
      expect(effectiveOrganizationTimezone('Asia/Riyadh'), 'Asia/Riyadh');
    });
  });

  group('calendarDayInOrganizationTimezone', () {
    test('regression: same instant can be different calendar days across zones', () {
      final instantUtc = DateTime.utc(2026, 7, 15, 2, 0);
      final riyadhDay = calendarDayInOrganizationTimezone('Asia/Riyadh', instantUtc);
      final newYorkDay = calendarDayInOrganizationTimezone('America/New_York', instantUtc);

      expect(riyadhDay, DateTime(2026, 7, 15));
      expect(newYorkDay, DateTime(2026, 7, 14));
    });
  });

  group('appointmentWallClockInOrganizationTimezone', () {
    test('advanced: converts UTC instant to organization wall clock', () {
      final instantUtc = DateTime.utc(2026, 7, 15, 21, 30);
      final riyadhClock = appointmentWallClockInOrganizationTimezone('Asia/Riyadh', instantUtc);

      expect(riyadhClock, DateTime(2026, 7, 16, 0, 30));
    });
  });

  group('appointmentCalendarDayHasArrivedInTimezone', () {
    test('edge case: appointment later today in org timezone has not arrived', () {
      final referenceUtc = DateTime.utc(2026, 7, 15, 6, 0);
      final startTime = DateTime.utc(2026, 7, 16, 6, 0);

      expect(
        appointmentCalendarDayHasArrivedInTimezone(
          startTime,
          organizationTimezone: 'America/New_York',
          referenceUtc: referenceUtc,
        ),
        isFalse,
      );
    });

    test('edge case: appointment on prior org calendar day has arrived', () {
      final referenceUtc = DateTime.utc(2026, 7, 15, 6, 0);
      final startTime = DateTime.utc(2026, 7, 14, 15, 0);

      expect(
        appointmentCalendarDayHasArrivedInTimezone(
          startTime,
          organizationTimezone: 'America/New_York',
          referenceUtc: referenceUtc,
        ),
        isTrue,
      );
    });
  });

  group('appointmentTodayRangeInTimezone', () {
    test('regression: today window differs between Asia/Riyadh and America/New_York', () {
      final referenceUtc = DateTime.utc(2026, 7, 15, 21, 30);
      final riyadhRange = appointmentTodayRangeInTimezone('Asia/Riyadh', referenceUtc);
      final newYorkRange = appointmentTodayRangeInTimezone('America/New_York', referenceUtc);

      expect(riyadhRange.from, DateTime.utc(2026, 7, 15, 21));
      expect(newYorkRange.from, DateTime.utc(2026, 7, 15, 4));
      expect(riyadhRange.from, isNot(equals(newYorkRange.from)));
      expect(riyadhRange.to.difference(riyadhRange.from), const Duration(days: 1));
      expect(newYorkRange.to.difference(newYorkRange.from), const Duration(days: 1));
    });
  });
}
