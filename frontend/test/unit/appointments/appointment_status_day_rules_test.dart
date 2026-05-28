import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';

void main() {
  group('appointment status day rules', () {
    test('confirmed and cancelled do not require appointment day', () {
      expect(appointmentStatusRequiresAppointmentDay(AppointmentStatus.confirmed), isFalse);
      expect(appointmentStatusRequiresAppointmentDay(AppointmentStatus.cancelled), isFalse);
      expect(
        canTransitionToStatusOnDate(AppointmentStatus.confirmed, DateTime.utc(2099, 1, 1), DateTime(2026, 1, 1)),
        isTrue,
      );
      expect(
        canTransitionToStatusOnDate(AppointmentStatus.cancelled, DateTime.utc(2099, 1, 1), DateTime(2026, 1, 1)),
        isTrue,
      );
    });

    test('checked_in requires appointment day on or before reference', () {
      expect(appointmentStatusRequiresAppointmentDay(AppointmentStatus.checkedIn), isTrue);

      final start = DateTime(2026, 6, 1, 10);
      expect(canTransitionToStatusOnDate(AppointmentStatus.checkedIn, start, DateTime(2026, 5, 31)), isFalse);
      expect(canTransitionToStatusOnDate(AppointmentStatus.checkedIn, start, DateTime(2026, 6, 1)), isTrue);
      expect(canTransitionToStatusOnDate(AppointmentStatus.checkedIn, start, DateTime(2026, 6, 2)), isTrue);
    });

    test('appointmentCalendarDayHasArrived compares local calendar days', () {
      final start = DateTime(2026, 6, 1, 10);
      expect(appointmentCalendarDayHasArrived(start, DateTime(2026, 5, 31)), isFalse);
      expect(appointmentCalendarDayHasArrived(start, DateTime(2026, 6, 1, 23)), isTrue);
    });
  });
}
