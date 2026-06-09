import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Clinic variant typography (`Outfit`, `Merriweather`, `Fira Code`).
abstract final class ClinicTypographyTokens {
  static TextTheme textTheme({required Color foreground, required Color mutedForeground}) {
    final base = ThemeData(
      brightness: Brightness.light,
    ).textTheme.apply(bodyColor: foreground, displayColor: foreground);

    final sans = GoogleFonts.outfitTextTheme(base);
    return sans.copyWith(
      bodySmall: sans.bodySmall?.copyWith(color: mutedForeground),
      labelSmall: sans.labelSmall?.copyWith(color: mutedForeground),
    );
  }
}
