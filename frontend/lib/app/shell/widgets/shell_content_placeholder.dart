import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Placeholder for the main content region until feature pages render here.
class ShellContentPlaceholder extends StatelessWidget {
  const ShellContentPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.semanticColors.background);
  }
}
