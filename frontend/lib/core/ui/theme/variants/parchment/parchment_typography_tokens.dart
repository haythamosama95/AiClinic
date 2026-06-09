import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Parchment variant typography (`Outfit` body, `ui-serif` display/headline, IBM Plex Mono labels).
abstract final class ParchmentTypographyTokens {
  static const _serifFamily = 'ui-serif';
  static const _serifFallback = <String>['Merriweather', 'Georgia', 'serif'];

  static TextTheme textTheme({required Color foreground, required Color mutedForeground}) {
    final base = ThemeData(
      brightness: Brightness.light,
    ).textTheme.apply(bodyColor: foreground, displayColor: foreground);

    final outfit = GoogleFonts.outfitTextTheme(base);
    final mono = GoogleFonts.ibmPlexMonoTextTheme(base);

    TextStyle? withSerif(TextStyle? style) =>
        style?.copyWith(fontFamily: _serifFamily, fontFamilyFallback: _serifFallback);

    return outfit.copyWith(
      displayLarge: withSerif(outfit.displayLarge),
      displayMedium: withSerif(outfit.displayMedium),
      displaySmall: withSerif(outfit.displaySmall),
      headlineLarge: withSerif(outfit.headlineLarge),
      headlineMedium: withSerif(outfit.headlineMedium),
      headlineSmall: withSerif(outfit.headlineSmall),
      bodySmall: outfit.bodySmall?.copyWith(color: mutedForeground),
      labelSmall: mono.labelSmall?.copyWith(color: mutedForeground),
    );
  }
}
