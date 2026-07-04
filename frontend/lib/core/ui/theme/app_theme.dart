import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/theme/app_typography_tokens.dart';

/// Builds [ThemeData] for light and dark modes from semantic tokens.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final typography = AppTypography.fromColors(colors, brightness: brightness);

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
      outline: colors.borderDefault,
      outlineVariant: colors.borderSubtle,
      surfaceContainerHighest: colors.surfaceMuted,
      onSurfaceVariant: colors.textSecondary,
      tertiary: colors.actionAi,
      onTertiary: colors.actionAiFg,
      shadow: colors.borderSubtle,
      scrim: colors.surfaceBackdrop,
    );

    final textTheme = TextTheme(
      displayLarge: typography.displayLg,
      displayMedium: typography.display,
      displaySmall: typography.h1,
      headlineLarge: typography.h1,
      headlineMedium: typography.h2,
      headlineSmall: typography.h3,
      titleLarge: typography.title,
      titleMedium: typography.title,
      titleSmall: typography.bodyStrong,
      bodyLarge: typography.bodyLg,
      bodyMedium: typography.body,
      bodySmall: typography.bodySm,
      labelLarge: typography.bodyStrong,
      labelMedium: typography.caption,
      labelSmall: typography.overline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.surfaceCanvas,
      fontFamily: AppTypographyTokens.body.family,
      colorScheme: colorScheme,
      textTheme: textTheme,
      extensions: [colors, typography],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surfaceDefault,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      splashFactory: InkSplash.splashFactory,
    );
  }
}
