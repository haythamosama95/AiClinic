import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_service.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/setup/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/setup/data/provisioning_repository.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';

@immutable
class DevClinicSeedState {
  const DevClinicSeedState({this.inProgress = false, this.progressMessage, this.errorMessage});

  final bool inProgress;
  final String? progressMessage;
  final String? errorMessage;

  DevClinicSeedState copyWith({
    bool? inProgress,
    String? progressMessage,
    String? errorMessage,
    bool clearError = false,
    bool clearProgress = false,
  }) {
    return DevClinicSeedState(
      inProgress: inProgress ?? this.inProgress,
      progressMessage: clearProgress ? null : (progressMessage ?? this.progressMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final devClinicSeedServiceProvider = Provider<DevClinicSeedService>((ref) {
  return DevClinicSeedService(
    bootstrap: ref.watch(bootstrapRepositoryProvider),
    branches: ref.watch(branchRepositoryProvider),
    provisioning: ref.watch(provisioningRepositoryProvider),
    staffAdmin: ref.watch(staffAdminRepositoryProvider),
    patients: ref.watch(patientRepositoryProvider),
    appointments: ref.watch(appointmentRepositoryProvider),
    visits: ref.watch(visitRepositoryProvider),
  );
});

final devClinicSeedProvider = NotifierProvider<DevClinicSeedNotifier, DevClinicSeedState>(DevClinicSeedNotifier.new);

class DevClinicSeedNotifier extends Notifier<DevClinicSeedState> {
  @override
  DevClinicSeedState build() => const DevClinicSeedState();

  Future<bool> fillDummyClinic() async {
    if (!kDebugMode) {
      return false;
    }

    final auth = ref.read(authSessionProvider).context;
    if (auth == null) {
      state = state.copyWith(errorMessage: 'Sign in before filling dummy clinic data.');
      return false;
    }

    if (!auth.staffProfile.isBootstrapAdmin) {
      state = state.copyWith(errorMessage: 'Only the bootstrap administrator can fill dummy clinic data.');
      return false;
    }

    state = state.copyWith(inProgress: true, clearError: true, progressMessage: 'Preparing…');
    AppLog.info('dev_clinic_seed.start');

    try {
      await ref
          .read(devClinicSeedServiceProvider)
          .run(
            auth: auth,
            refreshSession: () => ref.read(authSessionProvider.notifier).refreshSessionContext(),
            onProgress: (message) {
              state = state.copyWith(progressMessage: message);
            },
          );

      ref.read(setupNotifierProvider.notifier).markSetupComplete();
      state = const DevClinicSeedState();
      AppLog.info('dev_clinic_seed.completed');
      return true;
    } on RpcFailure catch (error) {
      AppLog.warning('dev_clinic_seed.rpc_failed code=${error.code}');
      state = DevClinicSeedState(
        inProgress: false,
        errorMessage: error.result.errorMessage ?? setupMessageForRpc(error),
      );
      return false;
    } catch (error, stack) {
      AppLog.warning('dev_clinic_seed.failed reason=${error.runtimeType}');
      AppLog.fine('dev_clinic_seed.stack $stack');
      state = DevClinicSeedState(
        inProgress: false,
        errorMessage: error is StateError ? error.message : 'Unable to fill dummy clinic data. Try again.',
      );
      return false;
    }
  }
}
