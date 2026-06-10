import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Placeholder for the left navigation region until nav is implemented.
class ShellNavPlaceholder extends StatelessWidget {
  const ShellNavPlaceholder({super.key});

  static const double width = 240;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return SizedBox(
      width: width,
      child: ColoredBox(color: colors.sidebar),
    );
  }
}
