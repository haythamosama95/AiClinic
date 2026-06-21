import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';

/// Top stats banner with value cards for queue pulse metrics.
class AppointmentQueueStatsBanner extends StatelessWidget {
  const AppointmentQueueStatsBanner({required this.stats, super.key});

  final AppointmentQueueStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final children = [
          _StatCard(label: 'Total appointments', value: '${stats.total}', accent: colors.primary),
          _StatCard(label: 'Completed', value: '${stats.completed}', accent: const Color(0xFF059669)),
          _StatCard(label: 'Currently waiting', value: '${stats.waiting}', accent: const Color(0xFFEAB308)),
          _StatCard(
            label: 'Avg. wait time',
            value: stats.avgWaitMinutes == null ? '—' : '${stats.avgWaitMinutes} mins',
            accent: colors.foreground,
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(SpacingTokens.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.mutedForeground)),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: accent, fontWeight: FontWeight.w700, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}
