import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/patients/domain/patient_dev_seed_data.dart';
import 'package:ai_clinic/features/auth/presentation/dev/dev_seed_providers.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

/// Debug-only control to seed ~20 demo patients (active + other branch, plus archived).
class DevSeedPatientsButton extends ConsumerStatefulWidget {
  const DevSeedPatientsButton({super.key});

  @override
  ConsumerState<DevSeedPatientsButton> createState() => _DevSeedPatientsButtonState();
}

class _DevSeedPatientsButtonState extends ConsumerState<DevSeedPatientsButton> {
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
      onPressed: _isBusy ? null : () => _confirmAndSeed(context),
      icon: _isBusy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.people_alt_outlined),
      label: Text(_isBusy ? 'Seeding…' : 'Dev: seed patients'),
    );
  }

  Future<void> _confirmAndSeed(BuildContext context) async {
    final count = PatientDevSeedData.patients.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seed demo patients?'),
        content: Text(
          'Creates $count patients prefixed with “[Dev]”: most at your active branch, '
          'several at a second branch (created if needed), and 2 archived. '
          'Skips if dev patients already exist.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Seed patients')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final auth = ref.read(authSessionProvider).context;
    if (auth == null) {
      return;
    }

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seeding demo patients...')));
    setState(() => _isBusy = true);
    AppLog.info('patients.dev_seed.ui_confirmed');

    final outcome = await ref
        .read(patientDevSeedServiceProvider)
        .seed(auth, reloadAuthContext: () => ref.read(authSessionProvider.notifier).reloadContext());

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

    if (outcome.skippedBecauseAlreadySeeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dev patients already exist — seed skipped. Delete [Dev] patients to re-run.')),
      );
      return;
    }

    ref.invalidate(patientListProvider);
    ref.invalidate(staffAssignableBranchesProvider);

    if (!context.mounted) {
      return;
    }

    final branchNote = outcome.otherBranchName != null ? ' Second branch: ${outcome.otherBranchName}.' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Created ${outcome.created} dev patients (${outcome.archived} archived).$branchNote '
          'Use “All branches” to see cross-branch rows.',
        ),
      ),
    );
  }
}
