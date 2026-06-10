import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Placeholder for the top header region until header is implemented.
class ShellHeaderPlaceholder extends StatelessWidget {
  const ShellHeaderPlaceholder({super.key});

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ColoredBox(color: colors.muted),
    );
  }
}
