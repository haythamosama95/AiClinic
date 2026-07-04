import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Builds light and dark [ThemeData] from design-system semantic tokens.
abstract final class AppTheme {
  static ThemeData light() => _build(brightness: Brightness.light, semantic: AppSemanticColors.light);

  static ThemeData dark() => _build(brightness: Brightness.dark, semantic: AppSemanticColors.dark);

  static ThemeData _build({required Brightness brightness, required AppSemanticColors semantic}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: semantic.actionPrimary,
      brightness: brightness,
      surface: semantic.surfaceDefault,
      onSurface: semantic.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: semantic.surfaceCanvas,
      textTheme: AppTypography.textTheme(brightness: brightness),
      extensions: [semantic],
      dividerColor: semantic.borderSubtle,
    );
  }
}
