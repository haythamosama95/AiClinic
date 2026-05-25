import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffListItem.fromRow', () {
    test('parses staff with role and branch name list', () {
      final item = StaffListItem.fromRow({
        'id': 'staff-1',
        'full_name': '  Dr. Sam  ',
        'role': 'doctor',
        'is_active': true,
        'phone': '+20 111',
      });

      expect(item, isNotNull);
      expect(item!.fullName, 'Dr. Sam');
      expect(item.role, StaffRole.doctor);
      expect(item.branchNames, isEmpty);
      expect(item.phone, '+20 111');
    });

    test('returns null for invalid rows', () {
      expect(StaffListItem.fromRow({'id': '', 'full_name': 'X', 'role': 'doctor'}), isNull);
      expect(StaffListItem.fromRow({'id': '1', 'full_name': '', 'role': 'doctor'}), isNull);
      expect(StaffListItem.fromRow({'id': '1', 'full_name': 'X', 'role': 'invalid_role'}), isNull);
      expect(StaffListItem.fromRow({'id': '1', 'full_name': 'X'}), isNull);
    });

    test('parses lab_staff wire value', () {
      final item = StaffListItem.fromRow({'id': '1', 'full_name': 'Lab', 'role': 'lab_staff', 'is_active': true});
      expect(item!.role, StaffRole.labStaff);
    });

    test('fromRow always yields empty branchNames (loaded separately via copyWith)', () {
      final item = StaffListItem.fromRow({'id': '1', 'full_name': 'X', 'role': 'owner', 'is_active': false});
      expect(item!.branchNames, isEmpty);
      expect(item.branchNamesLabel, 'No branches assigned');
    });
  });

  group('StaffListItem.branchNamesLabel', () {
    test('joins multiple branches for list subtitle', () {
      const item = StaffListItem(
        id: '1',
        fullName: 'A',
        role: StaffRole.administrator,
        isActive: true,
        branchNames: ['North', 'South'],
      );

      expect(item.branchNamesLabel, 'North, South');
    });
  });

  group('StaffListItem equality', () {
    test('listEquals on branchNames', () {
      const a = StaffListItem(id: '1', fullName: 'A', role: StaffRole.doctor, isActive: true, branchNames: ['X']);
      const b = StaffListItem(id: '1', fullName: 'A', role: StaffRole.doctor, isActive: true, branchNames: ['X']);
      const c = StaffListItem(id: '1', fullName: 'A', role: StaffRole.doctor, isActive: true, branchNames: ['Y']);

      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });
}
