import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';

/// Placeholder block for loading skeletons.
class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({this.width, this.height = 12, this.borderRadius, super.key});

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final radius = borderRadius ?? BorderRadius.circular(context.shapeTokens.sm);

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.muted, borderRadius: radius),
      child: SizedBox(width: width, height: height),
    );
  }
}

/// Circular avatar placeholder for loading skeletons.
class AppSkeletonCircle extends StatelessWidget {
  const AppSkeletonCircle({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonBox(width: size, height: size, borderRadius: BorderRadius.circular(size / 2));
  }
}
