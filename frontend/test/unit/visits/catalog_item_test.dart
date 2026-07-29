import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogItem.fromRow', () {
    test('trivial: parses catalog row with default unit', () {
      final item = CatalogItem.fromRow({
        'id': 'med-1',
        'name': 'Ibuprofen',
        'default_unit': 'mg',
      });

      expect(item, isNotNull);
      expect(item!.id, 'med-1');
      expect(item.name, 'Ibuprofen');
      expect(item.defaultUnit, 'mg');
    });

    test('advanced: parses row without default_unit', () {
      final item = CatalogItem.fromRow({'id': 'inv-1', 'name': 'CBC'});
      expect(item!.defaultUnit, isNull);
    });

    test('edge case: returns null when id or name missing or blank', () {
      expect(CatalogItem.fromRow({}), isNull);
      expect(CatalogItem.fromRow({'id': '', 'name': 'Drug'}), isNull);
      expect(CatalogItem.fromRow({'id': 'x', 'name': '  '}), isNull);
    });

    test('edge case: trims name and treats blank default_unit as null', () {
      final item = CatalogItem.fromRow({'id': 'v1', 'name': '  BP  ', 'default_unit': '  '});
      expect(item!.name, 'BP');
      expect(item.defaultUnit, isNull);
    });
  });

  group('CatalogCreateResult.fromRpcData', () {
    test('trivial: parses successful create response', () {
      final result = CatalogCreateResult.fromRpcData({
        'id': 'med-new',
        'name': 'Aspirin',
        'default_unit': 'tablet',
        'created': true,
      });

      expect(result, isNotNull);
      expect(result!.id, 'med-new');
      expect(result.name, 'Aspirin');
      expect(result.defaultUnit, 'tablet');
      expect(result.created, isTrue);
    });

    test('advanced: treats missing created flag as false', () {
      final result = CatalogCreateResult.fromRpcData({'id': 'med-2', 'name': 'Drug'});
      expect(result!.created, isFalse);
    });

    test('edge case: returns null for null data or missing core fields', () {
      expect(CatalogCreateResult.fromRpcData(null), isNull);
      expect(CatalogCreateResult.fromRpcData({}), isNull);
      expect(CatalogCreateResult.fromRpcData({'id': 'x', 'name': ''}), isNull);
    });

    test('invalid state: ignores unexpected extra keys', () {
      final result = CatalogCreateResult.fromRpcData({
        'id': 'med-3',
        'name': 'Drug',
        'created': true,
        'unexpected': 'ignored',
      });
      expect(result, isNotNull);
    });
  });

  group('DevCatalogSeedResult', () {
    test('trivial: exposes inserted and requested counts', () {
      const result = DevCatalogSeedResult(inserted: 42, requested: 50);
      expect(result.inserted, 42);
      expect(result.requested, 50);
    });
  });
}
