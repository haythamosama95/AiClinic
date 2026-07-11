import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Shared enter transition for collapsed setup summary cards.
class CollapsedSummaryEnterTransition extends StatelessWidget {
  const CollapsedSummaryEnterTransition({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final duration = AppMotion.resolveDurationFromTokens(
      context: context,
      duration: AppMotionDurationToken.quick,
      ease: AppMotionEasingToken.out,
    );

    return TweenAnimationBuilder<double>(
      duration: reducedMotion ? Duration.zero : duration,
      curve: AppMotion.resolveCurveFromTokens(context: context, ease: AppMotionEasingToken.out),
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, -8 * (1 - value)), child: child),
        );
      },
      child: child,
    );
  }
}

const kSetupSaveMinLoadingDuration = AppMotionDuration.base;
