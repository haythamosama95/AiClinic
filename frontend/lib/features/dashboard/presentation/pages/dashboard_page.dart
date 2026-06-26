import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Clinic dashboard landing page inside the authenticated shell.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: SingleChildScrollView(
        child: AppNotchedCard(
          title: Text('Today at a glance', style: theme.textTheme.titleMedium),
          description: Text(
            'Overview metrics and quick actions in a notched dashboard card.',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
          ),
          body: Text(
            'Appointments, queue depth, and revenue summaries will appear here.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
