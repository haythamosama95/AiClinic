import 'package:flutter/material.dart';

/// Compact layout density aligned with dense dashboard UIs (~12–14px body, ~20px titles).
abstract final class DensityTokens {
  /// Global font-size multiplier applied to Material [TextTheme] and forui [FTypography].
  static const double textScale = 0.875;

  /// Default interactive control height (inputs, buttons).
  static const double controlHeight = 36;

  /// Smaller control height for dense toolbars and inline actions.
  static const double controlHeightSm = 32;

  static const double controlPaddingHorizontal = 12;
  static const double controlPaddingVertical = 8;

  /// Returns [theme] with every non-null [TextStyle.fontSize] scaled by [textScale].
  static TextTheme compactTextTheme(TextTheme theme) {
    TextStyle? scale(TextStyle? style) {
      if (style == null) {
        return null;
      }
      final fontSize = style.fontSize;
      if (fontSize == null) {
        return style;
      }
      return style.copyWith(fontSize: fontSize * textScale);
    }

    return theme.copyWith(
      displayLarge: scale(theme.displayLarge),
      displayMedium: scale(theme.displayMedium),
      displaySmall: scale(theme.displaySmall),
      headlineLarge: scale(theme.headlineLarge),
      headlineMedium: scale(theme.headlineMedium),
      headlineSmall: scale(theme.headlineSmall),
      titleLarge: scale(theme.titleLarge),
      titleMedium: scale(theme.titleMedium),
      titleSmall: scale(theme.titleSmall),
      bodyLarge: scale(theme.bodyLarge),
      bodyMedium: scale(theme.bodyMedium),
      bodySmall: scale(theme.bodySmall),
      labelLarge: scale(theme.labelLarge),
      labelMedium: scale(theme.labelMedium),
      labelSmall: scale(theme.labelSmall),
    );
  }
}
