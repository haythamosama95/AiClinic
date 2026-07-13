import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_timeline.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_status_actions.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_motion.dart';

/// Visual timeline of appointment lifecycle statuses with the current step highlighted.
class AppointmentStatusTimelineWidget extends StatelessWidget {
  const AppointmentStatusTimelineWidget({
    required this.detail,
    required this.siblingAppointments,
    required this.shiftLookup,
    required this.onChanged,
    super.key,
  });

  final AppointmentDetail detail;
  final List<AppointmentListItem> siblingAppointments;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final VoidCallback onChanged;

  AppointmentStatus get currentStatus => detail.status;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault),
        boxShadow: [
          BoxShadow(color: colors.textPrimary.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 520;
                final titleSection = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.route_outlined, size: 20, color: colors.textLink),
                    const SizedBox(width: AppSpacing.space2),
                    Expanded(
                      child: Wrap(
                        spacing: AppSpacing.space2,
                        runSpacing: AppSpacing.space1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Status journey',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (progressLabel != null) AppBadge(label: progressLabel, variant: BadgeVariant.outline),
                        ],
                      ),
                    ),
                  ],
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleSection,
                      const SizedBox(height: AppSpacing.space2),
                      AppointmentDetailStatusActions(
                        detail: detail,
                        siblingAppointments: siblingAppointments,
                        shiftLookup: shiftLookup,
                        onChanged: onChanged,
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.route_outlined, size: 20, color: colors.textLink),
                    const SizedBox(width: AppSpacing.space2),
                    Expanded(
                      flex: 2,
                      child: Wrap(
                        spacing: AppSpacing.space2,
                        runSpacing: AppSpacing.space1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Status journey',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (progressLabel != null) AppBadge(label: progressLabel, variant: BadgeVariant.outline),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    Expanded(
                      flex: 3,
                      child: AppointmentDetailStatusActions(
                        detail: detail,
                        siblingAppointments: siblingAppointments,
                        shiftLookup: shiftLookup,
                        onChanged: onChanged,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              isTerminal
                  ? 'This appointment ended before completion.'
                  : 'Track where this appointment is in the clinic workflow.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space6),
            LayoutBuilder(
              builder: (context, constraints) {
                final useHorizontal = constraints.maxWidth >= 640;
                final timeline = useHorizontal
                    ? _HorizontalStatusTimeline(currentStatus: currentStatus, isTerminal: isTerminal)
                    : _VerticalStatusTimeline(currentStatus: currentStatus, isTerminal: isTerminal);

                if (!isTerminal) {
                  return timeline;
                }

                return _TerminalTimelineOverlay(status: currentStatus, child: timeline);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades the lifecycle timeline and centers the terminal status on top.
class _TerminalTimelineOverlay extends StatelessWidget {
  const _TerminalTimelineOverlay({required this.status, required this.child});

  final AppointmentStatus status;
  final Widget child;

  static const double _timelineOpacity = 0.15;

  @override
  Widget build(BuildContext context) {
    final statusColor = AppointmentCalendarDisplay.statusColor(status, Theme.of(context).brightness);
    final motionDuration = AppointmentStatusMotion.durationOf(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedOpacity(
          duration: motionDuration,
          curve: AppointmentStatusMotion.curve,
          opacity: _timelineOpacity,
          child: IgnorePointer(child: child),
        ),
        Positioned.fill(
          child: _TerminalStatusCard(status: status, statusColor: statusColor),
        ),
      ],
    );
  }
}

class _TerminalStatusCard extends StatelessWidget {
  const _TerminalStatusCard({required this.status, required this.statusColor});

  final AppointmentStatus status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final motionDuration = AppointmentStatusMotion.durationOf(context);

    return AnimatedContainer(
      duration: motionDuration,
      curve: AppointmentStatusMotion.curve,
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceDefault.withValues(alpha: 0.94),
        gradient: LinearGradient(
          colors: [statusColor.withValues(alpha: 0.14), statusColor.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: statusColor.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: colors.textPrimary.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: AppSpacing.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedAppointmentStatusColor(
                color: statusColor,
                builder: (context, color) => Icon(_iconForStatus(status), color: color, size: 32),
              ),
              const SizedBox(height: AppSpacing.space2),
              AnimatedDefaultTextStyle(
                duration: motionDuration,
                curve: AppointmentStatusMotion.curve,
                style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                textAlign: TextAlign.center,
                child: Text(status.label, textAlign: TextAlign.center),
              ),
              const SizedBox(height: AppSpacing.space1),
              Text(
                AppointmentStatusTimeline.stepDescription(status),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: AppSpacing.space2),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizontalStatusTimeline extends StatelessWidget {
  const _HorizontalStatusTimeline({required this.currentStatus, required this.isTerminal});

  final AppointmentStatus currentStatus;
  final bool isTerminal;

  @override
  Widget build(BuildContext context) {
    final steps = AppointmentStatusTimeline.mainFlow;
    final currentIndex = isTerminal ? -1 : steps.indexOf(currentStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final stepCount = steps.length;
            final segmentWidth = width / stepCount;
            const trackHeight = _HorizontalTimelineTrack.trackHeight;
            const nodeSize = _HorizontalTimelineTrack.nodeSize;
            const nodeRadius = nodeSize / 2;
            const connectorThickness = 2.0;
            final connectorTop = (trackHeight - connectorThickness) / 2;
            final connectorSpan = segmentWidth - nodeSize;

            return SizedBox(
              height: trackHeight,
              width: width,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (stepCount > 1)
                    for (var index = 0; index < stepCount - 1; index++)
                      Positioned(
                        left: segmentWidth * (index + 0.5) + nodeRadius,
                        top: connectorTop,
                        width: connectorSpan,
                        child: _HorizontalTimelineConnector(
                          fromStatus: steps[index],
                          isActive: !isTerminal && currentIndex > index,
                        ),
                      ),
                  for (var index = 0; index < stepCount; index++)
                    Positioned(
                      left: segmentWidth * index + (segmentWidth - nodeSize) / 2,
                      top: (trackHeight - nodeSize) / 2,
                      child: _HorizontalTimelineNode(
                        status: steps[index],
                        stepState: AppointmentStatusTimeline.stepState(current: currentStatus, step: steps[index]),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.space4),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < steps.length; index++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : AppSpacing.space1,
                      right: index == steps.length - 1 ? 0 : AppSpacing.space1,
                    ),
                    child: _HorizontalStepCard(
                      status: steps[index],
                      stepState: AppointmentStatusTimeline.stepState(current: currentStatus, step: steps[index]),
                      isTerminalContext: isTerminal,
                      stepNumber: index + 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HorizontalTimelineTrack {
  const _HorizontalTimelineTrack._();

  static const double trackHeight = 44;
  static const double nodeSize = 36;
}

class _HorizontalTimelineConnector extends StatelessWidget {
  const _HorizontalTimelineConnector({required this.fromStatus, required this.isActive});

  final AppointmentStatus fromStatus;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final statusColor = AppointmentCalendarDisplay.statusColor(fromStatus, Theme.of(context).brightness);
    final motionDuration = AppointmentStatusMotion.durationOf(context);

    return AnimatedContainer(
      duration: motionDuration,
      curve: AppointmentStatusMotion.curve,
      height: 2,
      color: isActive ? statusColor.withValues(alpha: 0.75) : colors.borderDefault,
    );
  }
}

class _HorizontalTimelineNode extends StatelessWidget {
  const _HorizontalTimelineNode({required this.status, required this.stepState});

  final AppointmentStatus status;
  final AppointmentTimelineStepState stepState;

  static const double _nodeSize = _HorizontalTimelineTrack.nodeSize;

  @override
  Widget build(BuildContext context) {
    final isCurrent = stepState == AppointmentTimelineStepState.current;
    final isCompleted = stepState == AppointmentTimelineStepState.completed;
    final isSkipped = stepState == AppointmentTimelineStepState.skipped;

    final statusColor = AppointmentCalendarDisplay.statusColor(status, Theme.of(context).brightness);
    final nodeColor = isSkipped
        ? statusColor.withValues(alpha: 0.35)
        : isCurrent || isCompleted
        ? statusColor
        : statusColor.withValues(alpha: 0.5);

    return _TimelineNode(
      icon: isCompleted ? Icons.check_rounded : _iconForStatus(status),
      color: nodeColor,
      statusColor: statusColor,
      isCurrent: isCurrent,
      isCompleted: isCompleted,
      isSkipped: isSkipped,
      fixedSize: _nodeSize,
    );
  }
}

class _HorizontalStepCard extends StatelessWidget {
  const _HorizontalStepCard({
    required this.status,
    required this.stepState,
    required this.isTerminalContext,
    required this.stepNumber,
  });

  final AppointmentStatus status;
  final AppointmentTimelineStepState stepState;
  final bool isTerminalContext;
  final int stepNumber;

  @override
  Widget build(BuildContext context) {
    final isCurrent = stepState == AppointmentTimelineStepState.current;
    final isCompleted = stepState == AppointmentTimelineStepState.completed;
    final isSkipped = stepState == AppointmentTimelineStepState.skipped;
    final isUpcoming = stepState == AppointmentTimelineStepState.upcoming;

    return _StatusStepCard(
      status: status,
      stepState: stepState,
      isTerminalContext: isTerminalContext,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space2 + AppSpacing.space1,
      ),
      child: _TimelineStepContent(
        status: status,
        isCurrent: isCurrent,
        isCompleted: isCompleted,
        isSkipped: isSkipped,
        isUpcoming: isUpcoming,
        isTerminalContext: isTerminalContext,
        stepNumber: stepNumber,
        colors: context.appColors,
        compact: true,
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
    final currentIndex = isTerminal ? -1 : steps.indexOf(currentStatus);

    return Column(
      children: [
        for (var index = 0; index < steps.length; index++)
          _TimelineStepRow(
            status: steps[index],
            stepState: AppointmentStatusTimeline.stepState(current: currentStatus, step: steps[index]),
            isTerminalContext: isTerminal,
            isLast: index == steps.length - 1,
            stepNumber: index + 1,
            stepIndex: index,
            currentIndex: currentIndex,
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
    required this.stepIndex,
    required this.currentIndex,
  });

  final AppointmentStatus status;
  final AppointmentTimelineStepState stepState;
  final bool isTerminalContext;
  final bool isLast;
  final int stepNumber;
  final int stepIndex;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final statusColor = AppointmentCalendarDisplay.statusColor(status, Theme.of(context).brightness);
    final isCurrent = stepState == AppointmentTimelineStepState.current;
    final isCompleted = stepState == AppointmentTimelineStepState.completed;
    final isSkipped = stepState == AppointmentTimelineStepState.skipped;
    final isUpcoming = stepState == AppointmentTimelineStepState.upcoming;

    final nodeColor = isSkipped
        ? statusColor.withValues(alpha: 0.35)
        : isCurrent || isCompleted
        ? statusColor
        : statusColor.withValues(alpha: 0.5);

    final connectorActive = !isTerminalContext && !isLast && currentIndex > stepIndex;
    final motionDuration = AppointmentStatusMotion.durationOf(context);

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
                  statusColor: statusColor,
                  isCurrent: isCurrent,
                  isCompleted: isCompleted,
                  isSkipped: isSkipped,
                ),
                if (!isLast)
                  Expanded(
                    child: AnimatedContainer(
                      duration: motionDuration,
                      curve: AppointmentStatusMotion.curve,
                      width: 2,
                      color: connectorActive ? statusColor.withValues(alpha: 0.75) : colors.borderDefault,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.space6),
              child: _StatusStepCard(
                status: status,
                stepState: stepState,
                isTerminalContext: isTerminalContext,
                padding: const EdgeInsets.all(AppSpacing.space4),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStepCard extends StatelessWidget {
  const _StatusStepCard({
    required this.status,
    required this.stepState,
    required this.isTerminalContext,
    required this.padding,
    required this.child,
  });

  final AppointmentStatus status;
  final AppointmentTimelineStepState stepState;
  final bool isTerminalContext;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isCurrent = stepState == AppointmentTimelineStepState.current;
    final useAnimatedBorder = isCurrent && !isTerminalContext;
    final motionDuration = AppointmentStatusMotion.durationOf(context);
    final brightness = Theme.of(context).brightness;
    final style = AppointmentCalendarDisplay.statusStyle(status, brightness);

    final card = AnimatedContainer(
      duration: motionDuration,
      curve: AppointmentStatusMotion.curve,
      decoration: _statusStepCardDecoration(
        context: context,
        status: status,
        stepState: stepState,
        includeBorder: !useAnimatedBorder,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (!useAnimatedBorder) {
      return card;
    }

    return AppAnimatedBorderCard(
      active: true,
      borderColor: style.border,
      highlightColor: style.accent,
      borderRadius: AppRadius.md,
      borderWidth: 1.5,
      child: card,
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
    this.compact = false,
  });

  final AppointmentStatus status;
  final bool isCurrent;
  final bool isCompleted;
  final bool isSkipped;
  final bool isUpcoming;
  final bool isTerminalContext;
  final int stepNumber;
  final AppSemanticColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTypography.bodyStrong(context).copyWith(
      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
      color: isSkipped
          ? colors.textSecondary.withValues(alpha: 0.55)
          : isUpcoming
          ? colors.textSecondary
          : colors.textPrimary,
    );

    final statusIndicator = isCurrent && !isTerminalContext
        ? const AppBadge(label: 'Current', variant: BadgeVariant.soft, color: BadgeColor.info, size: BadgeSize.sm)
        : isCompleted
        ? const AppBadge(label: 'Done', variant: BadgeVariant.outline, size: BadgeSize.sm)
        : AppBadge(label: 'Step $stepNumber', variant: BadgeVariant.outline, size: BadgeSize.sm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(status.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: labelStyle),
              const SizedBox(height: AppSpacing.space1),
              statusIndicator,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(status.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
              ),
              const SizedBox(width: AppSpacing.space1),
              statusIndicator,
            ],
          ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          AppointmentStatusTimeline.stepDescription(status),
          style: AppTypography.bodySm(context).copyWith(
            color: isCurrent
                ? colors.textPrimary.withValues(alpha: 0.85)
                : isSkipped
                ? colors.textSecondary.withValues(alpha: 0.5)
                : colors.textSecondary,
            height: compact ? 1.5 : 1.45,
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
    required this.statusColor,
    required this.isCurrent,
    required this.isCompleted,
    required this.isSkipped,
    this.fixedSize,
  });

  final IconData icon;
  final Color color;
  final Color statusColor;
  final bool isCurrent;
  final bool isCompleted;
  final bool isSkipped;
  final double? fixedSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final size = fixedSize ?? (isCurrent ? 40.0 : 36.0);
    final iconSize = fixedSize != null ? 18.0 : (isCurrent ? 20.0 : 18.0);
    final motionDuration = AppointmentStatusMotion.durationOf(context);

    final fillStrength = isSkipped ? 0.1 : (isCompleted || isCurrent ? 0.2 : 0.08);
    final backgroundColor = Color.lerp(colors.surfaceDefault, statusColor, fillStrength)!;

    Widget node = AnimatedContainer(
      duration: motionDuration,
      curve: AppointmentStatusMotion.curve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(
          color: isSkipped ? statusColor.withValues(alpha: 0.22) : color,
          width: isCurrent ? 2.5 : 1.5,
        ),
        boxShadow: isCurrent
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1)]
            : null,
      ),
      child: Center(
        child: AnimatedAppointmentStatusColor(
          color: isSkipped ? colors.textSecondary.withValues(alpha: 0.5) : color,
          builder: (context, animatedColor) => Icon(icon, size: iconSize, color: animatedColor),
        ),
      ),
    );

    if (isCurrent) {
      node = AnimatedContainer(
        duration: motionDuration,
        curve: AppointmentStatusMotion.curve,
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

BoxDecoration _statusStepCardDecoration({
  required BuildContext context,
  required AppointmentStatus status,
  required AppointmentTimelineStepState stepState,
  bool includeBorder = true,
}) {
  final brightness = Theme.of(context).brightness;
  final colors = context.appColors;
  final style = AppointmentCalendarDisplay.statusStyle(status, brightness);
  final isCurrent = stepState == AppointmentTimelineStepState.current;
  final isDark = brightness == Brightness.dark;

  final gradientStrength = switch (stepState) {
    AppointmentTimelineStepState.current => 1.0,
    AppointmentTimelineStepState.completed => 0.9,
    AppointmentTimelineStepState.upcoming => 0.62,
    AppointmentTimelineStepState.skipped => 0.38,
  };

  final borderAlpha = switch (stepState) {
    AppointmentTimelineStepState.current => isDark ? 0.55 : 0.58,
    AppointmentTimelineStepState.completed => isDark ? 0.42 : 0.48,
    AppointmentTimelineStepState.upcoming => isDark ? 0.3 : 0.34,
    AppointmentTimelineStepState.skipped => isDark ? 0.22 : 0.26,
  };

  Color blendGradient(Color tone) => Color.lerp(colors.surfaceDefault, tone, gradientStrength)!;

  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [blendGradient(style.gradientStart), blendGradient(style.gradientEnd)],
    ),
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: includeBorder
        ? Border.all(
            color: style.border.withValues(alpha: borderAlpha),
            width: isCurrent ? 1.5 : 1,
          )
        : null,
    boxShadow: [
      BoxShadow(
        color: style.accent.withValues(alpha: isCurrent ? (isDark ? 0.18 : 0.12) : (isDark ? 0.08 : 0.05)),
        blurRadius: isCurrent ? 14 : 6,
        offset: Offset(0, isCurrent ? 4 : 1.5),
      ),
    ],
  );
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
