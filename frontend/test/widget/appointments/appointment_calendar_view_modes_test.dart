import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_header_bar.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('AppointmentCalendarPage view modes', () {
    group('CAL-C — view modes and navigation', () {
      testWidgets('CAL-C01: Day tab shows day grid with branch working hours', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        final container = await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Day');

        final calendar = calendarWidget(tester);
        expect(calendar.view, CalendarView.day);
        expect(calendar.timeSlotViewSettings.startHour, 9);
        expect(calendar.timeSlotViewSettings.endHour, 17);
        expect(container.read(appointmentCalendarProvider).mode, AppointmentCalendarMode.day);
      });

      testWidgets('CAL-C02: Week tab shows seven-day grid with non-working days marked', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Week');

        final calendar = calendarWidget(tester);
        expect(calendar.view, CalendarView.week);
        expect(calendar.timeSlotViewSettings.nonWorkingDays, contains(DateTime.sunday));
      });

      testWidgets('CAL-C03: Month tab shows indicators and agenda appointments', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        final container = await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Month');
        await settleCalendarWidgetTest(tester);

        final calendar = calendarWidget(tester);
        final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
        expect(calendar.view, CalendarView.month);
        expect(calendar.monthViewSettings.showAgenda, isTrue);
        expect(calendar.monthViewSettings.appointmentDisplayMode, MonthAppointmentDisplayMode.indicator);
        expect(dataSource.appointments, isNotEmpty);
        expect(container.read(appointmentCalendarProvider).items, isNotEmpty);
      });

      testWidgets('CAL-C04: Schedule tab shows list view and hides navigation arrows', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Schedule');

        final calendar = calendarWidget(tester);
        expect(calendar.view, CalendarView.schedule);
        expect(find.byIcon(Icons.chevron_left), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      });

      testWidgets('CAL-C05: Timeline Day tab shows doctor resource rows', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(),
          rpcClient: DoctorAwareAppointmentRpcClient(),
          staffRepository: CalendarDoctorsStubStaffRepository(),
        );
        await waitForCalendarLoaded(tester);
        await waitForCalendarDoctorsLoaded(tester);

        await tapCalendarViewTab(tester, 'Timeline Day');
        await settleCalendarWidgetTest(tester);

        final calendar = calendarWidget(tester);
        final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
        expect(calendar.view, CalendarView.timelineDay);
        expect(
          dataSource.resources!.map((resource) => resource.displayName),
          containsAll(['Dr. Ada', 'Dr. Ben', 'Unassigned']),
        );
        expect(dataSource.appointments, hasLength(2));
      });

      testWidgets('CAL-C06: prev/next arrows change focus week and refetch appointments', (tester) async {
        final client = AppointmentRpcTestClient();

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), rpcClient: client);
        final container = await waitForCalendarLoaded(tester);

        final initialFocus = container.read(appointmentCalendarProvider).focusDate;
        final initialCalls = client.rpcCallCounts['list_appointments'] ?? 0;

        await tapCalendarNextPeriod(tester);
        await waitForCalendarLoaded(tester);

        final nextFocus = container.read(appointmentCalendarProvider).focusDate;
        expect(nextFocus.difference(initialFocus).inDays, 7);
        expect(client.rpcCallCounts['list_appointments'], greaterThan(initialCalls));
      });

      testWidgets('CAL-C07: Today returns focus to the current date', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        final container = await waitForCalendarLoaded(tester);

        await container.read(appointmentCalendarProvider.notifier).setFocusDate(DateTime(2026, 8, 15));
        await settleCalendarWidgetTest(tester);

        expect(container.read(appointmentCalendarProvider).focusDate, DateTime(2026, 8, 15));

        await tapCalendarToday(tester);
        await waitForCalendarLoaded(tester);

        final today = DateTime.now();
        final focus = container.read(appointmentCalendarProvider).focusDate;
        expect(focus, DateTime(today.year, today.month, today.day));
      });

      testWidgets('CAL-C08: closed weekday shows branch closed banner in day view', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        final container = await waitForCalendarLoaded(tester);

        final sunday = nearestSunday(DateTime.now());
        await container.read(appointmentCalendarProvider.notifier).setFocusDate(sunday);
        await container.read(appointmentCalendarProvider.notifier).setMode(AppointmentCalendarMode.day);
        await settleCalendarWidgetTest(tester);

        expect(find.text('This branch is closed on ${DateFormat.EEEE().format(sunday)}.'), findsOneWidget);
      });

      testWidgets('CAL-C09: month view blackout dates include closed Sundays', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        final container = await waitForCalendarLoaded(tester);

        final focus = DateTime(2026, 6, 15);
        await container.read(appointmentCalendarProvider.notifier).setFocusDate(focus);
        await container.read(appointmentCalendarProvider.notifier).setMode(AppointmentCalendarMode.month);
        await settleCalendarWidgetTest(tester);

        final calendar = calendarWidget(tester);
        final blackoutSundays = calendar.blackoutDates!.where((date) => date.weekday == DateTime.sunday).toList();
        expect(blackoutSundays, isNotEmpty);
        expect(blackoutSundays.every((date) => date.month == focus.month), isTrue);
      });

      testWidgets('CAL-C10: swipe navigation disabled when allowViewNavigation is false', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        await waitForCalendarLoaded(tester);

        expect(calendarWidget(tester).allowViewNavigation, isFalse);
      }, skip: true);

      testWidgets('CAL-C11: header title reflects mode and focus date', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        final container = await waitForCalendarLoaded(tester);

        for (final label in ['Day', 'Week', 'Month', 'Schedule']) {
          await tapCalendarViewTab(tester, label);
          final state = container.read(appointmentCalendarProvider);
          expect(
            find.descendant(
              of: find.byType(AppointmentCalendarHeaderBar),
              matching: find.text(expectedCalendarHeaderTitle(state)),
            ),
            findsOneWidget,
          );
        }

        await tapCalendarViewTab(tester, 'Week');
        await tapCalendarNextPeriod(tester);
        await waitForCalendarLoaded(tester);

        final state = container.read(appointmentCalendarProvider);
        expect(
          find.descendant(
            of: find.byType(AppointmentCalendarHeaderBar),
            matching: find.text(expectedCalendarHeaderTitle(state)),
          ),
          findsOneWidget,
        );
      });
    });
  });
}
