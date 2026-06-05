/// Payment method aligned with PostgreSQL `payment_method` enum (V1-6).
enum PaymentMethod {
  cash,
  card,
  bankTransfer,
  insuranceSettlement;

  static PaymentMethod? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'cash' => PaymentMethod.cash,
      'card' => PaymentMethod.card,
      'bank_transfer' => PaymentMethod.bankTransfer,
      'insurance_settlement' => PaymentMethod.insuranceSettlement,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    PaymentMethod.cash => 'cash',
    PaymentMethod.card => 'card',
    PaymentMethod.bankTransfer => 'bank_transfer',
    PaymentMethod.insuranceSettlement => 'insurance_settlement',
  };

  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.card => 'Card',
    PaymentMethod.bankTransfer => 'Bank transfer',
    PaymentMethod.insuranceSettlement => 'Insurance settlement',
  };

  /// Patient-tender methods subject to partial-payment policy (D4).
  bool get isPatientTender => switch (this) {
    PaymentMethod.cash || PaymentMethod.card || PaymentMethod.bankTransfer => true,
    PaymentMethod.insuranceSettlement => false,
  };
}
