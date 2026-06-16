import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/appointment_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_booking_sheet_test_support.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('CAL-K — integration and network', () {
    testWidgets('CAL-K01: offline open shows error state with retry', (tester) async {
      final client = OfflineAppointmentRpcClient();

      await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), rpcClient: client);
      await settleCalendarWidgetTest(tester);

      expect(find.textContaining('Could not load appointments'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(SfCalendar), findsOneWidget);
      expect(client.rpcCallCounts['list_appointments'], 1);
    });

    testWidgets('CAL-K02: offline booking submit shows user-friendly error without partial state', (tester) async {
      suppressBookingSheetListTileNoise();
      final client = OfflineAppointmentRpcClient(offlineFunctions: {'create_appointment'});
      final patient = samplePatientListItem(fullName: 'Offline Patient');
      final slotStart = appointmentTestStartTime(daysAhead: 7);

      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 30)),
        patientRepository: FakePatientRepository(patients: [patient]),
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await searchAndSelectPatient(tester, query: 'Offl', patientName: patient.fullName);
      await tapBookingSubmit(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Network unreachable'), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_submit')), findsOneWidget);
      expect(client.createAppointmentCalls, isEmpty);
    });

    testWidgets('CAL-K03: slow reschedule RPC blocks duplicate moves while in flight', (tester) async {
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

      await invokeCalendarDrag(tester, appointment: appointment, droppingTime: firstTarget, draggingTime: firstTarget);
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

    testWidgets('CAL-K04: calendar refresh while booking sheet open keeps sheet functional', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 16, 8, 0)), () async {
        suppressBookingSheetListTileNoise();
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Refresh During Book', branchId: calendarTestBranchAId);

        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthStateWithCreate(),
          rpcClient: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await waitForCalendarLoaded(tester);

        await tester.tap(find.text('Book Appointment'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await waitForBookingSheetReady(tester);

        final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
        await container.read(appointmentCalendarProvider.notifier).refresh();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const Key('appointment_booking_submit')), findsOneWidget);
        expect(find.text('Book appointment'), findsWidgets);

        await searchAndSelectPatient(tester, query: 'During', patientName: patient.fullName);
        expect(find.byKey(const Key('patient_picker_clear')), findsOneWidget);
        expect(find.textContaining('Duration:'), findsOneWidget);
        expect(find.text('Settings unavailable'), findsNothing);
      });
    });

    testWidgets('CAL-K05: refresh after external booking shows new appointment tile', (tester) async {
      final start = appointmentTestStartTime();
      final client = AppointmentRpcTestClient()
        ..rpcResults['list_appointments'] = {
          'success': true,
          'data': {
            'items': [appointmentRpcDefaultListItem(startLocal: start)],
          },
        };

      await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
      final container = await waitForCalendarLoaded(tester);

      expect(container.read(appointmentCalendarProvider).items, hasLength(1));

      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [
            appointmentRpcDefaultListItem(startLocal: start),
            appointmentRpcDefaultListItem(
              patientName: 'Tab B Patient',
              id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
              startLocal: start.add(const Duration(hours: 2)),
            ),
          ],
        },
      };

      await container.read(appointmentCalendarProvider.notifier).refresh();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final items = container.read(appointmentCalendarProvider).items;
        if (items.length == 2) {
          break;
        }
      }
      await settleCalendarWidgetTest(tester);

      final items = container.read(appointmentCalendarProvider).items;
      expect(items, hasLength(2));
      expect(items.any((item) => item.patientName == 'Tab B Patient'), isTrue);
    });

    test('CAL-K06: settings payload without max_duration_minutes parses without crash', () {
      final settings = AppointmentSettings.fromRpcData({'default_duration_minutes': 30, 'min_duration_minutes': 5});

      expect(settings, isNotNull);
      expect(settings!.maxDurationMinutes, isNull);
      expect(settings.defaultDurationMinutes, 30);
    });
  });
}
