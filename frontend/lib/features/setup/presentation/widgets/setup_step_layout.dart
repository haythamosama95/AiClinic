import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Viewports below this height use page-level scrolling; taller screens grow the modal instead.
abstract final class SetupLayoutBreakpoints {
  static const compactViewportHeight = 760.0;
}

/// Wizard step chrome: body and optional actions stacked at natural height.
class SetupStepLayout extends StatelessWidget {
  const SetupStepLayout({required this.body, this.actions, super.key});

  final Widget body;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final actionsWidget = actions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        body,
        if (actionsWidget != null) ...[const SizedBox(height: SpacingTokens.xl), actionsWidget],
      ],
    );
  }
}
