import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Status badge for dashboard appointment rows.
class DashboardAppointmentBadge extends StatelessWidget {
  const DashboardAppointmentBadge({required this.status, super.key});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = AppointmentQueueDisplay.scheduleBadgeTone(status);
    return AppBadge(
      variant: AppBadgeVariant.soft,
      color: _badgeColorForTone(tone),
      label: AppointmentQueueDisplay.scheduleBadgeLabel(status),
    );
  }
}

AppBadgeColor _badgeColorForTone(AppBadgeTone tone) {
  return switch (tone) {
    AppBadgeTone.neutral || AppBadgeTone.muted => AppBadgeColor.neutral,
    AppBadgeTone.info => AppBadgeColor.info,
    AppBadgeTone.success => AppBadgeColor.success,
    AppBadgeTone.warning => AppBadgeColor.warning,
    AppBadgeTone.destructive => AppBadgeColor.danger,
  };
}
