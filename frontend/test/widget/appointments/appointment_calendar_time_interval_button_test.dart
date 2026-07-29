import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_time_interval_button.dart';

import 'calendar_widget_test_harness.dart';

void main() {
  Future<SpyAppointmentCalendarController> pumpIntervalButton(
    WidgetTester tester, {
    int initialMinutes = 30,
  }) async {
    final state = defaultCalendarState(timeIntervalMinutes: initialMinutes, mode: AppointmentCalendarMode.day);
    return pumpCalendarSurface(
      tester,
      calendarState: state,
      child: const Center(child: AppointmentCalendarTimeIntervalButton()),
      surfaceSize: const Size(600, 300),
    );
  }

  testWidgets('trivial: CAL-INTERVAL-01 popover lists supported intervals', (tester) async {
    await pumpIntervalButton(tester);
    await tester.pump();

    await tester.tap(find.text('30m'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Time interval'), findsOneWidget);
    expect(find.text('15 minutes'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('1 hour'), findsOneWidget);
  });

  testWidgets('advanced: CAL-INTERVAL-02 current interval is indicated as selected', (tester) async {
    await pumpIntervalButton(tester, initialMinutes: 30);
    await tester.pump();

    await tester.tap(find.text('30m'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('advanced: CAL-INTERVAL-03 choosing an interval calls setTimeIntervalMinutes', (tester) async {
    final spy = await pumpIntervalButton(tester, initialMinutes: 30);
    await tester.pump();

    await tester.tap(find.text('30m'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('15 minutes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(spy.setTimeIntervalCallCount, 1);
    expect(spy.lastSetTimeIntervalMinutes, 15);
    expect(find.text('15m'), findsOneWidget);
  });

  testWidgets('edge case: CAL-INTERVAL-04 re-selecting current interval is harmless', (tester) async {
    final spy = await pumpIntervalButton(tester, initialMinutes: 60);
    await tester.pump();

    await tester.tap(find.text('60m'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('1 hour'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(spy.setTimeIntervalCallCount, 1);
    expect(spy.lastSetTimeIntervalMinutes, 60);
    expect(find.text('60m'), findsOneWidget);
  });
}
