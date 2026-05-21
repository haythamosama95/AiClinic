import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';

/// Field label with optional info icon tooltip (desktop hover).
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel({super.key, required this.label, this.infoTooltip});

  final String label;
  final String? infoTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        if (infoTooltip != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Tooltip(
            message: infoTooltip!,
            preferBelow: false,
            child: Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ],
    );
  }
}
