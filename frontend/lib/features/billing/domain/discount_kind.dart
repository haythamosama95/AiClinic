/// Discount kind aligned with PostgreSQL `discount_kind` enum (V1-6).
enum DiscountKind {
  percentage,
  fixed;

  static DiscountKind? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'percentage' => DiscountKind.percentage,
      'fixed' => DiscountKind.fixed,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    DiscountKind.percentage => 'percentage',
    DiscountKind.fixed => 'fixed',
  };

  String get label => switch (this) {
    DiscountKind.percentage => 'Percentage',
    DiscountKind.fixed => 'Fixed amount',
  };
}
