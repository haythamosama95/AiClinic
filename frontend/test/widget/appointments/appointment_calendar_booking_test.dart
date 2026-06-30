import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_booking_flow.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/appointment_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_booking_sheet_test_support.dart';
import 'appointment_calendar_test_support.dart';

/// After create, returns an updated appointment list for refresh assertions.
class BookingRefreshRpcClient extends AppointmentRpcTestClient {
  BookingRefreshRpcClient({this.bookedPatientName = 'Newly Booked Patient'});

  final String bookedPatientName;
  var refreshListAfterCreate = true;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    final result = super.rpc<T>(fn, params: params, get: get);
    if (fn == 'create_appointment' && refreshListAfterCreate) {
      final startLocal = appointmentTestStartTime(daysAhead: 7);
      rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [
            appointmentRpcDefaultListItem(),
            appointmentRpcDefaultListItem(
              patientName: bookedPatientName,
              id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              startLocal: startLocal,
            ),
          ],
        },
      };
    }
    return result;
  }
}

/// Tracks sequential sheet + simplified bookings on the same day for coexist tests.
class CoexistBookingRpcClient extends AppointmentRpcTestClient {
  CoexistBookingRpcClient({required this.slotStart}) : super() {
    rpcResults['list_appointments'] = {
      'success': true,
      'data': {'items': <Map<String, dynamic>>[]},
    };
  }

  final DateTime slotStart;
  final List<Map<String, dynamic>> _bookedItems = [];
  var _createCount = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_simplified_booking_slots') {
      final date =
          '${slotStart.year}-${slotStart.month.toString().padLeft(2, '0')}-${slotStart.day.toString().padLeft(2, '0')}';
      rpcResults[fn] = {
        'success': true,
        'data': {
          'default_duration_minutes': 30,
          'blocks': [
            {
              'start_time': '${date}T10:00:00.000',
              'end_time': '${date}T10:30:00.000',
              'state': 'available',
              'available_doctor_ids': [params?['p_preferred_doctor_id'] ?? calendarTestDoctorBId],
            },
          ],
        },
      };
    }

    final result = super.rpc<T>(fn, params: params, get: get);

    if (fn == 'create_appointment') {
      _createCount++;
      final doctorId = params?['p_doctor_id']?.toString() ?? calendarTestDoctorAId;
      _bookedItems.add(
        appointmentRpcDefaultListItem(
          patientName: doctorId == calendarTestDoctorAId ? 'Sheet Coexist Patient' : 'Simplified Coexist Patient',
          id: _createCount == 1 ? '11111111-1111-4111-8111-111111111111' : '22222222-2222-4222-8222-222222222222',
          doctorId: doctorId,
          doctorName: doctorId == calendarTestDoctorAId ? 'Dr. Ada' : 'Dr. Ben',
          startLocal: slotStart,
        ),
      );
      rpcResults['list_appointments'] = {
        'success': true,
        'data': {'items': List<Map<String, dynamic>>.from(_bookedItems)},
      };
    }

    return result;
  }
}

/// Bounded pumps only — never [pumpAndSettle] while [SfCalendar] is mounted.
Future<void> searchPatientBounded(
  WidgetTester tester, {
  required Key searchKey,
  required String query,
  required String patientName,
}) async {
  await tester.enterText(find.byKey(searchKey), query);
  await tester.pump(const Duration(milliseconds: 350));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text(patientName).evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.tap(find.text(patientName));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> selectOptionalDoctorBounded(WidgetTester tester, String doctorName) async {
  await tester.tap(find.widgetWithText(AppSelect<String>, 'Doctor (optional)'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text(doctorName));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> waitForSimplifiedStepTwoLoaded(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Select Date and Time').evaluate().isNotEmpty &&
        find.byType(AppCircularProgress).evaluate().isEmpty) {
      return;
    }
  }
  fail('Simplified step two did not load.');
}

Future<void> advanceSimplifiedStepOne(WidgetTester tester) async {
  final nextFinder = find.byKey(const Key('simplified_booking_step_one_next'));
  await tester.ensureVisible(nextFinder);
  await tester.tap(nextFinder);
  await tester.pump();
  await waitForSimplifiedStepTwoLoaded(tester);
}

Future<void> dismissOverlayIfPresent(WidgetTester tester) async {
  final close = find.byTooltip('Close');
  if (close.evaluate().isEmpty) {
    return;
  }
  await tester.tap(close);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> submitBookingSheetBounded(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('appointment_booking_submit')));
  await tester.tap(find.byKey(const Key('appointment_booking_submit')));
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(AppointmentBookingSheet).evaluate().isEmpty) {
      return;
    }
  }
}

