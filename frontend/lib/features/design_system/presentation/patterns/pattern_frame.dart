import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Bordered canvas for composed pattern demos (web `PatternFrame`).
class PatternFrame extends StatelessWidget {
  const PatternFrame({required this.child, this.minHeight, super.key});

  final Widget child;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceCanvas,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight ?? 0),
          child: child,
        ),
      ),
    );
  }
}
