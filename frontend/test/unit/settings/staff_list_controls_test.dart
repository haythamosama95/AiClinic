import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/staff_list_controls.dart';
import 'package:flutter_test/flutter_test.dart';

List<StaffListItem> _sampleStaff() {
  return const [
    StaffListItem(
      id: '1',
      fullName: 'Zoe Admin',
      role: StaffRole.administrator,
      isActive: true,
      username: 'zoe',
      branches: [StaffBranchLabel(id: 'branch-b', name: 'Beta', isPrimary: true)],
    ),
    StaffListItem(
      id: '2',
      fullName: 'Adam Doctor',
      role: StaffRole.doctor,
      isActive: true,
      phone: '5551111',
      username: 'adam',
      branches: [StaffBranchLabel(id: 'branch-a', name: 'Alpha', isPrimary: true)],
    ),
    StaffListItem(
      id: '3',
      fullName: 'Rita Reception',
      role: StaffRole.receptionist,
      isActive: true,
      username: 'rita',
      branches: [StaffBranchLabel(id: 'branch-b', name: 'Beta')],
    ),
  ];
}

List<BranchListItem> _sampleBranches() {
  return const [
    BranchListItem(id: 'branch-a', name: 'Alpha', isActive: true),
    BranchListItem(id: 'branch-b', name: 'Beta', isActive: true),
  ];
}

void main() {
  group('resetStaffSort', () {
    test('restores default name ascending sort', () {
      const controls = StaffListControls(sort: StaffSortKey.roleAsc);

      final reset = resetStaffSort(controls);

      expect(reset.sort, defaultStaffSort);
      expect(reset.search, controls.search);
    });
  });

  group('filterAndSortStaff', () {
    test('returns empty list for empty input', () {
      expect(
        filterAndSortStaff(staff: [], branches: [], controls: defaultStaffControls),
        isEmpty,
      );
    });

    test('filters by search across name, username, phone, and role label', () {
      final byName = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(search: 'adam'),
      );
      final byRoleLabel = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(search: 'reception'),
      );
      final byPhone = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(search: '5551111'),
      );

      expect(byName.map((member) => member.fullName), ['Adam Doctor']);
      expect(byRoleLabel.map((member) => member.fullName), ['Rita Reception']);
      expect(byPhone.map((member) => member.fullName), ['Adam Doctor']);
    });

    test('filters by role and branch assignment', () {
      final byRole = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(role: StaffRole.doctor),
      );
      final byBranch = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(branchId: 'branch-b'),
      );

      expect(byRole.map((member) => member.fullName), ['Adam Doctor']);
      expect(byBranch.map((member) => member.fullName), containsAll(['Zoe Admin', 'Rita Reception']));
      expect(byBranch, hasLength(2));
    });

    test('sorts by name, role, and branch', () {
      final nameAsc = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(sort: StaffSortKey.nameAsc),
      );
      final nameDesc = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(sort: StaffSortKey.nameDesc),
      );
      final roleAsc = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(sort: StaffSortKey.roleAsc),
      );
      final branchAsc = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(sort: StaffSortKey.branchAsc),
      );

      expect(nameAsc.map((member) => member.fullName), ['Adam Doctor', 'Rita Reception', 'Zoe Admin']);
      expect(nameDesc.map((member) => member.fullName), ['Zoe Admin', 'Rita Reception', 'Adam Doctor']);
      expect(roleAsc.first.fullName, 'Zoe Admin');
      expect(branchAsc.first.fullName, 'Adam Doctor');
    });

    test('returns no matches when filters exclude everyone', () {
      final result = filterAndSortStaff(
        staff: _sampleStaff(),
        branches: _sampleBranches(),
        controls: const StaffListControls(search: 'missing'),
      );

      expect(result, isEmpty);
    });
  });
}
