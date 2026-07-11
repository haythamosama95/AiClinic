import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_setup_dialog_content.dart';

/// First-run clinic setup presented as a modal dialog over the authenticated shell.
abstract final class ClinicSetupDialog {
  const ClinicSetupDialog._();

  static Future<bool> show(BuildContext context) async {
    var completed = false;
    var setupRequired = true;
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
          final setupDone = ref.watch(isSetupCompleteProvider);
          // Track setup-required state so the dialog can pop only once setup is
          // no longer required (genuine completion), while a PopScope prevents the
          // Android back button from dismissing the wizard while it is still required.
          setupRequired = !setupDone;
          ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
            final wasLocked = previous?.context?.needsClinicSetup ?? true;
            final isLocked = next.context?.needsClinicSetup ?? true;
            if (wasLocked && !isLocked) {
              completed = true;
              setupRequired = false;
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            }
          });

          return PopScope(
            canPop: !setupRequired,
            child: const ClinicSetupDialogContent(showPageHeader: false, showCompletedBanner: false),
          );
        },
      ),
    );

    return completed;
  }
}
