import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServicePromotion.isActiveOn', () {
    final promotion = ServicePromotion(
      price: Money.parse('100.00'),
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 31),
    );

    test('is active on inclusive start and end boundaries', () {
      expect(promotion.isActiveOn(DateTime(2026, 1, 1)), isTrue);
      expect(promotion.isActiveOn(DateTime(2026, 1, 31)), isTrue);
      expect(promotion.isActiveOn(DateTime(2026, 1, 15)), isTrue);
    });

    test('is inactive outside the window', () {
      expect(promotion.isActiveOn(DateTime(2025, 12, 31)), isFalse);
      expect(promotion.isActiveOn(DateTime(2026, 2, 1)), isFalse);
    });

    test('reports expired after end date', () {
      expect(promotion.isExpiredOn(DateTime(2026, 2, 1)), isTrue);
      expect(promotion.isExpiredOn(DateTime(2026, 1, 31)), isFalse);
    });
  });
}
