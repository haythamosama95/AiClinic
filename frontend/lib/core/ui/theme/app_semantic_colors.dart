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
    required this.actionPrimaryHover,
    required this.actionPrimaryActive,
    required this.actionPrimaryFg,
    required this.actionSecondary,
    required this.actionSecondaryFg,
    required this.actionSubtleHover,
    required this.actionDisabledBg,
    required this.actionDanger,
    required this.actionDangerHover,
    required this.actionDangerActive,
    required this.actionDangerFg,
    required this.actionAi,
    required this.actionAiHover,
    required this.actionAiFg,
    required this.textDisabled,
    required this.statusSuccessFg,
    required this.statusDangerFg,
    required this.statusDangerBorder,
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
  final Color actionPrimaryHover;
  final Color actionPrimaryActive;
  final Color actionPrimaryFg;
  final Color actionSecondary;
  final Color actionSecondaryFg;
  final Color actionSubtleHover;
  final Color actionDisabledBg;
  final Color actionDanger;
  final Color actionDangerHover;
  final Color actionDangerActive;
  final Color actionDangerFg;
  final Color actionAi;
  final Color actionAiHover;
  final Color actionAiFg;
  final Color textDisabled;
  final Color statusSuccessFg;
  final Color statusDangerFg;
  final Color statusDangerBorder;
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
    actionPrimaryHover: AppColorPrimitives.teal700,
    actionPrimaryActive: AppColorPrimitives.teal800,
    actionPrimaryFg: AppColorPrimitives.neutral0,
    actionSecondary: AppColorPrimitives.neutral0,
    actionSecondaryFg: AppColorPrimitives.neutral900,
    actionSubtleHover: AppColorPrimitives.neutral50,
    actionDisabledBg: AppColorPrimitives.neutral100,
    actionDanger: AppColorPrimitives.red600,
    actionDangerHover: AppColorPrimitives.red700,
    actionDangerActive: AppColorPrimitives.red700,
    actionDangerFg: AppColorPrimitives.neutral0,
    actionAi: AppColorPrimitives.violet600,
    actionAiHover: AppColorPrimitives.violet700,
    actionAiFg: AppColorPrimitives.neutral0,
    textDisabled: AppColorPrimitives.neutral400,
    statusSuccessFg: AppColorPrimitives.green700,
    statusDangerFg: AppColorPrimitives.red600,
    statusDangerBorder: AppColorPrimitives.red100,
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
    actionPrimaryHover: AppColorPrimitives.teal400,
    actionPrimaryActive: AppColorPrimitives.teal300,
    actionPrimaryFg: AppColorPrimitives.neutral950,
    actionSecondary: AppColorPrimitives.surfaceRaisedDark,
    actionSecondaryFg: AppColorPrimitives.textPrimaryDark,
    actionSubtleHover: AppColorPrimitives.surfaceHoverDark,
    actionDisabledBg: AppColorPrimitives.actionDisabledBgDark,
    actionDanger: AppColorPrimitives.red500Dark,
    actionDangerHover: AppColorPrimitives.statusDangerFgDark,
    actionDangerActive: AppColorPrimitives.statusDangerFgDark,
    actionDangerFg: AppColorPrimitives.neutral950,
    actionAi: AppColorPrimitives.violet500,
    actionAiHover: AppColorPrimitives.violet700,
    actionAiFg: AppColorPrimitives.neutral950,
    textDisabled: AppColorPrimitives.textDisabledDark,
    statusSuccessFg: AppColorPrimitives.statusSuccessFgDark,
    statusDangerFg: AppColorPrimitives.statusDangerFgDark,
    statusDangerBorder: AppColorPrimitives.statusDangerBorderDark,
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
    Color? actionPrimaryHover,
    Color? actionPrimaryActive,
    Color? actionPrimaryFg,
    Color? actionSecondary,
    Color? actionSecondaryFg,
    Color? actionSubtleHover,
    Color? actionDisabledBg,
    Color? actionDanger,
    Color? actionDangerHover,
    Color? actionDangerActive,
    Color? actionDangerFg,
    Color? actionAi,
    Color? actionAiHover,
    Color? actionAiFg,
    Color? textDisabled,
    Color? statusSuccessFg,
    Color? statusDangerFg,
    Color? statusDangerBorder,
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
      actionPrimaryHover: actionPrimaryHover ?? this.actionPrimaryHover,
      actionPrimaryActive: actionPrimaryActive ?? this.actionPrimaryActive,
      actionPrimaryFg: actionPrimaryFg ?? this.actionPrimaryFg,
      actionSecondary: actionSecondary ?? this.actionSecondary,
      actionSecondaryFg: actionSecondaryFg ?? this.actionSecondaryFg,
      actionSubtleHover: actionSubtleHover ?? this.actionSubtleHover,
      actionDisabledBg: actionDisabledBg ?? this.actionDisabledBg,
      actionDanger: actionDanger ?? this.actionDanger,
      actionDangerHover: actionDangerHover ?? this.actionDangerHover,
      actionDangerActive: actionDangerActive ?? this.actionDangerActive,
      actionDangerFg: actionDangerFg ?? this.actionDangerFg,
      actionAi: actionAi ?? this.actionAi,
      actionAiHover: actionAiHover ?? this.actionAiHover,
      actionAiFg: actionAiFg ?? this.actionAiFg,
      textDisabled: textDisabled ?? this.textDisabled,
      statusSuccessFg: statusSuccessFg ?? this.statusSuccessFg,
      statusDangerFg: statusDangerFg ?? this.statusDangerFg,
      statusDangerBorder: statusDangerBorder ?? this.statusDangerBorder,
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
      actionPrimaryHover: Color.lerp(actionPrimaryHover, other.actionPrimaryHover, t)!,
      actionPrimaryActive: Color.lerp(actionPrimaryActive, other.actionPrimaryActive, t)!,
      actionPrimaryFg: Color.lerp(actionPrimaryFg, other.actionPrimaryFg, t)!,
      actionSecondary: Color.lerp(actionSecondary, other.actionSecondary, t)!,
      actionSecondaryFg: Color.lerp(actionSecondaryFg, other.actionSecondaryFg, t)!,
      actionSubtleHover: Color.lerp(actionSubtleHover, other.actionSubtleHover, t)!,
      actionDisabledBg: Color.lerp(actionDisabledBg, other.actionDisabledBg, t)!,
      actionDanger: Color.lerp(actionDanger, other.actionDanger, t)!,
      actionDangerHover: Color.lerp(actionDangerHover, other.actionDangerHover, t)!,
      actionDangerActive: Color.lerp(actionDangerActive, other.actionDangerActive, t)!,
      actionDangerFg: Color.lerp(actionDangerFg, other.actionDangerFg, t)!,
      actionAi: Color.lerp(actionAi, other.actionAi, t)!,
      actionAiHover: Color.lerp(actionAiHover, other.actionAiHover, t)!,
      actionAiFg: Color.lerp(actionAiFg, other.actionAiFg, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      statusSuccessFg: Color.lerp(statusSuccessFg, other.statusSuccessFg, t)!,
      statusDangerFg: Color.lerp(statusDangerFg, other.statusDangerFg, t)!,
      statusDangerBorder: Color.lerp(statusDangerBorder, other.statusDangerBorder, t)!,
      signalColor: Color.lerp(signalColor, other.signalColor, t)!,
      signalColorAi: Color.lerp(signalColorAi, other.signalColorAi, t)!,
    );
  }
}

extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get appColors => Theme.of(this).extension<AppSemanticColors>()!;
}
