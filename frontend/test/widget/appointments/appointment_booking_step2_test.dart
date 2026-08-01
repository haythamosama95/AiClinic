import 'package:ai_clinic/core/ui/components/app_progress.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_booking_slots.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_step2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_calendar_test_support.dart';
import 'detail_widget_test_harness.dart';

void main() {
  group('AppointmentBookingStep2', () {
    testWidgets('trivial: renders day picker and date picker keys', (tester) async {
      final today = detailHarnessFixedNow;
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep2(
              patientName: 'Patient',
              branchName: 'Main',
              preferredDoctorName: 'Dr. Ada',
              hasPreferredDoctor: true,
              today: today,
              selectedDate: today,
              selectedSlotStart: null,
              slots: [
                AppointmentBookingTimeSlot(
                  start: today.add(const Duration(hours: 1)),
                  label: '11:00 AM',
                  status: AppointmentBookingSlotStatus.available,
                  availableDoctorIds: [calendarTestDoctorAId],
                ),
              ],
              loadingSlots: false,
              slotMinutes: 30,
              onDateSelected: (_) {},
              onSlotSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('appointment_booking_step2_day')), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_step2_date')), findsOneWidget);
    });

    testWidgets('advanced: tapping slot fires onSlotSelected', (tester) async {
      final today = detailHarnessFixedNow;
      AppointmentBookingTimeSlot? selected;
      final slot = AppointmentBookingTimeSlot(
        start: today.add(const Duration(hours: 1)),
        label: '11:00 AM',
        status: AppointmentBookingSlotStatus.available,
        availableDoctorIds: [calendarTestDoctorAId],
      );

      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep2(
              patientName: 'Patient',
              branchName: 'Main',
              preferredDoctorName: 'Dr. Ada',
              hasPreferredDoctor: true,
              today: today,
              selectedDate: today,
              selectedSlotStart: null,
              slots: [slot],
              loadingSlots: false,
              slotMinutes: 30,
              onDateSelected: (_) {},
              onSlotSelected: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('11:00 AM'));
      await tester.pump();

      expect(selected, slot);
    });

    testWidgets('trivial: loading shows progress indicator', (tester) async {
      final today = detailHarnessFixedNow;
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep2(
              patientName: 'Patient',
              branchName: 'Main',
              preferredDoctorName: null,
              hasPreferredDoctor: false,
              today: today,
              selectedDate: today,
              selectedSlotStart: null,
              slots: const [],
              loadingSlots: true,
              slotMinutes: 30,
              onDateSelected: (_) {},
              onSlotSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AppProgress), findsWidgets);
    });

    testWidgets('invalid state: date and time errors render', (tester) async {
      final today = detailHarnessFixedNow;
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep2(
              patientName: 'Patient',
              branchName: 'Main',
              preferredDoctorName: null,
              hasPreferredDoctor: false,
              today: today,
              selectedDate: today,
              selectedSlotStart: null,
              slots: const [],
              loadingSlots: false,
              slotMinutes: 30,
              dateError: 'Pick a day for the appointment.',
              timeError: 'Choose an available time slot.',
              onDateSelected: (_) {},
              onSlotSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Pick a day for the appointment.'), findsOneWidget);
      expect(find.text('Choose an available time slot.'), findsOneWidget);
    });

    testWidgets('edge case: empty slots day builds without throwing', (tester) async {
      final today = detailHarnessFixedNow;
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep2(
              patientName: 'Patient',
              branchName: 'Main',
              preferredDoctorName: null,
              hasPreferredDoctor: false,
              today: today,
              selectedDate: today,
              selectedSlotStart: null,
              slots: const [],
              loadingSlots: false,
              slotMinutes: 30,
              onDateSelected: (_) {},
              onSlotSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LEGEND'), findsOneWidget);
    });

    testWidgets('edge case: locked slot is not selectable', (tester) async {
      final today = detailHarnessFixedNow;
      var tapped = false;
      final locked = AppointmentBookingTimeSlot(
        start: today.add(const Duration(hours: 2)),
        label: '12:00 PM',
        status: AppointmentBookingSlotStatus.locked,
        availableDoctorIds: const [],
      );

      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep2(
              patientName: 'Patient',
              branchName: 'Main',
              preferredDoctorName: null,
              hasPreferredDoctor: false,
              today: today,
              selectedDate: today,
              selectedSlotStart: null,
              slots: [locked],
              loadingSlots: false,
              slotMinutes: 30,
              onDateSelected: (_) {},
              onSlotSelected: (_) => tapped = true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('12:00 PM'));
      await tester.pump();
      expect(tapped, isFalse);
    });
  });
}
