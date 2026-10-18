import 'package:intl/intl.dart';

/// Formats stored minor units for display without changing wire values.
class BillingMoney {
  const BillingMoney._();

  static String format(int amountMinor, String currency, String locale) {
    final formatter = NumberFormat.currency(
      locale: locale,
      name: currency,
      decimalDigits: 2,
    );
    return formatter.format(amountMinor / 100);
  }
}
