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

/// Runs dummy clinic setup (when needed) plus patient, doctor, and appointment dev seeds.
class DevSeedAllButton extends ConsumerWidget {
  const DevSeedAllButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final seedInProgress = ref.watch(devFullSeedInProgressProvider);
    final isBusy = bootstrapBusy || seedInProgress;

    return FilledButton.tonalIcon(
      key: const Key('dev_seed_all_button'),
      onPressed: isBusy ? null : () => _confirmAndRun(context, ref),
      icon: isBusy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.layers_outlined),
      label: Text(isBusy ? 'Seeding all…' : 'Dev: seed everything'),
    );
  }

  Future<void> _confirmAndRun(BuildContext context, WidgetRef ref) async {
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
                    '2. Seed $patientCount patients (active, second branch, archived)\n'
                    '3. Seed $doctorCount doctors (password: ${DoctorDevSeedData.defaultPassword})\n'
                    '4. Create $appointmentCount appointments at the active branch\n\n'
                    'Existing dev doctors or patients are skipped; appointments are always created.'
              : 'Seeds demo data at your clinic in order:\n'
                    '1. $patientCount patients\n'
                    '2. $doctorCount doctors (password: ${DoctorDevSeedData.defaultPassword})\n'
                    '3. $appointmentCount appointments\n\n'
                    'Existing dev doctors or patients are skipped; appointments are always created.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Seed everything')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    // Capture notifiers before any await — bootstrap redirect can unmount this widget
    // while [DevSeedAllRunner.run] continues on [devSeedAllRunnerProvider]'s Ref.
    final seedProgress = ref.read(devFullSeedInProgressProvider.notifier);
    final feedbackNotifier = ref.read(devSeedAllFeedbackProvider.notifier);
    final runner = ref.read(devSeedAllRunnerProvider);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Running full dev seed…')));
    seedProgress.setInProgress(true);
    AppLog.info('dev_seed_all.ui_confirmed setup_required=${auth.setupRequired}');

    DevSeedAllOutcome outcome;
    try {
      outcome = await runner.run();
    } catch (error, stack) {
      AppLog.warning('dev_seed_all.ui_failed reason=${error.runtimeType}');
      AppLog.fine('dev_seed_all.ui_stack $stack');
      outcome = DevSeedAllOutcome(isSuccess: false, summaryLines: ['Dev seed failed: $error']);
    } finally {
      seedProgress.setInProgress(false);
    }

    if (!context.mounted) {
      feedbackNotifier.publish(outcome);
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
