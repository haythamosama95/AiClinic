import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';

void main() {
  setUpAll(ensureAppointmentTimezonesInitialized);

  group('appointmentTodayRangeInTimezone', () {
    test('trivial: UTC midnight maps to UTC day bounds', () {
      final reference = DateTime.utc(2026, 6, 15, 14, 30);
      final range = appointmentTodayRangeInTimezone('UTC', reference);

      expect(range.from, DateTime.utc(2026, 6, 15));
      expect(range.to, DateTime.utc(2026, 6, 16));
    });

    test('regression: org timezone shifts today window vs UTC midnight', () {
      // 2026-06-02 06:00 UTC is still June 1 in America/Los_Angeles.
      final referenceUtc = DateTime.utc(2026, 6, 2, 6);
      final orgRange = appointmentTodayRangeInTimezone('America/Los_Angeles', referenceUtc);
      final utcRange = appointmentTodayRangeInTimezone('UTC', referenceUtc);

      expect(orgRange.from, DateTime.utc(2026, 6, 1, 7)); // June 1 00:00 PDT
      expect(utcRange.from, DateTime.utc(2026, 6, 2));
      expect(orgRange.from, isNot(equals(utcRange.from)));
    });

    test('edge case: end is exclusive', () {
      final range = appointmentTodayRangeInTimezone('UTC', DateTime.utc(2026, 1, 1));
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
