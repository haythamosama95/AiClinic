import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientListFilters high-severity regressions', () {
    test('H1: no assigned-doctor filter field is exposed', () {
      const filters = PatientListFilters();

      expect(filters.hasActiveFilters, isFalse);
      expect(filters.activeFilterCount, 0);
      expect(filters.copyWith(branchId: 'branch-1').hasActiveFilters, isTrue);
    });

    test('H2: last visit filter and sort wire values map to search_patients RPC', () {
      expect(PatientLastVisitFilter.over90Days.wireValue, 'over_90_days');
      expect(PatientLastVisitFilter.never.wireValue, 'never');
      expect(PatientSortField.lastVisitDesc.wireValue, 'last_visit_desc');
      expect(PatientSortField.nameAsc.wireValue, 'name_asc');
    });
  });

  group('PatientTableRow', () {
    PatientListItem item({required String id, required String name, DateTime? lastVisitAt}) {
      return PatientListItem(
        id: id,
        fullName: name,
        registeringBranchId: 'branch-1',
        registeringBranchName: 'Main',
        lastVisitAt: lastVisitAt,
      );
    }

    test('H2: rows are not client-filtered after server pagination', () {
      final rows = PatientTableRow.fromItems([
        item(id: 'p1', name: 'Alpha', lastVisitAt: DateTime.utc(2026, 1, 1)),
        item(id: 'p2', name: 'Beta', lastVisitAt: DateTime.utc(2025, 1, 1)),
        item(id: 'p3', name: 'Gamma'),
      ]);

      expect(rows, hasLength(3));
      expect(rows.map((row) => row.item.fullName), ['Alpha', 'Beta', 'Gamma']);
    });

    test('displayId truncates long ids to eight uppercase characters', () {
      final row = PatientTableRow(
        item: item(id: 'abcdefgh-ijkl-mnop', name: 'Pat'),
      );

      expect(row.displayId, 'ABCDEFGH');
    });

    test('displayId uppercases short ids without truncation', () {
      final row = PatientTableRow(item: item(id: 'p1', name: 'Pat'));

      expect(row.displayId, 'P1');
    });
  });

  group('PatientListFilters.offset', () {
    test('page 1 starts at offset zero', () {
      const filters = PatientListFilters(page: 1, pageSize: 20);

      expect(filters.offset, 0);
    });

    test('page 2 offsets by one page size', () {
      const filters = PatientListFilters(page: 2, pageSize: 20);

      expect(filters.offset, 20);
    });

    test('large page numbers scale with page size', () {
      const filters = PatientListFilters(page: 100, pageSize: 50);

      expect(filters.offset, 4950);
    });

    test('page zero yields negative offset (no guard in model)', () {
      const filters = PatientListFilters(page: 0, pageSize: 20);

      expect(filters.offset, -20);
    });
  });

  group('PatientListFilters.hasSearchOrFilters', () {
    test('false when search is empty and no active filters', () {
      const filters = PatientListFilters();

      expect(filters.hasSearchOrFilters, isFalse);
    });

    test('false when search is whitespace only', () {
      const filters = PatientListFilters(searchText: '   \t');

      expect(filters.hasSearchOrFilters, isFalse);
    });

    test('true when search text is non-empty after trim', () {
      const filters = PatientListFilters(searchText: '  Sara  ');

      expect(filters.hasSearchOrFilters, isTrue);
    });

    test('true when branch filter is active', () {
      const filters = PatientListFilters(branchId: 'branch-1');

      expect(filters.hasSearchOrFilters, isTrue);
    });

    test('true when last visit filter is not any', () {
      const filters = PatientListFilters(
        lastVisitFilter: PatientLastVisitFilter.last30Days,
      );

      expect(filters.hasSearchOrFilters, isTrue);
    });

    test('false when only sort differs from default', () {
      const filters = PatientListFilters(sortField: PatientSortField.nameDesc);

      expect(filters.hasSearchOrFilters, isFalse);
    });
  });

  group('PatientListFilters.copyWith', () {
    const original = PatientListFilters(
      searchText: 'query',
      branchId: 'branch-1',
      lastVisitFilter: PatientLastVisitFilter.last90Days,
      sortField: PatientSortField.lastVisitDesc,
      page: 3,
      pageSize: 25,
    );

    test('updates searchText', () {
      expect(original.copyWith(searchText: 'new').searchText, 'new');
    });

    test('preserves branchId when omitted', () {
      expect(original.copyWith(searchText: 'x').branchId, 'branch-1');
    });

    test('clears branchId when explicitly set to null', () {
      expect(original.copyWith(branchId: null).branchId, isNull);
    });

    test('sets all-branches sentinel when explicitly provided', () {
      expect(
        original.copyWith(branchId: PatientListFilters.allBranchesSentinel).branchId,
        PatientListFilters.allBranchesSentinel,
      );
    });

    test('updates lastVisitFilter', () {
      expect(
        original.copyWith(lastVisitFilter: PatientLastVisitFilter.never).lastVisitFilter,
        PatientLastVisitFilter.never,
      );
    });

    test('updates sortField', () {
      expect(
        original.copyWith(sortField: PatientSortField.nameAsc).sortField,
        PatientSortField.nameAsc,
      );
    });

    test('updates page', () {
      expect(original.copyWith(page: 5).page, 5);
    });

    test('updates pageSize', () {
      expect(original.copyWith(pageSize: 50).pageSize, 50);
    });
  });

  group('PatientListFilters.isAllBranchesFilter', () {
    test('true for all-branches sentinel', () {
      const filters = PatientListFilters(
        branchId: PatientListFilters.allBranchesSentinel,
      );

      expect(filters.isAllBranchesFilter, isTrue);
    });

    test('false for a concrete branch id', () {
      const filters = PatientListFilters(branchId: 'branch-1');

      expect(filters.isAllBranchesFilter, isFalse);
    });

    test('false when branchId is null', () {
      const filters = PatientListFilters();

      expect(filters.isAllBranchesFilter, isFalse);
    });
  });

  group('PatientListFilters active filter metrics', () {
    test('no filters: count zero and hasActiveFilters false', () {
      const filters = PatientListFilters();

      expect(filters.activeFilterCount, 0);
      expect(filters.hasActiveFilters, isFalse);
    });

    test('search only does not count toward active filters', () {
      const filters = PatientListFilters(searchText: 'Sara');

      expect(filters.activeFilterCount, 0);
      expect(filters.hasActiveFilters, isFalse);
    });

    test('last visit filter only increments count', () {
      const filters = PatientListFilters(
        lastVisitFilter: PatientLastVisitFilter.over90Days,
      );

      expect(filters.activeFilterCount, 1);
      expect(filters.hasActiveFilters, isTrue);
    });

    test('branch filter only increments count', () {
      const filters = PatientListFilters(branchId: 'branch-1');

      expect(filters.activeFilterCount, 1);
      expect(filters.hasActiveFilters, isTrue);
    });

    test('all-branches sentinel counts as an active branch filter', () {
      const filters = PatientListFilters(
        branchId: PatientListFilters.allBranchesSentinel,
      );

      expect(filters.activeFilterCount, 1);
      expect(filters.hasActiveFilters, isTrue);
    });

    test('sort only does not count', () {
      const filters = PatientListFilters(sortField: PatientSortField.nameDesc);

      expect(filters.activeFilterCount, 0);
      expect(filters.hasActiveFilters, isFalse);
    });

    test('branch and last visit together increment count to two', () {
      const filters = PatientListFilters(
        branchId: 'branch-1',
        lastVisitFilter: PatientLastVisitFilter.never,
      );

      expect(filters.activeFilterCount, 2);
      expect(filters.hasActiveFilters, isTrue);
    });
  });

  group('PatientSortField wireValue', () {
    test('maps every sort field to search_patients RPC value', () {
      expect(PatientSortField.nameAsc.wireValue, 'name_asc');
      expect(PatientSortField.nameDesc.wireValue, 'name_desc');
      expect(PatientSortField.lastVisitAsc.wireValue, 'last_visit_asc');
      expect(PatientSortField.lastVisitDesc.wireValue, 'last_visit_desc');
    });
  });

  group('PatientLastVisitFilter wireValue', () {
    test('maps every last-visit filter to search_patients RPC value', () {
      expect(PatientLastVisitFilter.any.wireValue, 'any');
      expect(PatientLastVisitFilter.last30Days.wireValue, 'last_30_days');
      expect(PatientLastVisitFilter.last90Days.wireValue, 'last_90_days');
      expect(PatientLastVisitFilter.over90Days.wireValue, 'over_90_days');
      expect(PatientLastVisitFilter.never.wireValue, 'never');
    });
  });
}
