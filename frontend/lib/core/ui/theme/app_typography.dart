import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';

/// Application text styles aligned with the design system type scale (`02-tokens` §4).
abstract final class AppTypography {
  static TextTheme textTheme({required Brightness brightness}) {
    final base = GoogleFonts.interTextTheme();
    final primary = brightness == Brightness.dark ? AppColorPrimitives.textPrimaryDark : AppColorPrimitives.neutral900;
    final secondary = brightness == Brightness.dark
        ? AppColorPrimitives.textSecondaryDark
        : AppColorPrimitives.neutral600;
    final tertiary = brightness == Brightness.dark
        ? AppColorPrimitives.textTertiaryDark
        : AppColorPrimitives.neutral500;

    return base.copyWith(
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 22 / 14, fontWeight: FontWeight.w400, color: primary),
      bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w400, color: secondary),
      labelLarge: base.labelLarge?.copyWith(fontSize: 14, height: 22 / 14, fontWeight: FontWeight.w500, color: primary),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        height: 16 / 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.06 * 11,
        color: tertiary,
      ),
    );
  }

  static TextStyle overline(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall!.copyWith(letterSpacing: 0.66);
  }

  static TextStyle body(BuildContext context) => Theme.of(context).textTheme.bodyMedium!;

  static TextStyle bodyStrong(BuildContext context) => Theme.of(context).textTheme.labelLarge!;

  static TextStyle bodySm(BuildContext context) => Theme.of(context).textTheme.bodySmall!;
}
