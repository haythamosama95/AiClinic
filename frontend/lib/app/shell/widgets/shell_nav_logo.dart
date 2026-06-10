import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Circular clinic mark at the top of the sidebar.
class ShellNavLogo extends StatelessWidget {
  const ShellNavLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return SizedBox(
      height: ShellTokens.headerHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: ShellTokens.logoSize,
          height: ShellTokens.logoSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.card,
            boxShadow: [
              BoxShadow(color: colors.foreground.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Center(
            child: Text(
              'AC',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
