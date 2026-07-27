import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/money/money_formatter.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';

/// Pure price-preview formatter reused across catalog flows (NFR-008).
abstract final class ServicePricePreview {
  static String formatUnitPrice(Money unitPrice, {String currency = 'USD'}) {
    return MoneyFormatter.format(unitPrice, currency: currency);
  }

  static String formatWithRule(EffectivePrice price, {String currency = 'USD'}) {
    final amount = formatUnitPrice(price.unitPrice, currency: currency);
    return switch (price.appliedRule) {
      AppliedPriceRule.promo => '$amount (promo)',
      AppliedPriceRule.override => '$amount (override)',
      AppliedPriceRule.defaultPrice => amount,
    };
  }

  static String? promotionBadge({required bool onPromotion}) {
    return onPromotion ? 'On promotion' : null;
  }
}
