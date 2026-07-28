import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Read-only dialog for patient clinical notes on the detail page.
abstract final class PatientNotesDialog {
  const PatientNotesDialog._();

  static Future<void> show(BuildContext context, {required String notes}) {
    final l10n = context.l10n;
    return AppDialog.show<void>(
      context,
      title: l10n.clinicalNotesSectionTitle,
      description: l10n.clinicalNotesSectionDescription,
      size: AppDialogSize.md,
      child: SelectableText(
        notes,
        style: AppTypography.body(
          context,
        ).copyWith(color: context.appColors.textPrimary),
      ),
    );
  }
}
