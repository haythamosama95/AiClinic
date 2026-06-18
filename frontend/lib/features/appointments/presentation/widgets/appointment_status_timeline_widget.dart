import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_timeline.dart';

/// Visual timeline of appointment lifecycle statuses with the current step highlighted.
class AppointmentStatusTimelineWidget extends StatelessWidget {
  const AppointmentStatusTimelineWidget({required this.currentStatus, super.key});

  final AppointmentStatus currentStatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final isTerminal = AppointmentStatusTimeline.isTerminalNegative(currentStatus);
    final steps = AppointmentStatusTimeline.mainFlow;
    final currentIndex = isTerminal ? -1 : steps.indexOf(currentStatus);
    final progressLabel = isTerminal
        ? 'Ended early'
        : currentIndex >= 0
        ? 'Step ${currentIndex + 1} of ${steps.length}'
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(color: colors.foreground.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, size: 20, color: colors.primary),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Text(
                    'Status journey',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (progressLabel != null) AppBadge(label: progressLabel, variant: AppBadgeVariant.outline),
              ],
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              isTerminal
                  ? 'This appointment ended before completion.'
                  : 'Track where this appointment is in the clinic workflow.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
            if (isTerminal) ...[const SizedBox(height: SpacingTokens.md), _TerminalStatusBanner(status: currentStatus)],
            const SizedBox(height: SpacingTokens.lg),
            _VerticalStatusTimeline(currentStatus: currentStatus, isTerminal: isTerminal),
          ],
        ),
      ),
    );
  }
}

class _TerminalStatusBanner extends StatelessWidget {
  const _TerminalStatusBanner({required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final statusColor = AppointmentCalendarDisplay.statusColor(status);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor.withValues(alpha: 0.18), statusColor.withValues(alpha: 0.06)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
        child: Row(
          children: [
            Icon(_iconForStatus(status), color: statusColor, size: 22),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.label,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: statusColor),
                  ),
                  Text(
                    AppointmentStatusTimeline.stepDescription(status),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                  ),
                ],
              ),
            ),
            AppBadge(label: 'Final', variant: AppBadgeVariant.outline),
          ],
        ),
      ),
    );
  }
}

class _VerticalStatusTimeline extends StatelessWidget {
  const _VerticalStatusTimeline({required this.currentStatus, required this.isTerminal});

  final AppointmentStatus currentStatus;
  final bool isTerminal;

  @override
  Widget build(BuildContext context) {
    final steps = AppointmentStatusTimeline.mainFlow;

    return Column(
      children: [
        for (var index = 0; index < steps.length; index++)
          _TimelineStepRow(
            status: steps[index],
            stepState: AppointmentStatusTimeline.stepState(current: currentStatus, step: steps[index]),
            isTerminalContext: isTerminal,
            isLast: index == steps.length - 1,
            stepNumber: index + 1,
          ),
      ],
    );
  }
}

class _TimelineStepRow extends StatelessWidget {
  const _TimelineStepRow({
    required this.status,
    required this.stepState,
    required this.isTerminalContext,
    required this.isLast,
    required this.stepNumber,
  });

  final AppointmentStatus status;
  final AppointmentTimelineStepState stepState;
  final bool isTerminalContext;
  final bool isLast;
  final int stepNumber;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final statusColor = AppointmentCalendarDisplay.statusColor(status);
    final isCurrent = stepState == AppointmentTimelineStepState.current;
    final isCompleted = stepState == AppointmentTimelineStepState.completed;
    final isSkipped = stepState == AppointmentTimelineStepState.skipped;
    final isUpcoming = stepState == AppointmentTimelineStepState.upcoming;

    final nodeColor = isSkipped
        ? colors.mutedForeground.withValues(alpha: 0.4)
        : isCurrent || isCompleted
        ? statusColor
        : colors.mutedForeground.withValues(alpha: 0.45);

