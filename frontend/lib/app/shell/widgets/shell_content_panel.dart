import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';

/// Floating card container for the main content region below [ShellHeader].
class ShellContentPanel extends StatelessWidget {
  const ShellContentPanel({required this.child, this.backgroundColor, super.key});

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final radius = BorderRadius.circular(context.shapeTokens.xl);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.background,
        borderRadius: radius,
        border: Border.all(color: colors.border),
        boxShadow: ShadowTokens.card,
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
