import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pickShiftDateInForm(WidgetTester tester, {DateTime? shiftDate}) async {
  final now = clock.now();
  final target = shiftDate ?? DateTime(now.year, now.month, now.day + 3);

  await tester.tap(find.byKey(const Key('shift_date_field')));
  await tester.pumpAndSettle();

  await _selectCalendarDay(tester, target);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> pickShiftStartTimeInForm(WidgetTester tester, {TimeOfDay? startTime}) async {
  await tester.tap(find.byKey(const Key('shift_start_time_field')));
  await tester.pumpAndSettle();
  await _selectTimeInPicker(tester, startTime ?? const TimeOfDay(hour: 9, minute: 0));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> pickShiftEndTimeInForm(WidgetTester tester, {TimeOfDay? endTime}) async {
  await tester.tap(find.byKey(const Key('shift_end_time_field')));
  await tester.pumpAndSettle();
  await _selectTimeInPicker(tester, endTime ?? const TimeOfDay(hour: 17, minute: 0));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> fillMinimalShiftCreateForm(WidgetTester tester) async {
  await pickShiftDateInForm(tester);
  await pickShiftStartTimeInForm(tester);
  await pickShiftEndTimeInForm(tester);
}

Future<void> _selectCalendarDay(WidgetTester tester, DateTime target) async {
  const maxMonthSteps = 24;
  for (var step = 0; step < maxMonthSteps; step++) {
    final dayFinder = find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('${target.day}'));
    if (dayFinder.evaluate().isNotEmpty) {
      await tester.tap(dayFinder.last);
      await tester.pumpAndSettle();
      return;
    }
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
  }
  fail('Could not select ${target.year}-${target.month}-${target.day} in date picker.');
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
