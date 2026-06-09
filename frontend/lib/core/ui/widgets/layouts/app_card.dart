import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Dashboard panel container wrapping [FCard] with optional header actions.
class AppCard extends StatelessWidget {
  const AppCard({required this.child, this.title, this.description, this.actions, super.key});

  final Widget? title;
  final Widget? description;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return FCard(
      title: title,
      subtitle: description,
      style: FCardStyleDelta.delta(
        decoration: DecorationDelta.boxDelta(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.md),
            Row(mainAxisAlignment: MainAxisAlignment.end, spacing: SpacingTokens.sm, children: actions!),
          ],
        ],
      ),
    );
  }
}
