import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_setup_dialog_content.dart';

/// First-run clinic setup presented as a modal dialog over the authenticated shell.
abstract final class ClinicSetupDialog {
  const ClinicSetupDialog._();

  static Future<bool> show(BuildContext context) async {
    var completed = false;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = (screenWidth - AppSpacing.space8) * 0.6;

    await AppDialog.show<void>(
      context,
      title: 'Clinic setup',
      size: AppDialogSize.full,
      maxWidth: maxWidth,
      barrierDismissible: false,
      showCloseButton: false,
      showHeader: false,
      child: Consumer(
        builder: (context, ref, _) {
          ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
            final wasLocked = previous?.context?.needsClinicSetup ?? false;
            final isLocked = next.context?.needsClinicSetup ?? false;
            if (wasLocked && !isLocked) {
              completed = true;
              Navigator.of(context).pop();
            }
          });

          return const ClinicSetupDialogContent(showPageHeader: false, showCompletedBanner: false);
        },
      ),
    );

    return completed;
  }
}
