import 'package:ai_clinic/features/billing/domain/payment_method.dart';

/// Partial-payment rules for patient-tender methods (V1-6 D4).
abstract final class PaymentPolicy {
  static bool requiresFullBalance({
    required PaymentMethod method,
    required bool allowPartialPayments,
  }) =>
      method.isPatientTender && !allowPartialPayments;
}
