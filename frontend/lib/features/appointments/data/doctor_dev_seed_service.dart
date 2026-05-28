import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/domain/doctor_dev_seed_data.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/auth/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';

class DoctorDevSeedOutcome {
  const DoctorDevSeedOutcome({required this.created, required this.skippedBecauseAlreadySeeded, this.errorMessage});

  final int created;
  final bool skippedBecauseAlreadySeeded;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

/// Creates demo doctor accounts for local debugging and UI testing.
class DoctorDevSeedService {
  DoctorDevSeedService({required StaffAdminRepository staffAdmin, required ProvisioningRepository provisioning})
    : _staffAdmin = staffAdmin,
      _provisioning = provisioning;

  final StaffAdminRepository _staffAdmin;
  final ProvisioningRepository _provisioning;

  Future<DoctorDevSeedOutcome> seed(AuthSessionContext auth) async {
    final branchId = auth.activeBranchId ?? auth.branchIds.firstOrNull;
    if (branchId == null || branchId.isEmpty) {
      return const DoctorDevSeedOutcome(
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
            staff.fullName.trim().toLowerCase().startsWith(DoctorDevSeedSpec.devNamePrefix.trim().toLowerCase()),
      );
      if (hasDevDoctors) {
        AppLog.info('appointments.dev_seed_doctors.skip_already_present');
        return const DoctorDevSeedOutcome(created: 0, skippedBecauseAlreadySeeded: true);
      }

      var created = 0;
      for (final spec in DoctorDevSeedData.doctors) {
        await _provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: spec.username,
            password: DoctorDevSeedData.defaultPassword,
            fullName: spec.fullName,
            role: StaffRole.doctor,
            branchIds: [branchId],
            primaryBranchId: branchId,
          ),
        );
        created++;
      }
      AppLog.info('appointments.dev_seed_doctors.done created=$created');
      return DoctorDevSeedOutcome(created: created, skippedBecauseAlreadySeeded: false);
    } on RpcFailure catch (error) {
      AppLog.warning('appointments.dev_seed_doctors.rpc_failed code=${error.code}');
      return DoctorDevSeedOutcome(
        created: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: error.result.errorMessage ?? 'Doctor seed failed (${error.code}).',
      );
    } catch (error, stack) {
      AppLog.warning('appointments.dev_seed_doctors.failed reason=${error.runtimeType}');
      AppLog.fine('appointments.dev_seed_doctors.stack $stack');
      return DoctorDevSeedOutcome(
        created: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: 'Doctor seed failed: $error',
      );
    }
  }
}
