import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Responsive two-column form layout matching the setup wizard reference design.
class SetupFormGrid extends StatelessWidget {
  const SetupFormGrid({required this.children, this.compactBreakpoint = compactBreakpointDefault, super.key});

  static const compactBreakpointDefault = 640.0;

  final List<Widget> children;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < compactBreakpoint;

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
        for (var i = 0; i < children.length; i += 2) {
          if (i > 0) {
            rows.add(const SizedBox(height: SpacingTokens.lg));
          }
          final left = children[i];
          final right = i + 1 < children.length ? children[i + 1] : const SizedBox.shrink();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: SpacingTokens.lg),
                Expanded(child: right),
              ],
            ),
          );
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}
