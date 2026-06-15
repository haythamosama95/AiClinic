import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appointmentCalendarFetchBounds', () {
    final focus = DateTime(2026, 6, 15); // Monday

    test('day mode returns single local day as UTC window', () {
      final dayStart = DateTime(focus.year, focus.month, focus.day);
      final (from, to) = appointmentCalendarFetchBounds(focus, AppointmentCalendarMode.day);
      expect(from, dayStart.toUtc());
      expect(to, dayStart.add(const Duration(days: 1)).toUtc());
    });

    test('week mode returns Monday through next Monday', () {
      final dayStart = DateTime(focus.year, focus.month, focus.day);
      final weekStart = dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
      final (from, to) = appointmentCalendarFetchBounds(focus, AppointmentCalendarMode.week);
      expect(from, weekStart.toUtc());
      expect(to, weekStart.add(const Duration(days: 7)).toUtc());
    });

    test('month mode returns full calendar month', () {
      final monthStart = DateTime(focus.year, focus.month, 1);
      final monthEnd = DateTime(focus.year, focus.month + 1, 1);
      final (from, to) = appointmentCalendarFetchBounds(focus, AppointmentCalendarMode.month);
      expect(from, monthStart.toUtc());
      expect(to, monthEnd.toUtc());
    });
  });

  group('appointmentCalendarPreviousFocus', () {
    test('month navigation rolls to previous month', () {
      final previous = appointmentCalendarPreviousFocus(DateTime(2026, 3, 15), AppointmentCalendarMode.month);
      expect(previous, DateTime(2026, 2, 15));
    });
  });

  group('appointmentCalendarNextFocus', () {
    test('week navigation advances seven days', () {
      final next = appointmentCalendarNextFocus(DateTime(2026, 6, 15), AppointmentCalendarMode.week);
      expect(next, DateTime(2026, 6, 22));
    });
  });
}
