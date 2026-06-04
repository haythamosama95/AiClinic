import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_actions.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:clock/clock.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  group('AppointmentStatusActions', () {
    testWidgets('trivial: scheduled shows confirm', (tester) async {
      await tester.pumpWidget(_host(item: _item(status: AppointmentStatus.scheduled)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_confirm')), findsOneWidget);
      expect(find.byKey(const Key('appointments_status_check_in')), findsNothing);
    });

    testWidgets('confirmed shows check-in on appointment day', (tester) async {
      await tester.pumpWidget(_host(item: _item(status: AppointmentStatus.confirmed, onAppointmentDay: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_check_in')), findsOneWidget);
      expect(find.byKey(const Key('appointments_status_start')), findsNothing);
    });

    testWidgets('confirmed hides check-in before appointment day', (tester) async {
      await tester.pumpWidget(_host(item: _item(status: AppointmentStatus.confirmed, onAppointmentDay: false)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_check_in')), findsNothing);
    });

    testWidgets('advanced: successful confirm calls RPC and callback', (tester) async {
      AppointmentStatus? changed;
      final client = AppointmentRpcTestClient();

      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.scheduled),
          client: client,
          onStatusChanged: (status) => changed = status,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointments_status_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'update_appointment_status');
      expect(client.lastParams?['p_new_status'], 'confirmed');
      expect(changed, AppointmentStatus.confirmed);
      expect(find.text('Status updated to Confirmed.'), findsOneWidget);
    });

    testWidgets('invalid transition shows error banner', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'update_appointment_status': {
            'success': false,
            'error_code': 'INVALID_TRANSITION',
            'error_message': 'Not allowed',
          },
        },
      );

      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.scheduled),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointments_status_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_error')), findsOneWidget);
      expect(find.textContaining('not allowed'), findsOneWidget);
    });

    testWidgets('permission denied hides actions without create grant', (tester) async {
      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.scheduled),
          permissions: const {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_confirm')), findsNothing);
    });

    testWidgets('V1-5: no appointment status shows manual complete button', (tester) async {
      for (final status in AppointmentStatus.values) {
        if (status == AppointmentStatus.cancelled || status == AppointmentStatus.noShow) {
          continue;
        }
        await tester.pumpWidget(
          _host(
            item: _item(status: status, onAppointmentDay: true),
            permissions: const {PermissionKeys.appointmentsCreate, PermissionKeys.visitsCreate},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('appointments_status_complete')), findsNothing);
      }
    });

    testWidgets('in_progress shows create visit instead of complete', (tester) async {
      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.inProgress, onAppointmentDay: true),
          permissions: const {PermissionKeys.appointmentsCreate, PermissionKeys.visitsCreate},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_visit_create')), findsOneWidget);
      expect(find.byKey(const Key('appointments_status_complete')), findsNothing);
    });

    testWidgets('checked_in shows create visit when visits.create granted', (tester) async {
      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.checkedIn, onAppointmentDay: true),
          permissions: const {PermissionKeys.appointmentsCreate, PermissionKeys.visitsCreate},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_visit_create')), findsOneWidget);
      expect(find.byKey(const Key('appointments_status_start')), findsOneWidget);
    });

    testWidgets('in_progress with linked visit shows open visit', (tester) async {
      final visitClient = VisitRpcTestClient(
        rpcResults: {
          'get_visit_by_appointment': {
            'success': true,
            'data': {'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'status': 'in_progress'},
          },
        },
      );

      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.inProgress, onAppointmentDay: true),
          permissions: const {PermissionKeys.appointmentsCreate, PermissionKeys.visitsCreate},
          visitClient: visitClient,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_visit_open')), findsOneWidget);
      expect(find.byKey(const Key('appointments_visit_create')), findsNothing);
    });

    testWidgets('visit actions hidden without visits.create grant', (tester) async {
      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.checkedIn, onAppointmentDay: true),
          permissions: const {PermissionKeys.appointmentsCreate},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_visit_create')), findsNothing);
      expect(find.byKey(const Key('appointments_visit_open')), findsNothing);
    });

    testWidgets('terminal completed hides all actions', (tester) async {
      await tester.pumpWidget(_host(item: _item(status: AppointmentStatus.completed)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_complete')), findsNothing);
      expect(find.byKey(const Key('appointments_status_start')), findsNothing);
      expect(find.byKey(const Key('appointments_visit_create')), findsNothing);
    });

    testWidgets('scheduled shows reschedule alongside confirm', (tester) async {
      await tester.pumpWidget(_host(item: _item(status: AppointmentStatus.scheduled)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_reschedule')), findsOneWidget);
      expect(find.byKey(const Key('appointments_status_confirm')), findsOneWidget);
    });

    testWidgets('checked_in planned hides reschedule', (tester) async {
      await tester.pumpWidget(_host(item: _item(status: AppointmentStatus.checkedIn)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_reschedule')), findsNothing);
    });

    testWidgets('confirmed planned hides reschedule per spec', (tester) async {
      await tester.pumpWidget(_host(item: _item(status: AppointmentStatus.confirmed, onAppointmentDay: false)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_reschedule')), findsNothing);
    });

    testWidgets('confirmed shows cancel when cancel grant present', (tester) async {
      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.confirmed, onAppointmentDay: false),
          permissions: const {PermissionKeys.appointmentsCancel},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_cancel')), findsOneWidget);
      expect(find.byKey(const Key('appointments_status_check_in')), findsNothing);
    });

    testWidgets('cancel from confirmed invokes cancel_appointment RPC', (tester) async {
      AppointmentStatus? changed;
      final client = AppointmentRpcTestClient();

      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.confirmed, onAppointmentDay: false),
          permissions: const {PermissionKeys.appointmentsCreate, PermissionKeys.appointmentsCancel},
          client: client,
          onStatusChanged: (status) => changed = status,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointments_status_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appointment_cancel_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'cancel_appointment');
      expect(changed, AppointmentStatus.cancelled);
    });

    testWidgets('scheduled shows cancel when cancel grant present', (tester) async {
      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.scheduled),
          permissions: const {PermissionKeys.appointmentsCancel},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_cancel')), findsOneWidget);
      expect(find.byKey(const Key('appointments_status_check_in')), findsNothing);
    });

    testWidgets('cancel hidden without appointments.cancel grant', (tester) async {
      await tester.pumpWidget(_host(item: _item(status: AppointmentStatus.scheduled)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_cancel')), findsNothing);
    });

    testWidgets('cancel success invokes onStatusChanged with cancelled', (tester) async {
      AppointmentStatus? changed;
      final client = AppointmentRpcTestClient();

      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.checkedIn, onAppointmentDay: true),
          permissions: const {PermissionKeys.appointmentsCreate, PermissionKeys.appointmentsCancel},
          client: client,
          onStatusChanged: (status) => changed = status,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointments_status_cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_cancel_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'cancel_appointment');
      expect(changed, AppointmentStatus.cancelled);
      expect(find.text('Appointment cancelled.'), findsOneWidget);
    });

    testWidgets('no-show from dialog updates status on appointment day', (tester) async {
      AppointmentStatus? changed;

      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.scheduled, onAppointmentDay: true),
          permissions: const {PermissionKeys.appointmentsCancel},
          onStatusChanged: (status) => changed = status,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointments_status_cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_cancel_no_show')));
      await tester.pumpAndSettle();

      expect(changed, AppointmentStatus.noShow);
      expect(find.text('Appointment marked as no-show.'), findsOneWidget);
    });

    testWidgets('terminal completed hides cancel action', (tester) async {
      await tester.pumpWidget(
        _host(
          item: _item(status: AppointmentStatus.completed),
          permissions: const {PermissionKeys.appointmentsCancel},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_status_cancel')), findsNothing);
    });

    testWidgets('reschedule success invokes onRescheduled callback', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        CreateAppointmentResult? rescheduled;
        final client = AppointmentRpcTestClient(
          rpcResults: {
            'reschedule_appointment': {
              'success': true,
              'data': {
                'appointment_id': 'appt-1',
                'start_time': '2026-06-01T11:00:00.000Z',
                'end_time': '2026-06-01T11:30:00.000Z',
                'status': 'scheduled',
                'type': 'planned',
              },
            },
          },
        );

        await tester.pumpWidget(
          _host(
            item: _item(startTime: DateTime(2026, 6, 1, 10), endTime: DateTime(2026, 6, 1, 10, 30)),
            client: client,
            onRescheduled: (result) => rescheduled = result,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appointments_status_reschedule')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('appointment_reschedule_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
        await tester.pumpAndSettle();

        expect(rescheduled, isNotNull);
        expect(client.rpcLog, contains('reschedule_appointment'));
      });
    });
  });
}

AppointmentListItem _item({
  AppointmentStatus status = AppointmentStatus.scheduled,
  AppointmentType type = AppointmentType.planned,
  bool onAppointmentDay = false,
  DateTime? startTime,
  DateTime? endTime,
}) {
  final start =
      startTime ??
      (onAppointmentDay
          ? DateTime.now().subtract(const Duration(hours: 1))
          : DateTime.now().add(const Duration(days: 7)));
  final end = endTime ?? start.add(const Duration(minutes: 30));
  return AppointmentListItem(
    id: 'appt-1',
    patientId: 'patient-1',
    patientName: 'Jane Doe',
    doctorName: 'Dr Smith',
    startTime: start,
    endTime: end,
    type: type,
    status: status,
  );
}

Widget _host({
  required AppointmentListItem item,
  Set<String> permissions = const {PermissionKeys.appointmentsCreate},
  AppointmentRpcTestClient? client,
  VisitRpcTestClient? visitClient,
  ValueChanged<AppointmentStatus>? onStatusChanged,
  ValueChanged<CreateAppointmentResult>? onRescheduled,
}) {
  final branchId = '44444444-4444-4444-8444-444444444444';
  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: branchId, branchIds: [branchId]),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client ?? AppointmentRpcTestClient())),
      visitRepositoryProvider.overrideWith((ref) => VisitRepository(visitClient ?? VisitRpcTestClient())),
      branchRepositoryProvider.overrideWithValue(_ActionsFakeBranchRepository(branchId: branchId)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: AppointmentStatusActions(item: item, onStatusChanged: onStatusChanged, onRescheduled: onRescheduled),
      ),
    ),
  );
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

class _ActionsFakeBranchRepository implements BranchRepository {
  _ActionsFakeBranchRepository({required this.branchId});

  final String branchId;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    return [
      BranchListItem(
        id: branchId,
        name: 'Main Branch',
        isActive: true,
        workingSchedule: BranchWorkingSchedule(
          BranchWeekday.values
              .map((day) => BranchWorkingDayHours(day: day, isWorkingDay: true, openTime: '00:00', closeTime: '23:59'))
              .toList(growable: false),
        ),
      ),
    ];
  }

  @override
  Future<String> createBranch(CreateBranchInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) => throw UnimplementedError();

  @override
  Future<String> updateBranch(UpdateBranchInput input) => throw UnimplementedError();
}
