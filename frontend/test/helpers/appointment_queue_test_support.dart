import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_waiting_column.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/appointment_calendar_test_support.dart';
import '../support/appointment_rpc_test_client.dart';
import '../support/fake_postgrest_rpc.dart';
import '../widget/appointments/appointment_booking_sheet_test_support.dart';
import '../widget/appointments/appointment_calendar_test_support.dart';
import 'auth_test_support.dart';
import 'patient_test_support.dart';

/// Default queue widget test viewport (wide three-column layout).
const queueWidgetSurfaceSize = Size(1280, 900);

const queueTestBranchId = calendarTestBranchAId;
const queueTestDoctorAlphaId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const queueTestDoctorBetaId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const queueTestPatientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const queueApptEarlyId = '11111111-1111-4111-8111-111111111111';
const queueApptLateId = '22222222-2222-4222-8222-222222222222';
const queueApptScheduledId = '33333333-3333-4333-8333-333333333333';
const queueApptConfirmedId = '44444444-4444-4444-8444-444444444444';
const queueApptCheckedInId = '55555555-5555-4555-8555-555555555555';
const queueApptWaitingId = '66666666-6666-4666-8666-666666666666';
const queueApptActiveAlphaId = '77777777-7777-4777-8777-777777777777';
const queueApptActiveBetaId = '88888888-8888-4888-8888-888888888888';
const queueApptNewBookingId = '99999999-9999-4999-8999-999999999999';

