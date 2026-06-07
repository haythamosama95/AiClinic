import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_overlap_conflict.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/shift_rpc_test_client.dart';

void main() {
  group('ShiftRepository (US4 mutations + overlap parsing)', () {
    late ShiftRpcTestClient client;
    late ShiftRepository repository;

    setUp(() {
      client = ShiftRpcTestClient();
      repository = ShiftRepository(client);
    });

    test('parseOverlapConflicts extracts staff name and time range', () {
      const message =
          'shift_overlap: [{"staff_member_id":"11111111-1111-4111-8111-111111111111","display_name":"Dr Ahmed","conflicting_shift_id":"22222222-2222-4222-8222-222222222222","start_time":"09:00","end_time":"17:00"}]';

      final conflicts = ShiftRepository.parseOverlapConflicts(message);

      expect(conflicts, hasLength(1));
      expect(conflicts.first.displayName, 'Dr Ahmed');
      expect(conflicts.first.startTime, '09:00');
      expect(conflicts.first.endTime, '17:00');
    });

    test('parseOverlapConflicts returns empty list for unrelated messages', () {
      expect(ShiftRepository.parseOverlapConflicts('permission_denied'), isEmpty);
    });

    test('updateShift sends expected_updated_at and field params', () async {
      final expectedAt = DateTime.utc(2026, 6, 1, 12);

      await repository.updateShift(
        shiftId: ShiftRpcTestClient.defaultShiftId,
        expectedUpdatedAt: expectedAt,
        shiftDate: DateTime(2026, 6, 10),
        startTime: '10:00',
        endTime: '18:00',
        notes: 'Updated note',
      );

      expect(client.lastFunction, 'update_shift');
      expect(client.paramsFor('update_shift')?['p_shift_id'], ShiftRpcTestClient.defaultShiftId);
      expect(client.paramsFor('update_shift')?['p_expected_updated_at'], expectedAt.toUtc().toIso8601String());
      expect(client.paramsFor('update_shift')?['p_shift_date'], '2026-06-10');
      expect(client.paramsFor('update_shift')?['p_start_time'], '10:00');
      expect(client.paramsFor('update_shift')?['p_end_time'], '18:00');
      expect(client.paramsFor('update_shift')?['p_notes'], 'Updated note');
    });

    test('updateShift rejects blank shift id before RPC', () {
      expect(
        () => repository.updateShift(
          shiftId: '  ',
          expectedUpdatedAt: DateTime.utc(2026, 6, 1),
          shiftDate: DateTime(2026, 6, 10),
          startTime: '09:00',
          endTime: '17:00',
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('cancelShift sends stale guard timestamp', () async {
      final expectedAt = DateTime.utc(2026, 6, 2, 8);

      await repository.cancelShift(shiftId: ShiftRpcTestClient.defaultShiftId, expectedUpdatedAt: expectedAt);

      expect(client.lastFunction, 'cancel_shift');
      expect(client.paramsFor('cancel_shift')?['p_expected_updated_at'], expectedAt.toUtc().toIso8601String());
    });

    test('updateShift maps stale_shift PostgrestException', () async {
      client.updateShiftException = PostgrestException(message: 'stale_shift', code: 'P0001');

      expect(
        () => repository.updateShift(
          shiftId: ShiftRpcTestClient.defaultShiftId,
          expectedUpdatedAt: DateTime.utc(2026, 6, 1),
          shiftDate: DateTime(2026, 6, 10),
          startTime: '09:00',
          endTime: '17:00',
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'stale_shift')),
      );
    });

    test('createShift dedupes duplicate staff ids before RPC', () async {
      const staffId = ShiftRpcTestClient.secondStaffId;

      await repository.createShift(
        branchId: client.branchId,
        shiftDate: DateTime(2026, 6, 10),
        startTime: '09:00',
        endTime: '17:00',
        staffIds: [staffId, staffId, '  $staffId  '],
      );

      expect(client.paramsFor('create_shift')?['p_staff_ids'], [staffId]);
    });

    test('modifyAssignments dedupes duplicate staff ids before RPC', () async {
      const staffId = ShiftRpcTestClient.secondStaffId;
      final expectedAt = DateTime.utc(2026, 6, 1, 12);

      await repository.modifyAssignments(
        shiftId: ShiftRpcTestClient.defaultShiftId,
        expectedUpdatedAt: expectedAt,
        addStaffIds: [staffId, staffId],
        removeStaffIds: [client.staffId, client.staffId],
      );

      expect(client.paramsFor('modify_shift_assignments')?['p_add_staff_ids'], [staffId]);
      expect(client.paramsFor('modify_shift_assignments')?['p_remove_staff_ids'], [client.staffId]);
    });

    test('getShiftDetail read-only flag surfaces from RPC payload', () async {
      client.getShiftDetailOverride = {
        'shift': {
          'id': ShiftRpcTestClient.defaultShiftId,
          'branch_id': client.branchId,
          'shift_date': '2026-06-10',
          'start_time': '09:00',
          'end_time': '17:00',
          'notes': null,
          'status': 'active',
          'is_unassigned': false,
          'is_past': false,
          'is_read_only': true,
          'updated_at': DateTime.utc(2026, 6, 1).toIso8601String(),
        },
        'assignments': [],
        'branch': {'id': client.branchId, 'name': 'Main', 'code': 'MAIN'},
      };

      final detail = await repository.getShiftDetail(shiftId: ShiftRpcTestClient.defaultShiftId);

      expect(detail.isReadOnly, isTrue);
    });
  });

  group('ShiftOverlapConflict', () {
    test('parseList ignores malformed rows', () {
      final conflicts = ShiftOverlapConflict.parseList([
        {'display_name': 'Missing fields'},
        {
          'staff_member_id': '11111111-1111-4111-8111-111111111111',
          'display_name': 'Nurse',
          'conflicting_shift_id': '22222222-2222-4222-8222-222222222222',
          'start_time': '13:00',
          'end_time': '15:00',
        },
      ]);

      expect(conflicts, hasLength(1));
      expect(conflicts.first.displayName, 'Nurse');
    });
  });
}
