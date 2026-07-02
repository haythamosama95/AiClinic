import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';

/// Warns about empty encounter phases before allowing visit submission.
class VisitEmptySectionsWarningDialog extends StatelessWidget {
  const VisitEmptySectionsWarningDialog({required this.emptyPhases, required this.dialogContext, super.key});

  final List<EncounterPhase> emptyPhases;
  final BuildContext dialogContext;

  static Future<bool> show(BuildContext context, {required List<EncounterPhase> emptyPhases}) {
    return AppDialog.show<bool>(
      context: context,
      title: 'Empty sections',
      barrierDismissible: false,
      bodyBuilder: (dialogContext) => VisitEmptySectionsWarningDialog(
        key: const Key('visit_empty_sections_warning_dialog'),
        emptyPhases: emptyPhases,
        dialogContext: dialogContext,
      ),
    ).then((value) => value ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The following sections have no content. You can go back to add documentation, '
          'or continue to submit the visit.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: SpacingTokens.md),
        AppAlert(
          key: const Key('visit_empty_sections_warning_list'),
          title: 'Empty sections',
          subtitle: emptyPhases.map((phase) => phase.label).join('\n'),
        ),
        const SizedBox(height: SpacingTokens.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              key: const Key('visit_empty_sections_go_back_button'),
              label: 'Go back',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(
              key: const Key('visit_empty_sections_continue_button'),
              label: 'Continue to submit',
              expand: false,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ],
    );
  }
}
