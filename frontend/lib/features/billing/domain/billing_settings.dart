import 'package:flutter/foundation.dart';

/// Organization billing settings (`get_billing_settings`, V1-6).
@immutable
class BillingSettings {
  const BillingSettings({required this.allowPartialPayments});

  final bool allowPartialPayments;

  static BillingSettings? fromRow(Map<String, dynamic> row) {
    final allowPartial = row['allow_partial_payments'];
    if (allowPartial == null) {
      return null;
    }

    return BillingSettings(allowPartialPayments: allowPartial == true || allowPartial.toString() == 'true');
  }
}
