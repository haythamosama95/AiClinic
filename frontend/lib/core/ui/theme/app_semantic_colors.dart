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
    required this.surfaceMuted,
    required this.surfaceAi,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textPlaceholder,
    required this.textInverse,
    required this.textLink,
    required this.textAi,
    required this.iconDefault,
    required this.iconMuted,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderAi,
    required this.actionPrimary,
    required this.actionAi,
    required this.actionAiFg,
    required this.statusSuccessFg,
    required this.statusDangerFg,
    required this.signalColor,
    required this.signalColorAi,
  });

  final Color surfaceCanvas;
  final Color surfaceDefault;
  final Color surfaceSunken;
  final Color surfaceHover;
  final Color surfaceSelected;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color surfaceAi;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textPlaceholder;
  final Color textInverse;
  final Color textLink;
  final Color textAi;
  final Color iconDefault;
  final Color iconMuted;
  final Color borderSubtle;
  final Color borderDefault;
  final Color borderAi;
  final Color actionPrimary;
  final Color actionAi;
  final Color actionAiFg;
  final Color statusSuccessFg;
  final Color statusDangerFg;
  final Color signalColor;
  final Color signalColorAi;

  static const light = AppSemanticColors(
    surfaceCanvas: AppColorPrimitives.neutral25,
    surfaceDefault: AppColorPrimitives.neutral0,
    surfaceSunken: AppColorPrimitives.neutral50,
    surfaceHover: AppColorPrimitives.neutral50,
    surfaceSelected: AppColorPrimitives.teal50,
    surfaceRaised: AppColorPrimitives.neutral0,
    surfaceMuted: AppColorPrimitives.neutral100,
    surfaceAi: AppColorPrimitives.violet50,
    textPrimary: AppColorPrimitives.neutral900,
    textSecondary: AppColorPrimitives.neutral600,
    textTertiary: AppColorPrimitives.neutral500,
    textPlaceholder: AppColorPrimitives.neutral400,
    textInverse: AppColorPrimitives.neutral0,
    textLink: AppColorPrimitives.teal700,
    textAi: AppColorPrimitives.violet700,
    iconDefault: AppColorPrimitives.neutral600,
    iconMuted: AppColorPrimitives.neutral400,
    borderSubtle: AppColorPrimitives.neutral150,
    borderDefault: AppColorPrimitives.neutral200,
    borderAi: AppColorPrimitives.violet400,
    actionPrimary: AppColorPrimitives.teal600,
    actionAi: AppColorPrimitives.violet600,
    actionAiFg: AppColorPrimitives.neutral0,
    statusSuccessFg: AppColorPrimitives.green700,
    statusDangerFg: AppColorPrimitives.red600,
    signalColor: AppColorPrimitives.teal500,
    signalColorAi: AppColorPrimitives.violet600,
  );

  static const dark = AppSemanticColors(
    surfaceCanvas: AppColorPrimitives.neutral950,
    surfaceDefault: AppColorPrimitives.surfaceDefaultDark,
    surfaceSunken: AppColorPrimitives.surfaceSunkenDark,
    surfaceHover: AppColorPrimitives.surfaceHoverDark,
    surfaceSelected: AppColorPrimitives.surfaceSelectedDark,
    surfaceRaised: AppColorPrimitives.surfaceRaisedDark,
    surfaceMuted: AppColorPrimitives.surfaceMutedDark,
    surfaceAi: AppColorPrimitives.surfaceAiDark,
    textPrimary: AppColorPrimitives.textPrimaryDark,
    textSecondary: AppColorPrimitives.textSecondaryDark,
    textTertiary: AppColorPrimitives.textTertiaryDark,
    textPlaceholder: AppColorPrimitives.textPlaceholderDark,
    textInverse: AppColorPrimitives.neutral900,
    textLink: AppColorPrimitives.teal300,
    textAi: AppColorPrimitives.violet300,
    iconDefault: AppColorPrimitives.iconDefaultDark,
    iconMuted: AppColorPrimitives.iconMutedDark,
    borderSubtle: AppColorPrimitives.borderSubtleDark,
    borderDefault: AppColorPrimitives.borderDefaultDark,
    borderAi: AppColorPrimitives.violet400,
    actionPrimary: AppColorPrimitives.teal500,
    actionAi: AppColorPrimitives.violet500,
    actionAiFg: AppColorPrimitives.neutral950,
    statusSuccessFg: AppColorPrimitives.statusSuccessFgDark,
    statusDangerFg: AppColorPrimitives.statusDangerFgDark,
    signalColor: AppColorPrimitives.teal400,
    signalColorAi: AppColorPrimitives.violet500,
  );

  @override
  AppSemanticColors copyWith({
    Color? surfaceCanvas,
    Color? surfaceDefault,
    Color? surfaceSunken,
    Color? surfaceHover,
    Color? surfaceSelected,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? surfaceAi,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textPlaceholder,
    Color? textInverse,
    Color? textLink,
    Color? textAi,
    Color? iconDefault,
    Color? iconMuted,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderAi,
    Color? actionPrimary,
    Color? actionAi,
    Color? actionAiFg,
    Color? statusSuccessFg,
    Color? statusDangerFg,
    Color? signalColor,
    Color? signalColorAi,
  }) {
    return AppSemanticColors(
      surfaceCanvas: surfaceCanvas ?? this.surfaceCanvas,
      surfaceDefault: surfaceDefault ?? this.surfaceDefault,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceAi: surfaceAi ?? this.surfaceAi,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textPlaceholder: textPlaceholder ?? this.textPlaceholder,
      textInverse: textInverse ?? this.textInverse,
      textLink: textLink ?? this.textLink,
      textAi: textAi ?? this.textAi,
      iconDefault: iconDefault ?? this.iconDefault,
      iconMuted: iconMuted ?? this.iconMuted,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderAi: borderAi ?? this.borderAi,
      actionPrimary: actionPrimary ?? this.actionPrimary,
      actionAi: actionAi ?? this.actionAi,
      actionAiFg: actionAiFg ?? this.actionAiFg,
      statusSuccessFg: statusSuccessFg ?? this.statusSuccessFg,
      statusDangerFg: statusDangerFg ?? this.statusDangerFg,
      signalColor: signalColor ?? this.signalColor,
      signalColorAi: signalColorAi ?? this.signalColorAi,
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
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceAi: Color.lerp(surfaceAi, other.surfaceAi, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textPlaceholder: Color.lerp(textPlaceholder, other.textPlaceholder, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
      textAi: Color.lerp(textAi, other.textAi, t)!,
      iconDefault: Color.lerp(iconDefault, other.iconDefault, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderAi: Color.lerp(borderAi, other.borderAi, t)!,
      actionPrimary: Color.lerp(actionPrimary, other.actionPrimary, t)!,
      actionAi: Color.lerp(actionAi, other.actionAi, t)!,
      actionAiFg: Color.lerp(actionAiFg, other.actionAiFg, t)!,
      statusSuccessFg: Color.lerp(statusSuccessFg, other.statusSuccessFg, t)!,
      statusDangerFg: Color.lerp(statusDangerFg, other.statusDangerFg, t)!,
      signalColor: Color.lerp(signalColor, other.signalColor, t)!,
      signalColorAi: Color.lerp(signalColorAi, other.signalColorAi, t)!,
    );
  }
}

extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get appColors => Theme.of(this).extension<AppSemanticColors>()!;
}
