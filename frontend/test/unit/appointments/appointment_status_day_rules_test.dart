import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';

void main() {
  setUpAll(ensureAppointmentTimezonesInitialized);

  group('appointment status day rules (org timezone)', () {
    test('confirmed and cancelled do not require appointment day', () {
      expect(appointmentStatusRequiresAppointmentDay(AppointmentStatus.confirmed), isFalse);
      expect(appointmentStatusRequiresAppointmentDay(AppointmentStatus.cancelled), isFalse);
      expect(
        canTransitionToStatusOnDate(
          AppointmentStatus.confirmed,
          DateTime.utc(2099, 1, 1),
          referenceUtc: DateTime.utc(2026, 1, 1),
        ),
        isTrue,
      );
      expect(
        canTransitionToStatusOnDate(
          AppointmentStatus.cancelled,
          DateTime.utc(2099, 1, 1),
          referenceUtc: DateTime.utc(2026, 1, 1),
        ),
        isTrue,
      );
    });

    test('checked_in requires appointment day on or before reference in org timezone', () {
      expect(appointmentStatusRequiresAppointmentDay(AppointmentStatus.checkedIn), isTrue);

      final start = DateTime.utc(2026, 6, 1, 12);
      expect(
        canTransitionToStatusOnDate(
          AppointmentStatus.checkedIn,
          start,
          organizationTimezone: 'UTC',
          referenceUtc: DateTime.utc(2026, 5, 31),
        ),
        isFalse,
      );
      expect(
        canTransitionToStatusOnDate(
          AppointmentStatus.checkedIn,
          start,
          organizationTimezone: 'UTC',
          referenceUtc: DateTime.utc(2026, 6, 1),
        ),
        isTrue,
      );
      expect(
        canTransitionToStatusOnDate(
          AppointmentStatus.checkedIn,
          start,
          organizationTimezone: 'UTC',
          referenceUtc: DateTime.utc(2026, 6, 2),
        ),
        isTrue,
      );
    });

    test('regression: device-local midnight differs from org timezone near boundary', () {
      // 2026-06-02 06:00 UTC = June 1 23:00 in America/Los_Angeles
      // Appointment at 2026-06-02 07:00 UTC = June 2 00:00 PDT (appointment day is June 2)
      const orgTz = 'America/Los_Angeles';
      final referenceUtc = DateTime.utc(2026, 6, 2, 6);
      final startTime = DateTime.utc(2026, 6, 2, 7);

      // Device-local (UTC) would treat both as June 2 -> check-in allowed.
      expect(
        canTransitionToStatusOnDate(
          AppointmentStatus.checkedIn,
          startTime,
          organizationTimezone: 'UTC',
          referenceUtc: referenceUtc,
        ),
        isTrue,
      );

      // Org timezone still on June 1 -> check-in blocked (matches backend day gate).
      expect(
        canTransitionToStatusOnDate(
          AppointmentStatus.checkedIn,
          startTime,
          organizationTimezone: orgTz,
          referenceUtc: referenceUtc,
        ),
        isFalse,
      );
    });
  });
}
