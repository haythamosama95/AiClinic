import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Visual treatment for [AppBadge].
enum AppBadgeVariant {
  /// Filled background using status or action primitives.
  solid,

  /// Tinted surface with matching foreground (default).
  soft,

  /// Border only with transparent background.
  outline,

  /// Leading status dot with optional label.
  dot,
}

/// Semantic color for [AppBadge].
enum AppBadgeColor {
  neutral,
  success,
  warning,
  danger,
  info,
  teal,
  violet,
}

/// Size scale for [AppBadge].
enum AppBadgeSize {
  /// Compact pill — 20px height.
  sm,

  /// Default pill — 24px height.
  md,
}

/// Status and count pill with solid, soft, outline, and dot variants.
class AppBadge extends StatelessWidget {
  const AppBadge({
    this.variant = AppBadgeVariant.soft,
    this.color = AppBadgeColor.neutral,
    this.size = AppBadgeSize.md,
    this.label,
    this.child,
    super.key,
  });

  final AppBadgeVariant variant;
  final AppBadgeColor color;
  final AppBadgeSize size;
  final String? label;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final scheme = _resolveScheme(colors, color, variant);
    final isDotOnly = variant == AppBadgeVariant.dot && child == null;
    final accessibleLabel = label ?? _childLabel(child);

    final textStyle = switch (size) {
      AppBadgeSize.sm => typography.caption.copyWith(
        fontWeight: FontWeight.w500,
        color: scheme.foreground,
      ),
      AppBadgeSize.md => typography.bodySm.copyWith(
        fontWeight: FontWeight.w500,
        color: scheme.foreground,
      ),
    };

    final height = switch (size) {
      AppBadgeSize.sm => AppSpacing.s5,
      AppBadgeSize.md => AppSpacing.s6,
    };

    final horizontalPadding = switch (size) {
      AppBadgeSize.sm => AppSpacing.s1 + AppSpacing.s0_5,
      AppBadgeSize.md => AppSpacing.s2,
    };

    final gap = switch (size) {
      AppBadgeSize.sm => AppSpacing.s1,
      AppBadgeSize.md => AppSpacing.s1 + AppSpacing.s0_5,
    };

    final dotSize = switch (size) {
      AppBadgeSize.sm => AppSpacing.s1 + AppSpacing.s0_5,
      AppBadgeSize.md => AppSpacing.s2,
    };

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (variant == AppBadgeVariant.dot)
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: scheme.dotColor ?? scheme.foreground,
              shape: BoxShape.circle,
            ),
          ),
        if (child != null) ...[
          if (variant == AppBadgeVariant.dot) SizedBox(width: gap),
          Flexible(
            child: DefaultTextStyle(
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: child!,
            ),
          ),
        ],
      ],
    );

    content = Container(
      height: height,
      padding: EdgeInsetsDirectional.symmetric(horizontal: horizontalPadding),
      alignment: AlignmentDirectional.center,
      decoration: BoxDecoration(
        color: scheme.background,
        border: scheme.borderColor != null
            ? Border.all(color: scheme.borderColor!)
            : null,
        borderRadius: AppRadii.fullAll,
      ),
      child: content,
    );

    if (isDotOnly) {
      content = Semantics(
        container: true,
        liveRegion: true,
        label: accessibleLabel,
        child: content,
      );
    }

    return content;
  }

  String? _childLabel(Widget? widget) {
    if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
    return null;
  }
}

@immutable
class _BadgeScheme {
  const _BadgeScheme({
    required this.background,
    required this.foreground,
    this.borderColor,
    this.dotColor,
  });

  final Color background;
  final Color foreground;
  final Color? borderColor;
  final Color? dotColor;
}

_BadgeScheme _resolveScheme(
  AppColors colors,
  AppBadgeColor color,
  AppBadgeVariant variant,
) {
  return switch (variant) {
    AppBadgeVariant.solid => _solidScheme(colors, color),
    AppBadgeVariant.soft => _softScheme(colors, color),
    AppBadgeVariant.outline => _outlineScheme(colors, color),
    AppBadgeVariant.dot => _dotScheme(colors, color),
  };
}

