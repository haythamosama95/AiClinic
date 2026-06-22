import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Color-coded status pill for schedule rows.
class AppointmentQueueStatusBadge extends StatelessWidget {
  const AppointmentQueueStatusBadge({required this.status, super.key});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final tone = AppointmentQueueDisplay.scheduleBadgeTone(status);
    final (background, foreground) = switch (tone) {
      AppBadgeTone.neutral => (colors.muted, colors.mutedForeground),
      AppBadgeTone.info => (colors.primary.withValues(alpha: 0.12), colors.primary),
      AppBadgeTone.success => (const Color(0xFF059669).withValues(alpha: 0.12), const Color(0xFF059669)),
      AppBadgeTone.warning => (const Color(0xFFEA580C).withValues(alpha: 0.12), const Color(0xFFEA580C)),
      AppBadgeTone.destructive => (colors.destructive.withValues(alpha: 0.12), colors.destructive),
      AppBadgeTone.muted => (colors.muted.withValues(alpha: 0.5), colors.mutedForeground),
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs / 2),
        child: Text(
          AppointmentQueueDisplay.scheduleBadgeLabel(status),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600, fontSize: 11),
        ),
      ),
    );
  }
}
