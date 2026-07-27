import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/constants/clinic_constants.dart';

typedef StaffRoleFilter = StaffRole?;

enum StaffSortKey { nameAsc, nameDesc, roleAsc, branchAsc }

class StaffListControls {
  const StaffListControls({
    this.search = '',
    this.role,
    this.branchId,
    this.sort = StaffSortKey.nameAsc,
  });

  final String search;
  final StaffRoleFilter role;
  final String? branchId;
  final StaffSortKey sort;

  StaffListControls copyWith({
    String? search,
    StaffRoleFilter? role,
    String? branchId,
    StaffSortKey? sort,
    bool clearRole = false,
    bool clearBranchId = false,
  }) {
    return StaffListControls(
      search: search ?? this.search,
      role: clearRole ? null : (role ?? this.role),
      branchId: clearBranchId ? null : (branchId ?? this.branchId),
      sort: sort ?? this.sort,
    );
  }
}

const defaultStaffControls = StaffListControls();

/// Default staff list sort (web `DEFAULT_STAFF_CONTROLS.sort`).
const defaultStaffSort = StaffSortKey.nameAsc;

StaffListControls resetStaffSort(StaffListControls controls) =>
    controls.copyWith(sort: defaultStaffSort);

/// Web `DEFAULT_STAFF_CONTROLS` alias.
// ignore: constant_identifier_names
const DEFAULT_STAFF_CONTROLS = defaultStaffControls;

const staffSortOptions = <({StaffSortKey value, String label})>[
  (value: StaffSortKey.nameAsc, label: 'Name A–Z'),
  (value: StaffSortKey.nameDesc, label: 'Name Z–A'),
  (value: StaffSortKey.roleAsc, label: 'Role A–Z'),
  (value: StaffSortKey.branchAsc, label: 'Branch A–Z'),
];

/// Web `STAFF_SORT_OPTIONS` alias.
// ignore: constant_identifier_names
const STAFF_SORT_OPTIONS = staffSortOptions;

List<StaffListItem> filterAndSortStaff({
  required List<StaffListItem> staff,
  required List<BranchListItem> branches,
  required StaffListControls controls,
}) {
  var rows = [...staff];
  final query = controls.search.trim().toLowerCase();

  if (query.isNotEmpty) {
    rows = rows.where((member) {
      final roleLabel = kRoleLabels[member.role]?.toLowerCase() ?? '';
      return member.fullName.toLowerCase().contains(query) ||
          (member.username?.toLowerCase().contains(query) ?? false) ||
          (member.phone?.contains(query) ?? false) ||
          roleLabel.contains(query);
    }).toList();
  }

  if (controls.role != null) {
    rows = rows.where((member) => member.role == controls.role).toList();
  }

  if (controls.branchId != null && controls.branchId!.isNotEmpty) {
    rows = rows.where((member) => member.isAssignedToBranch(controls.branchId!)).toList();
  }

  String branchNameFor(StaffListItem member) {
    final primary = member.branches.where((branch) => branch.isPrimary).map((branch) => branch.name).firstOrNull;
    if (primary != null) {
      return primary;
    }
    return member.branches.firstOrNull?.name ?? '';
  }

  switch (controls.sort) {
    case StaffSortKey.nameDesc:
      rows.sort((a, b) => b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase()));
    case StaffSortKey.roleAsc:
      rows.sort((a, b) {
        final roleCompare = (kRoleLabels[a.role] ?? '').compareTo(kRoleLabels[b.role] ?? '');
        return roleCompare != 0 ? roleCompare : a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });
    case StaffSortKey.branchAsc:
      rows.sort((a, b) {
        final branchCompare = branchNameFor(a).compareTo(branchNameFor(b));
        return branchCompare != 0 ? branchCompare : a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });
    case StaffSortKey.nameAsc:
      rows.sort(StaffListItem.compareByFullName);
  }

  return rows;
}
