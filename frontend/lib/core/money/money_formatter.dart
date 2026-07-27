import 'package:intl/intl.dart';

import 'package:ai_clinic/core/money/money.dart';

/// Shared currency formatting for billing and catalog surfaces (V1-6).
abstract final class MoneyFormatter {
  static const fallbackCurrencyCode = 'USD';

  static String format(Money amount, {required String currency, String? locale}) {
    final formatLocale = locale ?? 'en_US';
    final symbol = _currencySymbol(currency);
    try {
      if (symbol != null) {
        return NumberFormat.currency(locale: formatLocale, symbol: symbol).format(amount.asDouble);
      }
      return NumberFormat.currency(locale: formatLocale, name: currency.toUpperCase()).format(amount.asDouble);
    } on Object {
      final value = amount.wireValue;
      if (symbol != null) {
        return '$symbol$value';
      }
      return '$value $currency';
    }
  }

  static String? _currencySymbol(String currency) {
    return switch (currency.toUpperCase()) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      'EGP' => 'E£ ',
      _ => null,
    };
  }
}
