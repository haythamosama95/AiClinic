import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_page_shell.dart';

import 'calendar_widget_test_harness.dart';

void main() {
  testWidgets('trivial: CAL-SHELL-01 renders default Calendar title and description', (tester) async {
    await pumpCalendarSurface(
      tester,
      child: const AppointmentPageShell(
        child: Text('calendar body'),
      ),
    );
    await tester.pump();

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('View and manage scheduled visits across your branches.'), findsOneWidget);
    expect(find.text('calendar body'), findsOneWidget);
  });

  testWidgets('trivial: CAL-SHELL-02 renders custom title and description', (tester) async {
    await pumpCalendarSurface(
      tester,
      child: const AppointmentPageShell(
        title: 'Custom title',
        description: 'Custom description',
        child: Text('inner'),
      ),
    );
    await tester.pump();

    expect(find.text('Custom title'), findsOneWidget);
    expect(find.text('Custom description'), findsOneWidget);
  });

  testWidgets('trivial: CAL-SHELL-03 renders actions when supplied', (tester) async {
    await pumpCalendarSurface(
      tester,
      child: AppointmentPageShell(
        actions: AppButton(onPressed: () {}, child: const Text('Header action')),
        child: const Text('inner'),
      ),
    );
    await tester.pump();

    expect(find.text('Header action'), findsOneWidget);
  });

  testWidgets('trivial: CAL-SHELL-04 omits actions when null', (tester) async {
    await pumpCalendarSurface(
      tester,
      child: const AppointmentPageShell(
        child: Text('inner'),
      ),
    );
    await tester.pump();

    expect(find.byType(AppButton), findsNothing);
  });
}
