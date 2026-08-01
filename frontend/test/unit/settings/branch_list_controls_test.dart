import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/branch_list_controls.dart';
import 'package:flutter_test/flutter_test.dart';

List<BranchListItem> _sampleBranches() {
  return const [
    BranchListItem(id: '1', name: 'Zeta Clinic', isActive: false, code: 'Z1', address: 'North', phone: '111'),
    BranchListItem(id: '2', name: 'Alpha Clinic', isActive: true, code: 'A2', address: 'South', phone: '222'),
    BranchListItem(id: '3', name: 'Beta Clinic', isActive: true, code: 'B1', address: 'East', phone: '333'),
  ];
}

void main() {
  group('BranchSortKeyWire', () {
    test('serializes and parses wire values', () {
      expect(BranchSortKey.nameAsc.wireValue, 'name-asc');
      expect(BranchSortKey.nameDesc.wireValue, 'name-desc');
      expect(BranchSortKey.codeAsc.wireValue, 'code-asc');
      expect(BranchSortKey.status.wireValue, 'status');

      expect(BranchSortKeyWire.fromWire('name-desc'), BranchSortKey.nameDesc);
      expect(BranchSortKeyWire.fromWire('code-asc'), BranchSortKey.codeAsc);
      expect(BranchSortKeyWire.fromWire('status'), BranchSortKey.status);
      expect(BranchSortKeyWire.fromWire('unknown'), BranchSortKey.nameAsc);
    });
  });

  group('BranchStatusFilterWire', () {
    test('serializes and parses wire values', () {
      expect(BranchStatusFilter.all.wireValue, 'all');
      expect(BranchStatusFilter.active.wireValue, 'active');
      expect(BranchStatusFilter.inactive.wireValue, 'inactive');

      expect(BranchStatusFilterWire.fromWire('active'), BranchStatusFilter.active);
      expect(BranchStatusFilterWire.fromWire('inactive'), BranchStatusFilter.inactive);
      expect(BranchStatusFilterWire.fromWire('other'), BranchStatusFilter.all);
    });
  });

  group('filterAndSortBranches', () {
    test('returns empty list for empty input', () {
      const controls = DEFAULT_BRANCH_CONTROLS;

      expect(filterAndSortBranches([], controls), isEmpty);
    });

    test('filters by search across name, code, address, and phone', () {
      const controls = BranchListControls(
        search: 'south',
        status: BranchStatusFilter.all,
        sort: BranchSortKey.nameAsc,
      );

      final result = filterAndSortBranches(_sampleBranches(), controls);

      expect(result, hasLength(1));
      expect(result.first.name, 'Alpha Clinic');
    });

    test('filters by active and inactive status', () {
      final active = filterAndSortBranches(
        _sampleBranches(),
        const BranchListControls(search: '', status: BranchStatusFilter.active, sort: BranchSortKey.nameAsc),
      );
      final inactive = filterAndSortBranches(
        _sampleBranches(),
        const BranchListControls(search: '', status: BranchStatusFilter.inactive, sort: BranchSortKey.nameAsc),
      );

      expect(active.map((branch) => branch.name), ['Alpha Clinic', 'Beta Clinic']);
      expect(inactive.map((branch) => branch.name), ['Zeta Clinic']);
    });

    test('sorts by name, code, and active status', () {
      final nameAsc = filterAndSortBranches(
        _sampleBranches(),
        const BranchListControls(search: '', status: BranchStatusFilter.all, sort: BranchSortKey.nameAsc),
      );
      final nameDesc = filterAndSortBranches(
        _sampleBranches(),
        const BranchListControls(search: '', status: BranchStatusFilter.all, sort: BranchSortKey.nameDesc),
      );
      final codeAsc = filterAndSortBranches(
        _sampleBranches(),
        const BranchListControls(search: '', status: BranchStatusFilter.all, sort: BranchSortKey.codeAsc),
      );
      final status = filterAndSortBranches(
        _sampleBranches(),
        const BranchListControls(search: '', status: BranchStatusFilter.all, sort: BranchSortKey.status),
      );

      expect(nameAsc.map((branch) => branch.name), ['Alpha Clinic', 'Beta Clinic', 'Zeta Clinic']);
      expect(nameDesc.map((branch) => branch.name), ['Zeta Clinic', 'Beta Clinic', 'Alpha Clinic']);
      expect(codeAsc.map((branch) => branch.code), ['A2', 'B1', 'Z1']);
      expect(status.map((branch) => branch.isActive), [true, true, false]);
    });

    test('returns no matches when search finds nothing', () {
      const controls = BranchListControls(
        search: 'missing',
        status: BranchStatusFilter.all,
        sort: BranchSortKey.nameAsc,
      );

      expect(filterAndSortBranches(_sampleBranches(), controls), isEmpty);
    });
  });
}