const queueTestDoctors = [
  StaffListItem(id: queueTestDoctorAlphaId, fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
  StaffListItem(id: queueTestDoctorBetaId, fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
];

/// No-op realtime client for widget/integration tests.
class FakeAppointmentQueueRealtimeClient implements AppointmentQueueRealtimeClient {
  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {}

  @override
  void unsubscribe() {}
}

/// Idle queue controller that skips network refresh and realtime subscriptions.
class TestIdleAppointmentQueueNotifier extends AppointmentQueueController {
  @override
  AppointmentQueueState build() => const AppointmentQueueState(items: []);
}

/// In-memory RPC client that keeps queue list/detail rows in sync for widget tests.
class StatefulQueueRpcClient extends AppointmentRpcTestClient {
  StatefulQueueRpcClient({required List<Map<String, dynamic>> items}) : _items = items.map(_cloneRow).toList();

  final List<Map<String, dynamic>> _items;

  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  static Map<String, dynamic> _cloneRow(Map<String, dynamic> row) => Map<String, dynamic>.from(row);

  Map<String, dynamic> _detailForId(String? appointmentId) {
    final id = appointmentId?.trim();
    if (id == null || id.isEmpty) {
      return appointmentRpcDefaultDetailItem();
    }

    final index = _items.indexWhere((item) => item['id']?.toString() == id);
    if (index < 0) {
      return appointmentRpcDefaultDetailItem(id: id);
    }
    final row = _items[index];

    final start = DateTime.parse(row['start_time'] as String);
    final detail = appointmentRpcDefaultDetailItem(
      id: id,
      patientName: row['patient_name'] as String? ?? 'Test Patient',
      startLocal: start.toLocal(),
    );
    detail['doctor_id'] = row['doctor_id'];
    detail['doctor_name'] = row['doctor_name'];
    return {
      ...detail,
      'status': row['status'],
      'checked_in_at': row['checked_in_at'],
      'in_progress_at': row['in_progress_at'],
    };
  }

  void _mutateItem(String appointmentId, void Function(Map<String, dynamic> row) mutate) {
    final index = _items.indexWhere((item) => item['id']?.toString() == appointmentId);
    if (index < 0) {
      return;
    }
    mutate(_items[index]);
  }

  void _recordRpc(String fn, Map<String, dynamic>? params) {
    rpcLog.add(fn);
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      _recordRpc(fn, params);
      return FakePostgrestRpc({
            'success': true,
            'data': {'items': _items.map(_cloneRow).toList()},
          })
          as PostgrestFilterBuilder<T>;
    }

    if (fn == 'get_appointment') {
      _recordRpc(fn, params);
      return FakePostgrestRpc({'success': true, 'data': _detailForId(params?['p_appointment_id']?.toString())})
          as PostgrestFilterBuilder<T>;
    }

    if (fn == 'update_appointment_status') {
      _recordRpc(fn, params);
      final appointmentId = params?['p_appointment_id']?.toString();
      final newStatus = params?['p_new_status']?.toString();
      if (appointmentId != null && newStatus != null) {
        _mutateItem(appointmentId, (row) {
          row['status'] = newStatus;
          if (newStatus == 'checked_in') {
            row['checked_in_at'] = '2026-06-04T09:45:00.000Z';
            row['in_progress_at'] = null;
          } else if (newStatus == 'in_progress') {
            row['in_progress_at'] = '2026-06-04T10:00:00.000Z';
          } else {
            row['checked_in_at'] = null;
            row['in_progress_at'] = null;
          }
        });
      }
      final status = newStatus;
      return FakePostgrestRpc({
            'success': true,
            'data': {
              'appointment_id': appointmentId,
              'status': status,
              'updated_at': '2026-06-04T10:00:00.000Z',
              'checked_in_at': status == 'checked_in' || status == 'in_progress' ? '2026-06-04T09:45:00.000Z' : null,
              'in_progress_at': status == 'in_progress' ? '2026-06-04T10:00:00.000Z' : null,
            },
          })
          as PostgrestFilterBuilder<T>;
    }

    if (fn == 'update_appointment') {
      _recordRpc(fn, params);
      final appointmentId = params?['p_appointment_id']?.toString();
      final doctorId = params?['p_doctor_id']?.toString();
      if (appointmentId != null && doctorId != null) {
        _mutateItem(appointmentId, (row) {
          row['doctor_id'] = doctorId;
          row['doctor_name'] = doctorId == queueTestDoctorAlphaId
              ? 'Dr Alpha'
              : doctorId == queueTestDoctorBetaId
              ? 'Dr Beta'
              : row['doctor_name'];
        });
      }
      return FakePostgrestRpc({
            'success': true,
            'data': {
              'appointment_id': appointmentId,
              'start_time': params?['p_start_time'],
              'end_time': '2026-06-01T11:00:00.000Z',
              'status': 'scheduled',
              'type': 'planned',
            },
          })
          as PostgrestFilterBuilder<T>;
    }

    if (fn == 'cancel_appointment') {
      _recordRpc(fn, params);
      final appointmentId = params?['p_appointment_id']?.toString();
      if (appointmentId != null) {
        _mutateItem(appointmentId, (row) => row['status'] = 'cancelled');
      }
      return FakePostgrestRpc({
            'success': true,
            'data': {'appointment_id': appointmentId, 'status': 'cancelled'},
          })
          as PostgrestFilterBuilder<T>;
    }

    if (fn == 'create_appointment') {
      _recordRpc(fn, params);
      if (lastParams != null) {
        createAppointmentCalls.add(Map<String, dynamic>.from(lastParams!));
      }
      final startRaw = params?['p_start_time']?.toString() ?? DateTime.now().toUtc().toIso8601String();
      final start = DateTime.parse(startRaw);
      final end = start.add(const Duration(minutes: 30));
      final newRow = queueRpcListItem(
        id: queueApptNewBookingId,
        patientName: 'Booked Patient',
        startLocal: start.toLocal(),
        status: AppointmentStatus.scheduled,
      );
      _items.add(newRow);
      return FakePostgrestRpc({
            'success': true,
            'data': {
              'appointment_id': queueApptNewBookingId,
              'start_time': start.toUtc().toIso8601String(),
              'end_time': end.toUtc().toIso8601String(),
              'status': 'scheduled',
              'type': params?['p_type'] ?? 'planned',
            },
          })
          as PostgrestFilterBuilder<T>;
    }

    return super.rpc<T>(fn, params: params, get: get);
  }
}

/// Provider overrides that isolate tests from Supabase-backed queue I/O.
List<Override> appointmentQueueTestOverrides() => [
  appointmentQueueProvider.overrideWith(TestIdleAppointmentQueueNotifier.new),
  appointmentQueueRealtimeClientProvider.overrideWithValue(FakeAppointmentQueueRealtimeClient()),
  appointmentQueueShiftDoctorLookupProvider.overrideWith((ref) async => AppointmentQueueShiftDoctorLookup.empty),
];

/// Realtime + optional shift lookup overrides without replacing the queue controller.
List<Override> queueRealtimeOverrides({AppointmentQueueShiftDoctorLookup? shiftLookup}) => [
  appointmentQueueRealtimeClientProvider.overrideWithValue(FakeAppointmentQueueRealtimeClient()),
  if (shiftLookup != null) appointmentQueueShiftDoctorLookupProvider.overrideWith((ref) async => shiftLookup),
];

DateTime queueTodayDate() {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day);
}

