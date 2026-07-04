import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/layout/app_card.dart';

/// Direction of a metric delta indicator.
enum AppMetricDeltaDirection {
  up,
  down,
}

/// Optional change indicator for [AppMetricCard].
@immutable
class AppMetricDelta {
  const AppMetricDelta({
    required this.value,
    required this.direction,
    this.positive,
  });

  final String value;
  final AppMetricDeltaDirection direction;

  /// When omitted, `up` is treated as positive and `down` as negative.
  final bool? positive;
}

/// Dashboard metric surface composing [AppCard] with label, value, delta, and
/// an optional [sparkline] slot.
///
/// The [sparkline] accepts any widget (e.g. a future [AppChart] sparkline) —
/// this component does not render charts itself.
class AppMetricCard extends StatelessWidget {
  const AppMetricCard({
    required this.label,
    required this.value,
    this.delta,
    this.caption,
    this.sparkline,
    super.key,
  });

  final String label;
  final String value;
  final AppMetricDelta? delta;
  final String? caption;

  /// Optional trailing sparkline widget supplied by the caller.
  final Widget? sparkline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AppCard(
      variant: AppCardVariant.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: typography.overline.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: typography.tabular(typography.display).copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sparkline != null) ...[
                const SizedBox(width: AppSpacing.s4),
                sparkline!,
              ],
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: AppSpacing.s3),
            _DeltaRow(delta: delta!),
          ],
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(
              caption!,
              style: typography.caption.copyWith(color: colors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _DeltaRow extends StatelessWidget {
  const _DeltaRow({required this.delta});

  final AppMetricDelta delta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final positive =
        delta.positive ?? delta.direction == AppMetricDeltaDirection.up;
    final deltaColor =
        positive ? colors.statusSuccessFg : colors.statusDangerFg;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          icon: delta.direction == AppMetricDeltaDirection.up
              ? LucideIcons.trendingUp
              : LucideIcons.trendingDown,
          dimension: AppSpacing.s3 + AppSpacing.s0_5,
          color: deltaColor,
        ),
        const SizedBox(width: AppSpacing.s1 + AppSpacing.s0_5),
        Text(
          delta.value,
          style: typography.tabular(typography.bodySm).copyWith(
            color: deltaColor,
          ),
        ),
      ],
    );
  }
}
