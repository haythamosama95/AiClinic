import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Responsive multi-column form layout matching the setup wizard reference design.
class SetupFormGrid extends StatelessWidget {
  const SetupFormGrid({
    required this.children,
    this.columns = 2,
    this.compactBreakpoint = compactBreakpointDefault,
    super.key,
  });

  static const compactBreakpointDefault = 640.0;

  /// Use inside half-width [SettingsSectionCard] grids where available width is often below [compactBreakpointDefault].
  static const settingsCardBreakpoint = 320.0;

  final List<Widget> children;
  final int columns;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < compactBreakpoint;
        final columnCount = columns.clamp(1, children.isEmpty ? 1 : children.length);

        if (isCompact) {
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
          final rowChildren = children.skip(i).take(columnCount).toList(growable: false);
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < rowChildren.length; j++) ...[
                  if (j > 0) const SizedBox(width: SpacingTokens.lg),
                  Expanded(child: rowChildren[j]),
                ],
              ],
            ),
          );
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}
