import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_confirmed_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_widget_test_harness.dart';

void main() {
  group('AppointmentBookingConfirmedStep', () {
    testWidgets('trivial: renders booked heading and summary fields', (tester) async {
      final start = detailHarnessFixedNow.add(const Duration(hours: 2));

      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingConfirmedStep(
              patientName: 'Confirmed Patient',
              branchName: 'Main',
              startTime: start,
              durationMinutes: 45,
              doctorName: 'Dr. Ada',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Appointment booked'), findsOneWidget);
      expect(find.text('Confirmed Patient'), findsWidgets);
      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Dr. Ada'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
    });

    testWidgets('edge case: null doctorName renders Any available', (tester) async {
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingConfirmedStep(
              patientName: 'No Doctor Patient',
              branchName: 'Main',
              startTime: detailHarnessFixedNow,
              durationMinutes: 30,
              doctorName: null,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Any available'), findsOneWidget);
    });
  });
}
