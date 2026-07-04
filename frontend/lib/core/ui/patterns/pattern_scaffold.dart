import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Shared responsive helpers for page-template patterns.
abstract final class PatternScaffold {
  /// Page gutter padding — `space-4` on narrow, `space-6` from [AppBreakpoints.sm].
  static EdgeInsetsDirectional pagePadding(double width) {
    final horizontal = width >= AppBreakpoints.sm
        ? AppSpacing.s6
        : AppSpacing.s4;
    return EdgeInsetsDirectional.all(horizontal);
  }

  /// Vertical rhythm between major sections (`space-8`).
  static const double sectionGap = AppSpacing.s8;

  /// Gap between header and toolbar (`space-4`).
  static const double headerToolbarGap = AppSpacing.s4;

  /// Metric card columns: N → 2 → 1 across breakpoints.
  static int metricColumns(double width) {
    if (width >= AppBreakpoints.xl) return 4;
    if (width >= AppBreakpoints.sm) return 2;
    return 1;
  }

  /// Chart grid columns: 2 on large, 1 below.
  static int chartColumns(double width) =>
      width >= AppBreakpoints.lg ? 2 : 1;

  /// Master–detail split layout from [AppBreakpoints.lg] upward.
  static bool useSplitLayout(double width) => width >= AppBreakpoints.lg;

  /// Workspace multi-pane layout from [AppBreakpoints.lg] upward.
  static bool useWorkspaceSplit(double width) => width >= AppBreakpoints.lg;

  /// Editor form two-column field layout from [AppBreakpoints.md] upward.
  static bool useFormTwoColumn(double width) => width >= AppBreakpoints.md;
}

/// Responsive grid for a list of equally weighted children.
class PatternResponsiveGrid extends StatelessWidget {
  const PatternResponsiveGrid({
    required this.children,
    required this.columnCountForWidth,
    this.gap = AppSpacing.s4,
    super.key,
  });

  final List<Widget> children;
  final int Function(double width) columnCountForWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnCountForWidth(constraints.maxWidth).clamp(1, 12);
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}
