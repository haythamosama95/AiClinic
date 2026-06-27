import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_schedule_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_session_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_waiting_column.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/appointment_queue_test_support.dart';
import '../../helpers/auth_test_support.dart';

const queueWideViewport = Size(1280, 900);
const queueNarrowViewport = Size(800, 900);
const queueShortViewport = Size(1280, 500);
const queueStatsWideViewport = Size(800, 400);
const queueStatsCompactViewport = Size(600, 400);

const focusBubbleColor = Color(0xFF14B8A6);
const queueTestBranchId = '00000000-0000-4000-8000-000000000001';

/// Fixed "now" for FE tests — midday today so shift lookup and appointment times stay aligned.
DateTime get queueFeFixedNow => queueTodayLocal(hour: 12, minute: 10);

const queueNavItem = ShellNavSingle(
  id: ShellNavConfig.queueNavItemId,
  label: 'Queue',
  icon: Icons.queue_outlined,
  badgeTone: ShellNavBadgeTone.success,
);

/// Sets logical viewport size via [TestFlutterView.physicalSizeTestValue].
void setQueueViewport(WidgetTester tester, Size logicalSize) {
  tester.binding.window.physicalSizeTestValue = logicalSize;
  tester.binding.window.devicePixelRatioTestValue = 1.0;
  addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
  addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);
}

class StaticQueueNotifier extends AppointmentQueueController {
  StaticQueueNotifier(this.initial);

  final AppointmentQueueState initial;

  @override
  AppointmentQueueState build() => initial;

  @override
  Future<void> refresh() async {}
}

class MutableQueueNotifier extends AppointmentQueueController {
  MutableQueueNotifier(this._state);

  AppointmentQueueState _state;

  @override
  AppointmentQueueState build() => _state;

  @override
  Future<void> refresh() async {}

  void replace(AppointmentQueueState next) {
    _state = next;
    state = next;
  }
}

class PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

AuthSessionState queueAuthState({
  Set<String> permissions = const {PermissionKeys.appointmentsRead, PermissionKeys.appointmentsCreate},
}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: queueTestBranchId),
  );
}

List<Override> queueFeProviderOverrides({
  required AppointmentQueueState queueState,
  AppointmentQueueShiftDoctorLookup? shiftLookup,
  AuthSessionState? authState,
  List<Override> extra = const [],
}) {
  final lookup = shiftLookup ?? sampleShiftLookup();
  return [
    authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(authState ?? queueAuthState())),
    appointmentQueueProvider.overrideWith(() => StaticQueueNotifier(queueState)),
    appointmentQueueShiftDoctorLookupProvider.overrideWith((ref) async => lookup),
    appointmentCalendarBranchesProvider.overrideWith((ref) async => [sampleQueueBranch()]),
    appointmentCalendarDoctorsProvider.overrideWith((ref) async => sampleQueueDoctors()),
    ...appointmentQueueTestOverrides().where(
      (override) =>
          override.origin != appointmentQueueProvider && override.origin != appointmentQueueShiftDoctorLookupProvider,
    ),
    ...extra,
  ];
}

/// Overrides safe to combine with [pumpQueueWidget], which already supplies auth and realtime stubs.
List<Override> queueFeWidgetOverrides({
  required AppointmentQueueState queueState,
  AppointmentQueueShiftDoctorLookup? shiftLookup,
  List<Override> extra = const [],
}) {
  final lookup = shiftLookup ?? sampleShiftLookup();
  return [
    appointmentQueueProvider.overrideWith(() => StaticQueueNotifier(queueState)),
    appointmentQueueShiftDoctorLookupProvider.overrideWith((ref) async => lookup),
    appointmentCalendarBranchesProvider.overrideWith((ref) async => [sampleQueueBranch()]),
    appointmentCalendarDoctorsProvider.overrideWith((ref) async => sampleQueueDoctors()),
    ...extra,
  ];
}

BranchListItem sampleQueueBranch() {
  return const BranchListItem(id: queueTestBranchId, name: 'Main Clinic', isActive: true, code: 'MAIN');
}

List<StaffListItem> sampleQueueDoctors() {
  return const [
    StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
    StaffListItem(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
  ];
}

AppointmentQueueShiftDoctorLookup sampleShiftLookup({DateTime? shiftDate}) {
  final date = shiftDate ?? queueTodayDate();
  return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
    organizationTimezone: 'UTC',
    shifts: [
      ShiftListItem(
        id: 'shift-1',
        branchId: queueTestBranchId,
        shiftDate: date,
        startTime: '00:00',
        endTime: '23:59',
        status: ShiftStatus.active,
        isUnassigned: false,
        assigneeNames: const ['Dr Alpha', 'Dr Beta'],
        assigneeCount: 2,
      ),
    ],
    doctors: sampleQueueDoctors(),
  );
}

