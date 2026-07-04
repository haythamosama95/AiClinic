import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Shared input size tokens matching the web `inputSizeClasses`.
enum AppInputSize { sm, md, lg }

/// Shared decoration and typography helpers for text inputs and affixed fields.
abstract final class AppInputStyles {
  static double height(AppInputSize size) => switch (size) {
    AppInputSize.sm => 32,
    AppInputSize.md => 36,
    AppInputSize.lg => 44,
  };

  static EdgeInsets padding(AppInputSize size) => switch (size) {
    AppInputSize.sm => const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
    AppInputSize.md => const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
    AppInputSize.lg => const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
  };

  static TextStyle textStyle(BuildContext context, AppInputSize size) {
    final typography = context.typography;
    return switch (size) {
      AppInputSize.sm => typography.bodySm.copyWith(
        color: context.colors.textPrimary,
      ),
      AppInputSize.md => typography.body.copyWith(
        color: context.colors.textPrimary,
      ),
      AppInputSize.lg => typography.bodyLg.copyWith(
        color: context.colors.textPrimary,
      ),
    };
  }

  static TextStyle affixTextStyle(BuildContext context, AppInputSize size) {
    final typography = context.typography;
    final color = context.colors.textTertiary;
    return switch (size) {
      AppInputSize.sm => typography.bodySm.copyWith(color: color),
      AppInputSize.md => typography.body.copyWith(color: color),
      AppInputSize.lg => typography.bodyLg.copyWith(color: color),
    };
  }

  /// Standalone input surface (text field, select trigger).
  static BoxDecoration decoration(
    BuildContext context, {
    AppInputSize size = AppInputSize.md,
    bool invalid = false,
    bool disabled = false,
    bool readOnly = false,
    bool focused = false,
  }) {
    final colors = context.colors;
    final borderColor = invalid
        ? colors.statusDangerBorder
        : focused
        ? colors.borderFocus
        : colors.borderDefault;
    final background = disabled
        ? colors.actionDisabledBg
        : readOnly
        ? colors.surfaceSunken
        : colors.surfaceDefault;

    return BoxDecoration(
      color: background,
      borderRadius: AppRadius.mdAll,
      border: Border.all(color: borderColor, width: focused ? 1.5 : 1),
      boxShadow: focused ? _focusRing(context, invalid: invalid) : null,
    );
  }

  /// Wrapper for affixed inputs (prefix/suffix slots share one border).
  static BoxDecoration wrapperDecoration(
    BuildContext context, {
    AppInputSize size = AppInputSize.md,
    bool invalid = false,
    bool disabled = false,
    bool readOnly = false,
    bool focused = false,
  }) => decoration(
    context,
    size: size,
    invalid: invalid,
    disabled: disabled,
    readOnly: readOnly,
    focused: focused,
  );

  /// Transparent inner field decoration for inputs inside [wrapperDecoration].
  static InputDecoration bareInputDecoration(
    BuildContext context, {
    String? hintText,
    bool disabled = false,
  }) {
    final colors = context.colors;
    return InputDecoration(
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      hintText: hintText,
      hintStyle: context.typography.body.copyWith(
        color: colors.textPlaceholder,
      ),
      filled: false,
      isCollapsed: true,
    ).copyWith(
      hintStyle: context.typography.body.copyWith(
        color: colors.textPlaceholder,
      ),
    );
  }

  static List<BoxShadow> _focusRing(
    BuildContext context, {
    required bool invalid,
  }) {
    final colors = context.colors;
    final ringColor = invalid
        ? colors.statusDangerFg.withValues(alpha: 0.35)
        : colors.focusRing;
    return [BoxShadow(color: ringColor, blurRadius: 0, spreadRadius: 2)];
  }
}
