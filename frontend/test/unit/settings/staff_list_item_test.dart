import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffListItem.isAssignedToBranch', () {
    const branchA = '00000000-0000-4000-8000-000000000001';
    const branchB = '00000000-0000-4000-8000-000000000002';

    const doctor = StaffListItem(
      id: 'doctor-1',
      fullName: 'Dr. Ada',
      role: StaffRole.doctor,
      isActive: true,
      branches: [StaffBranchLabel(id: branchA, name: 'Branch A', isPrimary: true)],
    );

    test('returns true when branch is assigned', () {
      expect(doctor.isAssignedToBranch(branchA), isTrue);
    });

    test('returns false when branch is not assigned', () {
      expect(doctor.isAssignedToBranch(branchB), isFalse);
    });

    test('returns false for empty branch id', () {
      expect(doctor.isAssignedToBranch(''), isFalse);
      expect(doctor.isAssignedToBranch('   '), isFalse);
    });
  });
}
