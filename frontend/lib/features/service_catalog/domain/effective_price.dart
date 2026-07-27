import 'package:ai_clinic/core/money/money.dart';

/// Which pricing rule produced the resolved unit price (Service Catalog 015).
enum AppliedPriceRule {
  promo('promo'),
  override('override'),
  defaultPrice('default');

  const AppliedPriceRule(this.wireValue);

  final String wireValue;

  static AppliedPriceRule? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    for (final rule in AppliedPriceRule.values) {
      if (rule.wireValue == raw) {
        return rule;
      }
    }
    return null;
  }
}

/// Server-resolved effective unit price for a service at a branch on a date.
class EffectivePrice {
  const EffectivePrice({required this.unitPrice, required this.appliedRule});

  final Money unitPrice;
  final AppliedPriceRule appliedRule;

  bool get onPromotion => appliedRule == AppliedPriceRule.promo;

  static EffectivePrice? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final unitPrice = Money.tryParse(data['unit_price']?.toString());
    final appliedRule = AppliedPriceRule.tryParse(data['applied_rule']?.toString());
    if (unitPrice == null || appliedRule == null) {
      return null;
    }
    return EffectivePrice(unitPrice: unitPrice, appliedRule: appliedRule);
  }
}
