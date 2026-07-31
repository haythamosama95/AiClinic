import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// A label/value pair for [AppDescriptionList] (web `DescriptionItem`).
class DescriptionItem {
  const DescriptionItem({
    required this.label,
    required this.value,
    this.tabular = false,
  });

  final String label;
  final Widget value;
  final bool tabular;
}

/// Definition list for read-only label/value pairs (web `DescriptionList`).
class AppDescriptionList extends StatelessWidget {
  const AppDescriptionList({
    required this.items,
    this.columns = 2,
    super.key,
  });

  final List<DescriptionItem> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    assert(columns == 1 || columns == 2, 'columns must be 1 or 2');

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = AppSpacing.space4;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing) / 2;

        return Semantics(
          container: true,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final item in items)
                SizedBox(
                  width: itemWidth,
                  child: _DescriptionListEntry(item: item),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DescriptionListEntry extends StatelessWidget {
  const _DescriptionListEntry({required this.item});

  final DescriptionItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final valueStyle = AppTypography.body(context).copyWith(
      color: colors.textPrimary,
      fontFeatures: item.tabular ? const [FontFeature.tabularFigures()] : null,
    );

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              item.label,
              style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
            ),
          ),
          const SizedBox(height: AppSpacing.space1),
          DefaultTextStyle(
            style: valueStyle,
            child: item.value,
          ),
        ],
      ),
    );
  }
}
