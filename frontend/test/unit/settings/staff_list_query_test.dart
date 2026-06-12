import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const member = StaffListItem(
    id: '1',
    fullName: 'Dr. Sam',
    role: StaffRole.doctor,
    isActive: true,
    phone: '+20 111 222 3333',
    username: 'drsam',
    branches: [StaffBranchLabel(id: 'branch-1', name: 'Main Clinic', isPrimary: true)],
  );

  group('StaffListQuery.matches', () {
    test('matches by full name', () {
      const query = StaffListQuery(searchText: 'sam');
      expect(query.matches(member), isTrue);
    });

    test('matches by username', () {
      const query = StaffListQuery(searchText: 'drsa');
      expect(query.matches(member), isTrue);
    });

    test('matches by phone digits', () {
      const query = StaffListQuery(searchText: '111222');
      expect(query.matches(member), isTrue);
    });

    test('filters by role', () {
      const query = StaffListQuery(roles: {StaffRole.receptionist});
      expect(query.matches(member), isFalse);
    });

    test('filters by branch id', () {
      const query = StaffListQuery(branchIds: {'branch-1'});
      expect(query.matches(member), isTrue);

      const otherBranch = StaffListQuery(branchIds: {'branch-2'});
      expect(otherBranch.matches(member), isFalse);
    });

    test('combines search and filters', () {
      const query = StaffListQuery(searchText: 'sam', roles: {StaffRole.doctor}, branchIds: {'branch-1'});
      expect(query.matches(member), isTrue);

      const mismatch = StaffListQuery(searchText: 'sam', roles: {StaffRole.receptionist});
      expect(mismatch.matches(member), isFalse);
    });

    test('matches when any selected role matches', () {
      const query = StaffListQuery(roles: {StaffRole.doctor, StaffRole.receptionist});
      expect(query.matches(member), isTrue);
    });
  });
}
