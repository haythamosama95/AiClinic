import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_skeleton.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('AppointmentCalendarPage', () {
    group('CAL-A — access control', () {
      testWidgets('CAL-A02: permission denied without appointment access', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(permissions: {PermissionKeys.patientsView}),
        );
        await settleCalendarWidgetTest(tester);

        expect(find.text('You do not have permission to view appointments.'), findsOneWidget);
        expect(find.byType(SfCalendar), findsNothing);
      });

      testWidgets('CAL-A03: read-only user sees calendar without Book button or drag', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(permissions: {PermissionKeys.appointmentsRead}),
        );
        await settleCalendarWidgetTest(tester);

        expect(find.text('Today'), findsOneWidget);
        expect(find.byType(SfCalendar), findsOneWidget);
        expect(find.text('Book Appointment'), findsNothing);
        expect(calendarWidget(tester).allowDragAndDrop, isFalse);
        expect(calendarWidget(tester).allowAppointmentResize, isFalse);
      });

      testWidgets('CAL-A05: read-only user has drag and resize disabled', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(permissions: {PermissionKeys.appointmentsRead}),
        );
        await settleCalendarWidgetTest(tester);

        final calendar = calendarWidget(tester);
        expect(calendar.allowDragAndDrop, isFalse);
        expect(calendar.onDragStart, isNull);
        expect(calendar.onAppointmentResizeStart, isNull);
      });

      testWidgets('CAL-A07: missing active branch shows selection error', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: AuthSessionContext(
              staffProfile: StaffProfile(
                staffMemberId: '00000000-0000-4000-8000-000000000010',
                fullName: 'Test Staff',
                role: StaffRole.administrator,
                isBootstrapAdmin: false,
                isActive: true,
              ),
              organizationId: '00000000-0000-4000-8000-000000000020',
              branchIds: const [],
              activeBranchId: null,
              permissions: {PermissionKeys.appointmentsRead},
              setupRequired: false,
            ),
          ),
        );

        final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          final state = container.read(appointmentCalendarProvider);
          if (!state.loading && state.error != null) {
            break;
          }
        }
        await settleCalendarWidgetTest(tester);

        final state = container.read(appointmentCalendarProvider);
        expect(state.error, contains('active branch'));
        expect(state.items, isEmpty);
        expect(state.loading, isFalse);
        expect(find.byType(AppointmentCalendarSkeleton), findsNothing);
        expect(find.text('Test Patient'), findsNothing);
      });
    });

    group('CAL-B — loading and error states', () {
      testWidgets('CAL-B01: shows skeleton while appointments load', (tester) async {
        final client = SlowAppointmentRpcTestClient();

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), rpcClient: client);
        await tester.pump();

        expect(find.byType(AppointmentCalendarSkeleton), findsOneWidget);
        expect(find.byType(SfCalendar), findsNothing);

        await waitForCalendarLoaded(tester);

        expect(find.byType(AppointmentCalendarSkeleton), findsNothing);
        expect(find.byType(SfCalendar), findsOneWidget);
      });

      testWidgets('CAL-B02: appointment data loads and tile reveal completes after stagger delay', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());

        final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          final state = container.read(appointmentCalendarProvider);
          if (!state.loading && state.items.isNotEmpty) {
            break;
          }
        }

        expect(find.byType(AppointmentCalendarSkeleton), findsNothing);
        expect(find.byType(SfCalendar), findsOneWidget);
        expect(container.read(appointmentCalendarProvider).items, hasLength(1));

        await tester.pump(const Duration(milliseconds: 200));

        final tileSkeletonizersAfterReveal = tester
            .widgetList<Skeletonizer>(find.descendant(of: find.byType(SfCalendar), matching: find.byType(Skeletonizer)))
            .where((widget) => widget.enabled)
            .toList();
        expect(tileSkeletonizersAfterReveal, isEmpty);
      });

      testWidgets('CAL-B03: RPC failure shows error and Retry without crashing', (tester) async {
        final client = AppointmentRpcTestClient()
          ..rpcResults['list_appointments'] = {
            'success': false,
            'error_code': 'INTERNAL',
            'error_message': 'Database unavailable',
          };

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), rpcClient: client);
        await settleCalendarWidgetTest(tester);

        expect(find.textContaining('Could not load appointments'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.byType(SfCalendar), findsOneWidget);
      });

      testWidgets('CAL-B04: Retry refreshes appointments after error', (tester) async {
        // Syncfusion may trigger a second list fetch via onViewChanged before Retry.
        final client = FlakyListAppointmentRpcClient(failuresBeforeSuccess: 2);

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), rpcClient: client);

        final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          final state = container.read(appointmentCalendarProvider);
          if (!state.loading && state.error != null) {
            break;
          }
        }
        await settleCalendarWidgetTest(tester);

        expect(find.textContaining('Could not load appointments'), findsOneWidget);
        final callsBeforeRetry = client.rpcCallCounts['list_appointments'] ?? 0;
        expect(callsBeforeRetry, greaterThanOrEqualTo(1));

        // Syncfusion may issue 1–2 list fetches before Retry; drain remaining failures so Retry succeeds.
        client.failuresBeforeSuccess = 0;
        await tapForuiControl(tester, find.text('Retry'));
        final containerAfterRetry = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          final state = containerAfterRetry.read(appointmentCalendarProvider);
          if (!state.loading && state.error == null) {
            break;
          }
        }
        await settleCalendarWidgetTest(tester);

        expect(find.textContaining('Could not load appointments'), findsNothing);
        expect(client.rpcCallCounts['list_appointments'], greaterThan(callsBeforeRetry));
        expect(find.byType(SfCalendar), findsOneWidget);
      });

      testWidgets('CAL-B05: empty branch shows calendar grid without stuck skeleton', (tester) async {
        final client = AppointmentRpcTestClient()
          ..rpcResults['list_appointments'] = {
            'success': true,
            'data': {'items': <Map<String, dynamic>>[]},
          };

        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), rpcClient: client);
        await settleCalendarWidgetTest(tester);

        expect(find.byType(AppointmentCalendarSkeleton), findsNothing);
        expect(find.byType(SfCalendar), findsOneWidget);
        expect(find.text('Test Patient'), findsNothing);
      });
    });

    testWidgets('renders filter popover controls when appointment access granted', (tester) async {
      await pumpAppointmentCalendarPage(
        tester,
        authState: calendarAuthState(permissions: {PermissionKeys.appointmentsRead}),
      );
      await settleCalendarWidgetTest(tester);

      await tester.tap(find.byIcon(Icons.filter_list_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Filter by'), findsOneWidget);
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Apply Filters'), findsOneWidget);
      expect(find.text('Clear Filters'), findsOneWidget);
    });

    testWidgets('hovering color legend button shows appointment status colors', (tester) async {
      await pumpAppointmentCalendarPage(
        tester,
        authState: calendarAuthState(permissions: {PermissionKeys.appointmentsRead}),
      );
      await settleCalendarWidgetTest(tester);

      expect(calendarColorLegendButton, findsOneWidget);

      await hoverCalendarColorLegend(tester);

      expect(find.text('Appointment colors'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Checked in'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('No-show'), findsOneWidget);
    });
  });
}
