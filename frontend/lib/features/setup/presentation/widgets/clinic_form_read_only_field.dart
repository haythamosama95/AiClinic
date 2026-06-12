import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Read-only label + value row for clinic organization and branch forms in settings.
class ClinicFormReadOnlyField extends StatelessWidget {
  const ClinicFormReadOnlyField({required this.label, required this.value, super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = value?.trim();
    final hasDisplay = display != null && display.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: SpacingTokens.sm),
        Text(
          hasDisplay ? display : 'This value has not been set before.',
          style: hasDisplay
              ? theme.textTheme.bodyLarge
              : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
