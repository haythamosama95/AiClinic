import 'package:ai_clinic/features/service_catalog/application/service_form_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceFormValidation.validateName', () {
    test('accepts non-empty trimmed names', () {
      expect(ServiceFormValidation.validateName(' Consultation '), isNull);
    });

    test('rejects empty names', () {
      expect(ServiceFormValidation.validateName(''), isNotNull);
      expect(ServiceFormValidation.validateName('   '), isNotNull);
    });

    test('rejects names longer than 200 characters', () {
      expect(ServiceFormValidation.validateName('x' * 201), isNotNull);
    });
  });

  group('ServiceFormValidation.validateDefaultPrice', () {
    test('accepts non-negative money values', () {
      expect(ServiceFormValidation.validateDefaultPrice('0'), isNull);
      expect(ServiceFormValidation.validateDefaultPrice('200.50'), isNull);
    });

    test('rejects empty, invalid, comma, and negative values', () {
      expect(ServiceFormValidation.validateDefaultPrice(''), isNotNull);
      expect(ServiceFormValidation.validateDefaultPrice('abc'), isNotNull);
      expect(ServiceFormValidation.validateDefaultPrice('12,50'), isNotNull);
      expect(ServiceFormValidation.validateDefaultPrice('-1'), isNotNull);
    });
  });

  group('ServiceFormValidation.validateBranchSelection', () {
    test('allows all-branches mode without selections', () {
      expect(
        ServiceFormValidation.validateBranchSelection(assignAllBranches: true, selectedBranchIds: const {}),
        isNull,
      );
    });

    test('requires at least one branch in selected mode', () {
      expect(
        ServiceFormValidation.validateBranchSelection(assignAllBranches: false, selectedBranchIds: const {}),
        isNotNull,
      );
      expect(
        ServiceFormValidation.validateBranchSelection(assignAllBranches: false, selectedBranchIds: const {'branch-1'}),
        isNull,
      );
    });
  });
}
