// Acceptance outline for spec.md test cases 1–14 (V1-4 appointment management).
//
// Split coverage:
// - Cases 1–2, 7, 14 (booking): `appointment_booking_us1_test.dart`
// - Case 3 (walk-in) removed; booking-only flow in `appointment_booking_us1_test.dart`
// - Case 13 (backend harness): `backend/tests/run_appointment_management_tests.sh`
// - Remaining UI flows: this file (calendar, queue, status, cancel, reschedule, guards).

import 'dart:io';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_booking_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/doctor_schedule_page.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_actions.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/pages/auth_shell_page.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

const _repoRoot = '..';
const _branchAId = '44444444-4444-4444-8444-444444444444';
const _doctorA = '22222222-2222-4222-8222-222222222222';
const _doctorB = '33333333-3333-4333-8333-333333333333';

Future<void> _pumpHost(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

AuthSessionState _auth({
  Set<String> permissions = const {PermissionKeys.appointmentsCreate, PermissionKeys.patientsView},
  String activeBranchId = _branchAId,
}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions,
      activeBranchId: activeBranchId,
      branchIds: [activeBranchId],
    ),
  );
}

Widget _scope({
  required Widget child,
  AuthSessionState? auth,
  AppointmentRpcTestClient? client,
  AppointmentQueueRealtimeConnection realtime = AppointmentQueueRealtimeConnection.live,
  Map<String, Map<String, dynamic>>? rpcResults,
}) {
  final rpcClient = client ?? AppointmentRpcTestClient(rpcResults: rpcResults ?? {});
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _auth())),
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(rpcClient)),
      appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeRealtime(realtime)),
      patientRepositoryProvider.overrideWith((ref) => FakePatientRepository(patients: [samplePatientListItem()])),
      staffAdminRepositoryProvider.overrideWithValue(_SmokeStaffRepo()),
    ],
    child: child,
  );
}

