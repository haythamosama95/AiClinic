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
  });
}
