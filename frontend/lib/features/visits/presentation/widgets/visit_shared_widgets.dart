import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

/// Shared visit status badge and color helpers for visit screens.
abstract final class VisitStatusDisplay {
  static Color statusColor(VisitStatus status, SemanticColors colors) => switch (status) {
    VisitStatus.inProgress => colors.primary,
    VisitStatus.completed => colors.accent,
  };

  static AppBadgeVariant badgeVariant(VisitStatus status) => switch (status) {
    VisitStatus.inProgress => AppBadgeVariant.primary,
    VisitStatus.completed => AppBadgeVariant.accent,
  };
}

/// Hero summary card for visit date, doctor, and status.
class VisitHeroCard extends StatelessWidget {
  const VisitHeroCard({
    required this.dateLabel,
    required this.doctorName,
    required this.status,
    super.key,
  });

  final String dateLabel;
  final String doctorName;
  final VisitStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final statusColor = VisitStatusDisplay.statusColor(status, colors);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Visit',
                        style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground),
                      ),
                      const SizedBox(height: SpacingTokens.xs),
                      Text(
                        dateLabel,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                AppBadge(
                  label: status.label,
                  variant: VisitStatusDisplay.badgeVariant(status),
                  icon: Icon(
                    status == VisitStatus.inProgress ? Icons.edit_note_outlined : Icons.check_circle_outline,
                    size: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.md),
            _HeroFactRow(
              icon: Icons.person_outline_rounded,
              label: 'Doctor',
              value: doctorName,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroFactRow extends StatelessWidget {
  const _HeroFactRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground)),
              Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Section card wrapper for visit documentation blocks.
class VisitSectionCard extends StatelessWidget {
  const VisitSectionCard({
    required this.title,
    required this.child,
    this.description,
    this.headerActions,
    super.key,
  });

  final String title;
  final String? description;
  final Widget child;
  final List<Widget>? headerActions;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      description: description == null ? null : Text(description!),
      actions: headerActions,
      child: child,
    );
  }
}

/// Read-only label/value pair for visit detail sections.
class VisitDetailField extends StatelessWidget {
  const VisitDetailField({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final display = value.trim().isEmpty ? '—' : value.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground)),
          const SizedBox(height: SpacingTokens.xs),
          Text(display, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
