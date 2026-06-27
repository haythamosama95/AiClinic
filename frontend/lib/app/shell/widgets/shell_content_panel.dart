import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';

/// Main content region below [ShellHeader], flush to the shell trailing and bottom edges.
class ShellContentPanel extends StatelessWidget {
  const ShellContentPanel({required this.child, this.backgroundColor, super.key});

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final radius = BorderRadius.only(topLeft: Radius.circular(context.shapeTokens.xl));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.background,
        borderRadius: radius,
        border: Border(
          top: BorderSide(color: colors.border),
          left: BorderSide(color: colors.border),
        ),
        boxShadow: ShadowTokens.shellContentPanel,
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
