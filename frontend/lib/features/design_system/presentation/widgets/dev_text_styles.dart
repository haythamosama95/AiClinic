import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Typography helpers for the design system dev page (web token scale).
abstract final class DevTextStyles {
  static TextStyle h1(BuildContext context) {
    final colors = context.appColors;
    return AppTypography.bodyStrong(context).copyWith(
      fontSize: 24,
      height: 32 / 24,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    );
  }

  static TextStyle h2(BuildContext context) {
    final colors = context.appColors;
    return AppTypography.bodyStrong(context).copyWith(
      fontSize: 20,
      height: 28 / 20,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    );
  }

  static TextStyle h3(BuildContext context) {
    final colors = context.appColors;
    return AppTypography.bodyStrong(context).copyWith(
      fontSize: 18,
      height: 26 / 18,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    );
  }

  static TextStyle bodyLg(BuildContext context) {
    final colors = context.appColors;
    return AppTypography.body(context).copyWith(fontSize: 15, height: 24 / 15, color: colors.textSecondary);
  }

  static TextStyle overline(BuildContext context) => AppTypography.overline(context);

  static TextStyle bodySmLink(BuildContext context) {
    final colors = context.appColors;
    return AppTypography.bodySm(context).copyWith(color: colors.textLink);
  }
}
