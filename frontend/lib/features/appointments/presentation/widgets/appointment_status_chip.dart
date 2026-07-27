import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Shared status badge for appointment surfaces (calendar tiles, detail page, etc.).
class AppointmentStatusChip extends StatelessWidget {
  const AppointmentStatusChip({required this.status, required this.textColor, this.compact = false, super.key});

  final AppointmentStatus status;
  final Color textColor;
  final bool compact;

  static IconData iconFor(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => Icons.event_outlined,
      AppointmentStatus.confirmed => Icons.event_available_outlined,
      AppointmentStatus.checkedIn => Icons.how_to_reg_outlined,
      AppointmentStatus.inProgress => Icons.play_circle_outline,
      AppointmentStatus.completed => Icons.check_circle_outline,
      AppointmentStatus.cancelled => Icons.cancel_outlined,
      AppointmentStatus.noShow => Icons.person_off_outlined,
      AppointmentStatus.unknown => Icons.help_outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 11.0 : 13.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: textColor.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.space2 : AppSpacing.space3,
          vertical: compact ? AppSpacing.space1 : AppSpacing.space2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(status), size: iconSize, color: textColor.withValues(alpha: 0.92)),
            const SizedBox(width: AppSpacing.space1),
            Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption(context).copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
                height: 1.1,
                fontSize: compact ? 10 : null,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
