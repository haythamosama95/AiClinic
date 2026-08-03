import 'package:ai_clinic/features/service_catalog/application/promotion_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PromotionValidation.validatePrice', () {
    test('accepts valid non-negative prices', () {
      expect(PromotionValidation.validatePrice('0'), isNull);
      expect(PromotionValidation.validatePrice('100.50'), isNull);
      expect(PromotionValidation.validatePrice(' 75.00 '), isNull);
    });

    test('rejects empty values', () {
      expect(PromotionValidation.validatePrice(''), isNotNull);
      expect(PromotionValidation.validatePrice('   '), isNotNull);
      expect(PromotionValidation.validatePrice(null), isNotNull);
    });

    test('rejects invalid formats', () {
      expect(PromotionValidation.validatePrice('abc'), isNotNull);
      expect(PromotionValidation.validatePrice('12,50'), isNotNull);
    });

    test('rejects negative values', () {
      expect(PromotionValidation.validatePrice('-1'), isNotNull);
      expect(PromotionValidation.validatePrice('-0.01'), isNotNull);
    });

    test('rejects more than two decimal places', () {
      expect(PromotionValidation.validatePrice('12.345'), isNotNull);
      expect(PromotionValidation.validatePrice('0.001'), isNotNull);
    });
  });

  group('PromotionValidation.validateDateRange', () {
    test('requires both start and end dates', () {
      expect(
        PromotionValidation.validateDateRange(start: null, end: DateTime(2026, 1, 31)),
        isNotNull,
      );
      expect(
        PromotionValidation.validateDateRange(start: DateTime(2026, 1, 1), end: null),
        isNotNull,
      );
      expect(
        PromotionValidation.validateDateRange(start: null, end: null),
        isNotNull,
      );
    });

    test('rejects start date after end date', () {
      expect(
        PromotionValidation.validateDateRange(
          start: DateTime(2026, 2, 1),
          end: DateTime(2026, 1, 31),
        ),
        isNotNull,
      );
    });

    test('accepts inclusive same-day and multi-day ranges', () {
      expect(
        PromotionValidation.validateDateRange(
          start: DateTime(2026, 1, 15),
          end: DateTime(2026, 1, 15),
        ),
        isNull,
      );
      expect(
        PromotionValidation.validateDateRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
        isNull,
      );
    });

    test('compares calendar days only, ignoring time of day', () {
      expect(
        PromotionValidation.validateDateRange(
          start: DateTime(2026, 1, 15, 23, 59),
          end: DateTime(2026, 1, 16, 0, 0),
        ),
        isNull,
      );
    });
  });

  group('PromotionValidation.validateAgainstEffective', () {
    test('rejects promotion price above effective price', () {
      expect(
        PromotionValidation.validateAgainstEffective(
          promotionPrice: '150.00',
          effectivePrice: '100.00',
        ),
        isNotNull,
      );
    });

    test('accepts promotion price equal to effective price', () {
      expect(
        PromotionValidation.validateAgainstEffective(
          promotionPrice: '100.00',
          effectivePrice: '100.00',
        ),
        isNull,
      );
    });

    test('accepts promotion price below effective price', () {
      expect(
        PromotionValidation.validateAgainstEffective(
          promotionPrice: '75.00',
          effectivePrice: '100.00',
        ),
        isNull,
      );
    });

    test('returns null when either price is invalid money', () {
      expect(
        PromotionValidation.validateAgainstEffective(
          promotionPrice: 'abc',
          effectivePrice: '100.00',
        ),
        isNull,
      );
      expect(
        PromotionValidation.validateAgainstEffective(
          promotionPrice: '50.00',
          effectivePrice: 'invalid',
        ),
        isNull,
      );
    });
  });
}
