import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Med Spectra variant typography — clean sans-serif (Inter) for medical dashboards.
abstract final class MedSpectraTypographyTokens {
  static TextTheme textTheme({required Color foreground, required Color mutedForeground}) {
    final base = ThemeData(
      brightness: Brightness.light,
    ).textTheme.apply(bodyColor: foreground, displayColor: foreground);

    final inter = GoogleFonts.interTextTheme(base);

    return inter.copyWith(
      displayLarge: inter.displayLarge?.copyWith(fontWeight: FontWeight.w700),
      displayMedium: inter.displayMedium?.copyWith(fontWeight: FontWeight.w700),
      displaySmall: inter.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineLarge: inter.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: inter.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineSmall: inter.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: inter.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: inter.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: inter.bodySmall?.copyWith(color: mutedForeground),
      labelSmall: inter.labelSmall?.copyWith(color: mutedForeground, fontWeight: FontWeight.w500),
    );
  }
}
