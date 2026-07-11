import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';

enum BranchStatusFilter { all, active, inactive }

enum BranchSortKey { nameAsc, nameDesc, codeAsc, status }

class BranchListControls {
  const BranchListControls({
    required this.search,
    required this.status,
    required this.sort,
  });

  final String search;
  final BranchStatusFilter status;
  final BranchSortKey sort;

  BranchListControls copyWith({
    String? search,
    BranchStatusFilter? status,
    BranchSortKey? sort,
  }) {
    return BranchListControls(
      search: search ?? this.search,
      status: status ?? this.status,
      sort: sort ?? this.sort,
    );
  }

  bool get isSortCustom => sort != DEFAULT_BRANCH_CONTROLS.sort;

  BranchListControls withDefaultSort() => copyWith(sort: DEFAULT_BRANCH_CONTROLS.sort);
}

class BranchSortOption {
  const BranchSortOption({required this.value, required this.label});

  final BranchSortKey value;
  final String label;
}

// Web-port constant names (see `branch-list-controls.ts`).
// ignore: constant_identifier_names
const BRANCH_SORT_OPTIONS = <BranchSortOption>[
  BranchSortOption(value: BranchSortKey.nameAsc, label: 'Name A–Z'),
  BranchSortOption(value: BranchSortKey.nameDesc, label: 'Name Z–A'),
  BranchSortOption(value: BranchSortKey.codeAsc, label: 'Code A–Z'),
  BranchSortOption(value: BranchSortKey.status, label: 'Active first'),
];

// ignore: constant_identifier_names
const DEFAULT_BRANCH_CONTROLS = BranchListControls(
  search: '',
  status: BranchStatusFilter.all,
  sort: BranchSortKey.nameAsc,
);

extension BranchSortKeyWire on BranchSortKey {
  String get wireValue => switch (this) {
    BranchSortKey.nameAsc => 'name-asc',
    BranchSortKey.nameDesc => 'name-desc',
    BranchSortKey.codeAsc => 'code-asc',
    BranchSortKey.status => 'status',
  };

  static BranchSortKey fromWire(String value) => switch (value) {
    'name-desc' => BranchSortKey.nameDesc,
    'code-asc' => BranchSortKey.codeAsc,
    'status' => BranchSortKey.status,
    _ => BranchSortKey.nameAsc,
  };
}

extension BranchStatusFilterWire on BranchStatusFilter {
  String get wireValue => name;

  static BranchStatusFilter fromWire(String value) => switch (value) {
    'active' => BranchStatusFilter.active,
    'inactive' => BranchStatusFilter.inactive,
    _ => BranchStatusFilter.all,
  };
}

List<BranchListItem> filterAndSortBranches(
  List<BranchListItem> branches,
  BranchListControls controls,
) {
  var rows = [...branches];
  final query = controls.search.trim().toLowerCase();

  if (query.isNotEmpty) {
    rows = rows.where((branch) {
      final name = branch.name.toLowerCase();
      final code = (branch.code ?? '').toLowerCase();
      final address = (branch.address ?? '').toLowerCase();
      final phone = branch.phone ?? '';
      return name.contains(query) ||
          code.contains(query) ||
          address.contains(query) ||
          phone.contains(query);
    }).toList(growable: false);
  }

  switch (controls.status) {
    case BranchStatusFilter.active:
      rows = rows.where((branch) => branch.isActive).toList(growable: false);
    case BranchStatusFilter.inactive:
      rows = rows.where((branch) => !branch.isActive).toList(growable: false);
    case BranchStatusFilter.all:
      break;
  }

  int compareName(BranchListItem a, BranchListItem b) => a.name.compareTo(b.name);
  int compareCode(BranchListItem a, BranchListItem b) => (a.code ?? '').compareTo(b.code ?? '');

  switch (controls.sort) {
    case BranchSortKey.nameDesc:
      rows.sort((a, b) => b.name.compareTo(a.name));
    case BranchSortKey.codeAsc:
      rows.sort(compareCode);
    case BranchSortKey.status:
      rows.sort((a, b) {
        final statusCompare = (b.isActive ? 1 : 0).compareTo(a.isActive ? 1 : 0);
        return statusCompare != 0 ? statusCompare : compareName(a, b);
      });
    case BranchSortKey.nameAsc:
      rows.sort(compareName);
  }

  return rows;
}
