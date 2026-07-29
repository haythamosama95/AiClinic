import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart' hide AppointmentType;

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/models/appointment_section.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_section_nav.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/data/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

/// Tracks calls made through [AppointmentCalendarToolbar] and page actions.
class SpyAppointmentCalendarController extends AppointmentCalendarController {
  SpyAppointmentCalendarController(this._state);

  AppointmentCalendarState _state;

  var refreshCallCount = 0;
  var previousPeriodCallCount = 0;
  var nextPeriodCallCount = 0;
  var goToTodayCallCount = 0;
  var setModeCallCount = 0;
  AppointmentCalendarMode? lastSetMode;
  var setFocusDateCallCount = 0;
  DateTime? lastSetFocusDate;
  var setTimeIntervalCallCount = 0;
  int? lastSetTimeIntervalMinutes;

  void replaceState(AppointmentCalendarState next) {
    _state = next;
    state = next;
  }

  @override
  AppointmentCalendarState build() => _state;

  @override
  Future<void> refresh() async {
    refreshCallCount++;
  }

  @override
  Future<void> previousPeriod() async {
    previousPeriodCallCount++;
  }

  @override
  Future<void> nextPeriod() async {
    nextPeriodCallCount++;
  }

  @override
  Future<void> goToToday() async {
    goToTodayCallCount++;
  }

  @override
  Future<void> setMode(AppointmentCalendarMode mode) async {
    setModeCallCount++;
    lastSetMode = mode;
  }

  @override
  Future<void> setFocusDate(DateTime date) async {
    setFocusDateCallCount++;
    lastSetFocusDate = DateTime(date.year, date.month, date.day);
  }

  @override
  void setTimeIntervalMinutes(int minutes) {
    setTimeIntervalCallCount++;
    lastSetTimeIntervalMinutes = minutes;
    if (!AppointmentCalendarDisplay.supportedTimeIntervalMinutes.contains(minutes) ||
        minutes == _state.timeIntervalMinutes) {
      return;
    }
    _state = _state.copyWith(timeIntervalMinutes: minutes);
    state = _state;
  }
}

/// Default authenticated session with full appointment access.
AuthSessionState calendarAuthSession({
  Set<String>? permissions,
  String? activeBranchId,
  List<String>? branchIds,
}) {
  final branch = activeBranchId ?? calendarTestBranchAId;
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? RolePermissionSeed.administrator,
      activeBranchId: branch,
      branchIds: branchIds ?? [branch],
    ),
  );
}

/// Baseline calendar state for widget tests (week view, success payload).
AppointmentCalendarState defaultCalendarState({
  AppointmentCalendarMode mode = AppointmentCalendarMode.week,
  DateTime? focusDate,
  List<AppointmentListItem>? items,
  String? selectedBranchId,
  String? selectedDoctorId,
  Set<AppointmentStatus> selectedStatuses = const {},
  int timeIntervalMinutes = AppointmentCalendarDisplay.defaultTimeIntervalMinutes,
  bool loading = false,
  String? error,
}) {
  final focus = focusDate ?? DateTime(2026, 6, 15);
  return AppointmentCalendarState(
    mode: mode,
    focusDate: DateTime(focus.year, focus.month, focus.day),
    items: items ?? [calendarAppointmentItem()],
    selectedBranchId: selectedBranchId ?? calendarTestBranchAId,
    selectedDoctorId: selectedDoctorId,
    selectedStatuses: selectedStatuses,
    timeIntervalMinutes: timeIntervalMinutes,
    loading: loading,
    error: error,
  );
}

List<BranchListItem> calendarTestBranches({BranchWorkingSchedule? schedule}) {
  final workingSchedule = schedule ?? BranchWorkingSchedule.defaultSchedule();
  return [
    BranchListItem(
      id: calendarTestBranchAId,
      name: 'Main',
      code: 'M1',
      isActive: true,
      workingSchedule: workingSchedule,
    ),
    BranchListItem(
      id: calendarTestBranchBId,
      name: 'North',
      code: 'N1',
      isActive: true,
      workingSchedule: workingSchedule,
    ),
  ];
}

List<StaffListItem> calendarTestDoctorsWithBranches() {
  return [
    StaffListItem(
      id: calendarTestDoctorAId,
      fullName: 'Dr. Ada',
      role: StaffRole.doctor,
      isActive: true,
      branches: [const StaffBranchLabel(id: calendarTestBranchAId, name: 'Main')],
    ),
    StaffListItem(
      id: calendarTestDoctorBId,
      fullName: 'Dr. Ben',
      role: StaffRole.doctor,
      isActive: true,
      branches: [const StaffBranchLabel(id: calendarTestBranchAId, name: 'Main')],
    ),
  ];
}

