import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_reset_clinic.dart';
import 'package:ai_clinic/features/auth/domain/usecases/auth_use_case_providers.dart';
import 'package:ai_clinic/features/auth/presentation/dev/auth_dev_widgets.dart';

/// Dispatches debug-only dev nav actions (fill dummy clinic, reset clinic).
abstract final class ShellDevNavHandler {
  const ShellDevNavHandler._();

  static bool isActionItem(String itemId) => ShellDevNav.actionItemIds.contains(itemId);

  static Future<void> handleItemSelection(BuildContext context, WidgetRef ref, String itemId) async {
    switch (itemId) {
      case ShellDevFillDummyClinic.itemId:
        await ShellDevFillDummyClinic.handleNavSelection(context, ref);
      case ShellDevResetClinic.itemId:
        await ShellDevResetClinic.handleNavSelection(context, ref);
    }
  }

  /// Runs a dev action from the login screen: confirm first, then bootstrap admin sign-in, then execute.
  static Future<void> handleFromLogin(
    BuildContext context,
    WidgetRef ref, {
    required Future<bool> Function(BuildContext context) confirm,
    required Future<void> Function(BuildContext context, WidgetRef ref) run,
  }) async {
    final confirmed = await confirm(context);
    if (!confirmed || !context.mounted) {
      return;
    }

    final ready = await _ensureBootstrapAdminSession(ref);
    if (!context.mounted) {
      return;
    }

    if (!ready) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to sign in as bootstrap administrator.')));
      return;
    }

    await run(context, ref);
  }

  static Future<bool> _ensureBootstrapAdminSession(WidgetRef ref) async {
    final auth = ref.read(authSessionProvider);
    if (auth.isAuthenticated && auth.context?.staffProfile.isBootstrapAdmin == true) {
      return true;
    }

    try {
      await ref.read(authSessionProvider.notifier).ensureReadyForSignIn();
      await ref.read(signInUseCaseProvider)(
        username: AuthDevBootstrapCredentials.username,
        password: AuthDevBootstrapCredentials.password,
      );
      await ref.read(authSessionProvider.notifier).syncAfterSignIn();
    } catch (_) {
      return false;
    }

    final updated = ref.read(authSessionProvider);
    return updated.isAuthenticated && updated.context?.staffProfile.isBootstrapAdmin == true;
  }
}
