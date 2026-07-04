/// Semantic icon size tokens matching the design system scale.
enum AppIconSize {
  /// 16 logical pixels.
  sm,

  /// 20 logical pixels — default.
  md,

  /// 24 logical pixels.
  lg,

  /// 32 logical pixels.
  xl;

  /// Resolves this token to a concrete dimension in logical pixels.
  double get value => switch (this) {
    AppIconSize.sm => 16,
    AppIconSize.md => 20,
    AppIconSize.lg => 24,
    AppIconSize.xl => 32,
  };
}
