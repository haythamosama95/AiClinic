import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';

/// Responsive multi-column layout for settings cards.
class SettingsCardsGrid extends StatelessWidget {
  const SettingsCardsGrid({
    required this.children,
    this.columns = 2,
    this.enforceColumns = false,
    this.compactBreakpoint = 640,
    super.key,
  });

  final List<Widget> children;
  final int columns;
  final bool enforceColumns;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < compactBreakpoint;
        final maxColumns = enforceColumns ? columns : (children.isEmpty ? 1 : children.length);
        final columnCount = isCompact ? 1 : columns.clamp(1, maxColumns);

        if (columnCount == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.s6),
                children[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columnCount) {
          if (i > 0) {
            rows.add(const SizedBox(height: AppSpacing.s6));
          }
          final rowChildren = <Widget>[];
          for (var col = 0; col < columnCount; col++) {
            final index = i + col;
            rowChildren.add(
              Expanded(
                child: index < children.length ? children[index] : const SizedBox.shrink(),
              ),
            );
            if (col < columnCount - 1) {
              rowChildren.add(const SizedBox(width: AppSpacing.s6));
            }
          }
          rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren));
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}
