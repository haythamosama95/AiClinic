import 'package:ai_clinic/features/billing/domain/money.dart';
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
<<<<<<< HEAD
=======

  group('ServicePromotion.tryParse', () {
    test('parses valid promotion wire values', () {
      final promotion = ServicePromotion.tryParse(
        price: '100.00',
        startDate: '2026-01-01',
        endDate: '2026-01-31',
      );

      expect(promotion, isNotNull);
      expect(promotion!.price, Money.parse('100.00'));
      expect(promotion.startDate, DateTime.parse('2026-01-01'));
      expect(promotion.endDate, DateTime.parse('2026-01-31'));
    });

    test('returns null when any field is missing or invalid', () {
      expect(
        ServicePromotion.tryParse(price: '100.00', startDate: '2026-01-01', endDate: null),
        isNull,
      );
      expect(
        ServicePromotion.tryParse(price: 'bad', startDate: '2026-01-01', endDate: '2026-01-31'),
        isNull,
      );
      expect(
        ServicePromotion.tryParse(price: '100.00', startDate: '', endDate: '2026-01-31'),
        isNull,
      );
      expect(
        ServicePromotion.tryParse(price: '100.00', startDate: '2026-01-01', endDate: 'not-a-date'),
        isNull,
      );
    });
  });

  group('ServicePromotion wire getters', () {
    test('wirePrice, wireStartDate, and wireEndDate encode values', () {
      final promotion = ServicePromotion(
        price: Money.parse('100.50'),
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 1, 20),
      );

      expect(promotion.wirePrice, '100.50');
      expect(promotion.wireStartDate, '2026-01-05');
      expect(promotion.wireEndDate, '2026-01-20');
    });
  });
>>>>>>> master
}