Future<void> confirmSimplifiedBookingBounded(WidgetTester tester) async {
  final confirmFinder = find.byKey(const Key('simplified_slot_confirm'));
  await tester.ensureVisible(confirmFinder);
  await tester.tap(confirmFinder);
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(SimplifiedBookingFlow).evaluate().isEmpty) {
      return;
    }
  }
  fail('Simplified booking flow did not close after confirm.');
}

Future<void> waitForCalendarPatientNames(
  WidgetTester tester,
  ProviderContainer container,
  List<String> patientNames,
) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final items = container.read(appointmentCalendarProvider).items;
    if (patientNames.every((name) => items.any((item) => item.patientName == name))) {
      return;
    }
  }
}

Future<void> expectCellTapOpensBookingSheet(WidgetTester tester, DateTime tappedDate) async {
  await invokeCalendarTap(tester, date: tappedDate);

  expect(find.byType(AppointmentBookingSheet), findsOneWidget);
  expect(find.text('Book appointment'), findsWidgets);
  expect(find.byType(SimplifiedBookingFlow), findsNothing);
}

void main() {
  group('AppointmentCalendarPage booking', () {
    group('CAL-E — calendar booking entry points', () {
      testWidgets('CAL-E16: month view cell tap does not open booking sheet', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
        final container = await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Month');
        final focusDate = container.read(appointmentCalendarProvider).focusDate;
        final tappedDate = DateTime(focusDate.year, focusDate.month, focusDate.day);

        await invokeCalendarTap(tester, date: tappedDate, element: CalendarElement.calendarCell);

        expect(find.byType(AppointmentBookingSheet), findsNothing);
        expect(find.text('Book appointment'), findsNothing);
      });
    });

    group('ui-012 simplified slot booking — calendar QA', () {
      testWidgets('FUNC-A03: day view cell tap opens AppointmentBookingSheet', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
        final container = await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Day');
        final focusDate = container.read(appointmentCalendarProvider).focusDate;
        final tappedDate = DateTime(focusDate.year, focusDate.month, focusDate.day, 11, 7);

        await expectCellTapOpensBookingSheet(tester, tappedDate);
        expect(find.text('Duration: 30 min'), findsOneWidget);
      });

      testWidgets('FUNC-A03: week view cell tap opens AppointmentBookingSheet', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
        final container = await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Week');
        final focusDate = container.read(appointmentCalendarProvider).focusDate;
        final tappedDate = DateTime(focusDate.year, focusDate.month, focusDate.day, 14, 15);

        await expectCellTapOpensBookingSheet(tester, tappedDate);
      });

      testWidgets('REG-M09: header Book Appointment opens SimplifiedBookingFlow', (tester) async {
        await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
          await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
          await waitForCalendarLoaded(tester);

          await tester.tap(find.text('Book Appointment'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(SimplifiedBookingFlow), findsOneWidget);
          expect(find.text('Step 1 / 2'), findsOneWidget);
          expect(find.byType(AppointmentBookingSheet), findsNothing);
        });
      });

      testWidgets('FUNC-A04: simplified booking refreshes calendar with new tile', (tester) async {
        suppressBookingSheetListTileNoise();
        await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
          final client = BookingRefreshRpcClient();
          final patient = samplePatientListItem(fullName: 'Refresh Patient');

          await pumpAppointmentCalendarPage(
            tester,
            authState: calendarAuthStateWithCreate(),
            rpcClient: client,
            patientRepository: FakePatientRepository(patients: [patient]),
            staffRepository: CalendarDoctorsStubStaffRepository(),
          );
          await waitForCalendarLoaded(tester);

          final listCallsBeforeBook = client.rpcCallCounts['list_appointments'] ?? 0;

          await tester.tap(find.text('Book Appointment'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Step 1 / 2'), findsOneWidget);

          await searchPatientBounded(
            tester,
            searchKey: const Key('simplified_booking_patient_search'),
            query: 'Ref',
            patientName: patient.fullName,
          );
          await selectOptionalDoctorBounded(tester, 'Dr. Ada');
          await advanceSimplifiedStepOne(tester);

          final slotLabel = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
          await tester.ensureVisible(find.text(slotLabel));
          await tester.tap(find.text(slotLabel));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          await confirmSimplifiedBookingBounded(tester);

          expect(client.createAppointmentCalls, hasLength(1));
          expect((client.rpcCallCounts['list_appointments'] ?? 0), greaterThan(listCallsBeforeBook));

          final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
          await waitForCalendarPatientNames(tester, container, ['Newly Booked Patient']);

          final refreshedItems = container.read(appointmentCalendarProvider).items;
          expect(refreshedItems.any((item) => item.patientName == 'Newly Booked Patient'), isTrue);
        });
      });

      testWidgets('INT-K08: sheet and simplified bookings coexist for different doctors', (tester) async {
        suppressBookingSheetListTileNoise();
        await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
          final slotStart = DateTime(2026, 6, 27, 10, 0);
          final client = CoexistBookingRpcClient(slotStart: slotStart);
          final sheetPatient = samplePatientListItem(fullName: 'Sheet Coexist Patient');
          final simplifiedPatient = samplePatientListItem(
            fullName: 'Simplified Coexist Patient',
            id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab',
          );

          await pumpAppointmentCalendarPage(
            tester,
            authState: calendarAuthStateWithCreate(),
            rpcClient: client,
            patientRepository: FakePatientRepository(patients: [sheetPatient, simplifiedPatient]),
            staffRepository: CalendarDoctorsStubStaffRepository(),
          );
          final container = await waitForCalendarLoaded(tester);

          await tapCalendarViewTab(tester, 'Day');
          final focusDate = container.read(appointmentCalendarProvider).focusDate;
          final tappedDate = DateTime(focusDate.year, focusDate.month, focusDate.day, 10, 0);

          await invokeCalendarTap(tester, date: tappedDate);
          await waitForBookingSheetReady(tester);

          await searchPatientBounded(
            tester,
            searchKey: const Key('appointment_booking_patient_search'),
            query: 'Sheet',
            patientName: sheetPatient.fullName,
          );
          await selectOptionalDoctorBounded(tester, 'Dr. Ada');
          await submitBookingSheetBounded(tester);

          expect(client.createAppointmentCalls, hasLength(1));
          expect(client.createAppointmentCalls.single['p_doctor_id'], calendarTestDoctorAId);

          await waitForCalendarPatientNames(tester, container, ['Sheet Coexist Patient']);

          await dismissOverlayIfPresent(tester);
          await tester.tap(find.text('Book Appointment'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          await searchPatientBounded(
            tester,
            searchKey: const Key('simplified_booking_patient_search'),
            query: 'Simpl',
            patientName: simplifiedPatient.fullName,
          );
          await selectOptionalDoctorBounded(tester, 'Dr. Ben');
          await advanceSimplifiedStepOne(tester);

          final slotLabel = DateFormat.jm().format(slotStart);
          await tester.ensureVisible(find.text(slotLabel));
          await tester.tap(find.text(slotLabel));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          await confirmSimplifiedBookingBounded(tester);

          expect(client.createAppointmentCalls, hasLength(2));
          expect(
            client.createAppointmentCalls.map((call) => call['p_doctor_id']),
            containsAll([calendarTestDoctorAId, calendarTestDoctorBId]),
          );

          await waitForCalendarPatientNames(
            tester,
            container,
            ['Sheet Coexist Patient', 'Simplified Coexist Patient'],
          );

          final items = container.read(appointmentCalendarProvider).items;
          expect(items, hasLength(2));
          expect(items.any((item) => item.patientName == 'Sheet Coexist Patient'), isTrue);
          expect(items.any((item) => item.patientName == 'Simplified Coexist Patient'), isTrue);
        });
      });
    });
  });
}
