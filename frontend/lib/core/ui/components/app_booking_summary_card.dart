import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// A labeled value row inside [AppBookingSummaryCard].
class AppBookingSummaryItem {
  const AppBookingSummaryItem({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;
}

/// Read-only booking details summary (web step-1 bottom card).
class AppBookingSummaryCard extends StatelessWidget {
  const AppBookingSummaryCard({required this.items, this.layout = AppBookingSummaryLayout.responsive, super.key});

  final List<AppBookingSummaryItem> items;
  final AppBookingSummaryLayout layout;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = switch (layout) {
              AppBookingSummaryLayout.responsive => constraints.maxWidth >= 480 ? 3 : 1,
              AppBookingSummaryLayout.grid2 => constraints.maxWidth >= 280 ? 2 : 1,
            };
            final spacing = AppSpacing.space3;
            final itemWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in items)
                  SizedBox(
                    width: itemWidth,
                    child: _SummaryRow(item: item, colors: colors, compact: layout == AppBookingSummaryLayout.grid2),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Column layout for [AppBookingSummaryCard].
enum AppBookingSummaryLayout {
  /// Three columns on wide surfaces, one on narrow (step 1).
  responsive,

  /// Two-by-two grid on wide surfaces (confirmation step).
  grid2,
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.item, required this.colors, this.compact = false});

  final AppBookingSummaryItem item;
  final AppSemanticColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(item.icon, size: compact ? 20 : 22, color: colors.iconMuted),
        const SizedBox(width: AppSpacing.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label.toUpperCase(),
                style: AppTypography.caption(context).copyWith(color: colors.textTertiary, letterSpacing: 0.4),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
