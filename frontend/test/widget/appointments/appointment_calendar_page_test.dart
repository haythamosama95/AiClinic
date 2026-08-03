import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/core/ui/components/app_skeletonizer_zone.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_toolbar.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';

import '../../helpers/role_permission_seed.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'calendar_widget_test_harness.dart';

void main() {
  Future<SpyAppointmentCalendarController> pumpCalendarPage(
    WidgetTester tester, {
    AuthSessionState? auth,
    AppointmentCalendarState? calendarState,
    AppointmentRpcTestClient? rpcClient,
  }) {
    return pumpCalendarSurface(
      tester,
      auth: auth,
      calendarState: calendarState,
      rpcClient: rpcClient,
      child: const SizedBox(height: 900, child: AppointmentCalendarPage()),
    );
  }

  testWidgets('trivial: CAL-PAGE-01 builds successfully for a permitted user', (tester) async {
    await pumpCalendarPage(tester, calendarState: defaultCalendarState(loading: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.byType(AppointmentCalendarToolbar), findsOneWidget);
    expect(find.byType(SfCalendar), findsOneWidget);
  });

  testWidgets('invalid state: CAL-PAGE-02 permission denied renders no-access state without calendar', (tester) async {
    await pumpCalendarPage(
      tester,
      auth: calendarAuthSession(permissions: const {PermissionKeys.patientsView}),
      calendarState: defaultCalendarState(loading: false),
    );
    await tester.pump();

    expect(find.text('No access'), findsOneWidget);
    expect(find.text('You do not have permission to view this content.'), findsOneWidget);
    expect(find.byType(SfCalendar), findsNothing);
    expect(find.byType(AppointmentCalendarToolbar), findsNothing);
  });

  testWidgets('advanced: CAL-PAGE-03 loading state renders skeleton body', (tester) async {
    await pumpCalendarPage(tester, calendarState: defaultCalendarState(loading: true));
    await tester.pump();

    expect(find.byType(AppSkeletonizerZone), findsOneWidget);
    expect(find.byType(SfCalendar), findsNothing);
  });

  testWidgets('invalid state: CAL-PAGE-04 error state shows message, description, and Retry', (tester) async {
    const errorMessage = 'Could not load appointments. Please retry.';
    final spy = await pumpCalendarPage(
      tester,
      calendarState: defaultCalendarState(loading: false, error: errorMessage),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Could not load calendar'), findsOneWidget);
    expect(find.text(errorMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(spy.refreshCallCount, 1);
  });

  testWidgets('edge case: CAL-PAGE-05 closed day shows branch closed message on Sunday', (tester) async {
    final sunday = DateTime(2026, 6, 7);
    await pumpCalendarPage(
      tester,
      calendarState: defaultCalendarState(mode: AppointmentCalendarMode.day, focusDate: sunday, loading: false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('This branch is closed on Sunday.'), findsOneWidget);
  });

  testWidgets('advanced: CAL-PAGE-06 success state renders toolbar and calendar host', (tester) async {
    await pumpCalendarPage(tester, calendarState: defaultCalendarState(loading: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AppointmentCalendarToolbar), findsOneWidget);
    expect(find.byType(SfCalendar), findsOneWidget);
  });

  testWidgets('advanced: CAL-PAGE-07 Book appointment is present and enabled when user can create', (tester) async {
    await pumpCalendarPage(
      tester,
      auth: calendarAuthSession(permissions: RolePermissionSeed.administrator),
      calendarState: defaultCalendarState(loading: false, selectedBranchId: calendarTestBranchAId),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final bookButton = find.widgetWithText(AppButton, 'Book appointment');
    expect(bookButton, findsOneWidget);
    final button = tester.widget<AppButton>(bookButton);
    expect(button.disabled, isFalse);
  });

  testWidgets('invalid state: CAL-PAGE-08 Book appointment absent when user cannot create', (tester) async {
    await pumpCalendarPage(
      tester,
      auth: calendarAuthSession(permissions: RolePermissionSeed.labStaff),
      calendarState: defaultCalendarState(loading: false, selectedBranchId: calendarTestBranchAId),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Book appointment'), findsNothing);
  });

  testWidgets('invalid state: CAL-PAGE-09 Book appointment absent when no branch is active', (tester) async {
    await pumpCalendarPage(
      tester,
      auth: calendarAuthSession(
        permissions: RolePermissionSeed.administrator,
        activeBranchId: null,
        branchIds: const [],
      ),
      calendarState: defaultCalendarState(loading: false, selectedBranchId: null),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Book appointment'), findsNothing);
  });

  testWidgets('advanced: CAL-PAGE-10 tapping Book appointment opens booking sheet', (tester) async {
    await pumpCalendarPage(
      tester,
      auth: calendarAuthSession(permissions: RolePermissionSeed.administrator),
      calendarState: defaultCalendarState(loading: false, selectedBranchId: calendarTestBranchAId),
      rpcClient: AppointmentRpcTestClient(),
    );
    await tester.pump();

    await tester.tap(find.text('Book appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Book appointment'), findsWidgets);
    expect(find.text('Patient, branch, and optional doctor preference.'), findsOneWidget);
  });
}