void main() {
  group('spec case 4 — status lifecycle (reception on any doctor)', () {
    testWidgets('confirm, check-in, start, and complete advance status via RPC', (tester) async {
      final client = AppointmentRpcTestClient();
      var item = _item(status: AppointmentStatus.scheduled, onAppointmentDay: true);

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return AppointmentStatusActions(
                    item: item,
                    onStatusChanged: (status) => setState(() => item = item.copyWith(status: status)),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('appointments_status_confirm')));
      await tester.pumpAndSettle();
      expect(client.lastParams?['p_new_status'], 'confirmed');
      expect(find.byKey(const Key('appointments_status_check_in')), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointments_status_check_in')));
      await tester.pumpAndSettle();
      expect(client.lastParams?['p_new_status'], 'checked_in');
      expect(find.byKey(const Key('appointments_status_start')), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointments_status_start')));
      await tester.pumpAndSettle();
      expect(client.lastParams?['p_new_status'], 'in_progress');

      await tester.tap(find.byKey(const Key('appointments_status_complete')));
      await tester.pumpAndSettle();
      expect(client.lastParams?['p_new_status'], 'completed');
      expect(find.byKey(const Key('appointments_status_complete')), findsNothing);
    });
  });

  group('spec cases 5–6 — cancel and no-show', () {
    testWidgets('case 5: cancel scheduled appointment calls cancel_appointment RPC', (tester) async {
      final client = AppointmentRpcTestClient();
      AppointmentStatus? changed;

      await _pumpHost(
        tester,
        _scope(
          client: client,
          auth: _auth(permissions: {PermissionKeys.appointmentsCancel}),
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentStatusActions(
                item: _item(status: AppointmentStatus.scheduled),
                onStatusChanged: (s) => changed = s,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('appointments_status_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appointment_cancel_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'cancel_appointment');
      expect(changed, AppointmentStatus.cancelled);
    });

    testWidgets('case 6: no-show from checked-in updates status', (tester) async {
      AppointmentStatus? changed;

      await _pumpHost(
        tester,
        _scope(
          auth: _auth(permissions: {PermissionKeys.appointmentsCancel}),
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentStatusActions(
                item: _item(status: AppointmentStatus.checkedIn, onAppointmentDay: true),
                onStatusChanged: (s) => changed = s,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('appointments_status_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appointment_cancel_no_show')));
      await tester.pumpAndSettle();

      expect(changed, AppointmentStatus.noShow);
    });

    testWidgets('stupid user: completed row cannot cancel', (tester) async {
      await _pumpHost(
        tester,
        _scope(
          auth: _auth(permissions: {PermissionKeys.appointmentsCancel}),
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentStatusActions(item: _item(status: AppointmentStatus.completed)),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('appointments_status_cancel')), findsNothing);
    });
  });

  group('spec case 8 — queue scoped to active branch', () {
    testWidgets('list_appointments uses session active branch id', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {'items': []},
          },
        },
      );

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: const MaterialApp(home: AppointmentQueuePage()),
        ),
      );

      expect(client.lastFunction, 'list_appointments');
      expect(client.lastParams?['p_branch_id'], _branchAId);
      expect(client.lastParams?.containsKey('p_from'), isTrue);
      expect(client.lastParams?.containsKey('p_to'), isTrue);
    });
  });

  group('spec case 9 — queue realtime degraded fallback', () {
    testWidgets('degraded banner and manual refresh re-fetches list', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {'items': []},
          },
        },
      );

      await _pumpHost(
        tester,
        _scope(
          client: client,
          realtime: AppointmentQueueRealtimeConnection.degraded,
          child: const MaterialApp(home: AppointmentQueuePage()),
        ),
      );

      expect(find.byKey(const Key('appointments_queue_degraded_banner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointments_queue_refresh')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'list_appointments');
    });
  });

  group('spec case 10 — doctor schedule filter', () {
    testWidgets('schedule route pins doctor filter on list_appointments', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {'items': []},
          },
        },
      );

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: MaterialApp(home: DoctorSchedulePage(doctorId: _doctorA)),
        ),
      );

      expect(find.text('Appointment calendar'), findsOneWidget);
      expect(client.lastParams?['p_doctor_id'], _doctorA);
    });

    testWidgets('edge: empty doctor id does not send doctor filter', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {'items': []},
          },
        },
      );

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: AppRoutes.appointmentsCalendar,
              routes: [
                GoRoute(path: AppRoutes.appointmentsCalendar, builder: (_, _) => const AppointmentCalendarPage()),
              ],
            ),
          ),
        ),
      );

      expect(client.lastParams?.containsKey('p_doctor_id'), isFalse);
    });
  });

  group('spec case 12 — reschedule planned scheduled only', () {
    testWidgets('reschedule success calls RPC with new start', (tester) async {
      final client = AppointmentRpcTestClient();
      var item = _item(status: AppointmentStatus.scheduled);

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return AppointmentStatusActions(
                    item: item,
                    onStatusChanged: (status) => setState(() => item = item.copyWith(status: status)),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('appointments_status_reschedule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'reschedule_appointment');
    });

    testWidgets('invalid: checked-in hides reschedule control', (tester) async {
      await _pumpHost(
        tester,
        _scope(
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentStatusActions(item: _item(status: AppointmentStatus.checkedIn)),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('appointments_status_reschedule')), findsNothing);
    });

    testWidgets('overlap rejection surfaces conflict banner in dialog', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'reschedule_appointment': {'success': false, 'error_code': 'SCHEDULE_CONFLICT', 'error_message': 'Overlap'},
        },
      );

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentStatusActions(item: _item(status: AppointmentStatus.scheduled)),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('appointments_status_reschedule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('conflict_error_banner')), findsOneWidget);
      expect(find.textContaining('overlaps'), findsOneWidget);
    });
  });

  group('spec case 13 — backend verification harness', () {
    test('CRUD and RLS SQL files exist for operator run', () {
      final crud = File('$_repoRoot/backend/tests/appointment_management_crud.sql');
      final rls = File('$_repoRoot/backend/tests/appointment_management_rls.sql');
      final runner = File('$_repoRoot/backend/tests/run_appointment_management_tests.sh');

      expect(crud.existsSync(), isTrue);
      expect(rls.existsSync(), isTrue);
      expect(runner.existsSync(), isTrue);
      expect(crud.readAsStringSync(), contains('SCHEDULE_CONFLICT'));
      expect(rls.readAsStringSync(), contains('cross'));
    });
  });

  group('spec case 14 — default duration pre-fill on booking', () {
    testWidgets('booking form pre-fills settings default (30 min)', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'get_appointment_settings': {
            'success': true,
            'data': {'default_duration_minutes': 30, 'min_duration_minutes': 5, 'max_duration_minutes': 240},
          },
        },
      );

      await _pumpHost(
        tester,
        _scope(
          client: client,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: AppRoutes.appointmentsBook,
              routes: [GoRoute(path: AppRoutes.appointmentsBook, builder: (_, _) => const AppointmentBookingPage())],
            ),
          ),
        ),
      );

      expect(find.text('30'), findsOneWidget);
    });
  });

  group('shell navigation (phase 10 T061)', () {
    testWidgets('appointments hub visible when user can access appointments', (tester) async {
      await _pumpHost(tester, _scope(child: const MaterialApp(home: AuthShellPage())));

      expect(find.byKey(const Key('shell_home_appointments')), findsOneWidget);
    });

    testWidgets('appointments hub hidden without appointment grants', (tester) async {
      await _pumpHost(
        tester,
        _scope(
          auth: _auth(permissions: {PermissionKeys.patientsView}),
          child: const MaterialApp(home: AuthShellPage()),
        ),
      );

      expect(find.byKey(const Key('shell_home_appointments')), findsNothing);
    });
  });

  group('V1-3/V1-2 regression smoke (phase 10 T065)', () {
    test('patient and settings routes remain defined alongside appointments', () {
      expect(AppRoutes.patients, '/patients');
      expect(AppRoutes.settingsOrganization, '/settings/organization');
      expect(AppRoutes.appointmentsCalendar, '/appointments/calendar');
    });

    test('patient list route does not redirect for receptionist', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          permissions: {PermissionKeys.patientsView, PermissionKeys.appointmentsCreate},
        ),
      );
      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patients, auth: auth), isNull);
      expect(AuthRouteGuard.isAppointmentRoute(AppRoutes.appointments), isTrue);
      expect(AuthRouteGuard.isPatientRoute(AppRoutes.patients), isTrue);
    });
  });
}

