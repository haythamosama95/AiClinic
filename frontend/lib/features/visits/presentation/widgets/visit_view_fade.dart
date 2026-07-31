import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Top-level view swap with opacity-only transition (web `AnimatePresence mode="wait"`).
class VisitViewFade extends StatelessWidget {
  const VisitViewFade({
    required this.viewKey,
    required this.child,
    super.key,
  });

  final String viewKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    return AnimatedSwitcher(
      duration: reducedMotion ? Duration.zero : AppMotion.base,
      switchInCurve: AppMotionEasing.out,
      switchOutCurve: AppMotionEasing.out,
      transitionBuilder: (child, animation) {
        return Opacity(opacity: animation.value, child: child);
      },
      child: KeyedSubtree(
        key: ValueKey<String>(viewKey),
        child: child,
      ),
    );
  }
}
