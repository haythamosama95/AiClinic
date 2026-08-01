import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';

void main() {
  group('PatientListUiState getters', () {
    test('isEmptyResult is true when rows are empty', () {
      const state = PatientListUiState(
        rows: [],
        totalCount: 0,
        filters: PatientListFilters(),
      );

      expect(state.isEmptyResult, isTrue);
    });

    test('isEmptyResult is false when rows are present', () {
      final state = PatientListUiState(
        rows: [PatientTableRow(item: samplePatientListItem())],
        totalCount: 1,
        filters: const PatientListFilters(),
      );

      expect(state.isEmptyResult, isFalse);
    });

    test('isNoPatientsYet is true for empty browse state with no filters', () {
      const state = PatientListUiState(
        rows: [],
        totalCount: 0,
        filters: PatientListFilters(),
      );

      expect(state.isNoPatientsYet, isTrue);
      expect(state.isNoMatch, isFalse);
    });

    test('isNoPatientsYet is false when totalCount is non-zero even if rows are empty', () {
      const state = PatientListUiState(
        rows: [],
        totalCount: 12,
        filters: PatientListFilters(),
      );

      expect(state.isNoPatientsYet, isFalse);
      expect(state.isNoMatch, isTrue);
    });

    test('isNoMatch is true when search text is active and rows are empty', () {
      const state = PatientListUiState(
        rows: [],
        totalCount: 0,
        filters: PatientListFilters(searchText: 'Sara'),
      );

      expect(state.isNoPatientsYet, isFalse);
      expect(state.isNoMatch, isTrue);
    });

    test('isNoMatch is true when last-visit filter is active and rows are empty', () {
      const state = PatientListUiState(
        rows: [],
        totalCount: 0,
        filters: PatientListFilters(lastVisitFilter: PatientLastVisitFilter.never),
      );

      expect(state.isNoPatientsYet, isFalse);
      expect(state.isNoMatch, isTrue);
    });

    test('isNoMatch is true when all-branches filter is active and rows are empty', () {
      const state = PatientListUiState(
        rows: [],
        totalCount: 0,
        filters: PatientListFilters(branchId: PatientListFilters.allBranchesSentinel),
      );

      expect(state.isNoPatientsYet, isFalse);
      expect(state.isNoMatch, isTrue);
    });

    test('searchHint suppresses isNoMatch and isNoPatientsYet', () {
      const state = PatientListUiState(
        rows: [],
        totalCount: 0,
        filters: PatientListFilters(searchText: 'ab'),
        searchHint: 'Enter at least 3 characters to search by name.',
      );

      expect(state.isNoPatientsYet, isFalse);
      expect(state.isNoMatch, isFalse);
    });

    test('whitespace-only search does not count as an active filter', () {
      const state = PatientListUiState(
        rows: [],
        totalCount: 0,
        filters: PatientListFilters(searchText: '   '),
      );

      expect(state.filters.hasSearchOrFilters, isFalse);
      expect(state.isNoPatientsYet, isTrue);
      expect(state.isNoMatch, isFalse);
    });
  });
}
