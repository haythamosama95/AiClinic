import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography_tokens.dart';

/// Resolved semantic typography styles for the active theme.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.brightness,
    required this.displayLg,
    required this.display,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.title,
    required this.bodyLg,
    required this.body,
    required this.bodyStrong,
    required this.bodySm,
    required this.caption,
    required this.overline,
    required this.mono,
    this.arabic = false,
  });

  final Brightness brightness;
  final TextStyle displayLg;
  final TextStyle display;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle title;
  final TextStyle bodyLg;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle bodySm;
  final TextStyle caption;
  final TextStyle overline;
  final TextStyle mono;
  final bool arabic;

  static AppTypography fromColors(
    AppColors colors, {
    required Brightness brightness,
    bool arabic = false,
  }) {
    TextStyle role(TypographyRoleSpec spec, {List<FontFeature>? features}) {
      return TextStyle(
        fontFamily: spec.resolveFamily(arabic: arabic),
        fontSize: spec.fontSize,
        height: spec.height,
        fontWeight: spec.fontWeight,
        letterSpacing: spec.letterSpacingPx(arabic: arabic),
        color: colors.textPrimary,
        fontFeatures: features,
      );
    }

    return AppTypography(
      brightness: brightness,
      displayLg: role(AppTypographyTokens.displayLg),
      display: role(AppTypographyTokens.display),
      h1: role(AppTypographyTokens.h1),
      h2: role(AppTypographyTokens.h2),
      h3: role(AppTypographyTokens.h3),
      title: role(AppTypographyTokens.title),
      bodyLg: role(AppTypographyTokens.bodyLg),
      body: role(AppTypographyTokens.body),
      bodyStrong: role(AppTypographyTokens.bodyStrong),
      bodySm: role(AppTypographyTokens.bodySm),
      caption: role(AppTypographyTokens.caption),
      overline: role(AppTypographyTokens.overline),
      mono: role(
        AppTypographyTokens.mono,
        features: const [FontFeature.tabularFigures()],
      ),
      arabic: arabic,
    );
  }

  static AppTypography light({bool arabic = false}) =>
      fromColors(AppColors.light, brightness: Brightness.light, arabic: arabic);

  static AppTypography dark({bool arabic = false}) =>
      fromColors(AppColors.dark, brightness: Brightness.dark, arabic: arabic);

  /// Swaps to IBM Plex Sans Arabic with zero letter-spacing when [arabic] is true.
  AppTypography forScript(bool arabic) {
    if (this.arabic == arabic) return this;
    final colors = brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    return fromColors(colors, brightness: brightness, arabic: arabic);
  }

  /// Applies tabular figures to any style (for money, counts, times).
  TextStyle tabular(TextStyle style) {
    return style.copyWith(
      fontFeatures: [
        ...?style.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
    );
  }

  @override
  AppTypography copyWith({
    Brightness? brightness,
    TextStyle? displayLg,
    TextStyle? display,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? h3,
    TextStyle? title,
    TextStyle? bodyLg,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? bodySm,
    TextStyle? caption,
    TextStyle? overline,
    TextStyle? mono,
    bool? arabic,
  }) {
    return AppTypography(
      brightness: brightness ?? this.brightness,
      displayLg: displayLg ?? this.displayLg,
      display: display ?? this.display,
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      h3: h3 ?? this.h3,
      title: title ?? this.title,
      bodyLg: bodyLg ?? this.bodyLg,
      body: body ?? this.body,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      bodySm: bodySm ?? this.bodySm,
      caption: caption ?? this.caption,
      overline: overline ?? this.overline,
      mono: mono ?? this.mono,
      arabic: arabic ?? this.arabic,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      brightness: t < 0.5 ? brightness : other.brightness,
      displayLg: TextStyle.lerp(displayLg, other.displayLg, t)!,
      display: TextStyle.lerp(display, other.display, t)!,
      h1: TextStyle.lerp(h1, other.h1, t)!,
      h2: TextStyle.lerp(h2, other.h2, t)!,
      h3: TextStyle.lerp(h3, other.h3, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      bodyLg: TextStyle.lerp(bodyLg, other.bodyLg, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      bodySm: TextStyle.lerp(bodySm, other.bodySm, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      overline: TextStyle.lerp(overline, other.overline, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      arabic: t < 0.5 ? arabic : other.arabic,
    );
  }
}
