import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_toolbar.dart';

/// Appointment status chip for queue surfaces (web `StatusBadge`).
///
/// Maps [AppointmentStatus] only — no web `arrived` state. Tone comes from
/// [AppointmentQueueDisplay.scheduleBadgeTone]; labels match web `STATUS_LABELS`
/// (plus `confirmed`, which has no web label).
class QueueStatusBadge extends StatelessWidget {
  const QueueStatusBadge({
    required this.status,
    this.size = BadgeSize.sm,
    super.key,
  });

  final AppointmentStatus status;
  final BadgeSize size;

  @override
  Widget build(BuildContext context) {
    final tone = AppointmentQueueDisplay.scheduleBadgeTone(status);
    final label = _labelFor(status);
    final iconSize = size == BadgeSize.sm ? 12.0 : 14.0;

    return Semantics(
      label: 'Status: $label',
      child: AppBadge(
        size: size,
        variant: BadgeVariant.soft,
        color: _badgeColorForTone(tone),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForStatus(status),
              size: iconSize,
            ),
            const SizedBox(width: AppSpacing.space1),
            Text(label),
          ],
        ),
      ),
    );
  }

  static String _labelFor(AppointmentStatus status) {
    return queueToolbarStatusLabels[status] ??
        AppointmentQueueDisplay.scheduleBadgeLabel(status);
  }

  static IconData _iconForStatus(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => Icons.calendar_today,
      AppointmentStatus.confirmed => Icons.login,
      AppointmentStatus.checkedIn => Icons.schedule,
      AppointmentStatus.inProgress => Icons.medical_services,
      AppointmentStatus.completed => Icons.check_circle,
      AppointmentStatus.cancelled => Icons.cancel,
      AppointmentStatus.noShow => Icons.person_off,
      AppointmentStatus.unknown => Icons.help_outline,
    };
  }

  static BadgeColor _badgeColorForTone(AppBadgeTone tone) {
    return switch (tone) {
      AppBadgeTone.neutral => BadgeColor.neutral,
      AppBadgeTone.info => BadgeColor.info,
      AppBadgeTone.success => BadgeColor.success,
      AppBadgeTone.warning => BadgeColor.warning,
      AppBadgeTone.destructive => BadgeColor.danger,
      AppBadgeTone.muted => BadgeColor.neutral,
    };
  }
}
