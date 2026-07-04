import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';

/// Summary metrics banner for the clinic queue dashboard.
class AppointmentQueueStatsBanner extends StatelessWidget {
  const AppointmentQueueStatsBanner({
    required this.stats,
    this.trendsUnavailable = false,
    super.key,
  });

  final AppointmentQueueStats stats;
  final bool trendsUnavailable;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return AppCard(
      variant: AppCardVariant.flat,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final tiles = [
            _StatTile(label: 'Total today', value: '${stats.total}', trend: stats.totalTrend, compact: compact),
            _StatTile(label: 'Completed', value: '${stats.completed}', trend: stats.completedTrend, compact: compact),
            _StatTile(label: 'No-shows', value: '${stats.noShow}', trend: stats.noShowTrend, compact: compact),
            _StatTile(
              label: 'Avg wait',
              value: stats.avgWaitMinutes == null ? '—' : '${stats.avgWaitMinutes}m',
              trend: stats.avgWaitTrend,
              compact: compact,
            ),
            _StatTile(
              label: 'Avg visit',
              value: stats.avgVisitMinutes == null ? '—' : '${stats.avgVisitMinutes}m',
              trend: stats.avgVisitTrend,
              compact: compact,
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text("Today's queue", style: typography.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const Spacer(),
                  if (trendsUnavailable)
                    Flexible(
                      child: Text(
                        'Trends unavailable',
                        style: typography.caption.copyWith(color: colors.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              Wrap(
                spacing: AppSpacing.s3,
                runSpacing: AppSpacing.s3,
                children: tiles,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.compact,
    this.trend,
  });

  final String label;
  final String value;
  final AppointmentQueueStatTrend? trend;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;
    final width = compact ? double.infinity : 140.0;
    final percent = trend?.percentChange;
    final trendLabel = percent == null
        ? null
        : percent == 0
        ? '0%'
        : '${percent > 0 ? '+' : ''}${percent.round()}%';

    return SizedBox(
      width: compact ? null : width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: typography.caption.copyWith(color: colors.textTertiary)),
              const SizedBox(height: AppSpacing.s1),
              Text(value, style: typography.tabular(typography.title)),
              if (trendLabel != null) ...[
                const SizedBox(height: AppSpacing.s1),
                Text(trendLabel, style: typography.caption.copyWith(color: colors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
