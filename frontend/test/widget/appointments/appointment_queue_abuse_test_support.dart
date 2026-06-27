import 'dart:async';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';
import 'appointment_calendar_test_support.dart';

const queueTestBranchId = calendarTestBranchAId;
const queueDoctorAId = calendarTestDoctorAId;
const queueDoctorBId = calendarTestDoctorBId;

const queueCheckedInAppointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const queueScheduledAppointmentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const queueSecondAppointmentId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const queueWideSurfaceSize = Size(1280, 900);
const queueNarrowSurfaceSize = Size(900, 900);

Finder get queueAdvanceButton => find.byKey(const Key('appointment_control_advance_status'));

DateTime queueTodayStartUtc({int hour = 10}) {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day, hour);
}

DateTime get queueShiftDate {
  final now = DateTime.now().toUtc();
  return DateTime(now.year, now.month, now.day);
}

AuthSessionState queueAuthState() {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: {
        PermissionKeys.appointmentsRead,
        PermissionKeys.appointmentsCreate,
        PermissionKeys.appointmentsCancel,
      },
      activeBranchId: queueTestBranchId,
    ).copyWith(organizationTimezone: 'UTC'),
  );
}

Map<String, dynamic> queueListRpcItem({
  required String id,
  required String patientName,
  String status = 'checked_in',
  String? doctorId,
  String? doctorName,
  DateTime? startUtc,
}) {
  final start = startUtc ?? queueTodayStartUtc();
  final end = start.add(const Duration(minutes: 30));
  return {
    'id': id,
    'patient_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'patient_name': patientName,
    if (doctorId != null) 'doctor_id': doctorId,
    if (doctorName != null) 'doctor_name': doctorName,
    'start_time': start.toIso8601String(),
    'end_time': end.toIso8601String(),
    'type': 'planned',
    'status': status,
    if (status == 'checked_in') 'checked_in_at': start.toIso8601String(),
  };
}

Map<String, dynamic> queueDetailRpcItem(Map<String, dynamic> listItem) {
  final start = DateTime.parse(listItem['start_time'] as String);
  return {
    'id': listItem['id'],
    'branch_id': queueTestBranchId,
    'patient_id': listItem['patient_id'],
    'patient_name': listItem['patient_name'],
    if (listItem['doctor_id'] != null) 'doctor_id': listItem['doctor_id'],
    if (listItem['doctor_name'] != null) 'doctor_name': listItem['doctor_name'],
    'start_time': listItem['start_time'],
    'end_time': listItem['end_time'],
    'type': listItem['type'],
    'status': listItem['status'],
    'queue_number': null,
    'notes': null,
    'cancel_reason': null,
    'created_at': start.subtract(const Duration(days: 1)).toIso8601String(),
    'updated_at': start.toIso8601String(),
    'created_by_display': 'Reception',
    if (listItem['checked_in_at'] != null) 'checked_in_at': listItem['checked_in_at'],
    if (listItem['in_progress_at'] != null) 'in_progress_at': listItem['in_progress_at'],
  };
}

AppointmentQueueShiftDoctorLookup queueSingleDoctorShiftLookup() {
  return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
    organizationTimezone: 'UTC',
    shifts: [
      ShiftListItem(
        id: 'queue-shift-single',
        branchId: queueTestBranchId,
        shiftDate: queueShiftDate,
        startTime: '00:00',
        endTime: '23:59',
        status: ShiftStatus.active,
        isUnassigned: false,
        assigneeNames: const ['Dr. Ada'],
        assigneeCount: 1,
      ),
    ],
    doctors: const [StaffListItem(id: queueDoctorAId, fullName: 'Dr. Ada', role: StaffRole.doctor, isActive: true)],
  );
}

AppointmentQueueShiftDoctorLookup queueMultiDoctorShiftLookup() {
  return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
    organizationTimezone: 'UTC',
    shifts: [
      ShiftListItem(
        id: 'queue-shift-multi',
        branchId: queueTestBranchId,
        shiftDate: queueShiftDate,
        startTime: '00:00',
        endTime: '23:59',
        status: ShiftStatus.active,
        isUnassigned: false,
        assigneeNames: const ['Dr. Ada', 'Dr. Ben'],
        assigneeCount: 2,
      ),
    ],
    doctors: calendarTestDoctors,
  );
}

class QueueScenarioRpcClient extends AppointmentRpcTestClient {
  QueueScenarioRpcClient({required this.listItems, this.statusUpdateDelay});

