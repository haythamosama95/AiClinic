import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';

/// Confirmation before archiving (deactivating) a patient from the list row menu.
abstract final class ArchivePatientDialog {
  const ArchivePatientDialog._();

  /// Returns `true` when the user confirms deactivation.
  static Future<bool> show(BuildContext context, {required String fullName}) {
    final l10n = context.l10n;
    return AppConfirmationDialog.show(
      context,
      title: l10n.archivePatientDialogTitle,
      description: l10n.archivePatientDialogDescription(fullName),
      confirmLabel: l10n.archivePatientDialogConfirm,
      cancelLabel: l10n.cancel,
    );
  }
}
