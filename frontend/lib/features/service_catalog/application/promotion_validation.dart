import 'package:ai_clinic/core/money/money.dart';

/// Client-side promotion field validation (Service Catalog 015 US4).
abstract final class PromotionValidation {
  static String? validatePrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Promotion price is required.';
    }
    final parsed = Money.tryParse(trimmed);
    if (parsed == null) {
      return 'Enter a valid non-negative price with at most two decimal places.';
    }
    return null;
  }

  static String? validateDateRange({DateTime? start, DateTime? end}) {
    if (start == null || end == null) {
      return 'Promotion requires both start and end dates.';
    }
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    if (startDay.isAfter(endDay)) {
      return 'Start date must be on or before the end date.';
    }
    return null;
  }

  static String? validateAgainstEffective({required String promotionPrice, required String effectivePrice}) {
    final promo = Money.tryParse(promotionPrice.trim());
    final effective = Money.tryParse(effectivePrice.trim());
    if (promo == null || effective == null) {
      return null;
    }
    if (promo.compareTo(effective) > 0) {
      return 'Promotion price cannot exceed the effective price.';
    }
    return null;
  }
}
