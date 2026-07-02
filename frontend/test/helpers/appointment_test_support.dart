import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Start time for appointment widget tests: future weekday at 10:00 local, within 09:00–17:00.
DateTime appointmentTestStartTime({int daysAhead = 7}) {
  final now = DateTime.now();
  var day = DateTime(now.year, now.month, now.day).add(Duration(days: daysAhead));
  while (day.weekday == DateTime.sunday) {
    day = day.add(const Duration(days: 1));
  }
  return DateTime(day.year, day.month, day.day, 10, 0);
}

/// Opens the booking end-time clock picker and selects [endTime] (local, time only).
Future<void> pickBookingEndTimeInForm(WidgetTester tester, {required DateTime endTime}) async {
  await tester.tap(find.byKey(const Key('appointment_booking_pick_end')));
  await tester.pumpAndSettle();

  await _selectTimeInPicker(tester, TimeOfDay(hour: endTime.hour, minute: endTime.minute));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Opens the booking start-time clock picker and selects [startTime] (local, time only).
Future<void> pickBookingStartTimeInForm(WidgetTester tester, {DateTime? startTime}) async {
  final target = startTime ?? appointmentTestStartTime(daysAhead: 1);

  await tester.tap(find.byKey(const Key('appointment_booking_pick_start')));
  await tester.pumpAndSettle();

  await _selectTimeInPicker(tester, TimeOfDay(hour: target.hour, minute: target.minute));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _selectTimeInPicker(WidgetTester tester, TimeOfDay target) async {
  final dialog = find.byType(TimePickerDialog);
  expect(dialog, findsOneWidget);

  final inputMode = find.descendant(of: dialog, matching: find.byTooltip('Switch to text input mode'));
  if (inputMode.evaluate().isNotEmpty) {
    await tester.tap(inputMode);
    await tester.pumpAndSettle();
  }

  final periodLabel = target.period == DayPeriod.am ? 'AM' : 'PM';
  await tester.tap(find.descendant(of: dialog, matching: find.text(periodLabel)));
  await tester.pumpAndSettle();

  final hourField = find.descendant(of: dialog, matching: find.byType(TextField)).first;
  final minuteField = find.descendant(of: dialog, matching: find.byType(TextField)).last;

  await tester.enterText(hourField, target.hourOfPeriod == 0 ? '12' : '${target.hourOfPeriod}');
  await tester.enterText(minuteField, target.minute.toString().padLeft(2, '0'));
  await tester.pumpAndSettle();
}

/// Waits until [AppointmentRescheduleDialog] finished loading settings and Save is enabled.
Future<void> pumpUntilRescheduleDialogReady(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final confirmFinder = find.byKey(const Key('appointment_reschedule_confirm'));
  expect(confirmFinder, findsOneWidget);

  var attempts = 0;
  while (attempts < 50) {
    final button = tester.widget<FilledButton>(confirmFinder);
    if (button.onPressed != null) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
    attempts++;
  }

  fail('Reschedule dialog Save button did not become enabled');
}
