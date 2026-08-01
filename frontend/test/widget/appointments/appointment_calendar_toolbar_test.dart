import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
<<<<<<< HEAD
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_toolbar.dart';

import '../../support/appointment_calendar_test_support.dart';
import 'calendar_widget_test_harness.dart';

=======
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_toolbar.dart';

import 'calendar_widget_test_harness.dart';

void _noop() {}

>>>>>>> master
void main() {
  Future<SpyAppointmentCalendarController> pumpToolbar(
    WidgetTester tester, {
    AppointmentCalendarState? calendarState,
    bool isFullscreen = false,
<<<<<<< HEAD
    VoidCallback? onToggleFullscreen,
=======
    VoidCallback? onToggleFullscreen = _noop,
>>>>>>> master
  }) async {
    final state = calendarState ?? defaultCalendarState();
    return pumpCalendarSurface(
      tester,
      calendarState: state,
      child: SizedBox(
        height: 120,
        child: AppointmentCalendarToolbar(
          branchesAsync: AsyncData(calendarTestBranches()),
          doctorsAsync: AsyncData(calendarTestDoctorsWithBranches()),
          appliedBranchId: state.selectedBranchId,
          appliedDoctorId: state.selectedDoctorId,
          appliedStatuses: state.selectedStatuses,
          hasActiveFilters: false,
          onApplyFilters: (_) {},
          onClearFilters: () {},
          isFullscreen: isFullscreen,
          onToggleFullscreen: onToggleFullscreen,
        ),
      ),
      surfaceSize: const Size(1280, 200),
    );
  }

  testWidgets('trivial: CAL-TOOLBAR-01 renders period navigation, title, and utility controls', (tester) async {
    final focus = DateTime(2026, 6, 15);
    await pumpToolbar(
      tester,
      calendarState: defaultCalendarState(focusDate: focus, mode: AppointmentCalendarMode.week),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Previous period'), findsOneWidget);
    expect(find.bySemanticsLabel('Next period'), findsOneWidget);
    expect(find.text(AppointmentCalendarDisplay.headerTitle(AppointmentCalendarMode.week, focus)), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.bySemanticsLabel('Calendar view mode'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Doctors'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);
    expect(find.bySemanticsLabel('Appointment colors'), findsOneWidget);
    expect(find.bySemanticsLabel('Schedule filters'), findsOneWidget);
    expect(find.bySemanticsLabel('Expand calendar'), findsOneWidget);
  });

  testWidgets('advanced: CAL-TOOLBAR-02 previous and next period drive the controller', (tester) async {
    final spy = await pumpToolbar(tester);
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Previous period'));
    await tester.pump();
    expect(spy.previousPeriodCallCount, 1);

    await tester.tap(find.bySemanticsLabel('Next period'));
    await tester.pump();
    expect(spy.nextPeriodCallCount, 1);
  });

  testWidgets('advanced: CAL-TOOLBAR-03 Today calls goToToday', (tester) async {
    final spy = await pumpToolbar(tester);
    await tester.pump();

    await tester.tap(find.text('Today'));
    await tester.pump();

    expect(spy.goToTodayCallCount, 1);
  });

  testWidgets('advanced: CAL-TOOLBAR-04 selecting a view mode calls setMode', (tester) async {
    final spy = await pumpToolbar(tester);
    await tester.pump();

    await tester.tap(find.text('Day'));
    await tester.pump();

    expect(spy.setModeCallCount, 1);
    expect(spy.lastSetMode, AppointmentCalendarMode.day);
  });

  testWidgets('advanced: CAL-TOOLBAR-05 fullscreen toggle label switches and invokes callback', (tester) async {
    var toggled = 0;
    await pumpToolbar(
      tester,
      isFullscreen: false,
      onToggleFullscreen: () => toggled++,
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Expand calendar'));
    await tester.pump();
    expect(toggled, 1);

    await pumpToolbar(
      tester,
      isFullscreen: true,
      onToggleFullscreen: () => toggled++,
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Exit fullscreen'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Exit fullscreen'));
    await tester.pump();
    expect(toggled, 2);
  });

  testWidgets('edge case: CAL-TOOLBAR-06 schedule mode hides period navigation but keeps title', (tester) async {
    final focus = DateTime(2026, 6, 15);
    await pumpToolbar(
      tester,
      calendarState: defaultCalendarState(
        focusDate: focus,
        mode: AppointmentCalendarMode.schedule,
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Previous period'), findsNothing);
    expect(find.bySemanticsLabel('Next period'), findsNothing);
    expect(find.text(AppointmentCalendarDisplay.headerTitle(AppointmentCalendarMode.schedule, focus)), findsOneWidget);
    expect(find.text('30m'), findsNothing);
  });
}