/// Local calendar time on today's date (used for RPC rows and shift coverage).
DateTime queueTodayLocal({int hour = 10, int minute = 0}) {
  final today = queueTodayDate();
  return DateTime.utc(today.year, today.month, today.day, hour, minute);
}

Map<String, dynamic> queueRpcListItem({
  required String id,
  required String patientName,
  DateTime? startLocal,
  AppointmentStatus status = AppointmentStatus.scheduled,
  String? doctorId,
  String? doctorName,
  String patientId = queueTestPatientId,
}) {
  final start = (startLocal ?? queueTodayLocal()).toUtc();
  final end = start.add(const Duration(minutes: 30));
  return {
    'id': id,
    'patient_id': patientId,
    'patient_name': patientName,
    'doctor_id': ?doctorId,
    'doctor_name': ?doctorName,
    'start_time': start.toIso8601String(),
    'end_time': end.toIso8601String(),
    'type': 'planned',
    'status': status.wireValue,
  };
}

AppointmentListItem queueListItem({
  required String id,
  required String patientName,
  DateTime? startLocal,
  AppointmentStatus status = AppointmentStatus.scheduled,
  String? doctorId,
  String? doctorName,
  String patientId = queueTestPatientId,
}) {
  final start = (startLocal ?? queueTodayLocal()).toUtc();
  return AppointmentListItem(
    id: id,
    patientId: patientId,
    patientName: patientName,
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
  );
}

AppointmentQueueShiftDoctorLookup queueTwoDoctorShiftLookup() {
  final shiftDate = queueTodayDate();
  return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
    organizationTimezone: 'UTC',
    shifts: [
      ShiftListItem(
        id: 'queue-shift-1',
        branchId: queueTestBranchId,
        shiftDate: shiftDate,
        startTime: '00:00',
        endTime: '23:59',
        status: ShiftStatus.active,
        isUnassigned: false,
        assigneeNames: const ['Dr Alpha', 'Dr Beta'],
        assigneeCount: 2,
      ),
    ],
    doctors: queueTestDoctors,
  );
}

AuthSessionState queueAuthState({
  Set<String> permissions = const {
    PermissionKeys.appointmentsRead,
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
  },
  String? activeBranchId,
  List<String> branchIds = const [queueTestBranchId],
}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions,
      activeBranchId: activeBranchId,
      branchIds: branchIds,
    ).copyWith(organizationId: '00000000-0000-4000-8000-000000000020', organizationTimezone: 'UTC'),
  );
}

AuthSessionState queueAuthWithoutBranch() {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: AuthSessionContext(
      staffProfile: const StaffProfile(
        staffMemberId: '00000000-0000-4000-8000-000000000010',
        fullName: 'Test Staff',
        role: StaffRole.administrator,
        isBootstrapAdmin: false,
        isActive: true,
      ),
      organizationId: '00000000-0000-4000-8000-000000000020',
      branchIds: const [queueTestBranchId],
      activeBranchId: null,
      permissions: const {PermissionKeys.appointmentsRead},
      setupRequired: false,
      organizationTimezone: 'UTC',
    ),
  );
}