AppointmentListItem queueItem({
  required String id,
  required String patientName,
  required DateTime startTime,
  AppointmentStatus status = AppointmentStatus.scheduled,
  String? doctorId,
  String? doctorName,
  DateTime? checkedInAt,
  DateTime? inProgressAt,
}) {
  return AppointmentListItem(
    id: id,
    patientId: 'patient-$id',
    patientName: patientName,
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: startTime,
    endTime: startTime.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
    updatedAt: startTime,
    checkedInAt: checkedInAt,
    inProgressAt: inProgressAt,
  );
}

List<AppointmentListItem> hourlyScheduleItems({
  required DateTime dayStart,
  required int count,
  AppointmentStatus status = AppointmentStatus.scheduled,
}) {
  return [
    for (var i = 0; i < count; i++)
      queueItem(
        id: 'sched-$i',
        patientName: 'Patient $i',
        startTime: dayStart.add(Duration(hours: i)),
        status: status,
      ),
  ];
}

AppointmentDetail sampleAppointmentDetail(AppointmentListItem item) {
  final now = queueFeFixedNow;
  return AppointmentDetail(
    id: item.id,
    branchId: queueTestBranchId,
    patientId: item.patientId,
    patientName: item.patientName,
    doctorId: item.doctorId,
    doctorName: item.doctorName,
    startTime: item.startTime,
    endTime: item.endTime,
    type: item.type,
    status: item.status,
    createdAt: now,
    updatedAt: now,
    notes: 'Loaded from detail RPC',
  );
}

Future<void> pumpQueuePage(
  WidgetTester tester, {
  required AppointmentQueueState queueState,
  Size viewport = queueWideViewport,
  AppointmentQueueShiftDoctorLookup? shiftLookup,
  AuthSessionState? authState,
  List<Override> extra = const [],
  bool settle = true,
  DateTime? clockTime,
}) async {
  final effectiveClock = clockTime ?? queueFeFixedNow;
  await withClock(Clock.fixed(effectiveClock), () async {
    setQueueViewport(tester, viewport);

    await tester.pumpWidget(
      ProviderScope(
        overrides: queueFeProviderOverrides(
          queueState: queueState,
          shiftLookup: shiftLookup,
          authState: authState,
          extra: extra,
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: AppointmentQueuePage()),
        ),
      ),
    );

    if (settle) {
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
      await container.read(appointmentQueueShiftDoctorLookupProvider.future);
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  });
}

Future<void> pumpQueueWidget(
  WidgetTester tester, {
  required Widget child,
  Size viewport = queueWideViewport,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  setQueueViewport(tester, viewport);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(queueAuthState())),
        appointmentQueueRealtimeClientProvider.overrideWithValue(FakeAppointmentQueueRealtimeClient()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        home: Scaffold(body: child),
      ),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder columnTitle(String label) => find.text(label);

Offset columnTitleCenter(WidgetTester tester, String label) {
  return tester.getCenter(columnTitle(label));
}

ListView scheduleListView(WidgetTester tester) {
  return tester.widget<ListView>(
    find.descendant(of: find.byType(AppointmentQueueScheduleColumn), matching: find.byType(ListView)),
  );
}

ListView sessionListView(WidgetTester tester) {
  return tester.widget<ListView>(
    find.descendant(of: find.byType(AppointmentQueueSessionColumn), matching: find.byType(ListView)),
  );
}

ListView waitingListView(WidgetTester tester) {
  return tester.widget<ListView>(
    find.descendant(of: find.byType(AppointmentQueueWaitingColumn), matching: find.byType(ListView)),
  );
}

Finder pageScrollView() {
  return find.descendant(of: find.byType(AppointmentQueuePage), matching: find.byType(SingleChildScrollView));
}

List<dynamic> scheduleTimelinePainters(WidgetTester tester) {
  return find
      .descendant(of: find.byType(AppointmentQueueScheduleColumn), matching: find.byType(CustomPaint))
      .evaluate()
      .map((element) => (element.widget as CustomPaint).painter)
      .where((painter) => painter != null)
      .where((painter) => painter.runtimeType.toString().contains('QueueTimelineGutterPainter'))
      .toList();
}

InkWell? doctorRowInkWell(WidgetTester tester, String doctorName) {
  final row = find.ancestor(of: find.text(doctorName), matching: find.byType(InkWell));
  if (row.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<InkWell>(row.first);
}

bool isRectInViewport(WidgetTester tester, Rect rect) {
  final view = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.top >= 0 && rect.bottom <= view.height;
}
