import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_timeline.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_actions.dart';

/// Status journey timeline for an appointment detail view.
class AppointmentStatusTimelineSection extends StatelessWidget {
  const AppointmentStatusTimelineSection({required this.detail, super.key});

  final AppointmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;
    final current = detail.status;
    final isTerminal = AppointmentStatusTimeline.isTerminalNegative(current);
    final steps = AppointmentStatusTimeline.mainFlow;
    final currentIndex = isTerminal ? -1 : steps.indexOf(current);
    final progressLabel = isTerminal
        ? 'Ended early'
        : currentIndex >= 0
        ? 'Step ${currentIndex + 1} of ${steps.length}'
        : null;

    final events = <AppTimelineEvent>[
      for (final step in steps)
        AppTimelineEvent(
          id: step.wireValue,
          timestamp: step.label,
          title: step.label,
          description: Text(
            AppointmentStatusTimeline.stepDescription(step),
            style: typography.caption.copyWith(color: colors.textSecondary),
          ),
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(icon: LucideIcons.route, color: colors.textLink),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.s2,
                      runSpacing: AppSpacing.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Status journey', style: typography.title),
                        if (progressLabel != null)
                          AppBadge(
                            color: isTerminal ? AppBadgeColor.danger : AppBadgeColor.neutral,
                            child: Text(progressLabel),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      isTerminal
                          ? 'This appointment ended before completion.'
                          : 'Track where this appointment is in the clinic workflow.',
                      style: typography.caption.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              AppointmentStatusActions(detail: detail),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          AppTimeline(events: events),
          if (isTerminal) ...[
            const SizedBox(height: AppSpacing.s4),
            AppAlert(
              variant: AppAlertVariant.warning,
              title: current.label,
              body: AppointmentStatusTimeline.stepDescription(current),
            ),
          ],
        ],
      ),
    );
  }
}