  final List<Map<String, dynamic>> listItems;
  final Duration? statusUpdateDelay;
  final Map<String, Map<String, dynamic>> _detailsById = {};

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      final payload = {
        'success': true,
        'data': {'items': listItems},
      };
      return FakePostgrestRpc(payload) as PostgrestFilterBuilder<T>;
    }

    if (fn == 'get_appointment') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      final appointmentId = params?['p_appointment_id']?.toString() ?? '';
      final detail =
          _detailsById[appointmentId] ??
          queueDetailRpcItem(
            listItems.firstWhere((item) => item['id'] == appointmentId, orElse: () => listItems.first),
          );
      return FakePostgrestRpc({'success': true, 'data': detail}) as PostgrestFilterBuilder<T>;
    }

    if (fn == 'update_appointment_status' && statusUpdateDelay != null) {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      final payload = {
        'success': true,
        'data': {
          'appointment_id': params?['p_appointment_id'],
          'status': params?['p_new_status'],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'checked_in_at': params?['p_new_status'] == 'checked_in' ? DateTime.now().toUtc().toIso8601String() : null,
          'in_progress_at': params?['p_new_status'] == 'in_progress' ? DateTime.now().toUtc().toIso8601String() : null,
        },
      };
      return _DelayedFakePostgrestRpc(payload, statusUpdateDelay!) as PostgrestFilterBuilder<T>;
    }

    return super.rpc(fn, params: params, get: get);
  }
}

class AlwaysFailingQueueListRpcClient extends AppointmentRpcTestClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      return FakePostgrestRpc({'success': false, 'error_code': 'INTERNAL', 'error_message': 'Queue unavailable'})
          as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class CountingQueueRealtimeClient implements AppointmentQueueRealtimeClient {
  var subscribeCount = 0;
  var unsubscribeCount = 0;

  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    subscribeCount += 1;
  }

  @override
  void unsubscribe() {
    unsubscribeCount += 1;
  }
}

class _DelayedFakePostgrestRpc extends FakePostgrestRpc {
  _DelayedFakePostgrestRpc(super.result, this.delay);

  final Duration delay;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<void>.delayed(delay).then((_) => super.then(onValue, onError: onError));
  }
}

Future<ProviderContainer> pumpAppointmentQueueRoutes(
  WidgetTester tester, {
  required AppointmentRpcTestClient client,
  AppointmentQueueShiftDoctorLookup? shiftLookup,
  CountingQueueRealtimeClient? realtimeClient,
  Size surfaceSize = queueWideSurfaceSize,
  String initialLocation = AppRoutes.appointmentsQueue,
}) async {
  final countingRealtime = realtimeClient ?? CountingQueueRealtimeClient();
  final lookup = shiftLookup ?? queueSingleDoctorShiftLookup();

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: AppRoutes.appointmentsQueue, builder: (context, state) => const AppointmentQueuePage()),
      GoRoute(path: AppRoutes.appointmentsCalendar, builder: (context, state) => const AppointmentCalendarPage()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(queueAuthState())),
        appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        appointmentQueueShiftDoctorLookupProvider.overrideWith((ref) async => lookup),
        appointmentQueueRealtimeClientProvider.overrideWithValue(countingRealtime),
        listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(CalendarStubBranchRepository())),
        listStaffUseCaseProvider.overrideWith((ref) => ListStaff(CalendarDoctorsStubStaffRepository())),
      ],
      child: ForuiAppScope(
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    ),
  );
  await tester.pump();

  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<ProviderContainer> waitForQueueLoaded(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final state = container.read(appointmentQueueProvider);
    if (!state.loading) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

Future<void> openQueueJourneyDialog(WidgetTester tester, String appointmentId) async {
  await tester.tap(find.byKey(Key('appointment_queue_status_$appointmentId')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> closeQueueJourneyDialog(WidgetTester tester) async {
  await tester.tap(find.text('Close'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> waitForJourneyDetailLoaded(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (queueAdvanceButton.evaluate().isNotEmpty) {
      break;
    }
  }
}

Future<void> navigateToQueueCalendar(WidgetTester tester) async {
  final context = tester.element(find.byType(AppointmentQueuePage));
  GoRouter.of(context).go(AppRoutes.appointmentsCalendar);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> navigateToQueuePage(WidgetTester tester) async {
  final context = tester.element(find.byType(AppointmentCalendarPage));
  GoRouter.of(context).go(AppRoutes.appointmentsQueue);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}
