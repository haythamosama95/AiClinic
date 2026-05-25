import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/presentation/providers/bootstrap_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

/// Debug-only control to create organization and first branch with preset dummy data.
class DevFillDummyClinicButton extends ConsumerWidget {
  const DevFillDummyClinicButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode && !_kEnableDevTools) {
      return const SizedBox.shrink();
    }

    final auth = ref.watch(authSessionProvider).context;
    if (auth == null || !auth.staffProfile.isBootstrapAdmin || !auth.setupRequired) {
      return const SizedBox.shrink();
    }

    final bootstrap = ref.watch(bootstrapNotifierProvider);
    final isBusy = bootstrap.isSubmitting;

    return TextButton.icon(
      onPressed: isBusy ? null : () => _confirmAndFill(context, ref),
      icon: const Icon(Icons.auto_fix_high),
      label: const Text('Dev: fill dummy clinic'),
    );
  }

  Future<void> _confirmAndFill(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fill clinic with dummy data?'),
        content: const Text(
          'Creates a demo organization and main branch in this database using preset values. '
          'Use during local development to skip manual bootstrap entry.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Create dummy clinic')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    AppLog.info('bootstrap.dev_dummy_fill.ui_confirmed');
    final ok = await ref.read(bootstrapNotifierProvider.notifier).finishSetupWithDummyData();
    if (!context.mounted) {
      return;
    }

    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Demo organization and branch created.')));
      return;
    }

    final message =
        ref.read(bootstrapNotifierProvider).errorMessage ??
        'Dummy clinic setup failed. See logs for bootstrap.dev_dummy_fill.*';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    AppLog.warning('bootstrap.dev_dummy_fill.ui_failed');
  }
}
