import 'package:ai_clinic/features/shifts/domain/shift_assignment.dart';
import 'package:ai_clinic/features/shifts/domain/shift_assignment_result.dart';
import 'package:ai_clinic/features/shifts/domain/shift_detail.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

ShiftDetail _sampleDetail({String? notes}) {
  return ShiftDetail(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    branchId: '44444444-4444-4444-8444-444444444444',
    shiftDate: DateTime.utc(2026, 6, 10),
    startTime: '09:00',
    endTime: '17:00',
    status: ShiftStatus.active,
    isUnassigned: false,
    isPast: false,
    isReadOnly: false,
    assignments: const [
      ShiftAssignment(
        id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        staffMemberId: '22222222-2222-4222-8222-222222222222',
        displayName: 'Dr Shift',
      ),
    ],
    branch: const ShiftBranchSummary(id: '44444444-4444-4444-8444-444444444444', name: 'Main Branch', code: 'MAIN'),
    notes: notes,
  );
}

void main() {
  group('ShiftDetail.toListItem (#20 notes preview trim)', () {
    test('trims whitespace before building notes preview', () {
      final listItem = _sampleDetail(notes: '   foo   ').toListItem();

      expect(listItem.notesPreview, 'foo');
    });

    test('truncates trimmed notes to 80 characters', () {
      final longNote = '${'x' * 90}';
      final listItem = _sampleDetail(notes: '  $longNote  ').toListItem();

      expect(listItem.notesPreview, 'x' * 80);
    });
  });

  group('ShiftAssignmentResult.fromRpcData (#18 nullable updated_at)', () {
    test('parses response when updated_at is omitted', () {
      final result = ShiftAssignmentResult.fromRpcData({
        'shift_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'status': 'active',
        'assignee_count': 2,
      });

      expect(result, isNotNull);
      expect(result!.shiftId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(result.assigneeCount, 2);
      expect(result.updatedAt, isNull);
    });
  });

  group('ShiftDetail.fromRpcData (#6 empty branch code)', () {
    test('parses shift detail when branch code is empty', () {
      final detail = ShiftDetail.fromRpcData({
        'shift': {
          'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'branch_id': '44444444-4444-4444-8444-444444444444',
          'shift_date': '2026-06-10',
          'start_time': '09:00',
          'end_time': '17:00',
          'status': 'active',
          'is_unassigned': false,
          'is_past': false,
          'is_read_only': false,
        },
        'assignments': [],
        'branch': {'id': '44444444-4444-4444-8444-444444444444', 'name': 'Main Branch', 'code': ''},
      });

      expect(detail, isNotNull);
      expect(detail!.branch.name, 'Main Branch');
      expect(detail.branch.code, isNull);
    });
  });
}
