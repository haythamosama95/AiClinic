import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/appointment_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_booking_sheet_test_support.dart';

void main() {
  group('CAL-A04 — booking permissions', () {
    testWidgets('create permission: valid submit creates appointment and shows success toast', (tester) async {
      final client = AppointmentRpcTestClient();
      final patient = samplePatientListItem(fullName: 'Booking Patient');
      final slotStart = appointmentTestStartTime(daysAhead: 7);
      final slotEnd = slotStart.add(const Duration(minutes: 30));

      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotEnd,
        patientRepository: FakePatientRepository(patients: [patient]),
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await submitValidBooking(tester, patient: patient, searchQuery: 'Book');

      expect(client.createAppointmentCalls, hasLength(1));
      expect(client.createAppointmentCalls.single['p_patient_id'], patient.id);
      expect(find.text('Appointment booked successfully.'), findsOneWidget);
    });
  });

  group('CAL-E — booking sheet', () {
    testWidgets('CAL-E03: settings load shows default duration from RPC', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['get_appointment_settings'] = {
          'success': true,
          'data': {
            'default_duration_minutes': 45,
            'min_duration_minutes': 5,
            'working_schedule': {
              'days': [
                for (final day in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'])
                  {'day': day, 'is_working_day': true, 'open_time': '09:00', 'close_time': '17:00'},
                {'day': 'sunday', 'is_working_day': false},
              ],
            },
          },
        };

      final slotStart = appointmentTestStartTime(daysAhead: 7);
      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 45)),
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      expect(find.text('Duration: 45 min'), findsOneWidget);
      expect(find.textContaining('Branch hours:'), findsOneWidget);
    });

    testWidgets('CAL-E04: settings error shows retry path', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['get_appointment_settings'] = {
          'success': false,
          'error_code': 'INTERNAL',
          'error_message': 'Settings unavailable',
        };

      final slotStart = appointmentTestStartTime(daysAhead: 7);
      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 30)),
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      expect(find.text('Settings unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      client.rpcResults['get_appointment_settings'] = {
        'success': true,
        'data': {'default_duration_minutes': 30, 'min_duration_minutes': 5},
      };
      await tester.tap(find.text('Retry'));
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_booking_submit')), findsOneWidget);
    });

    testWidgets('CAL-E05: patient search debounces and selects result', (tester) async {
      final client = AppointmentRpcTestClient();
      final patient = samplePatientListItem(fullName: 'Alice Searchable');
      final repo = FakePatientRepository(patients: [patient], searchDelay: const Duration(milliseconds: 100));

      final slotStart = appointmentTestStartTime(daysAhead: 7);
      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 30)),
        patientRepository: repo,
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), 'Ali');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(repo.searchCallCount, 1);
      expect(repo.lastQuery, 'Ali');
      expect(find.text('Alice Searchable'), findsOneWidget);

      await tester.tap(find.text('Alice Searchable'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Alice Searchable'), findsWidgets);
      expect(find.byKey(const Key('patient_picker_clear')), findsOneWidget);
    });

    testWidgets('CAL-E06: short patient query does not invoke RPC', (tester) async {
      final client = AppointmentRpcTestClient();
      final repo = FakePatientRepository(patients: [samplePatientListItem()]);

      final slotStart = appointmentTestStartTime(daysAhead: 7);
      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 30)),
        patientRepository: repo,
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), 'Al');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(PatientSearchQuery.canInvokeRpc('Al'), isFalse);
      expect(repo.searchCallCount, 0);
      expect(find.byKey(const Key('patient_picker_result_0')), findsNothing);
    });

    testWidgets('CAL-E07: submit without patient shows validation error', (tester) async {
      final client = AppointmentRpcTestClient();
      final slotStart = appointmentTestStartTime(daysAhead: 7);

      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 30)),
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await tapBookingSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Select a patient.'), findsOneWidget);
      expect(client.createAppointmentCalls, isEmpty);
    });

    testWidgets('CAL-E08: past start time is rejected', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 15, 12, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Past Slot Patient');
        final slotStart = bookingTestMonday(hour: 10);
        final slotEnd = slotStart.add(const Duration(minutes: 30));

        await pumpAppointmentBookingSheet(
          tester,
          client: client,
          slotStart: slotStart,
          slotEnd: slotEnd,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await waitForBookingSheetReady(tester);
        await tester.pumpAndSettle();

        await searchAndSelectPatient(tester, query: 'Past', patientName: patient.fullName);
        await tapBookingSubmit(tester);
        await tester.pumpAndSettle();

        expect(find.text('Start time must be in the future.'), findsOneWidget);
        expect(client.createAppointmentCalls, isEmpty);
      });
    });

    testWidgets('CAL-E09: outside working hours is rejected', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['get_appointment_settings'] = {
          'success': true,
          'data': {
            'default_duration_minutes': 30,
            'min_duration_minutes': 5,
            'working_schedule': {
              'days': [
                for (final day in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'])
                  {'day': day, 'is_working_day': true, 'open_time': '09:00', 'close_time': '17:00'},
                {'day': 'sunday', 'is_working_day': false},
              ],
            },
          },
        };
      final patient = samplePatientListItem(fullName: 'Late Slot Patient');
      final day = appointmentTestStartTime(daysAhead: 7);
      final lateStart = DateTime(day.year, day.month, day.day, 18, 0);

      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: lateStart,
        slotEnd: lateStart.add(const Duration(minutes: 30)),
        patientRepository: FakePatientRepository(patients: [patient]),
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await searchAndSelectPatient(tester, query: 'Late', patientName: patient.fullName);
      await tapBookingSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('within branch working hours'), findsOneWidget);
      expect(client.createAppointmentCalls, isEmpty);
    });

    testWidgets('CAL-E10: duration below minimum is rejected', (tester) async {
      final client = AppointmentRpcTestClient();
      final patient = samplePatientListItem(fullName: 'Short Duration Patient');
      final slotStart = appointmentTestStartTime(daysAhead: 7);

      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 2)),
        patientRepository: FakePatientRepository(patients: [patient]),
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await searchAndSelectPatient(tester, query: 'Short', patientName: patient.fullName);
      await tapBookingSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Duration must be at least 5 minutes.'), findsOneWidget);
      expect(client.createAppointmentCalls, isEmpty);
    });

    testWidgets('CAL-E11: happy path closes sheet and shows success toast', (tester) async {
      final client = AppointmentRpcTestClient();
      final patient = samplePatientListItem(fullName: 'Happy Path Patient');
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

      await submitValidBooking(tester, patient: patient, searchQuery: 'Happy');

      expect(find.text('Appointment booked successfully.'), findsOneWidget);
      expect(client.createAppointmentCalls, hasLength(1));
    });

    testWidgets('CAL-E12: schedule conflict keeps form open with inline message', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'SCHEDULE_CONFLICT',
          'error_message': 'Overlap',
        };
      final patient = samplePatientListItem(fullName: 'Conflict Patient');
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

      await submitValidBooking(tester, patient: patient, searchQuery: 'Conf');

      expect(find.text('This time overlaps another booked slot. Choose a different slot.'), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_submit')), findsOneWidget);
      expect(client.createAppointmentCalls, hasLength(1));
    });

    testWidgets('CAL-E13: tapping scrim dismisses sheet without creating appointment', (tester) async {
      final client = AppointmentRpcTestClient();
      final patient = samplePatientListItem();
      final slotStart = appointmentTestStartTime(daysAhead: 7);

      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 30)),
        patientRepository: FakePatientRepository(patients: [patient]),
        useModalOverlay: true,
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), 'Test');
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Book appointment'), findsNothing);
      expect(client.createAppointmentCalls, isEmpty);
    });

    testWidgets('CAL-E14: rapid double submit creates only one appointment', (tester) async {
      final client = SlowCreateAppointmentRpcClient();
      final patient = samplePatientListItem(fullName: 'Double Submit Patient');
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

      await searchAndSelectPatient(tester, query: 'Double', patientName: patient.fullName);
      await tapBookingSubmit(tester);
      await tapBookingSubmit(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(client.createAppointmentCalls, hasLength(1));
    });

    testWidgets('CAL-E15: booking without doctor sends null doctor id', (tester) async {
      final client = AppointmentRpcTestClient();
      final patient = samplePatientListItem(fullName: 'No Doctor Patient');
      final slotStart = appointmentTestStartTime(daysAhead: 7);

      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: slotStart.add(const Duration(minutes: 30)),
        patientRepository: FakePatientRepository(patients: [patient]),
        doctors: calendarTestDoctors,
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await submitValidBooking(tester, patient: patient, searchQuery: 'No Doc');

      final params = client.createAppointmentCalls.single;
      expect(params['p_doctor_id'], isNull);
    });

    testWidgets('CAL-E17: duration over 240 minutes succeeds without cap', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['get_appointment_settings'] = {
          'success': true,
          'data': {
            'default_duration_minutes': 30,
            'min_duration_minutes': 5,
            'working_schedule': {
              'days': [
                for (final day in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'])
                  {'day': day, 'is_working_day': true, 'open_time': '06:00', 'close_time': '23:59'},
              ],
            },
          },
        };
      final patient = samplePatientListItem(fullName: 'Long Duration Patient');
      final slotStart = appointmentTestStartTime(daysAhead: 7);
      final longEnd = slotStart.add(const Duration(minutes: 300));

      await pumpAppointmentBookingSheet(
        tester,
        client: client,
        slotStart: slotStart,
        slotEnd: longEnd,
        patientRepository: FakePatientRepository(patients: [patient]),
      );
      await waitForBookingSheetReady(tester);
      await tester.pumpAndSettle();

      await searchAndSelectPatient(tester, query: 'Long', patientName: patient.fullName);
      expect(find.text('Duration: 300 min'), findsOneWidget);
      await tapBookingSubmit(tester);
      await tester.pumpAndSettle();

      expect(client.createAppointmentCalls, hasLength(1));
      expect(client.createAppointmentCalls.single['p_duration_minutes'], 300);
      expect(find.text('Appointment booked successfully.'), findsOneWidget);
    });
  });
}
