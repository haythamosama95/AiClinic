/// Layout spacing scale derived from `--spacing: 0.25rem` (4 logical pixels).
abstract final class SpacingTokens {
  /// Base unit (`--spacing`).
  static const double unit = 4;

  static const double xs = unit;
  static const double sm = unit * 2;
  static const double md = unit * 4;
  static const double lg = unit * 6;
  static const double xl = unit * 8;
  static const double xxl = unit * 12;
}
