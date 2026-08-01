import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Applies design-system skeleton shimmer tokens via [Skeletonizer.zone].
class AppSkeletonizerZone extends StatelessWidget {
  const AppSkeletonizerZone({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final effect = reducedMotion
        ? SolidColorEffect(color: colors.surfaceMuted)
        : ShimmerEffect(
            baseColor: colors.surfaceMuted,
            highlightColor: colors.surfaceHover,
            duration: AppMotionDuration.deliberate,
          );

    return SkeletonizerConfig(
      data: SkeletonizerConfigData(
        effect: effect,
        textBorderRadius: TextBoneBorderRadius(BorderRadius.circular(AppRadius.sm)),
      ),
      child: Skeletonizer.zone(enabled: true, child: child),
    );
  }
}
