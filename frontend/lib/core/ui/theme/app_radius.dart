/// Corner radii from the design system (`02-tokens` §6).
abstract final class AppRadius {
  static const sm = 4.0;
  static const md = 6.0;
  static const lg = 8.0;
  static const xl = 12.0;
  static const x2l = 16.0;
  static const full = 9999.0;

  static double token(String name) {
    return switch (name) {
      'sm' => sm,
      'md' => md,
      'lg' => lg,
      'xl' => xl,
      '2xl' => x2l,
      'full' => full,
      _ => md,
    };
  }
}
