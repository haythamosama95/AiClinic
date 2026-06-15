import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentCalendarDisplay', () {
    final schedule = BranchWorkingSchedule.defaultSchedule();

    test('day layout uses configured open and close hours', () {
      final layout = AppointmentCalendarDisplay.timeSlotLayout(
        schedule: schedule,
        mode: AppointmentCalendarMode.day,
        focusDate: DateTime(2026, 6, 4), // Thursday
      );

      expect(layout.startHour, 9);
      expect(layout.endHour, 17);
      expect(layout.timeIntervalHeight, greaterThanOrEqualTo(AppointmentCalendarDisplay.minTimeIntervalHeight));
    });

    test('week layout spans union of working-day hours', () {
      final layout = AppointmentCalendarDisplay.timeSlotLayout(
        schedule: schedule,
        mode: AppointmentCalendarMode.week,
        focusDate: DateTime(2026, 6, 4),
      );

      expect(layout.startHour, 9);
      expect(layout.endHour, 17);
      expect(layout.shadeRegions, isNotEmpty);
    });

    test('tall viewport expands slot height to fill available space', () {
      final layout = AppointmentCalendarDisplay.timeSlotLayout(
        schedule: schedule,
        mode: AppointmentCalendarMode.week,
        focusDate: DateTime(2026, 6, 4),
        viewportHeight: 800,
      );

      final slotCount =
          ((layout.endHour - layout.startHour) * 60 / AppointmentCalendarDisplay.defaultTimeIntervalMinutes).ceil();
      final expectedHeight = ((800 - AppointmentCalendarDisplay.timeSlotChromeHeight) / slotCount).clamp(
        AppointmentCalendarDisplay.minTimeIntervalHeight,
        double.infinity,
      );
      expect(layout.timeIntervalHeight, closeTo(expectedHeight, 0.01));
    });

    test('nonWorkingDays marks Sunday closed in default schedule', () {
      final closed = AppointmentCalendarDisplay.nonWorkingDays(schedule);
      expect(closed, contains(DateTime.sunday));
    });

    test('isClosedOnDate true for Sunday', () {
      expect(AppointmentCalendarDisplay.isClosedOnDate(schedule, DateTime(2026, 6, 7)), isTrue);
    });

    test('closedDatesInMonth includes Sundays', () {
      final closed = AppointmentCalendarDisplay.closedDatesInMonth(schedule, DateTime(2026, 6, 1));
      expect(closed.any((date) => date.weekday == DateTime.sunday), isTrue);
    });
  });
}
