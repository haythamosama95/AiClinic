import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Clinic variant typography (`Outfit` body, `Merriweather` display/headline, `Fira Code` labels).
abstract final class ClinicTypographyTokens {
  static TextTheme textTheme({required Color foreground, required Color mutedForeground}) {
    final base = ThemeData(
      brightness: Brightness.light,
    ).textTheme.apply(bodyColor: foreground, displayColor: foreground);

    final outfit = GoogleFonts.outfitTextTheme(base);
    final serif = GoogleFonts.merriweatherTextTheme(base);
    final mono = GoogleFonts.firaCodeTextTheme(base);

    return outfit.copyWith(
      displayLarge: serif.displayLarge,
      displayMedium: serif.displayMedium,
      displaySmall: serif.displaySmall,
      headlineLarge: serif.headlineLarge,
      headlineMedium: serif.headlineMedium,
      headlineSmall: serif.headlineSmall,
      bodySmall: outfit.bodySmall?.copyWith(color: mutedForeground),
      labelSmall: mono.labelSmall?.copyWith(color: mutedForeground),
    );
  }
}
