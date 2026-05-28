import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/appointments/domain/doctor_dev_seed_data.dart';
import 'package:ai_clinic/features/auth/presentation/dev/appointment_dev_seed_service.dart';
import 'package:ai_clinic/features/auth/presentation/dev/dev_seed_all_runner.dart';
import 'package:ai_clinic/features/auth/presentation/providers/bootstrap_notifier.dart';
import 'package:ai_clinic/features/patients/domain/patient_dev_seed_data.dart';

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

/// Runs dummy clinic setup (when needed) plus doctor, patient, and appointment dev seeds.
class DevSeedAllButton extends ConsumerStatefulWidget {
  const DevSeedAllButton({super.key});

  @override
  ConsumerState<DevSeedAllButton> createState() => _DevSeedAllButtonState();
}

class _DevSeedAllButtonState extends ConsumerState<DevSeedAllButton> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode && !_kEnableDevTools) {
      return const SizedBox.shrink();
    }

    final auth = ref.watch(authSessionProvider).context;
    if (auth == null || !auth.staffProfile.isBootstrapAdmin) {
      return const SizedBox.shrink();
    }

    if (!auth.setupRequired && !SupabaseBootstrap.isReady) {
      return const SizedBox.shrink();
    }

    final bootstrapBusy = ref.watch(bootstrapNotifierProvider).isSubmitting;
    final isBusy = _isBusy || bootstrapBusy;

    return FilledButton.tonalIcon(
      key: const Key('dev_seed_all_button'),
      onPressed: isBusy ? null : () => _confirmAndRun(context),
      icon: isBusy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.layers_outlined),
      label: Text(isBusy ? 'Seeding all…' : 'Dev: seed everything'),
    );
  }

  Future<void> _confirmAndRun(BuildContext context) async {
    final auth = ref.read(authSessionProvider).context;
    if (auth == null) {
      return;
    }

    final doctorCount = DoctorDevSeedData.doctors.length;
    final patientCount = PatientDevSeedData.patients.length;
    final appointmentCount = appointmentDevSeedPlannedCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seed all demo data?'),
        content: Text(
          auth.setupRequired
              ? 'Runs all dev setup steps in order:\n'
                    '1. Create demo organization and branch\n'
                    '2. Seed $doctorCount doctors (password: ${DoctorDevSeedData.defaultPassword})\n'
                    '3. Seed $patientCount patients (active, second branch, archived)\n'
                    '4. Create $appointmentCount appointments at the active branch\n\n'
                    'Existing dev doctors or patients are skipped; appointments are always created.'
              : 'Seeds demo data at your clinic in order:\n'
                    '1. $doctorCount doctors (password: ${DoctorDevSeedData.defaultPassword})\n'
                    '2. $patientCount patients\n'
                    '3. $appointmentCount appointments\n\n'
                    'Existing dev doctors or patients are skipped; appointments are always created.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Seed everything')),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Running full dev seed…')));
    setState(() => _isBusy = true);
    AppLog.info('dev_seed_all.ui_confirmed setup_required=${auth.setupRequired}');

    final outcome = await DevSeedAllRunner(ref).run();

    if (!mounted) {
      return;
    }
    setState(() => _isBusy = false);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.summaryLines.join('\n')),
        duration: outcome.isSuccess ? const Duration(seconds: 6) : const Duration(seconds: 4),
      ),
    );
  }
}
