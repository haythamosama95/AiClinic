import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_eligibility.dart';
import 'package:ai_clinic/features/service_catalog/presentation/utils/service_price_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceEligibility', () {
    test('parses eligible resolution', () {
      final eligibility = ServiceEligibility.fromRpcData({
        'eligible': true,
        'unit_price': '120.00',
        'applied_rule': 'override',
        'reason': null,
      });

      expect(eligibility.eligible, isTrue);
      expect(eligibility.reason, isNull);
      expect(eligibility.price?.unitPrice, Money.parse('120.00'));
      expect(eligibility.price?.appliedRule, AppliedPriceRule.override);
    });

    test('parses ineligible resolution with reason', () {
      final eligibility = ServiceEligibility.fromRpcData({
        'eligible': false,
        'unit_price': null,
        'applied_rule': null,
        'reason': 'BRANCH_INACTIVE',
      });

      expect(eligibility.eligible, isFalse);
      expect(eligibility.reason, EligibilityReason.branchInactive);
      expect(eligibility.price, isNull);
    });
  });

  group('ServicePricePreview', () {
    test('formats default price without suffix', () {
      final label = ServicePricePreview.formatWithRule(
        EffectivePrice(unitPrice: Money.parse('200.00'), appliedRule: AppliedPriceRule.defaultPrice),
      );

      expect(label, '\$200.00');
    });

    test('formats promo price with suffix', () {
      final label = ServicePricePreview.formatWithRule(
        EffectivePrice(unitPrice: Money.parse('100.00'), appliedRule: AppliedPriceRule.promo),
      );

      expect(label, '\$100.00 (promo)');
    });

    test('promotion badge only when on promotion', () {
      expect(ServicePricePreview.promotionBadge(onPromotion: true), 'On promotion');
      expect(ServicePricePreview.promotionBadge(onPromotion: false), isNull);
    });
  });
}
