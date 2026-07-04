import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Shared size tokens for text-based input fields.
enum AppFieldSize {
  /// 32 logical pixels tall.
  sm,

  /// 36 logical pixels tall (default).
  md,

  /// 44 logical pixels tall.
  lg,
}

/// Resolved metrics for an [AppFieldSize].
extension AppFieldSizeMetrics on AppFieldSize {
  /// Fixed field height matching the web `input-styles` scale.
  double get height => switch (this) {
    AppFieldSize.sm => AppSpacing.s8,
    AppFieldSize.md => AppSpacing.s8 + AppSpacing.s1,
    AppFieldSize.lg => AppSpacing.s10 + AppSpacing.s1,
  };

  /// Horizontal padding inside the field frame.
  EdgeInsetsDirectional get padding => switch (this) {
    AppFieldSize.sm => const EdgeInsetsDirectional.symmetric(
      horizontal: AppSpacing.s3,
    ),
    AppFieldSize.md => const EdgeInsetsDirectional.symmetric(
      horizontal: AppSpacing.s3,
    ),
    AppFieldSize.lg => const EdgeInsetsDirectional.symmetric(
      horizontal: AppSpacing.s4,
    ),
  };

  /// Typography role for field text and bare inputs.
  TextStyle textStyle(BuildContext context) {
    final typography = context.typography;
    return switch (this) {
      AppFieldSize.sm => typography.bodySm,
      AppFieldSize.md => typography.body,
      AppFieldSize.lg => typography.bodyLg,
    };
  }

  /// Typography role for prefix/suffix affixes.
  TextStyle affixStyle(BuildContext context) {
    return context.typography.tabular(
      textStyle(context).copyWith(color: context.colors.textTertiary),
    );
  }
}
