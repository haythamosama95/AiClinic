import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Shape preset for standalone [AppSkeleton] placeholders.
enum AppSkeletonShape {
  text,
  circular,
  rectangular,
}

/// Shape-matched loading placeholder with calm shimmer.
///
/// For list or card layouts, wrap the loaded widget tree in [Skeletonizer]:
/// ```dart
/// Skeletonizer(
///   enabled: isLoading,
///   effect: AppSkeleton.effectFor(context),
///   child: patientListRow,
/// )
/// ```
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    this.shape = AppSkeletonShape.rectangular,
    this.width,
    this.height,
    super.key,
  });

  final AppSkeletonShape shape;
  final double? width;
  final double? height;

  /// Resolves shimmer colors from design tokens; static under reduced motion.
  static PaintingEffect effectFor(BuildContext context) {
    final colors = context.colors;
    if (AppMotion.reduced(context)) {
      return SolidColorEffect(color: colors.surfaceMuted);
    }
    return ShimmerEffect(
      baseColor: colors.surfaceMuted,
      highlightColor: colors.surfaceHover,
      duration: AppDurations.deliberate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effect = effectFor(context);

    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: Skeletonizer.zone(
        enabled: true,
        effect: effect,
        child: _boneForShape(shape, width: width, height: height),
      ),
    );
  }

  static Widget _boneForShape(
    AppSkeletonShape shape, {
    double? width,
    double? height,
  }) {
    return switch (shape) {
      AppSkeletonShape.text => Bone(
        width: width ?? double.infinity,
        height: height ?? AppSpacing.s4,
        borderRadius: AppRadii.smAll,
      ),
      AppSkeletonShape.circular => Bone.circle(
        size: width ?? height ?? AppSpacing.s8,
      ),
      AppSkeletonShape.rectangular => Bone(
        width: width,
        height: height,
        borderRadius: AppRadii.mdAll,
      ),
    };
  }
}
