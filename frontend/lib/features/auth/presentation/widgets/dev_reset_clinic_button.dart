import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/presentation/providers/bootstrap_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

/// Debug-only control to delete organization/branch data and re-run clinic bootstrap.
class DevResetClinicButton extends ConsumerWidget {
  const DevResetClinicButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode && !_kEnableDevTools) {
      return const SizedBox.shrink();
    }

    final auth = ref.watch(authSessionProvider).context;
    if (auth == null || !auth.staffProfile.isBootstrapAdmin) {
      return const SizedBox.shrink();
    }

    final bootstrap = ref.watch(bootstrapNotifierProvider);
    final isBusy = bootstrap.isSubmitting;

    return TextButton.icon(
      onPressed: isBusy ? null : () => _confirmAndReset(context, ref),
      icon: const Icon(Icons.delete_outline),
      label: const Text('Dev: reset clinic'),
      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
    );
  }

  Future<void> _confirmAndReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
        title: const Text('Reset clinic installation?'),
        content: const Text(
          'This permanently deletes the organization, all branches, branch assignments, and related setup data '
          'in this database. Use only during local development to test bootstrap again.\n\n'
          'Staff login accounts are kept; only tenant setup rows are removed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete and reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    AppLog.info('bootstrap.dev_reset.ui_confirmed');
    final ok = await ref.read(bootstrapNotifierProvider.notifier).resetInstallationForDevelopment();
    if (!context.mounted) {
      return;
    }

    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clinic data removed. You can run organization setup again.')));
      context.go(AppRoutes.bootstrap);
      return;
    }

    final message =
        ref.read(bootstrapNotifierProvider).errorMessage ??
        'Reset failed. See logs for bootstrap.dev_reset.* and apply migration 20260521140000.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    AppLog.warning('bootstrap.dev_reset.ui_failed');
  }
}
