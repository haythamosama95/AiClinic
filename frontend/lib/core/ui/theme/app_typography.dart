import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale matching the web design-system type tokens.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
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
  });

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

  /// Builds typography for [locale]. Arabic uses IBM Plex Sans Arabic for all scales.
  factory AppTypography.forLocale(Locale locale) {
    final isArabic = locale.languageCode == 'ar';

    final displayFamily = isArabic
        ? GoogleFonts.ibmPlexSansArabic
        : _displayFont;
    final bodyFamily = isArabic
        ? GoogleFonts.ibmPlexSansArabic
        : GoogleFonts.inter;
    final monoFamily = GoogleFonts.jetBrainsMono;

    TextStyle displayStyle({
      required double size,
      required double height,
      FontWeight weight = FontWeight.w600,
      double? letterSpacing,
    }) {
      return displayFamily(
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: isArabic ? 0 : letterSpacing,
      );
    }

    TextStyle bodyStyle({
      required double size,
      required double height,
      FontWeight weight = FontWeight.w400,
      double? letterSpacing,
    }) {
      return bodyFamily(
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: isArabic ? 0 : letterSpacing,
      );
    }

    return AppTypography(
      displayLg: displayStyle(size: 32, height: 40, letterSpacing: -0.32),
      display: displayStyle(size: 28, height: 36, letterSpacing: -0.28),
      h1: displayStyle(size: 24, height: 32, letterSpacing: -0.24),
      h2: displayStyle(size: 20, height: 28),
      h3: displayStyle(size: 18, height: 26),
      title: bodyStyle(size: 16, height: 24, weight: FontWeight.w600),
      bodyLg: bodyStyle(size: 15, height: 24),
      body: bodyStyle(size: 14, height: 22),
      bodyStrong: bodyStyle(size: 14, height: 22, weight: FontWeight.w500),
      bodySm: bodyStyle(size: 13, height: 20),
      caption: bodyStyle(size: 12, height: 16),
      overline: bodyStyle(
        size: 11,
        height: 16,
        weight: FontWeight.w600,
        letterSpacing: isArabic ? 0 : 0.66,
      ).copyWith(textBaseline: TextBaseline.alphabetic),
      mono: monoFamily(
        fontSize: 13,
        height: 20 / 13,
        fontWeight: FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// Geist is not bundled in google_fonts; Inter is the approved fallback.
  static TextStyle Function({
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    Color? color,
  })
  get _displayFont => GoogleFonts.inter;

  TextTheme toTextTheme({Color? color}) {
    TextStyle withColor(TextStyle style) =>
        color == null ? style : style.copyWith(color: color);
    return TextTheme(
      displayLarge: withColor(displayLg),
      displayMedium: withColor(display),
      displaySmall: withColor(h1),
      headlineLarge: withColor(h1),
      headlineMedium: withColor(h2),
      headlineSmall: withColor(h3),
      titleLarge: withColor(title),
      titleMedium: withColor(bodyStrong),
      titleSmall: withColor(bodySm),
      bodyLarge: withColor(bodyLg),
      bodyMedium: withColor(body),
      bodySmall: withColor(caption),
      labelLarge: withColor(bodyStrong),
      labelMedium: withColor(bodySm),
      labelSmall: withColor(caption),
    );
  }

  @override
  AppTypography copyWith({
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
  }) {
    return AppTypography(
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
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    TextStyle lerpStyle(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTypography(
      displayLg: lerpStyle(displayLg, other.displayLg),
      display: lerpStyle(display, other.display),
      h1: lerpStyle(h1, other.h1),
      h2: lerpStyle(h2, other.h2),
      h3: lerpStyle(h3, other.h3),
      title: lerpStyle(title, other.title),
      bodyLg: lerpStyle(bodyLg, other.bodyLg),
      body: lerpStyle(body, other.body),
      bodyStrong: lerpStyle(bodyStrong, other.bodyStrong),
      bodySm: lerpStyle(bodySm, other.bodySm),
      caption: lerpStyle(caption, other.caption),
      overline: lerpStyle(overline, other.overline),
      mono: lerpStyle(mono, other.mono),
    );
  }
}
