import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_header_bar.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

const calendarWidgetSurfaceSize = Size(1280, 900);

/// Bounded pumps for Syncfusion calendar widget tests (never use [pumpAndSettle]).
Future<void> settleCalendarWidgetTest(
  WidgetTester tester, {
  int passes = 2,
  Duration step = const Duration(milliseconds: 300),
}) async {
  for (var i = 0; i < passes; i++) {
    await tester.pump(step);
  }
}

class PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class MutableAuthSessionNotifier extends AuthSessionNotifier {
  MutableAuthSessionNotifier(this._state);

  AuthSessionState _state;

  @override
  AuthSessionState build() => _state;

  void replace(AuthSessionState next) {
    _state = next;
    state = next;
  }
}

Future<void> pumpAppointmentCalendarPage(
  WidgetTester tester, {
  required AuthSessionState authState,
  SupabaseClient? rpcClient,
  BranchRepository? branchRepository,
  CalendarStubStaffRepository? staffRepository,
  FakePatientRepository? patientRepository,
  ThemeData? theme,
  Size? surfaceSize,
}) async {
  final client = rpcClient ?? AppointmentRpcTestClient();
  final patients = patientRepository ?? FakePatientRepository();
  final size = surfaceSize ?? calendarWidgetSurfaceSize;

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(authState)),
        appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        listBranchesUseCaseProvider.overrideWith(
          (ref) => ListBranches(branchRepository ?? CalendarStubBranchRepository()),
        ),
        listStaffUseCaseProvider.overrideWith((ref) => ListStaff(staffRepository ?? CalendarStubStaffRepository())),
        patientRepositoryProvider.overrideWithValue(patients),
        searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(ref.watch(patientRepositoryProvider))),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child!),
        home: const Scaffold(body: AppointmentCalendarPage()),
      ),
    ),
  );
  await tester.pump();
}

AuthSessionState calendarAuthState({
  Set<String> permissions = const {'appointments.read'},
  String? activeBranchId,
  List<String> branchIds = const [calendarTestBranchAId],
}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: activeBranchId, branchIds: branchIds),
  );
}

SfCalendar calendarWidget(WidgetTester tester) {
  return tester.widget<SfCalendar>(find.byType(SfCalendar));
}

Future<ProviderContainer> waitForCalendarLoaded(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final state = container.read(appointmentCalendarProvider);
    if (!state.loading) {
      break;
    }
  }
  await settleCalendarWidgetTest(tester);
  return container;
}

Future<void> tapCalendarViewTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder get calendarFilterButton =>
    find.descendant(of: find.byType(AppointmentCalendarHeaderBar), matching: find.byIcon(Icons.filter_list_outlined));

Finder get calendarColorLegendButton =>
    find.descendant(of: find.byType(AppointmentCalendarHeaderBar), matching: find.byIcon(Icons.legend_toggle_outlined));

