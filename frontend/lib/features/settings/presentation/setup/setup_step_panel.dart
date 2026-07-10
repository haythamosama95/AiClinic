import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/layout/shell_page_transition.dart';

/// Step-to-step transition wrapper aligned with shell page motion (web `StepPanel`).
///
/// Fade + vertical slide with wait-mode (exit then enter). Respects reduced motion.
class SetupStepPanel extends StatelessWidget {
  const SetupStepPanel({required this.stepKey, required this.child, super.key});

  final String stepKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShellPageTransition(pageKey: stepKey, child: child, builder: (context, content, _) => content);
  }
}
