import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientSearchPage.fromRpcData', () {
    test('parses well-formed search result with items', () {
      final page = PatientSearchPage.fromRpcData({
        'items': [
          {
            'id': 'p1',
            'full_name': 'Ahmed Hassan',
            'phone': '201234567890',
            'date_of_birth': '1990-05-15',
            'branch_id': 'b1',
            'branch_name': 'Main',
          },
          {
            'id': 'p2',
            'full_name': 'Sara Ali',
            'branch_id': 'b1',
            'branch_name': 'Main',
          },
        ],
        'total_count': 42,
        'limit': 25,
        'offset': 0,
      });

      expect(page.items, hasLength(2));
      expect(page.items[0].fullName, 'Ahmed Hassan');
      expect(page.items[1].fullName, 'Sara Ali');
      expect(page.totalCount, 42);
      expect(page.limit, 25);
      expect(page.offset, 0);
    });

    test('null data returns empty page with defaults', () {
      final page = PatientSearchPage.fromRpcData(null);

      expect(page.items, isEmpty);
      expect(page.totalCount, 0);
      expect(page.limit, 25);
      expect(page.offset, 0);
    });

    test('empty items list returns zero items', () {
      final page = PatientSearchPage.fromRpcData({
        'items': <dynamic>[],
        'total_count': 0,
        'limit': 25,
        'offset': 0,
      });

      expect(page.items, isEmpty);
      expect(page.totalCount, 0);
    });

    test('missing items key returns empty list', () {
      final page = PatientSearchPage.fromRpcData({
        'total_count': 5,
        'limit': 10,
        'offset': 0,
      });

      expect(page.items, isEmpty);
    });

    test('items that are not maps are skipped', () {
      final page = PatientSearchPage.fromRpcData({
        'items': [42, 'string', null, true],
        'total_count': 0,
        'limit': 25,
        'offset': 0,
      });

      expect(page.items, isEmpty);
    });

    test('malformed item rows are skipped', () {
      final page = PatientSearchPage.fromRpcData({
        'items': [
          {'id': '', 'full_name': 'Bad'},
          {
            'id': 'p1',
            'full_name': 'Good',
            'branch_id': 'b1',
            'branch_name': 'Main',
          },
        ],
        'total_count': 1,
        'limit': 25,
        'offset': 0,
      });

      expect(page.items, hasLength(1));
      expect(page.items.first.fullName, 'Good');
    });

    test('total_count as string is parsed', () {
      final page = PatientSearchPage.fromRpcData({
        'items': <dynamic>[],
        'total_count': '100',
        'limit': '50',
        'offset': '25',
      });

      expect(page.totalCount, 100);
      expect(page.limit, 50);
      expect(page.offset, 25);
    });

    test('non-numeric total_count falls back to items length', () {
      final page = PatientSearchPage.fromRpcData({
        'items': [
          {'id': 'p1', 'full_name': 'X', 'branch_id': 'b1', 'branch_name': 'B'},
        ],
        'total_count': 'bad',
        'limit': 25,
        'offset': 0,
      });

      expect(page.totalCount, 1);
    });

    test('missing pagination fields use defaults', () {
      final page = PatientSearchPage.fromRpcData({
        'items': <dynamic>[],
      });

      expect(page.totalCount, 0);
      expect(page.limit, 25);
      expect(page.offset, 0);
    });

    test('items as non-list is treated as empty', () {
      final page = PatientSearchPage.fromRpcData({
        'items': 'not a list',
        'total_count': 0,
        'limit': 25,
        'offset': 0,
      });

      expect(page.items, isEmpty);
    });

    test('mixed valid and invalid items preserves order', () {
      final page = PatientSearchPage.fromRpcData({
        'items': [
          {'id': 'p1', 'full_name': 'First', 'branch_id': 'b1', 'branch_name': 'B'},
          {'id': '', 'full_name': 'Skip'},
          {'id': 'p3', 'full_name': 'Third', 'branch_id': 'b1', 'branch_name': 'B'},
        ],
        'total_count': 2,
        'limit': 25,
        'offset': 0,
      });

      expect(page.items, hasLength(2));
      expect(page.items[0].fullName, 'First');
      expect(page.items[1].fullName, 'Third');
    });

    test('zero limit is preserved', () {
      final page = PatientSearchPage.fromRpcData({
        'items': <dynamic>[],
        'total_count': 0,
        'limit': 0,
        'offset': 0,
      });

      expect(page.limit, 0);
    });

    test('negative offset is preserved from payload', () {
      final page = PatientSearchPage.fromRpcData({
        'items': <dynamic>[],
        'total_count': 0,
        'limit': 25,
        'offset': -1,
      });

      expect(page.offset, -1);
    });
  });
}