List<Override> queuePageOverrides({
  required AuthSessionState authState,
  required AppointmentRpcTestClient rpcClient,
  AppointmentQueueShiftDoctorLookup? shiftLookup,
  FakePatientRepository? patientRepository,
  List<Override> extraOverrides = const [],
}) {
  final patients =
      patientRepository ?? FakePatientRepository(patients: [samplePatientListItem(fullName: 'Booked Patient')]);
  return [
    authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(authState)),
    appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(rpcClient)),
    listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(CalendarStubBranchRepository())),
    listStaffUseCaseProvider.overrideWith(
      (ref) => ListStaff(CalendarDoctorsStubStaffRepository(doctors: queueTestDoctors)),
    ),
    patientRepositoryProvider.overrideWithValue(patients),
    searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(ref.watch(patientRepositoryProvider))),
    ...queueRealtimeOverrides(shiftLookup: shiftLookup ?? queueTwoDoctorShiftLookup()),
    ...extraOverrides,
  ];
}

Future<ProviderContainer> pumpQueuePage(
  WidgetTester tester, {
  required AuthSessionState authState,
  AppointmentRpcTestClient? rpcClient,
  AppointmentQueueShiftDoctorLookup? shiftLookup,
  FakePatientRepository? patientRepository,
  List<Override> extraOverrides = const [],
  Size surfaceSize = queueWidgetSurfaceSize,
}) async {
  final client =
      rpcClient ??
      StatefulQueueRpcClient(
        items: [
          queueRpcListItem(id: queueApptScheduledId, patientName: 'Queue Patient', startLocal: queueTodayLocal()),
        ],
      );

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: queuePageOverrides(
        authState: authState,
        rpcClient: client,
        shiftLookup: shiftLookup,
        patientRepository: patientRepository,
        extraOverrides: extraOverrides,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child!),
        home: const Scaffold(body: AppointmentQueuePage()),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
}

Future<ProviderContainer> waitForQueueLoaded(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final loadingSkeleton = find.byType(AppSkeletonBox);
    final hasBody = find.text('Appointments').evaluate().isNotEmpty;
    if (hasBody && loadingSkeleton.evaluate().isEmpty) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 300));
  return ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
}

Future<void> openQueueJourneyDialog(WidgetTester tester, {required String appointmentId}) async {
  final statusButton = find.byKey(Key('appointment_queue_status_$appointmentId'));
  await tester.ensureVisible(statusButton);
  await tester.tap(statusButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byKey(const Key('appointment_control_advance_status')).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
      return;
    }
  }
  fail('Status journey dialog did not load for $appointmentId');
}

Future<void> tapJourneyAdvanceAction(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('appointment_control_advance_status')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> tapJourneyNoShowAction(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('appointment_control_no_show')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> tapJourneyCancelAction(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('appointment_control_cancel')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> confirmNoShowDialog(WidgetTester tester) async {
  await tester.tap(find.text('Mark no-show').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> completeCancelDialog(WidgetTester tester, {String reason = 'Patient requested'}) async {
  await tester.enterText(find.byKey(const Key('appointment_cancel_reason')), reason);
  await tester.tap(find.byKey(const Key('appointment_cancel_confirm')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> selectDoctorInPicker(WidgetTester tester, String doctorName) async {
  expect(find.text('Confirm doctor'), findsOneWidget);
  final picker = find.byType(FDialog);
  final doctorInDialog = find.descendant(of: picker, matching: find.text(doctorName));
  expect(doctorInDialog, findsWidgets);
  await tester.tap(doctorInDialog.first);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: picker, matching: find.text('Start visit')));
  await tester.pumpAndSettle();
}

Future<void> tapWaitingColumnPatient(WidgetTester tester, String patientName) async {
  await tester.tap(find.descendant(of: find.byType(AppointmentQueueWaitingColumn), matching: find.text(patientName)));
  await tester.pump();
}

AppButton queueAdvanceButton(WidgetTester tester) {
  return tester.widget<AppButton>(find.byKey(const Key('appointment_control_advance_status')));
}

int queueCheckedInBadgeCount(WidgetTester tester) {
  final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
  return container.read(appointmentQueueCheckedInCountProvider);
}

Future<void> tapBookAppointmentHeader(WidgetTester tester) async {
  suppressBookingSheetListTileNoise();
  await tester.tap(find.text('Book Appointment'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await waitForBookingSheetReady(tester);
}
