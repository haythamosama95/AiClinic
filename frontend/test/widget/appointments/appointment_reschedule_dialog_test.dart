import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_dialog.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';

import '../../helpers/appointment_test_support.dart';
import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRescheduleDialog', () {
    testWidgets('trivial: pre-fills duration from current appointment', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_reschedule_dialog')), findsOneWidget);
      expect(find.byKey(const Key('appointment_duration_field')), findsOneWidget);

      final field = tester.widget<TextFormField>(find.byKey(const Key('appointment_duration_field')));
      expect(field.controller?.text, '30');
    });

    testWidgets('advanced: successful save calls RPC and closes with result', (tester) async {
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

      CreateAppointmentResult? popped;
      await tester.pumpWidget(_host(client: client, onClosed: (result) => popped = result));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await pumpUntilRescheduleDialogReady(tester);

      await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'reschedule_appointment');
      expect(client.lastParams?['p_appointment_id'], 'appt-1');
      expect(popped, isNotNull);
      expect(popped!.appointmentId, 'appt-1');
    });

    testWidgets('invalid state: schedule conflict shows banner', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'reschedule_appointment': {'success': false, 'error_code': 'SCHEDULE_CONFLICT', 'error_message': 'Overlap'},
        },
      );

      await tester.pumpWidget(_host(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await pumpUntilRescheduleDialogReady(tester);

      await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('conflict_error_banner')), findsOneWidget);
      expect(find.textContaining('overlaps'), findsOneWidget);
    });

    testWidgets('stupid usage: invalid duration blocks submit', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('appointment_duration_field')), '1');
      await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('between 5 and 240'), findsOneWidget);
    });

    testWidgets('edge case: cancel closes without RPC', (tester) async {
      final client = AppointmentRpcTestClient();

      await tester.pumpWidget(_host(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_reschedule_cancel')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, isNot('reschedule_appointment'));
    });

    testWidgets('regression: wrong-status RPC shows inline error', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'reschedule_appointment': {
            'success': false,
            'error_code': 'INVALID_INPUT',
            'error_message': 'Only scheduled planned appointments can be rescheduled.',
          },
        },
      );

      await tester.pumpWidget(_host(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await pumpUntilRescheduleDialogReady(tester);

      await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_reschedule_error')), findsOneWidget);
      expect(find.textContaining('rescheduled'), findsOneWidget);
    });
  });
}

AppointmentListItem _item() {
  final start = appointmentTestStartTime();
  return AppointmentListItem(
    id: 'appt-1',
    patientId: 'patient-1',
    patientName: 'Jane Doe',
    doctorName: 'Dr Smith',
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: AppointmentStatus.scheduled,
  );
}

Widget _host({AppointmentRpcTestClient? client, void Function(dynamic result)? onClosed}) {
  final branchId = '44444444-4444-4444-8444-444444444444';
  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(activeBranchId: branchId, branchIds: [branchId]),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client ?? AppointmentRpcTestClient())),
      branchRepositoryProvider.overrideWithValue(_FakeBranchRepository(branchId: branchId)),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await AppointmentRescheduleDialog.show(context, item: _item());
                  onClosed?.call(result);
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
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

BranchWorkingSchedule _allDayWorkingSchedule() {
  return BranchWorkingSchedule(
    BranchWeekday.values
        .map((day) => BranchWorkingDayHours(day: day, isWorkingDay: true, openTime: '00:00', closeTime: '23:59'))
        .toList(growable: false),
  );
}

class _FakeBranchRepository implements BranchRepository {
  _FakeBranchRepository({required this.branchId}) : schedule = _allDayWorkingSchedule();

  final String branchId;
  final BranchWorkingSchedule schedule;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    return [BranchListItem(id: branchId, name: 'Main Branch', isActive: true, workingSchedule: schedule)];
  }

  @override
  Future<String> createBranch(CreateBranchInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) => throw UnimplementedError();

  @override
  Future<String> updateBranch(UpdateBranchInput input) => throw UnimplementedError();
}
