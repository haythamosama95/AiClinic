import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/appointment_test_support.dart';
import '../../helpers/patient_test_support.dart';
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

void main() {
  group('AppointmentCalendarPage booking', () {
    group('CAL-E — calendar booking entry points', () {
      testWidgets('CAL-E01: day view cell tap opens booking sheet with snapped slot', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
        final container = await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Day');
        final focusDate = container.read(appointmentCalendarProvider).focusDate;
        final tappedDate = DateTime(focusDate.year, focusDate.month, focusDate.day, 11, 7);

        await invokeCalendarTap(tester, date: tappedDate);

        expect(find.text('Book appointment'), findsWidgets);
        expect(find.text('Duration: 30 min'), findsOneWidget);
      });

      testWidgets('CAL-E02: header Book Appointment opens sheet at focus-date open time', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
        final container = await waitForCalendarLoaded(tester);

        final focusDate = container.read(appointmentCalendarProvider).focusDate;
        final schedule = BranchWorkingSchedule.defaultSchedule();
        final expectedRange = AppointmentCalendarDisplay.slotRangeFromTap(
          tappedDate: focusDate,
          schedule: schedule,
          mode: container.read(appointmentCalendarProvider).mode,
        );

        await tester.tap(find.text('Book Appointment'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Book appointment'), findsWidgets);
        final timeFormat = DateFormat('h:mm a');
        expect(find.textContaining(timeFormat.format(expectedRange.start)), findsWidgets);
        expect(
          find.text('Duration: ${expectedRange.end.difference(expectedRange.start).inMinutes} min'),
          findsOneWidget,
        );
      });

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

      testWidgets('CAL-E18: successful booking refreshes calendar with new appointment tile', (tester) async {
        suppressBookingSheetListTileNoise();
        await withClock(Clock.fixed(DateTime(2026, 6, 16, 8, 0)), () async {
          final client = BookingRefreshRpcClient();
          final patient = samplePatientListItem(fullName: 'Refresh Patient');

          await pumpAppointmentCalendarPage(
            tester,
            authState: calendarAuthStateWithCreate(),
            rpcClient: client,
            patientRepository: FakePatientRepository(patients: [patient]),
          );
          await waitForCalendarLoaded(tester);

          final listCallsBeforeBook = client.rpcCallCounts['list_appointments'] ?? 0;

          await tester.tap(find.text('Book Appointment'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await waitForBookingSheetReady(tester);
          await tester.pumpAndSettle();

          await submitValidBooking(tester, patient: patient, searchQuery: 'Ref');
          await tester.pumpAndSettle();

          expect(client.createAppointmentCalls, hasLength(1));
          expect((client.rpcCallCounts['list_appointments'] ?? 0), greaterThan(listCallsBeforeBook));

          final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            final items = container.read(appointmentCalendarProvider).items;
            if (items.any((item) => item.patientName == 'Newly Booked Patient')) {
              break;
            }
          }

          final refreshedItems = container.read(appointmentCalendarProvider).items;
          expect(refreshedItems.any((item) => item.patientName == 'Newly Booked Patient'), isTrue);
        });
      });
    });
  });
}
