import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EligibleService.fromRow', () {
    test('parses a valid eligible row', () {
      final service = EligibleService.fromRow({
        'service_id': 'service-1',
        'name': 'Consultation',
        'unit_price': '200.00',
        'applied_rule': 'default',
        'on_promotion': true,
      });

      expect(service, isNotNull);
      expect(service!.serviceId, 'service-1');
      expect(service.name, 'Consultation');
      expect(service.unitPrice, Money.parse('200.00'));
      expect(service.appliedRule, AppliedPriceRule.defaultPrice);
      expect(service.onPromotion, isTrue);
    });

    test('returns null for incomplete rows', () {
      expect(EligibleService.fromRow({'service_id': 'service-1'}), isNull);
      expect(
        EligibleService.fromRow({
          'service_id': 'service-1',
          'name': 'Consultation',
          'unit_price': 'bad',
          'applied_rule': 'default',
        }),
        isNull,
      );
      expect(
        EligibleService.fromRow({
          'service_id': 'service-1',
          'name': 'Consultation',
          'unit_price': '10.00',
          'applied_rule': 'unknown',
        }),
        isNull,
      );
    });
  });
}
