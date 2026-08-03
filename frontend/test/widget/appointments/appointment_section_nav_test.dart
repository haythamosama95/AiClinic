import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/appointments/presentation/models/appointment_section.dart';

import 'calendar_widget_test_harness.dart';

void main() {
  testWidgets('trivial: CAL-NAV-01 renders a tab per AppointmentSection with active selected', (tester) async {
    await pumpAppointmentSectionNav(tester, activeSection: AppointmentSection.calendar);
    await tester.pump();

    expect(find.text('Hub'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.bySemanticsLabel('Appointments sections'), findsOneWidget);
  });

  testWidgets('advanced: CAL-NAV-02 tapping Hub navigates to /appointments/calendar', (tester) async {
    final router = await pumpAppointmentSectionNav(
      tester,
      activeSection: AppointmentSection.queue,
      initialLocation: AppRoutes.appointmentsQueue,
    );
    await tester.pump();

    await tester.tap(find.text('Hub'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(router.state.uri.toString(), AppRoutes.appointmentsCalendar);
  });

  testWidgets('advanced: CAL-NAV-03 tapping Queue navigates to /appointments/queue', (tester) async {
    final router = await pumpAppointmentSectionNav(tester, activeSection: AppointmentSection.calendar);
    await tester.pump();

    await tester.tap(find.text('Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(router.state.uri.toString(), AppRoutes.appointmentsQueue);
    expect(find.text('stub:queue'), findsOneWidget);
  });

  testWidgets('advanced: CAL-NAV-04 tapping Calendar navigates to /appointments/calendar', (tester) async {
    final router = await pumpAppointmentSectionNav(
      tester,
      activeSection: AppointmentSection.hub,
      initialLocation: AppRoutes.appointments,
    );
    await tester.pump();

    await tester.tap(find.text('Calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(router.state.uri.toString(), AppRoutes.appointmentsCalendar);
  });

  testWidgets('advanced: CAL-NAV-05 tapping Book navigates to /appointments/book', (tester) async {
    final router = await pumpAppointmentSectionNav(tester, activeSection: AppointmentSection.calendar);
    await tester.pump();

    await tester.tap(find.text('Book'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(router.state.uri.toString(), AppRoutes.appointmentsBook);
    expect(find.text('stub:book'), findsOneWidget);
  });
}
