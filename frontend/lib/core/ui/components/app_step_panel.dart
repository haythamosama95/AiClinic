import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/layout/shell_page_transition.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/motion/app_page_transition.dart';

/// Multi-step panel with animated height and wait-mode step transitions
/// (web `StepPanel`).
///
/// Fades and slides step content while [AnimatedSize] tweens height between steps.
/// Respects reduced motion preferences.
class AppStepPanel extends StatelessWidget {
  const AppStepPanel({required this.stepKey, required this.child, super.key});

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
