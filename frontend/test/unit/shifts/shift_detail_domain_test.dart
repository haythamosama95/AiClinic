import 'package:ai_clinic/features/shifts/domain/shift_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
