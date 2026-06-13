import 'package:ai_clinic/features/setup/domain/admin_update_staff_username_result.dart';
import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';

class UpdateStaffUsername {
  const UpdateStaffUsername(this._repository);
  final ProvisioningRepository _repository;

  Future<AdminUpdateStaffUsernameResult> call({
    required String staffMemberId,
    required String newUsername,
  }) {
    return _repository.updateStaffUsername(staffMemberId: staffMemberId, newUsername: newUsername);
  }
}
