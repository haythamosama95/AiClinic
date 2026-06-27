import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';

/// Top stats banner with executive KPI cards for queue pulse metrics.
class AppointmentQueueStatsBanner extends StatelessWidget {
  const AppointmentQueueStatsBanner({required this.stats, super.key});

  final AppointmentQueueStats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final children = [
          AppMetricStatCard(
            label: 'Total appointments',
            value: '${stats.total}',
            icon: Icons.event_note_outlined,
            percentChange: stats.totalTrend?.percentChange,
          ),
          AppMetricStatCard(
            label: 'Completed',
            value: '${stats.completed}',
            icon: Icons.task_alt_outlined,
            percentChange: stats.completedTrend?.percentChange,
          ),
          AppMetricStatCard(
            label: 'No-show',
            value: '${stats.noShow}',
            icon: Icons.person_off_outlined,
            percentChange: stats.noShowTrend?.percentChange,
          ),
          AppMetricStatCard(
            label: 'Avg. waiting time',
            value: stats.avgWaitMinutes == null ? '—' : '${stats.avgWaitMinutes} mins',
            icon: Icons.timer_outlined,
            percentChange: stats.avgWaitTrend?.percentChange,
          ),
          AppMetricStatCard(
            label: 'Avg. visit duration',
            value: stats.avgVisitMinutes == null ? '—' : '${stats.avgVisitMinutes} mins',
            icon: Icons.medical_services_outlined,
            percentChange: stats.avgVisitTrend?.percentChange,
          ),
        ];

        if (isCompact) {
          return Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.sm,
            children: children
                .map((card) => SizedBox(width: (constraints.maxWidth - SpacingTokens.sm) / 2, child: card))
                .toList(),
          );
        }

        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: SpacingTokens.md),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}
