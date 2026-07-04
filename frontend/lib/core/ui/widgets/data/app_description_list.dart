import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// A single label/value pair for [AppDescriptionList].
@immutable
class AppDescriptionItem {
  const AppDescriptionItem({
    required this.label,
    required this.value,
    this.tabular = false,
  });

  final String label;
  final Widget value;
  final bool tabular;
}

/// Read-only key-value detail list with responsive one- or two-column layout.
class AppDescriptionList extends StatelessWidget {
  const AppDescriptionList({
    required this.items,
    this.columns = 2,
    super.key,
  });

  final List<AppDescriptionItem> items;

  /// Desired column count; two columns collapse to one on narrow widths.
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns =
            columns == 2 && constraints.maxWidth >= AppBreakpoints.sm;

        if (!useTwoColumns) {
          return _ItemColumn(items: items);
        }

        return Wrap(
          spacing: AppSpacing.s4,
          runSpacing: AppSpacing.s4,
          children: [
            for (final item in items)
              SizedBox(
                width: (constraints.maxWidth - AppSpacing.s4) / 2,
                child: _DescriptionEntry(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _ItemColumn extends StatelessWidget {
  const _ItemColumn({required this.items});

  final List<AppDescriptionItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s4),
          _DescriptionEntry(item: items[i]),
        ],
      ],
    );
  }
}

class _DescriptionEntry extends StatelessWidget {
  const _DescriptionEntry({required this.item});

  final AppDescriptionItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final valueStyle = item.tabular
        ? typography.tabular(typography.body)
        : typography.body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: typography.caption.copyWith(color: colors.textTertiary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s1),
        DefaultTextStyle(
          style: valueStyle.copyWith(color: colors.textPrimary),
          child: item.value,
        ),
      ],
    );
  }
}
