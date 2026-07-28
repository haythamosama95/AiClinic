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

  /// Human-readable discount label for detail surfaces (mirrors web `discountLabel`).
  static String labelFor(DiscountKind? kind, String? value) {
    if (kind == null || value == null || value.trim().isEmpty) {
      return '—';
    }

    return switch (kind) {
      DiscountKind.percentage => '$value% off',
      DiscountKind.fixed => '${_formatFixedValue(value)} off',
    };
  }

  static String _formatFixedValue(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return parsed.toStringAsFixed(2);
  }
}
