import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');
const int _plannedCount = 6;
const int _walkInCount = 4;

/// Debug-only control to seed mixed planned and walk-in appointments.
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
        content: const Text(
          'Creates 10 appointments at the active branch: 6 planned plus 4 walk-ins. '
          'Requires patients in the active branch.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Seed appointments')),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final auth = ref.read(authSessionProvider).context;
    final branchId = auth?.activeBranchId;
    if (branchId == null || branchId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Select an active branch before seeding appointments.')));
      }
      return;
    }

    setState(() => _isBusy = true);
    AppLog.info('appointments.dev_seed.ui_confirmed branch=$branchId');

    try {
      final patientsPage = await ref.read(searchPatientsUseCaseProvider)(
        scope: PatientListScope.thisBranch,
        branchId: branchId,
        limit: 20,
      );
      final patients = patientsPage.items;
      if (patients.isEmpty) {
        throw StateError('No patients found in the active branch. Seed patients first.');
      }

      final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.active);
      final doctorIds = staff
          .where((item) => item.role.name == 'doctor' && item.isActive)
          .map((item) => item.id)
          .toList(growable: false);

      final appointments = ref.read(appointmentRepositoryProvider);
      final now = DateTime.now();
      final rounded = DateTime(now.year, now.month, now.day, now.hour, ((now.minute + 14) ~/ 15) * 15);
      final plannedStart = rounded.add(const Duration(minutes: 30));

      for (var i = 0; i < _plannedCount; i++) {
        final patient = patients[i % patients.length];
        final doctorId = doctorIds.isEmpty ? null : doctorIds[i % doctorIds.length];
        await appointments.createAppointment(
          branchId: branchId,
          patientId: patient.id,
          doctorId: doctorId,
          type: AppointmentType.planned,
          startTime: plannedStart.add(Duration(minutes: i * 30)),
          durationMinutes: 30,
          notes: '[Dev] Planned seed #${i + 1}',
        );
      }

      for (var i = 0; i < _walkInCount; i++) {
        final patient = patients[(_plannedCount + i) % patients.length];
        final doctorId = doctorIds.isEmpty ? null : doctorIds[(_plannedCount + i) % doctorIds.length];
        await appointments.createAppointment(
          branchId: branchId,
          patientId: patient.id,
          doctorId: doctorId,
          type: AppointmentType.walkIn,
          durationMinutes: 20,
          notes: '[Dev] Walk-in seed #${i + 1}',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() => _isBusy = false);
      widget.onSeeded?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Created 10 demo appointments (6 planned, 4 walk-ins).')));
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.result.errorMessage ?? 'Failed to seed appointments (${error.code}).')),
      );
    } catch (error, stack) {
      AppLog.warning('appointments.dev_seed.failed reason=${error.runtimeType}');
      AppLog.fine('appointments.dev_seed.stack $stack');
      if (!mounted) {
        return;
      }
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(UserErrorMapper.mapToUserMessage(error))));
    }
  }
}
