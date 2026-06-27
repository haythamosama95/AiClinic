import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/core/ui/demo/theme_showcase_page.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/buttons/app_button.dart';
import 'package:ai_clinic/core/ui/widgets/layouts/app_notched_card.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_detail_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_status_actions.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart' hide AppointmentType;

import '../../helpers/appointment_queue_test_support.dart';
import '../../helpers/auth_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../widget/appointments/appointment_calendar_test_support.dart';
import '../../widget/shell/shell_test_support.dart';

const _doctorAId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _doctorBId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

class _PresetAppointmentCalendarNotifier extends AppointmentCalendarController {
  _PresetAppointmentCalendarNotifier(this._initial);

  final AppointmentCalendarState _initial;

  @override
  AppointmentCalendarState build() => _initial;
}

class _PresetAppointmentQueueNotifier extends AppointmentQueueController {
  _PresetAppointmentQueueNotifier(this._initial);

  final AppointmentQueueState _initial;

  @override
  AppointmentQueueState build() => _initial;

  @override
  Future<void> refresh() async {}
}

AppointmentListItem _listItem({
  required String id,
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? startTime,
  String? doctorId,
  String? doctorName,
}) {
  final start = startTime ?? DateTime.utc(2026, 6, 2, 10);
  return AppointmentListItem(
    id: id,
    patientId: _patientId,
    patientName: 'Test Patient',
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
  );
}

AppointmentDetail _detail({
  required String id,
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? startTime,
  String? doctorId,
  String? doctorName,
}) {
  final start = startTime ?? DateTime.utc(2026, 6, 2, 10);
  return AppointmentDetail(
    id: id,
    branchId: calendarTestBranchAId,
    patientId: _patientId,
    patientName: 'Test Patient',
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
    createdAt: start.subtract(const Duration(days: 1)),
    updatedAt: start.subtract(const Duration(days: 1)),
  );
}

AppointmentCalendarState _calendarState(List<AppointmentListItem> items) {
  return AppointmentCalendarState(
    mode: AppointmentCalendarMode.day,
    focusDate: DateTime.utc(2026, 6, 2),
    items: items,
    loading: false,
  );
}

AuthSessionState _detailAuthState({String organizationTimezone = 'UTC'}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: {
        PermissionKeys.appointmentsCreate,
        PermissionKeys.appointmentsRead,
        PermissionKeys.appointmentsCancel,
      },
      activeBranchId: calendarTestBranchAId,
      branchIds: const [calendarTestBranchAId],
    ).copyWith(organizationTimezone: organizationTimezone),
  );
}

AppointmentQueueShiftDoctorLookup _twoDoctorShiftLookup({DateTime? shiftDate}) {
  final date = shiftDate ?? DateTime.utc(2026, 6, 2);
  return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
    organizationTimezone: 'UTC',
    shifts: [
      ShiftListItem(
        id: 'shift-1',
        branchId: calendarTestBranchAId,
        shiftDate: date,
        startTime: '00:00',
        endTime: '23:59',
        status: ShiftStatus.active,
        isUnassigned: false,
        assigneeNames: const ['Dr Alpha', 'Dr Beta'],
        assigneeCount: 2,
      ),
    ],
    doctors: const [
      StaffListItem(id: _doctorAId, fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
      StaffListItem(id: _doctorBId, fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
    ],
  );
}

Future<void> _pumpCalendarWithQueueShared(
  WidgetTester tester, {
  required AuthSessionState authState,
  AppointmentRpcTestClient? rpcClient,
  List<Override> extraOverrides = const [],
}) async {
  final client = rpcClient ?? AppointmentRpcTestClient();

  await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(authState)),
        appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(CalendarStubBranchRepository())),
        listStaffUseCaseProvider.overrideWith((ref) => ListStaff(CalendarStubStaffRepository())),
        ...appointmentQueueTestOverrides(),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child!),
        home: const Scaffold(body: AppointmentCalendarPage()),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpDetailStatusActions(
  WidgetTester tester, {
  required AppointmentDetail detail,
  required List<AppointmentListItem> calendarItems,
  List<AppointmentListItem> queueItems = const [],
  AppointmentQueueShiftDoctorLookup? shiftLookup,
  AuthSessionState? authState,
}) async {
  final client = AppointmentRpcTestClient();
  final lookup = shiftLookup ?? AppointmentQueueShiftDoctorLookup.empty;

  await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(authState ?? _detailAuthState())),
        appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        appointmentCalendarProvider.overrideWith(
          () => _PresetAppointmentCalendarNotifier(_calendarState(calendarItems)),
        ),
        appointmentQueueProvider.overrideWith(
          () => _PresetAppointmentQueueNotifier(AppointmentQueueState(items: queueItems)),
        ),
        appointmentQueueShiftDoctorLookupProvider.overrideWith((ref) async => lookup),
        ...appointmentQueueTestOverrides().where(
          (override) =>
              override.origin != appointmentQueueProvider &&
              override.origin != appointmentQueueShiftDoctorLookupProvider,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child!),
        home: Scaffold(body: AppointmentDetailStatusActions(detail: detail)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  if (shiftLookup != null) {
    final element = tester.element(find.byType(AppointmentDetailStatusActions));
    final container = ProviderScope.containerOf(element);
    await container.read(appointmentQueueShiftDoctorLookupProvider.future);
    await tester.pump();
  }
}

