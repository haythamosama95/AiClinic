import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_draft_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';

/// Dev Options nav item and handlers for resetting clinic installation data.
abstract final class ShellDevResetClinic {
  const ShellDevResetClinic._();

  static const itemId = 'reset-clinic';
  static const label = 'Reset Clinic';
  static const icon = Icons.restart_alt_outlined;

  static bool get isEnabled => kDebugMode;

  static const confirmationTitle = 'Reset clinic data?';
  static const confirmationMessage =
      'This removes all organization and branch data from the server while keeping your bootstrap administrator login. '
      'You will need to run setup again before using the clinic.';

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
    final ok = await ref.read(setupNotifierProvider.notifier).resetInstallationForDevelopment();
    if (!context.mounted) {
      return;
    }

    if (ok) {
      await ref.read(clinicSetupDraftProvider.notifier).resetSetup();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clinic data reset.')));
      onSuccess?.call();
      return;
    }

    final errorMessage = ref.read(setupNotifierProvider).errorMessage;
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }
}
