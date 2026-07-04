import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';

/// Warns about empty encounter phases before allowing visit submission.
class VisitEmptySectionsWarningDialog extends StatelessWidget {
  const VisitEmptySectionsWarningDialog({
    required this.emptyPhases,
    required this.onClose,
    super.key,
  });

  final List<EncounterPhase> emptyPhases;
  final AppDialogCloseCallback<bool> onClose;

  /// Returns `true` when the user chooses to continue to submit.
  static Future<bool> show(
    BuildContext context, {
    required List<EncounterPhase> emptyPhases,
  }) {
    return showAppDialog<bool>(
      context,
      size: AppDialogSize.sm,
      barrierDismissible: false,
      semanticLabel: 'Empty sections',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Empty sections',
          onClose: () => close(false),
          body: VisitEmptySectionsWarningDialog(
            emptyPhases: emptyPhases,
            onClose: close,
          ),
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Go back',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: () => close(false),
              ),
              const SizedBox(width: AppSpacing.s2),
              AppButton(
                label: 'Continue to submit',
                size: AppButtonSize.sm,
                onPressed: () => close(true),
              ),
            ],
          ),
        );
      },
    ).then((value) => value ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'The following sections have no content. You can go back to add documentation, '
          'or continue to submit the visit.',
          style: typography.body.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppAlert(
          variant: AppAlertVariant.warning,
          title: 'Empty sections',
          body: emptyPhases.map((phase) => phase.label).join('\n'),
        ),
      ],
    );
  }
}