AppointmentListItem calendarAppointmentItem({
  String id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  String patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  String patientName = 'Test Patient',
  String? patientMrn,
  String? doctorId = calendarTestDoctorAId,
  String? doctorName = 'Dr. Ada',
  DateTime? start,
  DateTime? end,
  AppointmentStatus status = AppointmentStatus.scheduled,
}) {
  final startTime = start ?? DateTime(2026, 6, 15, 10, 0);
  final endTime = end ?? startTime.add(const Duration(minutes: 30));
  return AppointmentListItem(
    id: id,
    patientId: patientId,
    patientName: patientName,
    patientMrn: patientMrn,
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: startTime,
    endTime: endTime,
    type: AppointmentType.planned,
    status: status,
  );
}

CalendarAppointmentDetails calendarTileDetails({
  required String id,
  required String subject,
  required DateTime start,
  required DateTime end,
  Rect bounds = const Rect.fromLTWH(0, 0, 300, 56),
}) {
  final appointment = Appointment(
    id: id,
    subject: subject,
    startTime: start,
    endTime: end,
  );
  return CalendarAppointmentDetails(
    start,
    [appointment],
    bounds,
    isMoreAppointmentRegion: false,
  );
}

/// Branch repository that always throws (filter error-state tests).
class ThrowingCalendarBranchRepository implements BranchRepository {
  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    throw Exception('Could not load branches.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Staff repository that always throws (filter error-state tests).
class ThrowingCalendarStaffRepository implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    throw Exception('Could not load doctors.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> calendarProviderOverrides({
  AuthSessionState? auth,
  SpyAppointmentCalendarController? calendarController,
  AppointmentCalendarState? calendarState,
  List<BranchListItem>? branches,
  List<StaffListItem>? doctors,
  AppointmentRpcTestClient? rpcClient,
  List<Override> extraOverrides = const [],
}) {
  final state = calendarState ?? defaultCalendarState();
  final spy = calendarController ?? SpyAppointmentCalendarController(state);
  if (calendarController == null && calendarState != null) {
    spy.replaceState(state);
  }

  final client = rpcClient ?? AppointmentRpcTestClient();

  return [
    authSessionProvider.overrideWith(
      () => MutableAuthSessionNotifier(auth ?? calendarAuthSession()),
    ),
    appointmentCalendarProvider.overrideWith(() => spy),
    appointmentCalendarBranchesProvider.overrideWith(
      (ref) async => branches ?? calendarTestBranches(),
    ),
    appointmentCalendarDoctorsProvider.overrideWith(
      (ref) async => doctors ?? calendarTestDoctorsWithBranches(),
    ),
    appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
    branchRepositoryProvider.overrideWithValue(CalendarStubBranchRepository(branches: branches)),
    staffAdminRepositoryProvider.overrideWithValue(
      CalendarDoctorsStubStaffRepository(doctors: doctors ?? calendarTestDoctorsWithBranches()),
    ),
    ...extraOverrides,
  ];
}

/// Pumps [child] inside the canonical calendar widget-test shell.
Future<SpyAppointmentCalendarController> pumpCalendarSurface(
  WidgetTester tester, {
  required Widget child,
  AuthSessionState? auth,
  SpyAppointmentCalendarController? calendarController,
  AppointmentCalendarState? calendarState,
  List<BranchListItem>? branches,
  List<StaffListItem>? doctors,
  AppointmentRpcTestClient? rpcClient,
  List<Override> extraOverrides = const [],
  Size surfaceSize = const Size(1280, 900),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final state = calendarState ?? defaultCalendarState();
  final spy = calendarController ?? SpyAppointmentCalendarController(state);
  if (calendarController == null && calendarState != null) {
    spy.replaceState(state);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: calendarProviderOverrides(
        auth: auth,
        calendarController: spy,
        calendarState: state,
        branches: branches,
        doctors: doctors,
        rpcClient: rpcClient,
        extraOverrides: extraOverrides,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );

  return spy;
}

/// Minimal Material shell for dialog-only widget tests.
Future<void> pumpDialogShell(
  WidgetTester tester, {
  required Widget home,
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
}

/// GoRouter with lightweight stub pages for [AppointmentSectionNav] tests.
GoRouter createAppointmentSectionNavRouter({
  required Widget navHost,
  String initialLocation = AppRoutes.appointmentsCalendar,
}) {
  Widget stub(String label) => Scaffold(body: Center(child: Text('stub:$label')));

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.appointments,
        builder: (_, _) => stub('hub'),
        routes: [
          GoRoute(
            path: 'book',
            builder: (_, _) => stub('book'),
          ),
          GoRoute(
            path: 'queue',
            builder: (_, _) => stub('queue'),
          ),
          GoRoute(
            path: 'calendar',
            builder: (_, _) => navHost,
          ),
        ],
      ),
    ],
  );
}

Future<GoRouter> pumpAppointmentSectionNav(
  WidgetTester tester, {
  required AppointmentSection activeSection,
  String initialLocation = AppRoutes.appointmentsCalendar,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = createAppointmentSectionNavRouter(
    navHost: AppointmentSectionNav(activeSection: activeSection),
    initialLocation: initialLocation,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: calendarProviderOverrides(),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );

  return router;
}