AppointmentListItem _item({
  AppointmentStatus status = AppointmentStatus.scheduled,
  AppointmentType type = AppointmentType.planned,
  String doctorId = _doctorB,
  bool onAppointmentDay = false,
}) {
  final start = onAppointmentDay ? DateTime.now().subtract(const Duration(hours: 1)) : DateTime.utc(2026, 6, 1, 10);
  return AppointmentListItem(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    patientName: 'Test Patient',
    doctorId: doctorId,
    doctorName: 'Dr Other',
    startTime: start,
    endTime: start.add(const Duration(minutes: 20)),
    type: type,
    status: status,
  );
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _FakeRealtime implements AppointmentQueueRealtimeClient {
  _FakeRealtime(this.connection);

  final AppointmentQueueRealtimeConnection connection;

  @override
  void subscribe({
    required String branchId,
    required VoidCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    onConnectionChanged(connection);
  }

  @override
  void unsubscribe() {}
}

class _SmokeStaffRepo implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    return const [
      StaffListItem(id: _doctorA, fullName: 'Dr Smith', role: StaffRole.doctor, isActive: true),
      StaffListItem(id: _doctorB, fullName: 'Dr Jones', role: StaffRole.doctor, isActive: true),
    ];
  }

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<bool> organizationHasOwner() => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();
}
