import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';
import '../../support/shift_rpc_test_client.dart';

const queueIntegrationBranchId = calendarTestBranchAId;
const queueIntegrationOrgId = '00000000-0000-4000-8000-000000000020';
const queueIntegrationTimezone = 'UTC';

const queueDoctorAlphaId = '11111111-1111-4111-8111-111111111111';
const queueDoctorBetaId = '22222222-2222-4222-8222-222222222222';
const queuePatientAlphaId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const queueIntegrationSurfaceSize = Size(1280, 900);

List<StaffListItem> get queueIntegrationDoctors => const [
  StaffListItem(id: queueDoctorAlphaId, fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
  StaffListItem(id: queueDoctorBetaId, fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
];

BranchWorkingSchedule queueMonFriWorkingSchedule() {
  return BranchWorkingSchedule([
    for (final day in BranchWeekday.values)
      BranchWorkingDayHours(
        day: day,
        isWorkingDay: day != BranchWeekday.saturday && day != BranchWeekday.sunday,
        openTime: '09:00',
        closeTime: '17:00',
      ),
  ]);
}

DateTime queueIntegrationTodayLocal() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String queueIntegrationTodayShiftDate() {
  final today = queueIntegrationTodayLocal();
  return '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';
}

AuthSessionState queueIntegrationAuthState({Set<String>? permissions}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? {PermissionKeys.appointmentsRead},
      activeBranchId: queueIntegrationBranchId,
    ).copyWith(organizationId: queueIntegrationOrgId, organizationTimezone: queueIntegrationTimezone),
  );
}

class QueuePresetAuthSessionNotifier extends TestAuthSessionNotifier {
  QueuePresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

/// Captures realtime callbacks so tests can simulate a second client/session.
class CapturingQueueRealtimeClient implements AppointmentQueueRealtimeClient {
  AppointmentQueueRealtimeChangeCallback? onAppointmentChange;
  AppointmentQueueRealtimeStatusCallback? onConnectionChanged;

  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    this.onAppointmentChange = onAppointmentChange;
    this.onConnectionChanged = onConnectionChanged;
    onConnectionChanged(AppointmentQueueRealtimeConnection.live);
  }

  @override
  void unsubscribe() {
    onAppointmentChange = null;
    onConnectionChanged = null;
  }
}

/// Routes [list_appointments] payloads by whether [p_from] matches today's range.
class QueueIntegrationRpcClient extends AppointmentRpcTestClient {
  QueueIntegrationRpcClient({
    required List<Map<String, dynamic>> todayItems,
    List<Map<String, dynamic>> comparisonItems = const [],
    String organizationTimezone = queueIntegrationTimezone,
  }) : _todayItems = List<Map<String, dynamic>>.from(todayItems),
       _comparisonItems = List<Map<String, dynamic>>.from(comparisonItems),
       _organizationTimezone = organizationTimezone;

  List<Map<String, dynamic>> _todayItems;
  List<Map<String, dynamic>> _comparisonItems;
  final String _organizationTimezone;

  List<Map<String, dynamic>> get todayItems => _todayItems;

  set todayItems(List<Map<String, dynamic>> items) {
    _todayItems = List<Map<String, dynamic>>.from(items);
  }

  List<Map<String, dynamic>> get comparisonItems => _comparisonItems;

  set comparisonItems(List<Map<String, dynamic>> items) {
    _comparisonItems = List<Map<String, dynamic>>.from(items);
  }

  bool _isTodayFrom(String? fromIso) {
    if (fromIso == null || fromIso.isEmpty) {
      return true;
    }
    final parsed = DateTime.tryParse(fromIso);
    if (parsed == null) {
      return true;
    }
    final todayFrom = appointmentTodayRangeInTimezone(_organizationTimezone, DateTime.now().toUtc()).from;
    return parsed.toUtc().difference(todayFrom).inSeconds.abs() < 2;
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      final from = params?['p_from']?.toString();
      final items = _isTodayFrom(from) ? _todayItems : _comparisonItems;
      return FakePostgrestRpc({
            'success': true,
            'data': {'items': items},
          })
          as PostgrestFilterBuilder<T>;
    }

    if (fn == 'update_appointment') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      final appointmentId = params?['p_appointment_id']?.toString();
      final doctorId = params?['p_doctor_id']?.toString();
      final startTime = params?['p_start_time']?.toString();
      final endTime = params?['p_end_time']?.toString();
      if (appointmentId != null && doctorId != null) {
        final index = _todayItems.indexWhere((item) => item['id']?.toString() == appointmentId);
        if (index >= 0) {
          _todayItems[index] = {
            ..._todayItems[index],
            'doctor_id': doctorId,
            'doctor_name': doctorId == queueDoctorBetaId ? 'Dr Beta' : 'Dr Alpha',
          };
        }
      }
      final existing = appointmentId == null
          ? null
          : _todayItems.cast<Map<String, dynamic>?>().firstWhere(
              (item) => item?['id']?.toString() == appointmentId,
              orElse: () => null,
            );
      return FakePostgrestRpc({
            'success': true,
            'data': {
              'appointment_id': appointmentId,
              'start_time': startTime ?? existing?['start_time'],
              'end_time': endTime ?? existing?['end_time'],
              'status': existing?['status'] ?? 'checked_in',
              'type': existing?['type'] ?? 'planned',
            },
          })
          as PostgrestFilterBuilder<T>;
    }

    if (fn == 'update_appointment_status') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      final appointmentId = params?['p_appointment_id']?.toString();
      final newStatus = params?['p_new_status']?.toString();
      final now = DateTime.now().toUtc().toIso8601String();
      if (appointmentId != null && newStatus != null) {
        final index = _todayItems.indexWhere((item) => item['id']?.toString() == appointmentId);
        if (index >= 0) {
          _todayItems[index] = {
            ..._todayItems[index],
            'status': newStatus,
            if (newStatus == 'in_progress') 'in_progress_at': now,
          };
        }
      }
      return FakePostgrestRpc({
            'success': true,
            'data': {
              'appointment_id': appointmentId,
              'status': newStatus,
              'updated_at': now,
              'in_progress_at': newStatus == 'in_progress' ? now : null,
            },
          })
          as PostgrestFilterBuilder<T>;
    }

    return super.rpc(fn, params: params, get: get);
  }
}

