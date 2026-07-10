import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Shared header + body shell for Phase 1 settings placeholder screens (web `SummaryListScreen` / `NotificationsScreen`).
class EmptySettingsScreen extends StatelessWidget {
  const EmptySettingsScreen({
    required this.icon,
    required this.title,
    required this.description,
    this.emptyTitle,
    this.emptyDescription,
    this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? emptyTitle;
  final String? emptyDescription;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 20, color: colors.iconDefault),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.h2(context).copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    description,
                    style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    if (body != null) {
      return body!;
    }
    if (emptyTitle != null && emptyDescription != null) {
      return AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: emptyTitle,
        description: emptyDescription,
      );
    }
    return const SizedBox.shrink();
  }
}
