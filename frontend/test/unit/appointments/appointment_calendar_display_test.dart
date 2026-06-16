import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter/material.dart';
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

    test('doctors layout matches day layout', () {
      final dayLayout = AppointmentCalendarDisplay.timeSlotLayout(
        schedule: schedule,
        mode: AppointmentCalendarMode.day,
        focusDate: DateTime(2026, 6, 4),
      );
      final doctorsLayout = AppointmentCalendarDisplay.timeSlotLayout(
        schedule: schedule,
        mode: AppointmentCalendarMode.doctors,
        focusDate: DateTime(2026, 6, 4),
      );

      expect(doctorsLayout.startHour, dayLayout.startHour);
      expect(doctorsLayout.endHour, dayLayout.endHour);
      expect(doctorsLayout.shadeRegions, isEmpty);
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

    test('slotRangeFromTap uses tapped time in day view', () {
      final tapped = DateTime(2026, 6, 4, 10, 30);
      final range = AppointmentCalendarDisplay.slotRangeFromTap(
        tappedDate: tapped,
        schedule: schedule,
        mode: AppointmentCalendarMode.day,
      );

      expect(range.start, DateTime(2026, 6, 4, 10, 30));
      expect(range.end, DateTime(2026, 6, 4, 11, 0));
    });

    test('slotRangeFromTap uses branch open time in month view', () {
      final tapped = DateTime(2026, 6, 4);
      final range = AppointmentCalendarDisplay.slotRangeFromTap(
        tappedDate: tapped,
        schedule: schedule,
        mode: AppointmentCalendarMode.month,
      );

      expect(range.start, DateTime(2026, 6, 4, 9, 0));
      expect(range.end, DateTime(2026, 6, 4, 9, 30));
    });

    test('snapTimeToSlot rounds to nearest 30-minute slot start', () {
      expect(AppointmentCalendarDisplay.snapTimeToSlot(DateTime(2026, 6, 4, 14, 58)), DateTime(2026, 6, 4, 15, 0));
      expect(AppointmentCalendarDisplay.snapTimeToSlot(DateTime(2026, 6, 4, 15, 2)), DateTime(2026, 6, 4, 15, 0));
      expect(AppointmentCalendarDisplay.snapTimeToSlot(DateTime(2026, 6, 4, 15, 16)), DateTime(2026, 6, 4, 15, 30));
    });

    test('isAlignedToSlotGrid detects grid-aligned bounds', () {
      const slotHeight = 48.0;
      expect(
        AppointmentCalendarDisplay.isAlignedToSlotGrid(
          const Rect.fromLTWH(0, 96, 100, 48),
          slotHeight,
          timelineAxisIsHorizontal: false,
        ),
        isTrue,
      );
      expect(
        AppointmentCalendarDisplay.isAlignedToSlotGrid(
          const Rect.fromLTWH(0, 110, 100, 48),
          slotHeight,
          timelineAxisIsHorizontal: false,
        ),
        isFalse,
      );
    });

    group('CAL-I — display (unit)', () {
      test('CAL-I01: statusColor maps each appointment status', () {
        expect(AppointmentCalendarDisplay.statusColor(AppointmentStatus.scheduled), const Color(0xFF2563EB));
        expect(AppointmentCalendarDisplay.statusColor(AppointmentStatus.confirmed), const Color(0xFF0D9488));
        expect(AppointmentCalendarDisplay.statusColor(AppointmentStatus.completed), const Color(0xFF16A34A));
        expect(AppointmentCalendarDisplay.statusColor(AppointmentStatus.cancelled), const Color(0xFFDC2626));
      });

      test('CAL-I03: resourceRowStripeRegions stripes odd-indexed doctor rows', () {
        final regions = AppointmentCalendarDisplay.resourceRowStripeRegions(
          resourceIds: const ['doc-1', 'doc-2', 'doc-3'],
          focusDate: DateTime(2026, 6, 4),
          startHour: 9,
          endHour: 17,
          stripeColor: const Color(0xFFE5E7EB),
        );

        expect(regions, hasLength(1));
        expect(regions.single.resourceIds, ['doc-2']);
      });

      test('CAL-I07: filterVisibleAppointments hides appointments outside branch hours', () {
        final earlyBird = AppointmentListItem(
          id: 'early',
          patientId: 'p1',
          patientName: 'Early Bird',
          startTime: DateTime(2026, 6, 4, 7, 0),
          endTime: DateTime(2026, 6, 4, 7, 30),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        );
        final inHours = AppointmentListItem(
          id: 'ok',
          patientId: 'p2',
          patientName: 'In Hours',
          startTime: DateTime(2026, 6, 4, 10, 0),
          endTime: DateTime(2026, 6, 4, 10, 30),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        );

        final visible = AppointmentCalendarDisplay.filterVisibleAppointments([earlyBird, inHours], schedule);

        expect(visible, hasLength(1));
        expect(visible.single.id, 'ok');
      });
    });
  });
}