    final connectorActive = !isTerminalContext && isCompleted;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                _TimelineNode(
                  icon: isCompleted ? Icons.check_rounded : _iconForStatus(status),
                  color: nodeColor,
                  isCurrent: isCurrent,
                  isCompleted: isCompleted,
                  isSkipped: isSkipped,
                ),
                if (!isLast)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: 2,
                        color: connectorActive ? colors.primary : colors.border,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : SpacingTokens.lg),
              child: isCurrent
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(context.shapeTokens.md),
                        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(SpacingTokens.md),
                        child: _TimelineStepContent(
                          status: status,
                          isCurrent: isCurrent,
                          isCompleted: isCompleted,
                          isSkipped: isSkipped,
                          isUpcoming: isUpcoming,
                          isTerminalContext: isTerminalContext,
                          stepNumber: stepNumber,
                          colors: colors,
                        ),
                      ),
                    )
                  : _TimelineStepContent(
                      status: status,
                      isCurrent: isCurrent,
                      isCompleted: isCompleted,
                      isSkipped: isSkipped,
                      isUpcoming: isUpcoming,
                      isTerminalContext: isTerminalContext,
                      stepNumber: stepNumber,
                      colors: colors,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineStepContent extends StatelessWidget {
  const _TimelineStepContent({
    required this.status,
    required this.isCurrent,
    required this.isCompleted,
    required this.isSkipped,
    required this.isUpcoming,
    required this.isTerminalContext,
    required this.stepNumber,
    required this.colors,
  });

  final AppointmentStatus status;
  final bool isCurrent;
  final bool isCompleted;
  final bool isSkipped;
  final bool isUpcoming;
  final bool isTerminalContext;
  final int stepNumber;
  final SemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              status.label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                color: isSkipped
                    ? colors.mutedForeground.withValues(alpha: 0.55)
                    : isUpcoming
                    ? colors.mutedForeground
                    : colors.foreground,
              ),
            ),
            const SizedBox(width: SpacingTokens.sm),
            if (isCurrent && !isTerminalContext)
              AppBadge(label: 'Current', variant: AppBadgeVariant.primary)
            else if (isCompleted)
              Icon(Icons.check_circle_outline_rounded, size: 16, color: colors.primary)
            else
              Text(
                'Step $stepNumber',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
              ),
          ],
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          AppointmentStatusTimeline.stepDescription(status),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isCurrent
                ? colors.foreground.withValues(alpha: 0.85)
                : isSkipped
                ? colors.mutedForeground.withValues(alpha: 0.5)
                : colors.mutedForeground,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.icon,
    required this.color,
    required this.isCurrent,
    required this.isCompleted,
    required this.isSkipped,
  });

  final IconData icon;
  final Color color;
  final bool isCurrent;
  final bool isCompleted;
  final bool isSkipped;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final size = isCurrent ? 40.0 : 36.0;

    Widget node = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted || isCurrent
            ? color.withValues(alpha: isSkipped ? 0.15 : 0.18)
            : colors.muted.withValues(alpha: 0.35),
        border: Border.all(color: isSkipped ? colors.border : color, width: isCurrent ? 2.5 : 1.5),
        boxShadow: isCurrent
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1)]
            : null,
      ),
      child: Icon(
        icon,
        size: isCurrent ? 20 : 18,
        color: isSkipped ? colors.mutedForeground.withValues(alpha: 0.5) : color,
      ),
    );

    if (isCurrent) {
      node = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 2)],
        ),
        child: node,
      );
    }

    return node;
  }
}

IconData _iconForStatus(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.scheduled => Icons.event_outlined,
    AppointmentStatus.confirmed => Icons.verified_outlined,
    AppointmentStatus.checkedIn => Icons.login_rounded,
    AppointmentStatus.inProgress => Icons.medical_services_outlined,
    AppointmentStatus.completed => Icons.task_alt_rounded,
    AppointmentStatus.cancelled => Icons.cancel_outlined,
    AppointmentStatus.noShow => Icons.person_off_outlined,
    AppointmentStatus.unknown => Icons.help_outline_rounded,
  };
}
