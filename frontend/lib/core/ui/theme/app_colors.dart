import 'package:flutter/material.dart';

/// Semantic color tokens resolved from the web design-system primitives.
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

  // Surfaces
  final Color surfaceCanvas;
  final Color surfaceDefault;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color surfaceMuted;
  final Color surfaceHover;
  final Color surfaceSelected;
  final Color surfaceBackdrop;
  final Color surfaceAi;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textPlaceholder;
  final Color textDisabled;
  final Color textInverse;
  final Color textLink;
  final Color textAi;

  // Icons
  final Color iconDefault;
  final Color iconMuted;

  // Borders
  final Color borderSubtle;
  final Color borderDefault;
  final Color borderStrong;
  final Color borderFocus;
  final Color borderAi;

  // Actions
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

  // AI actions
  final Color actionAi;
  final Color actionAiHover;
  final Color actionAiFg;
  final Color focusRingAi;

  // Status
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

  // Signal
  final Color signalColor;
  final Color signalColorAi;

  static const AppColors light = AppColors(
    surfaceCanvas: Color(0xFFFAFBFC),
    surfaceDefault: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF4F6F9),
    surfaceMuted: Color(0xFFECEFF3),
    surfaceHover: Color(0xFFF4F6F9),
    surfaceSelected: Color(0xFFE6F7F7),
    surfaceBackdrop: Color(0x7310151C),
    surfaceAi: Color(0xFFEEEAFE),
    textPrimary: Color(0xFF1A2029),
    textSecondary: Color(0xFF55606D),
    textTertiary: Color(0xFF75828F),
    textPlaceholder: Color(0xFF9AA6B4),
    textDisabled: Color(0xFF9AA6B4),
    textInverse: Color(0xFFFFFFFF),
    textLink: Color(0xFF0A5B5F),
    textAi: Color(0xFF4632AB),
    iconDefault: Color(0xFF55606D),
    iconMuted: Color(0xFF9AA6B4),
    borderSubtle: Color(0xFFE2E7EE),
    borderDefault: Color(0xFFD5DCE5),
    borderStrong: Color(0xFFC0C9D4),
    borderFocus: Color(0xFF0E8A8F),
    borderAi: Color(0xFF7D6BEE),
    actionPrimary: Color(0xFF0B7075),
    actionPrimaryHover: Color(0xFF0A5B5F),
    actionPrimaryActive: Color(0xFF0A494C),
    actionPrimaryFg: Color(0xFFFFFFFF),
    actionSecondary: Color(0xFFFFFFFF),
    actionSecondaryFg: Color(0xFF1A2029),
    actionSubtleHover: Color(0xFFF4F6F9),
    actionDisabledBg: Color(0xFFECEFF3),
    actionDanger: Color(0xFFBC3333),
    actionDangerHover: Color(0xFF9A2828),
    actionDangerActive: Color(0xFF9A2828),
    actionDangerFg: Color(0xFFFFFFFF),
    focusRing: Color(0x730E8A8F),
    actionAi: Color(0xFF573FD1),
    actionAiHover: Color(0xFF4632AB),
    actionAiFg: Color(0xFFFFFFFF),
    focusRingAi: Color(0x736A54E6),
    statusSuccessFg: Color(0xFF0F5E34),
    statusSuccessSurface: Color(0xFFE7F6ED),
    statusSuccessBorder: Color(0xFFC6E9D2),
    statusWarningFg: Color(0xFF855009),
    statusWarningSurface: Color(0xFFFBF1DF),
    statusWarningBorder: Color(0xFFF6E0B8),
    statusDangerFg: Color(0xFF9A2828),
    statusDangerSurface: Color(0xFFFBECEC),
    statusDangerBorder: Color(0xFFF6CFCF),
    statusInfoFg: Color(0xFF164FAB),
    statusInfoSurface: Color(0xFFE8F0FE),
    statusInfoBorder: Color(0xFFC7DBFB),
    signalColor: Color(0xFF0B7075),
    signalColorAi: Color(0xFF573FD1),
  );

  static const AppColors dark = AppColors(
    surfaceCanvas: Color(0xFF0E1116),
    surfaceDefault: Color(0xFF161B22),
    surfaceRaised: Color(0xFF1C232C),
    surfaceSunken: Color(0xFF0B0E13),
    surfaceMuted: Color(0xFF222A34),
    surfaceHover: Color(0xFF20272F),
    surfaceSelected: Color(0xFF0E2B2C),
    surfaceBackdrop: Color(0x9903060A),
    surfaceAi: Color(0xFF1B1638),
    textPrimary: Color(0xFFE6EBF2),
    textSecondary: Color(0xFFA9B4C0),
    textTertiary: Color(0xFF7C8896),
    textPlaceholder: Color(0xFF5C6773),
    textDisabled: Color(0xFF4E5866),
    textInverse: Color(0xFF1A2029),
    textLink: Color(0xFF5BC4C6),
    textAi: Color(0xFF9A8BF4),
    iconDefault: Color(0xFFA9B4C0),
    iconMuted: Color(0xFF6B7684),
    borderSubtle: Color(0xFF232B35),
    borderDefault: Color(0xFF2C3542),
    borderStrong: Color(0xFF3A4553),
    borderFocus: Color(0xFF2BA7AB),
    borderAi: Color(0xFF7D6BEE),
    actionPrimary: Color(0xFF0E8A8F),
    actionPrimaryHover: Color(0xFF2BA7AB),
    actionPrimaryActive: Color(0xFF5BC4C6),
    actionPrimaryFg: Color(0xFF0E1116),
    actionSecondary: Color(0xFF1C232C),
    actionSecondaryFg: Color(0xFFE6EBF2),
    actionSubtleHover: Color(0xFF20272F),
    actionDisabledBg: Color(0xFF20272F),
    actionDanger: Color(0xFFD64545),
    actionDangerHover: Color(0xFFF08A8A),
    actionDangerActive: Color(0xFFF08A8A),
    actionDangerFg: Color(0xFF0E1116),
    focusRing: Color(0x8C2BA7AB),
    actionAi: Color(0xFF6A54E6),
    actionAiHover: Color(0xFF7D6BEE),
    actionAiFg: Color(0xFF0E1116),
    focusRingAi: Color(0x8C7D6BEE),
    statusSuccessFg: Color(0xFF5FD495),
    statusSuccessSurface: Color(0xFF0E2A1B),
    statusSuccessBorder: Color(0xFF1C4230),
    statusWarningFg: Color(0xFFE9B45A),
    statusWarningSurface: Color(0xFF2E2109),
    statusWarningBorder: Color(0xFF4A3712),
    statusDangerFg: Color(0xFFF08A8A),
    statusDangerSurface: Color(0xFF2E1414),
    statusDangerBorder: Color(0xFF4A2323),
    statusInfoFg: Color(0xFF7FB0FB),
    statusInfoSurface: Color(0xFF0F1F3A),
    statusInfoBorder: Color(0xFF1E355C),
    signalColor: Color(0xFF0E8A8F),
    signalColorAi: Color(0xFF6A54E6),
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
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      surfaceCanvas: lerpColor(surfaceCanvas, other.surfaceCanvas),
      surfaceDefault: lerpColor(surfaceDefault, other.surfaceDefault),
      surfaceRaised: lerpColor(surfaceRaised, other.surfaceRaised),
      surfaceSunken: lerpColor(surfaceSunken, other.surfaceSunken),
      surfaceMuted: lerpColor(surfaceMuted, other.surfaceMuted),
      surfaceHover: lerpColor(surfaceHover, other.surfaceHover),
      surfaceSelected: lerpColor(surfaceSelected, other.surfaceSelected),
      surfaceBackdrop: lerpColor(surfaceBackdrop, other.surfaceBackdrop),
      surfaceAi: lerpColor(surfaceAi, other.surfaceAi),
      textPrimary: lerpColor(textPrimary, other.textPrimary),
      textSecondary: lerpColor(textSecondary, other.textSecondary),
      textTertiary: lerpColor(textTertiary, other.textTertiary),
      textPlaceholder: lerpColor(textPlaceholder, other.textPlaceholder),
      textDisabled: lerpColor(textDisabled, other.textDisabled),
      textInverse: lerpColor(textInverse, other.textInverse),
      textLink: lerpColor(textLink, other.textLink),
      textAi: lerpColor(textAi, other.textAi),
      iconDefault: lerpColor(iconDefault, other.iconDefault),
      iconMuted: lerpColor(iconMuted, other.iconMuted),
      borderSubtle: lerpColor(borderSubtle, other.borderSubtle),
      borderDefault: lerpColor(borderDefault, other.borderDefault),
      borderStrong: lerpColor(borderStrong, other.borderStrong),
      borderFocus: lerpColor(borderFocus, other.borderFocus),
      borderAi: lerpColor(borderAi, other.borderAi),
      actionPrimary: lerpColor(actionPrimary, other.actionPrimary),
      actionPrimaryHover: lerpColor(
        actionPrimaryHover,
        other.actionPrimaryHover,
      ),
      actionPrimaryActive: lerpColor(
        actionPrimaryActive,
        other.actionPrimaryActive,
      ),
      actionPrimaryFg: lerpColor(actionPrimaryFg, other.actionPrimaryFg),
      actionSecondary: lerpColor(actionSecondary, other.actionSecondary),
      actionSecondaryFg: lerpColor(actionSecondaryFg, other.actionSecondaryFg),
      actionSubtleHover: lerpColor(actionSubtleHover, other.actionSubtleHover),
      actionDisabledBg: lerpColor(actionDisabledBg, other.actionDisabledBg),
      actionDanger: lerpColor(actionDanger, other.actionDanger),
      actionDangerHover: lerpColor(actionDangerHover, other.actionDangerHover),
      actionDangerActive: lerpColor(
        actionDangerActive,
        other.actionDangerActive,
      ),
      actionDangerFg: lerpColor(actionDangerFg, other.actionDangerFg),
      focusRing: lerpColor(focusRing, other.focusRing),
      actionAi: lerpColor(actionAi, other.actionAi),
      actionAiHover: lerpColor(actionAiHover, other.actionAiHover),
      actionAiFg: lerpColor(actionAiFg, other.actionAiFg),
      focusRingAi: lerpColor(focusRingAi, other.focusRingAi),
      statusSuccessFg: lerpColor(statusSuccessFg, other.statusSuccessFg),
      statusSuccessSurface: lerpColor(
        statusSuccessSurface,
        other.statusSuccessSurface,
      ),
      statusSuccessBorder: lerpColor(
        statusSuccessBorder,
        other.statusSuccessBorder,
      ),
      statusWarningFg: lerpColor(statusWarningFg, other.statusWarningFg),
      statusWarningSurface: lerpColor(
        statusWarningSurface,
        other.statusWarningSurface,
      ),
      statusWarningBorder: lerpColor(
        statusWarningBorder,
        other.statusWarningBorder,
      ),
      statusDangerFg: lerpColor(statusDangerFg, other.statusDangerFg),
      statusDangerSurface: lerpColor(
        statusDangerSurface,
        other.statusDangerSurface,
      ),
      statusDangerBorder: lerpColor(
        statusDangerBorder,
        other.statusDangerBorder,
      ),
      statusInfoFg: lerpColor(statusInfoFg, other.statusInfoFg),
      statusInfoSurface: lerpColor(statusInfoSurface, other.statusInfoSurface),
      statusInfoBorder: lerpColor(statusInfoBorder, other.statusInfoBorder),
      signalColor: lerpColor(signalColor, other.signalColor),
      signalColorAi: lerpColor(signalColorAi, other.signalColorAi),
    );
  }
}
