/// Spacing scale from the design system (`02-tokens` §5).
abstract final class AppSpacing {
  static const space0 = 0.0;
  static const spacePx = 1.0;
  static const space05 = 2.0;
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space8 = 32.0;
  static const space10 = 40.0;
  static const space12 = 48.0;
  static const space16 = 64.0;
  static const space20 = 80.0;
  static const space24 = 96.0;

  static double token(String name) {
    return switch (name) {
      '0' => space0,
      'px' => spacePx,
      '0.5' => space05,
      '1' => space1,
      '2' => space2,
      '3' => space3,
      '4' => space4,
      '5' => space5,
      '6' => space6,
      '8' => space8,
      '10' => space10,
      '12' => space12,
      '16' => space16,
      '20' => space20,
      '24' => space24,
      _ => space4,
    };
  }
}
