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

            if (columns == 1) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    if (index > 0) SizedBox(height: spacing),
                    _SummaryRow(item: items[index], colors: colors, compact: layout == AppBookingSummaryLayout.grid2),
                  ],
                ],
              );
            }

            final rows = <List<AppBookingSummaryItem>>[];
            for (var index = 0; index < items.length; index += columns) {
              final end = (index + columns).clamp(0, items.length);
              rows.add(items.sublist(index, end));
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
                  if (rowIndex > 0) SizedBox(height: spacing),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < rows[rowIndex].length; index++) ...[
                          if (index > 0) _FadingVerticalDivider(color: colors.borderDefault, width: spacing),
                          Expanded(
                            child: Center(
                              child: _SummaryRow(
                                item: rows[rowIndex][index],
                                colors: colors,
                                compact: layout == AppBookingSummaryLayout.grid2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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

class _FadingVerticalDivider extends StatelessWidget {
  const _FadingVerticalDivider({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
              stops: const [0, 0.5, 1],
            ),
          ),
          child: const SizedBox(width: 1, height: double.infinity),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.item, required this.colors, this.compact = false});

  final AppBookingSummaryItem item;
  final AppSemanticColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 20.0 : 22.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(item.icon, size: iconSize, color: colors.iconMuted),
            const SizedBox(width: AppSpacing.space3),
            Text(
              item.label.toUpperCase(),
              style: AppTypography.caption(context).copyWith(color: colors.textTertiary, letterSpacing: 0.4),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          item.value,
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
