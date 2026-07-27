import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/dev/dev_doctor_seed_data.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/setup/data/provisioning_repository.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';

class DevDoctorSeedOutcome {
  const DevDoctorSeedOutcome({required this.created, required this.skippedBecauseAlreadySeeded, this.errorMessage});

  final int created;
  final bool skippedBecauseAlreadySeeded;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

/// Creates demo doctor accounts for local debugging and UI testing.
class DevDoctorSeedService {
  DevDoctorSeedService({required StaffAdminRepository staffAdmin, required ProvisioningRepository provisioning})
    : _staffAdmin = staffAdmin,
      _provisioning = provisioning;

  final StaffAdminRepository _staffAdmin;
  final ProvisioningRepository _provisioning;

  Future<DevDoctorSeedOutcome> seed(AuthSessionContext auth) async {
    if (!kDebugMode) {
      return const DevDoctorSeedOutcome(
        created: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: 'Dev seeding is disabled in release builds.',
      );
    }

    final branchId = auth.activeBranchId ?? auth.branchIds.firstOrNull;
    if (branchId == null || branchId.isEmpty) {
      return const DevDoctorSeedOutcome(
        created: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: 'Select an active branch before seeding doctors.',
      );
    }

    try {
      final existing = await _staffAdmin.listStaff(filter: StaffListFilter.all);
      final hasDevDoctors = existing.any(
        (staff) =>
            staff.role == StaffRole.doctor &&
            staff.fullName.trim().toLowerCase().startsWith(DevDoctorSeedSpec.devNamePrefix.trim().toLowerCase()),
      );
      if (hasDevDoctors) {
        AppLog.info('dev.seed_doctors.skip_already_present');
        return const DevDoctorSeedOutcome(created: 0, skippedBecauseAlreadySeeded: true);
      }

      var created = 0;
      for (final spec in DevDoctorSeedData.doctors) {
        await _provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: spec.username,
            password: DevDoctorSeedData.defaultPassword,
            fullName: spec.fullName,
            role: StaffRole.doctor,
            branchIds: [branchId],
            primaryBranchId: branchId,
          ),
        );
        created++;
      }
      AppLog.info('dev.seed_doctors.done created=$created');
      return DevDoctorSeedOutcome(created: created, skippedBecauseAlreadySeeded: false);
    } on RpcFailure catch (error) {
      AppLog.warning('dev.seed_doctors.rpc_failed code=${error.code}');
      return DevDoctorSeedOutcome(
        created: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: error.result.errorMessage ?? 'Doctor seed failed (${error.code}).',
      );
    } catch (error, stack) {
      AppLog.warning('dev.seed_doctors.failed reason=${error.runtimeType}');
      AppLog.fine('dev.seed_doctors.stack $stack');
      return DevDoctorSeedOutcome(
        created: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: 'Doctor seed failed: $error',
      );
    }
  }
}

final devDoctorSeedServiceProvider = Provider<DevDoctorSeedService?>((ref) {
  if (!kDebugMode) {
    return null;
  }

  return DevDoctorSeedService(
    staffAdmin: ref.watch(staffAdminRepositoryProvider),
    provisioning: ref.watch(provisioningRepositoryProvider),
  );
});
