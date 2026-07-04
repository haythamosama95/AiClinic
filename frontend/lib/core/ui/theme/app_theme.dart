import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Builds [ThemeData] instances with design-system extensions registered.
abstract final class AppTheme {
  static ThemeData light({Locale locale = const Locale('en')}) => _build(
    brightness: Brightness.light,
    colors: AppColors.light,
    elevation: AppElevation.light,
    locale: locale,
  );

  static ThemeData dark({Locale locale = const Locale('en')}) => _build(
    brightness: Brightness.dark,
    colors: AppColors.dark,
    elevation: AppElevation.dark,
    locale: locale,
  );

  static ThemeData _build({
    required Brightness brightness,
    required AppColors colors,
    required AppElevation elevation,
    required Locale locale,
  }) {
    final typography = AppTypography.forLocale(locale);
    final textTheme = typography.toTextTheme(color: colors.textPrimary);

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.actionPrimary,
      onPrimary: colors.actionPrimaryFg,
      secondary: colors.actionAi,
      onSecondary: colors.actionAiFg,
      error: colors.actionDanger,
      onError: colors.actionDangerFg,
      surface: colors.surfaceDefault,
      onSurface: colors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.surfaceCanvas,
      textTheme: textTheme,
      extensions: [colors, elevation, typography],
      dividerColor: colors.borderSubtle,
      splashColor: colors.actionSubtleHover.withValues(alpha: 0.5),
      highlightColor: colors.actionSubtleHover.withValues(alpha: 0.3),
    );
  }
}
