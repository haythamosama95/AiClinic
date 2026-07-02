import 'package:flutter/material.dart';

import '../color_tokens.dart';
import '../density_tokens.dart';
import '../shape_tokens.dart';
import 'app_theme_variant.dart';
import 'clinic/clinic_color_tokens.dart';
import 'clinic/clinic_shape_tokens.dart';
import 'clinic/clinic_typography_tokens.dart';
import 'ecarely/ecarely_color_tokens.dart';
import 'ecarely/ecarely_shape_tokens.dart';
import 'ecarely/ecarely_typography_tokens.dart';
import 'med_spectra/med_spectra_color_tokens.dart';
import 'med_spectra/med_spectra_shape_tokens.dart';
import 'med_spectra/med_spectra_typography_tokens.dart';
import 'parchment/parchment_color_tokens.dart';
import 'parchment/parchment_shape_tokens.dart';
import 'parchment/parchment_typography_tokens.dart';

/// Resolves variant-specific tokens without mixing palettes.
abstract final class ThemePaletteResolver {
  static ColorTokens colors(AppThemeVariant variant, Brightness brightness) => switch (variant) {
    AppThemeVariant.clinic => ClinicColorTokens.forBrightness(brightness),
    AppThemeVariant.parchment => ParchmentColorTokens.forBrightness(brightness),
    AppThemeVariant.medSpectra => MedSpectraColorTokens.forBrightness(brightness),
    AppThemeVariant.eCarely => ECarelyColorTokens.forBrightness(brightness),
  };

  static ShapeTokens shapes(AppThemeVariant variant) => switch (variant) {
    AppThemeVariant.clinic => ClinicShapeTokens.values,
    AppThemeVariant.parchment => ParchmentShapeTokens.values,
    AppThemeVariant.medSpectra => MedSpectraShapeTokens.values,
    AppThemeVariant.eCarely => ECarelyShapeTokens.values,
  };

  static TextTheme typography(AppThemeVariant variant, {required Color foreground, required Color mutedForeground}) {
    final variantTheme = switch (variant) {
      AppThemeVariant.clinic => ClinicTypographyTokens.textTheme(
        foreground: foreground,
        mutedForeground: mutedForeground,
      ),
      AppThemeVariant.parchment => ParchmentTypographyTokens.textTheme(
        foreground: foreground,
        mutedForeground: mutedForeground,
      ),
      AppThemeVariant.medSpectra => MedSpectraTypographyTokens.textTheme(
        foreground: foreground,
        mutedForeground: mutedForeground,
      ),
      AppThemeVariant.eCarely => ECarelyTypographyTokens.textTheme(
        foreground: foreground,
        mutedForeground: mutedForeground,
      ),
    };

    return DensityTokens.compactTextTheme(variantTheme);
  }
}
