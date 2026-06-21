import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_status_badge.dart';

/// Column 1 — today's master schedule timeline.
class AppointmentQueueScheduleColumn extends StatelessWidget {
  const AppointmentQueueScheduleColumn({required this.items, super.key});

  final List<AppointmentListItem> items;

  static final _timeFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return _QueueColumnShell(
      title: "Today's schedule",
      subtitle: 'Source of truth for expected visits',
      child: items.isEmpty
          ? const _QueueEmptyState(
              icon: Icons.event_note_outlined,
              title: 'No appointments today',
              subtitle: 'Booked visits will appear here in time order.',
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.xs),
              itemBuilder: (context, index) {
                final item = items[index];
                final dimmed = AppointmentQueueDisplay.isScheduleRowDimmed(item);
                return _ScheduleRow(
                  item: item,
                  timeLabel: _timeFormat.format(item.startTime.toLocal()),
                  dimmed: dimmed,
                  onTap: () => AppNavigator(context).pushAppointmentDetail(item.id, preview: item),
                );
              },
            ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.item, required this.timeLabel, required this.dimmed, required this.onTap});

  final AppointmentListItem item;
  final String timeLabel;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final opacity = dimmed ? 0.45 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(SpacingTokens.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SpacingTokens.sm),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SpacingTokens.sm),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    timeLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.primary),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.patientName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.doctorDisplayName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                AppointmentQueueStatusBadge(status: item.status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared column chrome for the three-panel layout.
class _QueueColumnShell extends StatelessWidget {
  const _QueueColumnShell({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(SpacingTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: SpacingTokens.xs / 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(SpacingTokens.sm), child: child),
          ),
        ],
      ),
    );
  }
}

class _QueueEmptyState extends StatelessWidget {
  const _QueueEmptyState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: colors.mutedForeground),
            const SizedBox(height: SpacingTokens.md),
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
