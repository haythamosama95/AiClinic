import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_booking_flow.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
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

      testWidgets('US5-T037: header opens simplified flow while slot tap opens legacy sheet', (tester) async {
        await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
          await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
          final container = await waitForCalendarLoaded(tester);

          await tapCalendarViewTab(tester, 'Day');
          final focusDate = container.read(appointmentCalendarProvider).focusDate;
          final tappedDate = DateTime(focusDate.year, focusDate.month, focusDate.day, 11, 7);

          await invokeCalendarTap(tester, date: tappedDate);

          expect(find.byType(AppointmentBookingSheet), findsOneWidget);
          expect(find.text('Book appointment'), findsWidgets);
          expect(find.text('Duration: 30 min'), findsOneWidget);
          expect(find.byType(SimplifiedBookingFlow), findsNothing);

          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Book Appointment'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(SimplifiedBookingFlow), findsOneWidget);
          expect(find.text('Step 1 / 2'), findsOneWidget);
          expect(find.byType(AppointmentBookingSheet), findsNothing);
        });
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

      testWidgets('CAL-E18: header simplified booking refreshes calendar with new appointment tile', (tester) async {
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

          await tester.enterText(find.byKey(const Key('simplified_booking_patient_search')), 'Ref');
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          await tester.tap(find.text(patient.fullName));
          await tester.pumpAndSettle();

          await tester.tap(find.widgetWithText(AppSelect<String>, 'Doctor (optional)'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Dr. Ada'));
          await tester.pumpAndSettle();

          final nextFinder = find.byKey(const Key('simplified_booking_step_one_next'));
          await tester.ensureVisible(nextFinder);
          await tester.tap(nextFinder);
          await tester.pump();

          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            if (find.text('Select Date and Time').evaluate().isNotEmpty &&
                find.byType(AppCircularProgress).evaluate().isEmpty) {
              break;
            }
          }
          await tester.pumpAndSettle();

          final slotLabel = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
          await tester.ensureVisible(find.text(slotLabel));
          await tester.tap(find.text(slotLabel));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('simplified_slot_confirm')));
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
