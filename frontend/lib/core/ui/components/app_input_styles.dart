import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Shared input size scale (web `InputSize`).
enum AppInputSize { sm, md, lg }

/// Layout metrics for a given [AppInputSize].
@immutable
class AppInputMetrics {
  const AppInputMetrics({
    required this.height,
    required this.horizontalPadding,
    this.gap = AppSpacing.space2,
    this.iconSize = 16,
    this.textStyle,
    this.affixTextStyle,
  });

  final double height;
  final double horizontalPadding;
  final double gap;
  final double iconSize;
  final TextStyle? textStyle;
  final TextStyle? affixTextStyle;
}

AppInputMetrics _baseMetrics(AppInputSize size) {
  return switch (size) {
    AppInputSize.sm => const AppInputMetrics(height: 32, horizontalPadding: AppSpacing.space3),
    AppInputSize.md => const AppInputMetrics(height: 36, horizontalPadding: AppSpacing.space3),
    AppInputSize.lg => const AppInputMetrics(height: 44, horizontalPadding: AppSpacing.space4),
  };
}

AppInputMetrics _metricsWithStyles(BuildContext context, AppInputSize size) {
  final base = _baseMetrics(size);
  return AppInputMetrics(
    height: base.height,
    horizontalPadding: base.horizontalPadding,
    gap: base.gap,
    iconSize: base.iconSize,
    textStyle: appInputTextStyle(context, size),
    affixTextStyle: appInputAffixTextStyle(context, size),
  );
}

/// Resolves input metrics. Supports `appInputMetrics(size)` and `appInputMetrics(context, size)`.
AppInputMetrics appInputMetrics(Object first, [AppInputSize? second]) {
  if (first is BuildContext && second != null) {
    return _metricsWithStyles(first, second);
  }
  if (first is AppInputSize) {
    return _baseMetrics(first);
  }
  throw ArgumentError('Use appInputMetrics(size) or appInputMetrics(context, size).');
}

/// Alias for the context-aware metrics call.
AppInputMetrics appInputMetricsFor(BuildContext context, AppInputSize size) {
  return _metricsWithStyles(context, size);
}

TextStyle appInputTextStyle(BuildContext context, AppInputSize size) {
  final colors = context.appColors;
  final base = switch (size) {
    AppInputSize.sm => AppTypography.bodySm(context),
    AppInputSize.md => AppTypography.body(context),
    AppInputSize.lg => AppTypography.bodyLg(context),
  };
  return base.copyWith(color: colors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]);
}

TextStyle appInputAffixTextStyle(BuildContext context, AppInputSize size) {
  return appInputTextStyle(context, size).copyWith(color: context.appColors.textTertiary);
}

TextStyle appBareInputTextStyle(BuildContext context, AppInputSize size, {required bool disabled}) {
  final colors = context.appColors;
  return appInputTextStyle(context, size).copyWith(color: disabled ? colors.textDisabled : colors.textPrimary);
}

TextStyle appInputDisabledTextStyle(BuildContext context, AppInputSize size) {
  return appBareInputTextStyle(context, size, disabled: true);
}

BoxDecoration appInputBoxDecoration(
  BuildContext context, {
  AppInputSize size = AppInputSize.md,
  bool invalid = false,
  bool disabled = false,
  bool readOnly = false,
  bool focused = false,
}) {
  return appInputDecoration(
    context,
    size: size,
    invalid: invalid,
    disabled: disabled,
    readOnly: readOnly,
    focused: focused,
  );
}

Color appInputFocusRingColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppColorPrimitives.focusRingDark : AppColorPrimitives.focusRingLight;
}

Color appInputInvalidFocusRingColor(AppSemanticColors colors) {
  return colors.statusDangerFg.withValues(alpha: 0.35);
}

Color _inputFocusBorderColor(AppSemanticColors colors, Brightness brightness) {
  return brightness == Brightness.dark ? AppColorPrimitives.teal400 : AppColorPrimitives.teal500;
}

Border appInputBorder(
  AppSemanticColors colors, {
  bool invalid = false,
  bool focused = false,
  Brightness brightness = Brightness.light,
}) {
  return Border.all(
    color: invalid
        ? (focused ? colors.statusDangerFg : colors.statusDangerBorder)
        : (focused ? _inputFocusBorderColor(colors, brightness) : colors.borderDefault),
  );
}

/// Violet AI focus ring for the AI panel composer (web `focus-ring-ai`).
BoxDecoration appAiInputDecoration(
  BuildContext context, {
  required bool focused,
}) {
  final colors = context.appColors;

  return BoxDecoration(
    color: colors.surfaceDefault,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(color: focused ? colors.actionAi : colors.borderAi),
    boxShadow: focused
        ? [BoxShadow(color: colors.actionAi.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 2)]
        : null,
  );
}

/// Box decoration for input shells (web `inputFieldClasses` / `inputWrapperClasses`).
BoxDecoration appInputDecoration(
  BuildContext context, {
  AppInputSize size = AppInputSize.md,
  bool invalid = false,
  bool disabled = false,
  bool readOnly = false,
  bool focused = false,
}) {
  final colors = context.appColors;
  final brightness = Theme.of(context).brightness;
  final focusRing = invalid ? appInputInvalidFocusRingColor(colors) : appInputFocusRingColor(context);

  return BoxDecoration(
    color: disabled ? colors.actionDisabledBg : (readOnly ? colors.surfaceSunken : colors.surfaceDefault),
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: appInputBorder(colors, invalid: invalid, focused: focused, brightness: brightness),
    boxShadow: focused ? [BoxShadow(color: focusRing, blurRadius: 0, spreadRadius: 2)] : null,
  );
}

/// Alias used by affix/stepper inputs.
BoxDecoration appInputWrapperDecoration(
  BuildContext context, {
  AppInputSize size = AppInputSize.md,
  bool invalid = false,
  bool disabled = false,
  bool readOnly = false,
  bool focused = false,
}) {
  return appInputDecoration(
    context,
    size: size,
    invalid: invalid,
    disabled: disabled,
    readOnly: readOnly,
    focused: focused,
  );
}

/// Transparent [Material] shell required by [TextField], [Slider], and other
/// Material widgets when the visual chrome is provided by a parent [BoxDecoration].
Widget appWrapMaterialInput(Widget child) {
  return Material(type: MaterialType.transparency, color: Colors.transparent, child: child);
}

/// Vertically centers a single-line field inside a fixed-height input shell.
Widget appCenterInputField(Widget field) {
  return Align(alignment: AlignmentDirectional.centerStart, child: appWrapMaterialInput(field));
}

/// Borderless decoration for bare fields inside affix wrappers.
InputDecoration appBareInputDecoration(
  BuildContext context, {
  String? hintText,
  bool disabled = false,
  AppInputSize size = AppInputSize.md,
}) {
  final hintStyle = appBareInputTextStyle(
    context,
    size,
    disabled: disabled,
  ).copyWith(color: context.appColors.textPlaceholder);

  return InputDecoration(
    isDense: true,
    isCollapsed: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    hintText: hintText,
    hintStyle: hintStyle,
  );
}
