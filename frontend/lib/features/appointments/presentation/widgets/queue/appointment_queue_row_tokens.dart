import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Shared queue row and panel metrics — [AppointmentQueueScheduleColumn] is canonical.
abstract final class AppointmentQueueRowTokens {
  static const rowPadding = EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md);

  static const timeColumnWidth = 72.0;
  static const timeIconMinSize = 60.0;

  static const dividerGap = SpacingTokens.md;
  static const dividerLineHeight = 32.0;

  static const rowSeparatorGap = SpacingTokens.sm;
  static const estimatedRowHeight = 72.0;
}

/// Panel min-heights for the queue layout. Side panels stack to the schedule height on wide layouts.
abstract final class AppointmentQueuePanelHeights {
  static const schedule = 320.0;

  static const double session = (schedule - SpacingTokens.md) / 2;
  static const double waiting = (schedule - SpacingTokens.md) / 2;

  static const statsBannerWide = 94.0;
  static const statsBannerCompact = 200.0;
}

/// Centered vertical divider between queue row sections.
class AppointmentQueueSectionDivider extends StatelessWidget {
  const AppointmentQueueSectionDivider({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppointmentQueueRowTokens.dividerGap * 2 + 1,
      child: Center(
        child: SizedBox(
          height: AppointmentQueueRowTokens.dividerLineHeight,
          child: VerticalDivider(width: 1, thickness: 1, color: color.withValues(alpha: 1)),
        ),
      ),
    );
  }
}

/// Compact empty body for side queue panels (matches schedule column density).
class AppointmentQueuePanelEmptyState extends StatelessWidget {
  const AppointmentQueuePanelEmptyState({required this.icon, required this.title, required this.message, super.key});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: colors.mutedForeground),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