Future<void> _pumpCalendarDetailRoutes(WidgetTester tester, {AppointmentRpcTestClient? rpcClient}) async {
  final client = rpcClient ?? AppointmentRpcTestClient();

  await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: AppRoutes.appointmentsCalendar,
    routes: [
      GoRoute(
        path: AppRoutes.appointmentsCalendar,
        builder: (context, state) => const Scaffold(body: AppointmentCalendarPage()),
      ),
      GoRoute(
        path: '${AppRoutes.appointments}/:appointmentId',
        builder: (context, state) {
          final appointmentId = state.pathParameters['appointmentId']!;
          return Scaffold(body: AppointmentDetailPage(appointmentId: appointmentId));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(calendarAuthStateWithCreate())),
        appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(CalendarStubBranchRepository())),
        listStaffUseCaseProvider.overrideWith((ref) => ListStaff(CalendarStubStaffRepository())),
        ...appointmentQueueTestOverrides(),
      ],
      child: ForuiAppScope(
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('REG-001 — Calendar still loads after queue provider shared', () {
    testWidgets('calendar renders and booking entry stays available with shared queue providers', (tester) async {
      await _pumpCalendarWithQueueShared(tester, authState: calendarAuthStateWithCreate());
      await waitForCalendarLoaded(tester);

      expect(find.byType(AppointmentCalendarPage), findsOneWidget);
      expect(find.byType(SfCalendar), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Book Appointment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Book appointment'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail status advance still works and calendar remains usable afterward', (tester) async {
      final client = AppointmentRpcTestClient();

      await _pumpCalendarDetailRoutes(tester, rpcClient: client);
      await waitForCalendarLoaded(tester);
      await tapCalendarViewTab(tester, 'Day');
      await waitForAppointmentTileReveal(tester);

      await tapFirstCalendarAppointment(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AppointmentDetailPage), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.rpcCallCounts['update_appointment_status'], 1);

      await tester.pageBack();
      await tester.pump();
      await settleCalendarWidgetTest(tester);

      expect(find.byType(AppointmentCalendarPage), findsOneWidget);
      expect(find.byType(SfCalendar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses calendar siblings when queue is empty for in-progress blocking', (tester) async {
      final start = DateTime.utc(2026, 6, 2, 10);
      final active = _listItem(
        id: 'active',
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: _doctorAId,
        doctorName: 'Dr Alpha',
      );
      final waiting = _listItem(
        id: 'waiting',
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: _doctorAId,
        doctorName: 'Dr Alpha',
      );

      await withClock(Clock.fixed(DateTime.utc(2026, 6, 2, 12)), () async {
        await _pumpDetailStatusActions(
          tester,
          detail: _detail(
            id: 'waiting',
            status: AppointmentStatus.checkedIn,
            startTime: waiting.startTime,
            doctorId: _doctorAId,
            doctorName: 'Dr Alpha',
          ),
          calendarItems: [active, waiting],
        );

        final advanceButton = tester.widget<AppButton>(find.byKey(const Key('appointment_control_advance_status')));
        expect(advanceButton.onPressed, isNull);
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(
            of: find.byKey(const Key('appointment_control_advance_status')),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message.toString(), contains('already has a patient in progress'));
      });
    });
  });

  group('REG-002 — Shell settings nav not highlighted', () {
    testWidgets('settings route clears dashboard and appointments nav selection', (tester) async {
      await pumpAuthenticatedShell(tester, initialLocation: AppRoutes.home);

      final dashboardBefore = tester.widget<ShellNavItemRow>(find.widgetWithText(ShellNavItemRow, 'Dashboard'));
      expect(dashboardBefore.isSelected, isTrue);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      final dashboardAfter = tester.widget<ShellNavItemRow>(find.widgetWithText(ShellNavItemRow, 'Dashboard'));
      expect(dashboardAfter.isSelected, isFalse);
      expect(find.text('Settings content'), findsOneWidget);

      await tester.tap(find.text('Appointments'));
      await tester.pumpAndSettle();

      final calendarRow = tester.widget<ShellNavItemRow>(find.widgetWithText(ShellNavItemRow, 'Calendar'));
      final queueRow = tester.widget<ShellNavItemRow>(find.widgetWithText(ShellNavItemRow, 'Queue'));
      expect(calendarRow.isSelected, isFalse);
      expect(queueRow.isSelected, isFalse);
    });

    testWidgets('direct settings route does not highlight shell nav items', (tester) async {
      await pumpAuthenticatedShell(tester, initialLocation: AppRoutes.settings);

      expect(find.text('Settings content'), findsOneWidget);

      final dashboardRow = tester.widget<ShellNavItemRow>(find.widgetWithText(ShellNavItemRow, 'Dashboard'));
      expect(dashboardRow.isSelected, isFalse);

      await tester.tap(find.text('Appointments'));
      await tester.pumpAndSettle();

      final queueRow = tester.widget<ShellNavItemRow>(find.widgetWithText(ShellNavItemRow, 'Queue'));
      expect(queueRow.isSelected, isFalse);
    });
  });

  group('REG-003 — Dashboard without showcase cards', () {
    testWidgets('dashboard has no notched card demo clutter', (tester) async {
      await pumpShellWidget(tester, child: const DashboardPage());

      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.byType(AppNotchedCard), findsNothing);
      expect(find.text('Billing overview'), findsNothing);
      expect(find.text('Collections and adjustments'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('REG-004 — Theme showcase slider', () {
    testWidgets('adjusting feedback slider does not throw layout errors', (tester) async {
      await tester.binding.setSurfaceSize(shellSurfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child!),
            home: const ThemeShowcasePage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final slider = find.byType(Slider);
      await tester.scrollUntilVisible(slider, 500, scrollable: find.byType(Scrollable).at(0));
      expect(slider, findsOneWidget);

      await tester.drag(slider, const Offset(120, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('REG-005 — Detail status actions from appointment detail page', () {
    testWidgets('scheduled appointment offers Confirm action', (tester) async {
      await _pumpDetailStatusActions(
        tester,
        detail: _detail(id: 'scheduled'),
        calendarItems: [_listItem(id: 'scheduled')],
      );

      expect(find.text('Confirm'), findsOneWidget);
      final advanceButton = tester.widget<AppButton>(find.byKey(const Key('appointment_control_advance_status')));
      expect(advanceButton.onPressed, isNotNull);
    });

    testWidgets('check-in is blocked before appointment day', (tester) async {
      final today = DateTime.now().toUtc();
      final appointmentDay = DateTime.utc(today.year, today.month, today.day + 1, 10);
      final dayBefore = DateTime.utc(today.year, today.month, today.day, 12);

      await withClock(Clock.fixed(dayBefore), () async {
        await _pumpDetailStatusActions(
          tester,
          detail: _detail(id: 'confirmed', status: AppointmentStatus.confirmed, startTime: appointmentDay),
          calendarItems: [_listItem(id: 'confirmed', status: AppointmentStatus.confirmed, startTime: appointmentDay)],
          authState: _detailAuthState(organizationTimezone: 'UTC'),
        );

        expect(find.text('Check in'), findsOneWidget);
        final advanceButton = tester.widget<AppButton>(find.byKey(const Key('appointment_control_advance_status')));
        expect(advanceButton.onPressed, isNull);
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(
            of: find.byKey(const Key('appointment_control_advance_status')),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message.toString(), contains('only available on the appointment day'));
      });
    });

    testWidgets('start is blocked when preferred doctor already has in-progress visit', (tester) async {
      final start = DateTime.utc(2026, 6, 2, 10);
      final active = _listItem(
        id: 'active',
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: _doctorAId,
        doctorName: 'Dr Alpha',
      );
      final waiting = _listItem(
        id: 'waiting',
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: _doctorAId,
        doctorName: 'Dr Alpha',
      );

      await _pumpDetailStatusActions(
        tester,
        detail: _detail(
          id: 'waiting',
          status: AppointmentStatus.checkedIn,
          startTime: waiting.startTime,
          doctorId: _doctorAId,
          doctorName: 'Dr Alpha',
        ),
        calendarItems: [active, waiting],
      );

      expect(find.text('Start'), findsOneWidget);
      final advanceButton = tester.widget<AppButton>(find.byKey(const Key('appointment_control_advance_status')));
      expect(advanceButton.onPressed, isNull);
    });

    testWidgets('start opens doctor picker when multiple shift doctors are available', (tester) async {
      final today = DateTime.now().toUtc();
      final start = DateTime.utc(today.year, today.month, today.day, 11);
      final checkedIn = _listItem(id: 'checked-in', status: AppointmentStatus.checkedIn, startTime: start);

      await withClock(Clock.fixed(DateTime.utc(today.year, today.month, today.day, 12)), () async {
        await _pumpDetailStatusActions(
          tester,
          detail: _detail(id: 'checked-in', status: AppointmentStatus.checkedIn, startTime: start),
          calendarItems: [checkedIn],
          shiftLookup: _twoDoctorShiftLookup(shiftDate: DateTime(today.year, today.month, today.day)),
        );

        await tester.tap(find.byKey(const Key('appointment_control_advance_status')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Confirm doctor'), findsOneWidget);
        expect(find.text('Dr Alpha'), findsOneWidget);
        expect(find.text('Dr Beta'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(milliseconds: 200));
      });
    });
  });
}
