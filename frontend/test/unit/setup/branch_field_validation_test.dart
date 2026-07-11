import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchFieldValidation.validatePhone', () {
    test('accepts digits only', () {
      expect(BranchFieldValidation.validatePhone('201000000000'), isNull);
    });

    test('rejects empty values', () {
      expect(BranchFieldValidation.validatePhone(''), isNotNull);
      expect(BranchFieldValidation.validatePhone('   '), isNotNull);
    });

    test('rejects non-digit characters', () {
      expect(BranchFieldValidation.validatePhone('+20 100 000 0000'), isNotNull);
      expect(BranchFieldValidation.validatePhone('123-456'), isNotNull);
      expect(BranchFieldValidation.validatePhone('abc'), isNotNull);
    });
  });

  group('BranchFieldValidation.validateMapsUrl', () {
    test('accepts https and http URLs', () {
      expect(BranchFieldValidation.validateMapsUrl('https://maps.google.com/?q=test'), isNull);
      expect(BranchFieldValidation.validateMapsUrl('http://maps.example/main'), isNull);
    });

    test('accepts bare domains without a scheme', () {
      expect(BranchFieldValidation.validateMapsUrl('www.google.com'), isNull);
      expect(BranchFieldValidation.validateMapsUrl('maps.google.com/place/test'), isNull);
    });

    test('rejects empty and invalid values', () {
      expect(BranchFieldValidation.validateMapsUrl(''), isNotNull);
      expect(BranchFieldValidation.validateMapsUrl('not a url'), isNotNull);
      expect(BranchFieldValidation.validateMapsUrl('ftp://example.com'), isNotNull);
    });
  });
}
