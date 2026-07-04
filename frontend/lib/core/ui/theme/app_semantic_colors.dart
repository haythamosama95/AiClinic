import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';

/// Semantic color tokens consumed by application components (`02-tokens` §3).
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.surfaceCanvas,
    required this.surfaceDefault,
    required this.surfaceSunken,
    required this.surfaceHover,
    required this.surfaceSelected,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textPlaceholder,
    required this.textInverse,
    required this.textLink,
    required this.iconDefault,
    required this.iconMuted,
    required this.borderSubtle,
    required this.borderDefault,
    required this.actionPrimary,
    required this.statusDangerFg,
    required this.signalColor,
  });

  final Color surfaceCanvas;
  final Color surfaceDefault;
  final Color surfaceSunken;
  final Color surfaceHover;
  final Color surfaceSelected;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textPlaceholder;
  final Color textInverse;
  final Color textLink;
  final Color iconDefault;
  final Color iconMuted;
  final Color borderSubtle;
  final Color borderDefault;
  final Color actionPrimary;
  final Color statusDangerFg;
  final Color signalColor;

  static const light = AppSemanticColors(
    surfaceCanvas: AppColorPrimitives.neutral25,
    surfaceDefault: AppColorPrimitives.neutral0,
    surfaceSunken: AppColorPrimitives.neutral50,
    surfaceHover: AppColorPrimitives.neutral50,
    surfaceSelected: AppColorPrimitives.teal50,
    surfaceRaised: AppColorPrimitives.neutral0,
    textPrimary: AppColorPrimitives.neutral900,
    textSecondary: AppColorPrimitives.neutral600,
    textTertiary: AppColorPrimitives.neutral500,
    textPlaceholder: AppColorPrimitives.neutral400,
    textInverse: AppColorPrimitives.neutral0,
    textLink: AppColorPrimitives.teal700,
    iconDefault: AppColorPrimitives.neutral600,
    iconMuted: AppColorPrimitives.neutral400,
    borderSubtle: AppColorPrimitives.neutral150,
    borderDefault: AppColorPrimitives.neutral200,
    actionPrimary: AppColorPrimitives.teal600,
    statusDangerFg: AppColorPrimitives.red600,
    signalColor: AppColorPrimitives.teal500,
  );

  static const dark = AppSemanticColors(
    surfaceCanvas: AppColorPrimitives.neutral950,
    surfaceDefault: AppColorPrimitives.surfaceDefaultDark,
    surfaceSunken: AppColorPrimitives.surfaceSunkenDark,
    surfaceHover: AppColorPrimitives.surfaceHoverDark,
    surfaceSelected: AppColorPrimitives.surfaceSelectedDark,
    surfaceRaised: Color(0xFF1C232C),
    textPrimary: AppColorPrimitives.textPrimaryDark,
    textSecondary: AppColorPrimitives.textSecondaryDark,
    textTertiary: AppColorPrimitives.textTertiaryDark,
    textPlaceholder: AppColorPrimitives.textPlaceholderDark,
    textInverse: AppColorPrimitives.neutral900,
    textLink: AppColorPrimitives.teal300,
    iconDefault: AppColorPrimitives.iconDefaultDark,
    iconMuted: AppColorPrimitives.iconMutedDark,
    borderSubtle: AppColorPrimitives.borderSubtleDark,
    borderDefault: AppColorPrimitives.borderDefaultDark,
    actionPrimary: AppColorPrimitives.teal500,
    statusDangerFg: Color(0xFFF08A8A),
    signalColor: AppColorPrimitives.teal400,
  );

  @override
  AppSemanticColors copyWith({
    Color? surfaceCanvas,
    Color? surfaceDefault,
    Color? surfaceSunken,
    Color? surfaceHover,
    Color? surfaceSelected,
    Color? surfaceRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textPlaceholder,
    Color? textInverse,
    Color? textLink,
    Color? iconDefault,
    Color? iconMuted,
    Color? borderSubtle,
    Color? borderDefault,
    Color? actionPrimary,
    Color? statusDangerFg,
    Color? signalColor,
  }) {
    return AppSemanticColors(
      surfaceCanvas: surfaceCanvas ?? this.surfaceCanvas,
      surfaceDefault: surfaceDefault ?? this.surfaceDefault,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textPlaceholder: textPlaceholder ?? this.textPlaceholder,
      textInverse: textInverse ?? this.textInverse,
      textLink: textLink ?? this.textLink,
      iconDefault: iconDefault ?? this.iconDefault,
      iconMuted: iconMuted ?? this.iconMuted,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      actionPrimary: actionPrimary ?? this.actionPrimary,
      statusDangerFg: statusDangerFg ?? this.statusDangerFg,
      signalColor: signalColor ?? this.signalColor,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other is! AppSemanticColors) {
      return this;
    }

    return AppSemanticColors(
      surfaceCanvas: Color.lerp(surfaceCanvas, other.surfaceCanvas, t)!,
      surfaceDefault: Color.lerp(surfaceDefault, other.surfaceDefault, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textPlaceholder: Color.lerp(textPlaceholder, other.textPlaceholder, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
      iconDefault: Color.lerp(iconDefault, other.iconDefault, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      actionPrimary: Color.lerp(actionPrimary, other.actionPrimary, t)!,
      statusDangerFg: Color.lerp(statusDangerFg, other.statusDangerFg, t)!,
      signalColor: Color.lerp(signalColor, other.signalColor, t)!,
    );
  }
}

extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get appColors => Theme.of(this).extension<AppSemanticColors>()!;
}
