import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_detail_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/shift_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

const _branchId = '44444444-4444-4444-8444-444444444444';
const _shiftAId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _shiftBId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

Map<String, dynamic> _detailPayload({
  required String shiftId,
  required String notes,
  String status = 'active',
  bool isReadOnly = false,
}) {
  return {
    'shift': {
      'id': shiftId,
      'branch_id': _branchId,
      'shift_date': '2026-06-10',
      'start_time': '09:00',
      'end_time': '17:00',
      'notes': notes,
      'status': status,
      'is_unassigned': false,
      'is_past': false,
      'is_read_only': isReadOnly,
      'updated_at': DateTime.utc(2026, 6, 1, 10).toIso8601String(),
    },
    'assignments': [
      {
        'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'staff_member_id': '22222222-2222-4222-8222-222222222222',
        'display_name': 'Dr Shift',
      },
    ],
    'branch': {'id': _branchId, 'name': 'Main Branch', 'code': 'MAIN'},
  };
}

void main() {
  late ShiftRpcTestClient client;
  late ProviderContainer container;

  setUp(() {
    client = ShiftRpcTestClient(branchId: _branchId)
      ..detailByShiftId = {
        _shiftAId: _detailPayload(shiftId: _shiftAId, notes: 'Shift A notes'),
        _shiftBId: _detailPayload(shiftId: _shiftBId, notes: 'Shift B notes'),
      };

    container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(
          () => _PresetAuth(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(activeBranchId: _branchId, branchIds: [_branchId]),
            ),
          ),
        ),
        shiftRepositoryProvider.overrideWith((ref) => ShiftRepository(client)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('family provider loads the correct shift id for each instance', () async {
    final stateA = await container.read(shiftDetailProvider(_shiftAId).future);
    final stateB = await container.read(shiftDetailProvider(_shiftBId).future);

    expect(stateA.detail.id, _shiftAId);
    expect(stateA.detail.notes, 'Shift A notes');
    expect(stateB.detail.id, _shiftBId);
    expect(stateB.detail.notes, 'Shift B notes');

    expect(client.rpcLog.where((name) => name == 'get_shift_detail').length, greaterThanOrEqualTo(2));
    expect(client.paramsFor('get_shift_detail')?['p_shift_id'], isNotNull);
  });

  test('cancelShift reloads detail with cancelled status in local state', () async {
    client.detailByShiftId[_shiftAId] = _detailPayload(shiftId: _shiftAId, notes: 'Active shift');

    final notifier = container.read(shiftDetailProvider(_shiftAId).notifier);
    final before = await container.read(shiftDetailProvider(_shiftAId).future);
    expect(before.detail.status, ShiftStatus.active);
    expect(before.detail.isReadOnly, isFalse);

    final cancelled = await notifier.cancelShift();
    expect(cancelled, isTrue);

    final after = container.read(shiftDetailProvider(_shiftAId)).value!;
    expect(after.detail.status, ShiftStatus.cancelled);
    expect(after.detail.isReadOnly, isTrue);
    expect(after.mutationStatus, ShiftDetailMutationStatus.idle);
    expect(client.rpcLog, contains('cancel_shift'));
    expect(client.rpcLog.where((name) => name == 'get_shift_detail').length, greaterThanOrEqualTo(2));
  });
}
