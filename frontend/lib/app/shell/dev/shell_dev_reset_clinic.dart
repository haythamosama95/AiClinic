import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_bootstrap_sign_in.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';

/// Dev Options nav item and handlers for resetting clinic installation data.
abstract final class ShellDevResetClinic {
  const ShellDevResetClinic._();

  static const itemId = 'reset-clinic';
  static const label = 'Reset Clinic';
  static const icon = Icons.restart_alt_outlined;

  static bool get isEnabled => kDebugMode;

  static const confirmationTitle = 'Reset clinic data?';
  static const confirmationMessage =
      'This removes all organization and branch data from the server. '
      'You will be signed out and need to sign in again before running setup.';

  static Future<void> handleNavSelection(BuildContext context, WidgetRef ref) async {
    if (!isEnabled) {
      return;
    }

    await confirmAndRun(context, ref);
  }

  static Future<bool> confirm(BuildContext context) async {
    if (!isEnabled) {
      return false;
    }

    return AppConfirmationDialog.show(
      context,
      title: confirmationTitle,
      description: confirmationMessage,
      confirmLabel: 'Reset clinic',
      cancelLabel: 'Cancel',
    );
  }

  static Future<void> confirmAndRun(BuildContext context, WidgetRef ref, {VoidCallback? onSuccess}) async {
    final confirmed = await confirm(context);
    if (confirmed && context.mounted) {
      await run(context, ref, onSuccess: onSuccess);
    }
  }

  static Future<void> run(BuildContext context, WidgetRef ref, {VoidCallback? onSuccess}) async {
    final signInError = await ShellDevBootstrapSignIn.ensureSignedIn(ref);
    if (!context.mounted) {
      return;
    }
    if (signInError != null) {
      appToast(context, AppToastInput(message: signInError, variant: AppToastVariant.danger));
      return;
    }

    final ok = await ref.read(clinicSetupProvider.notifier).resetInstallationForDevelopment();
    if (!context.mounted) {
      return;
    }

    if (ok) {
      await ref.read(clinicSetupProvider.notifier).resetSetup();
      await ref.read(authSessionProvider.notifier).signOut();
      if (context.mounted) {
        context.go(AppRoutes.login);
        appToast(context, const AppToastInput(message: 'Clinic data reset.', variant: AppToastVariant.success));
      }
      onSuccess?.call();
      return;
    }

    final errorMessage = ref.read(clinicSetupProvider).submitError;
    if (errorMessage != null) {
      appToast(context, AppToastInput(message: errorMessage, variant: AppToastVariant.danger));
    }
  }
}
