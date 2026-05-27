import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

const _item1 = PatientListItem(
  id: 'p1',
  fullName: 'Ahmed',
  registeringBranchId: 'b1',
  registeringBranchName: 'Main',
);

const _item2 = PatientListItem(
  id: 'p2',
  fullName: 'Sara',
  registeringBranchId: 'b1',
  registeringBranchName: 'Main',
);

void main() {
  group('PatientListUiState.hasMore', () {
    test('true when offset + items < totalCount', () {
      const state = PatientListUiState(
        items: [_item1],
        totalCount: 5,
        limit: 1,
        offset: 0,
        searchQuery: '',
      );

      expect(state.hasMore, isTrue);
    });

    test('false when offset + items == totalCount', () {
      const state = PatientListUiState(
        items: [_item1, _item2],
        totalCount: 2,
        limit: 25,
        offset: 0,
        searchQuery: '',
      );

      expect(state.hasMore, isFalse);
    });

    test('false when offset + items > totalCount', () {
      const state = PatientListUiState(
        items: [_item1, _item2],
        totalCount: 1,
        limit: 25,
        offset: 0,
        searchQuery: '',
      );

      expect(state.hasMore, isFalse);
    });

    test('true with pagination offset', () {
      const state = PatientListUiState(
        items: [_item1],
        totalCount: 50,
        limit: 25,
        offset: 25,
        searchQuery: '',
      );

      expect(state.hasMore, isTrue);
    });

    test('false on empty result', () {
      const state = PatientListUiState(
        items: [],
        totalCount: 0,
        limit: 25,
        offset: 0,
        searchQuery: '',
      );

      expect(state.hasMore, isFalse);
    });
  });

  group('PatientListUiState.copyWith', () {
    const base = PatientListUiState(
      items: [_item1],
      totalCount: 10,
      limit: 25,
      offset: 0,
      searchQuery: 'ahmed',
      validationHint: 'Enter at least 3 characters',
      isLoadingMore: false,
    );

    test('preserves all fields when no overrides', () {
      final copy = base.copyWith();

      expect(copy.items, base.items);
      expect(copy.totalCount, base.totalCount);
      expect(copy.limit, base.limit);
      expect(copy.offset, base.offset);
      expect(copy.searchQuery, base.searchQuery);
      expect(copy.validationHint, base.validationHint);
      expect(copy.isLoadingMore, base.isLoadingMore);
    });

    test('overrides individual fields', () {
      final copy = base.copyWith(
        items: [_item1, _item2],
        totalCount: 20,
        limit: 50,
        offset: 10,
        searchQuery: 'sara',
        isLoadingMore: true,
      );

      expect(copy.items, hasLength(2));
      expect(copy.totalCount, 20);
      expect(copy.limit, 50);
      expect(copy.offset, 10);
      expect(copy.searchQuery, 'sara');
      expect(copy.isLoadingMore, isTrue);
    });

    test('clearValidationHint sets validationHint to null', () {
      final copy = base.copyWith(clearValidationHint: true);

      expect(copy.validationHint, isNull);
    });

    test('validationHint override takes precedence when clearValidationHint is false', () {
      final copy = base.copyWith(validationHint: 'New hint');

      expect(copy.validationHint, 'New hint');
    });

    test('clearValidationHint takes precedence over validationHint override', () {
      final copy = base.copyWith(
        clearValidationHint: true,
        validationHint: 'Should be ignored',
      );

      expect(copy.validationHint, isNull);
    });

    test('isLoadingMore defaults to current value', () {
      const loading = PatientListUiState(
        items: [_item1],
        totalCount: 10,
        limit: 25,
        offset: 0,
        searchQuery: '',
        isLoadingMore: true,
      );

      final copy = loading.copyWith(totalCount: 20);
      expect(copy.isLoadingMore, isTrue);
    });

    test('empty items list is preserved', () {
      final copy = base.copyWith(items: const []);
      expect(copy.items, isEmpty);
    });
  });
}
