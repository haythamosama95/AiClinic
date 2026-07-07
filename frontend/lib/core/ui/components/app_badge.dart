import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

enum BadgeVariant { solid, soft, outline, dot }

enum BadgeColor { neutral, success, warning, danger, info, teal, ai }

enum BadgeSize { sm, md }

/// Application-owned badge (`04-components` D4).
class AppBadge extends StatelessWidget {
  const AppBadge({
    this.label,
    this.child,
    this.variant = BadgeVariant.soft,
    this.color = BadgeColor.neutral,
    this.size = BadgeSize.md,
    super.key,
  }) : assert(
         label != null || child != null || variant == BadgeVariant.dot,
         'Provide label, child, or use dot variant with label for accessibility.',
       );

  /// Visible text when [child] is omitted. Also used as the accessible label for dot-only badges.
  final String? label;
  final Widget? child;
  final BadgeVariant variant;
  final BadgeColor color;
  final BadgeSize size;

  bool get _isDotOnly => variant == BadgeVariant.dot && child == null;

  String? _accessibleLabel() {
    if (label != null) return label;
    if (child case final Text text) return text.data;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final palette = _BadgePalette.resolve(colors, brightness, color, variant);
    final metrics = _badgeMetrics(size);
    final textStyle = (size == BadgeSize.sm ? AppTypography.caption(context) : AppTypography.bodySm(context)).copyWith(
      color: palette.foreground,
      fontWeight: FontWeight.w500,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (variant == BadgeVariant.dot)
          _BadgeDot(diameter: metrics.dotSize, color: palette.dotFill, excludeSemantics: !_isDotOnly),
        if (variant == BadgeVariant.dot && !_isDotOnly) SizedBox(width: metrics.gap),
        if (!_isDotOnly)
          DefaultTextStyle(
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            child: child ?? Text(label!),
          ),
      ],
    );

    final badge = UnconstrainedBox(
      constrainedAxis: Axis.vertical,
      alignment: AlignmentDirectional.centerStart,
      clipBehavior: Clip.none,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: palette.border != null ? Border.all(color: palette.border!) : null,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: metrics.height),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
            child: content,
          ),
        ),
      ),
    );

    if (_isDotOnly) {
      return Semantics(label: _accessibleLabel(), container: true, child: badge);
    }

    return badge;
  }
}

class _BadgeMetrics {
  const _BadgeMetrics({
    required this.height,
    required this.horizontalPadding,
    required this.dotSize,
    required this.gap,
  });

  final double height;
  final double horizontalPadding;
  final double dotSize;
  final double gap;
}

_BadgeMetrics _badgeMetrics(BadgeSize size) {
  return switch (size) {
    BadgeSize.sm => const _BadgeMetrics(height: 20, horizontalPadding: 6, dotSize: 6, gap: AppSpacing.space1),
    BadgeSize.md => const _BadgeMetrics(height: 24, horizontalPadding: AppSpacing.space2, dotSize: 8, gap: 6),
  };
}

class _BadgePalette {
  const _BadgePalette({required this.background, required this.foreground, required this.dotFill, this.border});

  final Color background;
  final Color foreground;
  final Color dotFill;
  final Color? border;

