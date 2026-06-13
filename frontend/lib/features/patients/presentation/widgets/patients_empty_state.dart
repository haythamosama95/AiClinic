import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Empty state variants for the patients list.
class PatientsEmptyState extends StatelessWidget {
  const PatientsEmptyState({
    this.title = 'No patients match your search criteria',
    this.subtitle = 'Try adjusting your filters or search terms.',
    this.icon = Icons.person_search_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  const PatientsEmptyState.noPatientsYet({this.onAction, super.key})
    : title = 'No patients yet',
      subtitle = 'Get started by registering your first patient.',
      icon = Icons.people_outline,
      actionLabel = 'Add New Patient';

  final String title;
  final String subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.muted.withValues(alpha: 0.45), shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.lg),
                child: Icon(icon, size: 36, color: colors.mutedForeground),
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: SpacingTokens.lg),
              AppButton(
                label: actionLabel!,
                expand: false,
                size: AppFieldSize.sm,
                icon: const Icon(Icons.add, size: 18),
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
