import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppBadgeVariant { neutral, success, warning, danger, info, ai }

enum AppBadgeTone { subtle, solid }

enum AppBadgeSize { sm, md }

/// Compact status pill with optional leading dot or icon.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    this.variant = AppBadgeVariant.neutral,
    this.tone = AppBadgeTone.subtle,
    this.size = AppBadgeSize.md,
    this.label,
    this.child,
    this.showDot = false,
    this.icon,
  });

  final AppBadgeVariant variant;
  final AppBadgeTone tone;
  final AppBadgeSize size;
  final String? label;
  final Widget? child;
  final bool showDot;
  final IconData? icon;

  double get _height => size == AppBadgeSize.sm ? 20 : 24;

  double get _dotSize => size == AppBadgeSize.sm ? 6 : 8;

  double get _iconSize => size == AppBadgeSize.sm ? 12 : 14;

  EdgeInsets get _padding => EdgeInsets.symmetric(
    horizontal: size == AppBadgeSize.sm ? AppSpacing.s1 + 2 : AppSpacing.s2,
  );

  TextStyle _textStyle(BuildContext context) {
    final typography = context.typography;
    return (size == AppBadgeSize.sm ? typography.caption : typography.bodySm)
        .copyWith(fontWeight: FontWeight.w500);
  }

  ({Color bg, Color fg, Color? border}) _colors(AppColors colors) {
    final fg = switch (variant) {
      AppBadgeVariant.neutral =>
        tone == AppBadgeTone.solid ? colors.textInverse : colors.textSecondary,
      AppBadgeVariant.success =>
        tone == AppBadgeTone.solid
            ? colors.textInverse
            : colors.statusSuccessFg,
      AppBadgeVariant.warning =>
        tone == AppBadgeTone.solid
            ? colors.textInverse
            : colors.statusWarningFg,
      AppBadgeVariant.danger =>
        tone == AppBadgeTone.solid ? colors.textInverse : colors.statusDangerFg,
      AppBadgeVariant.info =>
        tone == AppBadgeTone.solid ? colors.textInverse : colors.statusInfoFg,
      AppBadgeVariant.ai =>
        tone == AppBadgeTone.solid ? colors.actionAiFg : colors.textAi,
    };

    final bg = switch (tone) {
      AppBadgeTone.solid => switch (variant) {
        AppBadgeVariant.neutral => colors.textSecondary,
        AppBadgeVariant.success => colors.statusSuccessFg,
        AppBadgeVariant.warning => colors.statusWarningFg,
        AppBadgeVariant.danger => colors.statusDangerFg,
        AppBadgeVariant.info => colors.statusInfoFg,
        AppBadgeVariant.ai => colors.actionAi,
      },
      AppBadgeTone.subtle => switch (variant) {
        AppBadgeVariant.neutral => colors.surfaceMuted,
        AppBadgeVariant.success => colors.statusSuccessSurface,
        AppBadgeVariant.warning => colors.statusWarningSurface,
        AppBadgeVariant.danger => colors.statusDangerSurface,
        AppBadgeVariant.info => colors.statusInfoSurface,
        AppBadgeVariant.ai => colors.surfaceAi,
      },
    };

    return (bg: bg, fg: fg, border: null);
  }

  Color _dotColor(AppColors colors) => switch (variant) {
    AppBadgeVariant.neutral => colors.iconMuted,
    AppBadgeVariant.success => colors.statusSuccessFg,
    AppBadgeVariant.warning => colors.statusWarningFg,
    AppBadgeVariant.danger => colors.statusDangerFg,
    AppBadgeVariant.info => colors.statusInfoFg,
    AppBadgeVariant.ai => colors.actionAi,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _colors(colors);
    final content = child ?? (label != null ? Text(label!) : null);
    final isDotOnly = showDot && content == null;
    final accessibleLabel = label ?? (content is Text ? (content).data : null);

    return Semantics(
      label: isDotOnly ? accessibleLabel : null,
      container: isDotOnly,
      child: Container(
        constraints: BoxConstraints(minHeight: _height, maxHeight: _height),
        padding: _padding,
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: AppRadius.fullAll,
          border: palette.border != null
              ? Border.all(color: palette.border!)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot) ...[
              Container(
                width: _dotSize,
                height: _dotSize,
                decoration: BoxDecoration(
                  color: _dotColor(colors),
                  shape: BoxShape.circle,
                ),
              ),
              if (content != null)
                SizedBox(
                  width: size == AppBadgeSize.sm
                      ? AppSpacing.s1
                      : AppSpacing.s1 + 2,
                ),
            ],
            if (icon != null) ...[
              Icon(icon, size: _iconSize, color: palette.fg),
              if (content != null)
                SizedBox(
                  width: size == AppBadgeSize.sm
                      ? AppSpacing.s1
                      : AppSpacing.s1 + 2,
                ),
            ],
            if (content != null)
              Flexible(
                child: DefaultTextStyle(
                  style: _textStyle(context).copyWith(color: palette.fg),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  child: content,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
