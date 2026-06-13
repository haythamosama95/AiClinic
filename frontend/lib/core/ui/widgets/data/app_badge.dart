import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Semantic badge variants for counts, statuses, and tags.
enum AppBadgeVariant { muted, primary, outline, accent }

/// Compact label chip for counts, statuses, and metadata.
class AppBadge extends StatelessWidget {
  const AppBadge({required this.label, this.variant = AppBadgeVariant.muted, this.icon, this.dense = false, super.key});

  final String label;
  final AppBadgeVariant variant;
  final Widget? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final radius = BorderRadius.circular(context.shapeTokens.sm);
    final (background, foreground, border) = switch (variant) {
      AppBadgeVariant.muted => (colors.muted, colors.mutedForeground, colors.border),
      AppBadgeVariant.primary => (colors.primary, colors.primaryForeground, colors.primary),
      AppBadgeVariant.outline => (colors.background, colors.foreground, colors.border),
      AppBadgeVariant.accent => (colors.accent, colors.accentForeground, colors.accent),
    };

    final verticalPadding = dense ? SpacingTokens.xs / 2 : SpacingTokens.xs;
    final horizontalPadding = dense ? SpacingTokens.sm : SpacingTokens.sm + 2;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground,
      fontWeight: variant == AppBadgeVariant.muted ? FontWeight.w500 : FontWeight.w600,
      fontSize: dense ? 11 : 12,
      height: 1.2,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              IconTheme.merge(
                data: IconThemeData(size: 12, color: foreground),
                child: icon!,
              ),
              const SizedBox(width: SpacingTokens.xs),
            ],
            Text(label, style: textStyle),
          ],
        ),
      ),
    );
  }
}