class QueueMonFriBranchRepository implements BranchRepository {
  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    return [
      BranchListItem(
        id: queueIntegrationBranchId,
        name: 'Main',
        code: 'M1',
        isActive: true,
        workingSchedule: queueMonFriWorkingSchedule(),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QueueDoctorsStaffRepository implements StaffAdminRepository {
  QueueDoctorsStaffRepository({List<StaffListItem>? doctors}) : _doctors = doctors ?? queueIntegrationDoctors;

  final List<StaffListItem> _doctors;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async => _doctors;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ShiftRpcTestClient configureQueueShiftRpcClient() {
  final client = ShiftRpcTestClient(branchId: queueIntegrationBranchId);
  client.listShiftsPayload = [
    {
      'id': 'shift-queue-int',
      'branch_id': queueIntegrationBranchId,
      'shift_date': queueIntegrationTodayShiftDate(),
      'start_time': '00:00',
      'end_time': '23:59',
      'status': 'active',
      'is_unassigned': false,
      'assignee_names': ['Dr Alpha', 'Dr Beta'],
      'assignee_count': 2,
    },
  ];
  return client;
}

AppointmentQueueShiftDoctorLookup queueIntegrationShiftLookup() {
  return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
    organizationTimezone: queueIntegrationTimezone,
    shifts: [
      ShiftListItem(
        id: 'shift-queue-int',
        branchId: queueIntegrationBranchId,
        shiftDate: queueIntegrationTodayLocal(),
        startTime: '00:00',
        endTime: '23:59',
        status: ShiftStatus.active,
        isUnassigned: false,
        assigneeNames: const ['Dr Alpha', 'Dr Beta'],
        assigneeCount: 2,
      ),
    ],
    doctors: queueIntegrationDoctors,
  );
}

List<Override> queueIntegrationOverrides({
  required QueueIntegrationRpcClient rpcClient,
  required CapturingQueueRealtimeClient realtimeClient,
  AuthSessionState? authState,
  BranchRepository? branchRepository,
  StaffAdminRepository? staffRepository,
  ShiftRpcTestClient? shiftClient,
}) {
  final shiftRpc = shiftClient ?? configureQueueShiftRpcClient();

  return [
    authSessionProvider.overrideWith(() => QueuePresetAuthSessionNotifier(authState ?? queueIntegrationAuthState())),
    appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(rpcClient)),
    appointmentQueueRealtimeClientProvider.overrideWithValue(realtimeClient),
    listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(branchRepository ?? QueueMonFriBranchRepository())),
    listStaffUseCaseProvider.overrideWith((ref) => ListStaff(staffRepository ?? QueueDoctorsStaffRepository())),
    shiftRepositoryProvider.overrideWith((ref) => ShiftRepository(shiftRpc)),
    appointmentQueueShiftDoctorLookupProvider.overrideWith((ref) async => queueIntegrationShiftLookup()),
  ];
}

ProviderContainer createQueueIntegrationContainer({
  required QueueIntegrationRpcClient rpcClient,
  required CapturingQueueRealtimeClient realtimeClient,
  AuthSessionState? authState,
  BranchRepository? branchRepository,
  StaffAdminRepository? staffRepository,
  ShiftRpcTestClient? shiftClient,
}) {
  return ProviderContainer(
    overrides: queueIntegrationOverrides(
      rpcClient: rpcClient,
      realtimeClient: realtimeClient,
      authState: authState,
      branchRepository: branchRepository,
      staffRepository: staffRepository,
      shiftClient: shiftClient,
    ),
  );
}

Future<void> warmQueueProvider(ProviderContainer container) async {
  final _ = container.read(appointmentQueueProvider);
  await pumpEventQueue();
  await pumpEventQueue();
}

Future<void> pumpQueuePage(WidgetTester tester, {required List<Override> overrides}) async {
  tester.view.physicalSize = queueIntegrationSurfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        home: const AppointmentQueuePage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Map<String, dynamic> queueRpcListItem({
  required String id,
  required String patientName,
  required DateTime startLocal,
  String status = 'scheduled',
  String? doctorId,
  String? doctorName,
  String? checkedInAt,
  String? inProgressAt,
}) {
  final end = startLocal.add(const Duration(minutes: 30));
  return {
    'id': id,
    'patient_id': queuePatientAlphaId,
    'patient_name': patientName,
    'doctor_id': doctorId,
    'doctor_name': doctorName,
    'start_time': startLocal.toUtc().toIso8601String(),
    'end_time': end.toUtc().toIso8601String(),
    'type': 'planned',
    'status': status,
    if (checkedInAt != null) 'checked_in_at': checkedInAt,
    if (inProgressAt != null) 'in_progress_at': inProgressAt,
  };
}

DateTime queueStartTimeToday({int hour = 10, int minute = 0}) {
  final today = queueIntegrationTodayLocal();
  return DateTime.utc(today.year, today.month, today.day, hour, minute);
}
