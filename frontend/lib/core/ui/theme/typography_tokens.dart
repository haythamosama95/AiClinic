import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography tokens derived from `--font-sans`, `--font-serif`, and `--font-mono`.
abstract final class TypographyTokens {
  /// `--font-sans: Outfit, sans-serif`.
  static TextTheme sansTextTheme(TextTheme base) => GoogleFonts.outfitTextTheme(base);

  /// `--font-serif: Merriweather, serif`.
  static TextStyle serif({double? fontSize, FontWeight? fontWeight, Color? color}) {
    return GoogleFonts.merriweather(fontSize: fontSize, fontWeight: fontWeight, color: color);
  }

  /// `--font-mono: Fira Code, monospace`.
  static TextTheme monoTextTheme(TextTheme base) => GoogleFonts.firaCodeTextTheme(base);

  /// Builds the application [TextTheme] using Outfit as the primary typeface.
  static TextTheme textTheme({required Color foreground, required Color mutedForeground}) {
    final base = ThemeData(
      brightness: Brightness.light,
    ).textTheme.apply(bodyColor: foreground, displayColor: foreground);

    final sans = sansTextTheme(base);
    return sans.copyWith(
      bodySmall: sans.bodySmall?.copyWith(color: mutedForeground),
      labelSmall: sans.labelSmall?.copyWith(color: mutedForeground),
    );
  }
}
