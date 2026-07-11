import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/layout/shell_page_transition.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/motion/app_page_transition.dart';

/// Step-to-step transition wrapper aligned with shell page motion (web `StepPanel`).
///
/// Fade + vertical slide with wait-mode (exit then enter), plus animated height
/// when step content changes size. Respects reduced motion.
class SetupStepPanel extends StatelessWidget {
  const SetupStepPanel({required this.stepKey, required this.child, super.key});

  final String stepKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    return ClipRect(
      child: AnimatedSize(
        duration: reducedMotion ? Duration.zero : AppPageTransitionMotion.duration,
        curve: AppPageTransitionMotion.curve,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: Align(
          alignment: Alignment.topCenter,
          child: ShellPageTransition(pageKey: stepKey, child: child, builder: (context, content, _) => content),
        ),
      ),
    );
  }
}
