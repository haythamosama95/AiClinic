import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';

void main() {
  group('CatalogNameNormalizer.normalize', () {
    test('trims leading and trailing whitespace', () {
      expect(CatalogNameNormalizer.normalize('  amoxicillin  '), 'Amoxicillin');
    });

    test('collapses internal whitespace', () {
      expect(CatalogNameNormalizer.normalize('blood  pressure'), 'Blood pressure');
    });

    test('capitalizes first character only', () {
      expect(CatalogNameNormalizer.normalize('iBUPROFEN'), 'IBUPROFEN');
    });

    test('returns empty string for blank input', () {
      expect(CatalogNameNormalizer.normalize(''), '');
      expect(CatalogNameNormalizer.normalize('   '), '');
    });

    test('preserves single-character names', () {
      expect(CatalogNameNormalizer.normalize('a'), 'A');
    });
  });
}