_BadgeScheme _solidScheme(AppColors colors, AppBadgeColor color) {
  return switch (color) {
    AppBadgeColor.neutral => _BadgeScheme(
      background: colors.textSecondary,
      foreground: colors.textInverse,
    ),
    AppBadgeColor.success => _BadgeScheme(
      background: colors.statusSuccessFg,
      foreground: colors.textInverse,
    ),
    AppBadgeColor.warning => _BadgeScheme(
      background: colors.statusWarningFg,
      foreground: colors.textInverse,
    ),
    AppBadgeColor.danger => _BadgeScheme(
      background: colors.statusDangerFg,
      foreground: colors.textInverse,
    ),
    AppBadgeColor.info => _BadgeScheme(
      background: colors.statusInfoFg,
      foreground: colors.textInverse,
    ),
    AppBadgeColor.teal => _BadgeScheme(
      background: colors.actionPrimary,
      foreground: colors.actionPrimaryFg,
    ),
    AppBadgeColor.violet => _BadgeScheme(
      background: colors.actionAi,
      foreground: colors.actionAiFg,
    ),
  };
}

_BadgeScheme _softScheme(AppColors colors, AppBadgeColor color) {
  return switch (color) {
    AppBadgeColor.neutral => _BadgeScheme(
      background: colors.surfaceMuted,
      foreground: colors.textSecondary,
    ),
    AppBadgeColor.success => _BadgeScheme(
      background: colors.statusSuccessSurface,
      foreground: colors.statusSuccessFg,
    ),
    AppBadgeColor.warning => _BadgeScheme(
      background: colors.statusWarningSurface,
      foreground: colors.statusWarningFg,
    ),
    AppBadgeColor.danger => _BadgeScheme(
      background: colors.statusDangerSurface,
      foreground: colors.statusDangerFg,
    ),
    AppBadgeColor.info => _BadgeScheme(
      background: colors.statusInfoSurface,
      foreground: colors.statusInfoFg,
    ),
    AppBadgeColor.teal => _BadgeScheme(
      background: colors.surfaceSelected,
      foreground: colors.textLink,
    ),
    AppBadgeColor.violet => _BadgeScheme(
      background: colors.surfaceAi,
      foreground: colors.textAi,
    ),
  };
}

_BadgeScheme _outlineScheme(AppColors colors, AppBadgeColor color) {
  return switch (color) {
    AppBadgeColor.neutral => _BadgeScheme(
      background: Colors.transparent,
      foreground: colors.textSecondary,
      borderColor: colors.borderDefault,
    ),
    AppBadgeColor.success => _BadgeScheme(
      background: Colors.transparent,
      foreground: colors.statusSuccessFg,
      borderColor: colors.statusSuccessBorder,
    ),
    AppBadgeColor.warning => _BadgeScheme(
      background: Colors.transparent,
      foreground: colors.statusWarningFg,
      borderColor: colors.statusWarningBorder,
    ),
    AppBadgeColor.danger => _BadgeScheme(
      background: Colors.transparent,
      foreground: colors.statusDangerFg,
      borderColor: colors.statusDangerBorder,
    ),
    AppBadgeColor.info => _BadgeScheme(
      background: Colors.transparent,
      foreground: colors.statusInfoFg,
      borderColor: colors.statusInfoBorder,
    ),
    AppBadgeColor.teal => _BadgeScheme(
      background: Colors.transparent,
      foreground: colors.textLink,
      borderColor: colors.borderFocus,
    ),
    AppBadgeColor.violet => _BadgeScheme(
      background: Colors.transparent,
      foreground: colors.textAi,
      borderColor: colors.borderAi,
    ),
  };
}

_BadgeScheme _dotScheme(AppColors colors, AppBadgeColor color) {
  final dotColor = switch (color) {
    AppBadgeColor.neutral => colors.iconMuted,
    AppBadgeColor.success => colors.statusSuccessFg,
    AppBadgeColor.warning => colors.statusWarningFg,
    AppBadgeColor.danger => colors.statusDangerFg,
    AppBadgeColor.info => colors.statusInfoFg,
    AppBadgeColor.teal => colors.actionPrimary,
    AppBadgeColor.violet => colors.actionAi,
  };

  final foreground = switch (color) {
    AppBadgeColor.neutral => colors.textSecondary,
    AppBadgeColor.success => colors.statusSuccessFg,
    AppBadgeColor.warning => colors.statusWarningFg,
    AppBadgeColor.danger => colors.statusDangerFg,
    AppBadgeColor.info => colors.statusInfoFg,
    AppBadgeColor.teal => colors.textLink,
    AppBadgeColor.violet => colors.textAi,
  };

  return _BadgeScheme(
    background: Colors.transparent,
    foreground: foreground,
    dotColor: dotColor,
  );
}