  static _BadgePalette resolve(
    AppSemanticColors colors,
    Brightness brightness,
    BadgeColor color,
    BadgeVariant variant,
  ) {
    final isDark = brightness == Brightness.dark;

    final warningFg = isDark ? AppColorPrimitives.statusWarningFgDark : AppColorPrimitives.amber700;
    final warningSurface = isDark ? AppColorPrimitives.statusWarningSurfaceDark : AppColorPrimitives.amber50;
    final warningBorder = isDark ? AppColorPrimitives.statusWarningBorderDark : AppColorPrimitives.amber100;

    final infoFg = isDark ? AppColorPrimitives.statusInfoFgDark : AppColorPrimitives.blue700;
    final infoSurface = isDark ? AppColorPrimitives.statusInfoSurfaceDark : AppColorPrimitives.blue50;
    final infoBorder = isDark ? AppColorPrimitives.statusInfoBorderDark : AppColorPrimitives.blue100;

    final successSurface = isDark ? AppColorPrimitives.statusSuccessSurfaceDark : AppColorPrimitives.green50;
    final successBorder = isDark ? AppColorPrimitives.statusSuccessBorderDark : AppColorPrimitives.green100;

    final dangerSurface = isDark ? AppColorPrimitives.statusDangerSurfaceDark : AppColorPrimitives.red50;
    final dangerBorder = isDark ? AppColorPrimitives.statusDangerBorderDark : AppColorPrimitives.red100;

    return switch (variant) {
      BadgeVariant.solid => switch (color) {
        BadgeColor.neutral => _BadgePalette(
          background: colors.textSecondary,
          foreground: colors.textInverse,
          dotFill: colors.iconMuted,
        ),
        BadgeColor.success => _BadgePalette(
          background: colors.statusSuccessFg,
          foreground: colors.textInverse,
          dotFill: colors.statusSuccessFg,
        ),
        BadgeColor.warning => _BadgePalette(background: warningFg, foreground: colors.textInverse, dotFill: warningFg),
        BadgeColor.danger => _BadgePalette(
          background: colors.statusDangerFg,
          foreground: colors.textInverse,
          dotFill: colors.statusDangerFg,
        ),
        BadgeColor.info => _BadgePalette(background: infoFg, foreground: colors.textInverse, dotFill: infoFg),
        BadgeColor.teal => _BadgePalette(
          background: colors.actionPrimary,
          foreground: colors.actionPrimaryFg,
          dotFill: colors.actionPrimary,
        ),
        BadgeColor.ai => _BadgePalette(
          background: colors.actionAi,
          foreground: colors.actionAiFg,
          dotFill: colors.actionAi,
        ),
      },
      BadgeVariant.soft => switch (color) {
        BadgeColor.neutral => _BadgePalette(
          background: colors.surfaceMuted,
          foreground: colors.textSecondary,
          dotFill: colors.iconMuted,
        ),
        BadgeColor.success => _BadgePalette(
          background: successSurface,
          foreground: colors.statusSuccessFg,
          dotFill: colors.statusSuccessFg,
        ),
        BadgeColor.warning => _BadgePalette(background: warningSurface, foreground: warningFg, dotFill: warningFg),
        BadgeColor.danger => _BadgePalette(
          background: dangerSurface,
          foreground: colors.statusDangerFg,
          dotFill: colors.statusDangerFg,
        ),
        BadgeColor.info => _BadgePalette(background: infoSurface, foreground: infoFg, dotFill: infoFg),
        BadgeColor.teal => _BadgePalette(
          background: colors.surfaceSelected,
          foreground: colors.textLink,
          dotFill: colors.actionPrimary,
        ),
        BadgeColor.ai => _BadgePalette(
          background: colors.surfaceAi,
          foreground: colors.textAi,
          dotFill: colors.actionAi,
        ),
      },
      BadgeVariant.outline => switch (color) {
        BadgeColor.neutral => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.textSecondary,
          dotFill: colors.iconMuted,
          border: colors.borderDefault,
        ),
        BadgeColor.success => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.statusSuccessFg,
          dotFill: colors.statusSuccessFg,
          border: successBorder,
        ),
        BadgeColor.warning => _BadgePalette(
          background: Colors.transparent,
          foreground: warningFg,
          dotFill: warningFg,
          border: warningBorder,
        ),
        BadgeColor.danger => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.statusDangerFg,
          dotFill: colors.statusDangerFg,
          border: dangerBorder,
        ),
        BadgeColor.info => _BadgePalette(
          background: Colors.transparent,
          foreground: infoFg,
          dotFill: infoFg,
          border: infoBorder,
        ),
        BadgeColor.teal => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.textLink,
          dotFill: colors.actionPrimary,
          border: isDark ? AppColorPrimitives.teal400 : AppColorPrimitives.teal600,
        ),
        BadgeColor.ai => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.textAi,
          dotFill: colors.actionAi,
          border: colors.borderAi,
        ),
      },
      BadgeVariant.dot => switch (color) {
        BadgeColor.neutral => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.textSecondary,
          dotFill: colors.iconMuted,
        ),
        BadgeColor.success => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.statusSuccessFg,
          dotFill: colors.statusSuccessFg,
        ),
        BadgeColor.warning => _BadgePalette(background: Colors.transparent, foreground: warningFg, dotFill: warningFg),
        BadgeColor.danger => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.statusDangerFg,
          dotFill: colors.statusDangerFg,
        ),
        BadgeColor.info => _BadgePalette(background: Colors.transparent, foreground: infoFg, dotFill: infoFg),
        BadgeColor.teal => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.textLink,
          dotFill: colors.actionPrimary,
        ),
        BadgeColor.ai => _BadgePalette(
          background: Colors.transparent,
          foreground: colors.textAi,
          dotFill: colors.actionAi,
        ),
      },
    };
  }
}

class _BadgeDot extends StatelessWidget {
  const _BadgeDot({required this.diameter, required this.color, required this.excludeSemantics});

  final double diameter;
  final Color color;
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    if (excludeSemantics) {
      return ExcludeSemantics(child: dot);
    }

    return dot;
  }
}
