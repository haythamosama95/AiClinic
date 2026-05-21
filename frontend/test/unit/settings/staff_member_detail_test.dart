import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffMemberDetail.fromRow', () {
    test('parses assignments and primary branch', () {
      final detail = StaffMemberDetail.fromRow({
        'id': 's1',
        'full_name': 'Dr. Smith',
        'role': 'doctor',
        'is_active': true,
        'phone': '+1',
        'staff_branch_assignments': [
          {'branch_id': 'b1', 'is_primary': true, 'is_deleted': false},
          {'branch_id': 'b2', 'is_primary': false, 'is_deleted': false},
        ],
      });

      expect(detail?.branchIds, ['b1', 'b2']);
      expect(detail?.primaryBranchId, 'b1');
      expect(detail?.phone, '+1');
    });

    test('edge case: skips deleted assignments', () {
      final detail = StaffMemberDetail.fromRow({
        'id': 's1',
        'full_name': 'X',
        'role': 'receptionist',
        'is_active': true,
        'staff_branch_assignments': [
          {'branch_id': 'b1', 'is_primary': true, 'is_deleted': true},
        ],
      });

      expect(detail?.branchIds, isEmpty);
    });

    test('invalid row returns null', () {
      expect(StaffMemberDetail.fromRow({'id': '', 'full_name': 'X', 'role': 'doctor'}), isNull);
    });
  });
}
