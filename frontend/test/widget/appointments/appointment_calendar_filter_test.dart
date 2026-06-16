import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../support/appointment_calendar_test_support.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('AppointmentCalendarPage filters', () {
    group('CAL-D — filtering', () {
      testWidgets('CAL-D01: filter icon opens branch and doctor popover with actions', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(branchIds: [calendarTestBranchAId, calendarTestBranchBId]),
          staffRepository: CalendarDoctorsStubStaffRepository(),
        );
        await waitForCalendarLoaded(tester);

        await openCalendarFilterPopover(tester);

        expect(find.text('Filter by'), findsOneWidget);
        expect(find.text('Branch'), findsOneWidget);
        expect(find.text('Doctor'), findsOneWidget);
        expect(find.text('Apply Filters'), findsOneWidget);
        expect(find.text('Clear Filters'), findsOneWidget);
      });

      testWidgets('CAL-D02: applying branch filter shows branch appointments and active badge', (tester) async {
        final client = BranchAwareAppointmentRpcClient();

        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(branchIds: [calendarTestBranchAId, calendarTestBranchBId]),
          rpcClient: client,
        );
        final container = await waitForCalendarLoaded(tester);

        expect(container.read(appointmentCalendarProvider).items.single.patientName, 'Branch A Patient');

        await openCalendarFilterPopover(tester);
        await selectCalendarBranchFilter(tester, 'North');
        await applyCalendarFilters(tester);
        await waitForCalendarLoaded(tester);

        final state = container.read(appointmentCalendarProvider);
        expect(state.selectedBranchId, calendarTestBranchBId);
        expect(state.items.single.patientName, 'Branch B Patient');
        expect(calendarFilterBadge(tester).isLabelVisible, isTrue);
        expect(client.lastParams?['p_branch_id'], calendarTestBranchBId);
      });

      testWidgets('CAL-D03: applying doctor filter shows only that doctor appointments', (tester) async {
        final client = DoctorAwareAppointmentRpcClient();

        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(),
          rpcClient: client,
          staffRepository: CalendarDoctorsStubStaffRepository(),
        );
        final container = await waitForCalendarLoaded(tester);

        expect(container.read(appointmentCalendarProvider).items, hasLength(2));

        await openCalendarFilterPopover(tester);
        await selectCalendarDoctorFilter(tester, 'Dr. Ada');
        await applyCalendarFilters(tester);
        await waitForCalendarLoaded(tester);

        final state = container.read(appointmentCalendarProvider);
        expect(state.items, hasLength(1));
        expect(state.items.single.patientName, 'Ada Patient');
        expect(client.lastParams?['p_doctor_id'], calendarTestDoctorAId);
      });

      testWidgets('CAL-D04: clear filters resets branch to session default and clears doctor', (tester) async {
        final client = BranchAwareAppointmentRpcClient();

        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(branchIds: [calendarTestBranchAId, calendarTestBranchBId]),
          rpcClient: client,
          staffRepository: CalendarDoctorsStubStaffRepository(),
        );
        final container = await waitForCalendarLoaded(tester);

        await openCalendarFilterPopover(tester);
        await selectCalendarBranchFilter(tester, 'North');
        await selectCalendarDoctorFilter(tester, 'Dr. Ben');
        await applyCalendarFilters(tester);
        await waitForCalendarLoaded(tester);

        await openCalendarFilterPopover(tester);
        await clearCalendarFilters(tester);
        await waitForCalendarLoaded(tester);

        final state = container.read(appointmentCalendarProvider);
        expect(state.selectedBranchId, calendarTestBranchAId);
        expect(state.selectedDoctorId, isNull);
        expect(state.items.single.patientName, 'Branch A Patient');
        expect(calendarFilterBadge(tester).isLabelVisible, isFalse);
        expect(client.lastParams?['p_branch_id'], calendarTestBranchAId);
        expect(client.lastParams?.containsKey('p_doctor_id'), isFalse);
      });

      testWidgets('CAL-D05: default filters do not show filter badge', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        await waitForCalendarLoaded(tester);

        expect(calendarFilterBadge(tester).isLabelVisible, isFalse);
      });

      testWidgets('CAL-D06: doctor filter collapses timeline day to filtered doctor rows', (tester) async {
        final client = DoctorAwareAppointmentRpcClient();

        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(),
          rpcClient: client,
          staffRepository: CalendarDoctorsStubStaffRepository(),
        );
        final container = await waitForCalendarLoaded(tester);

        await openCalendarFilterPopover(tester);
        await selectCalendarDoctorFilter(tester, 'Dr. Ada');
        await applyCalendarFilters(tester);
        await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Timeline Day');
        await tester.pump(const Duration(milliseconds: 200));

        final calendar = calendarWidget(tester);
        final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
        expect(calendar.view, CalendarView.timelineDay);
        expect(dataSource.resources!.map((resource) => resource.displayName), containsAll(['Dr. Ada', 'Unassigned']));
        expect(dataSource.resources!.map((resource) => resource.displayName), isNot(contains('Dr. Ben')));
        expect(container.read(appointmentCalendarProvider).selectedDoctorId, calendarTestDoctorAId);
      });

      testWidgets('CAL-D07: slow branch list shows loading placeholder without crashing', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(branchIds: [calendarTestBranchAId, calendarTestBranchBId]),
          branchRepository: SlowCalendarStubBranchRepository(),
        );
        await tester.pump();

        await openCalendarFilterPopover(tester);

        expect(find.text('Loading branches…'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Loading branches…'), findsNothing);
        expect(find.text('Main'), findsWidgets);
      });

      testWidgets('CAL-D08: empty branch list keeps calendar usable with no branch options', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(),
          branchRepository: EmptyCalendarStubBranchRepository(),
        );
        final container = await waitForCalendarLoaded(tester);

        expect(find.byType(SfCalendar), findsOneWidget);
        expect(await container.read(appointmentCalendarBranchesProvider.future), isEmpty);
        expect(container.read(appointmentCalendarProvider).items, isNotEmpty);
      });
    });
  });
}
