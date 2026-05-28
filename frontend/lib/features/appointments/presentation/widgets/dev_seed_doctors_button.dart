import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/appointments/data/doctor_dev_seed_service.dart';
import 'package:ai_clinic/features/appointments/domain/doctor_dev_seed_data.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

final _doctorDevSeedServiceProvider = Provider<DoctorDevSeedService>((ref) {
  return DoctorDevSeedService(
    staffAdmin: ref.watch(staffAdminRepositoryProvider),
    provisioning: ref.watch(provisioningRepositoryProvider),
  );
});

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

class DevSeedDoctorsButton extends ConsumerStatefulWidget {
  const DevSeedDoctorsButton({super.key, this.onSeeded});

  final VoidCallback? onSeeded;

  @override
  ConsumerState<DevSeedDoctorsButton> createState() => _DevSeedDoctorsButtonState();
}

class _DevSeedDoctorsButtonState extends ConsumerState<DevSeedDoctorsButton> {
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
      key: const Key('appointments_dev_seed_doctors_button'),
      onPressed: _isBusy ? null : () => _confirmAndSeed(context),
      icon: _isBusy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.medical_services_outlined),
      label: Text(_isBusy ? 'Seeding…' : 'Dev: seed doctors'),
    );
  }

  Future<void> _confirmAndSeed(BuildContext context) async {
    final count = DoctorDevSeedData.doctors.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seed demo doctors?'),
        content: Text(
          'Creates $count doctor accounts at your active branch with names prefixed by "[Dev]". '
          'All seeded accounts use password "${DoctorDevSeedData.defaultPassword}". '
          'Skips if dev doctors already exist.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Seed doctors')),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final auth = ref.read(authSessionProvider).context;
    if (auth == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seeding demo doctors...')));
    setState(() => _isBusy = true);
    AppLog.info('appointments.dev_seed_doctors.ui_confirmed');

    final outcome = await ref.read(_doctorDevSeedServiceProvider).seed(auth);

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
        const SnackBar(content: Text('Dev doctors already exist — seed skipped. Delete [Dev] doctors to re-run.')),
      );
      return;
    }

    widget.onSeeded?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Created ${outcome.created} dev doctors. Password: ${DoctorDevSeedData.defaultPassword}')),
    );
  }
}