Future<void> hoverCalendarColorLegend(WidgetTester tester) async {
  final button = calendarColorLegendButton;
  final center = tester.getCenter(button);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: center);
  await tester.pump();
  await gesture.moveTo(center);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> openCalendarFilterPopover(WidgetTester tester) async {
  await tester.tap(calendarFilterButton, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Badge calendarFilterBadge(WidgetTester tester) {
  return tester.widget<Badge>(find.ancestor(of: calendarFilterButton, matching: find.byType(Badge)));
}

Future<void> selectCalendarBranchFilter(WidgetTester tester, String branchName) async {
  await tester.tap(find.descendant(of: find.byType(AppFilterSelect<String?>), matching: find.byType(EditableText)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text(branchName).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> selectCalendarDoctorFilter(WidgetTester tester, String doctorName) async {
  await tester.tap(find.descendant(of: find.byType(AppFilterSelect<String>), matching: find.byType(EditableText)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text(doctorName).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> applyCalendarFilters(WidgetTester tester) async {
  await tester.tap(find.text('Apply Filters'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> clearCalendarFilters(WidgetTester tester) async {
  await tester.tap(find.text('Clear Filters'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> tapCalendarNextPeriod(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chevron_right));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> tapCalendarPreviousPeriod(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chevron_left));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> tapCalendarToday(WidgetTester tester) async {
  await tester.tap(find.text('Today'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

String expectedCalendarHeaderTitle(AppointmentCalendarState state) {
  return AppointmentCalendarDisplay.headerTitle(state.mode, state.focusDate);
}

/// Nearest Sunday on or before [date].
DateTime nearestSunday(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return normalized.subtract(Duration(days: normalized.weekday % 7));
}

AuthSessionState calendarAuthStateWithCreate({List<String> branchIds = const [calendarTestBranchAId]}) {
  return calendarAuthState(
    permissions: {PermissionKeys.appointmentsCreate, PermissionKeys.appointmentsRead},
    branchIds: branchIds,
  );
}

Future<void> invokeCalendarTap(
  WidgetTester tester, {
  required DateTime date,
  CalendarElement element = CalendarElement.calendarCell,
  List<dynamic>? appointments,
  CalendarResource? resource,
}) async {
  final calendar = calendarWidget(tester);
  final onTap = calendar.onTap;
  expect(onTap, isNotNull);
  onTap!(CalendarTapDetails(appointments, date, element, resource));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> tapFirstCalendarAppointment(WidgetTester tester) async {
  final calendar = calendarWidget(tester);
  final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
  final appointments = dataSource.appointments;
  expect(appointments, isNotEmpty);
  final appointment = appointments!.first;
  await invokeCalendarTap(
    tester,
    date: appointment.startTime,
    element: CalendarElement.appointment,
    appointments: [appointment],
  );
}

Future<void> waitForAppointmentTileReveal(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
}

/// Waits for appointment data without exceeding the skeleton reveal delay.
Future<ProviderContainer> waitForCalendarDataBeforeReveal(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final state = container.read(appointmentCalendarProvider);
    if (!state.loading && state.items.isNotEmpty) {
      break;
    }
  }
  await tester.pump();
  return container;
}

Appointment firstCalendarAppointment(WidgetTester tester) {
  final calendar = calendarWidget(tester);
  final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
  final appointments = dataSource.appointments;
  expect(appointments, isNotEmpty);
  return appointments!.first as Appointment;
}

Appointment? calendarAppointmentById(WidgetTester tester, String id) {
  final calendar = calendarWidget(tester);
  final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
  for (final entry in dataSource.appointments ?? const <dynamic>[]) {
    if (entry is Appointment && entry.id?.toString() == id) {
      return entry;
    }
  }
  return null;
}

/// Simulates a drag gesture via Syncfusion callbacks (avoids real pointer drags).
/// Ends a drag with no drop target (e.g. dragged off the calendar viewport).
Future<void> invokeCalendarDragCancel(WidgetTester tester, {required Appointment appointment}) async {
  final calendar = calendarWidget(tester);
  expect(calendar.onDragStart, isNotNull);
  expect(calendar.onDragEnd, isNotNull);

  calendar.onDragStart!(AppointmentDragStartDetails(appointment, null));
  await tester.pump();
  calendar.onDragEnd!(AppointmentDragEndDetails(appointment, null, null, null));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> invokeCalendarDrag(
  WidgetTester tester, {
  required Appointment appointment,
  required DateTime droppingTime,
  CalendarResource? sourceResource,
  CalendarResource? targetResource,
  DateTime? draggingTime,
}) async {
  final calendar = calendarWidget(tester);
  expect(calendar.onDragStart, isNotNull);
  expect(calendar.onDragEnd, isNotNull);

  calendar.onDragStart!(AppointmentDragStartDetails(appointment, sourceResource));
  await tester.pump();

  if (draggingTime != null && calendar.onDragUpdate != null) {
    calendar.onDragUpdate!(
      AppointmentDragUpdateDetails(appointment, sourceResource, targetResource, null, draggingTime),
    );
    await tester.pump();
  }

  calendar.onDragEnd!(AppointmentDragEndDetails(appointment, sourceResource, targetResource, droppingTime));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Simulates a resize gesture via Syncfusion callbacks.
Future<void> invokeCalendarResize(
  WidgetTester tester, {
  required Appointment appointment,
  required DateTime startTime,
  required DateTime endTime,
  CalendarResource? resource,
  List<DateTime>? updateTimes,
}) async {
  final calendar = calendarWidget(tester);
  expect(calendar.onAppointmentResizeStart, isNotNull);
  expect(calendar.onAppointmentResizeEnd, isNotNull);

  calendar.onAppointmentResizeStart!(AppointmentResizeStartDetails(appointment, resource));
  await tester.pump();

  if (updateTimes != null && calendar.onAppointmentResizeUpdate != null) {
    for (final resizingTime in updateTimes) {
      calendar.onAppointmentResizeUpdate!(AppointmentResizeUpdateDetails(appointment, resource, resizingTime, null));
      await tester.pump();
    }
  }

  calendar.onAppointmentResizeEnd!(AppointmentResizeEndDetails(appointment, resource, startTime, endTime));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> confirmRescheduleDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> cancelRescheduleDialog(WidgetTester tester) async {
  await tester.tap(find.text('Cancel').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

AppointmentRpcTestClient calendarClientWithItems(List<Map<String, dynamic>> items) {
  return AppointmentRpcTestClient()
    ..rpcResults['list_appointments'] = {
      'success': true,
      'data': {'items': items},
    };
}
