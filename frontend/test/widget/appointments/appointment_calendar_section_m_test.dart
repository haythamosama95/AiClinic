import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart' as domain;
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/appointment_test_support.dart';
import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/pump_auth_app.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('CAL-M — abuse and edge cases', () {
    testWidgets('CAL-M01: rapid filter apply/clear remains stable', (tester) async {
      await pumpAppointmentCalendarPage(
        tester,
        authState: calendarAuthState(branchIds: [calendarTestBranchAId, calendarTestBranchBId]),
        rpcClient: BranchAwareAppointmentRpcClient(),
      );
      await waitForCalendarLoaded(tester);

      for (var i = 0; i < 10; i++) {
        await openCalendarFilterPopover(tester);
        await selectCalendarBranchFilter(tester, i.isEven ? 'North' : 'Main');
        await applyCalendarFilters(tester);
        await openCalendarFilterPopover(tester);
        await clearCalendarFilters(tester);
      }

      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
      final state = container.read(appointmentCalendarProvider);
      expect(state.selectedBranchId, calendarTestBranchAId);
      expect(state.selectedDoctorId, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CAL-M02: rapid view mode switching does not throw', (tester) async {
      await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
      await waitForCalendarLoaded(tester);

      const tabs = ['Day', 'Week', 'Month', 'Schedule', 'Timeline Day'];
      for (var cycle = 0; cycle < 2; cycle++) {
        for (final tab in tabs) {
          await tapCalendarViewTab(tester, tab);
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      expect(find.byType(SfCalendar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CAL-M03: rapid Today clicks keep focus on current date', (tester) async {
      await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
      final container = await waitForCalendarLoaded(tester);

      await tapCalendarNextPeriod(tester);
      await tapCalendarNextPeriod(tester);

      for (var i = 0; i < 10; i++) {
        await tapCalendarToday(tester);
      }

      final focusDate = container.read(appointmentCalendarProvider).focusDate;
      final today = DateTime.now();
      expect(focusDate.year, today.year);
      expect(focusDate.month, today.month);
      expect(focusDate.day, today.day);
    });

    testWidgets('CAL-M04: system back closes booking sheet gracefully', (tester) async {
      await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate());
      final container = await waitForCalendarLoaded(tester);

      await tapCalendarViewTab(tester, 'Day');
      final focusDate = container.read(appointmentCalendarProvider).focusDate;
      final tappedDate = DateTime(focusDate.year, focusDate.month, focusDate.day, 11, 7);
      await invokeCalendarTap(tester, date: tappedDate);

      expect(find.text('Book appointment'), findsWidgets);

      Navigator.of(tester.element(find.byType(AppointmentBookingSheet)), rootNavigator: true).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Book appointment'), findsNothing);
      expect(find.byType(AppointmentBookingSheet), findsNothing);
      expect(find.byType(AppointmentCalendarPage), findsOneWidget);
    });

    testWidgets('CAL-M05: invalid calendar URL does not mount calendar page', (tester) async {
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(
            () => PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsRead}),
              ),
            ),
          ),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go('${AppRoutes.appointmentsCalendar}/foo');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AppointmentCalendarPage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CAL-M06: drag off calendar reverts without dialog or RPC', (tester) async {
      final start = appointmentTestStartTime();
      final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)]);

      await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
      await waitForCalendarLoaded(tester);
      await tapCalendarViewTab(tester, 'Day');
      await settleCalendarWidgetTest(tester);

      final appointment = firstCalendarAppointment(tester);
      final originalStart = appointment.startTime;

      await invokeCalendarDragCancel(tester, appointment: appointment);

      expect(find.text('Move appointment?'), findsNothing);
      expect(client.rpcCallCounts['reschedule_appointment'] ?? 0, 0);
      expect(firstCalendarAppointment(tester).startTime, originalStart);
    });

    testWidgets('CAL-M07: rapid resize oscillation opens at most one confirm dialog', (tester) async {
      final start = appointmentTestStartTime();
      final end = start.add(const Duration(minutes: 30));
      final client = calendarClientWithItems([appointmentRpcDefaultListItem(startLocal: start)]);

      await pumpAppointmentCalendarPage(tester, authState: calendarAuthStateWithCreate(), rpcClient: client);
      await waitForCalendarLoaded(tester);
      await tapCalendarViewTab(tester, 'Day');

      final appointment = firstCalendarAppointment(tester);
      final extendedEnd = end.add(const Duration(minutes: 30));
      final shrunkEnd = end;

      await invokeCalendarResize(
        tester,
        appointment: appointment,
        startTime: start,
        endTime: extendedEnd,
        updateTimes: [extendedEnd],
      );
      expect(find.text('Move appointment?'), findsOneWidget);

      await cancelRescheduleDialog(tester);

      await invokeCalendarResize(
        tester,
        appointment: appointment,
        startTime: start,
        endTime: shrunkEnd,
        updateTimes: [shrunkEnd],
      );

      expect(find.text('Move appointment?'), findsNothing);
      expect(client.rpcCallCounts['reschedule_appointment'] ?? 0, 0);
    });

    testWidgets('CAL-M08: long patient name renders without layout overflow', (tester) async {
      final longName = 'A' * 120;
      final start = appointmentTestStartTime();
      final client = calendarClientWithItems([appointmentRpcDefaultListItem(patientName: longName, startLocal: start)]);

      await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), rpcClient: client);
      final container = await waitForCalendarLoaded(tester);
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(appointmentCalendarProvider).items.single.patientName, longName);
      final dataSource = calendarWidget(tester).dataSource! as AppointmentCalendarDataSource;
      expect((dataSource.appointments!.single as Appointment).subject, longName);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CAL-M09: week view with 100+ appointments loads without exception', (tester) async {
      final weekStart = appointmentTestStartTime();
      final items = List.generate(120, (index) {
        final dayOffset = index % 5;
        final slotIndex = index ~/ 5;
        final startLocal = DateTime(
          weekStart.year,
          weekStart.month,
          weekStart.day + dayOffset,
          9 + (slotIndex % 8),
          (slotIndex % 2) * 30,
        );
        return appointmentRpcDefaultListItem(
          id: 'appt-${index.toString().padLeft(4, '0')}-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          patientName: 'Patient $index',
          startLocal: startLocal,
        );
      });
      final client = calendarClientWithItems(items);

      await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), rpcClient: client);
      final container = await waitForCalendarLoaded(tester);

      expect(container.read(appointmentCalendarProvider).items, hasLength(120));
      expect(find.byType(SfCalendar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('CAL-M10: DST spring-forward day keeps org-local appointment bounds', () {
      ensureAppointmentTimezonesInitialized();
      final location = tz.getLocation('America/New_York');
      final localStart = tz.TZDateTime(location, 2026, 3, 8, 10, 0);
      final range = appointmentTodayRangeInTimezone('America/New_York', localStart.toUtc());

      final rangeStartLocal = tz.TZDateTime.from(range.from, location);
      final rangeEndLocal = tz.TZDateTime.from(range.to, location);

      expect(rangeStartLocal.year, 2026);
      expect(rangeStartLocal.month, 3);
      expect(rangeStartLocal.day, 8);
      expect(rangeEndLocal.difference(rangeStartLocal).inHours, inInclusiveRange(23, 24));
    });

    test('CAL-M11: midnight-spanning slot is valid when branch closes at 23:59', () {
      final schedule = BranchWorkingSchedule(
        BranchWeekday.values
            .map(
              (day) => BranchWorkingDayHours(
                day: day,
                isWorkingDay: day != BranchWeekday.sunday,
                openTime: day == BranchWeekday.sunday ? null : '22:00',
                closeTime: day == BranchWeekday.sunday ? null : '23:59',
              ),
            )
            .toList(growable: false),
      );
      final start = DateTime(2026, 6, 1, 23, 0);
      final end = DateTime(2026, 6, 2, 0, 0);

      expect(AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: start, end: end), isTrue);
    });

    test('CAL-M12: overlapping unassigned appointments are detected', () {
      final schedule = BranchWorkingSchedule.defaultSchedule();
      final day = DateTime(2026, 6, 4, 10, 0);
      final appointment = AppointmentListItem(
        id: 'a1',
        patientId: 'p1',
        patientName: 'Patient One',
        doctorId: null,
        startTime: day,
        endTime: day.add(const Duration(minutes: 30)),
        type: domain.AppointmentType.planned,
        status: AppointmentStatus.scheduled,
      );
      final blocker = AppointmentListItem(
        id: 'a2',
        patientId: 'p2',
        patientName: 'Patient Two',
        doctorId: null,
        startTime: day.add(const Duration(minutes: 15)),
        endTime: day.add(const Duration(minutes: 45)),
        type: domain.AppointmentType.planned,
        status: AppointmentStatus.scheduled,
      );

      final error = AppointmentRescheduleValidation.validateMove(
        appointment: appointment,
        newStart: day,
        schedule: schedule,
        branchAppointments: [appointment, blocker],
      );

      expect(error, contains('overlaps'));
    });
  });
}
