import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// User choice when leaving the visit documentation workspace with unsaved work.
enum VisitExitDecision { save, discard, stay }

/// Presents a three-way dialog for unsaved clinical documentation.
Future<VisitExitDecision> showVisitUnsavedChangesDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;

  final result = await AppDialog.show<VisitExitDecision>(
    context,
    title: l10n.visitUnsavedChangesTitle,
    description: l10n.visitUnsavedChangesMessage,
    size: AppDialogSize.sm,
    barrierDismissible: false,
    child: Builder(
      builder: (context) => Text(
        l10n.visitUnsavedChangesMessage,
        style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary),
      ),
    ),
    footer: Builder(
      builder: (dialogContext) {
        return Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(dialogContext).pop(VisitExitDecision.stay),
              child: Text(l10n.visitUnsavedChangesStay),
            ),
            AppButton(
              variant: AppButtonVariant.danger,
              onPressed: () => Navigator.of(dialogContext).pop(VisitExitDecision.discard),
              child: Text(l10n.visitUnsavedChangesDiscardAndLeave),
            ),
            AppButton(
              onPressed: () => Navigator.of(dialogContext).pop(VisitExitDecision.save),
              child: Text(l10n.visitUnsavedChangesSaveAndLeave),
            ),
          ],
        );
      },
    ),
  );

  return result ?? VisitExitDecision.stay;
}
