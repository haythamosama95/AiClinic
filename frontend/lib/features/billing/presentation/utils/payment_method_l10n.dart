import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:flutter/widgets.dart';

extension PaymentMethodL10n on PaymentMethod {
  String labelFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      PaymentMethod.cash => l10n.paymentMethodCash,
      PaymentMethod.card => l10n.paymentMethodCard,
      PaymentMethod.bankTransfer => l10n.paymentMethodBankTransfer,
      PaymentMethod.insuranceSettlement =>
        l10n.paymentMethodInsuranceSettlement,
    };
  }
}
