import 'package:flutter/material.dart';

/// Bundled font family names (declared in pubspec.yaml).
abstract final class AppFontFamilies {
  static const String sans = 'Inter';
  static const String display = 'Geist';
  static const String mono = 'Geist Mono';
  static const String arabic = 'IBM Plex Sans Arabic';
}

/// Describes a single typography role in the design scale.
@immutable
class TypographyRoleSpec {
  const TypographyRoleSpec({
    required this.fontSize,
    required this.lineHeight,
    required this.fontWeight,
    required this.family,
    this.letterSpacingEm = 0,
    this.useDisplayFamily = false,
    this.useMonoFamily = false,
  });

  final double fontSize;
  final double lineHeight;
  final FontWeight fontWeight;
  final String family;
  final double letterSpacingEm;
  final bool useDisplayFamily;
  final bool useMonoFamily;

  double get height => lineHeight / fontSize;

  double letterSpacingPx({bool arabic = false}) =>
      arabic ? 0 : letterSpacingEm * fontSize;

  String resolveFamily({bool arabic = false}) {
    if (arabic) return AppFontFamilies.arabic;
    if (useMonoFamily) return AppFontFamilies.mono;
    if (useDisplayFamily) return AppFontFamilies.display;
    return AppFontFamilies.sans;
  }
}

/// Canonical typography scale definitions (theme-independent).
abstract final class AppTypographyTokens {
  static const TypographyRoleSpec displayLg = TypographyRoleSpec(
    fontSize: 32,
    lineHeight: 40,
    fontWeight: FontWeight.w600,
    family: AppFontFamilies.display,
    letterSpacingEm: -0.01,
    useDisplayFamily: true,
  );

  static const TypographyRoleSpec display = TypographyRoleSpec(
    fontSize: 28,
    lineHeight: 36,
    fontWeight: FontWeight.w600,
    family: AppFontFamilies.display,
    letterSpacingEm: -0.01,
    useDisplayFamily: true,
  );

  static const TypographyRoleSpec h1 = TypographyRoleSpec(
    fontSize: 24,
    lineHeight: 32,
    fontWeight: FontWeight.w600,
    family: AppFontFamilies.display,
    letterSpacingEm: -0.01,
    useDisplayFamily: true,
  );

  static const TypographyRoleSpec h2 = TypographyRoleSpec(
    fontSize: 20,
    lineHeight: 28,
    fontWeight: FontWeight.w600,
    family: AppFontFamilies.display,
    useDisplayFamily: true,
  );

  static const TypographyRoleSpec h3 = TypographyRoleSpec(
    fontSize: 18,
    lineHeight: 26,
    fontWeight: FontWeight.w600,
    family: AppFontFamilies.display,
    useDisplayFamily: true,
  );

  static const TypographyRoleSpec title = TypographyRoleSpec(
    fontSize: 16,
    lineHeight: 24,
    fontWeight: FontWeight.w600,
    family: AppFontFamilies.sans,
  );

  static const TypographyRoleSpec bodyLg = TypographyRoleSpec(
    fontSize: 15,
    lineHeight: 24,
    fontWeight: FontWeight.w400,
    family: AppFontFamilies.sans,
  );

  static const TypographyRoleSpec body = TypographyRoleSpec(
    fontSize: 14,
    lineHeight: 22,
    fontWeight: FontWeight.w400,
    family: AppFontFamilies.sans,
  );

  static const TypographyRoleSpec bodyStrong = TypographyRoleSpec(
    fontSize: 14,
    lineHeight: 22,
    fontWeight: FontWeight.w500,
    family: AppFontFamilies.sans,
  );

  static const TypographyRoleSpec bodySm = TypographyRoleSpec(
    fontSize: 13,
    lineHeight: 20,
    fontWeight: FontWeight.w400,
    family: AppFontFamilies.sans,
  );

  static const TypographyRoleSpec caption = TypographyRoleSpec(
    fontSize: 12,
    lineHeight: 16,
    fontWeight: FontWeight.w400,
    family: AppFontFamilies.sans,
  );

  static const TypographyRoleSpec overline = TypographyRoleSpec(
    fontSize: 11,
    lineHeight: 16,
    fontWeight: FontWeight.w600,
    family: AppFontFamilies.sans,
    letterSpacingEm: 0.06,
  );

  static const TypographyRoleSpec mono = TypographyRoleSpec(
    fontSize: 13,
    lineHeight: 20,
    fontWeight: FontWeight.w400,
    family: AppFontFamilies.mono,
    useMonoFamily: true,
  );
}
