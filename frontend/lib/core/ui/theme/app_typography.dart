import 'package:flutter/material.dart';
<<<<<<< HEAD
import 'package:google_fonts/google_fonts.dart';
=======
>>>>>>> master

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';

/// Application text styles aligned with the design system type scale (`02-tokens` §4).
abstract final class AppTypography {
<<<<<<< HEAD
=======
  static const String sansFamily = 'Inter';
  static const String monoFamily = 'JetBrains Mono';

>>>>>>> master
  static TextTheme textTheme({required Brightness brightness}) {
    final primary = brightness == Brightness.dark ? AppColorPrimitives.textPrimaryDark : AppColorPrimitives.neutral900;
    final secondary = brightness == Brightness.dark
        ? AppColorPrimitives.textSecondaryDark
        : AppColorPrimitives.neutral600;
    final tertiary = brightness == Brightness.dark
        ? AppColorPrimitives.textTertiaryDark
        : AppColorPrimitives.neutral500;

<<<<<<< HEAD
    final sans = GoogleFonts.interTextTheme();
    final display = GoogleFonts.interTextTheme();
    final mono = GoogleFonts.jetBrainsMonoTextTheme();
=======
    final sans = ThemeData(brightness: brightness, fontFamily: sansFamily).textTheme;
    final mono = ThemeData(brightness: brightness, fontFamily: monoFamily).textTheme;
>>>>>>> master

    TextStyle style({
      required double size,
      required double lineHeight,
      FontWeight weight = FontWeight.w400,
      Color? color,
      FontStyle? fontStyle,
      double? letterSpacing,
      TextStyle? base,
    }) {
      return (base ?? sans.bodyMedium!).copyWith(
        fontSize: size,
        height: lineHeight / size,
        fontWeight: weight,
        color: color ?? primary,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
      );
    }

    return sans.copyWith(
<<<<<<< HEAD
      displayLarge: style(base: display.displayLarge, size: 32, lineHeight: 40, weight: FontWeight.w600),
      displayMedium: style(base: display.displayMedium, size: 28, lineHeight: 36, weight: FontWeight.w600),
=======
      displayLarge: style(base: sans.displayLarge, size: 32, lineHeight: 40, weight: FontWeight.w600),
      displayMedium: style(base: sans.displayMedium, size: 28, lineHeight: 36, weight: FontWeight.w600),
>>>>>>> master
      headlineLarge: style(size: 24, lineHeight: 32, weight: FontWeight.w600),
      headlineMedium: style(size: 20, lineHeight: 28, weight: FontWeight.w600),
      headlineSmall: style(size: 18, lineHeight: 26, weight: FontWeight.w600),
      titleLarge: style(size: 16, lineHeight: 24, weight: FontWeight.w600),
      titleMedium: style(size: 15, lineHeight: 24, weight: FontWeight.w400, color: secondary),
      bodyLarge: style(size: 15, lineHeight: 24, weight: FontWeight.w400, color: secondary),
      bodyMedium: style(size: 14, lineHeight: 22, weight: FontWeight.w400, color: secondary),
      bodySmall: style(size: 13, lineHeight: 20, weight: FontWeight.w400, color: secondary),
      labelLarge: style(size: 14, lineHeight: 22, weight: FontWeight.w500),
      labelMedium: style(base: mono.labelMedium, size: 13, lineHeight: 20, weight: FontWeight.w400),
<<<<<<< HEAD
      labelSmall: style(
        size: 12,
        lineHeight: 16,
        weight: FontWeight.w400,
        color: tertiary,
      ),
=======
      labelSmall: style(size: 12, lineHeight: 16, weight: FontWeight.w400, color: tertiary),
>>>>>>> master
    );
  }

  static TextStyle displayLg(BuildContext context) => Theme.of(context).textTheme.displayLarge!;

  static TextStyle display(BuildContext context) => Theme.of(context).textTheme.displayMedium!;

  static TextStyle h1(BuildContext context) => Theme.of(context).textTheme.headlineLarge!;

  static TextStyle h2(BuildContext context) => Theme.of(context).textTheme.headlineMedium!;

  static TextStyle h3(BuildContext context) => Theme.of(context).textTheme.headlineSmall!;

  static TextStyle title(BuildContext context) => Theme.of(context).textTheme.titleLarge!;

  static TextStyle bodyLg(BuildContext context) => Theme.of(context).textTheme.bodyLarge!;

  static TextStyle body(BuildContext context) => Theme.of(context).textTheme.bodyMedium!;

  static TextStyle bodySm(BuildContext context) => Theme.of(context).textTheme.bodySmall!;

  static TextStyle bodyStrong(BuildContext context) => Theme.of(context).textTheme.labelLarge!;

  static TextStyle caption(BuildContext context) => Theme.of(context).textTheme.labelSmall!;

  static TextStyle overline(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall!.copyWith(
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.06 * 11,
      color: theme.textTheme.labelSmall!.color,
    );
  }

  static TextStyle mono(BuildContext context) => Theme.of(context).textTheme.labelMedium!;

  static TextStyle forToken(BuildContext context, String token) {
    return switch (token) {
      'display-lg' => displayLg(context),
      'display' => display(context),
      'h1' => h1(context),
      'h2' => h2(context),
      'h3' => h3(context),
      'title' => title(context),
      'body-lg' => bodyLg(context),
      'body' => body(context),
      'body-sm' => bodySm(context),
      'body-strong' => bodyStrong(context),
      'caption' => caption(context),
      'overline' => overline(context),
      'mono' => mono(context),
      _ => body(context),
    };
  }
}
