import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Responsive multi-column layout for settings cards.
class SettingsCardsGrid extends StatelessWidget {
  const SettingsCardsGrid({
    required this.children,
    this.columns = 2,
    this.enforceColumns = false,
    this.compactBreakpoint = compactBreakpointDefault,
    super.key,
  });

  static const compactBreakpointDefault = 640.0;

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
                if (i > 0) const SizedBox(height: SpacingTokens.lg),
                children[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columnCount) {
          if (i > 0) {
            rows.add(const SizedBox(height: SpacingTokens.lg));
          }
          final rowChildren = <Widget>[];
          for (var col = 0; col < columnCount; col++) {
            final index = i + col;
            if (col > 0) {
              rowChildren.add(const SizedBox(width: SpacingTokens.lg));
            }
            rowChildren.add(Expanded(child: index < children.length ? children[index] : const SizedBox.shrink()));
          }
          rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren));
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}
