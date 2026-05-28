import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';

void main() {
  group('appointmentTodayRange', () {
    test('trivial: local midnight maps to UTC day bounds', () {
      final reference = DateTime(2026, 6, 15, 14, 30);
      final range = appointmentTodayRange(reference);

      expect(range.from, DateTime(2026, 6, 15).toUtc());
      expect(range.to, DateTime(2026, 6, 16).toUtc());
    });

    test('edge case: end is exclusive', () {
      final range = appointmentTodayRange(DateTime(2026, 1, 1));
      expect(appointmentStartTimeIsWithinRange(range.to.subtract(const Duration(microseconds: 1)), range), isTrue);
      expect(appointmentStartTimeIsWithinRange(range.to, range), isFalse);
    });
  });

  group('sortAppointmentsByStartTime', () {
    AppointmentListItem item(String id, DateTime start) {
      return AppointmentListItem(
        id: id,
        patientId: 'p',
        patientName: 'Patient',
        startTime: start,
        endTime: start.add(const Duration(minutes: 20)),
        type: AppointmentType.planned,
        status: AppointmentStatus.scheduled,
      );
    }

    test('advanced: sorts ascending by start_time', () {
      final late = item('late', DateTime.utc(2026, 6, 1, 15));
      final early = item('early', DateTime.utc(2026, 6, 1, 9));
      final mid = item('mid', DateTime.utc(2026, 6, 1, 11));

      final sorted = sortAppointmentsByStartTime([late, early, mid]);
      expect(sorted.map((e) => e.id).toList(), ['early', 'mid', 'late']);
    });

    test('regression: empty list stays empty', () {
      expect(sortAppointmentsByStartTime(const []), isEmpty);
    });
  });
}
