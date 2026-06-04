import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/presentation/dev/appointment_dev_seed_service.dart';
import 'package:ai_clinic/features/auth/presentation/dev/dev_seed_providers.dart';

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

/// Debug-only control to seed planned appointments.
class DevSeedAppointmentsButton extends ConsumerStatefulWidget {
  const DevSeedAppointmentsButton({super.key, this.onSeeded});

  final VoidCallback? onSeeded;

  @override
  ConsumerState<DevSeedAppointmentsButton> createState() => _DevSeedAppointmentsButtonState();
}

class _DevSeedAppointmentsButtonState extends ConsumerState<DevSeedAppointmentsButton> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode && !_kEnableDevTools) {
      return const SizedBox.shrink();
    }

    final auth = ref.watch(authSessionProvider).context;
    if (auth == null || !auth.staffProfile.isBootstrapAdmin || auth.setupRequired) {
      return const SizedBox.shrink();
    }

    if (!SupabaseBootstrap.isReady) {
      return const SizedBox.shrink();
    }

    return TextButton.icon(
      key: const Key('appointments_dev_seed_appointments_button'),
      onPressed: _isBusy ? null : () => _confirmAndSeed(context),
      icon: _isBusy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.auto_fix_high_outlined),
      label: Text(_isBusy ? 'Seeding…' : 'Dev: seed appointments'),
    );
  }

  Future<void> _confirmAndSeed(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seed demo appointments?'),
        content: Text(
          'Creates $appointmentDevSeedPlannedCount planned appointments at the active branch. '
          'Requires patients in the active branch.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Seed appointments')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final auth = ref.read(authSessionProvider).context;
    final branchId = auth?.activeBranchId;
    final organizationId = auth?.organizationId;
    if (branchId == null || branchId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Select an active branch before seeding appointments.')));
      }
      return;
    }
    if (organizationId == null || organizationId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Organization context is missing. Sign in again.')));
      }
      return;
    }

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seeding demo appointments...')));
    setState(() => _isBusy = true);
    AppLog.info('appointments.dev_seed.ui_confirmed branch=$branchId');

    final outcome = await ref
        .read(appointmentDevSeedServiceProvider)
        .seed(branchId: branchId, organizationId: organizationId);

    if (!mounted) {
      return;
    }
    setState(() => _isBusy = false);

    if (!context.mounted) {
      return;
    }

    if (!outcome.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.errorMessage!)));
      return;
    }

    widget.onSeeded?.call();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created ${outcome.plannedCreated} planned demo appointments.')));
  }
}
