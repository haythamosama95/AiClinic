/// Mutually exclusive discount application scope (V1-6 US3).
enum DiscountScope {
  line,
  invoice;

  String get label => switch (this) {
    DiscountScope.line => 'Line item',
    DiscountScope.invoice => 'Invoice total',
  };
}
