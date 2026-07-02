import 'package:flutter_test/flutter_test.dart';

import '../../helpers/appointment_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('AppointmentCalendarPage resize', () {
    group('CAL-H — resize (widget)', () {
      testWidgets('CAL-H01: extending end opens dialog and calls reschedule RPC', (tester) async {
        final start = appointmentTestStartTime();
        final end = start.add(const Duration(minutes: 30));
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)]);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final extendedEnd = end.add(const Duration(minutes: 30));

        await invokeCalendarResize(tester, appointment: appointment, startTime: start, endTime: extendedEnd);

        expect(find.text('Move appointment?'), findsOneWidget);
        await confirmRescheduleDialog(tester);

        expect(client.rpcCallCounts['reschedule_appointment'], 1);
      });

      testWidgets('CAL-H02: shrinking to 30 minutes succeeds when valid', (tester) async {
        final start = appointmentTestStartTime();
        final end = start.add(const Duration(hours: 1));
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(id: 'long-appt', startLocal: start)]);
        client.rpcResults['list_appointments'] = {
          'success': true,
          'data': {
            'items': [
              {
                ...appointmentRpcDefaultListItem(id: 'long-appt', startLocal: start),
                'end_time': end.toUtc().toIso8601String(),
              },
            ],
          },
        };

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final shrunkEnd = start.add(const Duration(minutes: 30));

        await invokeCalendarResize(tester, appointment: appointment, startTime: start, endTime: shrunkEnd);

        expect(find.text('Move appointment?'), findsOneWidget);
        await confirmRescheduleDialog(tester);

        expect(client.rpcCallCounts['reschedule_appointment'], 1);
      });

      testWidgets('CAL-H06: no-op resize back to original skips RPC', (tester) async {
        final start = appointmentTestStartTime();
        final end = start.add(const Duration(minutes: 30));
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)]);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);

        await invokeCalendarResize(tester, appointment: appointment, startTime: start, endTime: end);

        expect(find.text('Move appointment?'), findsNothing);
        expect(client.rpcCallCounts['reschedule_appointment'] ?? 0, 0);
      });

      testWidgets('CAL-H08: resize works after a completed drag reschedule', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)]);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final dragTarget = DateTime(start.year, start.month, start.day, 11, 0);

        await invokeCalendarDrag(tester, appointment: appointment, droppingTime: dragTarget, draggingTime: dragTarget);
        await confirmRescheduleDialog(tester);
        await tester.pump(const Duration(milliseconds: 300));

        final movedAppointment = firstCalendarAppointment(tester);
        final extendedEnd = dragTarget.add(const Duration(hours: 1));

        await invokeCalendarResize(
          tester,
          appointment: movedAppointment,
          startTime: dragTarget,
          endTime: extendedEnd,
          updateTimes: [extendedEnd],
        );
        await confirmRescheduleDialog(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(client.rpcCallCounts['reschedule_appointment'], 2);
      });
    });
  });
}
