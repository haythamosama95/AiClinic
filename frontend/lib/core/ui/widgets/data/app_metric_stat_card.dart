import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Executive-style KPI card with watermark icon, value, and day-over-day trend.
class AppMetricStatCard extends StatelessWidget {
  const AppMetricStatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.percentChange,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  /// Percent change vs comparison period. Positive = up (green), negative = down (red).
  final double? percentChange;

  static const _trendUpColor = Color(0xFF059669);
  static const _trendDownColor = Color(0xFFDC2626);
  static const _iconRotation = math.pi / 6; // 30°

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final shape = context.shapeTokens;
    final textTheme = Theme.of(context).textTheme;
    final borderRadius = BorderRadius.circular(shape.lg);
    final trendUp = percentChange != null && percentChange! > 0;
    final trendDown = percentChange != null && percentChange! < 0;
    final trendColor = trendUp
        ? _trendUpColor
        : trendDown
        ? _trendDownColor
        : colors.mutedForeground;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = constraints.hasBoundedHeight && constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 108.0;
        final watermarkSize = math.max(72.0, cardHeight * 0.95);

        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: borderRadius,
            border: Border.all(color: colors.border),
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (percentChange != null)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomRight,
                          end: Alignment.topLeft,
                          colors: [trendColor.withValues(alpha: 0.15), trendColor.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: -watermarkSize * 0.28,
                  right: -watermarkSize * 0.08,
                  child: Transform.rotate(
                    angle: _iconRotation,
                    child: Icon(icon, size: watermarkSize, color: colors.mutedForeground.withValues(alpha: 0.07)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SpacingTokens.md,
                    SpacingTokens.md,
                    SpacingTokens.md,
                    SpacingTokens.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 16, color: colors.foreground),
                          const SizedBox(width: SpacingTokens.sm),
                          Expanded(
                            child: Text(
                              label,
                              style: textTheme.labelMedium?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SpacingTokens.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              value,
                              style: textTheme.headlineMedium?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                letterSpacing: -0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (percentChange != null) ...[
                            const SizedBox(width: SpacingTokens.sm),
                            _TrendBadge(percentChange: percentChange!, color: trendColor),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.percentChange, required this.color});

  final double percentChange;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isUp = percentChange > 0;
    final isDown = percentChange < 0;
    final label = '${percentChange.abs().toStringAsFixed(1)}%';

    return DecoratedBox(
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600, height: 1.1),
            ),
            if (isUp || isDown) ...[
              const SizedBox(width: 2),
              Icon(isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 14, color: color),
            ],
          ],
        ),
      ),
    );
  }
}
