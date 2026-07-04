import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/tokens/color_primitives.dart';

/// Semantic color tokens — the layer consumed by components.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surfaceCanvas,
    required this.surfaceDefault,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.surfaceMuted,
    required this.surfaceHover,
    required this.surfaceSelected,
    required this.surfaceBackdrop,
    required this.surfaceAi,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textPlaceholder,
    required this.textDisabled,
    required this.textInverse,
    required this.textLink,
    required this.textAi,
    required this.iconDefault,
    required this.iconMuted,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.borderFocus,
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
    required this.focusRing,
    required this.actionAi,
    required this.actionAiHover,
    required this.actionAiFg,
    required this.focusRingAi,
    required this.statusSuccessFg,
    required this.statusSuccessSurface,
    required this.statusSuccessBorder,
    required this.statusWarningFg,
    required this.statusWarningSurface,
    required this.statusWarningBorder,
    required this.statusDangerFg,
    required this.statusDangerSurface,
    required this.statusDangerBorder,
    required this.statusInfoFg,
    required this.statusInfoSurface,
    required this.statusInfoBorder,
    required this.signalColor,
    required this.signalColorAi,
  });

  final Color surfaceCanvas;
  final Color surfaceDefault;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color surfaceMuted;
  final Color surfaceHover;
  final Color surfaceSelected;
  final Color surfaceBackdrop;
  final Color surfaceAi;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textPlaceholder;
  final Color textDisabled;
  final Color textInverse;
  final Color textLink;
  final Color textAi;
  final Color iconDefault;
  final Color iconMuted;
  final Color borderSubtle;
  final Color borderDefault;
  final Color borderStrong;
  final Color borderFocus;
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
  final Color focusRing;
  final Color actionAi;
  final Color actionAiHover;
  final Color actionAiFg;
  final Color focusRingAi;
  final Color statusSuccessFg;
  final Color statusSuccessSurface;
  final Color statusSuccessBorder;
  final Color statusWarningFg;
  final Color statusWarningSurface;
  final Color statusWarningBorder;
  final Color statusDangerFg;
  final Color statusDangerSurface;
  final Color statusDangerBorder;
  final Color statusInfoFg;
  final Color statusInfoSurface;
  final Color statusInfoBorder;
  final Color signalColor;
  final Color signalColorAi;

  static final AppColors light = AppColors(
    surfaceCanvas: AppColorPrimitives.neutral25,
    surfaceDefault: AppColorPrimitives.neutral0,
    surfaceRaised: AppColorPrimitives.neutral0,
    surfaceSunken: AppColorPrimitives.neutral50,
    surfaceMuted: AppColorPrimitives.neutral100,
    surfaceHover: AppColorPrimitives.neutral50,
    surfaceSelected: AppColorPrimitives.teal50,
    surfaceBackdrop: AppColorPrimitives.rgba(16, 21, 28, 0.45),
    surfaceAi: AppColorPrimitives.violet50,
    textPrimary: AppColorPrimitives.neutral900,
    textSecondary: AppColorPrimitives.neutral600,
    textTertiary: AppColorPrimitives.neutral500,
    textPlaceholder: AppColorPrimitives.neutral400,
    textDisabled: AppColorPrimitives.neutral400,
    textInverse: AppColorPrimitives.neutral0,
    textLink: AppColorPrimitives.teal700,
    textAi: AppColorPrimitives.violet700,
    iconDefault: AppColorPrimitives.neutral600,
    iconMuted: AppColorPrimitives.neutral400,
    borderSubtle: AppColorPrimitives.neutral150,
    borderDefault: AppColorPrimitives.neutral200,
    borderStrong: AppColorPrimitives.neutral300,
    borderFocus: AppColorPrimitives.teal500,
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
    focusRing: AppColorPrimitives.rgba(14, 138, 143, 0.45),
    actionAi: AppColorPrimitives.violet600,
    actionAiHover: AppColorPrimitives.violet700,
    actionAiFg: AppColorPrimitives.neutral0,
    focusRingAi: AppColorPrimitives.rgba(106, 84, 230, 0.45),
    statusSuccessFg: AppColorPrimitives.green700,
    statusSuccessSurface: AppColorPrimitives.green50,
    statusSuccessBorder: AppColorPrimitives.green100,
    statusWarningFg: AppColorPrimitives.amber700,
    statusWarningSurface: AppColorPrimitives.amber50,
    statusWarningBorder: AppColorPrimitives.amber100,
    statusDangerFg: AppColorPrimitives.red700,
    statusDangerSurface: AppColorPrimitives.red50,
    statusDangerBorder: AppColorPrimitives.red100,
    statusInfoFg: AppColorPrimitives.blue700,
    statusInfoSurface: AppColorPrimitives.blue50,
    statusInfoBorder: AppColorPrimitives.blue100,
    signalColor: AppColorPrimitives.teal600,
    signalColorAi: AppColorPrimitives.violet600,
  );

  static final AppColors dark = AppColors(
    surfaceCanvas: AppColorPrimitives.neutral950,
    surfaceDefault: AppColorPrimitives.darkSurfaceDefault,
    surfaceRaised: AppColorPrimitives.darkSurfaceRaised,
    surfaceSunken: AppColorPrimitives.darkSurfaceSunken,
    surfaceMuted: AppColorPrimitives.darkSurfaceMuted,
    surfaceHover: AppColorPrimitives.darkSurfaceHover,
    surfaceSelected: AppColorPrimitives.darkSurfaceSelected,
    surfaceBackdrop: AppColorPrimitives.rgba(3, 6, 10, 0.60),
    surfaceAi: AppColorPrimitives.darkSurfaceAi,
    textPrimary: AppColorPrimitives.darkTextPrimary,
    textSecondary: AppColorPrimitives.darkTextSecondary,
    textTertiary: AppColorPrimitives.darkTextTertiary,
    textPlaceholder: AppColorPrimitives.darkTextPlaceholder,
    textDisabled: AppColorPrimitives.darkTextDisabled,
    textInverse: AppColorPrimitives.neutral900,
    textLink: AppColorPrimitives.teal300,
    textAi: AppColorPrimitives.violet300,
    iconDefault: AppColorPrimitives.darkIconDefault,
    iconMuted: AppColorPrimitives.darkIconMuted,
    borderSubtle: AppColorPrimitives.darkBorderSubtle,
    borderDefault: AppColorPrimitives.darkBorderDefault,
    borderStrong: AppColorPrimitives.darkBorderStrong,
    borderFocus: AppColorPrimitives.teal400,
    borderAi: AppColorPrimitives.violet400,
    actionPrimary: AppColorPrimitives.teal500,
    actionPrimaryHover: AppColorPrimitives.teal400,
    actionPrimaryActive: AppColorPrimitives.teal300,
    actionPrimaryFg: AppColorPrimitives.neutral950,
    actionSecondary: AppColorPrimitives.darkSurfaceRaised,
    actionSecondaryFg: AppColorPrimitives.darkTextPrimary,
    actionSubtleHover: AppColorPrimitives.darkSurfaceHover,
    actionDisabledBg: AppColorPrimitives.darkSurfaceHover,
    actionDanger: AppColorPrimitives.red500,
    actionDangerHover: AppColorPrimitives.darkActionDangerHover,
    actionDangerActive: AppColorPrimitives.darkActionDangerActive,
    actionDangerFg: AppColorPrimitives.neutral950,
    focusRing: AppColorPrimitives.rgba(43, 167, 171, 0.55),
    actionAi: AppColorPrimitives.violet500,
    actionAiHover: AppColorPrimitives.violet400,
    actionAiFg: AppColorPrimitives.neutral950,
    focusRingAi: AppColorPrimitives.rgba(125, 107, 238, 0.55),
    statusSuccessFg: AppColorPrimitives.darkStatusSuccessFg,
    statusSuccessSurface: AppColorPrimitives.darkStatusSuccessSurface,
    statusSuccessBorder: AppColorPrimitives.darkStatusSuccessBorder,
    statusWarningFg: AppColorPrimitives.darkStatusWarningFg,
    statusWarningSurface: AppColorPrimitives.darkStatusWarningSurface,
    statusWarningBorder: AppColorPrimitives.darkStatusWarningBorder,
    statusDangerFg: AppColorPrimitives.darkStatusDangerFg,
    statusDangerSurface: AppColorPrimitives.darkStatusDangerSurface,
    statusDangerBorder: AppColorPrimitives.darkStatusDangerBorder,
    statusInfoFg: AppColorPrimitives.darkStatusInfoFg,
    statusInfoSurface: AppColorPrimitives.darkStatusInfoSurface,
    statusInfoBorder: AppColorPrimitives.darkStatusInfoBorder,
    signalColor: AppColorPrimitives.teal500,
    signalColorAi: AppColorPrimitives.violet500,
  );

  @override
  AppColors copyWith({
    Color? surfaceCanvas,
    Color? surfaceDefault,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? surfaceMuted,
    Color? surfaceHover,
    Color? surfaceSelected,
    Color? surfaceBackdrop,
    Color? surfaceAi,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textPlaceholder,
    Color? textDisabled,
    Color? textInverse,
    Color? textLink,
    Color? textAi,
    Color? iconDefault,
    Color? iconMuted,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
    Color? borderFocus,
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
    Color? focusRing,
    Color? actionAi,
    Color? actionAiHover,
    Color? actionAiFg,
    Color? focusRingAi,
    Color? statusSuccessFg,
    Color? statusSuccessSurface,
    Color? statusSuccessBorder,
    Color? statusWarningFg,
    Color? statusWarningSurface,
    Color? statusWarningBorder,
    Color? statusDangerFg,
    Color? statusDangerSurface,
    Color? statusDangerBorder,
    Color? statusInfoFg,
    Color? statusInfoSurface,
    Color? statusInfoBorder,
    Color? signalColor,
    Color? signalColorAi,
  }) {
    return AppColors(
      surfaceCanvas: surfaceCanvas ?? this.surfaceCanvas,
      surfaceDefault: surfaceDefault ?? this.surfaceDefault,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      surfaceBackdrop: surfaceBackdrop ?? this.surfaceBackdrop,
      surfaceAi: surfaceAi ?? this.surfaceAi,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textPlaceholder: textPlaceholder ?? this.textPlaceholder,
      textDisabled: textDisabled ?? this.textDisabled,
      textInverse: textInverse ?? this.textInverse,
      textLink: textLink ?? this.textLink,
      textAi: textAi ?? this.textAi,
      iconDefault: iconDefault ?? this.iconDefault,
      iconMuted: iconMuted ?? this.iconMuted,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
      borderFocus: borderFocus ?? this.borderFocus,
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
      focusRing: focusRing ?? this.focusRing,
      actionAi: actionAi ?? this.actionAi,
      actionAiHover: actionAiHover ?? this.actionAiHover,
      actionAiFg: actionAiFg ?? this.actionAiFg,
      focusRingAi: focusRingAi ?? this.focusRingAi,
      statusSuccessFg: statusSuccessFg ?? this.statusSuccessFg,
      statusSuccessSurface: statusSuccessSurface ?? this.statusSuccessSurface,
      statusSuccessBorder: statusSuccessBorder ?? this.statusSuccessBorder,
      statusWarningFg: statusWarningFg ?? this.statusWarningFg,
      statusWarningSurface: statusWarningSurface ?? this.statusWarningSurface,
      statusWarningBorder: statusWarningBorder ?? this.statusWarningBorder,
      statusDangerFg: statusDangerFg ?? this.statusDangerFg,
      statusDangerSurface: statusDangerSurface ?? this.statusDangerSurface,
      statusDangerBorder: statusDangerBorder ?? this.statusDangerBorder,
      statusInfoFg: statusInfoFg ?? this.statusInfoFg,
      statusInfoSurface: statusInfoSurface ?? this.statusInfoSurface,
      statusInfoBorder: statusInfoBorder ?? this.statusInfoBorder,
      signalColor: signalColor ?? this.signalColor,
      signalColorAi: signalColorAi ?? this.signalColorAi,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surfaceCanvas: Color.lerp(surfaceCanvas, other.surfaceCanvas, t)!,
      surfaceDefault: Color.lerp(surfaceDefault, other.surfaceDefault, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      surfaceBackdrop: Color.lerp(surfaceBackdrop, other.surfaceBackdrop, t)!,
      surfaceAi: Color.lerp(surfaceAi, other.surfaceAi, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textPlaceholder: Color.lerp(textPlaceholder, other.textPlaceholder, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
      textAi: Color.lerp(textAi, other.textAi, t)!,
      iconDefault: Color.lerp(iconDefault, other.iconDefault, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      borderAi: Color.lerp(borderAi, other.borderAi, t)!,
      actionPrimary: Color.lerp(actionPrimary, other.actionPrimary, t)!,
      actionPrimaryHover: Color.lerp(
        actionPrimaryHover,
        other.actionPrimaryHover,
        t,
      )!,
      actionPrimaryActive: Color.lerp(
        actionPrimaryActive,
        other.actionPrimaryActive,
        t,
      )!,
      actionPrimaryFg: Color.lerp(actionPrimaryFg, other.actionPrimaryFg, t)!,
      actionSecondary: Color.lerp(actionSecondary, other.actionSecondary, t)!,
      actionSecondaryFg: Color.lerp(
        actionSecondaryFg,
        other.actionSecondaryFg,
        t,
      )!,
      actionSubtleHover: Color.lerp(
        actionSubtleHover,
        other.actionSubtleHover,
        t,
      )!,
      actionDisabledBg: Color.lerp(
        actionDisabledBg,
        other.actionDisabledBg,
        t,
      )!,
      actionDanger: Color.lerp(actionDanger, other.actionDanger, t)!,
      actionDangerHover: Color.lerp(
        actionDangerHover,
        other.actionDangerHover,
        t,
      )!,
      actionDangerActive: Color.lerp(
        actionDangerActive,
        other.actionDangerActive,
        t,
      )!,
      actionDangerFg: Color.lerp(actionDangerFg, other.actionDangerFg, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      actionAi: Color.lerp(actionAi, other.actionAi, t)!,
      actionAiHover: Color.lerp(actionAiHover, other.actionAiHover, t)!,
      actionAiFg: Color.lerp(actionAiFg, other.actionAiFg, t)!,
      focusRingAi: Color.lerp(focusRingAi, other.focusRingAi, t)!,
      statusSuccessFg: Color.lerp(statusSuccessFg, other.statusSuccessFg, t)!,
      statusSuccessSurface: Color.lerp(
        statusSuccessSurface,
        other.statusSuccessSurface,
        t,
      )!,
      statusSuccessBorder: Color.lerp(
        statusSuccessBorder,
        other.statusSuccessBorder,
        t,
      )!,
      statusWarningFg: Color.lerp(statusWarningFg, other.statusWarningFg, t)!,
      statusWarningSurface: Color.lerp(
        statusWarningSurface,
        other.statusWarningSurface,
        t,
      )!,
      statusWarningBorder: Color.lerp(
        statusWarningBorder,
        other.statusWarningBorder,
        t,
      )!,
      statusDangerFg: Color.lerp(statusDangerFg, other.statusDangerFg, t)!,
      statusDangerSurface: Color.lerp(
        statusDangerSurface,
        other.statusDangerSurface,
        t,
      )!,
      statusDangerBorder: Color.lerp(
        statusDangerBorder,
        other.statusDangerBorder,
        t,
      )!,
      statusInfoFg: Color.lerp(statusInfoFg, other.statusInfoFg, t)!,
      statusInfoSurface: Color.lerp(
        statusInfoSurface,
        other.statusInfoSurface,
        t,
      )!,
      statusInfoBorder: Color.lerp(
        statusInfoBorder,
        other.statusInfoBorder,
        t,
      )!,
      signalColor: Color.lerp(signalColor, other.signalColor, t)!,
      signalColorAi: Color.lerp(signalColorAi, other.signalColorAi, t)!,
    );
  }
}
