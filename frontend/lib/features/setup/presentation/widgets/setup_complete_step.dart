import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_layout.dart';

class SetupCompleteStep extends StatelessWidget {
  const SetupCompleteStep({required this.onGoHome, super.key});

  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SetupStepLayout(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: SpacingTokens.lg),
          Text('Clinic setup is complete', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            'Your organization, first branch, and staff account are ready. Open the clinic shell to get started.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: Align(
        alignment: Alignment.center,
        child: AppButton(label: 'Go to clinic home', onPressed: onGoHome),
      ),
    );
  }
}
