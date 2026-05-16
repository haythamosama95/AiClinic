import 'package:flutter/material.dart';

/// Semantic color tokens shared across light and dark themes.
abstract final class AppColors {
  static const seed = Color(0xFF0F766E);

  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB45309);
  static const info = Color(0xFF0369A1);

  static Color successContainer(Brightness brightness) =>
      brightness == Brightness.light ? const Color(0xFFDCFCE7) : const Color(0xFF14532D);

  static Color onSuccessContainer(Brightness brightness) =>
      brightness == Brightness.light ? const Color(0xFF14532D) : const Color(0xFFDCFCE7);

  static Color warningContainer(Brightness brightness) =>
      brightness == Brightness.light ? const Color(0xFFFEF3C7) : const Color(0xFF78350F);

  static Color onWarningContainer(Brightness brightness) =>
      brightness == Brightness.light ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
}

/// Standard spacing scale for desktop layouts.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const borderRadius = 16.0;
}
