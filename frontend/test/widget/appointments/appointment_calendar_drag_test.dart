import 'dart:async';

import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/appointment_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('AppointmentCalendarPage drag reschedule', () {
    group('CAL-G — drag-and-drop reschedule (widget)', () {
      testWidgets('CAL-G01: happy path drag opens dialog, calls RPC, and refreshes', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)]);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final newStart = DateTime(start.year, start.month, start.day, 11, 0);

        await invokeCalendarDrag(tester, appointment: appointment, droppingTime: newStart, draggingTime: newStart);

        expect(find.text('Move appointment?'), findsOneWidget);
        await confirmRescheduleDialog(tester);

        expect(client.rpcCallCounts['reschedule_appointment'], 1);
        expect(client.rpcCallCounts['list_appointments'], greaterThan(1));
      });

      testWidgets('CAL-G03: no-op drop on same slot skips dialog and RPC', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)]);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        await invokeCalendarDrag(tester, appointment: appointment, droppingTime: start, draggingTime: start);

        expect(find.text('Move appointment?'), findsNothing);
        expect(client.rpcCallCounts['reschedule_appointment'] ?? 0, 0);
      });

      testWidgets('CAL-G05: confirmed appointment drag shows error toast and skips RPC', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([
          {...appointmentRpcDefaultListItem(startLocal: start), 'status': 'confirmed'},
        ]);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final newStart = DateTime(start.year, start.month, start.day, 11, 0);

        await invokeCalendarDrag(tester, appointment: appointment, droppingTime: newStart, draggingTime: newStart);

        expect(find.text('Move appointment?'), findsNothing);
        expect(find.textContaining('Only scheduled appointments'), findsOneWidget);
        expect(client.rpcCallCounts['reschedule_appointment'] ?? 0, 0);
      });

      testWidgets('CAL-G06: drag onto overlapping appointment shows overlap toast', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([
          appointmentRpcDefaultListItem(id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', startLocal: start),
          appointmentRpcDefaultListItem(
            id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            patientName: 'Blocked Patient',
            startLocal: start.add(const Duration(hours: 1)),
          ),
        ]);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = calendarAppointmentById(tester, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')!;
        final overlapStart = start.add(const Duration(hours: 1));

        await invokeCalendarDrag(
          tester,
          appointment: appointment,
          droppingTime: overlapStart,
          draggingTime: overlapStart,
        );

        expect(find.text('Move appointment?'), findsNothing);
        expect(find.textContaining('overlaps'), findsOneWidget);
        expect(client.rpcCallCounts['reschedule_appointment'] ?? 0, 0);
      });

      testWidgets('CAL-G10: RPC failure reverts and shows error toast', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)])
          ..rpcResults['reschedule_appointment'] = {
            'success': false,
            'error_code': 'INTERNAL',
            'error_message': 'Server unavailable',
          };

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final newStart = DateTime(start.year, start.month, start.day, 11, 0);

        await invokeCalendarDrag(tester, appointment: appointment, droppingTime: newStart, draggingTime: newStart);
        await confirmRescheduleDialog(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(client.rpcCallCounts['reschedule_appointment'], 1);
        expect(find.textContaining('Server unavailable'), findsOneWidget);
      });

      testWidgets('CAL-G11: month view disables drag and drop', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
        await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Month');
        await settleCalendarWidgetTest(tester);

        expect(calendarWidget(tester).allowDragAndDrop, isFalse);
      });

      testWidgets('CAL-G12: drag update moves preview start on data source', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)]);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final previewStart = DateTime(start.year, start.month, start.day, 11, 0);
        final calendar = calendarWidget(tester);

        calendar.onDragStart!(AppointmentDragStartDetails(appointment, null));
        await tester.pump();
        calendar.onDragUpdate!(AppointmentDragUpdateDetails(appointment, null, null, null, previewStart));
        await tester.pump();

        final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
        final preview = dataSource.appointments!.single as Appointment;
        expect(preview.startTime, previewStart);
      });

      testWidgets('CAL-G13: concurrent drag ignored while first reschedule is in flight', (tester) async {
        final start = appointmentTestStartTime();
        final client = SlowRescheduleRpcClient()
          ..rpcResults['list_appointments'] = {
            'success': true,
            'data': {
              'items': [appointmentRpcDefaultListItem(startLocal: start)],
            },
          };

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final firstTarget = DateTime(start.year, start.month, start.day, 11, 0);
        final secondTarget = DateTime(start.year, start.month, start.day, 12, 0);

        await invokeCalendarDrag(
          tester,
          appointment: appointment,
          droppingTime: firstTarget,
          draggingTime: firstTarget,
        );
        await confirmRescheduleDialog(tester);

        await invokeCalendarDrag(
          tester,
          appointment: appointment,
          droppingTime: secondTarget,
          draggingTime: secondTarget,
        );

        expect(find.text('Move appointment?'), findsNothing);

        await tester.pump(const Duration(milliseconds: 500));

        expect(client.rpcCallCounts['reschedule_appointment'], 1);
      });

      testWidgets('CAL-G15: server SCHEDULE_CONFLICT shows message and skips refresh success toast', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)])
          ..rpcResults['reschedule_appointment'] = {
            'success': false,
            'error_code': 'SCHEDULE_CONFLICT',
            'error_message': 'Slot taken',
          };

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');

        final appointment = firstCalendarAppointment(tester);
        final newStart = DateTime(start.year, start.month, start.day, 11, 0);

        await invokeCalendarDrag(tester, appointment: appointment, droppingTime: newStart, draggingTime: newStart);
        await confirmRescheduleDialog(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.textContaining('overlaps another booked slot'), findsOneWidget);
        expect(client.rpcCallCounts['reschedule_appointment'], 1);
      });
    });
  });
}
