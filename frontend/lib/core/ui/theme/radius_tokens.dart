/// Border radius tokens derived from `--radius: 0.5rem`.
abstract final class RadiusTokens {
  /// Base radius (`--radius-lg` / `--radius`).
  static const double lg = 8;

  /// `--radius-sm: calc(var(--radius) - 4px)`.
  static const double sm = 4;

  /// `--radius-md: calc(var(--radius) - 2px)`.
  static const double md = 6;

  /// `--radius-xl: calc(var(--radius) + 4px)`.
  static const double xl = 12;
}
