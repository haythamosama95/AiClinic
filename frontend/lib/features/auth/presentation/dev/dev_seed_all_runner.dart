import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/appointments/domain/doctor_dev_seed_data.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/dev/dev_seed_providers.dart';
import 'package:ai_clinic/features/auth/presentation/providers/bootstrap_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';

class DevSeedAllOutcome {
  const DevSeedAllOutcome({required this.isSuccess, required this.summaryLines});

  final bool isSuccess;
  final List<String> summaryLines;
}

class DevFullSeedInProgressNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setInProgress(bool inProgress) => state = inProgress;
}

class DevSeedAllFeedbackNotifier extends Notifier<DevSeedAllOutcome?> {
  @override
  DevSeedAllOutcome? build() => null;

  void publish(DevSeedAllOutcome outcome) => state = outcome;

  void clear() => state = null;
}

/// True while [DevSeedAllRunner] is running (suppresses bootstrap auto-redirect).
final devFullSeedInProgressProvider = NotifierProvider<DevFullSeedInProgressNotifier, bool>(
  DevFullSeedInProgressNotifier.new,
);

/// Outcome to show after seed completes when the initiating widget was unmounted (e.g. bootstrap redirect).
final devSeedAllFeedbackProvider = NotifierProvider<DevSeedAllFeedbackNotifier, DevSeedAllOutcome?>(
  DevSeedAllFeedbackNotifier.new,
);

final devSeedAllRunnerProvider = Provider<DevSeedAllRunner>((ref) => DevSeedAllRunner(ref));

/// Runs clinic bootstrap (when needed) then patients, doctors, and appointments in order.
///
/// Uses a [Ref] from [devSeedAllRunnerProvider] so the run survives widget disposal
/// (e.g. bootstrap page redirect after organization creation).
class DevSeedAllRunner {
  DevSeedAllRunner(this._ref);

  final Ref _ref;

  Future<DevSeedAllOutcome> run() async {
    final lines = <String>[];

    try {
      var auth = _ref.read(authSessionProvider).context;
      if (auth == null) {
        return const DevSeedAllOutcome(isSuccess: false, summaryLines: ['Not signed in.']);
      }

      if (auth.setupRequired) {
        AppLog.info('dev_seed_all.clinic_setup.start');
        final ok = await _ref.read(bootstrapNotifierProvider.notifier).finishSetupWithDummyData();
        if (!ok) {
          final message =
              _ref.read(bootstrapNotifierProvider).errorMessage ??
              'Dummy clinic setup failed. See logs for bootstrap.dev_dummy_fill.*';
          return DevSeedAllOutcome(isSuccess: false, summaryLines: [message]);
        }

        auth = await _waitForPostBootstrapAuth();
        if (auth == null) {
          return const DevSeedAllOutcome(
            isSuccess: false,
            summaryLines: ['Clinic setup finished but session context is not ready. Try again.'],
          );
        }
        if (auth.setupRequired) {
          return const DevSeedAllOutcome(
            isSuccess: false,
            summaryLines: [
              'Clinic setup finished but JWT claims are still in setup mode. '
                  'Sign out and sign in again, then retry seed.',
            ],
          );
        }
        if (auth.organizationId == null || auth.organizationId!.isEmpty || !auth.hasBranchAssignment) {
          return const DevSeedAllOutcome(
            isSuccess: false,
            summaryLines: [
              'Clinic setup finished but organization or branch claims are missing. '
                  'Sign out and sign in again, then retry seed.',
            ],
          );
        }

        lines.add('Demo organization and branch created.');
        AppLog.info('dev_seed_all.clinic_setup.done org=${auth.organizationId} branch=${auth.activeBranchId}');
      }

      AppLog.info('dev_seed_all.patients.start');
      final patientsOutcome = await _ref
          .read(patientDevSeedServiceProvider)
          .seed(auth, reloadAuthContext: () => _ref.read(authSessionProvider.notifier).reloadContext());
      if (!patientsOutcome.isSuccess) {
        return DevSeedAllOutcome(isSuccess: false, summaryLines: [...lines, patientsOutcome.errorMessage!]);
      }
      if (patientsOutcome.skippedBecauseAlreadySeeded) {
        lines.add('Patients: skipped (already seeded).');
      } else {
        final branchNote = patientsOutcome.otherBranchName != null
            ? ' Second branch: ${patientsOutcome.otherBranchName}.'
            : '';
        lines.add('Patients: created ${patientsOutcome.created} (${patientsOutcome.archived} archived).$branchNote');
      }

      _ref.invalidate(patientListProvider);
      _ref.invalidate(staffAssignableBranchesProvider);

      auth = _ref.read(authSessionProvider).context;
      if (auth == null) {
        return DevSeedAllOutcome(isSuccess: false, summaryLines: [...lines, 'Session lost after patient seed.']);
      }

      AppLog.info('dev_seed_all.doctors.start');
      final doctorsOutcome = await _ref.read(doctorDevSeedServiceProvider).seed(auth);
      if (!doctorsOutcome.isSuccess) {
        return DevSeedAllOutcome(isSuccess: false, summaryLines: [...lines, doctorsOutcome.errorMessage!]);
      }
      if (doctorsOutcome.skippedBecauseAlreadySeeded) {
        lines.add('Doctors: skipped (already seeded).');
      } else {
        lines.add('Doctors: created ${doctorsOutcome.created} (password: ${DoctorDevSeedData.defaultPassword}).');
      }

      auth = _ref.read(authSessionProvider).context;
      final branchId = auth?.activeBranchId;
      final organizationId = auth?.organizationId;
      if (branchId == null || branchId.isEmpty) {
        return DevSeedAllOutcome(
          isSuccess: false,
          summaryLines: [...lines, 'Select an active branch before seeding appointments.'],
        );
      }
      if (organizationId == null || organizationId.isEmpty) {
        return DevSeedAllOutcome(
          isSuccess: false,
          summaryLines: [...lines, 'Organization context is missing. Sign in again.'],
        );
      }

      AppLog.info('dev_seed_all.appointments.start branch=$branchId');
      final appointmentsOutcome = await _ref
          .read(appointmentDevSeedServiceProvider)
          .seed(branchId: branchId, organizationId: organizationId);
      if (!appointmentsOutcome.isSuccess) {
        return DevSeedAllOutcome(isSuccess: false, summaryLines: [...lines, appointmentsOutcome.errorMessage!]);
      }
      lines.add('Appointments: created ${appointmentsOutcome.plannedCreated} planned.');

      AppLog.info('dev_seed_all.done');
      return DevSeedAllOutcome(isSuccess: true, summaryLines: lines);
    } catch (error, stack) {
      AppLog.warning('dev_seed_all.unexpected_failure reason=${error.runtimeType}');
      AppLog.fine('dev_seed_all.stack $stack');
      return DevSeedAllOutcome(isSuccess: false, summaryLines: ['Dev seed failed unexpectedly: $error']);
    }
  }

  /// Refreshes JWT/session until org + branch claims are present after bootstrap RPCs.
  Future<AuthSessionContext?> _waitForPostBootstrapAuth() async {
    const maxAttempts = 6;
    AuthSessionContext? last;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await _ref.read(authSessionProvider.notifier).refreshSessionContext();
      last = _ref.read(authSessionProvider).context;
      if (last != null &&
          !last.setupRequired &&
          last.organizationId != null &&
          last.organizationId!.isNotEmpty &&
          last.hasBranchAssignment) {
        return last;
      }
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    return last;
  }
}
