import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_eligibility.dart';
import 'package:ai_clinic/features/service_catalog/presentation/utils/service_price_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppliedPriceRule.tryParse', () {
    test('parses known wire values', () {
      expect(AppliedPriceRule.tryParse('promo'), AppliedPriceRule.promo);
      expect(AppliedPriceRule.tryParse('override'), AppliedPriceRule.override);
      expect(AppliedPriceRule.tryParse('default'), AppliedPriceRule.defaultPrice);
    });

    test('returns null for null, empty, or unknown values', () {
      expect(AppliedPriceRule.tryParse(null), isNull);
      expect(AppliedPriceRule.tryParse(''), isNull);
      expect(AppliedPriceRule.tryParse('unknown'), isNull);
    });
  });

  group('EffectivePrice', () {
    test('fromRpcData parses unit price and rule', () {
      final price = EffectivePrice.fromRpcData({
        'unit_price': '150.00',
        'applied_rule': 'override',
      });

      expect(price, isNotNull);
      expect(price!.unitPrice, Money.parse('150.00'));
      expect(price.appliedRule, AppliedPriceRule.override);
    });

    test('onPromotion is true only for promo rule', () {
      expect(
        EffectivePrice(unitPrice: Money.parse('100.00'), appliedRule: AppliedPriceRule.promo).onPromotion,
        isTrue,
      );
      expect(
        EffectivePrice(unitPrice: Money.parse('100.00'), appliedRule: AppliedPriceRule.override).onPromotion,
        isFalse,
      );
    });

    test('fromRpcData returns null for invalid data', () {
      expect(EffectivePrice.fromRpcData(null), isNull);
      expect(
        EffectivePrice.fromRpcData({'unit_price': 'bad', 'applied_rule': 'default'}),
        isNull,
      );
    });
  });

  group('EligibilityReason.tryParse', () {
    test('parses known wire values', () {
      expect(EligibilityReason.tryParse('GLOBAL_INACTIVE'), EligibilityReason.globalInactive);
      expect(EligibilityReason.tryParse('NOT_ASSIGNED'), EligibilityReason.notAssigned);
      expect(EligibilityReason.tryParse('BRANCH_INACTIVE'), EligibilityReason.branchInactive);
    });

    test('returns null for null, empty, or unknown values', () {
      expect(EligibilityReason.tryParse(null), isNull);
      expect(EligibilityReason.tryParse(''), isNull);
      expect(EligibilityReason.tryParse('UNKNOWN'), isNull);
    });
  });

  group('ServiceEligibility', () {
    test('fromRpcData with null data returns ineligible', () {
      final eligibility = ServiceEligibility.fromRpcData(null);

      expect(eligibility.eligible, isFalse);
      expect(eligibility.price, isNull);
      expect(eligibility.reason, isNull);
    });

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

    test('formats override price with suffix', () {
      final label = ServicePricePreview.formatWithRule(
        EffectivePrice(unitPrice: Money.parse('175.00'), appliedRule: AppliedPriceRule.override),
      );

      expect(label, '\$175.00 (override)');
    });

    test('formatUnitPrice formats money with currency', () {
      expect(
        ServicePricePreview.formatUnitPrice(Money.parse('250.00')),
        '\$250.00',
      );
    });

    test('promotion badge only when on promotion', () {
      expect(ServicePricePreview.promotionBadge(onPromotion: true), 'On promotion');
      expect(ServicePricePreview.promotionBadge(onPromotion: false), isNull);
    });
  });
}
